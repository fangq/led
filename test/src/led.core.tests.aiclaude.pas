// led - a lightweight editor.  Tests for driving Claude Code.
//
// The lines below are not invented.  They were taken off a real run of
// claude 2.1.278 -- one plain question, one that used a tool -- and trimmed
// of everything the parser does not read.  That is deliberate: the wire
// format belongs to a program that is updated weekly, and the way to find
// out that it has changed is a check with a fixture beside it, not a pane
// that quietly stops showing anything.
//
// The one that matters most is AWholeMessageIsNotTheAnswerAgain.  With
// --include-partial-messages every word arrives twice, once as it is
// written and once more when the block closes, and an answer that says
// everything twice looks like a model being odd rather than like a bug.

unit Led.Core.Tests.AIClaude;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, {$IFDEF UNIX}BaseUnix,{$ENDIF} fpcunit, testregistry,
  Led.Core.AI, Led.Core.AI.Claude, Led.Core.Prefs;

type
  TTestAIClaude = class(TTestCase)
  private
    FChat: TLedAIChat;
    FAI: TLedAIClaude;
    FDeltas: TStringList;
    FTools: TStringList;
    FDone: Boolean;
    FError: string;
    FResult: TLedAIResult;
    FFake: string;
    FWasPath: string;
    FHadPath: Boolean;
    procedure GotDelta(Sender: TObject; const ADelta: TLedAIDelta);
    procedure GotDone(Sender: TObject; const AResult: TLedAIResult);
    procedure GotError(Sender: TObject; ASeq: Integer; const AWhy: string);
    { Writes a program that answers the way claude does, and points the
      preference at it.  Returns False where a shell script is not a thing
      that can be run. }
    function StandInFor(const ALines: string): Boolean;
    function Answer: string;
    function PumpUntilDone(AMaxMs: Integer): Boolean;
    { What the stand-in was called with, one argument a line. }
    function CalledWith: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  private
    function Args(const ATools: string): TStringList;
    function HasArg(AList: TStringList; const AName: string): Boolean;
    function ArgAfter(AList: TStringList; const AName: string): string;
  published
    { the command line }
    procedure TheCommandLineAsksForAStreamItCanRead;
    procedure WithoutVerboseTheCliRefusesStreamJson;
    procedure ATalkingBackendIsGivenNoToolsAtAll;
    procedure LettingItEditSaysSoOnTheCommandLine;
    procedure FullAccessIsAskedForByName;
    procedure AskIsPlanUntilLedCanPutTheQuestion;
    procedure TheConversationIsResumedWhenThereIsOne;
    procedure TheFirstTurnResumesNothing;
    procedure AModelIsNamedOnlyWhenOneWasChosen;
    procedure WhatItMayDoIsSaidInWords;

    { the stream }
    procedure TheInitLineSaysWhichConversationThisIs;
    procedure APartialMessageIsOneDelta;
    procedure ThinkingComesBackAsThinking;
    procedure ASignatureIsNotWorthShowing;
    procedure AToolIsNoticedButNotSpoken;
    procedure AWholeMessageIsNotTheAnswerAgain;
    procedure TheResultLineEndsTheTurnAndCarriesTheAnswer;
    procedure AFailedResultIsAFailure;
    procedure ALineThatIsNotAnEventIsRefused;
    procedure ARateLimitNoticeIsNotAnEvent;

    { a turn, driven through a real process }
    procedure ATurnIsReadOffTheProgramsOutput;
    procedure TheAnswerIsNotSaidTwice;
    procedure TheSecondTurnCarriesOnTheFirst;
    procedure AProgramThatSaysNothingIsNotAFinishedTurn;
    procedure AConversationIsRememberedEvenWhenTheTurnFails;
  end;

implementation

