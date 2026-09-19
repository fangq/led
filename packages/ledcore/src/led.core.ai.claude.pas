// led - a lightweight editor.  Talking to Claude Code.
//
// Not over a socket: claude is a program, and LED drives it the way it
// drives gdb and the notebook kernel -- a subprocess, a line protocol, and a
// poll that never blocks the editor.  One JSON object per line, out of its
// standard output, with --output-format stream-json.
//
// The shapes below are not guessed.  They were taken off a real run of
// claude 2.1.278 and are written down here so that a version that changes
// them fails a check with a fixture to look at rather than going quiet:
//
//   {"type":"system","subtype":"init","session_id":"d896...","model":...}
//   {"type":"stream_event","event":{"type":"content_block_start",
//      "content_block":{"type":"thinking"|"text"|"tool_use","name":...}}}
//   {"type":"stream_event","event":{"type":"content_block_delta",
//      "delta":{"type":"text_delta","text":"OK"}}}
//   {"type":"assistant","message":{"content":[{"type":"text","text":"OK"}]}}
//   {"type":"result","subtype":"success","is_error":false,"result":"OK",
//      "duration_ms":1207,"num_turns":1}
//
// The assistant lines are the trap.  With --include-partial-messages every
// word arrives twice: once as a delta, as it is written, and again in the
// whole message when the block closes.  Counting both gives an answer that
// reads correctly and says everything twice, and nothing about it looks
// wrong until you read it.  So the deltas are the answer and the assistant
// lines are ignored.
//
// One process per turn, rather than one session held open.  --resume with
// the session id from the init line keeps the conversation, which is the
// only thing a held-open process would buy, and it costs about a second of
// startup.  What it buys is worth more than the second: stopping is killing
// a process that is about to end anyway, there is no long-lived child to
// leak out of a crash, and a turn that goes wrong cannot poison the next
// one.
//
// What it is allowed to do in the project is the reader's, in one
// preference, and it is spelled out rather than being a Boolean because
// there are four real answers: nothing at all, ask about everything, write
// files but ask about commands, or get on with it.

unit Led.Core.AI.Claude;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, fpjson,
  Led.Core.AI, Led.Core.LineSplit, Led.Core.NBFormat, Led.Core.Prefs;

type
  TLedAIClaudeKind = (
    lcvNothing,     // a line that is not an event
    lcvInit,        // the session started.  Name is its id
    lcvText,        // a piece of the answer
    lcvThinking,    // a piece of it thinking
    lcvTool,        // it started using a tool.  Name says which
    lcvDone,        // the turn finished.  Text is the whole answer
    lcvFailed);     // it did not.  Text says why

  TLedAIClaudeEvent = record
    Kind: TLedAIClaudeKind;
    Text: string;
    Name: string;
    Stats: string;
  end;

  TLedAIClaude = class(TLedAIBackend)
  private
    FProcess: TProcess;
    FSplit: TLedLineSplitter;
    FSession: string;
    FAnswer: string;
    FThinking: string;
    FReplaces: Boolean;
    FWasCut: Boolean;
    FSawDelta: Boolean;
    FWorkDir: string;
    procedure Quit;
  public
    constructor Create(AChat: TLedAIChat); override;
    destructor Destroy; override;
    class function BackendName: string; override;
    class function Available: Boolean; override;
    { The program that will be run.  '' when there is none. }
    class function ClaudePath: string;
    { Where it is allowed to work.  The project's directory, set by the pane;
      empty means wherever LED was started, which is rarely what anyone
      means. }
    property WorkDir: string read FWorkDir write FWorkDir;
    { The conversation claude itself is keeping, or '' before the first
      answer.  Published because a check can watch it being carried from one
      turn to the next, which is the whole of how the conversation survives
      one process per turn. }
    property Session: string read FSession;
    function Ask(const ARequest: TLedAIRequest; out ASeq: Integer): Boolean;
      override;
    procedure Stop; override;
    function Poll: Boolean; override;
    procedure Shutdown; override;
  end;

{ The command line for one turn.  A free function returning the arguments in
  order, because what claude is allowed to do in somebody's project is worth
  a check that does not need claude installed to run.

  ATools is the preference: 'chat', 'ask', 'edits' or 'full'. }
function LedAIClaudeArgs(const AModel, ATools, ASession: string): TStringList;

{ What claude may do, in words, for the pane to show.  Public because a
  reader about to let a program write to their project should be able to
  read what they have agreed to without opening the preferences. }
function LedAIClaudeToolsSaid(const ATools: string): string;

