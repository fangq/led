// led - a lightweight editor.  Running notebook cells in a real kernel.
//
// LED does not implement Jupyter's wire protocol.  A kernel is reached over
// ZeroMQ with signed messages on five sockets, jupyter_client already does
// all of that correctly, and it is installed wherever the kernels are -- so
// LED drives a small Python helper that speaks it, the same way it drives gdb
// over its Machine Interface: a subprocess, a line protocol, and a poll that
// never blocks the editor.  One JSON object per line in each direction.
//
// What that buys, besides not writing a ZeroMQ binding: every kernel the
// reader has installed works, because none of them is special-cased here;
// and the magics work.  %%octave, %matplotlib inline, !pip install -- those
// belong to IPython, inside the kernel, and an editor that sends a cell's
// text as the cell's text gets them without knowing they exist.
//
// The outputs arrive already in nbformat's shape, built by the helper, which
// is the side with nbformat's own definition of it to hand.  This unit hands
// them to the document, which appends them to the cell.

unit Led.Core.Kernel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, fpjson,
  Led.Core.LineSplit, Led.Core.NBFormat, Led.Core.Paths, Led.Core.Prefs;

type
  TLedKernelState = (
    lksOff,        // nothing running
    lksStarting,   // the helper is up, the kernel is not ready yet
    lksIdle,       // ready and waiting
    lksBusy,       // running a cell
    lksFailed);    // it will not run; LastError says why

  TLedKernelEventKind = (
    lkeReady,      // the kernel is up; Language is what it speaks
    lkeStatus,     // busy or idle
    lkeOutput,     // one nbformat output object for the run Id
    lkeDone,       // the run Id finished; Status is 'ok' or 'error'
    lkeFailed);    // it is not going to work; Message says why

  TLedKernelEvent = record
    Kind: TLedKernelEventKind;
    Id: Integer;           // which run this belongs to
    Status: string;        // done: ok|error.  status: busy|idle
    Count: Integer;        // the execution count, or -1 if none was given
    Language: string;
    Message: string;
    { For lkeOutput: the output object, still owned by the event's parser.
      A caller that wants to keep it clones it. }
    Output: TJSONObject;
  end;

  TLedKernelEventProc = procedure(Sender: TObject;
    const AEvent: TLedKernelEvent) of object;

{ One line from the helper as an event.  False when the line is not one --
  a warning the helper's Python printed, say -- and then AError says so
  rather than the line being taken for an event with everything missing. }
function LedKernelParseEvent(const ALine: string; out AEvent: TLedKernelEvent;
  out AError: string): Boolean;

{ The commands, built here so their shape lives in one place beside the
  parser for the answers. }
function LedKernelRunCommand(AId: Integer; const ACode: string): string;
function LedKernelCommand(const AWhat: string): string;

{ Where the helper is, and the Python to run it with.  The second is a
  preference because a machine can have several and only one of them has
  jupyter_client in it. }
function LedKernelHelper: string;
function LedKernelPython: string;

const
  LedPrefKernelPython = 'Notebook/python';

type
  TLedKernel = class
  private
    FProcess: TProcess;
    FState: TLedKernelState;
    FLastError: string;
    FLanguage: string;
    FKernelName: string;
    FSplit: TLedLineSplitter;  // holds a partial line until its newline
    FNextId: Integer;
    FOnEvent: TLedKernelEventProc;
    procedure Send(const ALine: string);
    procedure Dispatch(const AEvent: TLedKernelEvent);
    procedure SetFailed(const AWhy: string);
  public
    constructor Create;
    destructor Destroy; override;

    { Starts the helper for a kernel by name -- 'python3', 'octave'.  True
      means the helper is running, not that the kernel is ready: that comes
      as lkeReady, because starting one takes a second or two and the editor
      must not stop for it. }
    function Start(const AKernelName: string; out AWhy: string): Boolean;
    { Sends a cell.  Returns the run id that its events will carry, or -1
      when there is nothing running to send it to. }
    function Run(const ACode: string): Integer;
    procedure Interrupt;
    procedure Restart;
    procedure Shutdown;

    { Reads whatever the helper has said and turns it into events.  Called
      from a timer; it never waits. }
    function Poll: Boolean;

    function Running: Boolean;
    property State: TLedKernelState read FState;
    property LastError: string read FLastError;
    property Language: string read FLanguage;
    property KernelName: string read FKernelName;
    property OnEvent: TLedKernelEventProc read FOnEvent write FOnEvent;
  end;

implementation

function LedKernelHelper: string;
begin
  { Its own directory: data/tools holds the external-tool definitions the
    tool runner reads, and a Python script is not one of those. }
  Result := LedDataFile('kernel' + PathDelim + 'ledkernel.py');
end;

