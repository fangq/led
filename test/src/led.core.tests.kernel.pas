// led - a lightweight editor.  Tests for running cells in a kernel.
//
// Two halves, checked separately.  The protocol is a line in and a record
// out, and that needs no kernel at all -- which is the point of putting it
// behind a function rather than inside the reading loop.
//
// The other half is the helper itself, and that is checked by running a real
// kernel and asking it for the answer to a real cell.  There is no way to be
// sure a protocol works by testing the half of it LED wrote; the shapes the
// helper emits are jupyter_client's, and the only authority on those is
// jupyter_client.  Where the machine has no kernel installed those tests do
// nothing, the same bargain the gdb tests make with a missing toolchain.

unit Led.Core.Tests.Kernel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, process, fpjson, fpcunit, testregistry,
  Led.Core.Kernel, Led.Core.NBFormat;

type
  TTestKernel = class(TTestCase)
  private
    FHaveKernel: Boolean;
    { What the events said, recorded as they arrived. }
    FReady: Boolean;
    FDoneId: Integer;
    FDoneStatus: string;
    FDoneCount: Integer;
    FStreams: string;
    FErrors: Integer;
    FFailure: string;
    procedure Heard(Sender: TObject; const AEvent: TLedKernelEvent);
    { Runs ACode in a kernel and waits for its done event.  False when there
      is no kernel to run it in. }
    function RunInKernel(const ACode: string; ASeconds: Integer = 60): Boolean;
  protected
    procedure SetUp; override;
  published
    { the protocol }
    procedure AReadyLineSaysWhatTheKernelSpeaks;
    procedure AStatusLineSaysBusyOrIdle;
    procedure AnOutputLineCarriesAnNBFormatOutput;
    procedure ADoneLineCarriesTheExecutionCount;
    procedure AFailureLineCarriesItsReason;
    procedure ALineThatIsNotAnEventIsRefused;
    procedure ARunCommandIsOneLineWhateverTheCodeIs;
    { the helper, against a real kernel }
    procedure AKernelRunsACellAndSaysWhatItPrinted;
    procedure AnErrorComesBackAsATraceback;
    procedure AMagicIsTheKernelsBusinessAndWorks;
  end;

implementation

procedure TTestKernel.SetUp;
var
  P: TProcess;
begin
  inherited SetUp;
  FHaveKernel := False;
  FReady := False;
  FDoneId := -1;
  FDoneStatus := '';
  FDoneCount := -2;
  FStreams := '';
  FErrors := 0;
  FFailure := '';

  if not FileExists(LedKernelHelper) then Exit;
  { Asked of the same Python the helper will be run with, because having
    jupyter_client is a property of an interpreter and not of a machine. }
  P := TProcess.Create(nil);
  try
    P.Executable := LedKernelPython;
    P.Parameters.Add('-c');
    P.Parameters.Add('import jupyter_client, ipykernel');
    P.Options := [poWaitOnExit, poUsePipes, poNoConsole];
    try
      P.Execute;
      FHaveKernel := P.ExitStatus = 0;
    except
      FHaveKernel := False;
    end;
  finally
    P.Free;
  end;
end;

procedure TTestKernel.Heard(Sender: TObject; const AEvent: TLedKernelEvent);
var
  Text: TJSONData;
  i: Integer;
