{ led - a light editor.  A gdb subprocess, driven over its machine interface.

  One session is one `gdb --interpreter=mi3` child.  It owns the pipe, tags
  every command with a token so replies can be matched to what asked for them,
  keeps the state machine, and hands finished answers to whoever is listening.
  It draws nothing.

  Why this is in ledcore, when the tool runner it resembles is not: the
  reading is driven by an explicit Poll rather than by a timer this unit
  owns.  The editor calls Poll from a TTimer; the headless suite calls it in a
  loop.  That one decision is what lets the whole session layer -- spawning,
  tokens, dispatch, breakpoints, stack, locals -- be tested against a real gdb
  with no window, which is where every interesting bug in it will be.

  Polling rather than waiting on the child, for the reason Led.UI.ToolRunner
  gives: the editor is driven by Application.ProcessMessages under the
  self-test rather than by Application.Run, and the async-process callbacks
  are not reliably serviced there.  A poll costs nothing and always works.

  Two quoting rules that are not interchangeable, both learned from medit's
  plugin and both easy to get backwards:

    * -file-exec-and-symbols and -environment-cd take an MI c-string, so a
      path is wrapped in double quotes with the usual escapes.  Shell quoting
      is wrong: gdb would take the quotes as part of the filename.

    * -break-insert takes its location *unquoted*, because gdb echoes it back
      in original-location= and a quoted location comes back quoted, so the
      breakpoint can never be matched to the line that asked for it. }
unit Led.Core.Gdb;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, Led.Core.GdbMI;

