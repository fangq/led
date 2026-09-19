// led - a lightweight editor.  Asking a model something, without caring
// which model it is.
//
// Two of them, to begin with, and they could hardly be less alike: ollama is
// an HTTP server on this machine that wants the whole conversation posted to
// it again every turn, and claude is a command-line program LED starts and
// talks to down a pipe, which remembers the conversation itself.  One is a
// blocking request on a worker thread; the other is a child process polled
// from a timer.
//
// The pane is not the place for either of those facts.  What it wants is:
// ask this, tell me as the words arrive, tell me when it is finished, and
// stop.  So that is the whole of TLedAIBackend, and Poll is the only place
// an event is ever raised -- on the caller's thread, which is the rule this
// tree already follows for the picture fetcher and for the notebook kernel.
// An event raised from a worker thread arrives on that thread, and a control
// may not be touched from there.
//
// The other half of this unit is the part with no I/O in it at all: turning
// an instruction and a piece of somebody's file into a prompt, and turning
// what comes back into text that can replace what was sent.  That is where
// the feature is won or lost -- a model that answers a proof-reading request
// with "Certainly! Here is the corrected text:" and then three backticks has
// answered correctly and unusably -- and it is the part that can be checked
// without a model, a socket or a subprocess, so it is written as free
// functions and checked exhaustively.

unit Led.Core.AI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  Led.Core.Markdown;

const
  { Whether the feature is offered at all.  A reader who does not want an
    editor that talks to a model says so once. }
  LedPrefAIEnabled       = 'AI/enabled';
  LedPrefAIBackend       = 'AI/backend';           // 'ollama' | 'claude'
  LedPrefAIOllamaURL     = 'AI/ollama_url';
  LedPrefAIOllamaModel   = 'AI/ollama_model';
  { qwen3 and its relatives think out loud before answering.  The thinking is
    interesting to read and disastrous to paste into a file, so it is kept
    apart from the answer either way; this only decides whether the model is
    asked to do it at all. }
  LedPrefAIOllamaThink   = 'AI/ollama_think';
  LedPrefAIClaudeModel   = 'AI/claude_model';
  { Which program to run.  Normally empty, meaning "the claude on the PATH".
    A reader with it installed somewhere unusual names it here -- and so
    does a check, which is how the part of this that drives a process gets
    tested without needing an account. }
  LedPrefAIClaudePath    = 'AI/claude_path';
  { What the claude session is allowed to do in the project: 'chat' for
    nothing at all, 'ask' for tools with every one of them put to the reader
    first, 'edits' to let it write files without asking, 'full' for no
    questions at all.  Spelled out here rather than as a Boolean because
    there are four real answers and the middle two are the interesting
    ones. }
  LedPrefAIClaudeTools   = 'AI/claude_tools';
  { How much of a file is worth sending.  64 KiB is around sixteen thousand
    tokens, which fits inside every local model's window with room for an
    answer; a 2 MB file is half a million, which none of them has room for
    and which a 27B model would spend minutes reading before saying a word. }
  LedPrefAIMaxContextKB  = 'AI/max_context_kb';
  { Long, and on purpose: /api/ps is empty until something is asked, so the
    first question of a session loads tens of gigabytes before a single token
    comes back. }
  LedPrefAITimeoutMs     = 'AI/timeout_ms';
  LedPrefAIStopGraceMs   = 'AI/stop_grace_ms';