function LedKernelPython: string;
begin
  Result := LedPrefs.GetStr(LedPrefKernelPython, 'python3');
  if Trim(Result) = '' then Result := 'python3';
end;

function LedKernelCommand(const AWhat: string): string;
begin
  Result := '{"cmd": ' + LedNBJSONString(AWhat) + '}';
end;

function LedKernelRunCommand(AId: Integer; const ACode: string): string;
begin
  { One line, whatever the code is: the string escape turns every newline in
    it into two characters, which is the whole reason the protocol can be
    line-based at all. }
  Result := Format('{"cmd": "run", "id": %d, "code": %s}',
    [AId, LedNBJSONString(ACode)]);
end;

function LedKernelParseEvent(const ALine: string; out AEvent: TLedKernelEvent;
  out AError: string): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  What: TJSONData;
  Named: string;      // the event's name, kept out of the object it came from

  function Str(const AKey: string): string;
  var
    V: TJSONData;
  begin
    Result := '';
    V := Obj.Find(AKey);
    if (V <> nil) and (V.JSONType = jtString) then Result := V.AsString;
  end;

  function Num(const AKey: string; ADefault: Integer): Integer;
  var
    V: TJSONData;
  begin
    Result := ADefault;
    V := Obj.Find(AKey);
    if (V <> nil) and (V.JSONType = jtNumber) then Result := V.AsInteger;
  end;

begin
  Result := False;
  AError := '';
  FillChar(AEvent, SizeOf(AEvent), 0);
  AEvent.Count := -1;

  if Trim(ALine) = '' then
  begin
    AError := 'the line is empty';
    Exit;
  end;

  Data := LedNBParseJSON(ALine, AError);
  if Data = nil then Exit;

  if Data.JSONType <> jtObject then
  begin
    Data.Free;
    AError := 'the line is not a JSON object';
    Exit;
  end;

  Obj := TJSONObject(Data);
  What := Obj.Find('ev');
  if (What = nil) or (What.JSONType <> jtString) then
  begin
    Obj.Free;
    AError := 'the line does not say which event it is';
    Exit;
  end;
  { Copied out before anything frees the object: the name is wanted again in
    the message for an event nothing here knows, and reading it back out of a
    freed object is how that message came to be an access violation. }
  Named := What.AsString;

  case Named of
    'ready':
      begin
        AEvent.Kind := lkeReady;
        AEvent.Language := Str('language');
      end;
    'status':
      begin
        AEvent.Kind := lkeStatus;
        AEvent.Status := Str('state');
      end;
    'output':
      begin
        AEvent.Kind := lkeOutput;
        AEvent.Id := Num('id', 0);
        if (Obj.Find('output') <> nil) and
           (Obj.Find('output').JSONType = jtObject) then
          { Taken out of its parent rather than pointed at inside it: the
            caller frees what it is given, and freeing a child while the
            object that owns it is still alive frees it twice. }
          AEvent.Output :=
            TJSONObject(Obj.Extract(Obj.IndexOfName('output')))
        else
        begin
          Obj.Free;
          AError := 'an output event carries no output';
          Exit;
        end;
      end;
    'done':
      begin
        AEvent.Kind := lkeDone;
        AEvent.Id := Num('id', 0);
        AEvent.Status := Str('status');
        AEvent.Count := Num('count', -1);
      end;
    'failed':
      begin
        AEvent.Kind := lkeFailed;
        AEvent.Message := Str('msg');
      end;
  else
    Obj.Free;
    AError := Format('"%s" is not an event this knows', [Named]);
    Exit;
  end;

  { The line itself is done with either way; what an output event leaves
    behind is the output object, which the caller owns and frees. }
  Obj.Free;
  Result := True;
end;

{ ---- the process ---- }

constructor TLedKernel.Create;
begin
  inherited Create;
  FSplit := TLedLineSplitter.Create;
  FState := lksOff;
  FNextId := 0;
end;

destructor TLedKernel.Destroy;
begin
  Shutdown;
  FProcess.Free;
  FSplit.Free;
  inherited Destroy;
end;

function TLedKernel.Running: Boolean;
begin
  Result := (FProcess <> nil) and FProcess.Running;
end;

procedure TLedKernel.SetFailed(const AWhy: string);
var
  Ev: TLedKernelEvent;
begin
  FState := lksFailed;
  FLastError := AWhy;
  FillChar(Ev, SizeOf(Ev), 0);
  Ev.Kind := lkeFailed;
  Ev.Count := -1;
  Ev.Message := AWhy;
  Dispatch(Ev);
end;

function TLedKernel.Start(const AKernelName: string; out AWhy: string): Boolean;
var
  Helper: string;
