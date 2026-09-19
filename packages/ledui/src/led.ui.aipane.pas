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
  Led.Core.AI, Led.Core.Markdown, Led.Core.Prefs,
  Led.Syn.Factory,
  Led.UI.PageStyle, Led.UI.NBPane, Led.UI.DPI, Led.UI.Focus;

type
  { What the pane is about to send with the question. }
  TLedAIAttach = (laaNothing, laaSelection, laaDocument);

  { What the reader wants done with a reply. }
  TLedAIApply = (lapInsert, lapReplaceSelection, lapReplaceDocument);

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
    FHead: TLabel;
    FLive: TMemo;               // what was said, as plain text
    FRender: TLedNBProse;       // an assistant's turn, once it has settled
    FProvider: TIpFileDataProvider;
    FBar: TPanel;
    FReplaces: Boolean;
    FCut: Boolean;
    FLayingOut: Boolean;
    FPage: string;        // the HTML handed to the renderer
    FPageWidth: Integer;  // ...and the width it was measured at
    procedure MakeHead;
    procedure MakeLive;
    procedure ChildWheel(Sender: TObject; AShift: TShiftState;
      AWheelDelta: Integer; AMousePos: TPoint; var AHandled: Boolean);
    procedure HookRenderChildren;
    function Fill: TColor;
    function InnerWidth: Integer;
    procedure MakeRender;
    procedure ProvideImage(Sender: TIpHtmlNode; const AURL: string;
      var APicture: TPicture);
    procedure MakeButtons;
    procedure CopyClicked(Sender: TObject);
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
    procedure Settle(AReplaces, ACut: Boolean);
    procedure Relayout;
    property Text: string read FText;
    property Role: TLedAIRole read FRole;
    { For the self-test: whether this turn has been laid out as a page, and
      what page it was given. }
    function Rendered: Boolean;
    { Whether this turn offers to go back into the file. }
    function OffersApply: Boolean;
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
    procedure PickAttach(AKind: TLedAIAttach);
    function Task: TLedAITask;
    procedure PickTask(ATask: TLedAITask);
    procedure ApplyTurn(ATurn: Integer; AKind: TLedAIApply);
    function InputControl: TWinControl;
    { Where the conversation is scrolled to, and how far there is to go. }
    function ScrollPos: Integer;
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
  MakeHead;
  { Both sides get one.  The reader's own words were kept and never shown,
    which made their half of the conversation a row of empty headings. }
  MakeLive;
  if AText <> '' then FLive.Text := AText;
  Relayout;
end;

{ The colour this turn is drawn on.  The reader's own words are picked out:
  a transcript where both halves are the same colour is a wall of text that
  has to be read to be navigated. }
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
    Result := C.CodeBg;
end;

{ Rounded, and drawn here rather than left to the panel, because a panel is
  a rectangle and a conversation drawn in rectangles reads as a table. }
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

  Round_ := LedScale96(10);
  Canvas.Brush.Color := Fill;
  Canvas.Pen.Color := LedMixColours(Fill, LedPageColours.Text, 88);
  Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round_, Round_);
end;

