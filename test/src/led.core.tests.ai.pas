// led - a lightweight editor.  Tests for the part of the AI pane that has no
// model behind it.
//
// Building a prompt and reading an answer back are where this feature is won
// or lost.  A model told badly answers a proof-reading request with
// "Certainly!  Here is the corrected text:" and three backticks, which is a
// correct answer and an unusable one -- and if that reply is pasted into
// somebody's file verbatim, the feature has damaged their work rather than
// helped it.
//
// None of that needs a model, a socket or a subprocess, so none of these
// tests has one.

unit Led.Core.Tests.AI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, fpcunit, testregistry,
  Led.Core.AI;

type
  TTestAI = class(TTestCase)
  private
    function Req(const AInstruction, AContext: string;
      ATask: TLedAITask = laskChat): TLedAIRequest;
  published
    { the prompt }
    procedure AChatTurnIsJustWhatWasTyped;
    procedure ATransformCarriesTheTextItIsToChange;
    procedure TheInstructionComesBeforeTheText;
    procedure TheFenceIsLongerThanAnythingInsideIt;
    procedure AnOrdinaryTextGetsTheOrdinaryFence;
    procedure TheFenceNamesTheLanguage;
    procedure TextWithNoNewlineAtTheEndStillClosesItsFence;
    procedure TheFileIsNamedWhenThereIsAName;

    { what the model is told it is for }
    procedure AReplacementTaskAsksForTheTextAndNothingElse;
    procedure ATaskThatExplainsDoesNotAskForAReplacement;
    procedure EveryTaskHasWordsOfItsOwn;
    procedure OnlyATransformIsMeantToGoBack;
    procedure AQuestionAboutNothingReplacesNothing;

    { how much is sent }
    procedure TextTooBigIsCutAtALineBoundary;
    procedure TextThatFitsIsNotTouched;

    { reading the answer back }
    procedure PlainProseComesBackAsItWas;
    procedure InlineBackticksAreNotAFence;
    procedure AFencedAnswerLosesItsFence;
    procedure ALanguageTagIsNotPartOfTheAnswer;
    procedure ThePreambleAModelWritesIsDropped;
    procedure ChatterAfterTheFenceGoesToo;
    procedure APreambleMayBeginWithAnInlineSpan;
    procedure AnUnterminatedFenceKeepsWhatArrived;
    procedure TwoFencesAreLeftAlone;
    procedure AFenceInsideALongerFenceSurvives;
    procedure TildeFencesCountToo;
    procedure WindowsLineEndingsDoNotDefeatIt;
    procedure AnIndentedFenceIsStillAFence;

    { the conversation }
    procedure WhatWasSaidComesBackInOrder;
    procedure TrimmingDropsTheOldestTurnFirst;
    procedure TrimmingNeverDropsTheQuestionBeingAsked;
  end;

implementation

function TTestAI.Req(const AInstruction, AContext: string;
  ATask: TLedAITask): TLedAIRequest;
begin
  Result := Default(TLedAIRequest);
  Result.Task := ATask;
  Result.Instruction := AInstruction;
  Result.Context := AContext;
end;

{ ----- the prompt ------------------------------------------------------- }

procedure TTestAI.AChatTurnIsJustWhatWasTyped;
begin
  { Ceremony around a conversational question makes the answers worse. }
  AssertEquals('nothing added', 'what does poUsePipes do?',
    LedAIBuildPrompt(Req('what does poUsePipes do?', '')));
end;

procedure TTestAI.ATransformCarriesTheTextItIsToChange;
var
  Built: string;
begin
  Built := LedAIBuildPrompt(Req('proof-read this', 'teh cat sat'));
  AssertTrue('the instruction is in it', Pos('proof-read this', Built) > 0);
  AssertTrue('and so is the text, as it stands',
    Pos('teh cat sat', Built) > 0);
end;

procedure TTestAI.TheInstructionComesBeforeTheText;
var
  Built: string;
begin
  { A model reading the text first has already started answering by the time
    it is told what to do. }
  Built := LedAIBuildPrompt(Req('proof-read this', 'teh cat sat'));
  AssertTrue('the instruction is first',
    Pos('proof-read this', Built) < Pos('teh cat sat', Built));
