// led - a lightweight editor.  Talking to a model running on this machine.
//
// ollama is an HTTP server, usually on localhost:11434, and /api/chat with
// "stream":true answers in NDJSON: one JSON object per line, each carrying a
// few more characters of the reply, and a last one that says it is done and
// how long it took.
//
// The difficulty is that TFPHTTPClient is a blocking client, and a reply
// takes as long as a model takes to think -- which on this machine begins
// with loading tens of gigabytes, because /api/ps is empty until something
// is asked.  A reader watching a frozen editor for forty seconds does not
// care that the answer will eventually be good.
//
// So the request runs on a thread of its own, and the trick that makes the
// words appear as they are written is this: TFPHTTPClient does not build the
// response in memory and hand it over at the end.  It writes into whatever
// stream it is given, once per read off the socket
// (fpchttpclient.pp:1009-1013, and the same in the chunked path at :1105).
// A stream of our own is therefore where the tokens of an answer first
// become visible -- seconds before the call the worker is inside of returns.
// From there they go through the line splitter, are parsed one line at a
// time, and are pushed onto a queue the editor drains from a timer.  Nothing
// is raised from the worker: an event raised on a worker thread arrives on
// that thread, and a control may not be touched from there.
//
// Stopping is three things, none of which waits.  The sink raises on the
// next chunk, so the request unwinds out of the socket read; the client is
// Terminated, which every read loop in fphttpclient tests; and the turn
// number is bumped, so anything still in flight belongs to a turn nobody is
// listening to and is dropped on the way past.  That last one is what makes
// Stop instant, because it is the only one of the three that does not depend
// on the far end doing anything.
//
// The honest limitation: if the question is still waiting for a 51 GB model
// to load, no byte has arrived, so neither the sink nor the terminate flag
// gets a chance to fire.  The worker is let go of instead -- it owns
// everything it touches and writes into nothing this object still points at
// -- and it ends on its own when the first byte comes or the timeout does.
// Nothing in the editor waits for it, and the next question can be asked
// straight away.

unit Led.Core.AI.Ollama;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, fphttpclient, fpjson,
  Led.Core.AI, Led.Core.LineSplit, Led.Core.NBFormat, Led.Core.Prefs;

type
  { What the worker has to say, in the order it said it.  The queue is shared
    between the worker and the backend and outlives whichever of them lets go
    first, which is what lets a turn be abandoned without waiting for it. }
  TLedAIOllamaQueue = class
  private
    FLock: TCriticalSection;
    FItems: TList;
    FRefs: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddRef;
    { Lets go.  The last one out frees it. }
    procedure Release;
    procedure Push(const ADelta: TLedAIDelta);
    function Take(out ADelta: TLedAIDelta): Boolean;
    function Waiting: Integer;
  end;

  TLedAIOllama = class(TLedAIBackend)
  private
    FQueue: TLedAIOllamaQueue;
    FWorker: TThread;
    FAnswer: string;
    FThinking: string;
    FStats: string;
    FReplaces: Boolean;
    FWasCut: Boolean;
    FStoppedAt: TDateTime;
    function BaseURL: string;
    procedure LetGoOfWorker;
  public
    constructor Create(AChat: TLedAIChat); override;
    destructor Destroy; override;
    class function BackendName: string; override;
    class function Available: Boolean; override;
    function Ask(const ARequest: TLedAIRequest; out ASeq: Integer): Boolean;
      override;
    procedure Stop; override;
    function Poll: Boolean; override;
    procedure Shutdown; override;
    function ModelList(ANames: TStrings; out AWhy: string): Boolean; override;
  end;

{ The body of one /api/chat request: every message of the conversation, then
  the question.  A free function because a check can read it back with a JSON
  parser and say what was sent, which is not a thing a socket will tell you.

  A standalone request -- a transform -- carries only its own system message
  and its own prompt.  Sending the conversation with it would re-send
  somebody's whole file on every turn after it, which costs the model's
  context window and, on a 27B model, seconds of reading per turn. }
function LedAIOllamaChatBody(const AModel: string; AChat: TLedAIChat;
  const ARequest: TLedAIRequest; AThink: Boolean): string;

