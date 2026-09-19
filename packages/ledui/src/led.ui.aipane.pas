// led - a lightweight editor.  The pane you talk to a model in.
//
// It knows nothing about ollama, about claude, or about what a tab is.  It
// is given words as they arrive and hands back what the reader asked for,
// the same way the debugger pane knows nothing about gdb: everything that
// crosses the edge of this unit is an event.
//
// Two decisions are worth writing down, because both were measured.
//
// The first is that a finished answer is one HTML bubble, built once, and
// the answer being written is plain text in a box.  IPro relays a page out
// on every repaint, and its layout is worse than quadratic: 8 KiB takes
// 140 ms, 32 KiB 1.9 s, 256 KiB 117 s.  Re-rendering a bubble on every token
// would therefore cost 140 ms a word by the time an answer was a page long,
// and rendering the whole conversation as one page is what the Markdown
// preview does -- which is why the preview had to be capped at 16 KB.  A
// transcript cannot be capped; it is what was said.  So: the turn in flight
// is a read-only memo, appended to, which costs the length of what arrived;
// when it finishes, that memo is replaced by one bubble, laid out once, at
// the moment the reader has stopped watching the words scroll.
//
// A memo and not a SynEdit, for a second reason as well.  The editing keys
// are claimed for whatever box has the caret by Led.UI.EditKeys, and that
// guard deliberately does not match a SynEdit -- so Ctrl+C in a SynEdit
// transcript would reach the main window's Copy action and copy from the
// document instead.  A memo is a TCustomEdit, so copying out of the
// transcript, and pasting into the question box, land where they are aimed.
//
// The second decision is that nothing a model says ever reaches a document
// on its own.  A reply arrives, and it sits there until the reader presses
// Apply.  A model asked to proof-read a file sometimes answers "Certainly!
// Here is the corrected text:" and stops, and an editor that pasted that
// over somebody's file automatically would be an editor that destroys work
// while looking helpful.

unit Led.UI.AIPane;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, StdCtrls, Buttons, Graphics, Forms,
  Clipbrd, LCLType,
  IpHtml, Ipfilebroker,
  LCLIntf,
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  Led.Core.AI, Led.Core.Markdown, Led.Core.Prefs, Led.Core.NBImage,
  Led.Syn.Factory,
  Led.UI.PageStyle, Led.UI.NBPane, Led.UI.DPI, Led.UI.Focus;