const
  { Straight from a run: claude -p --output-format stream-json --verbose
    --include-partial-messages --model haiku, asked to reply with one word. }
  LineInit =
    '{"type":"system","subtype":"init","cwd":"/tmp","session_id":' +
    '"d8968b26-1d42-4ba5-a11b-0b64df729296","model":' +
    '"claude-haiku-4-5-20251001","permissionMode":"default"}';
  LineThinkStart =
    '{"type":"stream_event","event":{"type":"content_block_start","index":0,' +
    '"content_block":{"type":"thinking","thinking":"","signature":""}}}';
  LineThinkDelta =
    '{"type":"stream_event","event":{"type":"content_block_delta","index":0,' +
    '"delta":{"type":"thinking_delta","thinking":"the user wants one word"}}}';
  LineSignature =
    '{"type":"stream_event","event":{"type":"content_block_delta","index":0,' +
    '"delta":{"type":"signature_delta","signature":"Er8DCrIBCBEYAipA"}}}';
  LineTextDelta =
    '{"type":"stream_event","event":{"type":"content_block_delta","index":1,' +
    '"delta":{"type":"text_delta","text":"OK"}}}';
  LineAssistant =
    '{"type":"assistant","message":{"role":"assistant","content":' +
    '[{"type":"text","text":"OK"}]}}';
  LineToolStart =
    '{"type":"stream_event","event":{"type":"content_block_start","index":1,' +
    '"content_block":{"type":"tool_use","id":"toolu_01Q4","name":"Read",' +
    '"input":{}}}}';
  LineInputJson =
    '{"type":"stream_event","event":{"type":"content_block_delta","index":1,' +
    '"delta":{"type":"input_json_delta","partial_json":"{\"file_path\":"}}}';
  LineRateLimit =
    '{"type":"rate_limit_event","rate_limit":{"status":"allowed"}}';
  LineResult =
    '{"type":"result","subtype":"success","is_error":false,"result":"OK",' +
    '"duration_ms":1207,"num_turns":1,"session_id":"d8968b26-1d42"}';
  LineFailed =
    '{"type":"result","subtype":"error_during_execution","is_error":true,' +
    '"result":"the model is overloaded","duration_ms":90}';

procedure TTestAIClaude.SetUp;
begin
  FChat := TLedAIChat.Create;
  FDeltas := TStringList.Create;
  FTools := TStringList.Create;
  FDone := False;
  FError := '';
  FHadPath := LedPrefs.HasKey(LedPrefAIClaudePath);
  FWasPath := LedPrefs.GetStr(LedPrefAIClaudePath, '');
end;

procedure TTestAIClaude.TearDown;
begin
  FreeAndNil(FAI);
  FreeAndNil(FChat);
  FreeAndNil(FDeltas);
  FreeAndNil(FTools);
  if FHadPath then LedPrefs.SetStr(LedPrefAIClaudePath, FWasPath)
  else LedPrefs.Remove(LedPrefAIClaudePath);
  if (FFake <> '') and FileExists(FFake) then DeleteFile(FFake);
  if (FFake <> '') and FileExists(FFake + '.args') then
    DeleteFile(FFake + '.args');
end;

function TTestAIClaude.StandInFor(const ALines: string): Boolean;
var
  Script: TStringList;
begin
  Result := False;
  {$IFDEF UNIX}
  FFake := GetTempDir + Format('led-fake-claude-%d.sh', [Random(100000)]);
  Script := TStringList.Create;
  try
    Script.Add('#!/bin/sh');
    { What it was called with, so a check can read the command line that was
      actually used rather than the one that was meant. }
    Script.Add('printf "%s\n" "$@" > "$0.args"');
    { Reads the question and throws it away: what is being checked here is
      the reading of the answer, not the asking. }
    Script.Add('cat > /dev/null');
    Script.Add(ALines);
    Script.SaveToFile(FFake);
  finally
    Script.Free;
  end;
  FpChmod(FFake, &755);
  LedPrefs.SetStr(LedPrefAIClaudePath, FFake);
  FAI := TLedAIClaude.Create(FChat);
  FAI.OnDelta := @GotDelta;
  FAI.OnDone := @GotDone;
  FAI.OnError := @GotError;
  Result := FAI.Available;
  { On a machine with a shell there is no excuse for this failing, and a
    check that quietly does nothing is worse than one that fails: every
    caller below returns early when this is False. }
  AssertTrue('the stand-in can be run', Result);
  {$ENDIF}
end;

function TTestAIClaude.CalledWith: string;
var
  L: TStringList;
begin
  Result := '';
  if not FileExists(FFake + '.args') then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(FFake + '.args');
    Result := L.Text;
  finally
    L.Free;
  end;
end;