procedure TLedAIBubble.MakeHead;
begin
  FHead := TLabel.Create(Self);
  FHead.Parent := Self;
  FHead.Align := alNone;
  FHead.AutoSize := False;
  FHead.Height := LedScale96(16);
  FHead.Transparent := True;
  FHead.Font.Style := [fsBold];
  FHead.Font.Color := LedPageColours.Muted;
  if FRole = larUser then FHead.Caption := 'You'
  else FHead.Caption := 'Assistant';
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
  FRender.DefaultFontSize := 10;
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
    Result.Align := alLeft;
    { A width worked out here rather than AutoSize.  A button that sizes
      itself, on a strip whose height feeds the bubble's height, is a loop
      the LCL notices and throws out of: "InvalidatePreferredSize loop
      detected". }
    Result.AutoSize := False;
    Result.Width := TextRoom(Font, ACaption) + LedScale96(20);
    Result.BorderSpacing.Right := LedScale96(4);
    Result.Caption := ACaption;
    Result.OnClick := AOn;
  end;

begin
  if FBar <> nil then Exit;
  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alNone;
  FBar.BevelOuter := bvNone;
  FBar.Color := Fill;
  FBar.ParentColor := False;
  { A height of its own rather than AutoSize.  A strip that sizes itself to
    its buttons, inside a bubble whose own height is worked out from the
    strip, is a loop -- and the LCL says so: "InvalidatePreferredSize loop
    detected". }
  FBar.Height := LedScale96(26);

  Add('Copy', @CopyClicked);
  Add('Insert at caret', @InsertClicked);

  { The one that changes a file says which file, and says nothing at all
    when it cannot be offered honestly: a whole-document replacement built
    from part of a document is silent truncation. }
  if FReplaces and not FCut then
    Add('Apply', @ApplyClicked);
end;

procedure TLedAIBubble.CopyClicked(Sender: TObject);
begin
  Clipboard.AsText := FText;
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

function TLedAIBubble.Page(AWidth: Integer): string;
var
  C: TLedPageColours;
  Html: string;
begin
  C := LedPageColours;
  Html := LedMarkdownToHTML(FText);
  { IPro cannot draw a <pre> at all, so the fenced blocks are rewritten into
    coloured <code> -- the same path the notebook's cells take. }
  Html := LedPageColourCode(Html, C.Text, C.CodeBg);
  Result := LedPageHead('', C) + Html + LedPageTail;
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
      Doc.DefaultFontSize := 10;
      Doc.FixedTypeface := FixedFace;
      Doc.OnGetImageX := @ProvideImage;
      Doc.LoadFromStream(Stream);
      H := Doc.PageHeightAt(Surface.Canvas, AWidth - LedScale96(16));
      if H > 0 then Result := H + LedScale96(28);
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

procedure TLedAIBubble.Settle(AReplaces, ACut: Boolean);
begin
  FReplaces := AReplaces;
  FCut := ACut;
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
function TLedAIBubble.InnerWidth: Integer;
begin
  Result := Width - LedScale96(8) * 2;
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
    { Room for the rounded edge to show.  Children placed by hand rather
      than aligned, so that the corners are not painted over. }
    Pad := LedScale96(8);
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
    FHead.SetBounds(Pad, Y, Inner, LedScale96(16));
    Inc(Y, FHead.Height + LedScale96(2));

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
      FBar.SetBounds(Pad, Y, Inner, FBar.Height);
      Inc(Y, FBar.Height);
    end;

    Height := Y + Pad;
  finally
    FLayingOut := False;
  end;
end;

function TLedAIBubble.Rendered: Boolean;
begin
  Result := FRender <> nil;
end;

function TLedAIBubble.OffersApply: Boolean;
var
  i: Integer;
begin
  Result := False;
  if FBar = nil then Exit;
  for i := 0 to FBar.ControlCount - 1 do
    if (FBar.Controls[i] is TButton) and
       (TButton(FBar.Controls[i]).Caption = 'Apply') then
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

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alTop;
  FStatus.AutoSize := False;
  FStatus.Height := LedScale96(16);
  FStatus.BorderSpacing.Around := LedScale96(2);
  FStatus.Font.Color := LedPageColours.Muted;
  FStatus.Caption := 'ready';

  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
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
  FInput.Align := alBottom;
  FInput.Height := LedScale96(60);
  FInput.ScrollBars := ssAutoVertical;
  FInput.WordWrap := True;
  FInput.OnKeyDown := @InputKey;

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
  i, Y, W: Integer;
  B: TLedAIBubble;
begin
  if (FTurns = nil) or (FRoll = nil) then Exit;
  Y := LedScale96(4);
  W := FRoll.ClientWidth - LedScale96(12);
  if W < LedScale96(80) then W := LedScale96(80);
  for i := 0 to FTurns.Count - 1 do
  begin
    B := TLedAIBubble(FTurns[i]);
    B.SetBounds(LedScale96(4), Y, W, B.Height);
    B.Relayout;
    B.SetBounds(LedScale96(4), Y, W, B.Height);
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
    FLive.Settle(AResult.Replaces, AResult.ContextWasCut);
    FLive := nil;
  end;
  ScrollToEnd;
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

function TLedAIPane.ScrollPos: Integer;
begin
  Result := FRoll.VertScrollBar.Position;
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