{ One line of stream-json as an event.  False when the line is not one -- and
  lines that are not are ordinary here: a login notice, a rate-limit event,
  anything a future version adds. }
function LedAIClaudeParseEvent(const ALine: string;
  out AEvent: TLedAIClaudeEvent): Boolean;

implementation

uses
  FileUtil, DateUtils;

{ ----- the free functions ----------------------------------------------- }

function LedAIClaudeArgs(const AModel, ATools, ASession: string): TStringList;
begin
  Result := TStringList.Create;
  Result.Add('-p');
  Result.Add('--output-format');
  Result.Add('stream-json');
  { stream-json is refused without it.  Cheaper to find out here, in a check
    that runs in a millisecond, than from a live turn that fails in a
    minute. }
  Result.Add('--verbose');
  { Without this the words arrive only when the whole message is finished,
    which is the difference between watching an answer and waiting for one. }
  Result.Add('--include-partial-messages');

  if AModel <> '' then
  begin
    Result.Add('--model');
    Result.Add(AModel);
  end;

  { The conversation is claude's own; this is how one process per turn still
    adds up to a conversation. }
  if ASession <> '' then
  begin
    Result.Add('--resume');
    Result.Add(ASession);
  end;

  { Nothing at all: a conversation, with no way to read or change anything
    -- the same as the model on this machine can do, and the default.  An
    editor that talks to a model must not become one that rewrites your
    project because you asked it a question. }
  if (ATools <> 'full') and (ATools <> 'edits') and (ATools <> 'ask') then
  begin
    Result.Add('--tools');
    Result.Add('none');
    Exit;
  end;

  Result.Add('--permission-mode');
  if ATools = 'full' then
    Result.Add('bypassPermissions')
  else if ATools = 'edits' then
    Result.Add('acceptEdits')
  else
    { "Ask" means the reader answers, and LED cannot put the question to
      them yet.  Until it can, this plans and changes nothing: refusing is
      safe, and pretending to have asked is not. }
    Result.Add('plan');
end;

function LedAIClaudeToolsSaid(const ATools: string): string;
begin
  if ATools = 'full' then
    Result := 'may read, write and run commands in the project without asking'
  else if ATools = 'edits' then
    Result := 'may read and write files in the project; commands still stop it'
  else if ATools = 'ask' then
    Result := 'may read and plan, but changes nothing'
  else
    Result := 'cannot read or change anything; it only talks';
end;

function LedAIClaudeParseEvent(const ALine: string;
  out AEvent: TLedAIClaudeEvent): Boolean;
var
  Data: TJSONData;
  Root, Ev, Delta, Block, Msg: TJSONObject;
  Why, Kind, EvKind: string;
begin
  Result := False;
  AEvent := Default(TLedAIClaudeEvent);

  Data := LedNBParseJSON(ALine, Why);
  if Data = nil then Exit;
  try
    if not (Data is TJSONObject) then Exit;
    Root := TJSONObject(Data);
    Kind := Root.Get('type', '');

    if Kind = 'system' then
    begin
      if Root.Get('subtype', '') <> 'init' then Exit;
      AEvent.Kind := lcvInit;
      AEvent.Name := Root.Get('session_id', '');
      AEvent.Text := Root.Get('model', '');
      Exit(True);
    end;

    if Kind = 'result' then
    begin
      Msg := Root;
      if Msg.Get('is_error', False) then
      begin
        AEvent.Kind := lcvFailed;
        AEvent.Text := Msg.Get('result', '');
        if AEvent.Text = '' then AEvent.Text := Msg.Get('subtype', 'it failed');
      end
      else
      begin
        AEvent.Kind := lcvDone;
        { The whole answer, which is how a turn whose deltas were missed
          still has something to show. }
        AEvent.Text := Msg.Get('result', '');
        AEvent.Stats := Format('in %.1f s',
          [Msg.Get('duration_ms', 0) / 1000]);
      end;
      AEvent.Name := Msg.Get('session_id', '');
      Exit(True);
    end;

    { Everything else worth having is inside a stream event.  The assistant
      lines are deliberately not: with --include-partial-messages they are
      the same words a second time. }
    if Kind <> 'stream_event' then Exit;
    if not (Root.Find('event') is TJSONObject) then Exit;
    Ev := TJSONObject(Root.Elements['event']);
    EvKind := Ev.Get('type', '');

    if EvKind = 'content_block_delta' then
    begin
      if not (Ev.Find('delta') is TJSONObject) then Exit;
      Delta := TJSONObject(Ev.Elements['delta']);
      Kind := Delta.Get('type', '');
      if Kind = 'text_delta' then
      begin
        AEvent.Kind := lcvText;
        AEvent.Text := Delta.Get('text', '');
        Exit(True);
      end;
      if Kind = 'thinking_delta' then
      begin
        AEvent.Kind := lcvThinking;
        AEvent.Text := Delta.Get('thinking', '');
        Exit(True);
      end;
      { A signature, or a tool's arguments arriving a few characters at a
        time.  Neither is anything to show. }
      Exit;
    end;

    if EvKind = 'content_block_start' then
    begin
      if not (Ev.Find('content_block') is TJSONObject) then Exit;
      Block := TJSONObject(Ev.Elements['content_block']);
      if Block.Get('type', '') <> 'tool_use' then Exit;
      AEvent.Kind := lcvTool;
      AEvent.Name := Block.Get('name', '');
      Exit(True);
    end;
  finally
    Data.Free;
  end;
