{ LED - a lightweight editor.  A notebook as a page of cells you can type in.

  The line view is the editor: one buffer, so find and replace, undo,
  bookmarks, column select and the minimap all work on a notebook the way
  they work on anything else.  This is the other view of the same file, the
  one that looks like a notebook -- prose rendered, code in its own box, and
  the pictures actually shown, which is the one thing a line of text cannot
  do.

  Both views edit the same notebook.  A cell typed into here is written
  through to the document, which puts the same text into the line buffer in
  the same breath, so the two never disagree.

  A widget per cell, with a real editor in each, rather than one clever
  control.  That was a measured choice, not a habit: 106 cells -- the size of
  the reader's largest teaching notebook -- came to 424 controls, 59 ms to
  build and show, 16 MB, and 2 ms to scroll. About 150 kB a cell, so a
  notebook of a thousand cells would want the boxes built only for what is on
  screen; at the sizes people actually write, building them all is simpler
  and fast enough.  The alternative measured beside it, one HTML container
  with a <textarea> per cell, laid out just as quickly but has no syntax
  colouring in the boxes, which is most of what an editor is for. }

unit Led.UI.NBPane;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Controls, ExtCtrls, StdCtrls, Buttons,
  Graphics, Forms, ImgList, LazUTF8, LCLType,
  IpHtml, Ipfilebroker,
  SynEditHighlighter,
  Led.Core.NBFormat, Led.Core.NBView, Led.Core.NBImage, Led.Core.NBFetch,
  Led.Core.NBConvert, Led.Core.NBMagic, Led.Core.Markdown,
  Led.Syn.Factory, Led.Syn.Notebook, Led.Syn.Theme, Led.UI.Icons,
  Led.UI.PageStyle, Led.UI.Pictures,
  Led.UI.Document, Led.UI.Edit, Led.UI.Dpi;

