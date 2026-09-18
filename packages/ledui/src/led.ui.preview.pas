{ LED - a lightweight editor.  The Markdown and wiki preview pane.

  medit rendered HTML with a 3,100-line DOM-to-text-buffer renderer of its
  own, because GTK had no HTML control it could use.  Lazarus ships
  TIpHtmlPanel, which the IDE's own help viewer is built on, so the renderer
  is not carried over.

  Wiki markup renders here too, in medit's UseMod / Habitat dialect -- see
  Led.Core.Wiki.  It was dropped up front as a niche format, which turned out
  to be a judgement about other people's files rather than this editor's
  users. }
unit Led.UI.Preview;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Controls, ExtCtrls, StdCtrls, Graphics, Forms,
  LCLIntf, LCLType,
  IpHtml, Ipfilebroker,
  Led.Core.Markdown, Led.Core.Wiki, Led.Core.Prefs, Led.Core.NBImage,
  Led.Core.NBFetch, Led.Core.NBConvert, Led.UI.Dpi, Led.UI.PageStyle,
  Led.UI.Pictures;

type
  { Fired when the reader clicks a place in the rendered page, with the source
    line that place came from. }
  TLedPreviewLineEvent = procedure(Sender: TObject; ALine: Integer) of object;

  { Reaching two things IPro keeps to itself, both needed for the same
    question: which line of the document is at the top of the page.

    Going the other way is easy -- MakeAnchorVisible scrolls to a block --
    and there is nothing at all for the reverse, so the page positions of
    the blocks are read off the nodes and kept.  FindElementId is protected
    on TIpHtml and ReportDrawRects is protected on TIpHtmlNode, so each is
    reached through a descendant declared here, the same way the notebook
    pane reaches GetPageRect. }
  TLedIpHtmlReach = class(TIpHtml)
  public
    function FindId(const AId: string): TIpHtmlNode;
  end;

  TLedIpNodeReach = class(TIpHtmlNodeCore)
  private
    procedure NoteRect(const R: TRect);
  public
    { The top of the topmost rectangle the node draws into, in page
      coordinates -- the same space the scroll position is in. }
    function PageTop: Integer;
  end;

  TLedPreviewPane = class(TPanel)
  private
    FHtml: TIpHtmlPanel;
    FProvider: TIpFileDataProvider;
    FNote: TLabel;
    FBaseDir: string;
    FIsWiki: Boolean;
    FTimer: TTimer;
    FResizeTimer: TTimer;
    FImageTimer: TTimer;
    FHasRendered: Boolean;
    FPendingRender: Boolean;
    FRenderedWidth: Integer;
    FRenderedText: string;
    FRenderedTitle: string;
    FRenderedWiki: Boolean;
    FPendingText: string;
    FPendingTitle: string;
    FLineIds: array of Integer;   { the source lines the page carries, rising }
    { Where those lines are on the page, for answering which one is at the
      top of it.  Built after a render, and only for the blocks that report
      a position: a paragraph reports none, and a heading does, which is why
      the answer is a section rather than a line -- and a section is the
      granularity a reader scrolling a preview is working in anyway. }
    FTopY: array of Integer;
    FTopLine: array of Integer;
    FTopsFor: Integer;            { the scroll height they were built at }
    FLastScroll: Integer;
    FScrollTimer: TTimer;
    FPicSrc: TLedPictureSource;
    FOnScrolled: TLedPreviewLineEvent;
    FSyncedLine: Integer;         { the last line scrolled to, to not repeat }
    FOnJumpToLine: TLedPreviewLineEvent;
    procedure BuildTops;
    function LineAtTop(AY: Integer): Integer;
    procedure ScrollTick(Sender: TObject);
    function CodeColumns: Integer;
    procedure CollectLineIds(const APage: string);
    function NearestLineId(ALine: Integer): Integer;
    function LineUnderCursor: Integer;
    procedure HtmlClicked(Sender: TObject);
    procedure Render(Sender: TObject);
    procedure ApplyFixedFont;
    function TruncationNote(AShown, AWhole: Integer): string;
    { Whether a picture on the web is in hand, and if not, why the page should
      say so in its place.  Asking for one starts the fetch. }
    function HaveRemote(const AURL: string; out AWhy: string): Boolean;
    { How big the picture behind a reference is, so that one too wide for
      the pane can be written into the page at a size that fits. }
    function ImageSize(const AURL: string; out AW, AH: Integer): Boolean;
    { Pictures that have arrived since the last look.  The page was laid out
      without them and is laid out again now -- there is no way to put one
      picture into a page IPro is already holding. }
    procedure ImageTick(Sender: TObject);
    function Pictures: TLedPictureSource;
    { Resolves an <img> URL against the document's own folder, since
      TIpFileDataProvider otherwise looks relative to the process's working
      directory.  Any failure to load degrades to "no image" instead of an
      exception escaping into IPro's layout code. }
    procedure ProvideImage(Sender: TIpHtmlNode; const URL: string;
      var Picture: TPicture);
    { TIpHtmlPanel relays out the whole document on every repaint it is
      given, not only when the content actually changed -- so a live
      drag-resize would otherwise force a full relayout on every
      intermediate size.  Hiding it for the duration of the drag and
      revealing it once, after the size has settled, keeps the drag itself
      responsive; see FResizeTimer. }
    procedure PaneResize(Sender: TObject);
    procedure ResizeSettled(Sender: TObject);
  public
    { The face code blocks are set in.  Public so a check can see that it is
      the editor's and not IPro's default. }
    function FixedFace: string;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Shows AText rendered as Markdown.  Debounced by default, because a
      refresh can arrive several times over in a row -- a tab change is three
      notifications -- and IPro relays out the whole document each time.
      AImmediate is for the one case where the quarter second is all the user
      would see: opening the pane, where waiting means looking at a blank
      panel for as long as it takes to notice it is blank. }
    procedure Update(const AText, ATitle, ABaseDir: string;
      AImmediate: Boolean = False);
    { Which dialect to render.  Set from the file name, so a .wiki and a .md
      in adjacent tabs each render as themselves. }
    property IsWiki: Boolean read FIsWiki write FIsWiki;
    procedure ShowMessage_(const AText: string);
    { Draws the same document again in the colours it is now given.  The
      render path skips a page it has already drawn at the same width, which
      is right for a tab change and wrong for a theme change: the text has
      not moved but every colour in it has. }
    procedure Restyle;
    { Renders now instead of a quarter-second from now, and says whether the
      HTML control took it.  For the self-test: the render path swallows an
      exception into a message label, so "it rendered" and "it quietly gave
      up" look identical from outside. }
    function RenderNow: Boolean;

    { Scrolls the rendered page to the block the given source line belongs to,
      and says whether there was one to scroll to.  The mapping is per block:
      a line inside a paragraph scrolls to the paragraph. }
    function ScrollToLine(ALine: Integer): Boolean;

    { Says the page is already showing the block ALine belongs to, without
      scrolling it there.  This is how a click on the page keeps the page
      still: the caret lands on the clicked line, the text view scrolls to
      put the caret somewhere comfortable, and the scroll comes back here as
      a sync request for whatever line ended up at the top -- a different
      line, and often a different block, from the one that was clicked.
      Telling the pane where the text now is stops that request moving the
      thing the reader just clicked on. }
    procedure AssumeSynced(ALine: Integer);

    { Where the page is scrolled to, in pixels.  For the self-test, which
      otherwise has no way to tell a page that stayed still from one that
      was scrolled back to where it started. }
    function ScrollPos: Integer;

    { Whether the page the renderer is holding carries an element with this
      id.  For the self-test: the pane hands over a string and the renderer
      parses it, and the two are worth telling apart. }
    function PageHasElement(const AId: string): Boolean;

    { The last document line the page was built from, or 0 for an empty
      page.  Less than the document's own line count when the document was
      too big to lay out whole -- see LedPreviewCut -- which is the one way
      from outside to tell a capped page from a complete one. }
    function LastLineShown: Integer;

    { Which line of the document is at the top of the page as it stands.
      What OnScrolledToLine reports, asked for directly: a check can scroll
      the page but cannot make the reader's own scroll happen. }
    function LineAtTopOfPage: Integer;

    { Clicking a place in the page reports the line it was made from, which is
      how the text view follows the preview. }
    property OnJumpToLine: TLedPreviewLineEvent
      read FOnJumpToLine write FOnJumpToLine;

    { And scrolling the page reports the line that is now at the top of it,
      which is the other half of keeping the two in step.

      Polled rather than watched: the renderer scrolls inside a control of
      its own and raises nothing anybody outside can hear -- the same reason
      the notebook pane polls for its hover bar, and the same control that
      swallowed the wheel and the double click. }
    property OnScrolledToLine: TLedPreviewLineEvent
      read FOnScrolled write FOnScrolled;
  end;

{ True when this document is one the preview understands. }
function LedPreviewHandles(const AFileName: string): Boolean;
{ The first line matters because a wiki file may be named anything and say
  so with a "<!-- wiki -->" comment, which is medit's convention. }
function LedPreviewHandles(const AFileName, AFirstLine: string): Boolean;

implementation

var
  { ReportDrawRects wants a method to call back, and a class used only as a
    way through to a protected member must not have fields of its own: the
    object it is cast over is a real node and has no room for them.  So the
    smallest possible piece of state lives here.  Single-threaded, which is
    what makes that safe: this runs on the main thread inside one call. }
  GNodeTop: Integer;

function TLedIpHtmlReach.FindId(const AId: string): TIpHtmlNode;
begin
  Result := FindElementId(AId);
end;

procedure TLedIpNodeReach.NoteRect(const R: TRect);
begin
  if (R.Bottom > R.Top) and (R.Top < GNodeTop) then GNodeTop := R.Top;
end;

function TLedIpNodeReach.PageTop: Integer;
begin
  GNodeTop := MaxInt;
  ReportDrawRects(@NoteRect);
  if GNodeTop = MaxInt then Result := -1 else Result := GNodeTop;
end;

function LedPreviewHandles(const AFileName: string): Boolean;
begin
  Result := LedPreviewHandles(AFileName, '');
end;

function LedPreviewHandles(const AFileName, AFirstLine: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.md') or (Ext = '.markdown') or (Ext = '.mdx') or
            LedIsWikiFile(AFileName, AFirstLine);
end;

constructor TLedPreviewPane.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';

  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.Align := alTop;
  FNote.WordWrap := True;
  FNote.Caption := 'Open a Markdown or wiki file to see it rendered here.';

  FProvider := TIpFileDataProvider.Create(Self);
  FProvider.OnGetImage := @ProvideImage;

  FHtml := TIpHtmlPanel.Create(Self);
  FHtml.Parent := Self;
  FHtml.Align := alClient;
  FHtml.DataProvider := FProvider;
  FHtml.Visible := False;
  ApplyFixedFont;
  { IPro lays a page out on the control's own canvas and then, by default,
    paints it into a bitmap it allocates for the purpose.  Nothing makes the
    two agree about resolution, and here they do not: the startup sweep puts
    the control at the scaled PPI and a fresh TBitmap comes up at the
    screen's.  Every word was measured at twice the size it was drawn at,
    which is a page of text with a gap after every word that grows with the
    word.

    Painting straight onto the control's canvas makes the measuring and the
    painting the same canvas at the same resolution -- and that resolution is
    the scaled one, so the page is drawn at the size this display is scaled
    to rather than at half of it.  Doing the same by putting the control back
    on the screen's PPI also lines the two up, but lines them up small.

    The buffer this gives up is what stops flicker on a repaint; gtk2
    double-buffers its own expose events, so on this widgetset there is
    nothing to lose. }
  FHtml.UsePaintBuffer := False;
  { Only a click that did not drag and did not land on a link gets here --
    TIpHtmlInternalPanel.MouseUp sees to that -- so selecting text in the
    preview and following a link both still mean what they meant. }
  FHtml.OnClick := @HtmlClicked;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 250;
  FTimer.Enabled := False;
  FTimer.OnTimer := @Render;

  { Runs only while a picture is in flight, so a document with none costs
    nothing. }
  FImageTimer := TTimer.Create(Self);
  FImageTimer.Interval := 300;
  FImageTimer.Enabled := False;
  FImageTimer.OnTimer := @ImageTick;

  { The renderer scrolls inside a control of its own and says nothing about
    it, so the pane looks. }
  FScrollTimer := TTimer.Create(Self);
  FScrollTimer.Interval := 150;
  FScrollTimer.Enabled := True;
  FScrollTimer.OnTimer := @ScrollTick;
  FTopsFor := -1;
  FLastScroll := -1;

  FResizeTimer := TTimer.Create(Self);
  FResizeTimer.Interval := 200;
  FResizeTimer.Enabled := False;
  FResizeTimer.OnTimer := @ResizeSettled;
  OnResize := @PaneResize;
end;

destructor TLedPreviewPane.Destroy;
begin
  FPicSrc.Free;
  inherited Destroy;
end;

procedure TLedPreviewPane.PaneResize(Sender: TObject);
begin
  if FHasRendered and FHtml.Visible then
    FHtml.Visible := False;
  FResizeTimer.Enabled := False;
  FResizeTimer.Enabled := True;
end;

procedure TLedPreviewPane.ResizeSettled(Sender: TObject);
begin
  FResizeTimer.Enabled := False;
  if not (FHasRendered or FPendingRender) then Exit;
  { The page was built for a width -- its code blocks are wrapped to it, see
    CodeColumns -- so a pane that is no longer that width needs the page
    rebuilt rather than merely shown again.  This is also where a render that
    arrived before the pane had a size gets made good. }
  if FPendingRender or (FHtml.ClientWidth <> FRenderedWidth) then
    Render(nil)
  else
    FHtml.Visible := True;
end;


procedure TLedPreviewPane.ShowMessage_(const AText: string);
begin
  FNote.Caption := AText;
  FNote.Visible := True;
  FHtml.Visible := False;
  FHasRendered := False;
  FPendingRender := False;
  FRenderedText := '';
  SetLength(FLineIds, 0);
  FSyncedLine := 0;
  FTimer.Enabled := False;
end;

procedure TLedPreviewPane.Update(const AText, ATitle, ABaseDir: string;
  AImmediate: Boolean);
begin
  FPendingText := AText;
  FPendingTitle := ATitle;
  FBaseDir := ABaseDir;
  FTimer.Enabled := False;
  if AImmediate then
  begin
    Render(nil);
    Exit;
  end;
  { Restarting the timer on each call is the debounce: a burst of refreshes
    renders once, at the end. }
  FTimer.Enabled := True;
end;

{ The line that says the page is not all of the document. }
function TLedPreviewPane.TruncationNote(AShown, AWhole: Integer): string;
begin
  { The id is how a check tells the note reached the renderer rather than
    only the string that was handed to it. }
  Result := Format('<hr><p id="ledcut"><i>Previewing the first %d KB ' +
    'of %d KB.  Laying out a page costs more than the square of its size, ' +
    'so the whole of this one would take far longer than this did; ' +
    'raise %s to see more.</i></p>',
    [AShown div 1024, AWhole div 1024, LedPrefPreviewMaxKB]);
end;

{ How many characters of a code block fit across the pane.

  A <pre> is the one thing on a page that will not narrow: its minimum width
  is its longest line, and IPro, which cannot scroll a single block, answers
  by laying the whole document out that wide -- which is how an eighty-column
  code sample pushes the prose off the right of a pane half that wide.  So
  the page is built to fit, and this is the measurement it is built to.

  Measured in the font IPro actually uses for a <pre>: the fixed typeface at
  two points under the document size, which is what TIpHtmlNodePRE.SetProps
  does.  Measured on the panel's own canvas rather than worked out, because
  that canvas is the one the page is laid out on, at whatever PPI the startup
  sweep left it.

  The allowances are the vertical scrollbar, which a preview of anything long
  has and which comes out of the width the layout gets, and IPro's page
  margin.  Only one margin turns up in the page width it computes -- both are
  subtracted, and the difference is the slack that keeps a rounding error
  from costing a column. }
function TLedPreviewPane.CodeColumns: Integer;
var
  CharW, Usable: Integer;
begin
  Result := 0;
  if (FHtml.ClientWidth <= 0) or not FHtml.HandleAllocated then Exit;
  FHtml.Canvas.Font.Name := FHtml.FixedTypeface;
  FHtml.Canvas.Font.Size := FHtml.DefaultFontSize - 2;
  { Over twenty characters, because a single one rounds badly. }
  CharW := FHtml.Canvas.TextWidth(StringOfChar('0', 20)) div 20;
  if CharW < 1 then Exit;
  Usable := FHtml.ClientWidth - 2 * FHtml.MarginWidth -
            GetSystemMetrics(SM_CXVSCROLL);
  Result := Usable div CharW;
  { Narrower than this and the wrapping is worse than the overflow it is
    there to prevent. }
  if Result < 16 then Result := 16;
end;

{ --- the line mapping ------------------------------------------------------

  The page carries the source line of every block it was made from, as
  id="L<n>" (see LedMarkdownToHTML).  Those ids are the whole mapping: one
  way through MakeAnchorVisible, which IPro resolves against element ids as
  well as anchors, and the other by reading the id off the block under the
  mouse.  Nothing here needs a document model, and nothing here is finer than
  a block -- which is as far as a preview can honestly point. }

{ The lines the page carries, in the order they appear, which for a document
  is ascending.  Read back off the finished page rather than kept by the
  converter: that keeps the converter a string-to-string function, and the
  scan costs a millisecond on a page that takes half a second to lay out. }
procedure TLedPreviewPane.CollectLineIds(const APage: string);
const
  Marker = ' id="L';
var
  P, Q, N, Count_: Integer;
begin
  SetLength(FLineIds, 0);
  Count_ := 0;
  P := Pos(Marker, APage);
  while P > 0 do
  begin
    Q := P + Length(Marker);
    N := 0;
    while (Q <= Length(APage)) and (APage[Q] in ['0'..'9']) do
    begin
      N := N * 10 + (Ord(APage[Q]) - Ord('0'));
      Inc(Q);
    end;
    { Strictly rising, so the array can be searched rather than scanned.  An
      id out of order would be a converter bug; dropping it here is better
      than a binary search that quietly lies. }
    if (N > 0) and ((Count_ = 0) or (N > FLineIds[Count_ - 1])) then
    begin
      if Count_ = Length(FLineIds) then
        SetLength(FLineIds, Count_ * 2 + 32);
      FLineIds[Count_] := N;
      Inc(Count_);
    end;
    P := PosEx(Marker, APage, Q);
  end;
  SetLength(FLineIds, Count_);
end;

{ The last block at or before ALine -- the block that line is inside.  Before
  the first block, the first block: scrolling a title page to nothing would
  look like a preview that had stopped following. }
function TLedPreviewPane.NearestLineId(ALine: Integer): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Result := 0;
  if Length(FLineIds) = 0 then Exit;
  if ALine <= FLineIds[0] then Exit(FLineIds[0]);
  Lo := 0;
  Hi := High(FLineIds);
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if FLineIds[Mid] <= ALine then Lo := Mid else Hi := Mid - 1;
  end;
  Result := FLineIds[Lo];
end;

function TLedPreviewPane.ScrollToLine(ALine: Integer): Boolean;
var
  N: Integer;
begin
  Result := False;
  if (not FHasRendered) or (not FHtml.Visible) then Exit;
  N := NearestLineId(ALine);
  if N = 0 then Exit;
  Result := True;
  { Already showing that block.  Worth the check: this runs on every line the
    text view scrolls past, and each move repaints the page. }
  if N = FSyncedLine then Exit;
  FSyncedLine := N;
  FHtml.MakeAnchorVisible('L' + IntToStr(N));
  { This pane moved the page, so the next look must not read it as the
    reader having moved it. }
  FLastScroll := FHtml.VScrollPos;
end;

{ The source line of the block under the mouse.  IPro keeps the element the
  pointer last moved over; the line is on the block that element belongs to,
  so this walks out of the text and up to the first ancestor that carries one
  -- a word in a paragraph reports the paragraph. }
function TLedPreviewPane.LineUnderCursor: Integer;
var
  Node: TIpHtmlNode;
  Id: string;
begin
  Result := 0;
  if FHtml.CurElement = nil then Exit;
  Node := FHtml.CurElement^.Owner;
  while Node <> nil do
  begin
    if Node is TIpHtmlNodeCore then
    begin
      Id := TIpHtmlNodeCore(Node).Id;
      if (Length(Id) > 1) and (Id[1] = 'L') then
      begin
        Result := StrToIntDef(Copy(Id, 2, MaxInt), 0);
        if Result > 0 then Exit;
      end;
    end;
    Node := Node.ParentNode;
  end;
end;

{ Where each of the page's blocks sits, for answering which line is at the
  top of it.

  Only the blocks that report a position, which in practice means the
  headings: a paragraph's node reports none.  That makes the answer a
  section rather than a line, which is the granularity a reader scrolling a
  preview is working in anyway -- and it is the same granularity the
  notebook pane syncs at, for the same reason.

  Built once per rendered page and thrown away when the page changes: the
  positions are only true of the layout they were read from. }
procedure TLedPreviewPane.BuildTops;
var
  i, n, Y: Integer;
  Html: TIpHtml;
  Node: TIpHtmlNode;
begin
  SetLength(FTopY, 0);
  SetLength(FTopLine, 0);
  FTopsFor := -1;
  if (not FHasRendered) or (FHtml.MasterFrame = nil) then Exit;
  Html := FHtml.MasterFrame.Html;
  if Html = nil then Exit;
  { The layout has to exist before anything can be asked where it is. }
  FHtml.GetContentSize;

  n := 0;
  for i := 0 to High(FLineIds) do
  begin
    Node := TLedIpHtmlReach(Html).FindId('L' + IntToStr(FLineIds[i]));
    if Node = nil then Continue;
    if not (Node is TIpHtmlNodeCore) then Continue;
    Y := TLedIpNodeReach(Node).PageTop;
    if Y < 0 then Continue;
    { Rising, and one entry per position: two blocks at the same place are
      one answer, and the first of them is the one a reader means. }
    if (n > 0) and (Y <= FTopY[n - 1]) then Continue;
    SetLength(FTopY, n + 1);
    SetLength(FTopLine, n + 1);
    FTopY[n] := Y;
    FTopLine[n] := FLineIds[i];
    Inc(n);
  end;
  FTopsFor := FHtml.GetContentSize.cy;
end;

function TLedPreviewPane.LineAtTop(AY: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  if Length(FTopY) = 0 then Exit;
  { The last block that starts at, above, or just below the top of the view.

    "Just below" matters and is not slack for its own sake: scrolling to a
    block does not put its first pixel exactly at the top -- the renderer
    stops a few pixels short -- so without it the answer is the block
    before the one the reader is looking at. }
  for i := 0 to High(FTopY) do
    if FTopY[i] <= AY + LedScale96(12) then
      Result := FTopLine[i]
    else
      Break;
  { Above the first block, the first block is the answer. }
  if Result = 0 then Result := FTopLine[0];
end;

{ Has the reader scrolled the page?  Asked rather than waited for: see
  OnScrolledToLine. }
procedure TLedPreviewPane.ScrollTick(Sender: TObject);
var
  Now_, Line: Integer;
begin
  if (not FHasRendered) or (not FHtml.Visible) or (not Showing) then Exit;
  if not Assigned(FOnScrolled) then Exit;
  Now_ := FHtml.VScrollPos;
  if Now_ = FLastScroll then Exit;
  FLastScroll := Now_;

  if (FTopsFor < 0) or (FTopsFor <> FHtml.GetContentSize.cy) then BuildTops;
  Line := LineAtTop(Now_);
  if (Line <= 0) or (Line = FSyncedLine) then Exit;
  { Remembered as synced, so that the text view moving in answer to this
    does not come straight back as a request to scroll the page again. }
  FSyncedLine := Line;
  FOnScrolled(Self, Line);
end;

function TLedPreviewPane.ScrollPos: Integer;
begin
  Result := FHtml.VScrollPos;
end;

function TLedPreviewPane.PageHasElement(const AId: string): Boolean;
var
  Html: TIpHtml;
begin
  Result := False;
  if (not FHasRendered) or (FHtml.MasterFrame = nil) then Exit;
  Html := FHtml.MasterFrame.Html;
  if Html = nil then Exit;
  Result := TLedIpHtmlReach(Html).FindId(AId) <> nil;
end;

function TLedPreviewPane.LastLineShown: Integer;
begin
  if Length(FLineIds) = 0 then
    Result := 0
  else
    Result := FLineIds[High(FLineIds)];
end;

function TLedPreviewPane.LineAtTopOfPage: Integer;
begin
  Result := 0;
  if not FHasRendered then Exit;
  if (FTopsFor < 0) or (FTopsFor <> FHtml.GetContentSize.cy) then BuildTops;
  Result := LineAtTop(FHtml.VScrollPos);
end;

procedure TLedPreviewPane.AssumeSynced(ALine: Integer);
var
  N: Integer;
begin
  N := NearestLineId(ALine);
  if N > 0 then FSyncedLine := N;
end;

procedure TLedPreviewPane.HtmlClicked(Sender: TObject);
var
  L: Integer;
begin
  if not Assigned(FOnJumpToLine) then Exit;
  L := LineUnderCursor;
  if L <= 0 then Exit;
  { The caller is responsible for keeping the page still across the jump --
    see AssumeSynced.  Recording the clicked block here instead was not
    enough: the request that comes back carries the view's top line, not the
    line that was clicked, and those are the same block only when the click
    happened to be at the top of the text view. }
  FOnJumpToLine(Self, L);
end;

{ The typeface <pre> and <code> are set in: the editor's own.

  IPro defaults to 'Courier New', which is not installed on a Linux desktop,
  so the code blocks in a preview were rendered in whatever the toolkit
  substituted -- often a proportional face, which is the one thing a code
  block must not be.  Taking the editor's font means a fenced block looks
  like the file it was copied from, and with no preference set that is the
  Fira Code LED ships.

  Re-read on every render rather than fixed at construction, so changing the
  font in Preferences shows up without restarting. }
function TLedPreviewPane.FixedFace: string;
begin
  Result := FHtml.FixedTypeface;
end;

procedure TLedPreviewPane.ApplyFixedFont;
var
  Face: string;
  Size: Integer;
begin
  LedParseFontSpec(LedPrefs.GetStr('Editor/font', ''), Face, Size);
  if Face <> '' then FHtml.FixedTypeface := Face;
end;

{ Where this document's pictures come from, and the three answers the
  renderer wants about them: Led.UI.Pictures has all of it, and the notebook
  pane asks it the same three questions.  Nothing embedded is offered -- a
  Markdown file has no attachments -- so a data: URI is the only picture in
  the document itself, and Led.Core.NBImage reads those. }
function TLedPreviewPane.Pictures: TLedPictureSource;
begin
  if FPicSrc = nil then FPicSrc := TLedPictureSource.Create;
  FPicSrc.BaseDir := FBaseDir;
  { The page's own width, so a picture wider than the pane is scaled once on
    the way in rather than by the renderer on every paint. }
  FPicSrc.FitWidth := FHtml.ClientWidth - LedScale96(32);
  Result := FPicSrc;
end;

function TLedPreviewPane.HaveRemote(const AURL: string;
  out AWhy: string): Boolean;
var
  Fetching: Boolean;
begin
  Result := Pictures.Have(AURL, AWhy, Fetching);
  { Asking started a fetch, so start looking for the answer.  What to do
    when one arrives is this pane's own business: lay the page out again. }
  if Fetching then FImageTimer.Enabled := True;
end;

function TLedPreviewPane.ImageSize(const AURL: string;
  out AW, AH: Integer): Boolean;
begin
  Result := Pictures.SizeOf_(AURL, AW, AH);
end;

procedure TLedPreviewPane.ProvideImage(Sender: TIpHtmlNode; const URL: string;
  var Picture: TPicture);
begin
  Picture := Pictures.Provide(URL);
end;

procedure TLedPreviewPane.ImageTick(Sender: TObject);
var
  URL: string;
  Again: Boolean;
begin
  Again := False;
  { The whole queue is read before anything is drawn, so a page with three
    pictures on it is laid out once rather than three times. }
  while LedNBImages.TakeArrived(URL) do
    if Pos(URL, FRenderedText) > 0 then Again := True;
  if Again then Restyle;
  FImageTimer.Enabled := LedNBImages.Pending > 0;
end;

procedure TLedPreviewPane.Restyle;
begin
  { The page is the same text at the same width, which is exactly what the
    render path is entitled to skip; this says to draw it anyway. }
  FPendingRender := True;
  if FHasRendered and Showing then Render(nil);
end;

procedure TLedPreviewPane.Render(Sender: TObject);
var
  Page: string;
  Colours: TLedPageColours;
  Body, Shown: string;
  Cut: Boolean;
begin
  FTimer.Enabled := False;
  { Re-read now rather than only at construction, so a font changed in
    Preferences shows in the next preview without a restart. }
  ApplyFixedFont;

  { Laying a page out costs more than everything else the pane does put
    together -- half a second for a README -- so it is worth some care about
    not doing it twice.

    Before the window is on screen the pane has whatever width the form was
    designed at, not the one it is about to be given: the files named on the
    command line are opened there, and a page laid out then is laid out for a
    pane 170 pixels wide and thrown away a moment later.  It waits for the
    size instead -- asked of the pane, not of the HTML control, which is
    hidden until there is a page in it and so is never showing. }
  if not Showing then
  begin
    FPendingRender := True;
    Exit;
  end;

  { And the same document at the same width is the same page.  Opening a file
    asks for the preview from more than one direction -- the tab change, the
    command line, the pane appearing -- and each of them is right to ask. }
  if FHasRendered and (not FPendingRender) and
     (FHtml.ClientWidth = FRenderedWidth) and (FIsWiki = FRenderedWiki) and
     (FPendingTitle = FRenderedTitle) and (FPendingText = FRenderedText) then
  begin
    FHtml.Visible := True;
    Exit;
  end;

  { The body only: the page around it is built in the theme's colours rather
    than in the fixed light-grey wrapper LedMarkdownToPage carries, which was
    written before LED had themes. }
  Colours := LedPageColours;
  Shown := LedPreviewCut(FPendingText,
    LedPrefs.GetInt(LedPrefPreviewMaxKB, 16) * 1024, Cut);
  if FIsWiki then
    Body := LedWikiToHTML(Shown, True)
  else
    Body := LedMarkdownToHTML(Shown, True);
  if Cut then Body := Body + TruncationNote(Length(Shown),
    Length(FPendingText));
  { A picture on somebody's server cannot be drawn while the page is being
    laid out -- see Led.Core.NBFetch -- so one that is not in hand yet is
    replaced by a line saying so, and the page is drawn again when it lands. }
  Body := LedNBHideRemoteImages(Body, @HaveRemote);
  { A picture wider than the pane is given a size that fits: this renderer
    draws one at its natural size and cannot scroll a block sideways, so the
    right-hand side of a wide screenshot was simply not there. }
  Body := LedNBFitImages(Body, FHtml.ClientWidth - LedScale96(32),
    @ImageSize);
  Page := LedPageHead(FPendingTitle, Colours, 12) + Body + LedPageTail;
  try
    { Both adjustments are for the renderer rather than for the document:
      see LedWrapPreLines and LedSplitInlineRuns. }
    Page := LedSplitInlineRuns(LedWrapPreLines(Page, CodeColumns));
    { The same treatment the notebook's cells get, and for the same reasons:
      the renderer draws in its own colours unless told otherwise, so a page
      on a dark theme was black text on a black background with its tables
      worse still, and a fenced block that named its language went
      uncoloured though LED has the highlighter for it. }
    Page := LedPageColourCode(Page, Colours.Text, Colours.CodeBg);
    FHtml.BgColor := Colours.Page;
    FHtml.TextColor := Colours.Text;
    FHtml.LinkColor := Colours.Link;
    FHtml.VLinkColor := Colours.Link;
    FHtml.ALinkColor := Colours.Link;
    FHtml.SetHtmlFromStr(Page);
    { From the page as it was handed over: neither adjustment touches an id,
      but this is the string the control is actually holding. }
    CollectLineIds(Page);
    { The positions of the old page are not the positions of this one. }
    FTopsFor := -1;
    FLastScroll := FHtml.VScrollPos;
    FSyncedLine := 0;
    FRenderedWidth := FHtml.ClientWidth;
    FRenderedText := FPendingText;
    FRenderedTitle := FPendingTitle;
    FRenderedWiki := FIsWiki;
    FPendingRender := False;
    FNote.Visible := False;
    FHtml.Visible := True;
    FHasRendered := True;
  except
    on E: Exception do
      ShowMessage_('The preview could not be rendered: ' + E.Message);
  end;
end;

function TLedPreviewPane.RenderNow: Boolean;
begin
  FTimer.Enabled := False;
  Render(nil);
  Result := FHtml.Visible and not FNote.Visible;
end;

end.
