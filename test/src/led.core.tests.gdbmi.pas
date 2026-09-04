{ led - a light editor.  The GDB/MI reader.

  Fixtures are real lines from `gdb --interpreter=mi3`, not invented ones. }
unit Led.Core.Tests.GdbMI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Led.Core.GdbMI;

type
  TTestGdbMI = class(TTestCase)
  published
    procedure PromptIsRecognised;
    procedure BlankLineIsHarmless;
    procedure SimpleDone;
    procedure DoneWithToken;
    procedure ErrorCarriesItsMessage;
    procedure MessageKeepsEmbeddedQuotes;
    procedure ExecRunning;
    procedure StoppedAtABreakpoint;
    procedure StoppedGivesTheSourcePosition;
    procedure NotifyRecord;
    procedure ConsoleStream;
    procedure LogAndTargetStreams;
    procedure EscapesAreUndone;
    procedure OctalEscapes;
    procedure NestedTupleAndList;
    procedure StackIsAListOfRepeatedNames;
    procedure EmptyTupleAndList;
    procedure MissingPathYieldsDefault;
    procedure IntReadsNumbers;
    procedure UnknownLineIsKept;
    procedure QuotingRoundTrips;
    procedure BreakpointTable;
  end;

implementation

{ --- shape --------------------------------------------------------------- }

procedure TTestGdbMI.PromptIsRecognised;
var R: TLedMIRecord;
begin
  R := LedMIParse('(gdb) ');
  try
    AssertTrue('the prompt is its own kind', R.Kind = mirPrompt);
  finally R.Free; end;
end;

procedure TTestGdbMI.BlankLineIsHarmless;
var R: TLedMIRecord;
begin
  R := LedMIParse('');
  try
    AssertTrue('an empty line parses to something', R <> nil);
  finally R.Free; end;
end;

procedure TTestGdbMI.SimpleDone;
var R: TLedMIRecord;
begin
  R := LedMIParse('^done');
  try
    AssertTrue('a result record', R.Kind = mirResult);
    AssertEquals('done', 'done', R.Class_);
    AssertEquals('no token', -1, R.Token);
  finally R.Free; end;
end;

procedure TTestGdbMI.DoneWithToken;
var R: TLedMIRecord;
begin
  { The token is how a reply is matched to the command that asked. }
  R := LedMIParse('0000000012^done,value="42"');
  try
    AssertEquals('the token comes back', 12, R.Token);
    AssertEquals('and the payload', '42', R.Results.Str('value'));
  finally R.Free; end;
end;

procedure TTestGdbMI.ErrorCarriesItsMessage;
var R: TLedMIRecord;
begin
  R := LedMIParse('^error,msg="No symbol table is loaded."');
  try
    AssertEquals('error', 'error', R.Class_);
    AssertEquals('the message', 'No symbol table is loaded.',
      R.Results.Str('msg'));
  finally R.Free; end;
end;

procedure TTestGdbMI.MessageKeepsEmbeddedQuotes;
var R: TLedMIRecord;
begin
  { The case that breaks a reader which finds the closing quote first. }
  R := LedMIParse('^error,msg="No symbol \"nosuch\" in current context."');
  try
    AssertEquals('the whole message survives',
      'No symbol "nosuch" in current context.', R.Results.Str('msg'));
  finally R.Free; end;
end;

procedure TTestGdbMI.ExecRunning;
var R: TLedMIRecord;
begin
  R := LedMIParse('*running,thread-id="all"');
  try
    AssertTrue('an exec record', R.Kind = mirExec);
    AssertEquals('running', 'running', R.Class_);
    AssertEquals('all', 'all', R.Results.Str('thread-id'));
  finally R.Free; end;
end;

procedure TTestGdbMI.StoppedAtABreakpoint;
var R: TLedMIRecord;
begin
  R := LedMIParse('*stopped,reason="breakpoint-hit",disp="keep",bkptno="1",' +
                  'thread-id="1",stopped-threads="all",core="3"');
  try
    AssertTrue('an exec record', R.Kind = mirExec);
    AssertEquals('stopped', 'stopped', R.Class_);
    AssertEquals('the reason', 'breakpoint-hit', R.Results.Str('reason'));
    AssertEquals('which breakpoint', 1, R.Results.Int('bkptno'));
  finally R.Free; end;