end;

procedure TTestAI.TheFenceIsLongerThanAnythingInsideIt;
var
  R: TLedAIRequest;
  Built, Fence: string;
  At, Count: Integer;
begin
  { A file with a code block in it is the ordinary case.  A three-backtick
    fence around one ends the block in the wrong place, and the model is
    then rewriting half the text it was given. }
  R := Req('proof-read this', 'a paragraph' + LineEnding +
    '````' + LineEnding + 'code' + LineEnding + '````' + LineEnding);
  Built := LedAIBuildPrompt(R);

  Fence := StringOfChar('`', 5);
  AssertTrue('the fence is longer than the one in the text',
    Pos(Fence, Built) > 0);

  Count := 0;
  At := Pos(Fence, Built);
  while At > 0 do
  begin
    Inc(Count);
    At := PosEx(Fence, Built, At + Length(Fence));
  end;
  AssertEquals('it opens once and closes once', 2, Count);
end;

procedure TTestAI.AnOrdinaryTextGetsTheOrdinaryFence;
begin
  AssertEquals('three backticks', '```', LedAIFence('nothing special here'));
  AssertEquals('an inline span does not lengthen it', '```',
    LedAIFence('call `Poll` often'));
end;

procedure TTestAI.TheFenceNamesTheLanguage;
var
  R: TLedAIRequest;
begin
  { "Comment this code" cannot know it is Pascal unless it is told. }
  R := Req('add comments', 'begin end.', laskComment);
  R.Language := 'pascal';
  AssertTrue('the fence carries the language',
    Pos('```pascal', LedAIBuildPrompt(R)) > 0);
end;

procedure TTestAI.TextWithNoNewlineAtTheEndStillClosesItsFence;
var
  Built: string;
begin
  { A selection almost never ends on a line break. }
  Built := LedAIBuildPrompt(Req('proof-read this', 'no newline here'));
  AssertTrue('the closing fence is on a line of its own',
    Pos('here' + LineEnding + '```', Built) > 0);
end;

procedure TTestAI.TheFileIsNamedWhenThereIsAName;
var
  R: TLedAIRequest;
begin
  R := Req('proof-read this', 'some words');
  R.ContextName := 'notes.md';
  AssertTrue('the prompt says where it came from',
    Pos('notes.md', LedAIBuildPrompt(R)) > 0);
end;

{ ----- what the model is told it is for --------------------------------- }

procedure TTestAI.AReplacementTaskAsksForTheTextAndNothingElse;
var
  S: string;
begin
  S := LowerCase(LedAITaskSystem(laskProofread));
  AssertTrue('it says no commentary', Pos('commentary', S) > 0);
  AssertTrue('and no fence', Pos('fence', S) > 0);
  AssertTrue('and says where the reply is going', Pos('in place of', S) > 0);
end;

procedure TTestAI.ATaskThatExplainsDoesNotAskForAReplacement;
var
  S: string;
begin
  { Explain returns prose about the text.  Telling it its answer will be
    pasted over the text would be a lie, and models act on it. }
  S := LowerCase(LedAITaskSystem(laskExplain));
  AssertTrue('nothing about replacing anything', Pos('in place of', S) = 0);
end;

procedure TTestAI.EveryTaskHasWordsOfItsOwn;
var
  T: TLedAITask;
  Seen: TStringList;
begin
  Seen := TStringList.Create;
  try
    for T := Low(TLedAITask) to High(TLedAITask) do
    begin
      if T = laskCustom then Continue;   // the reader's own wording
      AssertTrue(LedAITaskName(T) + ' has a name',
        LedAITaskName(T) <> '');
      AssertTrue(LedAITaskName(T) + ' says what it is for',
        LedAITaskSystem(T) <> '');
      AssertEquals(LedAITaskName(T) + ' does not borrow another task''s words',
        -1, Seen.IndexOf(LedAITaskSystem(T)));
      Seen.Add(LedAITaskSystem(T));
    end;
  finally
    Seen.Free;
  end;