{ One NDJSON line as an event.  False when the line is not one -- which
  happens: a proxy in front of ollama answers in HTML, and a line of HTML is
  not a failed message, it is not a message.

  A model's thinking is not its answer.  qwen3 and its relatives put it in a
  field of its own, and it comes back as a delta of its own kind, so that
  nothing that could replace a selection ever contains it. }
function LedAIOllamaParseLine(const ALine: string; out ADelta: TLedAIDelta;
  out AFinal: Boolean; out AStats, AError: string): Boolean;

{ The models the server has, from /api/tags, in the order it gave them. }
function LedAIOllamaParseTags(const AText: string; ANames: TStrings): Boolean;

implementation

uses
  DateUtils, FileUtil;

type
  ELedAIStopped = class(Exception);

  TLedAIOllamaWorker = class;

  { The stream TFPHTTPClient writes the answer into.  It keeps nothing. }
  TLedAIOllamaSink = class(TStream)
  private
    FWorker: TLedAIOllamaWorker;
  public
    constructor Create(AWorker: TLedAIOllamaWorker);
    function Write(const ABuffer; ACount: Longint): Longint; override;
    function Read(var ABuffer; ACount: Longint): Longint; override;
    function Seek(const AOffset: Int64; AOrigin: TSeekOrigin): Int64; override;
  end;

  TLedAIOllamaWorker = class(TThread)
  private
    FQueue: TLedAIOllamaQueue;
    FSplit: TLedLineSplitter;
    FClient: TFPHTTPClient;
    FSink: TLedAIOllamaSink;
    FURL, FBody: string;
    FSeq, FTimeoutMs: Integer;
    FCancelled: Integer;
    FEnded: Boolean;        // a done or an error has already been queued
    procedure PushText(AKind: TLedAIDeltaKind; const AText, AName: string);
  protected
    procedure Execute; override;
  public
    constructor Create(AQueue: TLedAIOllamaQueue; const AURL, ABody: string;
      ASeq, ATimeoutMs: Integer);
    destructor Destroy; override;
    { Called from the worker, on every chunk off the socket. }
    procedure Chunk(const AData: string);
    function Cancelled: Boolean;
    procedure Cancel;
  end;

const
  { The kinds a queued item can be.  Carried in the delta's own Kind for the
    ordinary ones, and in Name for the two that end a turn, so that one queue
    carries everything in the order it happened. }
  QueueDone = #1'done';
  QueueError = #1'error';
  QueueStopped = #1'stopped';

{ ----- the queue -------------------------------------------------------- }

type
  PLedAIDelta = ^TLedAIDelta;

constructor TLedAIOllamaQueue.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FItems := TList.Create;
  FRefs := 1;
end;

destructor TLedAIOllamaQueue.Destroy;
var
  i: Integer;
  P: PLedAIDelta;
begin
  for i := 0 to FItems.Count - 1 do
  begin
    P := PLedAIDelta(FItems[i]);
    Finalize(P^);
    Dispose(P);
  end;
  FItems.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TLedAIOllamaQueue.AddRef;
begin
  FLock.Acquire;
  try
    Inc(FRefs);
  finally
    FLock.Release;
  end;
end;

procedure TLedAIOllamaQueue.Release;
var
  Last: Boolean;
begin
  FLock.Acquire;
  try
    Dec(FRefs);
    Last := FRefs <= 0;
  finally
    FLock.Release;
  end;
  if Last then Free;
end;

procedure TLedAIOllamaQueue.Push(const ADelta: TLedAIDelta);
var
  P: PLedAIDelta;
begin
  New(P);
  Initialize(P^);
  P^ := ADelta;
  FLock.Acquire;
  try
    FItems.Add(P);
  finally
    FLock.Release;
  end;
end;

function TLedAIOllamaQueue.Take(out ADelta: TLedAIDelta): Boolean;
var
  P: PLedAIDelta;
begin
  Result := False;
  ADelta := Default(TLedAIDelta);
  FLock.Acquire;
  try
    if FItems.Count = 0 then Exit;
    P := PLedAIDelta(FItems[0]);
    FItems.Delete(0);
  finally
    FLock.Release;
  end;
  ADelta := P^;
  Finalize(P^);
  Dispose(P);
  Result := True;
end;

function TLedAIOllamaQueue.Waiting: Integer;
begin
  FLock.Acquire;
  try
    Result := FItems.Count;
  finally
    FLock.Release;
  end;