end;

procedure TTestGdbMI.StoppedGivesTheSourcePosition;
var R: TLedMIRecord;
begin
  R := LedMIParse('*stopped,reason="breakpoint-hit",bkptno="1",frame={' +
                  'addr="0x000000000040113a",func="main",args=[],' +
                  'file="hello.c",fullname="/tmp/hello.c",line="6",' +
                  'arch="i386:x86-64"},thread-id="1"');
  try
    { The dotted path is what the session layer will use to move the caret. }
    AssertEquals('the file', '/tmp/hello.c', R.Results.Str('frame.fullname'));
    AssertEquals('the line', 6, R.Results.Int('frame.line'));
    AssertEquals('the function', 'main', R.Results.Str('frame.func'));
  finally R.Free; end;
end;

procedure TTestGdbMI.NotifyRecord;
var R: TLedMIRecord;
begin
  R := LedMIParse('=thread-group-added,id="i1"');
  try
    AssertTrue('a notify record', R.Kind = mirNotify);
    AssertEquals('thread-group-added', 'thread-group-added', R.Class_);
    AssertEquals('i1', 'i1', R.Results.Str('id'));
  finally R.Free; end;
end;

procedure TTestGdbMI.ConsoleStream;
var R: TLedMIRecord;
begin
  R := LedMIParse('~"Reading symbols from a.out...\n"');
  try
    AssertTrue('a console record', R.Kind = mirConsole);
    AssertEquals('text, unescaped', 'Reading symbols from a.out...' + #10,
      R.Text);
  finally R.Free; end;
end;