procedure TTestAIClaude.GotDelta(Sender: TObject; const ADelta: TLedAIDelta);
begin
  if ADelta.Kind = ladText then FDeltas.Add(ADelta.Text);
  if ADelta.Kind = ladTool then FTools.Add(ADelta.Name);
end;

procedure TTestAIClaude.GotDone(Sender: TObject; const AResult: TLedAIResult);
begin
  FDone := True;
  FResult := AResult;
end;

procedure TTestAIClaude.GotError(Sender: TObject; ASeq: Integer;
  const AWhy: string);
begin
  FError := AWhy;
end;

function TTestAIClaude.Answer: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FDeltas.Count - 1 do
    Result := Result + FDeltas[i];
end;

function TTestAIClaude.PumpUntilDone(AMaxMs: Integer): Boolean;
var
  Started: TDateTime;
begin
  Started := Now;
  repeat
    FAI.Poll;
    if FDone or (FError <> '') then Break;
    Sleep(10);
  until MilliSecondsBetween(Now, Started) > AMaxMs;
  Result := FDone;
end;

function TTestAIClaude.Args(const ATools: string): TStringList;
begin
  Result := LedAIClaudeArgs('', ATools, '');
end;

function TTestAIClaude.HasArg(AList: TStringList; const AName: string): Boolean;
begin
  Result := AList.IndexOf(AName) >= 0;
end;

function TTestAIClaude.ArgAfter(AList: TStringList;
  const AName: string): string;
var
  i: Integer;
begin
  Result := '';
  i := AList.IndexOf(AName);
  if (i >= 0) and (i + 1 < AList.Count) then Result := AList[i + 1];
end;

{ ----- the command line ------------------------------------------------- }

procedure TTestAIClaude.TheCommandLineAsksForAStreamItCanRead;
var
  A: TStringList;
begin
  A := Args('chat');
  try
    AssertTrue('it is asked once and answers', HasArg(A, '-p'));
    AssertEquals('in the format this unit parses', 'stream-json',
      ArgAfter(A, '--output-format'));
    AssertTrue('and a word at a time',
      HasArg(A, '--include-partial-messages'));
  finally
    A.Free;
  end;
end;

procedure TTestAIClaude.WithoutVerboseTheCliRefusesStreamJson;
var
  A: TStringList;
begin
  { Found out the expensive way is a live turn that fails after a minute.
    Found out here, it is a millisecond. }
  A := Args('chat');
  try
    AssertTrue('--verbose is not optional with stream-json',
      HasArg(A, '--verbose'));
  finally
    A.Free;
  end;
end;

procedure TTestAIClaude.ATalkingBackendIsGivenNoToolsAtAll;
var
  A: TStringList;
begin
  { The default, and the whole of what stops an editor that talks to a model
    from being one that rewrites your project because you asked it a
    question. }
  A := Args('chat');
  try
    AssertEquals('no tools', 'none', ArgAfter(A, '--tools'));
    AssertFalse('and no permission mode to argue about',
      HasArg(A, '--permission-mode'));
  finally
    A.Free;
  end;
  A := Args('');
  try
    AssertEquals('and that is what an unset preference means', 'none',
      ArgAfter(A, '--tools'));
  finally
    A.Free;
  end;
end;

procedure TTestAIClaude.LettingItEditSaysSoOnTheCommandLine;
var
  A: TStringList;
begin
  A := Args('edits');
  try
    AssertEquals('files without asking', 'acceptEdits',
      ArgAfter(A, '--permission-mode'));
    AssertFalse('and the tools are not taken away', HasArg(A, '--tools'));
  finally
    A.Free;
  end;
end;

procedure TTestAIClaude.FullAccessIsAskedForByName;
var
  A: TStringList;
begin
  A := Args('full');
  try
    AssertEquals('everything, because the reader said so',
      'bypassPermissions', ArgAfter(A, '--permission-mode'));
  finally
    A.Free;
  end;
end;

procedure TTestAIClaude.AskIsPlanUntilLedCanPutTheQuestion;
var
  A: TStringList;
begin
  { LED cannot yet put a permission question to the reader, and a backend
    that says "ask" and then does not ask would be worse than one that
    refuses. }
  A := Args('ask');
  try
    AssertEquals('it plans and changes nothing', 'plan',
      ArgAfter(A, '--permission-mode'));
  finally
    A.Free;
  end;