type
  { What the pane is about to send with the question. }
  TLedAIAttach = (laaNothing, laaSelection, laaDocument);

  { What the reader wants done with a reply. }
  TLedAIApply = (lapInsert, lapReplaceSelection, lapReplaceDocument,
                 { Opened as a document of its own, which is the answer to
                   "I want to keep this but not here". }
                 lapNewDocument);

  TLedAIAskEvent = procedure(Sender: TObject; const APrompt: string;
    ATask: TLedAITask; AAttach: TLedAIAttach) of object;
  { Filled in by the form, which is the only thing that knows what a tab is.
    ALanguage is the fence's info string, so "comment this code" knows what
    it is looking at. }
  TLedAIContextEvent = procedure(Sender: TObject; AAttach: TLedAIAttach;
    out AText, AName, ALanguage: string) of object;
  TLedAIApplyEvent = procedure(Sender: TObject; ATurn: Integer;
    const AText: string; AKind: TLedAIApply) of object;

  TLedAIPane = class;

  { One thing that was said.  A panel with a header and either the answer
    being written, or the answer. }
  TLedAIBubble = class(TPanel)
  private
    FPane: TLedAIPane;
    FIndex: Integer;
    FRole: TLedAIRole;
    FText: string;              // the raw Markdown, whole and uncut
    FLive: TMemo;               // what was said, as plain text
    FRender: TLedNBProse;       // an assistant's turn, once it has settled
    FProvider: TIpFileDataProvider;
    FBar: TPanel;
    FReplaces: Boolean;
    FCut: Boolean;
    FLayingOut: Boolean;
    { What the button that puts this back into the file should be called:
      the consequence, not the word "apply". }
    FApplyName: string;
    FPage: string;        // the HTML handed to the renderer
    FPageWidth: Integer;  // ...and the width it was measured at
    FThought: string;     // what the model said while working up to it
    FThinkBox: TMemo;     // ...shown, when the reader asks to see it
    FThinkBtn: TButton;
    FButtons: TList;      // in the order they were made, for FlowButtons
    procedure MakeLive;
    procedure ChildWheel(Sender: TObject; AShift: TShiftState;
      AWheelDelta: Integer; AMousePos: TPoint; var AHandled: Boolean);
    procedure HookRenderChildren;
    function Fill: TColor;
    function Padding: Integer;
    function InnerWidth: Integer;
    function LayoutWidth(AWidth: Integer): Integer;
    function FlowButtons(AWidth: Integer): Integer;
    function CodeColumns(AWidth: Integer): Integer;
    function ImageSize(const AURL: string;
      out AWidth, AHeight: Integer): Boolean;
    procedure MakeRender;
    procedure ProvideImage(Sender: TIpHtmlNode; const AURL: string;
      var APicture: TPicture);
    procedure MakeButtons;
    procedure CopyClicked(Sender: TObject);
    procedure NewDocClicked(Sender: TObject);
    procedure ThinkClicked(Sender: TObject);
    procedure InsertClicked(Sender: TObject);
    procedure ApplyClicked(Sender: TObject);
    function Page(AWidth: Integer): string;
    function PageHeight(const APage: string; AWidth: Integer): Integer;
  protected
    procedure Paint; override;
  public
    constructor CreateTurn(AOwner: TLedAIPane; AIndex: Integer;
      ARole: TLedAIRole; const AText: string);
    { Adds to a turn still being written. }
    procedure Grow(const AText: string);
    { Stops being a box of text and becomes a page.  Once. }
    procedure Settle(AReplaces, ACut: Boolean; const AApplyName: string = '');
    procedure Relayout;
    property Text: string read FText;
    property Role: TLedAIRole read FRole;
    { For the self-test: whether this turn has been laid out as a page, and
      what page it was given. }
    { The width the renderer lays a page out in, and how many characters of
      code fit across it.  Published because the two have to agree: more
      columns than fit is every line of an answer's code running off the
      edge. }
    function LayoutRoom: Integer;
    function CodeFits: Integer;
    function FixedCharWidth: Integer;
    function Rendered: Boolean;
    { Whether this turn is drawn as a box. }
    function Boxed: Boolean;
    { Whether this turn offers to go back into the file, and what the
      button that does it says it will do. }
    function OffersApply: Boolean;
    function ApplyCaption: string;
    { What this turn offers to do with itself, and doing it the way a
      reader does: by pressing the button. }
    function ButtonNames: string;
    function PressButton(const ACaption: string): Boolean;
    { What the model said while working up to its answer, and whether it is
      on show. }
    procedure Thought(const AText: string);
    procedure ShowThinking(AOn: Boolean);
    function Thinking: string;
    function ThinkingShown: Boolean;
    function RenderedPage: string;
    function LiveText: string;
    function ShownText: string;
    { The control the words are in, so a check can turn the wheel over it
      the way a reader would. }
    function BodyControl: TWinControl;
    { The colour it is drawn on, so a check can say the two sides of the
      conversation do not look alike. }
    function Colour: TColor;
  end;

  TLedAIPane = class(TPanel)
  private
    FRoll: TScrollBox;
    FTop: TPanel;
    FStatus: TLabel;
    FBackends: TComboBox;
    FModels: TComboBox;
    FStop: TButton;
    FClear: TButton;
    FSend: TButton;
    FAttach: TComboBox;
    FTask: TComboBox;
    FInput: TMemo;
    FBottom: TPanel;
    FTurns: TList;
    FLive: TLedAIBubble;
    FThinking: Boolean;
    FThinkTimer: TTimer;
    FAskedAt: TDateTime;
    FModelSaid: string;
    FHasSelection: Boolean;
    FAttachPinned: Boolean;
    FRelayoutQueued: Boolean;
    FOnAsk: TLedAIAskEvent;
    FOnStop: TNotifyEvent;
    FOnNeedContext: TLedAIContextEvent;
    FOnApply: TLedAIApplyEvent;
    FOnBackendChanged: TNotifyEvent;
    procedure SendClicked(Sender: TObject);
    procedure StopClicked(Sender: TObject);
    procedure ClearClicked(Sender: TObject);
    procedure InputKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Ticked(Sender: TObject);
    procedure BackendPicked(Sender: TObject);
    procedure AttachPicked(Sender: TObject);
    function AddTurn(ARole: TLedAIRole; const AText: string): TLedAIBubble;
    procedure DropOldest;
    procedure ScrollToEnd;
    procedure RelayoutSoon(Data: PtrInt);
    procedure Restack;
    procedure LayoutBars;
    { One notch of the wheel, wherever it was turned.  True when there was
      something to scroll. }
    function WheelNotch(AWheelDelta: Integer): Boolean;
  protected
    procedure Resize; override;
    function DoMouseWheel(AShift: TShiftState; AWheelDelta: Integer;
      AMousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { The four things a backend says. }
    procedure BeginReply;
    procedure AddWords(const AText: string);
    procedure AddThinking(const AText: string);
    procedure AddDelta(const ADelta: TLedAIDelta);
    procedure EndReply(const AResult: TLedAIResult);
    procedure Failed(const AWhy: string);

    { What the form tells it. }
    procedure SetBackends(AList: TStrings; const AActive: string);
    procedure SetModels(AList: TStrings; const AActive: string);
    procedure SetAvailable(AOn: Boolean; const AWhy: string);
    procedure NoteSelection(AHas: Boolean);
    procedure Clear;

    { Asks, as if it had been typed and sent. }
    procedure Ask(const AText: string; ATask: TLedAITask = laskChat);

    { For the self-test, and for the form's own use. }
    function TurnCount: Integer;
    function Turn(AIndex: Integer): TLedAIBubble;
    function LastReply: string;
    function BubbleCount: Integer;
    function StreamText: string;
    function Thinking: Boolean;
    function StopEnabled: Boolean;
    function StatusText: string;
    function Attach: TLedAIAttach;
    function ApplyName: string;
    procedure PickAttach(AKind: TLedAIAttach);
    function Task: TLedAITask;
    procedure PickTask(ATask: TLedAITask);
    procedure ApplyTurn(ATurn: Integer; AKind: TLedAIApply);
    function InputControl: TWinControl;
    { The two strips below the conversation, so a check can say they are in
      the order a reader reads them in. }
    function StatusControl: TControl;
    function SendBar: TControl;
    function Transcript: TControl;
    { Where the conversation is scrolled to, and how far there is to go. }
    function ScrollPos: Integer;
    procedure ScrollTo(APos: Integer);
    function ScrollRange: Integer;
    function BackendName: string;
    function ModelName: string;
    procedure TypePrompt(const AText: string);
    function PressEnter(AShift: TShiftState): Boolean;

    property OnAsk: TLedAIAskEvent read FOnAsk write FOnAsk;
    property OnStop: TNotifyEvent read FOnStop write FOnStop;
    property OnNeedContext: TLedAIContextEvent
      read FOnNeedContext write FOnNeedContext;
    property OnApply: TLedAIApplyEvent read FOnApply write FOnApply;
    property OnBackendChanged: TNotifyEvent
      read FOnBackendChanged write FOnBackendChanged;
  end;

{ How many fenced blocks are in a reply, and what the ACount'th one says --
  without its fence, so that what reaches the clipboard is code and not
  three backticks and a language name.

  Free functions, in this unit rather than in the core, because they are
  about what a reader can press a button on rather than about what a model
  said. }
function LedAICodeBlocks(const AText: string): Integer;
function LedAICodeBlock(const AText: string; AIndex: Integer): string;

implementation

uses
  Math, DateUtils;

const
  { Past this many turns the oldest are let go of.  A few hundred widgets is
    cheap -- the notebook pane measured 424 of them at 59 ms and 16 MB -- but
    an afternoon's conversation is not a few hundred. }
  MostTurns = 40;

{ How wide a button has to be for its caption.

  Measured on a bitmap, not on the control's own canvas.  A control with no
  parent yet has no handle, and asking it for a canvas during its own
  constructor makes one -- which is how the window came to hang before it
  was ever shown.  A bitmap has a canvas of its own and needs nobody. }
{ How big prose in an answer is drawn.  Said in one place because the
  measurement and the panel have to agree: a page measured at one size and
  drawn at another comes out the wrong height. }
function ProseSize: Integer;
begin
  Result := 10;
end;

{ The face the reader edits in, which is the one a code block belongs in. }
function FixedFace: string;
var
  Size: Integer;
begin
  LedParseFontSpec(LedPrefs.GetStr(LedPrefFont, ''), Result, Size);
  if Result = '' then Result := 'Monospace';
end;

function TextRoom(AFont: TFont; const AText: string): Integer;
var
  B: TBitmap;
begin
  B := TBitmap.Create;
  try
    B.Canvas.Font.Assign(AFont);
    Result := B.Canvas.TextWidth(AText);
  finally
    B.Free;
  end;
end;

{ How tall AText comes out at AWidth once it has been wrapped.

  Counting lines and multiplying is what this replaced, and it is wrong in
  the one case that matters: a wrapped line is several lines tall and counts
  as one, so a paragraph of an answer was given a single line of room. }
function TextBlockHeight(AFont: TFont; const AText: string;
  AWidth: Integer): Integer;
var
  B: TBitmap;
  R: TRect;
  Said: string;
begin
  Said := AText;
  if Said = '' then Said := 'Mg';
  B := TBitmap.Create;
  try
    B.Canvas.Font.Assign(AFont);
    R := Rect(0, 0, AWidth, 0);
    DrawText(B.Canvas.Handle, PChar(Said), Length(Said), R,
      DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
    Result := R.Bottom - R.Top;
  finally
    B.Free;
  end;
end;

{ How tall one line of it is, measured the same way and for the same
  reason. }
function TextTall(AFont: TFont): Integer;
var
  B: TBitmap;
begin
  B := TBitmap.Create;
  try
    B.Canvas.Font.Assign(AFont);
    Result := B.Canvas.TextHeight('Mg');
  finally
    B.Free;
  end;
end;

{ ----- the fenced blocks of a reply -------------------------------------- }

procedure BlocksOf(const AText: string; AList: TStrings);
var
  Lines: TStringList;
  i, Run: Integer;
  Inside: Boolean;
  Fence: string;
  Block: string;

  function FenceAt(const ALine: string; out ARun: Integer): Boolean;
  var
    j, Spaces: Integer;
    C: Char;
  begin
    Result := False;
    ARun := 0;
    Spaces := 0;
    j := 1;
    while (j <= Length(ALine)) and (ALine[j] = ' ') and (Spaces < 3) do
    begin
      Inc(Spaces);
      Inc(j);
    end;
    if j > Length(ALine) then Exit;
    if not (ALine[j] in ['`', '~']) then Exit;
    C := ALine[j];
    while (j <= Length(ALine)) and (ALine[j] = C) do
    begin
      Inc(ARun);
      Inc(j);
    end;
    Result := ARun >= 3;
  end;

begin
  AList.Clear;
  Lines := TStringList.Create;
  try
    Lines.TrailingLineBreak := False;
    Lines.Text := AText;
    Inside := False;
    Block := '';
    for i := 0 to Lines.Count - 1 do
    begin
      if FenceAt(Lines[i], Run) then
      begin
        if Inside then
        begin
          AList.Add(Block);
          Block := '';
          Inside := False;
        end
        else
          Inside := True;
        Continue;
      end;
      if Inside then
      begin
        if Block <> '' then Block := Block + LineEnding;
        Block := Block + Lines[i];
      end;
    end;
    { A block that never closed is still a block: a reply cut off part way
      has code in it, and refusing to hand it over helps nobody. }
    if Inside and (Block <> '') then AList.Add(Block);
  finally
    Lines.Free;
  end;
end;

function LedAICodeBlocks(const AText: string): Integer;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    BlocksOf(AText, L);
    Result := L.Count;
  finally
    L.Free;
  end;
end;

function LedAICodeBlock(const AText: string; AIndex: Integer): string;
var
  L: TStringList;
begin
  Result := '';
  L := TStringList.Create;
  try
    BlocksOf(AText, L);
    if (AIndex >= 0) and (AIndex < L.Count) then Result := L[AIndex];
  finally
    L.Free;
  end;
end;

{ ----- one turn ---------------------------------------------------------- }

constructor TLedAIBubble.CreateTurn(AOwner: TLedAIPane; AIndex: Integer;
  ARole: TLedAIRole; const AText: string);
begin
  inherited Create(AOwner);
  { Its height is worked out, never guessed at by the LCL. }
  AutoSize := False;
  FPane := AOwner;
  FIndex := AIndex;
  FRole := ARole;
  FText := AText;
  Parent := AOwner.FRoll;
  { Placed by the pane rather than aligned to the top of the box.  Children
    aligned inside a scroll box re-enter the layout when the scrollbar
    appears, and the LCL throws out of that with "InvalidatePreferredSize
    loop detected" -- which is why the notebook pane places its cells by
    hand too. }
  Align := alNone;
  BevelOuter := bvNone;
  Color := LedPageColours.Page;
  ParentColor := False;
  { Both sides get one.  The reader's own words were kept and never shown,
    which made their half of the conversation a row of empty headings. }
  MakeLive;
  if AText <> '' then FLive.Text := AText;
  Relayout;
end;

{ The colour this turn is drawn on.

  Which of the two said something is told by shape rather than by a word in
  front of it: the reader's turns are a rounded box, indented, in a colour
  picked out from the page, and the model's are simply the page.  Most of a
  transcript is the model talking, so most of a transcript should look like
  the pane it is in; labelling every one of them "Assistant" spends a line
  saying what is already obvious. }
function TLedAIBubble.Fill: TColor;
var
  C: TLedPageColours;
begin
  C := LedPageColours;
  if FRole = larUser then
    { Towards the link colour, which is the one colour in the scheme chosen
      to stand out against the page and still be readable on it. }
    Result := LedMixColours(C.Page, C.Link, 86)
  else
    Result := C.Page;
end;

procedure TLedAIBubble.Paint;
var
  R: TRect;
  Round_: Integer;
begin
  R := ClientRect;
  { The pane behind it first, so the corners that are cut away show the
    scroll box and not whatever was underneath. }
  Canvas.Brush.Color := FPane.FRoll.Color;
  Canvas.FillRect(R);
  if not Boxed then Exit;

  Round_ := LedScale96(10);
  Canvas.Brush.Color := Fill;
  Canvas.Pen.Color := LedMixColours(Fill, LedPageColours.Text, 88);
  Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round_, Round_);
end;

{ How far in from the edge a turn sits.  A box needs room around its words
  for the rounding to be a rounding; the model's text is the page and needs
  none. }
{ Whether this turn is drawn as a box at all.  Only the reader's are: most
  of a transcript is the model talking, and an outline around every answer
  is the wall of boxes the headings were removed to be rid of. }
function TLedAIBubble.Boxed: Boolean;
begin
  Result := FRole = larUser;
end;

function TLedAIBubble.Padding: Integer;
begin
  if Boxed then Result := LedScale96(8)
  else Result := LedScale96(2);
end;

procedure TLedAIBubble.MakeLive;
begin
  FLive := TMemo.Create(Self);
  FLive.Parent := Self;
  FLive.Align := alNone;
  FLive.ReadOnly := True;
  FLive.ScrollBars := ssNone;
  FLive.WordWrap := True;
  FLive.BorderStyle := bsNone;
  { The bubble's own colour, so the box does not show as a rectangle inside
    the rounded shape. }
  FLive.Color := Fill;
  FLive.Font.Color := LedPageColours.Text;
  FLive.Height := LedScale96(20);
  { A memo keeps the wheel for itself and has nothing to scroll, being
    exactly as tall as its text.  The notch belongs to the pane. }
  FLive.OnMouseWheel := @ChildWheel;
end;

{ Every windowed child keeps the wheel and none of them has anywhere to go
  with it, so it is handed to the pane -- which is what the reader meant by
  turning it. }
procedure TLedAIBubble.ChildWheel(Sender: TObject; AShift: TShiftState;
  AWheelDelta: Integer; AMousePos: TPoint; var AHandled: Boolean);
begin
  AHandled := FPane.WheelNotch(AWheelDelta);
end;

{ The renderer makes its own inner control when it is given a page, so this
  runs after every SetHtmlFromStr and not only once. }
procedure TLedAIBubble.HookRenderChildren;

  procedure Hook(AControl: TWinControl);
  var
    i: Integer;
    C: TControl;
  begin
    for i := 0 to AControl.ControlCount - 1 do
    begin
      C := AControl.Controls[i];
      TControlEvents(C).OnMouseWheel := @ChildWheel;
      if C is TWinControl then Hook(TWinControl(C));
    end;
  end;

begin
  if FRender <> nil then Hook(FRender);
end;

procedure TLedAIBubble.ProvideImage(Sender: TIpHtmlNode; const AURL: string;
  var APicture: TPicture);
begin
  { Nothing is fetched.  A model naming a picture is not a reason to open a
    socket, and a name that is not there must not raise inside a paint --
    which is what this hook is for, and what the notebook pane learned the
    hard way. }
  APicture := nil;
end;

procedure TLedAIBubble.MakeRender;
var
  C: TLedPageColours;
begin
  if FRender <> nil then Exit;
  C := LedPageColours;
  FProvider := TIpFileDataProvider.Create(Self);
  FProvider.OnGetImage := @ProvideImage;
  FRender := TLedNBProse.Create(Self);
  FRender.Parent := Self;
  FRender.Align := alNone;
  FRender.DataProvider := FProvider;
  FRender.OnWheelPassedUp := @ChildWheel;
  FRender.DefaultTypeFace := Screen.SystemFont.Name;
  FRender.DefaultFontSize := ProseSize;
  { The editor's own face for anything fixed-width.  The pane's font is the
    menu font, and a code block in an answer drawn in the menu font is not
    a code block -- which is what it looked like. }
  FRender.FixedTypeface := FixedFace;
  FRender.BgColor := Fill;
  FRender.TextColor := C.Text;
  FRender.LinkColor := C.Link;
  FRender.VLinkColor := C.Link;
  FRender.ALinkColor := C.Link;
end;

procedure TLedAIBubble.MakeButtons;

  function Add(const ACaption: string; AOn: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := FBar;
    { Placed by FlowButtons, in rows.  Aligned left they came out in the
      reverse of the order they were made in, and the ones that did not fit
      were simply not there -- which at this width was most of them. }
    Result.Align := alNone;
    FButtons.Add(Result);
    { A width worked out here rather than AutoSize.  A button that sizes
      itself, on a strip whose height feeds the bubble's height, is a loop
      the LCL notices and throws out of: "InvalidatePreferredSize loop
      detected". }
    Result.AutoSize := False;
    Result.Width := TextRoom(Font, ACaption) + LedScale96(20);
    Result.Height := LedScale96(24);
    Result.Caption := ACaption;
    Result.OnClick := AOn;
  end;

begin
  if FBar <> nil then Exit;
  FButtons := TList.Create;
  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alNone;
  FBar.BevelOuter := bvNone;
  FBar.Color := Fill;
  FBar.ParentColor := False;
  FBar.Height := LedScale96(24);

  Add('Copy', @CopyClicked);
  Add('Insert at caret', @InsertClicked);
  { Somewhere to put an answer that is worth keeping and does not belong in
    the file being edited -- which is most of them. }
  Add('New document', @NewDocClicked);

  { The one that changes a file says nothing at all when it cannot be
    offered honestly: a whole-document replacement built from part of a
    document is silent truncation. }
  if FReplaces and not FCut then
    Add(FApplyName, @ApplyClicked);

  { Only when there is something to see. }
  if FThought <> '' then FThinkBtn := Add('Thinking', @ThinkClicked);
end;

procedure TLedAIBubble.CopyClicked(Sender: TObject);
begin
  Clipboard.AsText := FText;
end;

procedure TLedAIBubble.NewDocClicked(Sender: TObject);
begin
  if Assigned(FPane.FOnApply) then
    FPane.FOnApply(FPane, FIndex, FText, lapNewDocument);
end;

{ Thinking is kept whether or not anybody looks at it, and shown only when
  they ask.  It is usually longer than the answer and it is not the answer:
  a pane that showed it by default would bury what was asked for. }
procedure TLedAIBubble.Thought(const AText: string);
begin
  FThought := FThought + AText;
end;

procedure TLedAIBubble.ThinkClicked(Sender: TObject);
begin
  ShowThinking(FThinkBox = nil);
end;

procedure TLedAIBubble.ShowThinking(AOn: Boolean);
begin
  if AOn = (FThinkBox <> nil) then Exit;
  if AOn then
  begin
    FThinkBox := TMemo.Create(Self);
    FThinkBox.Parent := Self;
    FThinkBox.Align := alNone;
    FThinkBox.ReadOnly := True;
    FThinkBox.ScrollBars := ssNone;
    FThinkBox.WordWrap := True;
    FThinkBox.BorderStyle := bsNone;
    FThinkBox.Color := LedMixColours(Fill, LedPageColours.Text, 94);
    { Set apart from the answer by more than its position: it is the
      model's working, and it must not read as something to act on. }
    FThinkBox.Font.Color := LedPageColours.Muted;
    FThinkBox.Font.Style := [fsItalic];
    FThinkBox.Text := FThought;
    FThinkBox.OnMouseWheel := @ChildWheel;
  end
  else
    FreeAndNil(FThinkBox);

  if FThinkBtn <> nil then
  begin
    if FThinkBox <> nil then FThinkBtn.Caption := 'Hide thinking'
    else FThinkBtn.Caption := 'Thinking';
    { Measured again for the new caption.  A button keeps the width it was
      given, so the longer of the two words was cut in half. }
    FThinkBtn.Width := TextRoom(Font, FThinkBtn.Caption) + LedScale96(20);
  end;
  Relayout;
  FPane.Restack;
end;

function TLedAIBubble.Thinking: string;
begin
  Result := FThought;
end;

function TLedAIBubble.ThinkingShown: Boolean;
begin
  Result := FThinkBox <> nil;
end;

procedure TLedAIBubble.InsertClicked(Sender: TObject);
begin
  if Assigned(FPane.FOnApply) then
    FPane.FOnApply(FPane, FIndex, FText, lapInsert);
end;

procedure TLedAIBubble.ApplyClicked(Sender: TObject);
begin
  { Unfenced on the way out: a model told to answer with the text alone
    still wraps it, and three backticks in the middle of somebody's file is
    not what Apply promised. }
  if Assigned(FPane.FOnApply) then
    FPane.FOnApply(FPane, FIndex, LedAIUnfence(FText), lapReplaceSelection);
end;

procedure TLedAIBubble.Grow(const AText: string);
begin
  FText := FText + AText;
  if FLive = nil then Exit;
  { Appended through the selection rather than by rebuilding Lines: setting
    the whole text again costs the length of the answer so far, on every
    word of it. }
  FLive.SelStart := Length(FLive.Text);
  FLive.SelText := AText;
  Relayout;
  FPane.Restack;
end;

{ What this turn is showing, as opposed to what it is remembering.  A check
  that reads FText only proves the pane kept the words; the reader's
  complaint was that it kept them and showed nothing. }
function TLedAIBubble.ShownText: string;
begin
  Result := '';
  if (FLive <> nil) and FLive.Visible then Result := FLive.Text
  else if FRender <> nil then Result := FText;
end;

{ An answer as a page, by the same route the Markdown preview takes.

  Not a shorter one.  Everything the preview does to a page it does because
  the renderer needed it: a picture nobody has fetched cannot be drawn while
  the page is being laid out, a picture wider than the pane loses its
  right-hand side, a long line of code in a <pre> runs off the edge because
  this renderer will not wrap one, and a page whose inline runs are not
  split takes 2700 ms to lay out where the split one takes 22.  An answer
  full of Markdown is the same problem as a document full of it. }
function TLedAIBubble.Page(AWidth: Integer): string;
var
  C: TLedPageColours;
  Html: string;
begin
  C := LedPageColours;
  { With the line ids the preview asks for: they cost nothing here and they
    are what a click on a block could be traced back with. }
  Html := LedMarkdownToHTML(FText, True);
  { Nothing here fetches anything, so every remote picture is replaced by a
    line saying so -- which is what passing no hook means. }
  Html := LedNBHideRemoteImages(Html);
  Html := LedNBFitImages(Html, LayoutWidth(AWidth), @ImageSize);
  Result := LedPageHead('', C, 8) + Html + LedPageTail;
  Result := LedSplitInlineRuns(LedWrapPreLines(Result, CodeColumns(AWidth)));
  { IPro cannot draw a <pre> at all, and a fenced block that names its
    language goes uncoloured without this -- the same treatment the
    notebook's cells and the preview's pages get. }
  Result := LedPageColourCode(Result, C.Text, C.CodeBg);
end;

{ The width the renderer actually has to lay a page out in.

  Three things come out of the panel's width before the text sees any of
  it: the renderer's own margin on each side, and the vertical scrollbar,
  which anything long enough to need one takes out of the middle.  Getting
  this wrong is not a rounding error -- measure wide and the page wraps
  into more lines than it was given room for, which is the scrollbar it was
  trying to avoid, and then a horizontal one underneath it. }
function TLedAIBubble.LayoutWidth(AWidth: Integer): Integer;
var
  Margin: Integer;
begin
  Margin := LedScale96(8);
  if FRender <> nil then Margin := FRender.MarginWidth;
  Result := AWidth - 2 * Margin - GetSystemMetrics(SM_CXVSCROLL);
  { A little more off, because the wrap is in characters and the last one
    on a line must still fit whole. }
  Dec(Result, LedScale96(4));
  if Result < LedScale96(60) then Result := LedScale96(60);
end;

{ How many characters of code fit across, for the wrapping above.  Measured
  in the face and size the code will be drawn in, because those are the
  characters that have to fit. }
function TLedAIBubble.CodeColumns(AWidth: Integer): Integer;
var
  B: TBitmap;
  CharW: Integer;
begin
  Result := 16;
  B := TBitmap.Create;
  try
    B.Canvas.Font.Name := FixedFace;
    { At the size the code is actually drawn at, which is the page's own
      size and not a size smaller.  Measured two points small, twenty-three
      characters were thought to fit where nineteen do, and every line of
      an answer's code ran off the right-hand edge. }
    B.Canvas.Font.Size := ProseSize;
    { Over twenty characters, because one of them rounds badly. }
    CharW := B.Canvas.TextWidth(StringOfChar('0', 20)) div 20;
    if CharW < 1 then Exit;
    Result := LayoutWidth(AWidth) div CharW;
    { Narrower than this and the wrapping is worse than the overflow it is
      there to prevent. }
    if Result < 16 then Result := 16;
  finally
    B.Free;
  end;
end;

{ A picture's size, for LedNBFitImages.  Nothing is fetched, so nothing has
  one: every picture is left at its natural size and the fitting pass has
  nothing to do.  The hook is here because the function asks for one. }
function TLedAIBubble.ImageSize(const AURL: string;
  out AWidth, AHeight: Integer): Boolean;
begin
  AWidth := 0;
  AHeight := 0;
  Result := False;
end;

{ How tall the page is at the width it will be drawn at.

  Measured narrower, on purpose.  The renderer lays out inside margins of
  its own, so a page measured at the panel's full width wraps into more
  lines than it was given room for -- and a bubble too short for its answer
  grows a scrollbar, which is the one thing a bubble must not do.  Too tall
  costs a little white space; too short costs the end of the answer. }
function TLedAIBubble.PageHeight(const APage: string;
  AWidth: Integer): Integer;
var
  Doc: TIpHtmlMeasure;
  Stream: TStringStream;
  Surface: TBitmap;
  H: Integer;
begin
  Result := LedScale96(40);
  { A bitmap's canvas rather than the bubble's own: the bubble may not be on
    screen yet, and a control with no handle makes one when it is asked for
    a canvas.  The faces the measurement uses are said out loud below
    anyway, which is what the canvas would otherwise have carried. }
  Surface := TBitmap.Create;
  Doc := TIpHtmlMeasure.Create;
  Stream := TStringStream.Create(APage);
  try
    try
      { The same faces the panel was given: a page measured in one font and
        drawn in another comes out the wrong height, and too little room is
        a bubble with a scrollbar in it. }
      Doc.DefaultTypeFace := Screen.SystemFont.Name;
      Doc.DefaultFontSize := ProseSize;
      Doc.FixedTypeface := FixedFace;
      Doc.OnGetImageX := @ProvideImage;
      Doc.LoadFromStream(Stream);
      H := Doc.PageHeightAt(Surface.Canvas, LayoutWidth(AWidth));
      { Two lines of slack.  The throwaway layout and the renderer's own
        agree closely and not exactly, and the two costs are not
        comparable: a little too much room is white space, a little too
        little is a scrollbar inside a bubble. }
      if H > 0 then Result := H + TextTall(Font) * 2;
    except
      { A page that will not lay out gets the default rather than taking the
        pane down with it. }
    end;
  finally
    Stream.Free;
    Doc.Free;
    Surface.Free;
  end;
  { gtk2 measures a control in sixteen signed bits, and a box taller than
    that does not come back taller, it comes back wrong. }
  if Result > 30000 then Result := 30000;
end;

procedure TLedAIBubble.Settle(AReplaces, ACut: Boolean;
  const AApplyName: string);
begin
  FReplaces := AReplaces;
  FCut := ACut;
  FApplyName := AApplyName;
  if FApplyName = '' then FApplyName := 'Apply';
  { The words stay in FText; only the plain box goes, replaced by the page
    that was built from them. }
  FreeAndNil(FLive);
  MakeRender;
  MakeButtons;

  { Measured at the width it will be drawn at, which is the width inside
    the rounded edge and not the width of the bubble.  Measuring at one and
    drawing at the other wraps the text into more lines than were paid for,
    and a turn too short for its own answer scrolls inside itself -- which
    is the one thing a bubble must never do. }
  FPageWidth := InnerWidth;
  FPage := Page(FPageWidth);
  FRender.Height := PageHeight(FPage, FPageWidth);
  FRender.SetHtmlFromStr(FPage);
  HookRenderChildren;
  Relayout;
  FPane.Restack;
end;

{ The room inside the rounded edge: what every child is given, and what the
  page is measured against. }
{ The buttons, left to right and on to the next row when the next one will
  not fit.  A docked pane is about two hundred points across and the things
  a reader can do with an answer do not fit across it in one line; hiding
  the ones that do not fit is not an answer, because Copy was one of
  them. }
function TLedAIBubble.FlowButtons(AWidth: Integer): Integer;
var
  i, X, Y, Gap, RowH: Integer;
  B: TButton;
begin
  Gap := LedScale96(4);
  RowH := LedScale96(24);
  X := 0;
  Y := 0;
  for i := 0 to FButtons.Count - 1 do
  begin
    B := TButton(FButtons[i]);
    if (X > 0) and (X + B.Width > AWidth) then
    begin
      X := 0;
      Inc(Y, RowH + Gap);
    end;
    B.SetBounds(X, Y, Min(B.Width, AWidth), RowH);
    Inc(X, B.Width + Gap);
  end;
  Result := Y + RowH;
end;

function TLedAIBubble.InnerWidth: Integer;
begin
  Result := Width - Padding * 2;
  if Result < LedScale96(40) then Result := LedScale96(40);
end;

procedure TLedAIBubble.Relayout;
var
  Pad, Inner, Y: Integer;
begin
  { Setting a height inside a scroll box lays the box out again, which can
    come back here.  Once is enough. }
  if FLayingOut then Exit;
  FLayingOut := True;
  try
    { Room for the rounded edge to show, where there is one.  Children are
      placed by hand rather than aligned, so that the corners are not
      painted over. }
    Pad := Padding;
    Inner := InnerWidth;

    { A pane made narrower wraps the answer into more lines, so the page is
      measured again -- but only when the width it was measured at has
      actually changed, because measuring is a whole layout of the page. }
    if (FRender <> nil) and (Inner <> FPageWidth) and (FPage <> '') then
    begin
      FPageWidth := Inner;
      FRender.Height := PageHeight(FPage, Inner);
    end;

    Y := Pad;

    if (FLive <> nil) and FLive.Visible then
    begin
      { As tall as the words are once wrapped, so a turn never scrolls
        inside itself -- the pane is what scrolls. }
      { Measured a little narrower than it is drawn, and given a spare
        line.  A memo wraps inside its own margins, so text measured at the
        full width wraps into more lines than were paid for -- and the
        difference is not a scrollbar here, it is the end of the sentence
        simply not being shown. }
      FLive.SetBounds(Pad, Y, Inner,
        Max(LedScale96(16),
            TextBlockHeight(FLive.Font, FLive.Text, Inner - LedScale96(8)) +
            TextTall(FLive.Font)));
      Inc(Y, FLive.Height);
    end;

    if FRender <> nil then
    begin
      FRender.SetBounds(Pad, Y, Inner, FRender.Height);
      Inc(Y, FRender.Height);
    end;

    if FBar <> nil then
    begin
      Inc(Y, LedScale96(2));
      FBar.SetBounds(Pad, Y, Inner, FlowButtons(Inner));
      Inc(Y, FBar.Height);
    end;

    if FThinkBox <> nil then
    begin
      Inc(Y, LedScale96(4));
      FThinkBox.SetBounds(Pad, Y, Inner,
        Max(LedScale96(16),
            TextBlockHeight(FThinkBox.Font, FThinkBox.Text,
              Inner - LedScale96(8)) + TextTall(FThinkBox.Font)));
      Inc(Y, FThinkBox.Height);
    end;

    Height := Y + Pad;
  finally
    FLayingOut := False;
  end;
end;

function TLedAIBubble.LayoutRoom: Integer;
begin
  Result := LayoutWidth(InnerWidth);
end;

function TLedAIBubble.CodeFits: Integer;
begin
  Result := CodeColumns(InnerWidth);
end;

function TLedAIBubble.FixedCharWidth: Integer;
var
  B: TBitmap;
begin
  B := TBitmap.Create;
  try
    B.Canvas.Font.Name := FixedFace;
    B.Canvas.Font.Size := ProseSize;
    Result := B.Canvas.TextWidth(StringOfChar('0', 20)) div 20;
  finally
    B.Free;
  end;
end;

function TLedAIBubble.Rendered: Boolean;
begin
  Result := FRender <> nil;
end;

function TLedAIBubble.ButtonNames: string;
var
  i: Integer;
begin
  Result := '';
  if FButtons = nil then Exit;
  for i := 0 to FButtons.Count - 1 do
  begin
    if Result <> '' then Result := Result + '|';
    Result := Result + TButton(FButtons[i]).Caption;
  end;
end;

function TLedAIBubble.PressButton(const ACaption: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if FButtons = nil then Exit;
  for i := 0 to FButtons.Count - 1 do
    if TButton(FButtons[i]).Caption = ACaption then
    begin
      TButton(FButtons[i]).Click;
      Exit(True);
    end;
end;

function TLedAIBubble.ApplyCaption: string;
begin
  Result := FApplyName;
end;

function TLedAIBubble.OffersApply: Boolean;
var
  i: Integer;
begin
  Result := False;
  if FBar = nil then Exit;
  for i := 0 to FBar.ControlCount - 1 do
    if (FBar.Controls[i] is TButton) and
       (TButton(FBar.Controls[i]).Caption = FApplyName) then
      Exit(True);
end;

function TLedAIBubble.RenderedPage: string;
begin
  Result := '';
  if FRender <> nil then Result := Page(Max(LedScale96(80), Width));
end;

function TLedAIBubble.BodyControl: TWinControl;
begin
  if (FLive <> nil) and FLive.Visible then Result := FLive
  else Result := FRender;
end;

function TLedAIBubble.Colour: TColor;
begin
  Result := Fill;
end;

function TLedAIBubble.LiveText: string;
begin
  Result := '';
  if FLive <> nil then Result := FLive.Text;
end;

{ ----- the pane ---------------------------------------------------------- }

constructor TLedAIPane.Create(AOwner: TComponent);

  { Placed, not aligned.  A combo box has a height of its own that the
    widget set decides, and aligning one inside a strip only as tall as it
    is makes the two argue about it: the LCL gives up with
    "InvalidatePreferredSize loop detected" the moment the pane is shown. }
  function MakeCombo(AParent: TWinControl; ALeft, AWidth: Integer): TComboBox;
  begin
    Result := TComboBox.Create(Self);
    Result.Parent := AParent;
    Result.Align := alNone;
    Result.Anchors := [akLeft, akTop];
    Result.Style := csDropDownList;
    Result.SetBounds(LedScale96(ALeft), LedScale96(3), LedScale96(AWidth),
      LedScale96(24));
  end;

  function MakeButton(AParent: TWinControl; const ACaption: string;
    AOn: TNotifyEvent; AAlign: TAlign): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Align := AAlign;
    { Said out loud, for the reason given on the bubble's own buttons. }
    Result.AutoSize := False;
    Result.Width := TextRoom(Font, ACaption) + LedScale96(24);
    Result.BorderSpacing.Around := LedScale96(2);
    Result.Caption := ACaption;
    Result.OnClick := AOn;
  end;

begin
  { Before the inherited constructor, not after it: making a control lays
    it out, laying it out calls Resize, and Resize asks the list of turns
    how many there are.  An empty list answers that; one that does not
    exist yet takes the whole window down with it. }
  FTurns := TList.Create;
  inherited Create(AOwner);
  BevelOuter := bvNone;

  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.BevelOuter := bvNone;
  FTop.Height := LedScale96(30);

  FBackends := MakeCombo(FTop, 2, 90);
  FBackends.OnChange := @BackendPicked;
  FModels := MakeCombo(FTop, 96, 160);
  FStop := MakeButton(FTop, 'Stop', @StopClicked, alRight);
  FStop.Enabled := False;
  FClear := MakeButton(FTop, 'Clear', @ClearClicked, alRight);

  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
  { Controls aligned to the bottom are stacked by their Top, and three of
    them made in a row do not land in the order they were made in.  Said
    out loud: the send row lowest, the box you type in above it, the status
    line above that. }
  FBottom.Top := 30000;
  FBottom.Align := alBottom;
  FBottom.BevelOuter := bvNone;
  FBottom.Height := LedScale96(30);

  { What is being asked for.  A conversation by default; the rest are
    transforms, and a transform is the only kind of answer the pane will
    offer to put back into a file. }
  FTask := MakeCombo(FBottom, 2, 110);
  FTask.Items.Add(LedAITaskName(laskChat));
  FTask.Items.Add(LedAITaskName(laskProofread));
  FTask.Items.Add(LedAITaskName(laskRewrite));
  FTask.Items.Add(LedAITaskName(laskExplain));
  FTask.Items.Add(LedAITaskName(laskSummarise));
  FTask.Items.Add(LedAITaskName(laskComment));
  FTask.ItemIndex := 0;

  FAttach := MakeCombo(FBottom, 116, 150);
  FAttach.Items.Add('Nothing attached');
  FAttach.Items.Add('The selected text');
  FAttach.Items.Add('The whole file');
  FAttach.ItemIndex := 0;
  FAttach.OnChange := @AttachPicked;
  FSend := MakeButton(FBottom, 'Send', @SendClicked, alRight);

  FInput := TMemo.Create(Self);
  FInput.Parent := Self;
  FInput.Top := 20000;
  FInput.Align := alBottom;
  FInput.Height := LedScale96(60);
  FInput.ScrollBars := ssAutoVertical;
  FInput.WordWrap := True;
  FInput.OnKeyDown := @InputKey;

  { Above the box you type in, not at the top of the pane.  It says what is
    happening this second -- thinking, how long for, what the last answer
    cost -- and that belongs where the reader is looking when they are
    waiting for it, which is the question they just sent. }
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Top := 10000;
  FStatus.Align := alBottom;
  FStatus.AutoSize := False;
  FStatus.Height := LedScale96(16);
  FStatus.BorderSpacing.Around := LedScale96(2);
  FStatus.Font.Color := LedPageColours.Muted;
  FStatus.Caption := 'ready';

  FRoll := TScrollBox.Create(Self);
  FRoll.Parent := Self;
  FRoll.Align := alClient;
  FRoll.BorderStyle := bsNone;
  FRoll.HorzScrollBar.Visible := False;
  FRoll.Color := LedPageColours.Page;
  FRoll.ParentColor := False;

  FThinkTimer := TTimer.Create(Self);
  FThinkTimer.Interval := 500;
  FThinkTimer.Enabled := False;
  FThinkTimer.OnTimer := @Ticked;
end;

destructor TLedAIPane.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  FreeAndNil(FTurns);
  inherited Destroy;
end;

procedure TLedAIPane.Resize;
begin
  inherited Resize;
  if FTurns = nil then Exit;
  { A bubble is as tall as its page at the width it is drawn at, so a pane
    made narrower has to be asked again -- but not here.  Setting a child's
    height from inside a layout pass makes the pass run again, and the LCL
    throws out of the third or fourth round of that with
    "InvalidatePreferredSize loop detected".  Queued, the measuring happens
    once the layout has settled, which is also when the width it measures
    against is the width the reader will see. }
  if FRelayoutQueued then Exit;
  FRelayoutQueued := True;
  Application.QueueAsyncCall(@RelayoutSoon, 0);
end;

procedure TLedAIPane.RelayoutSoon(Data: PtrInt);
begin
  FRelayoutQueued := False;
  LayoutBars;
  Restack;
end;

{ The two strips of controls.

  Laid out here rather than by Align, and from the queued pass rather than
  from Resize: a combo box aligned inside a strip only as tall as it is
  argues with the widget set about its own height and the LCL gives up with
  "InvalidatePreferredSize loop detected".  Widths are shared out because
  this pane is usually narrow -- docked to an edge it is about 230 points
  across, and three controls at their natural widths do not fit. }
procedure TLedAIPane.LayoutBars;
var
  Gap, Room: Integer;
begin
  Gap := LedScale96(4);

  Room := FTop.ClientWidth - FStop.Width - FClear.Width - Gap * 4;
  if Room < LedScale96(120) then Room := LedScale96(120);
  FBackends.SetBounds(Gap, LedScale96(3), Room div 3, LedScale96(24));
  FModels.SetBounds(FBackends.Left + FBackends.Width + Gap, LedScale96(3),
    Room - FBackends.Width - Gap, LedScale96(24));

  Room := FBottom.ClientWidth - FSend.Width - Gap * 4;
  if Room < LedScale96(120) then Room := LedScale96(120);
  FTask.SetBounds(Gap, LedScale96(3), Room div 2, LedScale96(24));
  FAttach.SetBounds(FTask.Left + FTask.Width + Gap, LedScale96(3),
    Room - FTask.Width - Gap, LedScale96(24));
end;

{ Every turn, in order, down the inside of the scroll box.  The box takes
  its scrolling range from where the children end up, so this is also what
  tells it how far there is to scroll. }
procedure TLedAIPane.Restack;
var
  i, Y, W, Left_, Wide: Integer;
  B: TLedAIBubble;
begin
  if (FTurns = nil) or (FRoll = nil) then Exit;
  Y := LedScale96(4);
  W := FRoll.ClientWidth - LedScale96(12);
  if W < LedScale96(80) then W := LedScale96(80);
  for i := 0 to FTurns.Count - 1 do
  begin
    B := TLedAIBubble(FTurns[i]);
    { The reader's turns are set in from the left, which is the other half
      of saying who is speaking without a word for it.  Not so far in that
      a question has to wrap twice as often as the answer to it. }
    if B.Role = larUser then
    begin
      Left_ := LedScale96(24);
      Wide := W - Left_ + LedScale96(4);
    end
    else
    begin
      Left_ := LedScale96(2);
      Wide := W;
    end;
    B.SetBounds(Left_, Y, Wide, B.Height);
    B.Relayout;
    B.SetBounds(Left_, Y, Wide, B.Height);
    Inc(Y, B.Height + LedScale96(6));
  end;

  { Said out loud rather than left to the box to work out from where its
    children happen to end: children placed by hand do not always tell it,
    and a range of nothing is a wheel that does nothing. }
  if FRoll.HandleAllocated then FRoll.VertScrollBar.Range := Y;
end;

function TLedAIPane.AddTurn(ARole: TLedAIRole;
  const AText: string): TLedAIBubble;
begin
  Result := TLedAIBubble.CreateTurn(Self, FTurns.Count, ARole, AText);
  FTurns.Add(Result);
  DropOldest;
  Restack;
end;

procedure TLedAIPane.DropOldest;
var
  B: TLedAIBubble;
begin
  while FTurns.Count > MostTurns do
  begin
    B := TLedAIBubble(FTurns[0]);
    FTurns.Delete(0);
    B.Visible := False;
    { Released rather than freed: a control the LCL is still holding, freed
      here, is the "Destroy with LCLRefCount>0" the notebook pane ran into. }
    Application.ReleaseComponent(B);
  end;
end;

procedure TLedAIPane.ScrollToEnd;
begin
  { A scroll box that has never been shown has no handle to scroll, and
    asking it to anyway is "ScrollBy_WS: Handle not allocated" -- which a
    pane built off screen, as every pane here is, would meet on the first
    answer it was given. }
  if not FRoll.HandleAllocated then Exit;
  FRoll.VertScrollBar.Position := FRoll.VertScrollBar.Range;
end;

{ The wheel.

  Every windowed thing in the transcript -- the memo holding a turn, the
  renderer holding an answer -- takes the notch for itself and has nothing
  to do with it, being exactly as tall as its contents.  So they all hand it
  here, and so does the pane itself, and one notch moves the conversation
  the way the reader meant. }
function TLedAIPane.WheelNotch(AWheelDelta: Integer): Boolean;
var
  Notches, Was: Integer;
begin
  Result := False;
  if not FRoll.HandleAllocated then Exit;
  Notches := AWheelDelta div 120;
  if Notches = 0 then
    if AWheelDelta > 0 then Notches := 1 else Notches := -1;
  Was := FRoll.VertScrollBar.Position;
  FRoll.VertScrollBar.Position := Was - Notches * LedScale96(48);
  Result := FRoll.VertScrollBar.Position <> Was;
end;

function TLedAIPane.DoMouseWheel(AShift: TShiftState; AWheelDelta: Integer;
  AMousePos: TPoint): Boolean;
begin
  Result := WheelNotch(AWheelDelta);
  if not Result then
    Result := inherited DoMouseWheel(AShift, AWheelDelta, AMousePos);
end;

procedure TLedAIPane.Ask(const AText: string; ATask: TLedAITask);
begin
  if Trim(AText) = '' then Exit;
  if FThinking then Exit;
  AddTurn(larUser, AText);
  ScrollToEnd;
  if Assigned(FOnAsk) then FOnAsk(Self, AText, ATask, Attach);
end;

procedure TLedAIPane.SendClicked(Sender: TObject);
var
  Said: string;
begin
  Said := FInput.Text;
  if Trim(Said) = '' then Exit;
  FInput.Clear;
  Ask(Said, Task);
end;

procedure TLedAIPane.StopClicked(Sender: TObject);
begin
  if Assigned(FOnStop) then FOnStop(Self);
  FThinking := False;
  FThinkTimer.Enabled := False;
  FStop.Enabled := False;
  FStatus.Caption := 'stopped';
  if FLive <> nil then
  begin
    { What arrived is kept.  Half an answer is still something the reader
      asked for, and throwing it away on Stop would lose it. }
    FLive.Settle(False, False);
    FLive := nil;
  end;
end;

procedure TLedAIPane.ClearClicked(Sender: TObject);
begin
  Clear;
end;

procedure TLedAIPane.Clear;
var
  i: Integer;
  B: TLedAIBubble;
begin
  for i := 0 to FTurns.Count - 1 do
  begin
    B := TLedAIBubble(FTurns[i]);
    B.Visible := False;
    Application.ReleaseComponent(B);
  end;
  FTurns.Clear;
  FLive := nil;
  { A cleared pane is not waiting for anything.  Leaving this set left Stop
    lit over an empty transcript, and -- worse -- made the next question be
    refused as "still answering the last one". }
  FThinking := False;
  FThinkTimer.Enabled := False;
  FStop.Enabled := False;
  { A cleared pane is a fresh start, including what it will attach: a
    choice made for the last conversation should not quietly govern the
    next one.  Back to following the selection, which is where it began. }
  FAttachPinned := False;
  NoteSelection(FHasSelection);
  FStatus.Caption := 'ready';
  Restack;
end;

procedure TLedAIPane.InputKey(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  { Enter sends, Shift+Enter makes a new line.  Every chat box works this
    way, and both of LED's own prompts -- the debugger's and the watch box's
    -- send on Enter too. }
  if (Key = VK_RETURN) and (Shift * [ssShift, ssAlt] = []) then
  begin
    Key := 0;
    SendClicked(nil);
  end;
end;

function TLedAIPane.PressEnter(AShift: TShiftState): Boolean;
var
  Key: Word;
begin
  { The same door the keyboard uses, so a check goes through the pane's own
    handler rather than around it.  True when the pane took the key and
    sent the question; False when it left it alone, which is the whole of
    what Shift+Enter means here -- what the box then does with a Return is
    the widget's business and not LED's. }
  Key := VK_RETURN;
  InputKey(FInput, Key, AShift);
  Result := Key = 0;
end;

procedure TLedAIPane.TypePrompt(const AText: string);
begin
  FInput.Text := AText;
  FInput.SelStart := Length(AText);
end;

procedure TLedAIPane.Ticked(Sender: TObject);
var
  Secs: Integer;
begin
  if not FThinking then Exit;
  Secs := SecondsBetween(Now, FAskedAt);
  { Named, and counted.  The first question of a session waits for tens of
    gigabytes to be loaded, and a pane that says nothing for forty seconds
    is a pane that looks broken. }
  if FModelSaid <> '' then
    FStatus.Caption := Format('thinking... %ds  (%s)', [Secs, FModelSaid])
  else
    FStatus.Caption := Format('thinking... %ds', [Secs]);
end;

procedure TLedAIPane.BeginReply;
begin
  FThinking := True;
  FAskedAt := Now;
  FModelSaid := ModelName;
  FThinkTimer.Enabled := True;
  { Enabled from the moment the question is asked, not from the first word:
    the wait before the first word is exactly when a reader wants out. }
  FStop.Enabled := True;
  FStatus.Caption := 'thinking...';
  FLive := AddTurn(larAssistant, '');
  ScrollToEnd;
end;

procedure TLedAIPane.AddWords(const AText: string);
begin
  if FLive = nil then Exit;
  FLive.Grow(AText);
  ScrollToEnd;
end;

{ What the model is thinking, as it thinks it.  Kept against the turn and
  not shown: it is usually longer than the answer, and a pane that showed
  it by default would bury the thing that was asked for. }
{ Everything a backend says, sorted here rather than by the form.

  Which kind of delta goes where is this pane's business -- the answer into
  the answer, the working into the working, a tool into a note -- and
  putting that decision in the form put it where nothing could check it. }
procedure TLedAIPane.AddDelta(const ADelta: TLedAIDelta);
begin
  case ADelta.Kind of
    ladText: AddWords(ADelta.Text);
    ladThinking: AddThinking(ADelta.Text);
    ladTool:
      AddWords(LineEnding + '[' + ADelta.Name + ']' + LineEnding);
  end;
end;

procedure TLedAIPane.AddThinking(const AText: string);
begin
  if FLive = nil then Exit;
  FLive.Thought(AText);
  if FThinking then FStatus.Caption := 'thinking...';
end;

procedure TLedAIPane.EndReply(const AResult: TLedAIResult);
begin
  FThinking := False;
  FThinkTimer.Enabled := False;
  FStop.Enabled := False;
  if AResult.ContextWasCut then
    FStatus.Caption := 'answered, but it was only sent part of the file'
  else if AResult.Stats <> '' then
    FStatus.Caption := AResult.Stats
  else
    FStatus.Caption := 'ready';

  if FLive <> nil then
  begin
    FLive.Settle(AResult.Replaces, AResult.ContextWasCut, ApplyName);
    FLive := nil;
  end;
  ScrollToEnd;
end;

{ What putting this answer back would actually do, in words, so the button
  says the consequence rather than "apply". }
function TLedAIPane.ApplyName: string;
begin
  case Attach of
    laaDocument: Result := 'Replace the file';
    laaSelection: Result := 'Replace the selection';
  else
    Result := 'Apply';
  end;
end;

procedure TLedAIPane.Failed(const AWhy: string);
begin
  FThinking := False;
  FThinkTimer.Enabled := False;
  FStop.Enabled := False;
  FStatus.Caption := AWhy;
  if FLive <> nil then
  begin
    FLive.Settle(False, False);
    FLive := nil;
  end;
end;

procedure TLedAIPane.SetBackends(AList: TStrings; const AActive: string);
begin
  FBackends.Items.Assign(AList);
  FBackends.ItemIndex := FBackends.Items.IndexOf(AActive);
  if (FBackends.ItemIndex < 0) and (FBackends.Items.Count > 0) then
    FBackends.ItemIndex := 0;
end;

procedure TLedAIPane.SetModels(AList: TStrings; const AActive: string);
begin
  FModels.Items.Assign(AList);
  FModels.ItemIndex := FModels.Items.IndexOf(AActive);
  if (FModels.ItemIndex < 0) and (FModels.Items.Count > 0) then
    FModels.ItemIndex := 0;
end;

procedure TLedAIPane.SetAvailable(AOn: Boolean; const AWhy: string);
begin
  FSend.Enabled := AOn;
  FInput.Enabled := AOn;
  { Said either way.  Only clearing the line when something goes wrong
    leaves "switched off" on the screen after it has been switched back
    on -- which reads as a setting that did not take. }
  if AOn then FStatus.Caption := 'ready'
  else FStatus.Caption := AWhy;
end;

procedure TLedAIPane.NoteSelection(AHas: Boolean);
begin
  FHasSelection := AHas;
  { Follows the selection until the reader says otherwise, and then it is
    theirs.  What leaves the editor is worth being able to see and worth
    being able to decide. }
  if FAttachPinned then Exit;
  if AHas then FAttach.ItemIndex := Ord(laaSelection)
  else FAttach.ItemIndex := Ord(laaNothing);
end;

procedure TLedAIPane.AttachPicked(Sender: TObject);
begin
  FAttachPinned := True;
end;

procedure TLedAIPane.BackendPicked(Sender: TObject);
begin
  if Assigned(FOnBackendChanged) then FOnBackendChanged(Self);
end;

function TLedAIPane.TurnCount: Integer;
begin
  Result := FTurns.Count;
end;

function TLedAIPane.Turn(AIndex: Integer): TLedAIBubble;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex < FTurns.Count) then
    Result := TLedAIBubble(FTurns[AIndex]);
end;

function TLedAIPane.LastReply: string;
var
  i: Integer;
begin
  Result := '';
  for i := FTurns.Count - 1 downto 0 do
    if TLedAIBubble(FTurns[i]).Role = larAssistant then
      Exit(TLedAIBubble(FTurns[i]).Text);
end;

function TLedAIPane.BubbleCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FTurns.Count - 1 do
    if TLedAIBubble(FTurns[i]).Rendered then Inc(Result);
end;

function TLedAIPane.StreamText: string;
begin
  Result := '';
  if FLive <> nil then Result := FLive.Text;
end;

function TLedAIPane.Thinking: Boolean;
begin
  Result := FThinking;
end;

function TLedAIPane.StopEnabled: Boolean;
begin
  Result := FStop.Enabled;
end;

function TLedAIPane.StatusText: string;
begin
  Result := FStatus.Caption;
end;

function TLedAIPane.Task: TLedAITask;
begin
  Result := laskChat;
  case FTask.ItemIndex of
    1: Result := laskProofread;
    2: Result := laskRewrite;
    3: Result := laskExplain;
    4: Result := laskSummarise;
    5: Result := laskComment;
  end;
end;

procedure TLedAIPane.PickTask(ATask: TLedAITask);
var
  i: Integer;
begin
  for i := 0 to FTask.Items.Count - 1 do
    if FTask.Items[i] = LedAITaskName(ATask) then
    begin
      FTask.ItemIndex := i;
      Exit;
    end;
end;

{ What the button on a finished turn does, reached the same way a check
  reaches it: through the pane. }
procedure TLedAIPane.ApplyTurn(ATurn: Integer; AKind: TLedAIApply);
var
  B: TLedAIBubble;
begin
  B := Turn(ATurn);
  if B = nil then Exit;
  if Assigned(FOnApply) then
    FOnApply(Self, ATurn, LedAIUnfence(B.Text), AKind);
end;

function TLedAIPane.Attach: TLedAIAttach;
begin
  Result := TLedAIAttach(Max(0, FAttach.ItemIndex));
end;

procedure TLedAIPane.PickAttach(AKind: TLedAIAttach);
begin
  FAttach.ItemIndex := Ord(AKind);
  AttachPicked(nil);
end;

function TLedAIPane.StatusControl: TControl;
begin
  Result := FStatus;
end;

function TLedAIPane.SendBar: TControl;
begin
  Result := FBottom;
end;

function TLedAIPane.Transcript: TControl;
begin
  Result := FRoll;
end;

function TLedAIPane.ScrollPos: Integer;
begin
  Result := FRoll.VertScrollBar.Position;
end;

procedure TLedAIPane.ScrollTo(APos: Integer);
begin
  if FRoll.HandleAllocated then FRoll.VertScrollBar.Position := APos;
end;

function TLedAIPane.ScrollRange: Integer;
begin
  Result := FRoll.VertScrollBar.Range;
end;

function TLedAIPane.InputControl: TWinControl;
begin
  Result := FInput;
end;

function TLedAIPane.BackendName: string;
begin
  Result := '';
  if FBackends.ItemIndex >= 0 then
    Result := FBackends.Items[FBackends.ItemIndex];
end;

function TLedAIPane.ModelName: string;
begin
  Result := '';
  if FModels.ItemIndex >= 0 then
    Result := FModels.Items[FModels.ItemIndex];
end;

end.