procedure TTestGdbMI.LogAndTargetStreams;
var R: TLedMIRecord;
begin
  R := LedMIParse('&"warning: something\n"');
  try
    AssertTrue('a log record', R.Kind = mirLog);
  finally R.Free; end;
  { @ is the inferior's own stdout, which the console pane must show. }
  R := LedMIParse('@"hello from the program\n"');
  try
    AssertTrue('a target record', R.Kind = mirTarget);
    AssertEquals('its text', 'hello from the program' + #10, R.Text);
  finally R.Free; end;
end;

{ --- escaping ------------------------------------------------------------- }

procedure TTestGdbMI.EscapesAreUndone;
begin
  AssertEquals('newline', 'a' + #10 + 'b', LedMIUnescape('a\nb'));
  AssertEquals('tab', 'a' + #9 + 'b', LedMIUnescape('a\tb'));
  AssertEquals('quote', 'a"b', LedMIUnescape('a\"b'));
  AssertEquals('backslash', 'a\b', LedMIUnescape('a\\b'));
end;

procedure TTestGdbMI.OctalEscapes;
var R: TLedMIRecord;
begin
  { \303\251 is UTF-8 for e-acute; gdb spells non-ASCII bytes this way. }
  R := LedMIParse('~"caf\303\251\n"');
  try
    AssertEquals('the bytes come through',
      'caf' + Chr($C3) + Chr($A9) + #10, R.Text);
  finally R.Free; end;
end;

{ --- structure ------------------------------------------------------------ }

procedure TTestGdbMI.NestedTupleAndList;
var R: TLedMIRecord; V: TLedMIValue;
begin
  R := LedMIParse('^done,frame={level="0",args=[{name="argc",value="1"},' +
                  '{name="argv",value="0x7fff"}]}');
  try
    V := R.Results.Find('frame.args');
    AssertTrue('args is there', V <> nil);
    AssertTrue('and is a list', V.Kind = mivList);
    AssertEquals('with two entries', 2, V.Count);
    AssertEquals('first name', 'argc', V[0].Str('name'));
    AssertEquals('second value', '0x7fff', V[1].Str('value'));
  finally R.Free; end;
end;

procedure TTestGdbMI.StackIsAListOfRepeatedNames;
var R: TLedMIRecord; V: TLedMIValue; i, n: Integer;
begin
  { The shape a tuple-like reader loses: every element is called "frame". }
  R := LedMIParse('^done,stack=[frame={level="0",func="inner",line="4"},' +
                  'frame={level="1",func="middle",line="9"},' +
                  'frame={level="2",func="main",line="14"}]');
  try
    V := R.Results.ByName('stack');
    AssertTrue('stack is there', V <> nil);
    AssertEquals('three frames survive', 3, V.Count);
    n := 0;
    i := V.IndexOfName('frame');
    while i >= 0 do
    begin
      Inc(n);
      i := V.IndexOfName('frame', i + 1);
    end;
    AssertEquals('all three are reachable by name', 3, n);
    AssertEquals('innermost first', 'inner', V[0].Str('func'));
    AssertEquals('outermost last', 'main', V[2].Str('func'));
    AssertEquals('and its line', 14, V[2].Int('line'));
  finally R.Free; end;
end;

procedure TTestGdbMI.EmptyTupleAndList;
var R: TLedMIRecord;
begin
  R := LedMIParse('^done,a={},b=[]');
  try
    AssertTrue('empty tuple', R.Results.ByName('a') <> nil);
    AssertEquals('with nothing in it', 0, R.Results.ByName('a').Count);
    AssertTrue('empty list', R.Results.ByName('b') <> nil);
    AssertEquals('likewise', 0, R.Results.ByName('b').Count);
  finally R.Free; end;
end;

procedure TTestGdbMI.MissingPathYieldsDefault;
var R: TLedMIRecord;
begin
  { A gdb build that omits a field must not take the debugger down. }
  R := LedMIParse('^done');
  try
    AssertEquals('missing gives the default', 'none',
      R.Results.Str('frame.fullname', 'none'));
    AssertEquals('and for integers', -1, R.Results.Int('frame.line'));
    AssertFalse('Has says so', R.Results.Has('frame.line'));
  finally R.Free; end;
end;

procedure TTestGdbMI.IntReadsNumbers;
var R: TLedMIRecord;
begin
  R := LedMIParse('^done,n="17",bad="abc"');
  try
    AssertEquals('a number', 17, R.Results.Int('n'));
    AssertEquals('a non-number falls back', 99, R.Results.Int('bad', 99));
  finally R.Free; end;
end;

procedure TTestGdbMI.UnknownLineIsKept;
var R: TLedMIRecord;
begin
  { gdb prints banners and warnings that are not MI at all. }
  R := LedMIParse('GNU gdb (Ubuntu 12.1) 12.1');
  try
    AssertTrue('unknown kind', R.Kind = mirUnknown);
    AssertEquals('but the text is kept', 'GNU gdb (Ubuntu 12.1) 12.1', R.Text);
  finally R.Free; end;
end;

procedure TTestGdbMI.QuotingRoundTrips;
var R: TLedMIRecord;
begin
  AssertEquals('a plain path', '"/tmp/a.c"', LedMIQuote('/tmp/a.c'));
  AssertEquals('a space', '"/tmp/my file.c"', LedMIQuote('/tmp/my file.c'));
  AssertEquals('a quote', '"say \"hi\""', LedMIQuote('say "hi"'));
  { What we quote, gdb echoes back, and we must read it as we wrote it. }
  R := LedMIParse('^done,f=' + LedMIQuote('/tmp/a b"c.c'));
  try
    AssertEquals('round trip', '/tmp/a b"c.c', R.Results.Str('f'));
  finally R.Free; end;
end;

procedure TTestGdbMI.BreakpointTable;
var R: TLedMIRecord; V: TLedMIValue;
begin
  R := LedMIParse('^done,bkpt={number="1",type="breakpoint",disp="keep",' +
                  'enabled="y",addr="0x0000000000401136",func="main",' +
                  'file="hello.c",fullname="/tmp/hello.c",line="5",' +
                  'thread-groups=["i1"],times="0",original-location="hello.c:5"}');
  try
    AssertEquals('the number gdb gave it', 1, R.Results.Int('bkpt.number'));
    AssertEquals('the resolved line', 5, R.Results.Int('bkpt.line'));
    AssertEquals('and file', '/tmp/hello.c', R.Results.Str('bkpt.fullname'));
    AssertEquals('enabled', 'y', R.Results.Str('bkpt.enabled'));
    V := R.Results.Find('bkpt.thread-groups');
    AssertTrue('a plain list of strings', (V <> nil) and (V.Kind = mivList));
    AssertEquals('with one element', 1, V.Count);
    AssertEquals('i1', 'i1', V[0].Text);
  finally R.Free; end;
end;

initialization
  RegisterTest(TTestGdbMI);

end.