begin
  Result := False;
  AWhy := '';
  Shutdown;

  Helper := LedKernelHelper;
  if not FileExists(Helper) then
  begin
    AWhy := Format('the kernel helper is missing (%s)', [Helper]);
    FState := lksFailed;
    FLastError := AWhy;
    Exit;
  end;

  FreeAndNil(FProcess);
  FProcess := TProcess.Create(nil);
  FProcess.Executable := LedKernelPython;
  FProcess.Parameters.Add(Helper);
  FProcess.Parameters.Add(AKernelName);
  { Not poStderrToOutput: the helper's stdout is a protocol, and a warning
    printed by somebody's sitecustomize.py would arrive in the middle of it. }
  FProcess.Options := [poUsePipes, poNoConsole];
  try
    FProcess.Execute;
  except
    on E: Exception do
    begin
      AWhy := Format('%s would not run (%s)', [LedKernelPython, E.Message]);
      FreeAndNil(FProcess);
      FState := lksFailed;
      FLastError := AWhy;
      Exit;
    end;
  end;

  FKernelName := AKernelName;
  FSplit.Reset;
  FLanguage := '';
  FLastError := '';
  FState := lksStarting;
  Result := True;
end;

procedure TLedKernel.Send(const ALine: string);
var
  Line: string;
begin
  if not Running then Exit;
  Line := ALine + #10;
  try
    FProcess.Input.Write(Line[1], Length(Line));
  except
    on E: Exception do
      SetFailed('the kernel helper stopped listening (' + E.Message + ')');
  end;
end;

function TLedKernel.Run(const ACode: string): Integer;
begin
  Result := -1;
  if not Running then Exit;
  Inc(FNextId);
  Result := FNextId;
  FState := lksBusy;
  Send(LedKernelRunCommand(Result, ACode));
end;

procedure TLedKernel.Interrupt;
begin
  Send(LedKernelCommand('interrupt'));
end;

procedure TLedKernel.Restart;
begin
  if not Running then Exit;
  FState := lksStarting;
  Send(LedKernelCommand('restart'));
end;

procedure TLedKernel.Shutdown;
begin
  if FProcess = nil then Exit;
  if FProcess.Running then
  begin
    Send(LedKernelCommand('shutdown'));
    { A moment to go quietly, then not.  A kernel that will not shut down
      cleanly is not worth holding the editor's exit for. }
    if not FProcess.WaitOnExit(1500) then
      FProcess.Terminate(0);
  end;
  FreeAndNil(FProcess);
  FState := lksOff;
end;

procedure TLedKernel.Dispatch(const AEvent: TLedKernelEvent);
begin
  if Assigned(FOnEvent) then FOnEvent(Self, AEvent);
end;

function TLedKernel.Poll: Boolean;
var
  Buf: array[0..16383] of Char;
  N: Integer;
  Chunk, Line, Err: string;
  Ev: TLedKernelEvent;
begin
  Result := False;
  if FProcess = nil then Exit;

  while (FProcess.Output <> nil) and (FProcess.Output.NumBytesAvailable > 0) do
  begin
    N := FProcess.Output.Read(Buf, SizeOf(Buf));
    if N <= 0 then Break;
    SetString(Chunk, Buf, N);
    { An event is a line, and a read can end in the middle of one: the tail
      waits for its newline rather than being parsed as half an event.  The
      splitter is where that is written down, and where it is tested -- this
      used to be twenty lines here and twenty more in Led.Core.Gdb, neither
      of them reachable by a check without a subprocess to hand. }
    FSplit.Feed(Chunk);
    Result := True;
  end;

  while FSplit.Next(Line) do
  begin
    if Trim(Line) = '' then Continue;
    if not LedKernelParseEvent(Line, Ev, Err) then Continue;
    try
      case Ev.Kind of
        lkeReady:
          begin
            FLanguage := Ev.Language;
            FState := lksIdle;
          end;
        lkeStatus:
          if Ev.Status = 'idle' then FState := lksIdle
          else if Ev.Status = 'busy' then FState := lksBusy;
        lkeFailed:
          begin
            FState := lksFailed;
            FLastError := Ev.Message;
          end;
        lkeDone:
          FState := lksIdle;
      end;
      Dispatch(Ev);
    finally
      { The parser hands ownership of an output event's object over; the
        document has taken what it wanted from it by now. }
      if Ev.Kind = lkeOutput then Ev.Output.Free;
    end;
  end;

  { The helper going away is a state change the window has to show. }
  if (FProcess <> nil) and (not FProcess.Running) and
     (FState <> lksOff) and (FState <> lksFailed) then
  begin
    if FLastError = '' then FLastError := 'the kernel stopped';
    FState := lksFailed;
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.Kind := lkeFailed;
    Ev.Count := -1;
    Ev.Message := FLastError;
    Dispatch(Ev);
  end;
end;

end.