end;

procedure TTestAIClaude.TheConversationIsResumedWhenThereIsOne;
var
  A: TStringList;
begin
  { One process per turn only adds up to a conversation because of this. }
  A := LedAIClaudeArgs('', 'chat', 'abc-123');
  try
    AssertEquals('the session is carried over', 'abc-123',
      ArgAfter(A, '--resume'));
  finally
    A.Free;
  end;
end;

procedure TTestAIClaude.TheFirstTurnResumesNothing;
var
  A: TStringList;
begin
  A := LedAIClaudeArgs('', 'chat', '');
  try
    AssertFalse('there is nothing to resume yet', HasArg(A, '--resume'));
  finally
    A.Free;
  end;
end;

procedure TTestAIClaude.AModelIsNamedOnlyWhenOneWasChosen;
var
  A: TStringList;
begin
  A := LedAIClaudeArgs('', 'chat', '');
  try
    AssertFalse('claude picks its own by default', HasArg(A, '--model'));
  finally
    A.Free;
  end;
  A := LedAIClaudeArgs('haiku', 'chat', '');
  try
    AssertEquals('and takes one when it is given', 'haiku',
      ArgAfter(A, '--model'));
  finally
    A.Free;
  end;
end;

procedure TTestAIClaude.WhatItMayDoIsSaidInWords;
var
  i: Integer;
  Said: TStringList;
const
  Kinds: array[0..3] of string = ('chat', 'ask', 'edits', 'full');
  { Not just "they differ": what each one has to get across.  A sentence
    that is merely different from the others can still fail to tell somebody
    that they are about to let a program run commands in their project. }
  MustSay: array[0..3] of string =
    ('cannot', 'changes nothing', 'write', 'commands');
begin
  Said := TStringList.Create;
  try
    for i := 0 to High(Kinds) do
    begin
      AssertTrue(Kinds[i] + ' says what it means, in words a reader can act ' +
        'on: ' + LedAIClaudeToolsSaid(Kinds[i]),
        Pos(MustSay[i], LedAIClaudeToolsSaid(Kinds[i])) > 0);
      AssertEquals(Kinds[i] + ' does not borrow another answer''s words',
        -1, Said.IndexOf(LedAIClaudeToolsSaid(Kinds[i])));
      Said.Add(LedAIClaudeToolsSaid(Kinds[i]));
    end;
    { The one that can run commands must not read like the one that cannot. }
    AssertEquals('only full access mentions commands', 0,
      Pos('commands', LedAIClaudeToolsSaid('chat')));
  finally
    Said.Free;
  end;
end;

{ ----- the stream ------------------------------------------------------- }

procedure TTestAIClaude.TheInitLineSaysWhichConversationThisIs;
var
  E: TLedAIClaudeEvent;
begin
  AssertTrue('it is an event', LedAIClaudeParseEvent(LineInit, E));
  AssertEquals('the session', Ord(lcvInit), Ord(E.Kind));
  AssertEquals('by its id', 'd8968b26-1d42-4ba5-a11b-0b64df729296', E.Name);
end;

procedure TTestAIClaude.APartialMessageIsOneDelta;
var
  E: TLedAIClaudeEvent;
begin
  AssertTrue('it is an event', LedAIClaudeParseEvent(LineTextDelta, E));
  AssertEquals('a piece of the answer', Ord(lcvText), Ord(E.Kind));
  AssertEquals('', 'OK', E.Text);
end;

procedure TTestAIClaude.ThinkingComesBackAsThinking;
var
  E: TLedAIClaudeEvent;