type
  TLedGdbState = (lgsIdle, lgsLoading, lgsReady, lgsRunning, lgsStopped,
                  lgsExited, lgsError);

  { What a reply is an answer to.  A token is matched to one of these rather
    than to a closure, because Pascal makes an array of records much easier to
    reason about than an array of anonymous methods -- and every request led
    makes is one of a fixed handful. }
  TLedGdbRequest = (lgrNone, lgrVersion, lgrBreakInsert, lgrBreakDelete,
                    lgrLocals, lgrFrames, lgrEval, lgrExec);

  TLedGdbLocal = record
    Name: string;
    TypeName: string;
    Value: string;
  end;
  TLedGdbLocals = array of TLedGdbLocal;

  TLedGdbFrame = record
    Level: Integer;
    Func: string;
    FileName: string;
    Line: Integer;
    Addr: string;
  end;
  TLedGdbFrames = array of TLedGdbFrame;

  TLedGdbTextEvent = procedure(Sender: TObject; const AText: string) of object;
  TLedGdbStopEvent = procedure(Sender: TObject;
    const AReason, AFileName: string; ALine: Integer; const AFunc: string) of object;
  TLedGdbBreakEvent = procedure(Sender: TObject; ANumber: Integer;
    const AFileName: string; ALine: Integer) of object;
  TLedGdbEvalEvent = procedure(Sender: TObject; const ATag, AValue: string;
    AIsError: Boolean) of object;
  TLedGdbNotify = procedure(Sender: TObject) of object;

  TLedGdbSession = class
  private
    FProcess: TProcess;
    FState: TLedGdbState;
    FPending: string;                 // partial trailing line from the pipe
    FToken: Integer;
    FVersion: string;
    FInferiorAlive: Boolean;
    FLastError: string;

    { token -> what it was asking, and a caller-supplied tag (an expression,
      or "file:line") that the reply alone would not carry. }
    FPendTokens: array of Integer;
    FPendKinds: array of TLedGdbRequest;
    FPendTags: array of string;

    FLocals: TLedGdbLocals;
    FFrames: TLedGdbFrames;

    FOnConsole: TLedGdbTextEvent;
    FOnTarget: TLedGdbTextEvent;
    FOnLog: TLedGdbTextEvent;
    FOnError: TLedGdbTextEvent;
    FOnStopped: TLedGdbStopEvent;
    FOnRunning: TLedGdbNotify;
    FOnStateChanged: TLedGdbNotify;
    FOnBreakAdded: TLedGdbBreakEvent;
    FOnBreakRemoved: TLedGdbBreakEvent;
    FOnLocals: TLedGdbNotify;
    FOnFrames: TLedGdbNotify;
    FOnEval: TLedGdbEvalEvent;
    FOnExited: TLedGdbNotify;

    procedure SetState(AValue: TLedGdbState);
    function NextToken(AKind: TLedGdbRequest; const ATag: string): Integer;
    function TakePending(AToken: Integer; out AKind: TLedGdbRequest;
      out ATag: string): Boolean;
    procedure Dispatch(ARec: TLedMIRecord);
    procedure HandleResult(ARec: TLedMIRecord);
    procedure HandleExec(ARec: TLedMIRecord);
    procedure HandleNotify(ARec: TLedMIRecord);
    procedure ReadLocals(ARec: TLedMIRecord);
    procedure ReadFrames(ARec: TLedMIRecord);
    procedure EmitBreakpoint(AValue: TLedMIValue);
    procedure Send(const ACommand: string; AKind: TLedGdbRequest = lgrNone;
      const ATag: string = '');
  public
    constructor Create;
    destructor Destroy; override;

    { Spawns gdb.  False when it could not be started -- LastError says why,
      and the caller should say so rather than leaving a dead pane. }
    function Start(const AGdbPath: string = 'gdb'): Boolean;
    procedure Quit;
    function Alive: Boolean;

    { Drains whatever gdb has said and dispatches it.  Safe to call when
      nothing is running.  Returns True when it handled at least one line,
      which is what a test loop waits on. }
    function Poll: Boolean;

    { Waits up to ATimeoutMs for the session to reach one of AStates, polling
      as it goes.  For the headless suite; the editor never blocks. }
    function WaitForState(AStates: array of TLedGdbState;
      ATimeoutMs: Integer = 10000): Boolean;

    { --- configuring the target --- }
    procedure SetTarget(const APath: string);
    procedure SetArguments(AArgs: TStrings);
    procedure SetWorkingDir(const ADir: string);
    procedure SetEnvironmentVar(const AName, AValue: string);

    { --- execution --- }
    procedure ExecRun;
    procedure ExecContinue;
    procedure ExecNext;      // step over
    procedure ExecStep;      // step into
    procedure ExecFinish;    // step out
    procedure ExecInterrupt; // pause

    { --- breakpoints --- }
    procedure BreakInsert(const AFileName: string; ALine: Integer);
    procedure BreakDelete(ANumber: Integer);

    { --- inspection --- }
    procedure RequestLocals;
    procedure RequestFrames;
    procedure SelectFrame(ALevel: Integer);
    { The answer arrives on OnEval carrying ATag, so one handler can serve
      watches and hover without keeping a queue of its own. }
    procedure Evaluate(const AExpression, ATag: string);

    procedure SendRaw(const ACommand: string);

    property State: TLedGdbState read FState;
    property InferiorAlive: Boolean read FInferiorAlive;
    property Version: string read FVersion;
    property LastError: string read FLastError;
    property Locals: TLedGdbLocals read FLocals;
    property Frames: TLedGdbFrames read FFrames;

    property OnConsole: TLedGdbTextEvent read FOnConsole write FOnConsole;
    property OnTarget: TLedGdbTextEvent read FOnTarget write FOnTarget;
    property OnLog: TLedGdbTextEvent read FOnLog write FOnLog;
    property OnError: TLedGdbTextEvent read FOnError write FOnError;
    property OnStopped: TLedGdbStopEvent read FOnStopped write FOnStopped;
    property OnRunning: TLedGdbNotify read FOnRunning write FOnRunning;
    property OnStateChanged: TLedGdbNotify read FOnStateChanged write FOnStateChanged;
    property OnBreakAdded: TLedGdbBreakEvent read FOnBreakAdded write FOnBreakAdded;
    property OnBreakRemoved: TLedGdbBreakEvent read FOnBreakRemoved write FOnBreakRemoved;
    property OnLocals: TLedGdbNotify read FOnLocals write FOnLocals;
    property OnFrames: TLedGdbNotify read FOnFrames write FOnFrames;
    property OnEval: TLedGdbEvalEvent read FOnEval write FOnEval;
    property OnExited: TLedGdbNotify read FOnExited write FOnExited;
  end;