end;

{ ----- the backend ------------------------------------------------------ }

var
  GTried: Boolean = False;
  GPath: string = '';

constructor TLedAIClaude.Create(AChat: TLedAIChat);
begin
  inherited Create(AChat);
  FSplit := TLedLineSplitter.Create;
  if Available then SetState(laiIdle);
end;

destructor TLedAIClaude.Destroy;
begin
  Shutdown;
  FSplit.Free;
  inherited Destroy;
end;

class function TLedAIClaude.BackendName: string;
begin
  Result := 'claude';
end;

class function TLedAIClaude.Available: Boolean;
begin
  Result := ClaudePath <> '';
end;

class function TLedAIClaude.ClaudePath: string;
begin
  { A named program wins, and is not remembered: it is a preference, and a
    preference that needed a restart to take effect would be a bug. }
  Result := LedPrefs.GetStr(LedPrefAIClaudePath, '');
  if Result <> '' then
  begin
    if not FileExists(Result) then Result := '';
    Exit;
  end;

  { Otherwise the one on the PATH, looked up once and remembered.  Never by
    running it to see what it says: LED already knows what that costs. }
  if not GTried then
  begin
    GTried := True;
    GPath := FindDefaultExecutablePath('claude');
  end;
  Result := GPath;
end;

function TLedAIClaude.Ask(const ARequest: TLedAIRequest;
  out ASeq: Integer): Boolean;
var
  Req: TLedAIRequest;
  Args: TStringList;
  Prompt, Tools: string;
  Limit, i: Integer;