begin
  case AEvent.Kind of
    lkeReady: FReady := True;
    lkeFailed: FFailure := AEvent.Message;
    lkeDone:
      begin
        FDoneId := AEvent.Id;
        FDoneStatus := AEvent.Status;
        FDoneCount := AEvent.Count;
      end;
    lkeOutput:
      begin
        if AEvent.Output.Get('output_type', '') = 'error' then Inc(FErrors);
        Text := AEvent.Output.Find('text');
        if (Text <> nil) and (Text.JSONType = jtArray) then
          for i := 0 to TJSONArray(Text).Count - 1 do
            FStreams := FStreams + TJSONArray(Text).Items[i].AsString;
        { An error's lines are in its traceback rather than in text. }
        Text := AEvent.Output.Find('traceback');
        if (Text <> nil) and (Text.JSONType = jtArray) then
          for i := 0 to TJSONArray(Text).Count - 1 do
            FStreams := FStreams + TJSONArray(Text).Items[i].AsString + #10;
      end;
  end;
end;

function TTestKernel.RunInKernel(const ACode: string;
  ASeconds: Integer): Boolean;
var
  K: TLedKernel;
  Why: string;
  Deadline: TDateTime;
  Id: Integer;
begin
  Result := False;
  if not FHaveKernel then Exit;
  K := TLedKernel.Create;
  try
    K.OnEvent := @Heard;
    AssertTrue('the helper starts: ' + Why, K.Start('python3', Why));

    { Waiting is what a test may do and the editor may not: the editor polls
      from a timer, and this stands in for the timer. }
    Deadline := Now + ASeconds / 86400.0;
    while (not FReady) and (FFailure = '') and (Now < Deadline) do
    begin
      K.Poll;
      Sleep(20);
    end;
    AssertEquals('the kernel started without complaint', '', FFailure);
    AssertTrue('and became ready', FReady);

    Id := K.Run(ACode);
    AssertTrue('the cell was sent', Id > 0);

    while (FDoneId < 0) and (FFailure = '') and (Now < Deadline) do
    begin
      K.Poll;
      Sleep(20);
    end;
    AssertEquals('nothing went wrong while running', '', FFailure);
    AssertEquals('the run that finished is the run that was sent',
      Id, FDoneId);
    Result := True;
  finally
    K.Free;
  end;
end;

{ ---- the protocol ---- }

procedure TTestKernel.AReadyLineSaysWhatTheKernelSpeaks;
var
  Ev: TLedKernelEvent;
  Err: string;
begin
  AssertTrue('it parses: ' + Err, LedKernelParseEvent(
    '{"ev": "ready", "kernel": "python3", "language": "python"}', Ev, Err));
  AssertEquals(Ord(lkeReady), Ord(Ev.Kind));
  AssertEquals('python', Ev.Language);
end;

procedure TTestKernel.AStatusLineSaysBusyOrIdle;
var
  Ev: TLedKernelEvent;
  Err: string;
begin
  AssertTrue(LedKernelParseEvent('{"ev": "status", "state": "busy"}', Ev, Err));
  AssertEquals(Ord(lkeStatus), Ord(Ev.Kind));
  AssertEquals('busy', Ev.Status);
end;

procedure TTestKernel.AnOutputLineCarriesAnNBFormatOutput;
var
  Ev: TLedKernelEvent;
  Err: string;
begin
  AssertTrue('it parses: ' + Err, LedKernelParseEvent(
    '{"ev": "output", "id": 7, "output": {"output_type": "stream", ' +
    '"name": "stdout", "text": ["42' + '\n' + '"]}}', Ev, Err));
  try
    AssertEquals(Ord(lkeOutput), Ord(Ev.Kind));
    AssertEquals('which run it belongs to', 7, Ev.Id);
    AssertTrue('the output came with it', Ev.Output <> nil);
    AssertEquals('and is an output object, ready for the cell',
      'stream', Ev.Output.Get('output_type', ''));
  finally
    Ev.Output.Free;
  end;
end;

procedure TTestKernel.ADoneLineCarriesTheExecutionCount;
var
  Ev: TLedKernelEvent;
  Err: string;
begin
  AssertTrue(LedKernelParseEvent(
    '{"ev": "done", "id": 3, "status": "error", "count": 9}', Ev, Err));
  AssertEquals(Ord(lkeDone), Ord(Ev.Kind));
  AssertEquals(3, Ev.Id);
  AssertEquals('error', Ev.Status);
  AssertEquals(9, Ev.Count);

  { A kernel that gave no count -- a cell that never ran -- is -1, not 0:
    zero is a count a cell could have. }
  AssertTrue(LedKernelParseEvent(
    '{"ev": "done", "id": 3, "status": "ok", "count": null}', Ev, Err));
  AssertEquals(-1, Ev.Count);
end;

procedure TTestKernel.AFailureLineCarriesItsReason;
var
  Ev: TLedKernelEvent;
  Err: string;
begin
  AssertTrue(LedKernelParseEvent(
    '{"ev": "failed", "msg": "jupyter_client is not installed"}', Ev, Err));
  AssertEquals(Ord(lkeFailed), Ord(Ev.Kind));
  AssertTrue('the reason survives: ' + Ev.Message,
    Pos('jupyter_client', Ev.Message) > 0);
end;

procedure TTestKernel.ALineThatIsNotAnEventIsRefused;
var
  Ev: TLedKernelEvent;
  Err: string;
begin
  { Anything a helper's Python might print on the way past: a warning, a
    blank line, a half-written line.  None of them is an event, and none of
    them may be taken for one with its fields left empty. }
  AssertFalse('a warning', LedKernelParseEvent(
    'DeprecationWarning: something', Ev, Err));
  AssertTrue('with a reason: ' + Err, Err <> '');
  AssertFalse('an empty line', LedKernelParseEvent('', Ev, Err));
  AssertFalse('JSON that is not an event',
    LedKernelParseEvent('{"hello": 1}', Ev, Err));
  AssertFalse('an event nothing here knows',
    LedKernelParseEvent('{"ev": "teapot"}', Ev, Err));
  AssertFalse('an output event with no output',
    LedKernelParseEvent('{"ev": "output", "id": 1}', Ev, Err));
end;

procedure TTestKernel.ARunCommandIsOneLineWhateverTheCodeIs;
var
  Line: string;
  Ev: TLedKernelEvent;
  Err: string;
  Back: TJSONData;
begin
  Line := LedKernelRunCommand(4,
    'print("a")' + #10 + 'x = "quoted \ and' + #9 + 'tabbed"' + #10 + 'y = 2');
  AssertTrue('a command carries no newline of its own',
    Pos(#10, Line) = 0);
  AssertTrue('nor a tab', Pos(#9, Line) = 0);

  { Read back with the same reader the events go through, because the claim
    is that what came out is JSON and says what went in. }
  Back := LedNBParseJSON(Line, Err);
  AssertTrue('the command is JSON: ' + Err, Back <> nil);
  try
    AssertEquals('run', TJSONObject(Back).Get('cmd', ''));
    AssertEquals(4, TJSONObject(Back).Get('id', 0));
    AssertEquals('and the code arrives as it was written',
      'print("a")' + #10 + 'x = "quoted \ and' + #9 + 'tabbed"' + #10 + 'y = 2',
      TJSONObject(Back).Get('code', ''));
  finally
    Back.Free;
  end;
  { And the parser does not mistake a command for an event. }
  AssertFalse('a command is not an event', LedKernelParseEvent(Line, Ev, Err));
end;

{ ---- the helper, against a real kernel ---- }

procedure TTestKernel.AKernelRunsACellAndSaysWhatItPrinted;
begin
  if not RunInKernel('print(6 * 7)') then Exit;
  AssertEquals('it finished cleanly', 'ok', FDoneStatus);
  AssertEquals('and it was the first thing run', 1, FDoneCount);
  AssertTrue('what it printed came back: ' + FStreams,
    Pos('42', FStreams) > 0);
end;

procedure TTestKernel.AnErrorComesBackAsATraceback;
begin
  if not RunInKernel('1/0') then Exit;
  AssertEquals('the run says it failed', 'error', FDoneStatus);
  AssertEquals('with one error output', 1, FErrors);
  AssertTrue('naming what went wrong: ' + FStreams,
    Pos('ZeroDivisionError', FStreams) > 0);
end;

{ The reason for driving a real kernel rather than piping code to python:
  magics are IPython's, and they work here without a line of LED knowing
  they exist. }
procedure TTestKernel.AMagicIsTheKernelsBusinessAndWorks;
begin
  if not RunInKernel('!echo from-a-shell-magic') then Exit;
  AssertEquals('the cell ran', 'ok', FDoneStatus);
  AssertTrue('and the shell magic did what it says: ' + FStreams,
    Pos('from-a-shell-magic', FStreams) > 0);
end;

initialization
  RegisterTest(TTestKernel);

end.