{ True when a gdb that speaks mi3 can be found.  The pane greys itself out
  rather than failing at the first click. }
function LedGdbAvailable(const AGdbPath: string = 'gdb'): Boolean;

implementation

uses
  FileUtil, LazFileUtils;

var
  { Probed once; the answer cannot change while the editor runs, and the
    probe costs a process. }
  FGdbProbed: Boolean = False;
  FGdbFound: Boolean = False;

function LedGdbAvailable(const AGdbPath: string): Boolean;
begin
  if FGdbProbed then Exit(FGdbFound);
  FGdbProbed := True;
  FGdbFound := (AGdbPath <> '') and
               ((FileExists(AGdbPath) and FileIsExecutable(AGdbPath)) or
                (FindDefaultExecutablePath(AGdbPath) <> ''));
  Result := FGdbFound;
end;

{ --- lifecycle ------------------------------------------------------------- }

constructor TLedGdbSession.Create;
begin
  inherited Create;
  FState := lgsIdle;
  FToken := 0;
end;

destructor TLedGdbSession.Destroy;
begin
  Quit;
  FProcess.Free;
  inherited Destroy;
end;

function TLedGdbSession.Alive: Boolean;
begin
  Result := (FProcess <> nil) and FProcess.Running;
end;

procedure TLedGdbSession.SetState(AValue: TLedGdbState);
begin
  if FState = AValue then Exit;
  FState := AValue;
  if Assigned(FOnStateChanged) then FOnStateChanged(Self);
end;

function TLedGdbSession.Start(const AGdbPath: string): Boolean;
begin
  Result := False;
  FLastError := '';
  if Alive then Exit(True);

  FreeAndNil(FProcess);
  FProcess := TProcess.Create(nil);
  FProcess.Executable := AGdbPath;
  { -nx so a personal .gdbinit cannot change the protocol under us, --quiet
    so the banner does not arrive as a dozen unknown records. }
  FProcess.Parameters.Add('--interpreter=mi3');
  FProcess.Parameters.Add('-nx');
  FProcess.Parameters.Add('--quiet');
  FProcess.Options := [poUsePipes, poStderrToOutPut, poNoConsole];

  try
    FProcess.Execute;
  except
    on E: Exception do
    begin
      FLastError := 'could not start ' + AGdbPath + ': ' + E.Message;
      FreeAndNil(FProcess);
      SetState(lgsError);
      Exit;
    end;
  end;

  FPending := '';
  FInferiorAlive := False;
  SetState(lgsLoading);
  { Proves the pipe works and gives us a version to show. }
  Send('-gdb-version', lgrVersion);
  Result := True;
end;

procedure TLedGdbSession.Quit;
begin
  if FProcess = nil then Exit;
  if FProcess.Running then
  begin
    try
      Send('-gdb-exit');
      { gdb goes away on its own after -gdb-exit; give it a moment, then
        insist.  Terminate on a process that has already gone is harmless. }
      Sleep(60);
      Poll;
      if FProcess.Running then FProcess.Terminate(0);
    except
      { A pipe that has already closed raises on write.  Nothing to do. }
    end;
  end;
  SetState(lgsExited);
end;

{ --- writing --------------------------------------------------------------- }

function TLedGdbSession.NextToken(AKind: TLedGdbRequest;
  const ATag: string): Integer;
var
  n: Integer;