type
  TLedAIState = (
    laiOff,        // nothing to talk to
    laiIdle,       // ready
    laiBusy,       // a turn is in flight
    laiStopping,   // the reader gave up on it; it has not noticed yet
    laiFailed);    // LastError says why

  { Not everything a model emits is its answer.  qwen3 thinks out loud, and
    claude narrates the tools it is using; neither belongs in text that might
    replace somebody's selection, and both are worth showing. }
  TLedAIDeltaKind = (
    ladText,       // the answer
    ladThinking,   // the model working up to it
    ladTool,       // it used a tool.  Name says which
    ladNotice);    // something happened worth saying in the status line

  TLedAIRole = (larSystem, larUser, larAssistant);

  { What is being asked for.  Chat is a conversation; the rest are transforms
    -- an instruction, a piece of a file, and an answer meant to go back where
    the piece came from. }
  TLedAITask = (
    laskChat,
    laskProofread,
    laskRewrite,
    laskExplain,
    laskSummarise,
    laskComment,
    laskCustom);   // the reader's own template, from the preferences

  TLedAIDelta = record
    { Which turn this belongs to.  A delta from a turn the reader has given
      up on is dropped rather than shown: stopping has to be instant, and
      the only thing that can be made instant is what LED listens to. }
    Seq: Integer;
    Kind: TLedAIDeltaKind;
    Text: string;
    Name: string;        // ladTool: the tool.  ladNotice: what happened
  end;

  TLedAIResult = record
    Seq: Integer;
    Text: string;          // every ladText delta, joined
    Thinking: string;
    Stats: string;         // 'in 4.2 s, 318 tokens', for the status line
    { The turn was asked for as a replacement.  Whether it becomes one is
      the reader's click, never this. }
    Replaces: Boolean;
    { ...and only part of the file was sent.  A whole-file replacement from
      a partial reading is silent truncation, so the pane must not offer
      one. }
    ContextWasCut: Boolean;
  end;

  { One turn's worth of asking.  A record rather than six arguments because
    it will grow: the pane fills in what it knows, and each backend decides
    what any of it means on its own wire. }
  TLedAIRequest = record
    Task: TLedAITask;
    Instruction: string;     // what the reader typed
    Context: string;         // the selection, or the file.  '' for plain chat
    ContextName: string;     // the file's name, so the prompt can say it
    Language: string;        // 'pascal', 'python': the fence's info string
    { '' means "whatever this task usually asks for".  The same string
      reaches ollama as a system message and claude as
      --append-system-prompt: one field, two encodings. }
    System: string;
    Replaces: Boolean;       // the answer is meant to go back into the buffer
    Standalone: Boolean;     // and this turn is not part of the conversation
  end;

  TLedAIDeltaProc = procedure(Sender: TObject;
    const ADelta: TLedAIDelta) of object;
  TLedAIDoneProc = procedure(Sender: TObject;
    const AResult: TLedAIResult) of object;
  TLedAIErrorProc = procedure(Sender: TObject; ASeq: Integer;
    const AWhy: string) of object;
  TLedAIStateProc = procedure(Sender: TObject; AState: TLedAIState) of object;

  { A backend that can act in the project asks before it does.  AAllow comes
    in False: a handler that does nothing denies, and a backend with no
    handler at all cannot touch anything.  The reader's answer, not the
    editor's guess. }
  TLedAIPermissionProc = procedure(Sender: TObject; const ATool, ADetail: string;
    var AAllow: Boolean) of object;

  { What was said, in order.

    Owned by the pane rather than by a backend, so that changing backend
    part-way through leaves the conversation on the screen. }
  TLedAIChat = class
  private
    { The role rides in the string list's own object slot.  A second list
      kept in step with the first is a second list to get out of step. }
    FTexts: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(ARole: TLedAIRole; const AText: string);
    procedure Clear;
    function Count: Integer;
    function Role(AIndex: Integer): TLedAIRole;
    function Text(AIndex: Integer): string;
    { Drops the oldest turns, oldest first, until what is left weighs less
      than ABytes.  The system message is never dropped, and neither is the
      last turn: a conversation trimmed to nothing is not a conversation. }
    procedure TrimTo(ABytes: Integer);
  end;

  { What every backend looks like from the pane. }
  TLedAIBackend = class
  protected
    FChat: TLedAIChat;            // not owned
    FState: TLedAIState;
    FSeq: Integer;
    FLastError: string;
    FModel: string;
    FOnDelta: TLedAIDeltaProc;
    FOnDone: TLedAIDoneProc;
    FOnError: TLedAIErrorProc;
    FOnState: TLedAIStateProc;
    FOnPermission: TLedAIPermissionProc;
    { Whether anybody is still listening to that turn.  One place, used by
      everything that would speak on a turn's behalf: a backend that stops a
      request cannot stop what is already on its way back, so the only thing
      that can be made instant is what LED will still repeat.  Written once
      because two copies of it cover for one another, and a check cannot
      then tell whether either works. }
    function Current(ASeq: Integer): Boolean;
    procedure SetState(AState: TLedAIState);
    procedure Emit(const ADelta: TLedAIDelta);
    procedure Finish(const AResult: TLedAIResult);
    procedure Fail(ASeq: Integer; const AWhy: string);
    { False unless a handler says otherwise. }
    function AskPermission(const ATool, ADetail: string): Boolean;
  public
    constructor Create(AChat: TLedAIChat); virtual;

    { What goes in the preference and on the pane's menu. }
    class function BackendName: string; virtual; abstract;
    { Whether it is worth offering.  Looked up once and remembered, and never
      by running the thing: LED already learned what running a program to see
      whether it is there costs, when asking ctags its version deadlocked on
      a pipe nobody was reading. }
    class function Available: Boolean; virtual; abstract;

    { Asks.  False when there is nothing to ask with or when the last turn
      has not let go yet; LastError says which.  ASeq is the number the
      answer's events will carry. }
    function Ask(const ARequest: TLedAIRequest; out ASeq: Integer): Boolean;
      virtual; abstract;
    { Gives up on the turn in flight.  Returns at once: what is behind it may
      take a while to notice, and nothing in the editor waits for that. }
    procedure Stop; virtual; abstract;
    { Everything that has arrived since last time, as events, on the caller's
      thread.  Driven by a timer; it never waits.  True when something
      happened. }
    function Poll: Boolean; virtual; abstract;
    procedure Shutdown; virtual;

    { The models this backend can be pointed at.  False with AWhy set when it
      cannot say. }
    function ModelList(ANames: TStrings; out AWhy: string): Boolean; virtual;

    property State: TLedAIState read FState;
    property Seq: Integer read FSeq;
    property LastError: string read FLastError;
    property Model: string read FModel write FModel;
    property OnDelta: TLedAIDeltaProc read FOnDelta write FOnDelta;
    property OnDone: TLedAIDoneProc read FOnDone write FOnDone;
    property OnError: TLedAIErrorProc read FOnError write FOnError;
    property OnState: TLedAIStateProc read FOnState write FOnState;
    property OnPermission: TLedAIPermissionProc
      read FOnPermission write FOnPermission;
  end;

{ Whether an answer to this is meant to go back where the text came from.

  A question about nothing has nowhere to put an answer, and explaining or
  summarising a paragraph produces prose about it rather than a replacement
  for it -- offering to paste that over the paragraph would be offering to
  replace somebody's text with a description of it. }
function LedAIReplaces(ATask: TLedAITask; AHasContext: Boolean): Boolean;

{ The name of a task, for a menu or a transcript. }
function LedAITaskName(ATask: TLedAITask): string;

{ What the model is told it is for.  One string per task, kept here beside
  the tasks rather than scattered through two backends that would drift. }
function LedAITaskSystem(ATask: TLedAITask): string;

{ A fence long enough to hold AText: three backticks, or one more than the
  longest run already inside it.  A file with a code block in it is the
  ordinary case, not the awkward one, and a three-backtick fence around one
  ends the block three lines early. }
function LedAIFence(const AText: string): string;

{ The instruction and the text it is about, as one prompt.  Pure: the same
  request gives the same string on either backend, with nothing read from
  anywhere. }
function LedAIBuildPrompt(const ARequest: TLedAIRequest): string;

{ As much of AText as is worth sending, cut at a line boundary.  A turn over
  LedPreviewCut, which already cuts at a newline and already says whether it
  had to -- the same reasoning as the preview's cap, for the same reason: a
  cut in the middle of a fence makes nonsense of everything after it. }
function LedAICutContext(const AText: string; ALimitBytes: Integer;
  out ACut: Boolean): string;

{ The text a model meant to hand back, with the wrapping it habitually puts
  around it taken off.

  Deliberately narrow.  Everything this strips is something no model meant as
  content, and the cost of being clever is eating somebody's words:

    no fence                      unchanged, less blank lines at the ends
    exactly one fence             what is inside it
    an info string                dropped with the fence
    chatter before or after       dropped: the fence is the answer
    an opener with no closer      everything after the opener, for a reply
                                  cut off part way
    two or more fences            unchanged -- two snippets have no single
                                  answer, and picking one loses the other
    ~~~ instead of backticks      the same
    a longer fence outside a
    shorter one                   the inner fences survive

  A "Here is the rewritten text:" with no fence after it is left alone.
  Stripping that would mean guessing which sentences are the answer. }
function LedAIUnfence(const AText: string): string;

implementation

uses
  StrUtils;

{ ----- the conversation ------------------------------------------------- }

constructor TLedAIChat.Create;
begin
  inherited Create;
  FTexts := TStringList.Create;
end;

destructor TLedAIChat.Destroy;
begin
  FTexts.Free;
  inherited Destroy;
end;

procedure TLedAIChat.Add(ARole: TLedAIRole; const AText: string);
begin
  FTexts.AddObject(AText, TObject(PtrUInt(Ord(ARole))));
end;

procedure TLedAIChat.Clear;
begin
  FTexts.Clear;
end;

function TLedAIChat.Count: Integer;
begin
  Result := FTexts.Count;
end;

function TLedAIChat.Role(AIndex: Integer): TLedAIRole;
begin
  Result := TLedAIRole(PtrUInt(FTexts.Objects[AIndex]));
end;

function TLedAIChat.Text(AIndex: Integer): string;
begin
  Result := FTexts[AIndex];
end;

procedure TLedAIChat.TrimTo(ABytes: Integer);
var
  Total, i: Integer;
begin
  Total := 0;
  for i := 0 to FTexts.Count - 1 do
    Inc(Total, Length(FTexts[i]));

  { From the front, because the oldest turn is the one the model needs
    least -- and never the last one, which is the question being asked. }
  while (Total > ABytes) and (FTexts.Count > 1) do
  begin
    Dec(Total, Length(FTexts[0]));
    FTexts.Delete(0);
  end;
end;

{ ----- the backend ------------------------------------------------------ }

constructor TLedAIBackend.Create(AChat: TLedAIChat);
begin
  inherited Create;
  FChat := AChat;
  FState := laiOff;
end;

procedure TLedAIBackend.SetState(AState: TLedAIState);
begin
  if FState = AState then Exit;
  FState := AState;
  if Assigned(FOnState) then FOnState(Self, AState);
end;

function TLedAIBackend.Current(ASeq: Integer): Boolean;
begin
  Result := ASeq = FSeq;
end;

procedure TLedAIBackend.Emit(const ADelta: TLedAIDelta);
begin
  { A delta from a turn that has been given up on is not shown.  This is the
    whole of what makes Stop instant: the socket may still be delivering an
    answer nobody wants, and it goes nowhere. }
  if not Current(ADelta.Seq) then Exit;
  if Assigned(FOnDelta) then FOnDelta(Self, ADelta);
end;

procedure TLedAIBackend.Finish(const AResult: TLedAIResult);
begin
  if not Current(AResult.Seq) then Exit;
  SetState(laiIdle);
  if Assigned(FOnDone) then FOnDone(Self, AResult);
end;

procedure TLedAIBackend.Fail(ASeq: Integer; const AWhy: string);
begin
  FLastError := AWhy;
  if not Current(ASeq) then Exit;
  SetState(laiIdle);
  if Assigned(FOnError) then FOnError(Self, ASeq, AWhy);
end;

function TLedAIBackend.AskPermission(const ATool, ADetail: string): Boolean;
begin
  Result := False;
  if Assigned(FOnPermission) then FOnPermission(Self, ATool, ADetail, Result);
end;

procedure TLedAIBackend.Shutdown;
begin
  SetState(laiOff);
end;

function TLedAIBackend.ModelList(ANames: TStrings; out AWhy: string): Boolean;
begin
  ANames.Clear;
  AWhy := 'this backend does not offer a choice of model';
  Result := False;
end;

{ ----- the part with no I/O in it --------------------------------------- }

function LedAIReplaces(ATask: TLedAITask; AHasContext: Boolean): Boolean;
begin
  Result := AHasContext and
    (ATask in [laskProofread, laskRewrite, laskComment, laskCustom]);
end;

function LedAITaskName(ATask: TLedAITask): string;
begin
  case ATask of
    laskChat: Result := 'Chat';
    laskProofread: Result := 'Proof-read';
    laskRewrite: Result := 'Rewrite';
    laskExplain: Result := 'Explain';
    laskSummarise: Result := 'Summarise';
    laskComment: Result := 'Comment';
  else
    Result := 'Custom';
  end;
end;

function LedAITaskSystem(ATask: TLedAITask): string;
const
  { Said twice, in two ways, because one way is not enough: a model that is
    only told "no commentary" still writes "Here is the corrected text:"
    often enough to matter, and a model only told to answer with the text
    still wraps it in a fence. }
  OnlyTheText =
    'Reply with the replacement text and nothing else: no explanation, no ' +
    'commentary, no code fence, no introduction.  Do not describe what you ' +
    'changed.  Your entire reply will be put into the file in place of the ' +
    'text you were given.';
begin
  case ATask of
    laskProofread:
      Result := 'You are proof-reading text from a file in an editor.  ' +
        'Correct spelling, grammar and punctuation.  Leave the wording, the ' +
        'formatting, the indentation and the line structure alone unless ' +
        'they are wrong.  ' + OnlyTheText;
    laskRewrite:
      Result := 'You are rewriting text from a file in an editor to be ' +
        'clearer and easier to read.  Keep what it says and keep its ' +
        'formatting.  ' + OnlyTheText;
    laskComment:
      Result := 'You are adding comments to code from a file in an editor.  ' +
        'Keep the code exactly as it is and add comments that say why, not ' +
        'what.  ' + OnlyTheText;
    laskExplain:
      Result := 'You are explaining a piece of a file to the person editing ' +
        'it.  Be brief and concrete.  Do not repeat the text back.';
    laskSummarise:
      Result := 'You are summarising a piece of a file for the person ' +
        'editing it.  Be brief.  Do not repeat the text back.';
    laskChat:
      Result := 'You are helping someone working in a text editor.  Be ' +
        'brief and concrete.  When you show code, put it in a fenced block.';
  else
    Result := '';
  end;
end;

function LedAIFence(const AText: string): string;
var
  i, Run, Longest: Integer;
begin
  Longest := 0;
  Run := 0;
  for i := 1 to Length(AText) do
    if AText[i] = '`' then
    begin
      Inc(Run);
      if Run > Longest then Longest := Run;
    end
    else
      Run := 0;

  if Longest < 3 then Longest := 2;
  Result := StringOfChar('`', Longest + 1);
end;

function LedAIBuildPrompt(const ARequest: TLedAIRequest): string;
var
  Fence, Where: string;
begin
  { A conversation is what was typed.  Wrapping it in ceremony makes the
    answers worse, not better. }
  if (ARequest.Context = '') then
    Exit(ARequest.Instruction);

  Fence := LedAIFence(ARequest.Context);

  Where := 'text';
  if ARequest.ContextName <> '' then
    Where := 'text from ' + ARequest.ContextName;

  Result := ARequest.Instruction + LineEnding + LineEnding +
    'Here is the ' + Where + ':' + LineEnding +
    Fence + ARequest.Language + LineEnding +
    ARequest.Context;

  { The fence has to start its own line, and the text handed over may not
    end with one. }
  if (ARequest.Context <> '') and
     (ARequest.Context[Length(ARequest.Context)] <> #10) then
    Result := Result + LineEnding;

  Result := Result + Fence + LineEnding;
end;

function LedAICutContext(const AText: string; ALimitBytes: Integer;
  out ACut: Boolean): string;
begin
  Result := LedPreviewCut(AText, ALimitBytes, ACut);
end;

{ How long a run of fence characters begins at AFrom, and which character it
  is made of.  0 when the line does not open or close a fence: a fence is at
  least three, and may be indented by up to three spaces, which is Markdown's
  own rule and the one every model writes to. }
function FenceRunAt(const AText: string; AFrom: Integer;
  out AChar: AnsiChar): Integer;
var
  i, Spaces: Integer;
begin
  Result := 0;
  AChar := #0;
  Spaces := 0;
  i := AFrom;
  while (i <= Length(AText)) and (AText[i] = ' ') and (Spaces < 3) do
  begin
    Inc(Spaces);
    Inc(i);
  end;
  if i > Length(AText) then Exit;
  if not (AText[i] in ['`', '~']) then Exit;

  AChar := AText[i];
  while (i <= Length(AText)) and (AText[i] = AChar) do
  begin
    Inc(Result);
    Inc(i);
  end;
  if Result < 3 then
  begin
    Result := 0;
    AChar := #0;
  end;
end;

function LedAIUnfence(const AText: string): string;
var
  Lines: TStringList;
  i, Opens, OpenAt, CloseAt, Run: Integer;
  OpenRun: Integer;
  OpenChar, C: AnsiChar;
begin
  Result := AText;
  if Pos('```', AText) + Pos('~~~', AText) = 0 then
  begin
    { Nothing is fenced.  Blank lines at either end are the model breathing,
      not content. }
    Result := Trim(Result);
    Exit;
  end;

  Lines := TStringList.Create;
  try
    Lines.LineBreak := #10;
    Lines.TrailingLineBreak := False;
    { Setting Text splits on a carriage return as readily as on a newline,
      so a reply from a child process on Windows needs nothing done to it
      first.  WindowsLineEndingsDoNotDefeatIt is what says so. }
    Lines.Text := AText;

    { Count the fences before touching anything.  A reply with two blocks in
      it has no single answer to substitute, and guessing which one was meant
      loses the other. }
    Opens := 0;
    OpenAt := -1;
    CloseAt := -1;
    OpenRun := 0;
    OpenChar := #0;
    i := 0;
    while i < Lines.Count do
    begin
      Run := FenceRunAt(Lines[i], 1, C);
      if Run > 0 then
      begin
        if OpenAt < 0 then
        begin
          Inc(Opens);
          OpenAt := i;
          OpenRun := Run;
          OpenChar := C;
        end
        else if (C = OpenChar) and (Run >= OpenRun) and (CloseAt < 0) then
          { A closer has to be at least as long as its opener and made of the
            same character, which is what lets a four-backtick block hold
            three-backtick ones. }
          CloseAt := i
        else if CloseAt >= 0 then
          Inc(Opens);
      end;
      Inc(i);
    end;

    if (Opens <> 1) or (OpenAt < 0) then Exit;

    { An opener with no closer is a reply that was cut off part way.  What
      arrived is still the answer; the delimiter in front of it is not. }
    if CloseAt < 0 then CloseAt := Lines.Count;

    Result := '';
    for i := OpenAt + 1 to CloseAt - 1 do
    begin
      if Result <> '' then Result := Result + LineEnding;
      Result := Result + Lines[i];
    end;
  finally
    Lines.Free;
  end;
end;

end.
