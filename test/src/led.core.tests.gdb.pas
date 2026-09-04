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
    FBreakCond: string;
    FBreakKind: TLedGdbBreakKind;
    FBreakExpr: string;
    FBreakEnabled: Boolean;
    FBreakHits: Integer;
    FBreakComplete: Boolean;
    FRemovedNum: Integer;
    FRemovals: Integer;
    FWatchNum: Integer;
    FWatchExpr, FWatchOld, FWatchNew: string;
    FWatchHits: Integer;
    FErrors: string;
    FLoopSrc: string;
    FEvalTag, FEvalValue: string;
    FEvalError: Boolean;
    FVarTag, FVarObj, FVarType, FVarValue: string;
    FVarNumChild: Integer;
    FKidsTag: string;
    FKids: TLedGdbVarChildren;
    FConsole: string;
    FTargetText: string;
    procedure OnStopped(Sender: TObject; const AReason, AFileName: string;
      ALine: Integer; const AFunc: string);
    procedure OnBreakAdded(Sender: TObject; const AInfo: TLedGdbBreakInfo);
    procedure OnBreakRemoved(Sender: TObject; ANumber: Integer);
    procedure OnWatchHit(Sender: TObject; ANumber: Integer;
      const AExpression, AOldValue, ANewValue: string);
    procedure OnError(Sender: TObject; const AText: string);
    { The global fixture: a loop that writes and then reads a global, so a
      watchpoint of every kind has something to fire on. }
    function StopInGlobalProgram(out ASession: TLedGdbSession;
      out ASource: string): Boolean;
    function CompileTo(const AName, ASource: string): string;
    function StopInLoopProgram(out ASession: TLedGdbSession;
      const ACondition: string): Boolean;
    procedure OnEval(Sender: TObject; const ATag, AValue: string;
      AIsError: Boolean);
    procedure OnVarCreated(Sender: TObject; const ATag, AVarObj,
      ATypeName, AValue: string; ANumChild: Integer);
    procedure OnVarChildren(Sender: TObject; const ATag: string;
      const AChildren: TLedGdbVarChildren);
    function StopInStructProgram(out ASession: TLedGdbSession): Boolean;
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
    procedure VarCreateDescribesAStruct;
    procedure VarChildrenListsTheFields;
    procedure AggregateChildrenHaveNoValue;
    procedure DrillingTwoLevelsDeepReachesALeaf;
    procedure ArrayChildrenAreIndexed;
    procedure VarCreateBeforeStoppingIsAnswered;
    procedure HoverFindsAPlainIdentifier;
    procedure HoverFindsFieldAccess;
    procedure HoverFindsArrowAccess;
    procedure HoverFindsSubscripts;
    procedure HoverSkipsKeywordsAndNumbers;
    procedure HoverOffAWordIsEmpty;
    procedure ConditionalBreakpointWaitsForItsExpression;
    procedure ConditionIsEchoedBack;
    procedure ChangingAConditionTakesEffect;
    procedure ClearingAConditionMakesItAlwaysFire;
    procedure RunToCursorReachesTheLine;
    procedure RunToCursorSkipsWhatIsBetween;
    procedure WatchpointStopsWhenTheValueChanges;
    procedure WatchpointReportsWhatItWasAndWhatItIs;
    procedure ReadWatchpointFiresWithoutAChange;
    procedure WatchpointComesBackAsAWatchpointNotABreakpoint;
    procedure WatchingALocalBeforeThereIsAFrameIsRefused;
    procedure AWatchpointOutOfScopeIsDeleted;
    procedure DisablingABreakpointStopsItFiring;
    procedure EnablingItAgainBringsItBack;
    procedure HitCountsComeBackFromGdb;
    procedure PaddingIsStrippedFromACharArray;
    procedure ACollapsedRunOfNulsGoesToo;
    procedure ANulInTheMiddleIsKept;
    procedure APlainValueIsLeftAlone;
    procedure AStructIsBrokenAcrossLines;
    procedure StringsWithBracesInThemAreNotSplit;
    procedure AHugeValueIsCutOff;
    procedure RealGdbValuesComeOutReadable;
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
  FRemovedNum := -1;
  FRemovals := 0;
  FWatchNum := -1;
  FWatchHits := 0;
  FWatchOld := '';
  FWatchNew := '';
  FErrors := '';
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

procedure TTestGdb.OnBreakAdded(Sender: TObject;
  const AInfo: TLedGdbBreakInfo);
begin
  FBreakNum := AInfo.Number;
  FBreakFile := AInfo.FileName;
  FBreakLine := AInfo.Line;
  FBreakCond := AInfo.Condition;
  FBreakKind := AInfo.Kind;
  FBreakExpr := AInfo.Expression;
  FBreakEnabled := AInfo.Enabled;
  FBreakHits := AInfo.HitCount;
  FBreakComplete := AInfo.Complete;