end;

{ ----- the sink --------------------------------------------------------- }

constructor TLedAIOllamaSink.Create(AWorker: TLedAIOllamaWorker);
begin
  inherited Create;
  FWorker := AWorker;
end;

function TLedAIOllamaSink.Write(const ABuffer; ACount: Longint): Longint;
var
  Chunk: string;
begin
  Result := ACount;
  if ACount <= 0 then Exit;
  { Asked to stop, and the bytes kept coming.  Unwound here rather than
    waited out: the only other way out of a blocking request is the far end
    going quiet, and a model in the middle of an answer never does. }
  if FWorker.Cancelled then raise ELedAIStopped.Create('stopped');
  SetString(Chunk, PAnsiChar(@ABuffer), ACount);
  FWorker.Chunk(Chunk);
end;

function TLedAIOllamaSink.Read(var ABuffer; ACount: Longint): Longint;
begin
  Result := 0;
end;

function TLedAIOllamaSink.Seek(const AOffset: Int64;
  AOrigin: TSeekOrigin): Int64;
begin
  Result := 0;
end;

{ ----- the worker ------------------------------------------------------- }

constructor TLedAIOllamaWorker.Create(AQueue: TLedAIOllamaQueue;
  const AURL, ABody: string; ASeq, ATimeoutMs: Integer);
begin
  FQueue := AQueue;
  FQueue.AddRef;
  FURL := AURL;
  FBody := ABody;
  FSeq := ASeq;
  FTimeoutMs := ATimeoutMs;
  FSplit := TLedLineSplitter.Create;
  FSink := TLedAIOllamaSink.Create(Self);
  FreeOnTerminate := True;
  inherited Create(False);
end;

destructor TLedAIOllamaWorker.Destroy;
begin
  FSink.Free;
  FSplit.Free;
  FQueue.Release;
  inherited Destroy;
end;

function TLedAIOllamaWorker.Cancelled: Boolean;
begin
  Result := InterlockedCompareExchange(FCancelled, 0, 0) <> 0;
end;

procedure TLedAIOllamaWorker.Cancel;
begin
  InterlockedExchange(FCancelled, 1);
  if FClient <> nil then FClient.Terminate;
end;

procedure TLedAIOllamaWorker.PushText(AKind: TLedAIDeltaKind;
  const AText, AName: string);
var
  D: TLedAIDelta;
begin
  D := Default(TLedAIDelta);
  D.Seq := FSeq;
  D.Kind := AKind;
  D.Text := AText;
  D.Name := AName;
  FQueue.Push(D);
end;

procedure TLedAIOllamaWorker.Chunk(const AData: string);
var
  Line, Stats, Err: string;
  D: TLedAIDelta;
  Final: Boolean;
begin
  FSplit.Feed(AData);
  while FSplit.Next(Line) do
  begin
    if Trim(Line) = '' then Continue;
    if not LedAIOllamaParseLine(Line, D, Final, Stats, Err) then
    begin
      { Not a message at all.  A proxy answering in HTML gets one notice, not
        a hundred. }
      PushText(ladNotice, '', 'unreadable');
      Continue;
    end;
    if Err <> '' then
    begin
      FEnded := True;
      PushText(ladNotice, Err, QueueError);
      Exit;
    end;
    if D.Text <> '' then
    begin
      D.Seq := FSeq;
      FQueue.Push(D);
    end;
    if Final then
    begin
      FEnded := True;
      PushText(ladNotice, Stats, QueueDone);
      Exit;
    end;
  end;
end;

procedure TLedAIOllamaWorker.Execute;
var
  Body: TStringStream;