begin
  { Kept apart for the same reason as the local model's: it must never be
    able to replace somebody's selection. }
  AssertTrue('it is an event', LedAIClaudeParseEvent(LineThinkDelta, E));
  AssertEquals('not the answer', Ord(lcvThinking), Ord(E.Kind));
  AssertEquals('', 'the user wants one word', E.Text);
end;

procedure TTestAIClaude.ASignatureIsNotWorthShowing;
var
  E: TLedAIClaudeEvent;
begin
  { A thinking block is signed, and the signature is four hundred characters
    of base64 that is not a word of anybody's answer. }
  AssertFalse('nothing to show', LedAIClaudeParseEvent(LineSignature, E));
  AssertFalse('nor is a tool''s arguments arriving in pieces',
    LedAIClaudeParseEvent(LineInputJson, E));
end;

procedure TTestAIClaude.AToolIsNoticedButNotSpoken;
var
  E: TLedAIClaudeEvent;
begin
  AssertTrue('it is an event', LedAIClaudeParseEvent(LineToolStart, E));
  AssertEquals('a tool', Ord(lcvTool), Ord(E.Kind));
  AssertEquals('named', 'Read', E.Name);
  AssertEquals('and it says nothing into the answer', '', E.Text);
end;

procedure TTestAIClaude.AWholeMessageIsNotTheAnswerAgain;
var
  E: TLedAIClaudeEvent;
begin
  { The important one.  With --include-partial-messages the words arrive as
    deltas and then again in the finished message; reading both gives an
    answer that says everything twice, which reads like a strange model
    rather than like a bug. }
  AssertFalse('the deltas already said it',
    LedAIClaudeParseEvent(LineAssistant, E));
end;

procedure TTestAIClaude.TheResultLineEndsTheTurnAndCarriesTheAnswer;
var
  E: TLedAIClaudeEvent;
begin
  AssertTrue('it is an event', LedAIClaudeParseEvent(LineResult, E));
  AssertEquals('the turn is over', Ord(lcvDone), Ord(E.Kind));
  AssertEquals('with the answer, for a turn whose deltas were missed',
    'OK', E.Text);
  AssertTrue('and what it cost: ' + E.Stats, Pos('1.2', E.Stats) > 0);
  AssertEquals('and the session to carry on with', 'd8968b26-1d42', E.Name);
end;

procedure TTestAIClaude.AFailedResultIsAFailure;
var
  E: TLedAIClaudeEvent;
begin
  { A failure read as a finished turn is an empty answer with nothing said
    about why. }
  AssertTrue('it is an event', LedAIClaudeParseEvent(LineFailed, E));
  AssertEquals('and it failed', Ord(lcvFailed), Ord(E.Kind));
  AssertTrue('in words: ' + E.Text, Pos('overloaded', E.Text) > 0);
end;

procedure TTestAIClaude.ALineThatIsNotAnEventIsRefused;
var
  E: TLedAIClaudeEvent;
begin
  AssertFalse('nothing', LedAIClaudeParseEvent('', E));
  AssertFalse('not json', LedAIClaudeParseEvent('claude: command not found', E));
  AssertFalse('json, but not one of ours',
    LedAIClaudeParseEvent('{"type":"teapot"}', E));
end;

procedure TTestAIClaude.ARateLimitNoticeIsNotAnEvent;
var
  E: TLedAIClaudeEvent;
begin
  { A real line from a real run, and one this has no use for.  A parser that
    fell over on the lines it does not know would break on every version
    that adds one. }
  AssertFalse('passed over', LedAIClaudeParseEvent(LineRateLimit, E));
end;

{ ----- a turn, driven through a real process ---------------------------- }

procedure TTestAIClaude.ATurnIsReadOffTheProgramsOutput;
var
  R: TLedAIRequest;
  Seq: Integer;
begin
  { Everything above reads one line at a time.  This drives the whole of it:
    a program is started, a question goes in on its standard input, the
    answer comes back down a pipe in pieces, and the pieces are reassembled
    into a turn.  A stand-in rather than claude itself, so that the check
    runs on a machine with no account and costs nothing. }
  if not StandInFor(
    'printf ''%s\n'' ''' + LineInit + '''' + LineEnding +
    'printf ''%s\n'' ''' + LineThinkDelta + '''' + LineEnding +
    'printf ''%s\n'' ''' + LineToolStart + '''' + LineEnding +
    'printf ''%s\n'' ''' + LineTextDelta + '''' + LineEnding +
    'printf ''%s\n'' ''' + LineResult + '''') then Exit;

  R := Default(TLedAIRequest);
  R.Instruction := 'say OK';
  AssertTrue('asked: ' + FAI.LastError, FAI.Ask(R, Seq));
  AssertTrue('and it finished: ' + FError, PumpUntilDone(10000));

  AssertEquals('the answer', 'OK', Answer);
  AssertEquals('which is what the turn carries too', 'OK', FResult.Text);
  AssertEquals('the thinking is kept, apart from it',
    'the user wants one word', FResult.Thinking);
  AssertEquals('the tool was noticed', 1, FTools.Count);
  AssertEquals('by name', 'Read', FTools[0]);
  AssertEquals('and the conversation was remembered',
    'd8968b26-1d42', FAI.Session);
end;

procedure TTestAIClaude.TheAnswerIsNotSaidTwice;
var
  R: TLedAIRequest;
  Seq: Integer;
begin
  { The failure this whole unit is most likely to have: --include-partial-
    messages sends the words as deltas and then again in the finished
    message, and an answer that says everything twice reads like a strange
    model rather than like a bug. }
  if not StandInFor(
    'printf ''%s\n'' ''' + LineInit + '''' + LineEnding +
    'printf ''%s\n'' ''' + LineTextDelta + '''' + LineEnding +
    'printf ''%s\n'' ''' + LineAssistant + '''' + LineEnding +
    'printf ''%s\n'' ''' + LineResult + '''') then Exit;

  R := Default(TLedAIRequest);
  R.Instruction := 'say OK';
  AssertTrue('asked', FAI.Ask(R, Seq));
  AssertTrue('finished', PumpUntilDone(10000));
  AssertEquals('once, not twice', 'OK', FResult.Text);
end;

procedure TTestAIClaude.TheSecondTurnCarriesOnTheFirst;
var
  R: TLedAIRequest;
  Seq: Integer;
begin
  { One process per turn is only a conversation because the session id comes
    back out of the first turn and goes into the second. }
  if not StandInFor(
    'printf ''%s\n'' ''' + LineInit + '''' + LineEnding +
    'printf ''%s\n'' ''' + LineTextDelta + '''' + LineEnding +
    'printf ''%s\n'' ''' + LineResult + '''') then Exit;

  R := Default(TLedAIRequest);
  R.Instruction := 'first';
  AssertTrue('asked', FAI.Ask(R, Seq));
  AssertTrue('finished', PumpUntilDone(10000));
  AssertFalse('the first turn had nothing to resume',
    Pos('--resume', CalledWith) > 0);

  FDone := False;
  R.Instruction := 'second';
  AssertTrue('asked again', FAI.Ask(R, Seq));
  AssertTrue('finished again', PumpUntilDone(10000));
  AssertTrue('and it carried the conversation over: ' + CalledWith,
    Pos('--resume', CalledWith) > 0);
  AssertTrue('naming it', Pos('d8968b26-1d42', CalledWith) > 0);
end;

procedure TTestAIClaude.AProgramThatSaysNothingIsNotAFinishedTurn;
var
  R: TLedAIRequest;
  Seq: Integer;
begin
  { claude that is not logged in prints a line to standard error and stops.
    Reading that as an answer would show an empty reply and say nothing
    about why -- and, worse, offer to put it into somebody's file. }
  if not StandInFor('exit 1') then Exit;

  R := Default(TLedAIRequest);
  R.Instruction := 'say OK';
  AssertTrue('asked', FAI.Ask(R, Seq));
  PumpUntilDone(10000);
  AssertFalse('it did not finish', FDone);
  AssertTrue('it said so: ' + FError, FError <> '');
end;

procedure TTestAIClaude.AConversationIsRememberedEvenWhenTheTurnFails;
var
  R: TLedAIRequest;
  Seq: Integer;
begin
  { A turn that fails sends no result line, so the only place the session id
    was ever said is the init line at the start.  Without it, giving up on
    one answer would quietly start a new conversation. }
  if not StandInFor(
    'printf ''%s\n'' ''' + LineInit + '''' + LineEnding +
    'exit 1') then Exit;

  R := Default(TLedAIRequest);
  R.Instruction := 'say OK';
  AssertTrue('asked', FAI.Ask(R, Seq));
  PumpUntilDone(10000);
  AssertFalse('the turn failed', FDone);
  AssertEquals('and the conversation survived it',
    'd8968b26-1d42-4ba5-a11b-0b64df729296', FAI.Session);
end;

initialization
  Randomize;
  RegisterTest(TTestAIClaude);

end.