end;

procedure TTestGdb.OnBreakRemoved(Sender: TObject; ANumber: Integer);
begin
  FRemovedNum := ANumber;
  Inc(FRemovals);
end;

procedure TTestGdb.OnWatchHit(Sender: TObject; ANumber: Integer;
  const AExpression, AOldValue, ANewValue: string);
begin
  FWatchNum := ANumber;
  FWatchExpr := AExpression;
  FWatchOld := AOldValue;
  FWatchNew := ANewValue;
  Inc(FWatchHits);
end;

procedure TTestGdb.OnError(Sender: TObject; const AText: string);
begin
  FErrors := FErrors + AText + LineEnding;
end;

procedure TTestGdb.OnEval(Sender: TObject; const ATag, AValue: string;
  AIsError: Boolean);
begin
  FEvalTag := ATag;
  FEvalValue := AValue;
  FEvalError := AIsError;
end;

procedure TTestGdb.OnVarCreated(Sender: TObject; const ATag, AVarObj,
  ATypeName, AValue: string; ANumChild: Integer);
begin
  FVarTag := ATag;
  FVarObj := AVarObj;
  FVarType := ATypeName;
  FVarValue := AValue;
  FVarNumChild := ANumChild;
end;

procedure TTestGdb.OnVarChildren(Sender: TObject; const ATag: string;
  const AChildren: TLedGdbVarChildren);
var
  i: Integer;
begin
  FKidsTag := ATag;
  SetLength(FKids, Length(AChildren));
  for i := 0 to High(AChildren) do FKids[i] := AChildren[i];
end;

procedure TTestGdb.OnConsole(Sender: TObject; const AText: string);
begin
  FConsole := FConsole + AText;
end;

procedure TTestGdb.OnTarget(Sender: TObject; const AText: string);
begin
  FTargetText := FTargetText + AText;
end;

{ The struct fixture, stopped where its locals are all initialised.  Returns
  False -- with no session -- when there is no toolchain to build it. }
function TTestGdb.StopInStructProgram(out ASession: TLedGdbSession): Boolean;
var
  L: TStringList;
  P: TProcess;
  Src, Bin: string;
begin
  Result := False;
  ASession := nil;
  if not LedGdbAvailable then Exit;
  if FindDefaultExecutablePath('gcc') = '' then Exit;

  Src := IncludeTrailingPathDelimiter(FDir) + 'st.c';
  Bin := IncludeTrailingPathDelimiter(FDir) + 'st';
  L := TStringList.Create;
  try
    L.Add('struct Point { int x; int y; };');
    L.Add('struct Box { struct Point tl; struct Point br; };');
    L.Add('int main(void)');
    L.Add('{');
    L.Add('    struct Box b = { {1,2}, {3,4} };');
    L.Add('    int arr[3] = {7,8,9};');
    L.Add('    int last = b.tl.x + arr[0];');       { line 7 }
    L.Add('    return last;');                       { line 8 -- stop here }
    L.Add('}');
    L.SaveToFile(Src);
  finally
    L.Free;
  end;

  P := TProcess.Create(nil);
  try
    P.Executable := FindDefaultExecutablePath('gcc');
    P.Parameters.Add('-g');
    P.Parameters.Add('-O0');
    P.Parameters.Add(Src);
    P.Parameters.Add('-o');
    P.Parameters.Add(Bin);
    P.Options := [poWaitOnExit, poUsePipes, poStderrToOutPut, poNoConsole];
    P.Execute;
    if (P.ExitStatus <> 0) or (not FileExists(Bin)) then Exit;
  finally
    P.Free;
  end;

  ASession := NewSession;
  ASession.OnVarCreated := @OnVarCreated;
  ASession.OnVarChildren := @OnVarChildren;
  ASession.Start;
  ASession.WaitForState([lgsReady], 10000);
  ASession.SetTarget(Bin);
  ASession.BreakInsert(Src, 8);
  PumpFor(ASession, 500);
  ASession.ExecRun;
  Result := PumpUntilStops(ASession, 1);
end;

{ Compiles one source into the test's directory and answers with the binary's
  path, or '' when there is no toolchain or gcc refused it. }
function TTestGdb.CompileTo(const AName, ASource: string): string;
var
  L: TStringList;
  P: TProcess;
  Src: string;
begin
  Result := '';
  if FindDefaultExecutablePath('gcc') = '' then Exit;
  Src := IncludeTrailingPathDelimiter(FDir) + AName + '.c';
  L := TStringList.Create;
  try
    L.Text := ASource;
    L.SaveToFile(Src);
  finally
    L.Free;
  end;

  P := TProcess.Create(nil);
  try
    P.Executable := FindDefaultExecutablePath('gcc');
    P.Parameters.Add('-g');
    P.Parameters.Add('-O0');
    P.Parameters.Add(Src);
    P.Parameters.Add('-o');
    P.Parameters.Add(IncludeTrailingPathDelimiter(FDir) + AName);
    P.Options := [poWaitOnExit, poUsePipes, poStderrToOutPut, poNoConsole];
    P.Execute;
    if (P.ExitStatus = 0) and
       FileExists(IncludeTrailingPathDelimiter(FDir) + AName) then
      Result := IncludeTrailingPathDelimiter(FDir) + AName;
  finally
    P.Free;
  end;
