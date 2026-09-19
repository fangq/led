// led - a lightweight editor.  Tests for talking to a model on this machine.
//
// Two kinds of test here.  The first needs nothing at all: what goes out in
// a request and what a line of the answer means are free functions, and they
// are where the mistakes that matter live -- a thinking field pasted into
// somebody's selection, a whole conversation re-sent on every turn of a
// transform, a server's refusal read as an empty answer.
//
// The second kind needs a server, so it gets one: an ollama-shaped HTTP
// server on the loopback, which answers /api/chat by dribbling NDJSON out a
// line at a time with a wait in between.  That is the only way to prove the
// thing the whole design exists for -- that the words appear as they are
// written rather than in one lump at the end -- and the only way to prove
// that Stop stops.
//
// One server for the whole unit, started when the first test wants it.  The
// picture-fetching tests found out why: starting and stopping one per test
// hung the run.

unit Led.Core.Tests.AIOllama;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, ssockets, fpcunit, testregistry, fphttpserver,
  fpjson,
  Led.Core.AI, Led.Core.AI.Ollama, Led.Core.Prefs;

type
  TTestAIOllama = class(TTestCase)
  private
    FChat: TLedAIChat;
    FAI: TLedAIOllama;
    FDeltas: TStringList;       // what arrived, and when
    FFirstDelta: TDateTime;
    FDoneAt: TDateTime;
    FDone: Boolean;
    FError: string;
    FResult: TLedAIResult;
    FWasURL: string;
    FHadURL: Boolean;
    FWasModel: string;
    FHadModel: Boolean;
    procedure GotDelta(Sender: TObject; const ADelta: TLedAIDelta);
    procedure GotDone(Sender: TObject; const AResult: TLedAIResult);
    procedure GotError(Sender: TObject; ASeq: Integer; const AWhy: string);
    { Polls until the turn ends or AMaxMs goes by.  Returns how long it took. }
    function PumpUntilDone(AMaxMs: Integer): Integer;
    function Answer: string;
    procedure PointAtTheFakeServer(APort: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { what goes out }
    procedure AQuestionCarriesTheModelAndAsksToStream;
    procedure EveryTurnSendsTheWholeConversation;
    procedure TheSystemMessageIsFirstAndOnlyOnce;
    procedure ATransformDoesNotCarryTheConversation;
    procedure ATransformIsAskedForColderThanAChat;

    { what comes back }
    procedure ATokenLineIsOneDelta;
    procedure TheLastLineSaysItIsDoneAndHowLongItTook;
    procedure AThinkingLineIsNotTheAnswer;
    procedure AnErrorFromTheServerIsSaidInWords;
    procedure ALineThatIsNotAnEventIsRefused;
    procedure TheModelsAreReadInTheOrderGiven;
    procedure ATagsAnswerThatIsNotOneIsRefused;

    { over a real socket }
    procedure TokensArriveBeforeTheAnswerIsFinished;
    procedure StoppingEndsTheTurnAndDropsTheRest;
    procedure StoppingDropsWhatArrivedButWasNotShownYet;
    procedure ASecondQuestionIsRefusedWhileTheFirstIsRunning;
    procedure AnOldConversationIsTrimmedBeforeItIsSent;
    procedure AServerThatRefusesIsReportedNotSwallowed;
    procedure AServerThatIsNotThereIsReportedQuickly;
    procedure ModelsAreListedFromTheServer;
  end;

implementation

{ ----- the fake ollama -------------------------------------------------- }

const
  FakePort = 18653;
  { Five lines, a tenth of a second apart.  Long enough that "they arrived
    together" and "they arrived as they were written" cannot be confused for
    one another, short enough that the suite does not drag. }
  FakeLines = 5;
  FakeGapMs = 100;

type
  { fphttpserver sends a response body with Socket.CopyFrom, and CopyFrom
    stops at the first short read: "until i < BufferSize", with a buffer of
    128 KiB (rtl/objpas/classes/streams.inc).  So a stream that hands over
    one line at a time -- the obvious way to write a server that dribbles --
    delivers exactly one line and the rest is never sent.

    The headers still go through the framework, so Content-Length and the
    rest are whatever a real response would carry.  Only the body is written
    by hand, a line at a time, which is the whole point of this server.
    Connection is protected, so it is reached the way the notebook pane
    reaches a control's own events: through a descendant declared here. }
  TConnAccess = class(TFPHTTPConnectionResponse)
  public
    function Sock: TSocketStream;
  end;

  TFakeOllama = class(TThread)
  private
    FServer: TFPHttpServer;
    procedure Request(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
  protected
    procedure Execute; override;
  public
    LastBody: string;
    constructor Create;
    procedure Stop;
  end;

var
  GFake: TFakeOllama = nil;

function TConnAccess.Sock: TSocketStream;
begin
  Result := Connection.Socket;
end;

constructor TFakeOllama.Create;
begin
  FreeOnTerminate := False;
  inherited Create(True);
  FServer := TFPHttpServer.Create(nil);
  FServer.Port := FakePort;
  FServer.Threaded := True;
  FServer.OnRequest := @Request;
  Start;
end;

procedure TFakeOllama.Stop;
begin
  { Closes the listening socket and lets the thread go.  Not a WaitFor: a
    thread sitting in accept does not always come back, and waiting for one
    that will not is how a run stops answering -- which is exactly what
    happened here the first time. }
  Terminate;
  try
    FServer.Active := False;
  except
    { Stopping a server that never started is not worth an error. }
  end;
end;

procedure TFakeOllama.Execute;
begin
  try
    FServer.Active := True;
  except
    { The port is busy, or the run has no loopback.  The tests that need it
      say so themselves. }
  end;
end;

procedure TFakeOllama.Request(Sender: TObject;
  var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  Lines: TStringList;
  Sock: TSocketStream;
  Body, Line: string;
  i: Integer;
begin
  LastBody := ARequest.Content;

  if Pos('/api/tags', ARequest.URI) > 0 then
  begin
    AResponse.Content :=
      '{"models":[{"name":"first:latest"},{"name":"second:7b"},' +
      '{"name":"third:27b"}]}';
    AResponse.Code := 200;
    AResponse.SendResponse;
    Exit;
  end;

  if Pos('/api/refuse', ARequest.URI) > 0 then
  begin
    AResponse.Code := 404;
    AResponse.Content := '{"error":"model ''nope'' not found"}';
    AResponse.SendResponse;
    Exit;
  end;

  Lines := TStringList.Create;
  try
    for i := 1 to FakeLines do
      Lines.Add(Format(
        '{"model":"fake","message":{"role":"assistant","content":"tok%d "},' +
        '"done":false}', [i]));
    Lines.Add('{"model":"fake","message":{"role":"assistant","content":""},' +
      '"done":true,"eval_count":42,"total_duration":1500000000}');

    Body := '';
    for i := 0 to Lines.Count - 1 do
      Body := Body + Lines[i] + #10;

    AResponse.Code := 200;
    AResponse.ContentType := 'application/x-ndjson';
    AResponse.ContentLength := Length(Body);
    AResponse.SendHeaders;

    { A line, a wait, a line.  Written straight to the socket for the reason
      in the comment on TConnAccess. }
    Sock := TConnAccess(AResponse).Sock;
    for i := 0 to Lines.Count - 1 do
    begin
      if i > 0 then Sleep(FakeGapMs);
      Line := Lines[i] + #10;
      Sock.WriteBuffer(Line[1], Length(Line));
    end;
  finally
    Lines.Free;
  end;
end;

function FakeServer: TFakeOllama;
begin
  if GFake = nil then
  begin
    GFake := TFakeOllama.Create;
    { Give it a moment to bind before the first request. }
    Sleep(300);
  end;
  Result := GFake;
end;

{ ----- the fixture ------------------------------------------------------ }

procedure TTestAIOllama.SetUp;
begin
  FChat := TLedAIChat.Create;
  FAI := TLedAIOllama.Create(FChat);
  FAI.OnDelta := @GotDelta;
  FAI.OnDone := @GotDone;
  FAI.OnError := @GotError;
  FDeltas := TStringList.Create;
  FDone := False;
  FError := '';
  FFirstDelta := 0;

  { The self-test's rule applies here too: a check must report LED's
    behaviour, not the developer's configuration. }
  FHadURL := LedPrefs.HasKey(LedPrefAIOllamaURL);
  FWasURL := LedPrefs.GetStr(LedPrefAIOllamaURL, '');
  FHadModel := LedPrefs.HasKey(LedPrefAIOllamaModel);
  FWasModel := LedPrefs.GetStr(LedPrefAIOllamaModel, '');
end;

procedure TTestAIOllama.TearDown;
begin
  FAI.Free;
  FChat.Free;
  FDeltas.Free;
  if FHadURL then LedPrefs.SetStr(LedPrefAIOllamaURL, FWasURL)
  else LedPrefs.Remove(LedPrefAIOllamaURL);
  if FHadModel then LedPrefs.SetStr(LedPrefAIOllamaModel, FWasModel)
  else LedPrefs.Remove(LedPrefAIOllamaModel);
end;

procedure TTestAIOllama.PointAtTheFakeServer(APort: Integer);
begin
  FakeServer;
  LedPrefs.SetStr(LedPrefAIOllamaURL, Format('http://127.0.0.1:%d', [APort]));
  LedPrefs.SetStr(LedPrefAIOllamaModel, 'fake');
  FAI.Model := 'fake';
end;

procedure TTestAIOllama.GotDelta(Sender: TObject; const ADelta: TLedAIDelta);
begin
  if FFirstDelta = 0 then FFirstDelta := Now;
  if ADelta.Kind = ladText then FDeltas.Add(ADelta.Text);
end;

procedure TTestAIOllama.GotDone(Sender: TObject; const AResult: TLedAIResult);
begin
  FDone := True;
  FDoneAt := Now;
  FResult := AResult;
end;

procedure TTestAIOllama.GotError(Sender: TObject; ASeq: Integer;
  const AWhy: string);
begin
  FError := AWhy;
  FDone := True;
  FDoneAt := Now;
end;

function TTestAIOllama.PumpUntilDone(AMaxMs: Integer): Integer;
var
  Started: TDateTime;
begin
  Started := Now;
  repeat
    FAI.Poll;
    if FDone or (FError <> '') then Break;
    Sleep(10);
  until MilliSecondsBetween(Now, Started) > AMaxMs;
  Result := MilliSecondsBetween(Now, Started);
end;

function TTestAIOllama.Answer: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FDeltas.Count - 1 do
    Result := Result + FDeltas[i];
end;

{ ----- what goes out ---------------------------------------------------- }

function BodyOf(const AJSON: string): TJSONObject;
var
  D: TJSONData;
begin
  D := GetJSON(AJSON);
  Result := D as TJSONObject;
end;

procedure TTestAIOllama.AQuestionCarriesTheModelAndAsksToStream;
var
  R: TLedAIRequest;
  O: TJSONObject;
begin
  R := Default(TLedAIRequest);
  R.Instruction := 'hello';
  O := BodyOf(LedAIOllamaChatBody('qwen3:27b', FChat, R, False));
  try
    AssertEquals('the model asked for', 'qwen3:27b', O.Get('model', ''));
    AssertTrue('streamed, or nothing appears until the end',
      O.Get('stream', False));
  finally
    O.Free;
  end;
end;

procedure TTestAIOllama.EveryTurnSendsTheWholeConversation;
var
  R: TLedAIRequest;
  O: TJSONObject;
  M: TJSONArray;
begin
  { The server keeps nothing.  A backend that sends only the newest question
    has a model with no memory, and the reader sees it answer as if nothing
    had been said. }
  FChat.Add(larUser, 'first question');
  FChat.Add(larAssistant, 'first answer');
  R := Default(TLedAIRequest);
  R.Instruction := 'second question';

  O := BodyOf(LedAIOllamaChatBody('m', FChat, R, False));
  try
    M := O.Arrays['messages'];
    AssertEquals('system, two turns, and the new question', 4, M.Count);
    AssertEquals('', 'system', TJSONObject(M.Items[0]).Get('role', ''));
    AssertEquals('', 'first question',
      TJSONObject(M.Items[1]).Get('content', ''));
    AssertEquals('', 'first answer',
      TJSONObject(M.Items[2]).Get('content', ''));
    AssertEquals('', 'second question',
      TJSONObject(M.Items[3]).Get('content', ''));
  finally
    O.Free;
  end;
end;

procedure TTestAIOllama.TheSystemMessageIsFirstAndOnlyOnce;
var
  R: TLedAIRequest;
  O: TJSONObject;
  M: TJSONArray;
  i, Count: Integer;
begin
  FChat.Add(larUser, 'one');
  FChat.Add(larAssistant, 'two');
  R := Default(TLedAIRequest);
  R.Instruction := 'three';

  O := BodyOf(LedAIOllamaChatBody('m', FChat, R, False));
  try
    M := O.Arrays['messages'];
    AssertEquals('it is first', 'system',
      TJSONObject(M.Items[0]).Get('role', ''));
    Count := 0;
    for i := 0 to M.Count - 1 do
      if TJSONObject(M.Items[i]).Get('role', '') = 'system' then Inc(Count);
    AssertEquals('and there is one of it', 1, Count);
  finally
    O.Free;
  end;
end;

procedure TTestAIOllama.ATransformDoesNotCarryTheConversation;
var
  R: TLedAIRequest;
  O: TJSONObject;
  M: TJSONArray;
begin
  { Proof-reading a file is not a conversational turn.  Carrying the chat
    with it would re-send the file on every turn after it as well. }
  FChat.Add(larUser, 'an earlier question');
  FChat.Add(larAssistant, 'an earlier answer');
  R := Default(TLedAIRequest);
  R.Task := laskProofread;
  R.Instruction := 'proof-read this';
  R.Context := 'teh cat';
  R.Replaces := True;
  R.Standalone := True;

  O := BodyOf(LedAIOllamaChatBody('m', FChat, R, False));
  try
    M := O.Arrays['messages'];
    AssertEquals('the system message and the question, and nothing else',
      2, M.Count);
    AssertTrue('the text to work on is in it',
      Pos('teh cat', TJSONObject(M.Items[1]).Get('content', '')) > 0);
    AssertEquals('and the conversation is untouched', 2, FChat.Count);
  finally
    O.Free;
  end;
end;

procedure TTestAIOllama.ATransformIsAskedForColderThanAChat;
var
  R: TLedAIRequest;
  Hot, Cold: TJSONObject;
begin
  { A proof-reading that invents a livelier sentence has not proof-read
    anything. }
  R := Default(TLedAIRequest);
  R.Instruction := 'hello';
  Hot := BodyOf(LedAIOllamaChatBody('m', FChat, R, False));
  R.Replaces := True;
  Cold := BodyOf(LedAIOllamaChatBody('m', FChat, R, False));
  try
    AssertTrue('a replacement is the colder of the two',
      Cold.Objects['options'].Get('temperature', 1.0) <
      Hot.Objects['options'].Get('temperature', 1.0));
  finally
    Hot.Free;
    Cold.Free;
  end;
end;

{ ----- what comes back -------------------------------------------------- }

procedure TTestAIOllama.ATokenLineIsOneDelta;
var
  D: TLedAIDelta;
  Final: Boolean;
  Stats, Err: string;
begin
  AssertTrue('it is an event', LedAIOllamaParseLine(
    '{"message":{"role":"assistant","content":"hello "},"done":false}',
    D, Final, Stats, Err));
  AssertEquals('the words', 'hello ', D.Text);
  AssertEquals('as the answer', Ord(ladText), Ord(D.Kind));
  AssertFalse('and not the end of it', Final);
  AssertEquals('with nothing wrong', '', Err);
end;

procedure TTestAIOllama.TheLastLineSaysItIsDoneAndHowLongItTook;
var
  D: TLedAIDelta;
  Final: Boolean;
  Stats, Err: string;
begin
  AssertTrue('it is an event', LedAIOllamaParseLine(
    '{"message":{"content":""},"done":true,"eval_count":42,' +
    '"total_duration":1500000000}', D, Final, Stats, Err));
  AssertTrue('the turn is over', Final);
  AssertTrue('and it says what it cost: ' + Stats, Pos('42', Stats) > 0);
  AssertTrue('in seconds, not nanoseconds: ' + Stats, Pos('1.5', Stats) > 0);
end;

procedure TTestAIOllama.AThinkingLineIsNotTheAnswer;
var
  D: TLedAIDelta;
  Final: Boolean;
  Stats, Err: string;
begin
  { qwen3 thinks out loud.  Its scratchpad must never be able to reach a
    buffer: this is the difference between proof-reading a paragraph and
    replacing it with the model wondering how to proof-read it. }
  AssertTrue('it is an event', LedAIOllamaParseLine(
    '{"message":{"role":"assistant","content":"",' +
    '"thinking":"the user wants"},"done":false}', D, Final, Stats, Err));
  AssertEquals('kept apart from the answer', Ord(ladThinking), Ord(D.Kind));
  AssertEquals('with the words it thought', 'the user wants', D.Text);
end;

procedure TTestAIOllama.AnErrorFromTheServerIsSaidInWords;
var
  D: TLedAIDelta;
  Final: Boolean;
  Stats, Err: string;
begin
  AssertTrue('it is an event', LedAIOllamaParseLine(
    '{"error":"model ''nope'' not found"}', D, Final, Stats, Err));
  AssertTrue('and it is a refusal: ' + Err, Pos('nope', Err) > 0);
end;

procedure TTestAIOllama.ALineThatIsNotAnEventIsRefused;
var
  D: TLedAIDelta;
  Final: Boolean;
  Stats, Err: string;
begin
  { A proxy in front of ollama answers in HTML.  A line of HTML is not a
    failed message; it is not a message. }
  AssertFalse('html', LedAIOllamaParseLine('<html><body>no</body>',
    D, Final, Stats, Err));
  AssertFalse('nothing', LedAIOllamaParseLine('', D, Final, Stats, Err));
  AssertFalse('a number is not an event',
    LedAIOllamaParseLine('42', D, Final, Stats, Err));
end;

procedure TTestAIOllama.TheModelsAreReadInTheOrderGiven;
var
  Names: TStringList;
begin
  Names := TStringList.Create;
  try
    AssertTrue('read', LedAIOllamaParseTags(
      '{"models":[{"name":"a:1"},{"name":"b:2"}]}', Names));
    AssertEquals('both', 2, Names.Count);
    AssertEquals('in order', 'a:1', Names[0]);
    AssertEquals('', 'b:2', Names[1]);
  finally
    Names.Free;
  end;
end;

procedure TTestAIOllama.ATagsAnswerThatIsNotOneIsRefused;
var
  Names: TStringList;
begin
  Names := TStringList.Create;
  try
    AssertFalse('not json', LedAIOllamaParseTags('<html>', Names));
    AssertFalse('json, but not a list of models',
      LedAIOllamaParseTags('{"hello":1}', Names));
  finally
    Names.Free;
  end;
end;

{ ----- over a real socket ----------------------------------------------- }

procedure TTestAIOllama.TokensArriveBeforeTheAnswerIsFinished;
var
  R: TLedAIRequest;
  Seq, Took, Gap: Integer;
begin
  { The whole design is here.  TFPHTTPClient is a blocking client, and the
    reason the words appear as they are written is that it writes what it
    reads into a stream of ours as it goes.  If that ever stopped being
    true, every token would arrive at once, at the end -- which is exactly
    what this measures. }
  PointAtTheFakeServer(FakePort);
  R := Default(TLedAIRequest);
  R.Instruction := 'say something';
  AssertTrue('asked', FAI.Ask(R, Seq));

  Took := PumpUntilDone(20000);
  AssertTrue('it finished: ' + FError, FDone and (FError = ''));
  AssertTrue(Format('several deltas, not one lump (%d)', [FDeltas.Count]),
    FDeltas.Count >= 3);

  Gap := MilliSecondsBetween(FDoneAt, FFirstDelta);
  AssertTrue(Format('the first word came %d ms before the last, of %d ms',
    [Gap, Took]), Gap > (FakeLines - 2) * FakeGapMs);

  AssertEquals('and the answer is all of it', 'tok1 tok2 tok3 tok4 tok5 ',
    Answer);
  AssertEquals('which is what the result carries too',
    'tok1 tok2 tok3 tok4 tok5 ', FResult.Text);
end;

procedure TTestAIOllama.StoppingEndsTheTurnAndDropsTheRest;
var
  R: TLedAIRequest;
  Seq, Started, Waited: Integer;
  Was: Integer;
begin
  PointAtTheFakeServer(FakePort);
  R := Default(TLedAIRequest);
  R.Instruction := 'say something';
  AssertTrue('asked', FAI.Ask(R, Seq));

  { Let a word or two through, then give up on it. }
  Started := 0;
  while (FDeltas.Count < 2) and (Started < 500) do
  begin
    FAI.Poll;
    Sleep(10);
    Inc(Started);
  end;
  AssertTrue('something arrived before stopping', FDeltas.Count >= 1);
  Was := FDeltas.Count;

  FAI.Stop;
  AssertTrue('it is no longer answering', FAI.State <> laiBusy);

  { Everything still coming belongs to a turn nobody is listening to. }
  Waited := 0;
  while (FAI.State = laiStopping) and (Waited < 800) do
  begin
    FAI.Poll;
    Sleep(10);
    Inc(Waited);
  end;

  AssertEquals('and nothing more was shown', Was, FDeltas.Count);
  AssertFalse('the turn never reported itself finished', FDone);
  AssertTrue('the answer is shorter than the whole one',
    Length(Answer) < Length('tok1 tok2 tok3 tok4 tok5 '));

  { And the pane is usable again straight away. }
  AssertTrue('a new question is accepted', FAI.Ask(R, Seq));
end;

procedure TTestAIOllama.StoppingDropsWhatArrivedButWasNotShownYet;
var
  R: TLedAIRequest;
  Seq, Waited: Integer;
begin
  { Stopping cannot depend on the far end noticing.  A request already part
    way through an answer has words on the queue, and more coming, and the
    editor has to be free of them the moment the reader says so -- which is
    what the turn number does, and nothing else can.

    So: let the answer pile up without draining it, then stop, and only then
    look.  Everything queued belongs to the turn that was abandoned. }
  PointAtTheFakeServer(FakePort);
  R := Default(TLedAIRequest);
  R.Instruction := 'say something';
  AssertTrue('asked', FAI.Ask(R, Seq));

  Sleep((FakeLines - 1) * FakeGapMs);     // words arrive; nothing polls
  FAI.Stop;

  Waited := 0;
  while (Waited < 300) do
  begin
    FAI.Poll;
    Sleep(10);
    Inc(Waited, 10);
  end;

  AssertEquals('not one word of it was shown', 0, FDeltas.Count);
  AssertFalse('and it never reported itself finished', FDone);
  AssertTrue('the pane is free', FAI.State = laiIdle);
end;

procedure TTestAIOllama.ASecondQuestionIsRefusedWhileTheFirstIsRunning;
var
  R: TLedAIRequest;
  Seq: Integer;
begin
  PointAtTheFakeServer(FakePort);
  R := Default(TLedAIRequest);
  R.Instruction := 'say something';
  AssertTrue('the first is asked', FAI.Ask(R, Seq));
  AssertFalse('the second is not', FAI.Ask(R, Seq));
  AssertTrue('and it says why: ' + FAI.LastError,
    Pos('answering', FAI.LastError) > 0);
  PumpUntilDone(20000);
end;

procedure TTestAIOllama.AnOldConversationIsTrimmedBeforeItIsSent;
var
  R: TLedAIRequest;
  Seq, i: Integer;
  HadKB: Boolean;
  WasKB: string;
begin
  { The server keeps nothing, so every turn carries the whole conversation
    with it.  An afternoon's chat eventually exceeds the model's context
    window -- and long before that, every question costs seconds of reading
    before a word comes back. }
  PointAtTheFakeServer(FakePort);
  HadKB := LedPrefs.HasKey(LedPrefAIMaxContextKB);
  WasKB := LedPrefs.GetStr(LedPrefAIMaxContextKB, '');
  try
    LedPrefs.SetInt(LedPrefAIMaxContextKB, 1);      { one KB of history }
    for i := 1 to 20 do
      FChat.Add(larUser, StringOfChar('x', 500));
    FChat.Add(larUser, 'the newest thing anybody said');

    R := Default(TLedAIRequest);
    R.Instruction := 'and now this';
    AssertTrue('asked', FAI.Ask(R, Seq));
    PumpUntilDone(20000);

    { What actually went down the socket, which is the only thing that
      settles this. }
    AssertTrue(Format('the old turns were left behind (%d bytes sent)',
      [Length(GFake.LastBody)]), Length(GFake.LastBody) < 4000);
    AssertTrue('the newest one was not',
      Pos('the newest thing anybody said', GFake.LastBody) > 0);
    AssertTrue('nor was the question',
      Pos('and now this', GFake.LastBody) > 0);
  finally
    if HadKB then LedPrefs.SetStr(LedPrefAIMaxContextKB, WasKB)
    else LedPrefs.Remove(LedPrefAIMaxContextKB);
  end;
end;

procedure TTestAIOllama.AServerThatRefusesIsReportedNotSwallowed;
var
  R: TLedAIRequest;
  Seq: Integer;
begin
  { A refusal read as an empty answer is the worst of both: nothing appears
    and nothing says why. }
  FakeServer;
  LedPrefs.SetStr(LedPrefAIOllamaURL,
    Format('http://127.0.0.1:%d/api/refuse', [FakePort]));
  LedPrefs.SetStr(LedPrefAIOllamaModel, 'fake');
  FAI.Model := 'fake';

  R := Default(TLedAIRequest);
  R.Instruction := 'say something';
  AssertTrue('asked', FAI.Ask(R, Seq));
  PumpUntilDone(10000);
  AssertTrue('something said no', FError <> '');
  AssertTrue('in the server''s own words, which name the model: ' + FError,
    Pos('nope', FError) > 0);
  AssertFalse('and it did not pretend to finish', FDone and (FError = ''));
  AssertTrue('and it is ready to be asked again', FAI.State = laiIdle);
end;

procedure TTestAIOllama.AServerThatIsNotThereIsReportedQuickly;
var
  R: TLedAIRequest;
  Seq, Took: Integer;
begin
  LedPrefs.SetStr(LedPrefAIOllamaURL, 'http://127.0.0.1:1');
  LedPrefs.SetStr(LedPrefAIOllamaModel, 'fake');
  FAI.Model := 'fake';
  R := Default(TLedAIRequest);
  R.Instruction := 'hello';
  AssertTrue('asked', FAI.Ask(R, Seq));
  Took := PumpUntilDone(8000);
  AssertTrue('it said so rather than hanging: ' + FError, FError <> '');
  { This says "it reports rather than hangs", and not what the connect
    timeout is set to: a refused connection on the loopback comes back in
    microseconds whatever the timeout says, so no bound here could tell the
    two apart.  A machine that drops the packets instead is where the
    timeout earns its keep, and that is not a thing a check can arrange. }
  AssertTrue(Format('and quickly (%d ms)', [Took]), Took < 6000);
end;

procedure TTestAIOllama.ModelsAreListedFromTheServer;
var
  Names: TStringList;
  Why: string;
begin
  PointAtTheFakeServer(FakePort);
  Names := TStringList.Create;
  try
    AssertTrue('asked and answered: ' + Why, FAI.ModelList(Names, Why));
    AssertEquals('three of them', 3, Names.Count);
    AssertEquals('in the order the server gave', 'first:latest', Names[0]);
  finally
    Names.Free;
  end;
end;

initialization
  RegisterTest(TTestAIOllama);

finalization
  { One server for the unit, shut down when the run ends.  Starting and
    stopping one per test is what hung the picture-fetching suite. }
  if GFake <> nil then
  begin
    GFake.Stop;
    GFake := nil;
  end;

end.