begin
  Result := False;
  ASeq := FSeq;
  if FState = laiBusy then
  begin
    FLastError := 'it is still answering the last question';
    Exit;
  end;
  if not Available then
  begin
    FLastError := 'claude is not installed';
    Exit;
  end;

  Req := ARequest;
  Limit := LedPrefs.GetInt(LedPrefAIMaxContextKB, 64) * 1024;
  FWasCut := False;
  if Length(Req.Context) > Limit then
    Req.Context := LedAICutContext(Req.Context, Limit, FWasCut);

  { claude keeps the conversation itself, so only this turn is sent -- but
    the instructions for a transform still have to travel with it. }
  Prompt := LedAIBuildPrompt(Req);
  if Req.System <> '' then
    Prompt := Req.System + LineEnding + LineEnding + Prompt
  else if Req.Task <> laskChat then
    Prompt := LedAITaskSystem(Req.Task) + LineEnding + LineEnding + Prompt;

  Quit;
  FSplit.Reset;
  FAnswer := '';
  FThinking := '';
  FSawDelta := False;
  FReplaces := Req.Replaces;
  Inc(FSeq);
  ASeq := FSeq;

  Tools := LedPrefs.GetStr(LedPrefAIClaudeTools, 'chat');
  FProcess := TProcess.Create(nil);
  FProcess.Executable := ClaudePath;
  Args := LedAIClaudeArgs(LedPrefs.GetStr(LedPrefAIClaudeModel, ''),
    Tools, FSession);
  try
    for i := 0 to Args.Count - 1 do
      FProcess.Parameters.Add(Args[i]);
  finally
    Args.Free;
  end;
  if (FWorkDir <> '') and DirectoryExists(FWorkDir) then
    FProcess.CurrentDirectory := FWorkDir;
  { Not poStderrToOutput: stdout is a protocol, and a notice printed by
    somebody's shell profile must not arrive in the middle of it. }
  FProcess.Options := [poUsePipes, poNoConsole];

  try
    FProcess.Execute;
  except
    on E: Exception do
    begin
      FreeAndNil(FProcess);
      FLastError := 'claude would not run (' + E.Message + ')';
      SetState(laiFailed);
      Exit;
    end;
  end;

  { The question goes in on standard input rather than on the command line:
    a transform carries a piece of somebody's file, and a file does not fit
    in an argument list. }
  try
    Prompt := Prompt + #10;
    FProcess.Input.Write(Prompt[1], Length(Prompt));
    FProcess.CloseInput;
  except
    on E: Exception do
    begin
      Quit;
      FLastError := 'claude stopped listening (' + E.Message + ')';
      SetState(laiIdle);
      Exit;
    end;
  end;

  SetState(laiBusy);
  Result := True;
end;

procedure TLedAIClaude.Quit;
begin
  if FProcess = nil then Exit;
  if FProcess.Running then
  begin
    { Its input is already closed, so a turn that is finishing will end by
      itself; this is for one that is not. }
    if not FProcess.WaitOnExit(200) then
      FProcess.Terminate(0);
  end;
  FreeAndNil(FProcess);
end;

procedure TLedAIClaude.Stop;
begin
  if FState <> laiBusy then Exit;
  { One process per turn is what makes this simple: the turn is the process,
    and ending one ends the other. }
  Inc(FSeq);
  Quit;
  SetState(laiIdle);
end;

function TLedAIClaude.Poll: Boolean;
var
  Buf: array[0..16383] of AnsiChar;
  N: Integer;
  Chunk, Line: string;
  Ev: TLedAIClaudeEvent;
  D: TLedAIDelta;
  R: TLedAIResult;
  Ended: Boolean;

  procedure Deliver(AKind: TLedAIDeltaKind; const AText, AName: string);
  begin
    D := Default(TLedAIDelta);
    D.Seq := FSeq;
    D.Kind := AKind;
    D.Text := AText;
    D.Name := AName;
    Emit(D);
  end;

begin
  Result := False;
  if FProcess = nil then Exit;

  while (FProcess.Output <> nil) and (FProcess.Output.NumBytesAvailable > 0) do
  begin
    N := FProcess.Output.Read(Buf, SizeOf(Buf));
    if N <= 0 then Break;
    SetString(Chunk, Buf, N);
    FSplit.Feed(Chunk);
    Result := True;
  end;

  Ended := False;
  while FSplit.Next(Line) do
  begin
    if Trim(Line) = '' then Continue;
    if not LedAIClaudeParseEvent(Line, Ev) then Continue;

    case Ev.Kind of
      lcvInit:
        { Remembered for the next turn: this is the conversation. }
        FSession := Ev.Name;
      lcvText:
        begin
          FSawDelta := True;
          FAnswer := FAnswer + Ev.Text;
          Deliver(ladText, Ev.Text, '');
        end;
      lcvThinking:
        begin
          FThinking := FThinking + Ev.Text;
          Deliver(ladThinking, Ev.Text, '');
        end;
      lcvTool:
        Deliver(ladTool, '', Ev.Name);
      lcvDone:
        begin
          if Ev.Name <> '' then FSession := Ev.Name;
          { The deltas are the answer.  The result line carries it again, and
            is used only when nothing was streamed at all -- which happens
            when a version stops sending partial messages, and is better
            than showing nothing. }
          if not FSawDelta then FAnswer := Ev.Text;
          R := Default(TLedAIResult);
          R.Seq := FSeq;
          R.Text := FAnswer;
          R.Thinking := FThinking;
          R.Stats := Ev.Stats;
          R.Replaces := FReplaces;
          R.ContextWasCut := FWasCut;
          Finish(R);
          Ended := True;
        end;
      lcvFailed:
        begin
          Fail(FSeq, Ev.Text);
          Ended := True;
        end;
    end;
    Result := True;
    if Ended then Break;
  end;

  if Ended then
  begin
    Quit;
    Exit;
  end;

  { It stopped without ever saying how it went. }
  if (FProcess <> nil) and (not FProcess.Running) and
     (FProcess.Output.NumBytesAvailable = 0) and (FState = laiBusy) then
  begin
    Quit;
    if FAnswer <> '' then
    begin
      R := Default(TLedAIResult);
      R.Seq := FSeq;
      R.Text := FAnswer;
      R.Thinking := FThinking;
      R.Replaces := FReplaces;
      R.ContextWasCut := FWasCut;
      Finish(R);
    end
    else
      Fail(FSeq, 'claude stopped without answering');
    Result := True;
  end;
end;

procedure TLedAIClaude.Shutdown;
begin
  Quit;
  inherited Shutdown;
end;

end.