end;

{ A program with a global that is written and then read, stopped on the line
  before the loop starts -- so a watchpoint can be set on a local as well.

  ASource is handed back because a breakpoint's location is a path, and the
  tests set theirs by line number in this file. }
function TTestGdb.StopInGlobalProgram(out ASession: TLedGdbSession;
  out ASource: string): Boolean;
var
  Bin: string;
begin
  Result := False;
  ASession := nil;
  ASource := '';
  if not LedGdbAvailable then Exit;

  Bin := CompileTo('glob',
    'int g = 0;'#10 +                                   { 1 }
    'int main(void)'#10 +                               { 2 }
    '{'#10 +                                            { 3 }
    '    int i, total = 0;'#10 +                        { 4 }
    '    for (i = 0; i < 5; i++) {'#10 +                 { 5 }
    '        g = i + 1;'#10 +                            { 6 }
    '        total += g;'#10 +                           { 7 }
    '    }'#10 +                                         { 8 }
    '    return total;'#10 +                             { 9 }
    '}'#10);
  if Bin = '' then Exit;
  ASource := IncludeTrailingPathDelimiter(FDir) + 'glob.c';

  ASession := NewSession;
  ASession.Start;
  ASession.WaitForState([lgsReady], 10000);
  ASession.SetTarget(Bin);
  ASession.BreakInsert(ASource, 4);
  PumpFor(ASession, 600);
  ASession.ExecRun;
  Result := PumpUntilStops(ASession, 1);
end;

function TTestGdb.NewSession: TLedGdbSession;
begin
  Result := TLedGdbSession.Create;
  Result.OnStopped := @OnStopped;
  Result.OnBreakAdded := @OnBreakAdded;
  Result.OnBreakRemoved := @OnBreakRemoved;
  Result.OnWatchHit := @OnWatchHit;
  Result.OnError := @OnError;
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

{ --- variable objects: drilling into a struct ------------------------------ }

procedure TTestGdb.VarCreateDescribesAStruct;
var S: TLedGdbSession;
begin
  if not StopInStructProgram(S) then Exit;
  try
    FVarObj := '';
    S.VarCreate('b', 'loc:0');
    PumpFor(S, 2000);
    AssertEquals('answered against its tag', 'loc:0', FVarTag);
    AssertTrue('gdb named a variable object', FVarObj <> '');
    AssertEquals('with the struct''s type', 'struct Box', FVarType);
    AssertEquals('and two fields to drill into', 2, FVarNumChild);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.VarChildrenListsTheFields;
var S: TLedGdbSession;
begin
  if not StopInStructProgram(S) then Exit;
  try
    S.VarCreate('b', 'loc:0');
    PumpFor(S, 2000);
    if FVarObj = '' then Exit;
    SetLength(FKids, 0);
    S.VarChildren(FVarObj, 'k:0');
    PumpFor(S, 2000);
    AssertEquals('answered against its tag', 'k:0', FKidsTag);
    AssertEquals('two fields', 2, Length(FKids));
    AssertEquals('named as written in the struct', 'tl', FKids[0].Expr);
    AssertEquals('and the second', 'br', FKids[1].Expr);
    AssertEquals('each with its type', 'struct Point', FKids[0].TypeName);
    AssertTrue('and a handle to drill further', FKids[0].VarObj <> '');
  finally
    S.Free;
  end;
end;

procedure TTestGdb.AggregateChildrenHaveNoValue;
var S: TLedGdbSession;
begin
  if not StopInStructProgram(S) then Exit;
  try
    S.VarCreate('b', 'loc:0');
    PumpFor(S, 2000);
    if FVarObj = '' then Exit;
    S.VarChildren(FVarObj, 'k:0');
    PumpFor(S, 2000);
    if Length(FKids) < 1 then Exit;
    { --simple-values gives a value only for leaves.  An empty value means
      "expand me", and a reader that treats it as a failure shows nothing
      where a struct should be. }
    AssertEquals('a struct field has no value of its own', '', FKids[0].Value);
    AssertTrue('but says how many children it has', FKids[0].NumChild > 0);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.DrillingTwoLevelsDeepReachesALeaf;
var S: TLedGdbSession; Inner: string;
begin
  if not StopInStructProgram(S) then Exit;
  try
    S.VarCreate('b', 'loc:0');
    PumpFor(S, 2000);
    if FVarObj = '' then Exit;
    S.VarChildren(FVarObj, 'k:0');
    PumpFor(S, 2000);
    if Length(FKids) < 1 then Exit;
    Inner := FKids[0].VarObj;          { b.tl }

    SetLength(FKids, 0);
    S.VarChildren(Inner, 'k:1');
    PumpFor(S, 2000);
    AssertEquals('two members of the inner struct', 2, Length(FKids));
    AssertEquals('x', 'x', FKids[0].Expr);
    { b = { {1,2}, {3,4} } -- so b.tl.x is 1, and at the leaf a value
      finally appears. }
    AssertEquals('whose value is now given', '1', FKids[0].Value);
    AssertEquals('and y', '2', FKids[1].Value);
    AssertEquals('leaves have no children', 0, FKids[0].NumChild);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.ArrayChildrenAreIndexed;
var S: TLedGdbSession;
begin
  if not StopInStructProgram(S) then Exit;
  try
    S.VarCreate('arr', 'loc:1');
    PumpFor(S, 2000);
    if FVarObj = '' then Exit;
    AssertEquals('three elements', 3, FVarNumChild);
    SetLength(FKids, 0);
    S.VarChildren(FVarObj, 'k:2');
    PumpFor(S, 2000);
    AssertEquals('listed as three children', 3, Length(FKids));
    { gdb names array children by subscript, which is what makes an array
      and a struct the same problem. }
    AssertEquals('by index', '0', FKids[0].Expr);
    AssertEquals('with their values', '7', FKids[0].Value);
    AssertEquals('and the last', '9', FKids[2].Value);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.VarCreateBeforeStoppingIsAnswered;
var S: TLedGdbSession;
begin
  if not LedGdbAvailable then Exit;
  S := NewSession;
  S.OnVarCreated := @OnVarCreated;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    FVarTag := '';
    FVarObj := 'not-empty';
    { Answered locally with nothing, so the pane needs one code path. }
    S.VarCreate('whatever', 'loc:9');
    AssertEquals('answered at once', 'loc:9', FVarTag);
    AssertEquals('with no variable object', '', FVarObj);
  finally
    S.Free;
  end;
end;

{ --- what to ask about when the pointer rests on something -------------- }

procedure TTestGdb.HoverFindsAPlainIdentifier;
begin
  //                              1234567890123456789
  AssertEquals('mid-word', 'total', LedExpressionAt('    int total = 0;', 11));
  AssertEquals('at its first letter', 'total',
    LedExpressionAt('    int total = 0;', 9));
  AssertEquals('at its last', 'total', LedExpressionAt('    int total = 0;', 13));
end;

procedure TTestGdb.HoverFindsFieldAccess;
begin
  { The whole point of doing more than medit: hovering the y of box.tl.y has
    to ask about box.tl.y, not about y, which is not in scope. }
  AssertEquals('two levels', 'box.tl.y',
    LedExpressionAt('    n = box.tl.y + 1;', 16));
  AssertEquals('one level', 'box.tl',
    LedExpressionAt('    n = box.tl.y + 1;', 14));
  AssertEquals('the root alone', 'box',
    LedExpressionAt('    n = box.tl.y + 1;', 10));
end;

procedure TTestGdb.HoverFindsArrowAccess;
begin
  AssertEquals('through a pointer', 'p->next->value',
    LedExpressionAt('    x = p->next->value;', 22));
  AssertEquals('mixed with a dot', 'a.b->c',
    LedExpressionAt('    y = a.b->c;', 14));
end;

procedure TTestGdb.HoverFindsSubscripts;
begin
  { A subscript is only ever *passed through* on the way left, so the
    positions that matter are the ones after it.  Hovering a closing bracket
    asks nothing, because a bracket is not a word. }
  //                1234567890123456789
  AssertEquals('through a subscript', 'arr[2].x',
    LedExpressionAt('    v = arr[2].x;', 16));
  AssertEquals('two dimensions', 'm[1][2].z',
    LedExpressionAt('    v = m[1][2].z;', 17));
  AssertEquals('a computed subscript', 'a[i+1].n',
    LedExpressionAt('    v = a[i+1].n;', 16));
  AssertEquals('the index is a literal', '',
    LedExpressionAt('    v = arr[2].x;', 13));
  AssertEquals('and the name is just the name', 'arr',
    LedExpressionAt('    v = arr[2].x;', 10));
  AssertEquals('a bracket is not a word', '',
    LedExpressionAt('    v = m[1][2];', 15));
end;

procedure TTestGdb.HoverSkipsKeywordsAndNumbers;
begin
  { Each of these would come back from gdb as an error, and showing it would
    look like a fault rather than a non-question. }
  AssertEquals('a keyword', '', LedExpressionAt('    int total = 0;', 6));
  AssertEquals('return', '', LedExpressionAt('    return sum;', 6));
  AssertEquals('a literal', '', LedExpressionAt('    x = 4200;', 10));
  AssertEquals('but a name with digits in it is fine', 'x2',
    LedExpressionAt('    x2 = 1;', 6));
end;

procedure TTestGdb.HoverOffAWordIsEmpty;
begin
  AssertEquals('on a space', '', LedExpressionAt('    x = 1;', 4));
  AssertEquals('on punctuation', '', LedExpressionAt('    x = 1;', 7));
  AssertEquals('past the end', '', LedExpressionAt('    x = 1;', 99));
  AssertEquals('before the start', '', LedExpressionAt('    x = 1;', 0));
  AssertEquals('an empty line', '', LedExpressionAt('', 1));
  { A qualifier with nothing in front of it is not an expression. }
  AssertEquals('a stray field', 'x', LedExpressionAt('.x', 2));
end;

{ --- conditional breakpoints and run-to-cursor --------------------------- }

{ A loop, so a condition has something to be true on only one turn of it.
  Stops at line 5 -- "total += i;" -- under ACondition, or unconditionally
  when that is empty. }
function TTestGdb.StopInLoopProgram(out ASession: TLedGdbSession;
  const ACondition: string): Boolean;
var
  L: TStringList;
  P: TProcess;
  Bin: string;
begin
  Result := False;
  ASession := nil;
  if not LedGdbAvailable then Exit;
  if FindDefaultExecutablePath('gcc') = '' then Exit;

  FLoopSrc := IncludeTrailingPathDelimiter(FDir) + 'loop.c';
  Bin := IncludeTrailingPathDelimiter(FDir) + 'loop';
  L := TStringList.Create;
  try
    L.Add('int main(void)');                    { 1 }
    L.Add('{');                                 { 2 }
    L.Add('    int i, total = 0;');             { 3 }
    L.Add('    for (i = 0; i < 10; i++) {');    { 4 }
    L.Add('        total += i;');               { 5 }
    L.Add('    }');                             { 6 }
    L.Add('    total = total * 2;');            { 7 }
    L.Add('    return total;');                 { 8 }
    L.Add('}');                                 { 9 }
    L.SaveToFile(FLoopSrc);
  finally
    L.Free;
  end;

  P := TProcess.Create(nil);
  try
    P.Executable := FindDefaultExecutablePath('gcc');
    P.Parameters.Add('-g');
    P.Parameters.Add('-O0');
    P.Parameters.Add(FLoopSrc);
    P.Parameters.Add('-o');
    P.Parameters.Add(Bin);
    P.Options := [poWaitOnExit, poUsePipes, poStderrToOutPut, poNoConsole];
    P.Execute;
    if (P.ExitStatus <> 0) or (not FileExists(Bin)) then Exit;
  finally
    P.Free;
  end;

  ASession := NewSession;
  ASession.Start;
  ASession.WaitForState([lgsReady], 10000);
  ASession.SetTarget(Bin);
  ASession.BreakInsert(FLoopSrc, 5, ACondition);
  PumpFor(ASession, 600);
  ASession.ExecRun;
  Result := PumpUntilStops(ASession, 1);
end;

procedure TTestGdb.ConditionalBreakpointWaitsForItsExpression;
var S: TLedGdbSession; i: Integer; Found: Boolean;
begin
  if not StopInLoopProgram(S, 'i == 7') then Exit;
  try
    { The loop runs ten times and the breakpoint is on the body, so an
      unconditional one would stop on the first turn.  This one must not. }
    S.RequestLocals;
    PumpFor(S, 2000);
    Found := False;
    for i := 0 to High(S.Locals) do
      if S.Locals[i].Name = 'i' then
      begin
        Found := True;
        AssertEquals('stopped on the turn the condition names', '7',
          S.Locals[i].Value);
      end;
    AssertTrue('the loop variable is there', Found);
    for i := 0 to High(S.Locals) do
      if S.Locals[i].Name = 'total' then
        { 0+1+...+6 }
        AssertEquals('and the sum so far proves', '21', S.Locals[i].Value);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.ConditionIsEchoedBack;
var S: TLedGdbSession;
begin
  if not StopInLoopProgram(S, 'i == 3') then Exit;
  try
    { gdb repeats the condition in the reply, which is how the gutter knows
      to draw this one hollow. }
    AssertEquals('the condition comes back on the event', 'i == 3',
      FBreakCond);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.ChangingAConditionTakesEffect;
var S: TLedGdbSession; i: Integer;
begin
  { Set unconditionally, then given a condition before running. }
  if not LedGdbAvailable then Exit;
  if not StopInLoopProgram(S, 'i == 1') then Exit;
  try
    S.BreakCondition(FBreakNum, 'i == 6');
    PumpFor(S, 500);
    S.ExecContinue;
    if not PumpUntilStops(S, 2) then Exit;
    S.RequestLocals;
    PumpFor(S, 2000);
    for i := 0 to High(S.Locals) do
      if S.Locals[i].Name = 'i' then
        AssertEquals('the new condition is the one that stops it', '6',
          S.Locals[i].Value);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.ClearingAConditionMakesItAlwaysFire;
var S: TLedGdbSession; i: Integer;
begin
  if not StopInLoopProgram(S, 'i == 2') then Exit;
  try
    { Cleared, so the very next turn of the loop stops. }
    S.BreakCondition(FBreakNum, '');
    PumpFor(S, 500);
    S.ExecContinue;
    if not PumpUntilStops(S, 2) then Exit;
    S.RequestLocals;
    PumpFor(S, 2000);
    for i := 0 to High(S.Locals) do
      if S.Locals[i].Name = 'i' then
        AssertEquals('it stops on the next turn now', '3',
          S.Locals[i].Value);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.RunToCursorReachesTheLine;
var S: TLedGdbSession; i: Integer;
begin
  if not StopInLoopProgram(S, '') then Exit;
  try
    { With nothing in the way, running to line 7 passes all ten turns of the
      loop in one go -- which is the point of it, as against Continue. }
    S.BreakDelete(FBreakNum);
    PumpFor(S, 500);
    S.ExecUntil(FLoopSrc, 7);
    if not PumpUntilStops(S, 2) then Exit;
    AssertEquals('the reason gdb gives for arriving', 'location-reached',
      FLastReason);
    AssertEquals('on the line asked for', 7, FLastLine);
    S.RequestLocals;
    PumpFor(S, 2000);
    for i := 0 to High(S.Locals) do
      if S.Locals[i].Name = 'total' then
        AssertEquals('having run the entire loop', '45', S.Locals[i].Value);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.RunToCursorSkipsWhatIsBetween;
var S: TLedGdbSession;
begin
  if not StopInLoopProgram(S, '') then Exit;
  try
    { But it does *not* ignore breakpoints, and that is worth pinning down
      because it reads as though it should: -exec-until stops at the first
      breakpoint on the way, so with the one on line 5 still in place a run
      to line 7 gets no further than the next turn of the loop.  Every IDE
      behaves this way, and a run-to-cursor that silently stepped over a
      breakpoint would be worse.  The first version of this test asserted the
      opposite, and gdb corrected it. }
    S.ExecUntil(FLoopSrc, 7);
    if not PumpUntilStops(S, 2) then Exit;
    AssertEquals('a breakpoint on the way still stops it', 'breakpoint-hit',
      FLastReason);
    AssertEquals('on the line the breakpoint is on', 5, FLastLine);
  finally
    S.Free;
  end;
end;

{ --- watchpoints ----------------------------------------------------------- }

procedure TTestGdb.WatchpointStopsWhenTheValueChanges;
var S: TLedGdbSession; Src: string; i: Integer;
begin
  if not StopInGlobalProgram(S, Src) then Exit;
  try
    S.WatchInsert('g');
    PumpFor(S, 500);
    S.ExecContinue;
    if not PumpUntilStops(S, 2) then Exit;
    AssertEquals('gdb says why it stopped', 'watchpoint-trigger', FLastReason);
    { The write is on line 6; gdb reports the line after the store. }
    S.RequestLocals;
    PumpFor(S, 1500);
    for i := 0 to High(S.Locals) do
      if S.Locals[i].Name = 'i' then
        AssertEquals('on the first turn of the loop', '0', S.Locals[i].Value);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.WatchpointReportsWhatItWasAndWhatItIs;
var S: TLedGdbSession; Src: string;
begin
  if not StopInGlobalProgram(S, Src) then Exit;
  try
    S.WatchInsert('g');
    PumpFor(S, 500);
    S.ExecContinue;
    if not PumpUntilStops(S, 2) then Exit;
    AssertEquals('one hit reported', 1, FWatchHits);
    AssertEquals('on the expression asked about', 'g', FWatchExpr);
    { Both values, which is the whole reason a watchpoint beats a breakpoint
      on the line: the old one is gone by the time anything else can look. }
    AssertEquals('what it was', '0', FWatchOld);
    AssertEquals('what it became', '1', FWatchNew);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.ReadWatchpointFiresWithoutAChange;
var S: TLedGdbSession; Src: string;
begin
  if not StopInGlobalProgram(S, Src) then Exit;
  try
    { total += g reads g without writing it, so only a read watchpoint can
      catch it -- the write watchpoint above would not. }
    S.WatchInsert('g', lgbReadWatch);
    PumpFor(S, 500);
    S.ExecContinue;
    if not PumpUntilStops(S, 2) then Exit;
    AssertEquals('a read is its own kind of stop', 'read-watchpoint-trigger',
      FLastReason);
    AssertEquals('reported for the expression', 'g', FWatchExpr);
    { A read has no previous value: gdb sends value={value=...} and nothing
      else, which is what tells the two apart downstream. }
    AssertEquals('with no old value', '', FWatchOld);
    AssertEquals('and the value that was read', '1', FWatchNew);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.WatchpointComesBackAsAWatchpointNotABreakpoint;
var S: TLedGdbSession; Src: string;
begin
  if not StopInGlobalProgram(S, Src) then Exit;
  try
    S.WatchInsert('g');
    PumpFor(S, 800);
    AssertEquals('the kind gdb gave it', Ord(lgbWatch), Ord(FBreakKind));
    AssertEquals('watching what was asked for', 'g', FBreakExpr);
    AssertTrue('and it has a number of its own', FBreakNum > 0);
    { The insert reply carries a number and an expression and nothing else,
      so a listener must not read a condition or a hit count out of it. }
    AssertFalse('the short reply is not a full record', FBreakComplete);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.WatchingALocalBeforeThereIsAFrameIsRefused;
var S: TLedGdbSession;
begin
  if not LedGdbAvailable then Exit;
  if CompileTo('glob2',
    'int main(void) { int total = 0; total++; return total; }'#10) = '' then Exit;
  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    S.SetTarget(IncludeTrailingPathDelimiter(FDir) + 'glob2');
    { A local does not exist until there is a frame, and gdb says so.  The
      message names the expression, because gdb's own does not. }
    S.WatchInsert('total');
    PumpFor(S, 800);
    AssertTrue('the failure is reported: ' + FErrors,
      Pos('cannot watch total', FErrors) > 0);
    AssertTrue('with gdb''s own reason kept',
      Pos('No symbol', FErrors) > 0);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.AWatchpointOutOfScopeIsDeleted;
var S: TLedGdbSession; Src: string; Num: Integer;
begin
  if not StopInGlobalProgram(S, Src) then Exit;
  try
    { A watchpoint on a local dies with the frame it was made in.  gdb stops
      to say so and deletes it, which is the one path where a breakpoint
      disappears without anyone asking. }
    S.WatchInsert('total');
    PumpFor(S, 800);
    Num := FBreakNum;
    AssertTrue('the watchpoint took', Num > 0);
    FRemovals := 0;
    S.ExecContinue;
    { Several stops on the way: the value changes on every turn of the loop. }
    while (FRemovals = 0) and (FStops < 12) do
    begin
      if not PumpUntilStops(S, FStops + 1, 15000) then Break;
      S.ExecContinue;
    end;
    PumpFor(S, 1000);
    AssertTrue('gdb dropped it when the frame went', FRemovals > 0);
    AssertEquals('and named the one it dropped', Num, FRemovedNum);
  finally
    S.Free;
  end;
end;

{ --- enabling and disabling ------------------------------------------------ }

procedure TTestGdb.DisablingABreakpointStopsItFiring;
var S: TLedGdbSession;
begin
  if not StopInLoopProgram(S, '') then Exit;
  try
    { Stopped on the first turn of the loop with a breakpoint on the body.
      Disabled, a continue must reach the end of the program rather than the
      second turn. }
    S.BreakEnable(FBreakNum, False);
    PumpFor(S, 500);
    S.ExecContinue;
    if not PumpUntilStops(S, 2) then Exit;
    AssertTrue('it ran to the end instead of stopping again: ' + FLastReason,
      Pos('exited', FLastReason) > 0);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.EnablingItAgainBringsItBack;
var S: TLedGdbSession; i: Integer;
begin
  if not StopInLoopProgram(S, '') then Exit;
  try
    S.BreakEnable(FBreakNum, False);
    PumpFor(S, 300);
    S.BreakEnable(FBreakNum, True);
    PumpFor(S, 300);
    S.ExecContinue;
    if not PumpUntilStops(S, 2) then Exit;
    AssertEquals('the breakpoint fires again', 'breakpoint-hit', FLastReason);
    S.RequestLocals;
    PumpFor(S, 1500);
    for i := 0 to High(S.Locals) do
      if S.Locals[i].Name = 'i' then
        AssertEquals('on the next turn of the loop', '1', S.Locals[i].Value);
  finally
    S.Free;
  end;
end;

procedure TTestGdb.HitCountsComeBackFromGdb;
var S: TLedGdbSession;
begin
  if not StopInLoopProgram(S, '') then Exit;
  try
    AssertEquals('one hit so far', 1, FBreakHits);
    AssertTrue('and that record was a full one', FBreakComplete);
    AssertTrue('reported as enabled', FBreakEnabled);
    S.ExecContinue;
    if not PumpUntilStops(S, 2) then Exit;
    PumpFor(S, 500);
    { =breakpoint-modified carries times= on every hit, which is where the
      count in the breakpoint list comes from -- there is no other way to
      ask for it short of parsing -break-list. }
    AssertEquals('two after the second stop', 2, FBreakHits);
  finally
    S.Free;
  end;
end;

{ --- making values readable ------------------------------------------------ }

procedure TTestGdb.PaddingIsStrippedFromACharArray;
begin
  { A char[16] holding "item-1" comes back padded to its declared length.
    The padding is the array's size, which is already in its type. }
  AssertEquals('the trailing NULs go', '"item-1"',
    LedTidyValue('"item-1\000\000\000\000\000\000\000\000\000"'));
  AssertEquals('an array of nothing but padding is an empty string', '""',
    LedTidyValue('"\000\000\000"'));
end;

procedure TTestGdb.ACollapsedRunOfNulsGoesToo;
begin
  { Past ten repeats gdb stops spelling them out and says so instead. }
  AssertEquals('the shorthand form goes as well', '"item-1"',
    LedTidyValue('"item-1", ''\000'' <repeats 25 times>'));
  AssertEquals('inside a struct, and the comma with it',
    '{name = "a", value = 3}',
    LedTidyValue('{name = "a", ''\000'' <repeats 14 times>, value = 3}'));
end;

procedure TTestGdb.ANulInTheMiddleIsKept;
begin
  { A NUL between two runs of text is a fact about the buffer, not padding,
    and someone looking at a buffer needs to see it. }
  AssertEquals('an embedded NUL survives', '"a\000b"',
    LedTidyValue('"a\000b"'));
  AssertEquals('and only what trails is taken', '"a\000b"',
    LedTidyValue('"a\000b\000\000"'));
end;

procedure TTestGdb.APlainValueIsLeftAlone;
begin
  AssertEquals('a number', '42', LedTidyValue('42'));
  AssertEquals('a pointer', '0x7fff1234 "text"',
    LedTidyValue('0x7fff1234 "text"'));
  AssertEquals('nothing at all', '', LedTidyValue(''));
end;

procedure TTestGdb.AStructIsBrokenAcrossLines;
var
  S: string;
begin
  S := LedExpandValue('{name = "a", value = 3}');
  AssertTrue('it is more than one line now', Pos(LineEnding, S) > 0);
  AssertTrue('with the first field on its own: ' + S,
    Pos('name = "a",' + LineEnding, S) > 0);
  AssertTrue('and the second', Pos('value = 3', S) > 0);
  { Nesting indents, so which brace a field belongs to can be seen. }
  S := LedExpandValue('{a = {b = 1}}');
  AssertTrue('a nested field is indented further: ' + S,
    Pos(LineEnding + '    b = 1', S) > 0);
end;

procedure TTestGdb.StringsWithBracesInThemAreNotSplit;
var
  S: string;
begin
  { A comma or a brace inside a string is text, and splitting on it would
    break the string across lines in the middle of a word. }
  S := LedExpandValue('{msg = "a, b {c}"}');
  AssertTrue('the string stays whole: ' + S, Pos('"a, b {c}"', S) > 0);
end;

procedure TTestGdb.AHugeValueIsCutOff;
var
  i: Integer;
  Big, S: string;
begin
  Big := '{';
  for i := 1 to 200 do Big := Big + Format('f%d = %d, ', [i, i]);
  Big := Big + 'last = 0}';
  S := LedExpandValue(Big, 10);
  { A tooltip taller than the screen is no more use than one line. }
  AssertTrue('it stops', Pos('...', S) > 0);
  AssertTrue('well short of the whole thing', Length(S) < Length(Big));
end;

procedure TTestGdb.RealGdbValuesComeOutReadable;
var
  S: TLedGdbSession;
  Src, Bin: string;
begin
  { Against gdb rather than against a string I wrote: the padding is only
    worth stripping if it is the shape gdb actually produces. }
  if not LedGdbAvailable then Exit;
  Bin := CompileTo('pad',
    'struct Item { char name[16]; int value; };'#10 +
    'int main(void)'#10 +
    '{'#10 +
    '    struct Item it = { "item-1", 7 };'#10 +
    '    return it.value;'#10 +                    { line 5 }
    '}'#10);
  if Bin = '' then Exit;
  Src := IncludeTrailingPathDelimiter(FDir) + 'pad.c';

  S := NewSession;
  try
    S.Start;
    S.WaitForState([lgsReady], 10000);
    S.SetTarget(Bin);
    S.BreakInsert(Src, 5);
    PumpFor(S, 600);
    S.ExecRun;
    if not PumpUntilStops(S, 1) then Exit;
    S.Evaluate('it.name', 't');
    PumpFor(S, 1500);
    AssertTrue('gdb really does pad it: ' + FEvalValue,
      Pos('\000', FEvalValue) > 0);
    AssertEquals('and it comes out clean', '"item-1"',
      LedTidyValue(FEvalValue));
  finally
    S.Free;
  end;
end;

initialization
  RegisterTest(TTestGdb);

end.
