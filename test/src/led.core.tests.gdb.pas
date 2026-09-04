{ led - a light editor.  A real gdb, driven end to end.

  These tests compile a C program with gcc and debug it with the gdb on this
  machine.  Nothing is mocked, because the things that break in a debugger
  are the protocol's real answers -- a pending breakpoint that comes back
  without a file, an evaluation after the program has exited -- and a mock
  would only ever return what its author already believed.

  Everything is skipped, not failed, when gcc or gdb is missing: a machine
  without a C toolchain is allowed to run led's test suite. }
unit Led.Core.Tests.Gdb;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, process, fpcunit, testregistry,
  Led.Core.Gdb, Led.Core.GdbMI;

type
  TTestGdb = class(TTestCase)
  private
    FDir: string;
    FSource: string;
    FBinary: string;
    FToolchain: Boolean;
    { Recorded by the event handlers so a test can assert what arrived. }
    FStops: Integer;
    FLastReason: string;
    FLastFile: string;
    FLastLine: Integer;
    FLastFunc: string;
    FBreakNum: Integer;
    FBreakFile: string;
    FBreakLine: Integer;
    FEvalTag, FEvalValue: string;
    FEvalError: Boolean;
    FConsole: string;
    FTargetText: string;
    procedure OnStopped(Sender: TObject; const AReason, AFileName: string;
      ALine: Integer; const AFunc: string);
    procedure OnBreakAdded(Sender: TObject; ANumber: Integer;
      const AFileName: string; ALine: Integer);
    procedure OnEval(Sender: TObject; const ATag, AValue: string;
      AIsError: Boolean);
    procedure OnConsole(Sender: TObject; const AText: string);
    procedure OnTarget(Sender: TObject; const AText: string);
    function NewSession: TLedGdbSession;
    { Polls until ACondition is met or the time runs out. }
    function PumpUntilStops(ASession: TLedGdbSession; ACount: Integer;
      ATimeoutMs: Integer = 15000): Boolean;
    procedure PumpFor(ASession: TLedGdbSession; AMs: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure GdbStartsAndReportsAVersion;
    procedure MissingGdbIsReportedNotRaised;
    procedure BreakpointBeforeTheBinaryIsLoaded;
    procedure RunStopsAtTheBreakpoint;
    procedure LocalsAreReadAtTheStop;
    procedure StackIsReadAtTheStop;
    procedure SteppingMovesALine;
    procedure EvaluateReadsAVariable;
    procedure EvaluateOfNonsenseIsAnErrorNotAFault;
    procedure EvaluateBeforeRunningIsAnswered;
    procedure ProgramOutputReachesTheTarget;
    procedure ContinueRunsToExitAndClearsInferior;
    procedure DeleteStopsTheBreakpointFiring;
  end;

implementation

const
  { Deliberately ordinary: a couple of frames, a local to read, a printf so
    there is inferior output to catch. }
  CSource =
    '#include <stdio.h>'#10 +
    ''#10 +
    'int add(int a, int b)'#10 +
    '{'#10 +
    '    int sum = a + b;'#10 +          // line 5
    '    return sum;'#10 +               // line 6
    '}'#10 +
    ''#10 +
    'int main(void)'#10 +
    '{'#10 +
    '    int total = 0;'#10 +            // line 11
    '    total = add(2, 3);'#10 +        // line 12
    '    printf("total=%d\n", total);'#10 +
    '    return 0;'#10 +
    '}'#10;

  BreakLine = 5;      { "int sum = a + b;" -- inside add(), so there is a stack }

procedure TTestGdb.SetUp;
var
  L: TStringList;
  P: TProcess;
begin
  FToolchain := False;
  FStops := 0;
  FStops := 0;
  FBreakNum := -1;
  FConsole := '';
  FTargetText := '';

  FDir := IncludeTrailingPathDelimiter(GetTempDir) +
          Format('led-gdbtest-%d', [GetProcessID]);
  ForceDirectories(FDir);
  FSource := IncludeTrailingPathDelimiter(FDir) + 'prog.c';
  FBinary := IncludeTrailingPathDelimiter(FDir) + 'prog';

  if not LedGdbAvailable then Exit;
  if FindDefaultExecutablePath('gcc') = '' then Exit;

  L := TStringList.Create;
  try
    L.Text := CSource;
    L.SaveToFile(FSource);
  finally
    L.Free;
  end;

  P := TProcess.Create(nil);
  try
    P.Executable := FindDefaultExecutablePath('gcc');
    P.Parameters.Add('-g');
    P.Parameters.Add('-O0');
    P.Parameters.Add(FSource);
    P.Parameters.Add('-o');
    P.Parameters.Add(FBinary);
    P.Options := [poWaitOnExit, poUsePipes, poStderrToOutPut, poNoConsole];
    P.Execute;
    FToolchain := (P.ExitStatus = 0) and FileExists(FBinary);
  finally
    P.Free;
  end;
end;

procedure TTestGdb.TearDown;
begin
  if (FDir <> '') and DirectoryExists(FDir) then
    DeleteDirectory(FDir, False);
end;

{ --- event capture --------------------------------------------------------- }

procedure TTestGdb.OnStopped(Sender: TObject; const AReason, AFileName: string;
  ALine: Integer; const AFunc: string);
begin
  Inc(FStops);
  FLastReason := AReason;
  FLastFile := AFileName;
  FLastLine := ALine;
  FLastFunc := AFunc;
end;

procedure TTestGdb.OnBreakAdded(Sender: TObject; ANumber: Integer;
  const AFileName: string; ALine: Integer);
begin
  FBreakNum := ANumber;
  FBreakFile := AFileName;
  FBreakLine := ALine;
end;

procedure TTestGdb.OnEval(Sender: TObject; const ATag, AValue: string;
  AIsError: Boolean);
begin
  FEvalTag := ATag;
  FEvalValue := AValue;
  FEvalError := AIsError;
end;

procedure TTestGdb.OnConsole(Sender: TObject; const AText: string);
begin
  FConsole := FConsole + AText;
end;

procedure TTestGdb.OnTarget(Sender: TObject; const AText: string);
begin
  FTargetText := FTargetText + AText;
end;

function TTestGdb.NewSession: TLedGdbSession;
begin
  Result := TLedGdbSession.Create;
  Result.OnStopped := @OnStopped;
  Result.OnBreakAdded := @OnBreakAdded;
  Result.OnEval := @OnEval;
  Result.OnConsole := @OnConsole;
  Result.OnTarget := @OnTarget;
end;

procedure TTestGdb.PumpFor(ASession: TLedGdbSession; AMs: Integer);
var
  i: Integer;
begin
  for i := 1 to AMs div 10 do
  begin
    ASession.Poll;
    Sleep(10);
  end;
end;

function TTestGdb.PumpUntilStops(ASession: TLedGdbSession; ACount: Integer;
  ATimeoutMs: Integer): Boolean;
var
  Waited: Integer;
begin
  Waited := 0;
  while (FStops < ACount) and (Waited < ATimeoutMs) do
  begin
    ASession.Poll;
    Sleep(10);
    Inc(Waited, 10);
  end;
  Result := FStops >= ACount;
end;

{ --- the tests ------------------------------------------------------------- }

procedure TTestGdb.GdbStartsAndReportsAVersion;
var S: TLedGdbSession;
begin
  if not LedGdbAvailable then Exit;
  S := NewSession;
  try
    AssertTrue('gdb starts', S.Start);
    AssertTrue('and reaches ready',
      S.WaitForState([lgsReady], 10000));
    AssertTrue('reporting a version', S.Version <> '');
  finally
    S.Free;
  end;
end;

procedure TTestGdb.MissingGdbIsReportedNotRaised;
var S: TLedGdbSession;
begin
  { A machine without gdb must get a message, not an exception out of a
    timer handler. }
  S := TLedGdbSession.Create;
  try
    AssertFalse('a gdb that is not there does not start',
      S.Start('led-no-such-debugger-xyz'));
    AssertTrue('and says why', S.LastError <> '');
    AssertTrue('leaving the session in error', S.State = lgsError);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.BreakpointBeforeTheBinaryIsLoaded;
var S: TLedGdbSession;
begin
  if not FToolchain then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    { -break-insert -f, before any -file-exec-and-symbols.  gdb answers with
      no file and no line, only original-location -- the case that makes a
      naive reader drop the breakpoint. }
    S.BreakInsert(FSource, BreakLine);
    PumpFor(S, 1500);
    AssertTrue('gdb gave it a number', FBreakNum > 0);
    AssertEquals('and the line it was asked for', BreakLine, FBreakLine);
    AssertTrue('and a file', FBreakFile <> '');
  finally
    S.Free;
  end;
end;

procedure TTestGdb.RunStopsAtTheBreakpoint;
var S: TLedGdbSession;
begin
  if not FToolchain then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    S.SetTarget(FBinary);
    S.BreakInsert(FSource, BreakLine);
    PumpFor(S, 500);
    S.ExecRun;
    AssertTrue('the program stops', PumpUntilStops(S, 1));
    AssertEquals('because it hit the breakpoint', 'breakpoint-hit',
      FLastReason);
    AssertEquals('on the line asked for', BreakLine, FLastLine);
    AssertEquals('in the right function', 'add', FLastFunc);
    AssertTrue('with an absolute path to the source',
      (FLastFile <> '') and (Pos('prog.c', FLastFile) > 0));
    AssertTrue('and the session says stopped', S.State = lgsStopped);
    AssertTrue('with the program still alive', S.InferiorAlive);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.LocalsAreReadAtTheStop;
var S: TLedGdbSession; i: Integer; Found: Boolean;
begin
  if not FToolchain then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    S.SetTarget(FBinary);
    S.BreakInsert(FSource, BreakLine);
    PumpFor(S, 500);
    S.ExecRun;
    if not PumpUntilStops(S, 1) then Exit;
    S.RequestLocals;
    PumpFor(S, 1500);

    AssertTrue('some locals came back', Length(S.Locals) > 0);
    Found := False;
    for i := 0 to High(S.Locals) do
      if S.Locals[i].Name = 'a' then
      begin
        Found := True;
        AssertEquals('the argument''s value', '2', S.Locals[i].Value);
        AssertEquals('and its type', 'int', S.Locals[i].TypeName);
      end;
    AssertTrue('including the argument a', Found);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.StackIsReadAtTheStop;
var S: TLedGdbSession;
begin
  if not FToolchain then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    S.SetTarget(FBinary);
    S.BreakInsert(FSource, BreakLine);
    PumpFor(S, 500);
    S.ExecRun;
    if not PumpUntilStops(S, 1) then Exit;
    S.RequestFrames;
    PumpFor(S, 1500);

    { add() called from main() -- two frames, innermost first.  This is the
      repeated-name list that a tuple-shaped reader collapses to one. }
    AssertTrue('at least two frames', Length(S.Frames) >= 2);
    AssertEquals('innermost is where we stopped', 'add', S.Frames[0].Func);
    AssertEquals('and it is level 0', 0, S.Frames[0].Level);
    AssertEquals('its caller is main', 'main', S.Frames[1].Func);
    AssertEquals('called from the call site', 12, S.Frames[1].Line);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.SteppingMovesALine;
var S: TLedGdbSession; First: Integer;
begin
  if not FToolchain then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    S.SetTarget(FBinary);
    S.BreakInsert(FSource, BreakLine);
    PumpFor(S, 500);
    S.ExecRun;
    if not PumpUntilStops(S, 1) then Exit;
    First := FLastLine;

    S.ExecNext;
    AssertTrue('stepping stops again', PumpUntilStops(S, 2));
    AssertEquals('for having finished a step', 'end-stepping-range',
      FLastReason);
    AssertEquals('one line further on', First + 1, FLastLine);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.EvaluateReadsAVariable;
var S: TLedGdbSession;
begin
  if not FToolchain then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    S.SetTarget(FBinary);
    S.BreakInsert(FSource, BreakLine);
    PumpFor(S, 500);
    S.ExecRun;
    if not PumpUntilStops(S, 1) then Exit;

    FEvalValue := '';
    S.Evaluate('a + b', 'hover:1');
    PumpFor(S, 1500);
    AssertEquals('the tag comes back with the answer', 'hover:1', FEvalTag);
    AssertEquals('2 + 3', '5', FEvalValue);
    AssertFalse('and it is not an error', FEvalError);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.EvaluateOfNonsenseIsAnErrorNotAFault;
var S: TLedGdbSession;
begin
  if not FToolchain then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    S.SetTarget(FBinary);
    S.BreakInsert(FSource, BreakLine);
    PumpFor(S, 500);
    S.ExecRun;
    if not PumpUntilStops(S, 1) then Exit;

    { Hovering over a name that is not in scope is the ordinary case, so it
      must not be posted as a session error. }
    FEvalError := False;
    S.Evaluate('no_such_variable_here', 'hover:2');
    PumpFor(S, 1500);
    AssertTrue('reported as an error on the request', FEvalError);
    AssertEquals('against its own tag', 'hover:2', FEvalTag);
    AssertTrue('with gdb''s wording', Pos('No symbol', FEvalValue) > 0);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.EvaluateBeforeRunningIsAnswered;
var S: TLedGdbSession;
begin
  if not LedGdbAvailable then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    FEvalTag := '';
    FEvalError := False;
    { Answered locally, so a caller needs one code path rather than two. }
    S.Evaluate('anything', 'hover:3');
    AssertEquals('answered at once', 'hover:3', FEvalTag);
    AssertTrue('as an error', FEvalError);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.ProgramOutputReachesTheTarget;
var S: TLedGdbSession;
begin
  if not FToolchain then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    S.SetTarget(FBinary);
    S.ExecRun;
    { No breakpoint: it runs to completion and its printf has to arrive. }
    PumpFor(S, 4000);
    AssertTrue('the program''s own output is seen',
      Pos('total=5', FTargetText + FConsole) > 0);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.ContinueRunsToExitAndClearsInferior;
var S: TLedGdbSession;
begin
  if not FToolchain then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    S.SetTarget(FBinary);
    S.BreakInsert(FSource, BreakLine);
    PumpFor(S, 500);
    S.ExecRun;
    if not PumpUntilStops(S, 1) then Exit;

    S.ExecContinue;
    AssertTrue('it stops again, having exited', PumpUntilStops(S, 2));
    AssertTrue('the reason says so', Pos('exited', FLastReason) > 0);
    { gdb is still there and could re-run, but nothing may be evaluated. }
    AssertFalse('and the program is no longer alive', S.InferiorAlive);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.DeleteStopsTheBreakpointFiring;
var S: TLedGdbSession;
begin
  if not FToolchain then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    S.SetTarget(FBinary);
    S.BreakInsert(FSource, BreakLine);
    PumpFor(S, 800);
    AssertTrue('the breakpoint exists', FBreakNum > 0);

    S.BreakDelete(FBreakNum);
    PumpFor(S, 500);
    S.ExecRun;
    PumpFor(S, 4000);
    { With it gone the program runs to completion, so the only stop is the
      exit -- never a breakpoint-hit. }
    AssertTrue('nothing stopped at a breakpoint',
      Pos('breakpoint', FLastReason) = 0);
    AssertTrue('and it ran to the end',
      Pos('total=5', FTargetText + FConsole) > 0);
  finally
    S.Free;
  end;
end;

initialization
  RegisterTest(TTestGdb);

end.