begin
  Inc(FToken);
  Result := FToken;
  if AKind = lgrNone then Exit;
  n := Length(FPendTokens);
  SetLength(FPendTokens, n + 1);
  SetLength(FPendKinds, n + 1);
  SetLength(FPendTags, n + 1);
  FPendTokens[n] := Result;
  FPendKinds[n] := AKind;
  FPendTags[n] := ATag;
end;

function TLedGdbSession.TakePending(AToken: Integer;
  out AKind: TLedGdbRequest; out ATag: string): Boolean;
var
  i, j: Integer;
begin
  Result := False;
  AKind := lgrNone;
  ATag := '';
  for i := 0 to High(FPendTokens) do
    if FPendTokens[i] = AToken then
    begin
      AKind := FPendKinds[i];
      ATag := FPendTags[i];
      { Removed before the caller is told, so a handler may issue another
        command without tripping over its own entry. }
      for j := i to High(FPendTokens) - 1 do
      begin
        FPendTokens[j] := FPendTokens[j + 1];
        FPendKinds[j] := FPendKinds[j + 1];
        FPendTags[j] := FPendTags[j + 1];
      end;
      SetLength(FPendTokens, Length(FPendTokens) - 1);
      SetLength(FPendKinds, Length(FPendKinds) - 1);
      SetLength(FPendTags, Length(FPendTags) - 1);
      Exit(True);
    end;
end;

procedure TLedGdbSession.Send(const ACommand: string; AKind: TLedGdbRequest;
  const ATag: string);
var
  Line: string;
  Tok: Integer;
begin
  if not Alive then Exit;
  Tok := NextToken(AKind, ATag);
  Line := IntToStr(Tok) + ACommand + LineEnding;
  try
    FProcess.Input.Write(Line[1], Length(Line));
  except
    on E: Exception do
    begin
      FLastError := E.Message;
      SetState(lgsError);
    end;
  end;
end;

procedure TLedGdbSession.SendRaw(const ACommand: string);
begin
  Send(ACommand);
end;

{ --- reading --------------------------------------------------------------- }

function TLedGdbSession.Poll: Boolean;
var
  Buf: array[0..8191] of Char;
  N, i: Integer;
  Chunk, Line: string;
  Lines: TStringList;
  Rec: TLedMIRecord;