type
  TLedNBCellEvent = procedure(Sender: TObject; ACell: Integer) of object;
  { A cell to be added after ACell -- so -1 means "before the first" -- of
    the kind the reader asked for. }
  TLedNBInsertEvent = procedure(Sender: TObject; ACell: Integer;
    AKind: TLedNBCellKind) of object;

  { A cell's code editor.

    SynEdit handles the wheel through its own mouse actions, before any
    OnMouseWheel the owner assigned, so scrolling over a code cell moved the
    cell's own view -- which has nowhere to go, the box being exactly as tall
    as its text -- and never the page.  Overriding the entry point is the one
    place that beats it. }
  TLedNBCellEdit = class(TLedEdit)
  private
    FOnWheel: TMouseWheelEvent;
  protected
    function DoMouseWheel(AShift: TShiftState; AWheelDelta: Integer;
      AMousePos: TPoint): Boolean; override;
  public
    property OnWheelPassedUp: TMouseWheelEvent read FOnWheel write FOnWheel;
  end;

  { The rendered prose of one cell.

    A descendant rather than the panel itself, for two things the panel does
    not do on its own.  It keeps the mouse wheel: the panel is exactly as
    tall as its page and so has nothing to scroll, but it still swallows the
    event, and the page behind it is what the reader was trying to move.  And
    it is opened for editing by a double click, which is the gesture every
    notebook front end uses for prose -- a single click has to stay a single
    click so that text can be selected and a link can be followed. }
  TLedNBProse = class(TIpHtmlPanel)
  private
    FOnWheel: TMouseWheelEvent;
    FOnEnterEdit: TNotifyEvent;
  protected
    function DoMouseWheel(AShift: TShiftState; AWheelDelta: Integer;
      AMousePos: TPoint): Boolean; override;
    procedure DblClick; override;
  public
    property OnWheelPassedUp: TMouseWheelEvent read FOnWheel write FOnWheel;
    property OnEnterEdit: TNotifyEvent read FOnEnterEdit write FOnEnterEdit;
  end;

  { Both of these events are declared where a descendant may publish them and
    a caller may not assign them, so they are reached the way the LCL expects:
    through a descendant that says they are public.  The control itself is
    untouched.  Public here because the renderer's own inner control is what
    they are put on, and a check has to be able to fire them. }
  TControlEvents = class(TControl)
  public
    property OnMouseWheel;
    property OnDblClick;
    property OnMouseDown;
  end;

  { One of the buttons at a cell boundary.

    Drawn rather than left to the widgetset: a flat TSpeedButton on a panel
    is three words with no edge to them, which reads as part of the page
    rather than as something to press -- and the page it floats over is a
    cell, so it needs to stand away from it.  So: a rounded slab, a border,
    the theme's own text colour, and a lighter fill while the pointer is on
    it.  All of it mixed from the theme's page and text colours, which is
    what makes it work on a scheme nobody has seen. }
  TLedNBBarButton = class(TSpeedButton)
  protected
    procedure Paint; override;
  end;

  { The three buttons that appear at the boundary between two cells: add a
    code cell, add a prose cell, delete the cell above.

    One bar, moved to whichever boundary the pointer is near, rather than a
    set per cell: a notebook has hundreds of boundaries and the reader is
    never at two of them.  It is a notebook front end's own gesture -- Colab
    puts the same two buttons in the same place -- and it is the only way to
    add a cell at all from the pane.

    Which boundary the pointer is near is polled rather than watched.  A cell
    is a panel with an editor, a rendered page, labels and pictures in it,
    and every one of those takes the mouse for itself: LED has already had
    the wheel and the double click go missing inside the renderer's own
    drawing control, and hooking mouse-move onto every child of every cell
    would be the same bet made a third time.  A timer that asks where the
    pointer is costs nothing measurable and cannot be intercepted. }
  TLedNBAddBar = class(TPanel)
  private
    FCode: TSpeedButton;
    FText: TSpeedButton;
    FDrop: TSpeedButton;
    FCell: Integer;
  public
    constructor Create(AOwner: TComponent); reintroduce;
    { Which cell the bar is under: a new cell goes after it, and Delete
      Above takes it out. }
    property Cell: Integer read FCell write FCell;
    property AddCode: TSpeedButton read FCode;
    property AddText: TSpeedButton read FText;
    property DeleteAbove: TSpeedButton read FDrop;
  end;

  { The pictures the cells have decoded, and where a cell's pictures come
    from: both in Led.UI.Pictures now, because the Markdown preview asks the
    renderer's questions in exactly the same words. }
  TLedNBPictures = TLedPictureCache;

  { The colours the pane draws with.  The same record the Markdown and wiki
    preview uses: see Led.UI.PageStyle. }
  TLedNBColourSet = TLedPageColours;

  { One cell: its label, its Run button, its source, and whatever it
    produced. }
  TLedNBCellBox = class(TPanel)
  private
    FDoc: TLedDocument;
    FCell: Integer;
    FHead: TLabel;
    FRun: TSpeedButton;
    { Prose is shown rendered, so it needs a way to be got at.  A button
      rather than only a click on the text: the renderer may keep a click
      for itself -- it has links to think about -- and a way in that depends
      on that is a way in that sometimes is not there. }
    FEditBtn: TSpeedButton;
    FEdit: TLedNBCellEdit;
    FRender: TLedNBProse;
    FProvider: TIpFileDataProvider;
    FOnRun: TLedNBCellEvent;
    FOnEdited: TLedNBCellEvent;
    FEditing: Boolean;         // a markdown cell being typed into
    { The editor's own notebook highlighter, and what it is told about the
      cell: the language to colour it in, and whether a line beginning % or !
      is one of IPython's magics -- which it is not in a cell that %%bash has
      handed to another language. }
    FHigh: TLedNBHighlighter;
    FEditLang: string;
    FEditIPython: Boolean;
    { The width the page was built for, which is the width a picture too wide
      for the cell is drawn at.  Part of what a cached picture is keyed on:
      the same picture in a pane that has been made wider is a different
      bitmap. }
    FFitWidth: Integer;
    FPicSrc: TLedPictureSource;
    function EditLineKind(ALine: Integer; out ACell: Integer;
      out ALang: string): TLedNBLine;
    function EditLineText(ALine: Integer): string;
    procedure RunClicked(Sender: TObject);
    procedure RenderClicked(Sender: TObject);
    procedure EditClicked(Sender: TObject);
    procedure EditExited(Sender: TObject);
    procedure MakeEditor;
    procedure MakeRender;
    procedure ProvideImage(Sender: TIpHtmlNode; const URL: string;
      var Picture: TPicture);
    { The renderer draws into a control of its own inside the panel, and that
      control is what the mouse reaches: a wheel notch and a double click
      over rendered prose never touched the panel at all, which is why
      neither did anything.  Its children are given the same two handlers. }
    procedure HookRenderChildren;
    procedure ChildDblClick(Sender: TObject);
    { A click on anything in the cell that is not the editor: the head, the
      padding round it, the rendered prose of the cell next door.  A cell
      being typed into is left then, the way clicking off a cell leaves it in
      a notebook front end.  The editor's own OnExit does this when the focus
      moves, and a click on a label or on the renderer's drawing control
      moves no focus at all, which is why this is needed. }
    procedure ChildMouseDown(Sender: TObject; AButton: TMouseButton;
      AShift: TShiftState; X, Y: Integer);
    { Whether a picture on the web is here to be drawn, asking for it if it
      is not.  The page is laid out with what has arrived; when the rest
      arrives the cell is drawn again. }
    function HaveRemote(const AURL: string; out AWhy: string): Boolean;
    { The wheel, from a child that would otherwise swallow it, handed to the
      page the reader was trying to scroll. }
    procedure ChildWheel(Sender: TObject; AShift: TShiftState;
      AWheelDelta: Integer; AMousePos: TPoint; var AHandled: Boolean);
    procedure BuildOutputs(var AY: Integer; AWidth: Integer);
    function RenderedHeight(const APage: string; AWidth: Integer): Integer;
    function ImageSize(const AURL: string; out AW, AH: Integer): Boolean;
    function Pictures: TLedPictureSource;
    function EmbeddedPicture(const AURL: string;
      out ABytes, AMime: string): Boolean;

  public
    { The page this cell's prose renders to, at a given width.  Public for
      the sake of a check: what a picture too wide for the cell is given
      cannot be seen from outside the rendered page otherwise. }
    function ProsePage(const ASource: string; AWidth: Integer): string;
    constructor Create(AOwner: TComponent; ADoc: TLedDocument;
      ACell: Integer; AImages: TCustomImageList); reintroduce;
    destructor Destroy; override;
    { Lays the cell out for AWidth and answers how tall it came to.

      The width is given rather than read back from the box: laying the pane
      out happens with autosizing held off, so a box that has just been told
      its new width still reports the old one, and a picture scaled to that
      came out a tenth of the size it should have been. }
    function Rebuild(AWidth: Integer): Integer;
    { How tall this cell's editor has to be for the text in it. }
    function EditorHeight: Integer;
    { Takes what is in the editor and gives it to the document, which puts it
      in the line buffer too.

      On leaving the cell and before running it, not on every keystroke:
      writing a cell back rewrites those lines of the line buffer, and doing
      that per character would throw away that view's undo history a letter
      at a time. }
    procedure Commit;
    property Cell: Integer read FCell;
    property Editor: TLedNBCellEdit read FEdit;
    property Rendered: TLedNBProse read FRender;
    property RunButton: TSpeedButton read FRun;
    { The button that turns rendered prose into text and back.  nil on a code
      cell, which is text already. }
    property EditButton: TSpeedButton read FEditBtn;
    { Whether this cell is showing its source rather than its rendering. }
    property Editing: Boolean read FEditing;
    procedure SetEditing(AValue: Boolean);
    property OnRunCell: TLedNBCellEvent read FOnRun write FOnRun;
    property OnEdited: TLedNBCellEvent read FOnEdited write FOnEdited;
  end;

{ The colours the pane and its cells draw with, from the current theme. }
function LedNBColours: TLedNBColourSet;

{ Colours the code in a rendered markdown page, and puts it in a face the
  reader can read.

  Two things were wrong with a code block in a prose cell and both are here.
  It came out in whatever the renderer's idea of a fixed font is, in black --
  on a dark theme, black on near-black.  And a fence that named its language
  was not coloured at all, though the notebook says what it is and LED has
  the highlighter for it.

  So every <pre> and <code> is given the monospaced face and the page's text
  colour outright, and the contents of a fence that named a language LED can
  colour are run through that language's highlighter and written out a token
  at a time.  As <font> tags rather than a style sheet, because that is what
  this renderer reads. }
function LedNBColourCode(const AHtml, AFixedFace: string;
  ATextColour, ABackColour: TColor): string;

type
  { The page of cells.

    Only the cells on screen are built.  That is not an optimisation, it is
    what makes the pane work at all: a control's position in the LCL is a
    signed 16-bit number, and stacking a hundred cells of full-height prose
    runs past 32767 pixels -- at which point the coordinates wrap and the
    editor comes down.  The report that found it was a notebook laying a cell
    out at Top = 33133.

    So the pane does its own scrolling.  The scrollbar counts the notebook's
    whole height, which is a 32-bit number and may be as large as it likes;
    the boxes are positioned against the top of the viewport, where nothing
    is ever more than a screen from zero.  A cell's height is remembered once
    it has been built and estimated until then, so the bar is roughly right
    immediately and exactly right for everything the reader has seen. }
  TLedNotebookPane = class(TPanel)
  private
    FDoc: TLedDocument;
    FBoxes: TFPList;           // of TLedNBCellBox: the cells on screen
    FPics: TLedNBPictures;     // the pictures they have already decoded
    FAddBar: TLedNBAddBar;     // the buttons at whichever boundary is near
    FHoverTimer: TTimer;       // asks where the pointer is; see TLedNBAddBar
    FOnInsert: TLedNBInsertEvent;
    FOnDelete: TLedNBCellEvent;
    FFirst: Integer;           // the first cell built, or -1
    FHeights: array of Integer;   // per cell; -1 until it has been built
    FBar: TScrollBar;
    FNote: TLabel;
    FImages: TCustomImageList;
    FOnRun: TLedNBCellEvent;
    FOnScrolled: TLedNBCellEvent;
    FOnPicked: TLedNBCellEvent;
    { The top cell as it was last reported, so that a scroll within one cell
      is not reported over and over -- and a flag for a scroll this pane was
      told to make, which must not be reported at all: that would be an echo
      of whoever told it. }
    FToldCell: Integer;
    FFollowing: Boolean;
    FBuilding: Boolean;        // BuildWindow is not re-entrant
    { Resizing is coalesced.  Dragging the splitter fires a resize per pixel,
      and every one of them would re-wrap every cell and re-measure every
      piece of prose; the pane waits until the dragging stops.  The preview
      pane does the same, for the same reason. }
    FResizeTimer: TTimer;
    FImageTimer: TTimer;
    FLaidOutFor: Integer;      // the width the boxes were laid out for
    procedure CellRun(Sender: TObject; ACell: Integer);
    procedure CellEdited(Sender: TObject; ACell: Integer);
    procedure ResizeSettled(Sender: TObject);
    procedure BarScrolled(Sender: TObject);
    procedure ReportTop;
    procedure CellPicked(ACell: Integer);
    procedure HoverTick(Sender: TObject);
    procedure PlaceAddBar(ABox: TLedNBCellBox);
    procedure AddCodeClicked(Sender: TObject);
    procedure AddTextClicked(Sender: TObject);
    procedure DeleteAboveClicked(Sender: TObject);
    procedure ImageTick(Sender: TObject);
    procedure LeaveEditDeferred(AData: PtrInt);
    procedure PaneMouseDown(Sender: TObject; AButton: TMouseButton;
      AShift: TShiftState; X, Y: Integer);
    { The height a cell takes, measured if it has ever been built and
      estimated from its neighbours if not. }
    function HeightOf(ACell: Integer): Integer;
    function Estimate: Integer;
    { Where a cell starts, and how tall the whole notebook is, in the
      scrollbar's own coordinates. }
    function VirtualTop(ACell: Integer): Integer;
    function VirtualHeight: Integer;
    procedure SyncBar;
    { Builds the cells the viewport covers and releases the rest. }
    procedure BuildWindow;
    procedure ReleaseBoxes;
    procedure LayoutBelow(ACell: Integer);
    { Whether the document these cells are of is still open, forgetting it
      when it is not.  Every path that touches the notebook asks first: the
      pane outlives the tab it was showing, and a resize arriving after a
      close would otherwise read a freed document.  The docking checks, which
      show and hide every pane, found exactly that. }
    function LiveDoc: Boolean;
    function GetScrollPos: Integer;
    procedure SetScrollPos(AValue: Integer);
  protected
    procedure Resize; override;
    function DoMouseWheel(AShift: TShiftState; AWheelDelta: Integer;
      AMousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Lays the cells out again for the pane's current width: the wrapped
      height of a cell and the size a wide picture is scaled to both depend
      on it, so every remembered height is forgotten and taken again. }
    procedure Relayout;

    { Shows a document's cells, or a note saying why there are none.  Called
      when the pane is shown and when the tab changes. }
    procedure ShowDocument(ADoc: TLedDocument);
    { Builds the cells again from the notebook -- after a run, or after the
      line view has been typed into. }
    procedure Reload;
    { One cell again, which is what a run needs: its label, its output and
      its height.  Does nothing for a cell that is not on screen: there is no
      box to redraw, and its height is taken again when it is next built. }
    procedure RefreshCell(ACell: Integer);

    { The pictures the cells have already decoded.  Public so that a cell can
      reach it -- the cache belongs to the pane, not to a box, or scrolling
      a cell out of view would throw away exactly what scrolling it back
      needs -- and so that a check can count what is in it. }
    property Pictures: TLedNBPictures read FPics;

    { Puts away whatever cell is being typed into, if any.

      Deferred, because this is called from a mouse event on a control the
      rebuild may well destroy -- the cell's own head label, the drawing
      control inside the renderer -- and freeing a control while it is
      handling its own event is how the pane came to print "Destroy with
      LCLRefCount>0" and stop. }
    procedure LeaveEditing;

    { Puts a cell at the top of the viewport, building it if it was not on
      screen. }
    procedure ScrollToCell(ACell: Integer);
    { Starts looking for pictures that have been asked for. }
    procedure WatchForImages;

    { How many cells the notebook has, and how many of them are built.  The
      second is a property of the window on screen and not of the file. }
    function CellCount: Integer;
    function BuiltCount: Integer;
    { The AIndex-th box on screen, or nil. }
    function Box(AIndex: Integer): TLedNBCellBox;
    { The box showing a given cell, or nil when that cell is not on screen. }
    function BoxOf(ACell: Integer): TLedNBCellBox;

    { Where the page is scrolled to, in pixels down the whole notebook. }
    property ScrollPos: Integer read GetScrollPos write SetScrollPos;

    property Document: TLedDocument read FDoc;
    { Where the cells take their button icons from.  The window's own list,
      so a notebook's Run button is the same glyph as the toolbar's. }
    property Images: TCustomImageList read FImages write FImages;
    { Fired when a cell's Run button is pressed; the window runs it, because
      the kernel is the document's and the reporting is the window's. }
    property OnRunCell: TLedNBCellEvent read FOnRun write FOnRun;

    { Which cell is at the top of the viewport, or -1 when there is no
      notebook.  What the text view follows when the two are kept in step. }
    function TopCell: Integer;
    { Says where the pane is, as a scroll by the reader would.  For a check,
      which moves the pane by calling ScrollToCell rather than by turning a
      wheel. }
    procedure ReportTopNow;
    { Puts ACell at the top without saying so: this is the pane following
      something else, and reporting it would be an echo. }
    procedure FollowToCell(ACell: Integer);

    { Fired when the cell at the top of the viewport changes because the
      reader scrolled the pane. }
    property OnScrolled: TLedNBCellEvent read FOnScrolled write FOnScrolled;
    { Fired when the reader puts the mouse in a cell, so that the window can
      move the caret there: the two views then look at the same cell, and Run
      Cell runs the one under the pointer. }
    property OnCellPicked: TLedNBCellEvent read FOnPicked write FOnPicked;

    { The buttons at a cell boundary.  Public so a check can press them:
      they appear on a hover, and a scripted run has no pointer. }
    property AddBar: TLedNBAddBar read FAddBar;
    { Shows the bar under ACell, as hovering near that boundary does. }
    procedure ShowAddBarUnder(ACell: Integer);
    { Builds the cells again and leaves the reader where they were, with
      ATopCell back at the top.  For a change in the notebook's shape -- a
      cell added or taken out -- which needs everything rebuilt and is not a
      request to go anywhere. }
    procedure ReloadKeeping(ATopCell: Integer);
    { Fired when one of them is pressed.  The window does the work: it owns
      the asking-before-deleting and the reporting, the same division the
      Run button has. }
    property OnInsertCell: TLedNBInsertEvent read FOnInsert write FOnInsert;
    property OnDeleteCell: TLedNBCellEvent read FOnDelete write FOnDelete;
  end;

implementation

const
  Pad = 6;
  LabelWidth = 76;
  { The space between one cell and the next.  Wide enough for the buttons
    that appear there on a hover: at four pixels -- which is all a reader
    needs to see where one cell ends -- the bar had to be drawn over the
    last line of one cell or the first line of the next, and both of those
    are lines somebody clicks.  A notebook front end leaves the same room
    for the same reason. }
  CellGap = 24;
  { The prose face.  Proportional, and at a size taken from the reader's own
    editor font rather than fixed -- see ProseSize. }
  ProseFace = 'Sans';
  { Prose runs nearly the full width, the way it does in a notebook front
    end: a paragraph is read across the page, and the column a code cell
    needs for its execution count is room a paragraph should not give up.
    The gutter that is left is for the button that turns it into text. }
  ProseGutter = 30;

{ The colours a notebook page needs, all of them derived from the theme so
  that the pane belongs to the window it is in rather than being a white
  sheet beside a dark editor.

  Only two are read: the page and the text.  The rest are mixed from those,
  which is what makes this work for a scheme nobody has seen -- a code block
  a few per cent away from the page is a code block on a light theme and on
  a dark one, where a fixed grey is right on one and wrong on the other. }
{ How big the prose is: the size the reader set for their editor, and three
  points more.

  Fixed at ten points it was smaller than the code beside it on some
  machines and smaller than the editor on all of them, which is the wrong way
  round -- prose is read and code is scanned, and a notebook front end sets
  prose larger.  Derived, it follows the font preference: a reader who makes
  the editor bigger gets a bigger page. }
function ProseSize(ADoc: TLedDocument): Integer;
begin
  Result := 10;
  if (ADoc <> nil) and (ADoc.Master.Font.Size > 0) then
    Result := ADoc.Master.Font.Size;
  Result := Result + 3;
end;

{ APoints bigger, whether the font says its size in points or in pixels.

  Font.Size is only meaningful when it is positive.  A desktop with no font
  preference leaves LED's own size at zero, the LCL answers with the system
  font, and from then on the font is described by Font.Height -- Size reads
  back as a negative number, and adding two to that is not two points bigger,
  it is nonsense.  So the bump was skipped there and the code in a cell came
  out at exactly the editor's size, which is the thing it is here to prevent.
  That is what the CI runner has, and what a fresh install has until somebody
  chooses a font.

  Height is in pixels and its sign says which way is bigger: negative is the
  em size, positive is the whole cell.  A font that gives neither is left
  alone -- there is nothing there to add to. }
procedure BumpFont(AFont: TFont; APoints: Integer);
var
  Px: Integer;
begin
  if AFont.Size > 0 then
  begin
    AFont.Size := AFont.Size + APoints;
    Exit;
  end;
  Px := MulDiv(APoints, AFont.PixelsPerInch, 72);
  if Px < 1 then Px := 1;
  if AFont.Height < 0 then
    AFont.Height := AFont.Height - Px
  else if AFont.Height > 0 then
    AFont.Height := AFont.Height + Px;
end;

function LedNBColours: TLedNBColourSet;
begin
  Result := LedPageColours;
end;

{ A colour as HTML says it. }
function HtmlColour(AColour: TColor): string;
begin
  Result := LedHtmlColour(AColour);
end;

function TLedNBCellEdit.DoMouseWheel(AShift: TShiftState;
  AWheelDelta: Integer; AMousePos: TPoint): Boolean;
var
  Handled: Boolean;
begin
  Handled := False;
  if Assigned(FOnWheel) then
    FOnWheel(Self, AShift, AWheelDelta, AMousePos, Handled);
  if Handled then Exit(True);
  Result := inherited DoMouseWheel(AShift, AWheelDelta, AMousePos);
end;

function TLedNBProse.DoMouseWheel(AShift: TShiftState; AWheelDelta: Integer;
  AMousePos: TPoint): Boolean;
var
  Handled: Boolean;
begin
  Handled := False;
  if Assigned(FOnWheel) then FOnWheel(Self, AShift, AWheelDelta, AMousePos, Handled);
  if Handled then Exit(True);
  Result := inherited DoMouseWheel(AShift, AWheelDelta, AMousePos);
end;

procedure TLedNBProse.DblClick;
begin
  if Assigned(FOnEnterEdit) then FOnEnterEdit(Self);
  inherited DblClick;
end;

{ ---- code inside prose ---- }

{ The colouring itself lives in Led.UI.PageStyle, which the Markdown and wiki
  preview uses too: both panes render HTML, both had the same faults, and one
  fix is better than two. }

function LedNBColourCode(const AHtml, AFixedFace: string;
  ATextColour, ABackColour: TColor): string;
begin
  { AFixedFace is deliberately not passed on.  Naming a face is what breaks
    the monospaced font -- Led.UI.PageStyle says why at length -- and the
    face reaches the page through the panel's FixedTypeface instead. }
  Result := LedPageColourCode(AHtml, ATextColour, ABackColour);
end;


{ ---- the buttons at a cell boundary ---- }

procedure TLedNBBarButton.Paint;
var
  C: TLedNBColourSet;
  Face, Edge: TColor;
  R, Radius: Integer;
  Box: TRect;
  W, H: Integer;
begin
  C := LedNBColours;
  { Away from the page, and further while the pointer is on it or it is
    being pressed: three states a reader can tell apart without being told
    what they mean. }
  if FState in [bsDown, bsExclusive] then
    Face := LedMixColours(C.Page, C.Text, 62)
  else if MouseInControl then
    Face := LedMixColours(C.Page, C.Text, 74)
  else
    Face := LedMixColours(C.Page, C.Text, 84);
  Edge := LedMixColours(C.Page, C.Text, 52);

  Box := Rect(0, 0, Width, Height);
  Radius := Height div 2;
  if Radius > LedScale96(10) then Radius := LedScale96(10);

  Canvas.Brush.Style := bsSolid;
  { The gap behind it, so the corners the round rectangle does not cover are
    the pane's own colour rather than whatever was drawn there before. }
  Canvas.Brush.Color := C.Page;
  Canvas.FillRect(Box);
  Canvas.Brush.Color := Face;
  Canvas.Pen.Color := Edge;
  Canvas.Pen.Style := psSolid;
  Canvas.RoundRect(Box, Radius, Radius);

  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  { The theme's text colour rather than the muted one: this is a control,
    and a label nobody can read is not a higher-contrast anything. }
  Canvas.Font.Color := C.Text;
  W := Canvas.TextWidth(Caption);
  H := Canvas.TextHeight(Caption);
  R := (Width - W) div 2;
  if R < 0 then R := 0;
  Canvas.TextOut(R, (Height - H) div 2, Caption);
end;

constructor TLedNBAddBar.Create(AOwner: TComponent);
var
  C: TLedNBColourSet;
  X: Integer;
  Ruler: TBitmap;

  { Each button as wide as its own caption.  Measured rather than guessed:
    the first version gave "Delete Above" eighty pixels, which is what it
    needs at some font sizes and not at the reader's. }
  function Button(const ACaption, AHint: string): TSpeedButton;
  var
    W: Integer;
  begin
    W := Ruler.Canvas.TextWidth(ACaption) + LedScale96(18);
    Result := TLedNBBarButton.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.Hint := AHint;
    Result.ShowHint := True;
    Result.Flat := True;
    Result.Cursor := crHandPoint;
    Result.SetBounds(X, LedScale96(1), W, LedScale96(20));
    Inc(X, W + LedScale96(4));
  end;

begin
  inherited Create(AOwner);
  FCell := -1;
  BevelOuter := bvNone;
  { No frame and no shade of its own: the buttons carry their own edges now,
    and a panel behind them would be a box round a box. }
  BorderStyle := bsNone;
  ParentColor := False;
  C := LedNBColours;
  Color := C.Page;
  Font.Color := C.Text;
  Visible := False;

  Ruler := TBitmap.Create;
  try
    { A canvas of its own to measure with: the panel has no handle yet, and
      a font with no canvas cannot say how wide a word is. }
    Ruler.Canvas.Font.Assign(Font);
    X := LedScale96(2);
    FCode := Button('+ Code', 'Add a code cell below this one');
    FText := Button('+ Text', 'Add a text cell below this one');
    FDrop := Button('Delete Above', 'Delete the cell above');
  finally
    Ruler.Free;
  end;
  SetBounds(0, 0, X + LedScale96(2), LedScale96(22));
end;

{ ---- one cell ---- }

constructor TLedNBCellBox.Create(AOwner: TComponent; ADoc: TLedDocument;
  ACell: Integer; AImages: TCustomImageList);
var
  Colours: TLedNBColourSet;
begin
  inherited Create(AOwner);
  FDoc := ADoc;
  FCell := ACell;
  BevelOuter := bvNone;
  ParentColor := False;
  Colours := LedNBColours;
  Color := Colours.Page;

  FHead := TLabel.Create(Self);
  FHead.Parent := Self;
  FHead.Transparent := True;
  FHead.Font.Color := Colours.Muted;
  { Monospaced, like the execution count in a notebook front end, so that
    [1] and [12] do not shift the code beside them. }
  FHead.Font.Name := FDoc.Master.Font.Name;
  FHead.SetBounds(LedScale96(Pad), LedScale96(Pad), LedScale96(LabelWidth),
    LedScale96(16));
  FHead.OnMouseDown := @ChildMouseDown;
  { The box's own padding counts as outside the editor too. }
  OnMouseDown := @ChildMouseDown;

  { Code cells get a Run button; prose has nothing to run. }
  if FDoc.Notebook.CellKind(FCell) = nbkCode then
  begin
    FRun := TSpeedButton.Create(Self);
    FRun.Parent := Self;
    FRun.Hint := 'Run this cell';
    FRun.ShowHint := True;
    FRun.Flat := True;
    { LED's own run icon, the one the toolbar and the debugger use, so this
      button looks like the rest of the editor.  A caption only where there
      is no image list to take it from -- a pane built without one still has
      a working button rather than a blank square. }
    FRun.Images := AImages;
    if AImages <> nil then
      FRun.ImageIndex := LedIconIndex('run')
    else
      FRun.Caption := '>';
    FRun.SetBounds(LedScale96(Pad), LedScale96(Pad + 18),
      LedScale96(22), LedScale96(22));
    { A hand, because it is a button and the pane around it is a page: with
      the arrow it read as part of the drawing rather than something to
      press. }
    FRun.Cursor := crHandPoint;
    FRun.OnClick := @RunClicked;
  end
  else
  begin
    FEditBtn := TSpeedButton.Create(Self);
    FEditBtn.Parent := Self;
    FEditBtn.Caption := '...';
    FEditBtn.Hint := 'Edit this cell as text (or double-click the text)';
    FEditBtn.ShowHint := True;
    FEditBtn.Flat := True;
    FEditBtn.SetBounds(LedScale96(Pad), LedScale96(Pad + 18),
      LedScale96(20), LedScale96(20));
    FEditBtn.OnClick := @EditClicked;
  end;
end;

{ Rendered prose to text and back.  Leaving it puts the typing away first,
  which is what Commit does. }
procedure TLedNBCellBox.SetEditing(AValue: Boolean);
begin
  if FEditing = AValue then Exit;
  if not AValue then Commit;
  FEditing := AValue;
  Rebuild(Width);
  if FEditing and (FEdit <> nil) and FEdit.CanFocus then FEdit.SetFocus;
end;

procedure TLedNBCellBox.EditClicked(Sender: TObject);
begin
  SetEditing(not FEditing);
end;

{ A wheel notch over a cell scrolls the page of cells.

  Every windowed child of a cell keeps the wheel for itself -- the editor
  because SynEdit scrolls, the prose because the renderer does -- and both of
  them have nothing to scroll, being exactly as tall as their contents.  So
  the notch is passed to the pane, which is what the reader meant. }
procedure TLedNBCellBox.ChildWheel(Sender: TObject; AShift: TShiftState;
  AWheelDelta: Integer; AMousePos: TPoint; var AHandled: Boolean);
var
  Page: TLedNotebookPane;
  Notches: Integer;
begin
  if not (Parent is TLedNotebookPane) then Exit;
  Page := TLedNotebookPane(Parent);
  Notches := AWheelDelta div 120;
  if Notches = 0 then
    if AWheelDelta > 0 then Notches := 1 else Notches := -1;
  Page.ScrollPos := Page.ScrollPos - Notches * LedScale96(48);
  AHandled := True;
end;

procedure TLedNBCellBox.RunClicked(Sender: TObject);
begin
  { What is on screen is what runs, so the typing goes in first. }
  Commit;
  if Assigned(FOnRun) then FOnRun(Self, FCell);
end;

procedure TLedNBCellBox.Commit;
begin
  if (FEdit = nil) or (not LedDocumentIsOpen(FDoc)) then Exit;
  if not FEdit.Modified then Exit;
  FDoc.NBSetCellSource(FCell, FEdit.Lines.Text);
  FEdit.Modified := False;
  if Assigned(FOnEdited) then FOnEdited(Self, FCell);
end;

{ A rendered prose cell, clicked: prose is shown rendered and edited as
  Markdown, which is what every notebook front end does. }
procedure TLedNBCellBox.RenderClicked(Sender: TObject);
begin
  SetEditing(True);
end;

procedure TLedNBCellBox.EditExited(Sender: TObject);
begin
  Commit;
  if FEditing then
  begin
    FEditing := False;
    Rebuild(Width);
  end;
end;

{ Tall enough for all of the cell, with no scrollbar of its own: a box that
  scrolls inside a page that scrolls is a box nobody can read.

  Rows rather than lines, because the text is wrapped: a line that takes
  three rows of a narrow pane needs three rows of height.

  Counted here rather than asked of the editor.  Asking looked obvious and
  was wrong: the wrapped row count is not settled while the box is being laid
  out, and a one-line cell came back as eighteen rows and got a box five
  times the height it needed.  The text is monospaced, so the count is a
  division. }
function TLedNBCellBox.EditorHeight: Integer;
var
  i, Cols, Rows, Len: Integer;
begin
  Result := LedScale96(20);
  if FEdit = nil then Exit;

  Cols := 0;
  if FEdit.CharWidth > 0 then
    Cols := (FEdit.ClientWidth - LedScale96(4)) div FEdit.CharWidth;
  if Cols < 8 then Cols := 8;

  Rows := 0;
  for i := 0 to FEdit.Lines.Count - 1 do
  begin
    Len := UTF8Length(FEdit.Lines[i]);
    if Len <= Cols then
      Inc(Rows)
    else
      Inc(Rows, (Len + Cols - 1) div Cols);
  end;
  if Rows < 1 then Rows := 1;
  Result := Rows * FEdit.LineHeight + LedScale96(6);
end;

{ The editor for this cell, and its own buffer.

  Not one of the document's views: those are views of the whole notebook's
  line buffer, which is what makes a split tab work -- put one in a cell box
  and the box shows the entire file, and setting its text rewrites the
  document.  A cell is its own little document here, the same arrangement the
  notebook highlighter makes for the language highlighter it drives. }
destructor TLedNBCellBox.Destroy;
begin
  { The pictures this cell asked for.  Freeing the source does not free the
    bitmaps when the cache belongs to the pane, which is the point of the
    pane owning it. }
  FPicSrc.Free;
  inherited Destroy;
end;

procedure TLedNBCellBox.MakeEditor;
begin
  if FEdit <> nil then Exit;
  FEdit := TLedNBCellEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Gutter.Visible := False;
  FEdit.RightEdge := 0;
  FEdit.ScrollBars := ssNone;
  { Wrapped, because this pane is narrow and a box with no scrollbar of its
    own would otherwise cut a long line off where nobody can see that it
    continues.  The line view is where a long line is read unwrapped. }
  FEdit.WrapEnabled := True;
  FEdit.Font.Assign(FDoc.Master.Font);
  { A size up from the editor's.  The pane is a reading view -- the cells are
    looked at rather than typed in all day -- and at the editor's own size the
    code in it came out smaller than the prose around it. }
  BumpFont(FEdit.Font, 2);
  LedApplyThemeToEditor(LedCurrentTheme, FEdit);
  { On the code block's shade rather than the page's, which is what makes a
    cell read as a cell.  After the theme, so it is not overwritten by it. }
  FEdit.Color := LedNBColours.CodeBg;

  { Coloured by the language of this cell: prose as Markdown, code as what
    the cell's own magic says and only then as what the notebook says -- a
    %%octave cell is Octave however the file describes itself.

    Through the notebook highlighter rather than the language's own, so that
    the magic line itself is drawn the way a comment is drawn: %%shell says
    what the cell is, %load_ext and !pip are instructions to the front end,
    and none of the three is code the language should be asked to read.  One
    cell wide, so its folding is off -- the nesting it would report is the
    buffer's, and here there is no header above and no output below. }
  FHigh := TLedNBHighlighter.Create(Self);
  FHigh.Folding := False;
  FHigh.OnLineKind := @EditLineKind;
  FHigh.OnLineText := @EditLineText;
  LedApplyThemeToHighlighter(LedCurrentTheme, FHigh);
  FEdit.Highlighter := FHigh;

  FEdit.OnExit := @EditExited;
  FEdit.OnWheelPassedUp := @ChildWheel;
end;

procedure TLedNBCellBox.MakeRender;
var
  C: TLedNBColourSet;
begin
  if FRender <> nil then Exit;
  FProvider := TIpFileDataProvider.Create(Self);
  { Every picture on the page comes through here.  Without it the renderer
    opens the file itself and raises when there is not one -- which a real
    notebook managed on the first try: a Markdown cell referring to an image
    by a bare name took the error out through the paint. }
  FProvider.OnGetImage := @ProvideImage;
  FRender := TLedNBProse.Create(Self);
  FRender.Parent := Self;
  FRender.DataProvider := FProvider;
  { A double click opens it; a single one is left alone so that text can
    still be selected and a link followed. }
  FRender.OnEnterEdit := @RenderClicked;
  FRender.OnWheelPassedUp := @ChildWheel;
  HookRenderChildren;
  { Said out loud rather than left to the default, because the same face and
    size have to be given to the throwaway document that measures how tall a
    page comes out: a measurement taken in one font and drawn in another is
    how a paragraph of prose came to be given a single line of room. }
  FRender.DefaultTypeFace := ProseFace;
  FRender.DefaultFontSize := ProseSize(FDoc);
  FRender.FixedTypeface := FDoc.Master.Font.Name;
  C := LedNBColours;
  FRender.BgColor := C.Page;
  FRender.TextColor := C.Text;
  FRender.LinkColor := C.Link;
  FRender.VLinkColor := C.Link;
  FRender.ALinkColor := C.Link;
end;

{ A picture named by a Markdown cell: beside the notebook, or nothing.

  Nothing is fetched over the network -- a preview that reaches out to the
  internet while somebody reads their own file is not what they asked for --
  and a name that is not there is simply not drawn.  Neither is an error: a
  cell whose picture is missing still has its prose. }
procedure TLedNBCellBox.HookRenderChildren;

  procedure Hook(AControl: TWinControl);
  var
    i: Integer;
    C: TControl;
  begin
    for i := 0 to AControl.ControlCount - 1 do
    begin
      C := AControl.Controls[i];
      TControlEvents(C).OnMouseWheel := @ChildWheel;
      TControlEvents(C).OnDblClick := @ChildDblClick;
      TControlEvents(C).OnMouseDown := @ChildMouseDown;
      if C is TWinControl then Hook(TWinControl(C));
    end;
  end;

begin
  if FRender <> nil then Hook(FRender);
end;

{ What the notebook highlighter is told about the box's own editor: one
  cell, every line of it the cell's own, and a magic line answered as a
  magic.  The buffer's version of this is TLedDocument.NBLineKind, which has
  headers and output to account for; here there is only the cell. }
function TLedNBCellBox.EditLineKind(ALine: Integer; out ACell: Integer;
  out ALang: string): TLedNBLine;
begin
  ACell := 0;
  ALang := FEditLang;
  Result := nblSource;
  if (FEdit <> nil) and (ALine >= 0) and (ALine < FEdit.Lines.Count) and
     LedNBIsMagicLine(FEdit.Lines[ALine], ALine = 0, FEditIPython) then
    Result := nblMagic;
end;

function TLedNBCellBox.EditLineText(ALine: Integer): string;
begin
  Result := '';
  if (FEdit <> nil) and (ALine >= 0) and (ALine < FEdit.Lines.Count) then
    Result := FEdit.Lines[ALine];
end;

procedure TLedNBCellBox.ChildDblClick(Sender: TObject);
begin
  SetEditing(True);
end;

procedure TLedNBCellBox.ChildMouseDown(Sender: TObject;
  AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
begin
  if Parent is TLedNotebookPane then
  begin
    TLedNotebookPane(Parent).LeaveEditing;
    TLedNotebookPane(Parent).CellPicked(FCell);
  end;
end;

function TLedNBCellBox.HaveRemote(const AURL: string;
  out AWhy: string): Boolean;
var
  Fetching: Boolean;
begin
  Result := Pictures.Have(AURL, AWhy, Fetching);
  { Asking started a fetch, so the pane starts looking for the answer.  That
    part is the pane's own: what to do when one arrives is "redraw the cells
    that name it" here and "lay the page out again" in the preview. }
  if Fetching and (Parent is TLedNotebookPane) then
    TLedNotebookPane(Parent).WatchForImages;
end;

{ Where this cell's pictures come from, and the three answers the renderer
  wants about them: Led.UI.Pictures has all of it.  Made on first use, so a
  cell nobody has scrolled to has cost nothing, and sharing the pane's own
  cache -- a cell scrolled out of view must not throw away what scrolling it
  back needs. }
function TLedNBCellBox.Pictures: TLedPictureSource;
begin
  if FPicSrc = nil then
  begin
    if Parent is TLedNotebookPane then
      FPicSrc := TLedPictureSource.Create(TLedNotebookPane(Parent).Pictures)
    else
      { A box with no pane over it, which happens in a check: it keeps its
        own pictures and lets them go with itself. }
      FPicSrc := TLedPictureSource.Create;
    FPicSrc.BaseDir := ExtractFileDir(FDoc.FileName);
    FPicSrc.OnEmbedded := @EmbeddedPicture;
  end;
  FPicSrc.FitWidth := FFitWidth;
  Result := FPicSrc;
end;

{ The pictures a notebook carries in itself: a data: URI in a cell's text, or
  an attachment pasted into it.  This is the part only the cell can answer,
  which is why the shared code asks rather than doing it. }
function TLedNBCellBox.EmbeddedPicture(const AURL: string;
  out ABytes, AMime: string): Boolean;
begin
  Result := LedNBEmbeddedImage(FDoc.Notebook, FCell, AURL, ABytes, AMime);
end;

function TLedNBCellBox.ImageSize(const AURL: string;
  out AW, AH: Integer): Boolean;
begin
  Result := Pictures.SizeOf_(AURL, AW, AH);
end;

procedure TLedNBCellBox.ProvideImage(Sender: TIpHtmlNode; const URL: string;
  var Picture: TPicture);
begin
  Picture := Pictures.Provide(URL);
end;

{ One prose cell as a page, in the theme's colours.

  The style is a notebook front end's: the prose in a proportional face at
  reading size, code on a block a little away from the page, links that look
  like links and are still readable against whatever the page is.  The
  colours are set as attributes as well as in the style sheet, because IPro
  reads rather little CSS and the attributes it does read are the ones that
  decide the background. }
function TLedNBCellBox.ProsePage(const ASource: string;
  AWidth: Integer): string;
var
  C: TLedNBColourSet;
  Html: string;
begin
  C := LedNBColours;
  Html := LedNBHideRemoteImages(LedMarkdownToHTML(ASource), @HaveRemote);
  { A picture wider than the cell is given a size that fits.  The renderer
    draws one at its natural size and cannot scroll a block sideways, so a
    700-pixel meme in a 600-pixel pane simply lost its last hundred pixels. }
  FFitWidth := AWidth;
  Html := LedNBFitImages(Html, AWidth, @ImageSize);
  Html := LedNBColourCode(Html, FDoc.Master.Font.Name, C.Text, C.CodeBg);
  { The page around it is the shared one -- see Led.UI.PageStyle -- so that
    a cell and a Markdown file are drawn the same way. }
  Result := LedPageHead('', C) + Html + LedPageTail;
end;

{ How tall a page of HTML comes out at a given width.

  Laid out by a document of its own and thrown away: the panel will lay the
  same page out again for itself, and measuring twice costs a few
  milliseconds on the cells that have prose in them.  The alternative is
  giving every prose cell a guessed height, which is what showed one line of
  each of them. }
function TLedNBCellBox.RenderedHeight(const APage: string;
  AWidth: Integer): Integer;
var
  Doc: TIpHtmlMeasure;
  Stream: TStringStream;
  H: Integer;
  Surface: TCanvas;
begin
  Result := LedScale96(40);
  { The panel's own canvas where there is one: the measurement is of how tall
    this page is in the font that panel draws with, and a canvas carries the
    font. }
  Surface := Canvas;
  if (FRender <> nil) and (FRender.Canvas <> nil) then Surface := FRender.Canvas;

  Doc := TIpHtmlMeasure.Create;
  Stream := TStringStream.Create(APage);
  try
    try
      { The same face and size the panel was given, for the same reason --
        and the monospaced one too, which was left out: a block of code
        measured in the renderer's own 'Courier New', which no desktop here
        has, is not the height it is then drawn at. }
      Doc.DefaultTypeFace := ProseFace;
      Doc.DefaultFontSize := ProseSize(FDoc);
      Doc.FixedTypeface := FDoc.Master.Font.Name;
      { And the pictures, through the same hook the panel uses.  Without it
        the measuring document opens each <img> itself, raises on the first
        one it cannot find, and the whole measurement is lost -- a prose cell
        with a picture in it then came out at the fallback height, one line
        tall with a scrollbar, which is what a picture arriving did to a
        cell that had been laid out without it. }
      Doc.OnGetImageX := @ProvideImage;
      Doc.LoadFromStream(Stream);
      { A height of nothing lays nothing out: the page is measured with as
        much room as it could want and comes back with what it used. }
      H := Doc.PageHeightAt(Surface, AWidth);
      { A line of slack.  The two layouts agree to a pixel or two and not
        always exactly, and the costs are not symmetrical: a little too much
        room is a little white space, while a little too little folds the
        cell into a box with a scrollbar, which is the thing this is for. }
      if H > 0 then Result := H + ProseSize(FDoc) * 2;
    except
      { A page that will not lay out gets the default height rather than
        taking the cell down with it. }
    end;
  finally
    Stream.Free;
    Doc.Free;
  end;
  { No cap on how tall prose may be -- a cell shows all of itself, which is
    the whole point -- but not past what a widget can be: gtk2 measures a
    control in a signed 16-bit number, and a box bigger than that does not
    come back as a taller box, it comes back wrong. }
  if Result > 30000 then Result := 30000;
end;

{ The pictures and the text a cell produced, as widgets under it. }
procedure TLedNBCellBox.BuildOutputs(var AY: Integer; AWidth: Integer);
var
  Outs: TStringList;
  Flags: TLedNBFlags;
  i, Index_, Count: Integer;
  Bytes, Mime: string;
  Img: TImage;
  Room, W, H: Integer;
  Note: TLabel;
  Stream: TStringStream;
begin
  if FDoc.Notebook.CellKind(FCell) <> nbkCode then Exit;
  Count := 0;
  if FDoc.Notebook.CellOutputs(FCell) <> nil then
    Count := FDoc.Notebook.CellOutputs(FCell).Count;

  { A picture per output that has one.  This is the thing the line view
    cannot do, and the reason this pane exists. }
  for Index_ := 0 to Count - 1 do
    if LedNBImageOf(FDoc.Notebook, FCell, Index_, Bytes, Mime) and
       { A cell that asked matplotlib for SVG has SVG in its outputs. }
       LedNBMakeDrawable(Bytes, Mime) then
    begin
      Img := TImage.Create(Self);
      Img.Parent := Self;
      { Sized here rather than by AutoSize.  Laying the pane out holds
        autosizing off, so an AutoSize image keeps the 90 by 90 the LCL gives
        a fresh control -- which is what a 900-pixel plot came out as. }
      Img.AutoSize := False;
      Img.Proportional := True;
      Stream := TStringStream.Create(Bytes);
      try
        try
          Img.Picture.LoadFromStreamWithFileExt(Stream, LedNBImageExt(Mime));
        except
          { A picture the LCL cannot read is left out rather than left
            half-drawn. }
          FreeAndNil(Img);
        end;
      finally
        Stream.Free;
      end;
      if Img <> nil then
      begin
        Room := AWidth - LedScale96(LabelWidth + Pad * 2);
        if Room < LedScale96(40) then Room := LedScale96(40);
        { A plot is saved at the size the plotting library chose, which is
          usually wider than a side pane.  Shown at its own size it is cut
          off at the edge with no sign that there is more of it, so one that
          does not fit is scaled down whole; one that fits is drawn as it
          is. }
        if (Img.Picture.Width > Room) and (Img.Picture.Width > 0) then
        begin
          Img.Stretch := True;
          W := Room;
          H := Round(Img.Picture.Height * (Room / Img.Picture.Width));
          if H < 1 then H := 1;
        end
        else
        begin
          Img.Stretch := False;
          W := Img.Picture.Width;
          H := Img.Picture.Height;
        end;
        Img.SetBounds(LedScale96(LabelWidth + Pad), AY, W, H);
        Inc(AY, H + LedScale96(4));
      end;
    end;

  { And the text, rendered the same way the line view renders it -- one
    place decides what an output says. }
  Outs := TStringList.Create;
  try
    Outs.TextLineBreakStyle := tlbsLF;
    { The pictures are drawn above; what is wanted here is everything else.
      Otherwise a plot arrives twice -- once as itself and once as the line
      of text the file carries beside it. }
    LedNBOutputLines(FDoc.Notebook, FCell, Outs, Flags, True);
    if Outs.Count = 0 then Exit;
    for i := 0 to Outs.Count - 1 do
    begin
      Note := TLabel.Create(Self);
      Note.Parent := Self;
      Note.Transparent := True;
      Note.Font.Name := FEdit.Font.Name;
      Note.Font.Size := FEdit.Font.Size;
      Note.Font.Color := LedNBColours.Text;
      { An error keeps its own colour, which every theme has one of and
        which is the one thing in an output worth shouting. }
      if (i <= High(Flags)) and Flags[i] then
        Note.Font.Color := LedEnsureReadable(clRed, LedNBColours.Page, 3.5);
      Note.Caption := Outs[i];
      Note.SetBounds(LedScale96(LabelWidth + Pad), AY,
        AWidth - LedScale96(LabelWidth + Pad * 2), FEdit.LineHeight);
      Inc(AY, FEdit.LineHeight);
    end;
  finally
    Outs.Free;
  end;
end;

function TLedNBCellBox.Rebuild(AWidth: Integer): Integer;
var
  Y, Count, i, Room: Integer;
  Source, Page: string;
  Prose: Boolean;
  Inner: TSynCustomHighlighter;
begin
  Width := AWidth;
  { Everything below the head is made afresh: the outputs change shape, and
    a cell that has just run has different ones. }
  for i := ComponentCount - 1 downto 0 do
    if (Components[i] is TImage) or
       ((Components[i] is TLabel) and (Components[i] <> FHead)) then
      Components[i].Free;

  Count := FDoc.Notebook.CellExecutionCount(FCell);
  case FDoc.Notebook.CellKind(FCell) of
    nbkCode:
      if Count >= 0 then
        FHead.Caption := Format('In [%d]:', [Count])
      else
        FHead.Caption := 'In [ ]:';
    { A prose cell needs no label: what it is is plain from the fact that it
      is prose, and the space is better given to the prose. }
    nbkMarkdown: FHead.Caption := '';
  else
    FHead.Caption := 'Raw';
  end;

  Source := FDoc.Notebook.CellSource(FCell);
  Prose := (FDoc.Notebook.CellKind(FCell) = nbkMarkdown) and (not FEditing);
  if FEditBtn <> nil then
    if FEditing then
    begin
      FEditBtn.Caption := 'ok';
      FEditBtn.Hint := 'Show this cell rendered';
    end
    else
    begin
      FEditBtn.Caption := '...';
      FEditBtn.Hint := 'Edit this cell as text';
    end;

  Y := LedScale96(Pad);
  if Prose then
  begin
    MakeRender;
    if FEdit <> nil then FEdit.Visible := False;
    FRender.Visible := True;
    Room := AWidth - LedScale96(ProseGutter + Pad);
    if Room < LedScale96(80) then Room := LedScale96(80);
    { The width is worked out before the page is built, because a picture
      too wide for it is written into the page at the size that fits. }
    Page := ProsePage(Source, Room - LedScale96(8));
    { The panel is made as tall as the prose is, so the cell shows all of it
      and never scrolls inside itself.  A cell of prose folded into a box
      with its own scrollbar is the one thing a reader cannot skim.

      How tall that is has to be measured: the renderer does not know what
      height it wants until it has laid the page out, and the panel cannot be
      asked before it has a page in it. }
    FRender.SetBounds(LedScale96(ProseGutter), Y, Room,
      RenderedHeight(Page, Room));
    FRender.SetHtmlFromStr(Page);
    { The renderer makes its drawing control when it is given a page, so the
      handlers go on after that as well as at creation. }
    HookRenderChildren;
    { Repainted rather than left: the same panel drew the page before the
      pictures arrived, and what it drew for a picture it did not have was
      still on it under the new page. }
    FRender.Invalidate;
    Inc(Y, FRender.Height + LedScale96(4));
  end
  else
  begin
    { Which language to colour the cell in, and whether a line beginning %
      or ! is one of IPython's magics.  Worked out on every rebuild rather
      than once when the editor was made: a reader who types %%octave into a
      cell has changed its language, and the query the highlighter calls
      reads these as it paints.

      An inner made during a paint has nobody to theme it and comes out in
      SynEdit's own colours rather than the reader's, so it is made here. }
    FEditLang := LedNBCellLanguage(Source, FDoc.Notebook.LanguageName);
    if FDoc.Notebook.CellKind(FCell) = nbkMarkdown then
      FEditLang := 'markdown';
    FEditIPython := LedNBCellMagic(Source) = '';
    MakeEditor;
    if FHigh <> nil then
    begin
      Inner := FHigh.EnsureInner(FEditLang);
      if Inner <> nil then
        LedApplyThemeToHighlighter(LedCurrentTheme, Inner);
    end;
    if FRender <> nil then FRender.Visible := False;
    FEdit.Visible := True;
    if FEdit.Lines.Text <> Source then
    begin
      FEdit.Lines.Text := Source;
      FEdit.Modified := False;
    end;
    { In two steps, because the second answer depends on the first: how tall
      the box has to be is how many rows the text wraps into, and that is not
      known until it has been given its width. }
    Room := AWidth - LedScale96(LabelWidth + Pad * 2);
    if Room < LedScale96(80) then Room := LedScale96(80);
    FEdit.SetBounds(LedScale96(LabelWidth + Pad), Y, Room,
      FEdit.LineHeight * 2);
    FEdit.SetBounds(LedScale96(LabelWidth + Pad), Y, Room, EditorHeight);
    Inc(Y, FEdit.Height + LedScale96(4));
  end;

  BuildOutputs(Y, AWidth);
  Result := Y + LedScale96(Pad);
  Height := Result;
end;

{ ---- the pane ---- }

constructor TLedNotebookPane.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  FBoxes := TFPList.Create;
  FPics := TLedNBPictures.Create;
  FFirst := -1;
  FToldCell := -1;
  Color := LedNBColours.Page;
  ParentColor := False;

  { The pane's own scrollbar rather than a scroll box's.  A scroll box scrolls
    by moving its children, and a child cannot be positioned past 32767; this
    one carries the whole notebook's height as an ordinary integer and the
    cells are drawn where the viewport is. }
  FBar := TScrollBar.Create(Self);
  FBar.Parent := Self;
  FBar.Kind := sbVertical;
  FBar.Align := alRight;
  FBar.OnChange := @BarScrolled;
  FBar.Min := 0;
  FBar.Max := 0;

  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.Align := alTop;
  FNote.Transparent := True;
  FNote.Font.Color := LedNBColours.Muted;
  FNote.BorderSpacing.Around := LedScale96(8);
  FNote.Visible := False;

  FResizeTimer := TTimer.Create(Self);
  FResizeTimer.Interval := 150;
  FResizeTimer.Enabled := False;
  FResizeTimer.OnTimer := @ResizeSettled;
  FLaidOutFor := -1;

  { The buttons at a cell boundary, and the timer that decides which
    boundary that is; see TLedNBAddBar for why it is asked rather than
    told. }
  FAddBar := TLedNBAddBar.Create(Self);
  FAddBar.Parent := Self;
  FAddBar.AddCode.OnClick := @AddCodeClicked;
  FAddBar.AddText.OnClick := @AddTextClicked;
  FAddBar.DeleteAbove.OnClick := @DeleteAboveClicked;

  FHoverTimer := TTimer.Create(Self);
  FHoverTimer.Interval := 120;
  FHoverTimer.Enabled := True;
  FHoverTimer.OnTimer := @HoverTick;

  { Pictures arrive after the page they belong to has been drawn, on a
    thread of their own, so the pane looks in rather than being called. }
  FImageTimer := TTimer.Create(Self);
  FImageTimer.Interval := 150;
  FImageTimer.Enabled := False;
  FImageTimer.OnTimer := @ImageTick;
  { A click on the page behind the cells puts away whatever was being typed
    into, the same as a click on a cell. }
  OnMouseDown := @PaneMouseDown;
end;

destructor TLedNotebookPane.Destroy;
begin
  FBoxes.Free;
  FPics.Free;
  inherited Destroy;
end;

function TLedNotebookPane.GetScrollPos: Integer;
begin
  Result := FBar.Position;
end;

procedure TLedNotebookPane.SetScrollPos(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if AValue > FBar.Max then AValue := FBar.Max;
  if FBar.Position = AValue then Exit;
  FBar.Position := AValue;      { fires BarScrolled }
end;

function TLedNotebookPane.LiveDoc: Boolean;
begin
  if (FDoc <> nil) and (not LedDocumentIsOpen(FDoc)) then FDoc := nil;
  Result := FDoc <> nil;
end;

function TLedNotebookPane.CellCount: Integer;
begin
  if not LiveDoc then Result := 0 else Result := FDoc.Notebook.CellCount;
end;

function TLedNotebookPane.BuiltCount: Integer;
begin
  Result := FBoxes.Count;
end;

function TLedNotebookPane.Box(AIndex: Integer): TLedNBCellBox;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex < FBoxes.Count) then
    Result := TLedNBCellBox(FBoxes[AIndex]);
end;

function TLedNotebookPane.BoxOf(ACell: Integer): TLedNBCellBox;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to FBoxes.Count - 1 do
    if TLedNBCellBox(FBoxes[i]).Cell = ACell then
      Exit(TLedNBCellBox(FBoxes[i]));
end;

{ How tall a cell nobody has built yet should be assumed to be.

  The average of the ones that have been built, which is a better guess the
  more of the notebook has been looked at, and a plain default before any of
  it has.  It only moves the scrollbar's thumb: every cell is laid out from
  its own contents when it is built. }
function TLedNotebookPane.Estimate: Integer;
var
  i, Known, Total: Integer;
begin
  Known := 0;
  Total := 0;
  for i := 0 to High(FHeights) do
    if FHeights[i] > 0 then
    begin
      Inc(Known);
      Inc(Total, FHeights[i]);
    end;
  if Known = 0 then Exit(LedScale96(120));
  Result := Total div Known;
end;

function TLedNotebookPane.HeightOf(ACell: Integer): Integer;
begin
  if (ACell >= 0) and (ACell <= High(FHeights)) and (FHeights[ACell] > 0) then
    Result := FHeights[ACell]
  else
    Result := Estimate;
  Inc(Result, LedScale96(CellGap));      { the gap between cells }
end;

function TLedNotebookPane.VirtualTop(ACell: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to ACell - 1 do
    Inc(Result, HeightOf(i));
end;

function TLedNotebookPane.VirtualHeight: Integer;
begin
  Result := VirtualTop(CellCount);
end;

procedure TLedNotebookPane.SyncBar;
var
  Room: Integer;
begin
  Room := VirtualHeight - ClientHeight;
  if Room < 0 then Room := 0;
  FBar.PageSize := ClientHeight;
  FBar.LargeChange := ClientHeight;
  FBar.SmallChange := LedScale96(24);
  FBar.Max := Room + FBar.PageSize;
  FBar.Visible := Room > 0;
end;

procedure TLedNotebookPane.ReleaseBoxes;
var
  i: Integer;
begin
  { Released rather than freed: a box holds the controls a reader clicks, and
    freeing one the LCL still has in hand is "Destroy with LCLRefCount>0" and
    an editor standing on freed memory. }
  for i := 0 to FBoxes.Count - 1 do
  begin
    TLedNBCellBox(FBoxes[i]).Visible := False;
    Application.ReleaseComponent(TLedNBCellBox(FBoxes[i]));
  end;
  FBoxes.Clear;
  FFirst := -1;
end;

{ Builds the cells the viewport covers, and only those.

  Every box is positioned against the top of the pane, so no coordinate is
  ever more than a screen away from zero however long the notebook is.  A
  cell's real height is learnt here and remembered, which is why the
  scrollbar settles as the reader moves through the file. }
procedure TLedNotebookPane.BuildWindow;
var
  Cell, Y, W, Offset, Grown: Integer;
  B: TLedNBCellBox;
  Keep: TFPList;
begin
  if FBuilding then Exit;
  if not LiveDoc then
  begin
    ReleaseBoxes;
    Exit;
  end;
  FBuilding := True;
  Keep := TFPList.Create;
  DisableAutoSizing;
  try
    W := ClientWidth - LedScale96(4);
    if FBar.Visible then Dec(W, FBar.Width);
    if W < LedScale96(120) then W := LedScale96(120);

    Offset := FBar.Position;
    { Which cell the top of the viewport is in, and how far into it. }
    Cell := 0;
    while (Cell < CellCount - 1) and
          (VirtualTop(Cell) + HeightOf(Cell) <= Offset) do
      Inc(Cell);
    FFirst := Cell;
    Y := VirtualTop(Cell) - Offset;

    while (Cell < CellCount) and (Y < ClientHeight) do
    begin
      { A cell already on screen is kept rather than built again.  Building
        one measures a page of prose, and rebuilding the lot on every wheel
        notch would make scrolling cost what opening the pane costs. }
      B := BoxOf(Cell);
      if B = nil then
      begin
        B := TLedNBCellBox.Create(Self, FDoc, Cell, FImages);
        B.Parent := Self;
        B.OnRunCell := @CellRun;
        B.OnEdited := @CellEdited;
        B.SetBounds(0, Y, W, LedScale96(40));
        Grown := B.Rebuild(W);
      end
      else if B.Width <> W then
        Grown := B.Rebuild(W)
      else
        Grown := B.Height;

      B.Left := 0;
      B.Top := Y;
      Keep.Add(B);
      if Cell <= High(FHeights) then FHeights[Cell] := Grown;
      Inc(Y, Grown + LedScale96(CellGap));
      Inc(Cell);
    end;

    { Whatever scrolled out of sight goes away -- released, not freed. }
    for Cell := 0 to FBoxes.Count - 1 do
      if Keep.IndexOf(FBoxes[Cell]) < 0 then
      begin
        TLedNBCellBox(FBoxes[Cell]).Visible := False;
        Application.ReleaseComponent(TLedNBCellBox(FBoxes[Cell]));
      end;
    FBoxes.Clear;
    for Cell := 0 to Keep.Count - 1 do FBoxes.Add(Keep[Cell]);
  finally
    Keep.Free;
    EnableAutoSizing;
    FBuilding := False;
  end;
  { The heights just learnt may have changed how tall the notebook is. }
  SyncBar;
end;

{ Pictures that have arrived since the last look.

  Every cell on screen whose text names one is drawn again, which is the whole
  of what makes a fetched picture appear: the page was laid out without it and
  is worth laying out again now.  Only the cells on screen -- one that has not
  been built yet takes the picture out of the cache when it is.

  The timer runs only while something is in flight, so a notebook with no
  pictures on the web costs nothing. }
procedure TLedNotebookPane.ImageTick(Sender: TObject);
var
  i, Cell: Integer;
  URL: string;
  Cells: TStringList;
begin
  if not LiveDoc then
  begin
    FImageTimer.Enabled := False;
    Exit;
  end;

  Cells := TStringList.Create;
  try
    while LedNBImages.TakeArrived(URL) do
      for i := 0 to FBoxes.Count - 1 do
      begin
        Cell := TLedNBCellBox(FBoxes[i]).Cell;
        if (Cell < 0) or (Cell >= CellCount) then Continue;
        if (Pos(URL, FDoc.Notebook.CellSource(Cell)) > 0) and
           (Cells.IndexOf(IntToStr(Cell)) < 0) then
          Cells.Add(IntToStr(Cell));
      end;

    { Redrawn after the whole queue has been read, so a cell with three
      pictures in it is laid out once rather than three times. }
    for i := 0 to Cells.Count - 1 do
      RefreshCell(StrToIntDef(Cells[i], -1));
  finally
    Cells.Free;
  end;

  FImageTimer.Enabled := LedNBImages.Pending > 0;
end;

procedure TLedNotebookPane.LeaveEditing;
var
  i: Integer;
begin
  for i := 0 to FBoxes.Count - 1 do
    if TLedNBCellBox(FBoxes[i]).Editing then
    begin
      Application.QueueAsyncCall(@LeaveEditDeferred,
        PtrInt(TLedNBCellBox(FBoxes[i]).Cell));
      Exit;
    end;
end;

{ The cell is found again by number rather than held as a pointer: between
  the click and this, the pane may have been scrolled or reloaded and the box
  released. }
procedure TLedNotebookPane.LeaveEditDeferred(AData: PtrInt);
var
  B: TLedNBCellBox;
begin
  if not LiveDoc then Exit;
  B := BoxOf(Integer(AData));
  if (B <> nil) and B.Editing then B.SetEditing(False);
end;

{ A cell the reader has put the mouse in. }
procedure TLedNotebookPane.CellPicked(ACell: Integer);
begin
  { Counted as where the pane is, so that following the caret back here does
    not scroll the pane away from the cell just clicked. }
  FToldCell := TopCell;
  if Assigned(FOnPicked) then FOnPicked(Self, ACell);
end;

{ Where the pointer is, and whether it is near the foot of a cell.

  Near, not on: the strip between two cells is a few pixels of background,
  and a reader aiming at it with a mouse does not hit a four-pixel target.
  The whole bottom quarter of a cell counts, up to a limit -- a very tall
  cell should not be a bar that follows the pointer half way up it. }
procedure TLedNotebookPane.HoverTick(Sender: TObject);
var
  P: TPoint;
  i, Edge, Reach: Integer;
  B, Near_: TLedNBCellBox;
begin
  if (FAddBar = nil) or (not LiveDoc) or (not Showing) then
  begin
    if (FAddBar <> nil) and FAddBar.Visible then FAddBar.Visible := False;
    Exit;
  end;

  P := ScreenToClient(Mouse.CursorPos);
  { The bar itself counts as being at its own boundary, or moving the
    pointer onto a button would take the button away. }
  if FAddBar.Visible and (P.x >= FAddBar.Left) and
     (P.x < FAddBar.Left + FAddBar.Width) and (P.y >= FAddBar.Top) and
     (P.y < FAddBar.Top + FAddBar.Height) then Exit;

  Near_ := nil;
  if (P.x >= 0) and (P.x < ClientWidth) and (P.y >= 0) and
     (P.y < ClientHeight) then
    for i := 0 to FBoxes.Count - 1 do
    begin
      B := TLedNBCellBox(FBoxes[i]);
      Edge := B.Top + B.Height;
      Reach := B.Height div 4;
      if Reach > LedScale96(40) then Reach := LedScale96(40);
      if Reach < LedScale96(12) then Reach := LedScale96(12);
      if (P.y >= Edge - Reach) and (P.y <= Edge + LedScale96(6)) then
      begin
        Near_ := B;
        Break;
      end;
    end;

  if Near_ = nil then
  begin
    if FAddBar.Visible then FAddBar.Visible := False;
    Exit;
  end;
  PlaceAddBar(Near_);
end;

{ The bar at the foot of a box, indented to where a cell's own text starts so
  that it lines up with the cell it belongs to. }
procedure TLedNotebookPane.PlaceAddBar(ABox: TLedNBCellBox);
begin
  FAddBar.Cell := ABox.Cell;
  { Just below the boundary rather than across it, and indented to where a
    cell's own text starts so that it lines up with the cells rather than
    with the pane.

    Below, because what is above the boundary is the foot of the cell's
    editor -- the end of its last line, which is somewhere a reader clicks
    -- and what is below it is the next cell's label, which is not.  The
    pointer is in the cell above when the bar appears, so it appears
    somewhere the pointer is not already. }
  FAddBar.SetBounds(LedScale96(LabelWidth + Pad),
    ABox.Top + ABox.Height + (LedScale96(CellGap) - FAddBar.Height) div 2,
    FAddBar.Width, FAddBar.Height);
  FAddBar.Visible := True;
  FAddBar.BringToFront;
end;

procedure TLedNotebookPane.ReloadKeeping(ATopCell: Integer);
var
  Tries: Integer;
begin
  Reload;
  if (ATopCell < 0) or (ATopCell >= CellCount) then Exit;

  { Followed, not scrolled to: nobody asked to move, so nothing is reported
    and the text view is not dragged along behind it.

    More than once, because where a cell is depends on how tall the ones
    above it are, and a reload has just forgotten every height it knew: the
    first attempt lands somewhere near, measures the cells it landed on, and
    the next one lands closer.  Measured on a four-hundred-cell notebook,
    the first attempt was five cells out. }
  Tries := 0;
  while (TopCell <> ATopCell) and (Tries < 4) do
  begin
    FollowToCell(ATopCell);
    Inc(Tries);
  end;
end;

procedure TLedNotebookPane.ShowAddBarUnder(ACell: Integer);
var
  B: TLedNBCellBox;
begin
  B := BoxOf(ACell);
  { A cell with no box has no boundary to put the bar at.  Asked for by
    number, though, the answer is to build it rather than to do nothing:
    the pane keeps boxes only for the cells the viewport covers, and a
    relayout throws away every measured height and re-estimates, so the
    same scroll position can come back covering a different set of cells.
    Between asking for a cell and asking for the bar under it, the box can
    therefore have gone -- and a request that quietly evaporates is worse
    than a scroll nobody asked for.

    The pointer's own path never reaches this: hovering hands the box
    straight to PlaceAddBar, because the pointer is over it. }
  if B = nil then
  begin
    ScrollToCell(ACell);
    B := BoxOf(ACell);
  end;
  if B = nil then Exit;
  PlaceAddBar(B);
end;

procedure TLedNotebookPane.AddCodeClicked(Sender: TObject);
begin
  if Assigned(FOnInsert) then FOnInsert(Self, FAddBar.Cell, nbkCode);
end;

procedure TLedNotebookPane.AddTextClicked(Sender: TObject);
begin
  if Assigned(FOnInsert) then FOnInsert(Self, FAddBar.Cell, nbkMarkdown);
end;

procedure TLedNotebookPane.DeleteAboveClicked(Sender: TObject);
begin
  if Assigned(FOnDelete) then FOnDelete(Self, FAddBar.Cell);
end;

procedure TLedNotebookPane.PaneMouseDown(Sender: TObject;
  AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
begin
  LeaveEditing;
end;

procedure TLedNotebookPane.WatchForImages;
begin
  if (FImageTimer <> nil) and (LedNBImages.Pending > 0) then
    FImageTimer.Enabled := True;
end;

function TLedNotebookPane.TopCell: Integer;
var
  Cell, Offset: Integer;
begin
  Result := -1;
  if not LiveDoc then Exit;
  if CellCount = 0 then Exit;
  { The same arithmetic BuildWindow starts with: which cell the top of the
    viewport is inside. }
  Offset := FBar.Position;
  Cell := 0;
  while (Cell < CellCount - 1) and
        (VirtualTop(Cell) + HeightOf(Cell) <= Offset) do
    Inc(Cell);
  Result := Cell;
end;

procedure TLedNotebookPane.FollowToCell(ACell: Integer);
begin
  if not LiveDoc then Exit;
  if TopCell = ACell then Exit;
  FFollowing := True;
  try
    ScrollToCell(ACell);
  finally
    FFollowing := False;
  end;
  { Remembered as told, so that the next report is a real move by the
    reader and not the tail of this one. }
  FToldCell := TopCell;
end;

{ Says which cell the reader has scrolled to, once per cell rather than once
  per pixel, and never for a scroll the pane was told to make. }
procedure TLedNotebookPane.ReportTop;
var
  Cell: Integer;
begin
  if FFollowing then Exit;
  Cell := TopCell;
  if (Cell < 0) or (Cell = FToldCell) then Exit;
  FToldCell := Cell;
  if Assigned(FOnScrolled) then FOnScrolled(Self, Cell);
end;

procedure TLedNotebookPane.ReportTopNow;
begin
  ReportTop;
end;

procedure TLedNotebookPane.BarScrolled(Sender: TObject);
begin
  BuildWindow;
  ReportTop;
end;

function TLedNotebookPane.DoMouseWheel(AShift: TShiftState;
  AWheelDelta: Integer; AMousePos: TPoint): Boolean;
var
  Notches: Integer;
begin
  Notches := AWheelDelta div 120;
  if Notches = 0 then
    if AWheelDelta > 0 then Notches := 1 else Notches := -1;
  ScrollPos := ScrollPos - Notches * LedScale96(48);
  ReportTop;
  Result := True;
end;

procedure TLedNotebookPane.Resize;
begin
  inherited Resize;
  if FBoxes = nil then Exit;
  if ClientWidth = FLaidOutFor then Exit;
  FResizeTimer.Enabled := False;
  FResizeTimer.Enabled := True;
end;

procedure TLedNotebookPane.ResizeSettled(Sender: TObject);
begin
  FResizeTimer.Enabled := False;
  Relayout;
end;

procedure TLedNotebookPane.Relayout;
var
  i: Integer;
begin
  if not LiveDoc then Exit;
  { Every height was measured at the old width and none of them is worth
    keeping: a cell's wrapped text and a scaled picture both depend on it. }
  for i := 0 to High(FHeights) do FHeights[i] := -1;
  FLaidOutFor := ClientWidth;
  SyncBar;
  BuildWindow;
end;

procedure TLedNotebookPane.ShowDocument(ADoc: TLedDocument);
begin
  if (ADoc <> nil) and (not ADoc.IsNotebook) then ADoc := nil;
  { A different notebook, so the pictures decoded for the last one go.  Not
    only to save the memory: an attachment is named by the cell that carries
    it -- "attachment:plot.png" -- and two notebooks can each have one of
    those.  A theme change goes through Reload instead and keeps them, which
    is right: a picture is not themed. }
  if (ADoc <> FDoc) and (FPics <> nil) then FPics.Clear;
  FDoc := ADoc;
  Reload;
end;

procedure TLedNotebookPane.Reload;
var
  i: Integer;
begin
  { Nothing in here is the reader scrolling, and the scrollbar going back to
    zero on the way through is the loudest thing that looks like it: left to
    report itself it said "the reader is now at cell nought", and the text
    view dutifully went to the top of the file.  That was the jump after
    adding a cell. }
  FFollowing := True;
  try
  LiveDoc;
  { The theme may have changed since the cells were built, and every colour
    in here comes from it. }
  Color := LedNBColours.Page;
  FNote.Font.Color := LedNBColours.Muted;

  ReleaseBoxes;
  if FDoc = nil then
  begin
    SetLength(FHeights, 0);
    FBar.Visible := False;
    FNote.Caption := 'This is not a Jupyter notebook.';
    FNote.Visible := True;
    Exit;
  end;
  FNote.Visible := False;

  SetLength(FHeights, CellCount);
  for i := 0 to High(FHeights) do FHeights[i] := -1;
  FLaidOutFor := ClientWidth;
  FBar.Position := 0;
  SyncBar;
  BuildWindow;
  finally
    FFollowing := False;
  end;
  FToldCell := TopCell;
end;

procedure TLedNotebookPane.RefreshCell(ACell: Integer);
var
  B: TLedNBCellBox;
begin
  if not LiveDoc then Exit;
  B := BoxOf(ACell);
  { Not on screen: there is nothing to redraw, and the height it will be
    built at is taken from the cell itself next time. }
  if B = nil then
  begin
    if (ACell >= 0) and (ACell <= High(FHeights)) then FHeights[ACell] := -1;
    Exit;
  end;
  { A cell that has just run is a different height -- it has output now --
    so what is under it moves.  The box itself is kept: this is called from a
    kernel event and from the Run button's own click, and releasing the box
    then is what destroyed the control that was processing the event. }
  if (ACell >= 0) and (ACell <= High(FHeights)) then
    FHeights[ACell] := B.Rebuild(B.Width)
  else
    B.Rebuild(B.Width);
  LayoutBelow(ACell);
end;

procedure TLedNotebookPane.ScrollToCell(ACell: Integer);
begin
  if not LiveDoc then Exit;
  if ACell < 0 then ACell := 0;
  if ACell >= CellCount then ACell := CellCount - 1;
  ScrollPos := VirtualTop(ACell);
  { When the position was already there, nothing was rebuilt by the setter. }
  if BoxOf(ACell) = nil then BuildWindow;
end;

procedure TLedNotebookPane.CellRun(Sender: TObject; ACell: Integer);
begin
  if Assigned(FOnRun) then FOnRun(Self, ACell);
end;

procedure TLedNotebookPane.CellEdited(Sender: TObject; ACell: Integer);
var
  B: TLedNBCellBox;
begin
  if not LiveDoc then Exit;
  { A cell grows as it is typed into, so what is under it moves.  Its own box
    is not rebuilt -- that would take the caret out of the editor being typed
    in -- but its new height is recorded and the cells below are moved. }
  B := BoxOf(ACell);
  if B = nil then Exit;
  if B.Editor <> nil then B.Editor.Height := B.EditorHeight;
  B.Height := B.Editor.Top + B.Editor.Height + LedScale96(Pad);
  if (ACell >= 0) and (ACell <= High(FHeights)) then
    FHeights[ACell] := B.Height;
  LayoutBelow(ACell);
end;

{ The boxes under a cell that changed height, moved by the difference.

  Moved rather than rebuilt, which is the whole point: rebuilding takes the
  caret out of a cell being typed in, and releases the box of a button being
  clicked. }
procedure TLedNotebookPane.LayoutBelow(ACell: Integer);
var
  i, Y: Integer;
  B: TLedNBCellBox;
begin
  B := BoxOf(ACell);
  if B = nil then Exit;
  Y := B.Top + B.Height + LedScale96(CellGap);
  for i := 0 to FBoxes.Count - 1 do
    if TLedNBCellBox(FBoxes[i]).Cell > ACell then
    begin
      TLedNBCellBox(FBoxes[i]).Top := Y;
      Inc(Y, TLedNBCellBox(FBoxes[i]).Height + LedScale96(CellGap));
    end;
  SyncBar;
end;

end.