end;

procedure TTestAI.OnlyATransformIsMeantToGoBack;
begin
  AssertTrue('proof-reading is', LedAIReplaces(laskProofread, True));
  AssertTrue('rewriting is', LedAIReplaces(laskRewrite, True));
  AssertTrue('commenting code is', LedAIReplaces(laskComment, True));
  { Prose about a paragraph is not a replacement for it.  Offering to paste
    it over the paragraph is offering to replace somebody's text with a
    description of it. }
  AssertFalse('explaining is not', LedAIReplaces(laskExplain, True));
  AssertFalse('summarising is not', LedAIReplaces(laskSummarise, True));
  AssertFalse('and a conversation is not', LedAIReplaces(laskChat, True));
end;

procedure TTestAI.AQuestionAboutNothingReplacesNothing;
begin
  { Nothing was sent, so there is nowhere for an answer to go. }
  AssertFalse('nothing attached, nothing to replace',
    LedAIReplaces(laskProofread, False));
  AssertFalse('', LedAIReplaces(laskRewrite, False));
end;

{ ----- how much is sent ------------------------------------------------- }

procedure TTestAI.TextTooBigIsCutAtALineBoundary;
var
  Big, Cut, Last: string;
  i: Integer;
  WasCut: Boolean;
begin
  Big := '';
  for i := 1 to 5000 do
    Big := Big + Format('line %d', [i]) + #10;

  Cut := LedAICutContext(Big, 4096, WasCut);
  AssertTrue('it was cut', WasCut);
  AssertTrue('to within the limit', Length(Cut) <= 4096);
  AssertTrue('and something is left', Length(Cut) > 0);

  { The point of cutting at a line: the last thing sent is a whole line, not
    the first half of one.  Half of a fence, or of a table row, makes
    nonsense of everything the model does with it. }
  AssertEquals('it ends on a line boundary', #10, Cut[Length(Cut)]);
  i := Length(Cut) - 1;
  while (i > 0) and (Cut[i] <> #10) do Dec(i);
  Last := Copy(Cut, i + 1, Length(Cut) - i - 1);
  AssertTrue('and the last line is whole: ' + Last,
    (Copy(Last, 1, 5) = 'line ') and (StrToIntDef(Copy(Last, 6, 9), -1) > 0));
end;

procedure TTestAI.TextThatFitsIsNotTouched;
var
  WasCut: Boolean;
begin
  AssertEquals('handed over as it stands', 'a short file'#10,
    LedAICutContext('a short file'#10, 4096, WasCut));
  AssertFalse('and it says so', WasCut);
end;

{ ----- reading the answer back ------------------------------------------ }

procedure TTestAI.PlainProseComesBackAsItWas;
begin
  AssertEquals('unchanged', 'The cat sat on the mat.',
    LedAIUnfence('The cat sat on the mat.'));
end;

procedure TTestAI.InlineBackticksAreNotAFence;
begin
  { Stripping these would eat the model's own words. }
  AssertEquals('kept', 'Call `Poll` from a timer.',
    LedAIUnfence('Call `Poll` from a timer.'));
end;

procedure TTestAI.AFencedAnswerLosesItsFence;
begin
  AssertEquals('what was inside it', 'the cat sat',
    LedAIUnfence('```'#10'the cat sat'#10'```'));
end;

procedure TTestAI.ALanguageTagIsNotPartOfTheAnswer;
begin
  AssertEquals('the tag went with the fence', 'begin end.',
    LedAIUnfence('```pascal'#10'begin end.'#10'```'));
end;

procedure TTestAI.ThePreambleAModelWritesIsDropped;
begin
  { The single commonest way a model disobeys "reply with the text only". }
  AssertEquals('only the text', 'The cat sat on the mat.',
    LedAIUnfence('Certainly!  Here is the corrected text:'#10#10 +
      '```'#10'The cat sat on the mat.'#10'```'));
end;

procedure TTestAI.ChatterAfterTheFenceGoesToo;
begin
  AssertEquals('only the text', 'The cat sat.',
    LedAIUnfence('Here you go:'#10'```'#10'The cat sat.'#10'```'#10 +
      'I fixed the spelling of "cat".'));
end;

procedure TTestAI.APreambleMayBeginWithAnInlineSpan;
begin
  { A line that starts with a backtick is not a fence -- a fence is three of
    them.  Getting that wrong swallows the answer instead of the preamble:
    the first line becomes the opener, the real opener becomes its closer,
    and what is handed back is the nothing in between. }
  AssertEquals('the fenced part is still the answer', 'The cat sat.',
    LedAIUnfence('`cat` was misspelled:'#10 +
      '```'#10'The cat sat.'#10'```'));
end;

procedure TTestAI.AnUnterminatedFenceKeepsWhatArrived;
begin
  { A reply stopped part way.  What arrived is still the answer; the
    delimiter in front of it is certainly not. }
  AssertEquals('what arrived', 'half a sen',
    LedAIUnfence('```'#10'half a sen'));
end;

procedure TTestAI.TwoFencesAreLeftAlone;
var
  Two: string;
begin
  { Two snippets have no single answer to substitute, and picking one of them
    loses the other silently. }
  Two := 'first:'#10'```'#10'one'#10'```'#10'second:'#10'```'#10'two'#10'```';
  AssertEquals('unchanged', Two, LedAIUnfence(Two));
end;

procedure TTestAI.AFenceInsideALongerFenceSurvives;
begin
  { How a model hands back a Markdown file that has code in it. }
  AssertEquals('the inner fences are content',
    '```'#10'code'#10'```',
    LedAIUnfence('````'#10'```'#10'code'#10'```'#10'````'));
end;

procedure TTestAI.TildeFencesCountToo;
begin
  AssertEquals('the other fence Markdown allows', 'the cat sat',
    LedAIUnfence('~~~'#10'the cat sat'#10'~~~'));
end;

procedure TTestAI.WindowsLineEndingsDoNotDefeatIt;
begin
  AssertEquals('the fence is found and the returns are gone', 'the cat sat',
    LedAIUnfence('```'#13#10'the cat sat'#13#10'```'));
end;

procedure TTestAI.AnIndentedFenceIsStillAFence;
begin
  { Markdown allows up to three spaces, and models write them. }
  AssertEquals('found', 'the cat sat',
    LedAIUnfence('  ```'#10'the cat sat'#10'  ```'));
end;

{ ----- the conversation ------------------------------------------------- }

procedure TTestAI.WhatWasSaidComesBackInOrder;
var
  C: TLedAIChat;
begin
  C := TLedAIChat.Create;
  try
    C.Add(larUser, 'first');
    C.Add(larAssistant, 'second');
    AssertEquals('both turns', 2, C.Count);
    AssertEquals('the reader asked first', Ord(larUser), Ord(C.Role(0)));
    AssertEquals('', 'first', C.Text(0));
    AssertEquals('the model answered', Ord(larAssistant), Ord(C.Role(1)));
    AssertEquals('', 'second', C.Text(1));
  finally
    C.Free;
  end;
end;

procedure TTestAI.TrimmingDropsTheOldestTurnFirst;
var
  C: TLedAIChat;
begin
  C := TLedAIChat.Create;
  try
    C.Add(larUser, StringOfChar('a', 100));
    C.Add(larAssistant, StringOfChar('b', 100));
    C.Add(larUser, StringOfChar('c', 100));
    C.TrimTo(150);
    AssertEquals('the oldest went', 1, C.Count);
    AssertEquals('and the newest stayed', StringOfChar('c', 100), C.Text(0));
  finally
    C.Free;
  end;
end;

procedure TTestAI.TrimmingNeverDropsTheQuestionBeingAsked;
var
  C: TLedAIChat;
begin
  { A conversation trimmed to nothing is not a conversation, and the last
    turn is the thing being asked. }
  C := TLedAIChat.Create;
  try
    C.Add(larUser, StringOfChar('a', 1000));
    C.TrimTo(10);
    AssertEquals('it is still there', 1, C.Count);
  finally
    C.Free;
  end;
end;

initialization
  RegisterTest(TTestAI);

end.