begin
  Body := TStringStream.Create(FBody);
  FClient := TFPHTTPClient.Create(nil);
  try
    try
      { Localhost either listens or it does not, and a refusal is instant. }
      FClient.ConnectTimeout := 3000;
      { Long, and on purpose: the first question of a session waits for the
        model to be loaded.  A short timeout here would not mean "give up
        politely" -- the read fails and the answer is lost. }
      FClient.IOTimeout := FTimeoutMs;
      FClient.AddHeader('Content-Type', 'application/json');
      FClient.RequestBody := Body;
      { Every code accepted, and the body read whatever it says.  Asking only
        for 200 would be tidier and would throw away the useful half of a
        refusal: ollama says no in JSON, in the body, and "model 'qwen3:80b'
        not found" is worth reading out where "the server answered 404" is
        not. }
      FClient.HTTPMethod('POST', FURL, FSink, []);
      if not (Cancelled or FEnded) then
        if (FClient.ResponseStatusCode div 100) <> 2 then
          PushText(ladNotice, Format('the server answered %d',
            [FClient.ResponseStatusCode]), QueueError)
        else
          { It closed the connection without ever saying it was done. }
          PushText(ladNotice, '', QueueDone);
    except
      on E: ELedAIStopped do
        PushText(ladNotice, '', QueueStopped);
      on E: Exception do
        if Cancelled then
          PushText(ladNotice, '', QueueStopped)
        else
          PushText(ladNotice, E.Message, QueueError);
    end;
  finally
    FClient.RequestBody := nil;
    FreeAndNil(FClient);
    Body.Free;
  end;
end;

{ ----- the free functions ----------------------------------------------- }

function RoleName(ARole: TLedAIRole): string;
begin
  case ARole of
    larSystem: Result := 'system';
    larAssistant: Result := 'assistant';
  else
    Result := 'user';
  end;
end;

function LedAIOllamaChatBody(const AModel: string; AChat: TLedAIChat;
  const ARequest: TLedAIRequest; AThink: Boolean): string;
var
  Root, Opts: TJSONObject;
  Msgs: TJSONArray;
  i: Integer;
  Sys: string;

  procedure AddMessage(const ARole, AText: string);
  var
    M: TJSONObject;
  begin
    M := TJSONObject.Create;
    M.Add('role', ARole);
    M.Add('content', AText);
    Msgs.Add(M);
  end;

begin
  Root := TJSONObject.Create;
  try
    Msgs := TJSONArray.Create;

    Sys := ARequest.System;
    if Sys = '' then Sys := LedAITaskSystem(ARequest.Task);
    if Sys <> '' then AddMessage('system', Sys);

    { A transform is one question about one piece of text.  A conversation is
      everything said so far, because the server keeps none of it. }
    if (not ARequest.Standalone) and (AChat <> nil) then
      for i := 0 to AChat.Count - 1 do
        AddMessage(RoleName(AChat.Role(i)), AChat.Text(i));

    AddMessage('user', LedAIBuildPrompt(ARequest));

    Root.Add('model', AModel);
    Root.Add('messages', Msgs);
    Root.Add('stream', True);
    Root.Add('think', AThink);

    Opts := TJSONObject.Create;
    { Colder for a replacement than for a conversation: a proof-reading that
      invents a livelier sentence has not proof-read anything. }
    if ARequest.Replaces then
      Opts.Add('temperature', 0.2)
    else
      Opts.Add('temperature', 0.7);
    Root.Add('options', Opts);

    Result := Root.AsJSON;
  finally
    Root.Free;
  end;
end;

function LedAIOllamaParseLine(const ALine: string; out ADelta: TLedAIDelta;
  out AFinal: Boolean; out AStats, AError: string): Boolean;
var
  Data: TJSONData;
  Root, Msg: TJSONObject;
  Why, Text: string;
  Nanos: Int64;
  Tokens: Integer;
begin
  Result := False;
  ADelta := Default(TLedAIDelta);
  AFinal := False;
  AStats := '';
  AError := '';

  Data := LedNBParseJSON(ALine, Why);
  if Data = nil then Exit;
  try
    if not (Data is TJSONObject) then Exit;
    Root := TJSONObject(Data);
    Result := True;

    { The server says no in the same shape it says anything else. }
    if Root.IndexOfName('error') >= 0 then
    begin
      AError := Root.Get('error', '');
      if AError = '' then AError := 'the server refused the request';
      Exit;
    end;

    if (Root.IndexOfName('message') >= 0) and
       (Root.Elements['message'] is TJSONObject) then
    begin
      Msg := TJSONObject(Root.Elements['message']);

      { Thinking first, so that a line carrying both is not mistaken for an
        answer.  It never replaces anything. }
      Text := Msg.Get('thinking', '');
      if Text <> '' then
      begin
        ADelta.Kind := ladThinking;
        ADelta.Text := Text;
      end
      else
      begin
        ADelta.Kind := ladText;
        ADelta.Text := Msg.Get('content', '');
      end;
    end;

    AFinal := Root.Get('done', False);
    if AFinal then
    begin
      Tokens := Root.Get('eval_count', 0);
      Nanos := Root.Get('total_duration', Int64(0));
      if (Tokens > 0) and (Nanos > 0) then
        AStats := Format('%d tokens in %.1f s', [Tokens, Nanos / 1000000000])
      else if Nanos > 0 then
        AStats := Format('in %.1f s', [Nanos / 1000000000]);
    end;
  finally
    Data.Free;
  end;
end;

function LedAIOllamaParseTags(const AText: string; ANames: TStrings): Boolean;
var
  Data: TJSONData;
  Root: TJSONObject;
  Arr: TJSONArray;
  i: Integer;
  Why, Name: string;
begin
  Result := False;
  ANames.Clear;
  Data := LedNBParseJSON(AText, Why);
  if Data = nil then Exit;
  try
    if not (Data is TJSONObject) then Exit;
    Root := TJSONObject(Data);
    if (Root.IndexOfName('models') < 0) or
       not (Root.Elements['models'] is TJSONArray) then Exit;
    Arr := TJSONArray(Root.Elements['models']);
    for i := 0 to Arr.Count - 1 do
      if Arr.Items[i] is TJSONObject then
      begin
        Name := TJSONObject(Arr.Items[i]).Get('name', '');
        if Name <> '' then ANames.Add(Name);
      end;
    Result := True;
  finally
    Data.Free;
  end;
end;

{ ----- the backend ------------------------------------------------------ }

var
  GTried: Boolean = False;
  GAvailable: Boolean = False;

constructor TLedAIOllama.Create(AChat: TLedAIChat);
begin
  inherited Create(AChat);
  FQueue := TLedAIOllamaQueue.Create;
  if Available then SetState(laiIdle);
end;

destructor TLedAIOllama.Destroy;
begin
  Shutdown;
  FQueue.Release;
  inherited Destroy;
end;

class function TLedAIOllama.BackendName: string;
begin
  Result := 'ollama';
end;

class function TLedAIOllama.Available: Boolean;
begin
  { Two ways to be available: the program is installed here, or the reader
    has pointed the preference at a server somewhere else, in which case
    there is nothing local to find.  Never by running it: LED already knows
    what running a program to see whether it is there costs. }
  if GTried then Exit(GAvailable);
  GTried := True;
  GAvailable := (LedPrefs.GetStr(LedPrefAIOllamaURL, '') <> '') or
    (FindDefaultExecutablePath('ollama') <> '');
  Result := GAvailable;
end;

function TLedAIOllama.BaseURL: string;
begin
  Result := LedPrefs.GetStr(LedPrefAIOllamaURL, 'http://localhost:11434');
  while (Result <> '') and (Result[Length(Result)] = '/') do
    SetLength(Result, Length(Result) - 1);
end;

function TLedAIOllama.Ask(const ARequest: TLedAIRequest;
  out ASeq: Integer): Boolean;
var
  Req: TLedAIRequest;
  Body: string;
  Limit: Integer;
begin
  Result := False;
  ASeq := FSeq;
  if FState = laiBusy then
  begin
    FLastError := 'it is still answering the last question';
    Exit;
  end;
  if FModel = '' then
    FModel := LedPrefs.GetStr(LedPrefAIOllamaModel, '');
  if FModel = '' then
  begin
    FLastError := 'no model has been chosen';
    Exit;
  end;

  Req := ARequest;
  Limit := LedPrefs.GetInt(LedPrefAIMaxContextKB, 64) * 1024;
  FWasCut := False;
  if Length(Req.Context) > Limit then
    Req.Context := LedAICutContext(Req.Context, Limit, FWasCut);

  { The server keeps nothing, so every turn carries the whole conversation
    with it.  Left alone that grows without limit: an afternoon's chat
    eventually exceeds the model's context window, and long before that
    every question costs seconds of reading before a word comes back.  The
    oldest turns go first, and never the question being asked. }
  if (not Req.Standalone) and (FChat <> nil) then FChat.TrimTo(Limit);

  Inc(FSeq);
  ASeq := FSeq;
  FAnswer := '';
  FThinking := '';
  FStats := '';
  FReplaces := Req.Replaces;

  Body := LedAIOllamaChatBody(FModel, FChat, Req,
    LedPrefs.GetBool(LedPrefAIOllamaThink, False));

  FWorker := TLedAIOllamaWorker.Create(FQueue, BaseURL + '/api/chat', Body,
    FSeq, LedPrefs.GetInt(LedPrefAITimeoutMs, 300000));
  SetState(laiBusy);
  Result := True;
end;

procedure TLedAIOllama.LetGoOfWorker;
begin
  { The worker owns its client, its sink and its splitter, holds its own
    reference to the queue, and writes into nothing this object points at.
    Letting go of it is therefore safe, and waiting for it is not always
    possible: a request still waiting for a model to load has had no chance
    to notice that anybody wants it to stop. }
  FWorker := nil;
end;

procedure TLedAIOllama.Stop;
begin
  if FState <> laiBusy then Exit;
  if FWorker <> nil then TLedAIOllamaWorker(FWorker).Cancel;
  { The turn number is what makes this instant: everything still in flight
    now belongs to a turn nobody is listening to. }
  Inc(FSeq);
  FStoppedAt := Now;
  SetState(laiStopping);
end;

function TLedAIOllama.Poll: Boolean;
var
  D: TLedAIDelta;
  R: TLedAIResult;
  Grace: Integer;
begin
  Result := False;
  while FQueue.Take(D) do
  begin
    Result := True;

    if D.Name = QueueDone then
    begin
      if Current(D.Seq) then
      begin
        R := Default(TLedAIResult);
        R.Seq := D.Seq;
        R.Text := FAnswer;
        R.Thinking := FThinking;
        R.Stats := D.Text;
        R.Replaces := FReplaces;
        R.ContextWasCut := FWasCut;
        LetGoOfWorker;
        Finish(R);
      end;
      Continue;
    end;

    if D.Name = QueueError then
    begin
      if Current(D.Seq) then
      begin
        LetGoOfWorker;
        Fail(D.Seq, D.Text);
      end;
      Continue;
    end;

    if D.Name = QueueStopped then
    begin
      if FState = laiStopping then
      begin
        LetGoOfWorker;
        SetState(laiIdle);
      end;
      Continue;
    end;

    { The same question Emit asks, asked here too so that a turn nobody is
      listening to does not go on building up an answer either. }
    if not Current(D.Seq) then Continue;

    case D.Kind of
      ladText: FAnswer := FAnswer + D.Text;
      ladThinking: FThinking := FThinking + D.Text;
    end;
    Emit(D);
  end;

  { A worker that has not noticed yet.  It is let go of rather than waited
    for; see the note on LetGoOfWorker. }
  if FState = laiStopping then
  begin
    Grace := LedPrefs.GetInt(LedPrefAIStopGraceMs, 5000);
    if MilliSecondsBetween(Now, FStoppedAt) > Grace then
    begin
      LetGoOfWorker;
      SetState(laiIdle);
      Result := True;
    end;
  end;
end;

procedure TLedAIOllama.Shutdown;
begin
  if FWorker <> nil then
  begin
    TLedAIOllamaWorker(FWorker).Cancel;
    LetGoOfWorker;
  end;
  inherited Shutdown;
end;

function TLedAIOllama.ModelList(ANames: TStrings; out AWhy: string): Boolean;
var
  Client: TFPHTTPClient;
  Text: string;
begin
  Result := False;
  AWhy := '';
  ANames.Clear;
  { Blocking, deliberately.  /api/tags is answered off disk and loads
    nothing, the pane asks once when it opens, and the timeouts below bound
    the worst case at three seconds -- less machinery than a thread and a
    queue for a question that is fast by construction. }
  Client := TFPHTTPClient.Create(nil);
  try
    try
      Client.ConnectTimeout := 1000;
      Client.IOTimeout := 2000;
      Text := Client.Get(BaseURL + '/api/tags');
    except
      on E: Exception do
      begin
        AWhy := 'ollama did not answer at ' + BaseURL;
        Exit;
      end;
    end;
  finally
    Client.Free;
  end;

  Result := LedAIOllamaParseTags(Text, ANames);
  if not Result then
    AWhy := 'ollama answered something that was not a list of models'
  else if ANames.Count = 0 then
    AWhy := 'ollama has no models installed';
end;

end.