begin
  Result := False;
  if FProcess = nil then Exit;

  { Everything waiting, but no waiting: a poll must never block the editor. }
  while (FProcess.Output <> nil) and (FProcess.Output.NumBytesAvailable > 0) do
  begin
    N := FProcess.Output.Read(Buf, SizeOf(Buf));
    if N <= 0 then Break;
    SetString(Chunk, Buf, N);
    FPending := FPending + Chunk;
    Result := True;
  end;

  if FPending <> '' then
  begin
    Lines := TStringList.Create;
    try
      { A record is a line, and a read can end in the middle of one -- the
        tail is held back until its newline arrives, or half a *stopped
        would be parsed as garbage and the stop would be missed. }
      FPending := StringReplace(FPending, #13#10, #10, [rfReplaceAll]);
      Lines.StrictDelimiter := True;
      Lines.Delimiter := #10;
      Lines.DelimitedText := FPending;
      if (FPending <> '') and (FPending[Length(FPending)] = #10) then
        FPending := ''
      else if Lines.Count > 0 then
      begin
        FPending := Lines[Lines.Count - 1];
        Lines.Delete(Lines.Count - 1);
      end;

      for i := 0 to Lines.Count - 1 do
      begin
        Line := Lines[i];
        if Trim(Line) = '' then Continue;
        Rec := LedMIParse(Line);
        try
          Dispatch(Rec);
        finally
          Rec.Free;
        end;
      end;
    finally
      Lines.Free;
    end;
  end;

  { gdb itself going away is a state change the pane has to show. }
  if (FProcess <> nil) and (not FProcess.Running) and
     (FState <> lgsExited) and (FState <> lgsError) then
  begin
    FInferiorAlive := False;
    SetState(lgsExited);
    if Assigned(FOnExited) then FOnExited(Self);
  end;
end;

function TLedGdbSession.WaitForState(AStates: array of TLedGdbState;
  ATimeoutMs: Integer): Boolean;
var
  Waited, i: Integer;
begin
  Waited := 0;
  while Waited < ATimeoutMs do
  begin
    Poll;
    for i := 0 to High(AStates) do
      if FState = AStates[i] then Exit(True);
    Sleep(10);
    Inc(Waited, 10);
  end;
  Result := False;
end;

{ --- dispatch -------------------------------------------------------------- }

procedure TLedGdbSession.Dispatch(ARec: TLedMIRecord);
begin
  case ARec.Kind of
    mirResult:  HandleResult(ARec);
    mirExec:    HandleExec(ARec);
    mirNotify:  HandleNotify(ARec);
    mirConsole:
      begin
        { -gdb-version answers with console lines and a bare ^done -- there
          is no version= field to read, which the first version of this
          assumed.  The banner's first line is the version. }
        if (FVersion = '') and (Pos('GNU gdb', ARec.Text) > 0) then
          FVersion := Trim(ARec.Text);
        if Assigned(FOnConsole) then FOnConsole(Self, ARec.Text);
      end;
    mirTarget:  if Assigned(FOnTarget) then FOnTarget(Self, ARec.Text);
    mirLog:     if Assigned(FOnLog) then FOnLog(Self, ARec.Text);
    mirPrompt:
      if FState = lgsLoading then SetState(lgsReady);
    mirUnknown:
      { The debugged program's own output.  On a pipe the inferior inherits
        gdb's stdout and writes to it directly, so its text arrives as a bare
        line between the records rather than in an @ record -- checked
        against gdb 12.1, where `printf("total=5")` lands exactly here.
        Treating it as target output is what stops it disappearing. }
      if (ARec.Text <> '') and Assigned(FOnTarget) then
        FOnTarget(Self, ARec.Text + LineEnding);
  end;
end;

procedure TLedGdbSession.HandleResult(ARec: TLedMIRecord);
var
  Kind: TLedGdbRequest;
  Tag, Msg: string;
  Known: Boolean;
begin
  Known := TakePending(ARec.Token, Kind, Tag);

  if ARec.Class_ = 'error' then
  begin
    Msg := ARec.Results.Str('msg', 'gdb reported an error');
    { An evaluation that failed is an answer, not a fault: hovering over a
      name that is not in scope is the ordinary case, and posting it as a
      session error would fill the console with noise. }
    if Known and (Kind = lgrEval) then
    begin
      if Assigned(FOnEval) then FOnEval(Self, Tag, Msg, True);
      Exit;
    end;
    FLastError := Msg;
    if Assigned(FOnError) then FOnError(Self, Msg);
    Exit;
  end;

  if not Known then Exit;

  case Kind of
    lgrVersion:
      { Only as a fallback: gdb answers this on the console stream, and the
        console handler above has already taken it. }
      if FVersion = '' then
        FVersion := Trim(ARec.Results.Str('version', ''));
    lgrBreakInsert:
      EmitBreakpoint(ARec.Results.ByName('bkpt'));
    lgrLocals:
      ReadLocals(ARec);
    lgrFrames:
      ReadFrames(ARec);
    lgrEval:
      if Assigned(FOnEval) then
        FOnEval(Self, Tag, ARec.Results.Str('value', ''), False);
  end;
end;

procedure TLedGdbSession.HandleExec(ARec: TLedMIRecord);
var
  Reason, FileName, Func: string;
  Line: Integer;
begin
  if ARec.Class_ = 'running' then
  begin
    FInferiorAlive := True;
    SetState(lgsRunning);
    if Assigned(FOnRunning) then FOnRunning(Self);
    Exit;
  end;

  if ARec.Class_ <> 'stopped' then Exit;

  Reason := ARec.Results.Str('reason', '');
  { fullname is the absolute path; file may be relative to the compilation
    directory, which is not where the editor is. }
  FileName := ARec.Results.Str('frame.fullname',
                               ARec.Results.Str('frame.file', ''));
  Line := ARec.Results.Int('frame.line', 0);
  Func := ARec.Results.Str('frame.func', '');

  { The program finishing is a stop like any other as far as gdb is
    concerned -- it is still there and can be re-run -- but nothing may be
    evaluated afterwards, or gdb answers "No registers." to everything. }
  if Copy(Reason, 1, 6) = 'exited' then
    FInferiorAlive := False;

  SetState(lgsStopped);
  if Assigned(FOnStopped) then FOnStopped(Self, Reason, FileName, Line, Func);
end;

procedure TLedGdbSession.HandleNotify(ARec: TLedMIRecord);
var
  Num: Integer;
begin
  if (ARec.Class_ = 'breakpoint-created') or
     (ARec.Class_ = 'breakpoint-modified') then
    EmitBreakpoint(ARec.Results.ByName('bkpt'))
  else if ARec.Class_ = 'breakpoint-deleted' then
  begin
    Num := ARec.Results.Int('id', -1);
    if (Num >= 0) and Assigned(FOnBreakRemoved) then
      FOnBreakRemoved(Self, Num, '', 0);
  end;
end;

procedure TLedGdbSession.EmitBreakpoint(AValue: TLedMIValue);
var
  Num, Line, p: Integer;
  FileName, Loc: string;
begin
  if AValue = nil then Exit;
  Num := AValue.Int('number', -1);
  if Num < 0 then Exit;

  FileName := AValue.Str('fullname', AValue.Str('file', ''));
  Line := AValue.Int('line', 0);

  { A pending breakpoint -- set before any binary was loaded -- has no file
    or line of its own; gdb only echoes back what was asked for. }
  if (FileName = '') or (Line = 0) then
  begin
    Loc := AValue.Str('original-location', '');
    p := LastDelimiter(':', Loc);
    if p > 1 then
    begin
      FileName := Copy(Loc, 1, p - 1);
      Line := StrToIntDef(Copy(Loc, p + 1, Length(Loc)), 0);
    end;
  end;

  if Assigned(FOnBreakAdded) then FOnBreakAdded(Self, Num, FileName, Line);
end;

procedure TLedGdbSession.ReadLocals(ARec: TLedMIRecord);
var
  V, E: TLedMIValue;
  i, n: Integer;
begin
  SetLength(FLocals, 0);
  V := ARec.Results.ByName('variables');
  if V = nil then Exit;
  n := 0;
  SetLength(FLocals, V.Count);
  for i := 0 to V.Count - 1 do
  begin
    E := V[i];
    if E = nil then Continue;
    FLocals[n].Name := E.Str('name', '');
    FLocals[n].TypeName := E.Str('type', '');
    { --simple-values leaves an aggregate without a value; saying so is
      better than an empty cell that looks like a failure. }
    FLocals[n].Value := E.Str('value', '{...}');
    if FLocals[n].Name <> '' then Inc(n);
  end;
  SetLength(FLocals, n);
  if Assigned(FOnLocals) then FOnLocals(Self);
end;

procedure TLedGdbSession.ReadFrames(ARec: TLedMIRecord);
var
  V, E: TLedMIValue;
  i, n: Integer;
begin
  SetLength(FFrames, 0);
  V := ARec.Results.ByName('stack');
  if V = nil then Exit;
  n := 0;
  SetLength(FFrames, V.Count);
  for i := 0 to V.Count - 1 do
  begin
    E := V[i];
    if E = nil then Continue;
    FFrames[n].Level := E.Int('level', n);
    FFrames[n].Func := E.Str('func', '??');
    FFrames[n].FileName := E.Str('fullname', E.Str('file', ''));
    FFrames[n].Line := E.Int('line', 0);
    FFrames[n].Addr := E.Str('addr', '');
    Inc(n);
  end;
  SetLength(FFrames, n);
  if Assigned(FOnFrames) then FOnFrames(Self);
end;

{ --- commands -------------------------------------------------------------- }

procedure TLedGdbSession.SetTarget(const APath: string);
begin
  { MI quoting, not shell quoting -- see the note at the top. }
  Send('-file-exec-and-symbols ' + LedMIQuote(APath));
end;

procedure TLedGdbSession.SetArguments(AArgs: TStrings);
var
  i: Integer;
  Line: string;
begin
  Line := '';
  if AArgs <> nil then
    for i := 0 to AArgs.Count - 1 do
      Line := Line + ' ' + LedMIQuote(AArgs[i]);
  { Sent even when empty, to clear arguments left over from a previous run. }
  Send('-exec-arguments' + Line);
end;

procedure TLedGdbSession.SetWorkingDir(const ADir: string);
begin
  if ADir = '' then Exit;
  Send('-environment-cd ' + LedMIQuote(ADir));
end;

procedure TLedGdbSession.SetEnvironmentVar(const AName, AValue: string);
begin
  if AName = '' then Exit;
  Send('-gdb-set environment ' + AName + '=' + AValue);
end;

procedure TLedGdbSession.ExecRun;
begin
  Send('-exec-run', lgrExec);
end;

procedure TLedGdbSession.ExecContinue;
begin
  Send('-exec-continue', lgrExec);
end;

procedure TLedGdbSession.ExecNext;
begin
  Send('-exec-next', lgrExec);
end;

procedure TLedGdbSession.ExecStep;
begin
  Send('-exec-step', lgrExec);
end;

procedure TLedGdbSession.ExecFinish;
begin
  Send('-exec-finish', lgrExec);
end;

procedure TLedGdbSession.ExecInterrupt;
begin
  Send('-exec-interrupt --all', lgrExec);
end;

procedure TLedGdbSession.BreakInsert(const AFileName: string; ALine: Integer);
begin
  { -f allows a breakpoint before any binary is loaded, which is what makes
    setting one in the editor before pressing Start work.  Unquoted on
    purpose: see the note at the top of the unit. }
  Send(Format('-break-insert -f %s:%d', [AFileName, ALine]), lgrBreakInsert,
    Format('%s:%d', [AFileName, ALine]));
end;

procedure TLedGdbSession.BreakDelete(ANumber: Integer);
begin
  Send(Format('-break-delete %d', [ANumber]), lgrBreakDelete);
  { Reported locally as well as from =breakpoint-deleted: the notify does not
    always arrive, and a duplicate removal is harmless. }
  if Assigned(FOnBreakRemoved) then FOnBreakRemoved(Self, ANumber, '', 0);
end;

procedure TLedGdbSession.RequestLocals;
begin
  if not FInferiorAlive then Exit;
  Send('-stack-list-variables --simple-values', lgrLocals);
end;

procedure TLedGdbSession.RequestFrames;
begin
  if not FInferiorAlive then Exit;
  Send('-stack-list-frames', lgrFrames);
end;

procedure TLedGdbSession.SelectFrame(ALevel: Integer);
begin
  Send(Format('-stack-select-frame %d', [ALevel]));
end;

procedure TLedGdbSession.Evaluate(const AExpression, ATag: string);
begin
  if AExpression = '' then Exit;
  { Answered immediately rather than sent, when there is nothing to ask: the
    caller gets one code path instead of two. }
  if (FState <> lgsStopped) or (not FInferiorAlive) then
  begin
    if Assigned(FOnEval) then
      FOnEval(Self, ATag, 'not running', True);
    Exit;
  end;
  Send('-data-evaluate-expression ' + LedMIQuote(AExpression), lgrEval, ATag);
end;

end.
