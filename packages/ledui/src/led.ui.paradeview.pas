{ LED - a lightweight editor.  The Markdown preview laid out by Parade.

  The preview pane renders with TIpHtmlPanel, whose cost is not linear in
  the size of the page: measured on this machine, at a 700 pixel pane, a
  36 KB README is 213 ms and a 110 KB document 997 ms, and because IPro
  will not reflow a page it is already holding, a pane dragged to a new
  width pays that again for every step of the drag -- ten steps of the
  110 KB document is 9.9 seconds.  That is what LedPrefPreviewMaxKB is a
  ceiling on.

  Parade lays the same documents out in 56 ms and 20 ms a reflow, and it
  is already incremental: one typed character re-breaks one paragraph of
  2,628.  So this is the same preview with the other engine under it --
  one page as wide as the pane and as tall as it needs to be, reflowed
  when the pane changes width, read only.

  It is fed LED's own HTML rather than Parade's Markdown reader, through
  PD_CONV_HTML, so the document is read by Led.Core.Markdown and the
  dialect it implements is the one the reader sees either way.  Measured
  the same: 19 ms against 20 for the 110 KB document.

  What is not here yet, and is Parade's side rather than LED's:

    - The paper is white whatever the theme says, because the colour is
      written into TParadeEdit.PaintPage, and the gap and frame between
      two pages show where a web page would show nothing (FPageGap and
      the two FillRectImg colours).

    - A press costs what the page holds.  TParadeEdit.MouseDown asks
      ClickPage whether the point is on a drawing, and DrawingAt walks
      every drawn item of the page and resolves each one's placement:
      on this README at a 800 pixel pane one press took 920 ms with the
      document on one page, 37 ms at 4,000 pt a page and 4 ms at 1,500.
      That is why the page is cut to an item budget below, which is a
      workaround and not the fix -- whether a point is on a drawing
      should not depend on how much text shares the page with it.

  Both belong in the Parade tree, not in a copy of it here. }
unit Led.UI.ParadeView;

{$mode objfpc}{$H+}
{$I led.parade.inc}

interface

{$IFDEF LED_PARADE}
uses
  Classes, SysUtils, Controls, Graphics, Math, ctypes,
  parade, paradeedit,
  Led.Core.StrBuf, Led.UI.Pictures, Led.UI.ParadeFonts;

type
  { A click in the page, with the source line of the block it landed in. }
  TLedParadeLineEvent = procedure(Sender: TObject; ALine: Integer) of object;

  { A place in the page that a source line reaches: the bookmark LED wrote
    into the HTML, as the document now holds it. }
  TLedParadeAnchor = record
    Line: Integer;
    Pos: pd_pos;
  end;

  TLedParadeView = class(TParadeEdit)
  private
    FPics: TLedPictureSource;
    FAnchors: array of TLedParadeAnchor;
    FWantPt: Double;          { the size the reader asked for }
    FWantFace: string;        { and the face, from Preferences }
    FLayouts: Integer;        { MEASURE }
    FDownAt: TPoint;          { where the button went down }
    FDownOn: Boolean;         { and whether it is still down }
    FDragged: Boolean;        { it moved far enough to be a drag, not a click }
    FOnClickedLine: TLedParadeLineEvent;
    FBodyPt: Double;          { the size the document's own body came in at }
    FLaidOutFor: Integer;     { the pane width the page was last laid out for }
    procedure CollectAnchors;
    { A blank line between paragraphs.  The page asks for one in its style
      sheet, which the HTML reader does not read, so the document's own
      body style is given the space instead -- without it a preview is a
      wall of text where IPro's is a column of paragraphs. }
    procedure SpaceParagraphs;
    { The reader's prose face, applied to the document's body style.  The
      page names no family on purpose -- IPro takes the face from the
      control rather than from the HTML -- so this is where the setting
      reaches a Parade page.  A family a page does name, and the
      monospace of a code span, still win: they are written on the runs
      and the style is underneath them. }
    procedure UseProseFace;
    { The registered family that best answers the name the reader gave,
      or '' for none: resolution is by name, so Sans has to become a
      family that is actually there. }
    function FaceNamed(const AWanted: string): string;
    function BodyPointSize: Double;
    { How wide the page may be drawn, in pixels.  Asked of the control
      rather than worked out, because the room a page gets is the client
      area less the scroll bar and the gap around the page, and both of
      those are the control's own private business: PageWidthZoom is the
      zoom at which the page it is holding would fill that room, so the
      room is that zoom times the width it is holding. }
    function RoomForPage: Integer;
    procedure LayOutForWidth;
    { The client y of a place in the document, or MaxInt when the layout
      cannot say where it is. }
    function ClientYOf(const APos: pd_pos): Integer;
    { Where the text on the last page ends, in points from the top of
      that page, or 0 when the layout cannot say.  A page as tall as the
      ceiling is a page with a mile of blank paper under the end of the
      document, so the page is cut down to this. }
    function ContentBottom: Double;
    function LineAtY(AY: Integer): Integer;
  protected
    { A click in the page is the reader pointing at a block, and a drag is
      the reader selecting text -- which must not be reported, because
      what the pane does with a reported line is scroll the text view and
      take the focus, and doing that on every mouse move during a drag is
      a loop: the scroll comes back as a request to sync the page, which
      moves the caret, which looks like another click.  That loop is what
      hung the pane.  So the line is reported from the button coming up,
      and only where it did not travel. }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure DblClick; override;      { MEASURE }
  public
    constructor Create(AOwner: TComponent); override;

    { Shows AHtml -- a whole page, as LedPageHead and LedMarkdownToHTML
      write it -- with ABaseDir the folder relative picture names are
      resolved against, and APictures the pane's own picture source for
      everything Parade cannot fetch itself: an SVG, a data: URI, a
      picture on the web that has already been fetched. }
    procedure ShowHtml(const AHtml, ABaseDir: string;
      APictures: TLedPictureSource);

    { The prose face and size the reader chose in Preferences (View,
      "Notebook and preview text font").  The size is applied as a zoom,
      because the size the document carries is the HTML's and the
      reader's choice is about all of its text at once; the face is
      applied to the body style. }
    procedure SetProseFont(const AFace: string; APoints: Integer);

    { Lays the page out again if the pane is no longer the width it was
      laid out for, and says whether it did. }
    function Reflow: Boolean;

    { Puts the block that source line ALine belongs to on screen; False
      when the page carries no such place. }
    function ScrollToLine(ALine: Integer): Boolean;
    { The source line of the block at the top of the view, 0 for none. }
    function LineAtTop: Integer;
    { The source line of the block the caret is in -- where a click just
      put it. }
    function LineAtCaret: Integer;
    { Where the view is scrolled to, in pixels from the top of the page.
      For a check: a view that stayed put and one that was scrolled back
      look alike from outside otherwise. }
    function ScrollTop: Integer;
    { The last source line the page carries, 0 for an empty page. }
    function LastLine: Integer;
    { How many places in the page a source line can be scrolled to. }
    function AnchorCount: Integer;
    { Blank paper under the end of the document, in pixels.  For a
      check: a page is as tall as it is told to be, and a page told to
      be taller than the text is a preview that scrolls on into
      nothing. }
    function PaperUnderText: Integer;
    { MEASURE }
    function Layouts: Integer;
    { Whether the reader has the button down in the page: nothing that
      moves the view may happen while they do. }
    property Dragging: Boolean read FDownOn;
    { A click, with the line of the block it landed in. }
    property OnClickedLine: TLedParadeLineEvent
      read FOnClickedLine write FOnClickedLine;
  end;

{ LED writes the source line of every block into the page as id="L<n>".
  Parade's HTML reader keeps an <a name> or an <a id> as a bookmark and
  drops the id of a block, so this writes the one it keeps beside the one
  it does not -- which leaves the page that IPro is given unchanged. }
function LedParadeAnchors(const AHtml: string): string;
{$ENDIF}

implementation

{$IFDEF LED_PARADE}

uses
  StrUtils;

const
  { What Parade draws a point as, which is TParadeEdit's own SCREEN_PPI --
    a constant in its implementation, so it is written out again here. }
  ScreenPPI = 96.0;
  { The page the document is first laid out on, before it is cut down to
    what the content actually used.  A page is measured in pd_sp, a
    32-bit count of 1/65536 point, so 32,767 pt is the ceiling and this
    is comfortably under it: about 1,400 lines of body text, so an
    ordinary README is one page and shows no seam at all. }
  PageTallPt = 20000.0;
  { How many drawn items a page may hold before it is split into more
    pages.  Nothing about the layout wants this -- laying out and
    painting a tall page are both cheap, and the whole point of the page
    being tall is that a document is one page with no seam in it.  It is
    what a press costs: TParadeEdit.MouseDown asks ClickPage whether the
    point is on a drawing, and that walks every item of the page and
    resolves each one's placement.  Measured on this README at a 800
    pixel pane, one press: a 20,000 pt page (2 pages, ~30,000 items)
    takes 920 ms, 4,000 pt 37 ms, 1,500 pt 4 ms.  So the page is cut to
    about this many items, which keeps a press under about ten
    milliseconds and still leaves an ordinary page or two rather than
    forty.

    The real fix is in Parade -- a point is on a drawing or it is not,
    and answering that should not depend on how much text shares the
    page -- and when it lands this can go and the page can be as tall as
    the document. }
  PageItemBudget = 4000;
  { The gap after a paragraph, in points: a blank line, near enough. }
  PageSpacePt = 6.0;
  { Room between the text and the edge of the page.  Small: the pane is
    narrow and the gap the control leaves around the page is already
    there. }
  PageMarginPt = 6.0;

function LedParadeAnchors(const AHtml: string): string;
const
  Marker = ' id="L';
var
  Buf: TLedStrBuf;
  P, Q, Gt, N: Integer;
  Line: string;
begin
  { Built in a buffer rather than by appending to a string: a page carries
    one id per block, which on a long document is thousands of them, and
    an append that copies what it has already built turns a pass over the
    page into a pass over the page squared. }
  Buf.Init(Length(AHtml) + Length(AHtml) div 8);
  P := 1;
  Q := Pos(Marker, AHtml);
  while Q > 0 do
  begin
    { the digits of the id, and the end of the tag they are in }
    N := Q + Length(Marker);
    Line := '';
    while (N <= Length(AHtml)) and (AHtml[N] in ['0'..'9']) do
    begin
      Line := Line + AHtml[N];
      Inc(N);
    end;
    Gt := PosEx('>', AHtml, N);
    if (Line = '') or (Gt = 0) then
    begin
      { not an id of ours, or a tag that never ends: leave it alone }
      Buf.AddSlice(AHtml, P, N - P);
      P := N;
    end
    else
    begin
      Buf.AddSlice(AHtml, P, Gt - P + 1);
      Buf.Add('<a name="L' + Line + '"></a>');
      P := Gt + 1;
    end;
    Q := PosEx(Marker, AHtml, P);
  end;
  Buf.AddSlice(AHtml, P, Length(AHtml) - P + 1);
  Result := Buf.Text;
end;

{ A picture Parade could not fetch for itself, from the pane's own source:
  an SVG converted, a picture on the web that has already arrived, a data:
  URI.  Handed over as PNG because that is what both sides can read, and
  already scaled to the pane (TLedPictureSource.FitWidth), so a three
  thousand pixel screenshot does not arrive as a three thousand pixel
  picture.

  A C callback: nothing may escape it. }
function FetchPicture(user: Pointer; address: PAnsiChar; write: pd_writer;
  sink: Pointer): cint; cdecl;
var
  View: TLedParadeView;
  Pic: TPicture;
  Png: TPortableNetworkGraphic;
  Ms: TMemoryStream;
begin
  Result := 1;
  try
    View := TLedParadeView(user);
    if (View = nil) or (View.FPics = nil) then Exit;
    Pic := View.FPics.Provide(StrPas(address));
    if Pic = nil then Exit;
    try
      if Pic.Graphic = nil then Exit;
      Png := TPortableNetworkGraphic.Create;
      Ms := TMemoryStream.Create;
      try
        Png.Assign(Pic.Graphic);
        Png.SaveToStream(Ms);
        if Ms.Size > 0 then
          Result := write(sink, Ms.Memory, Ms.Size);
      finally
        Ms.Free;
        Png.Free;
      end;
    finally
      Pic.Free;
    end;
  except
    Result := 1;
  end;
end;

constructor TLedParadeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ReadOnly := True;
  { The page is white (PaintPage draws it so), and the control's own
    background is what shows around it: the same white, so that what the
    reader sees is one sheet rather than a page on a desk. }
  Color := clWhite;
  FWantPt := 0;
  FBodyPt := 0;
  FLaidOutFor := -1;
  LedParadeAddFonts(Self);
end;

{ The size the document's own body text is in, read off the first
  paragraph: the zoom is worked out from it, so it has to be what the
  document says rather than what the HTML writer is assumed to have said. }
function TLedParadeView.BodyPointSize: Double;
var
  Root, Para: pd_block_id;
  Info: pd_block_info;
  Cp: pd_char_props;
  Runs: array of pd_run;
  N: Int32;
begin
  Result := 0;
  if Doc = nil then Exit;
  Root := pd_doc_child(Doc, pd_doc_root(Doc), 0);
  Para := Root;
  while (Para <> 0) and (pd_doc_block_info(Doc, Para, Info) = PD_OK) and
        (Info.kind <> PD_BLOCK_PARAGRAPH) do
    Para := pd_doc_child(Doc, Para, 0);
  { past the title, which is a heading and larger than the body }
  while (Para <> 0) and (pd_doc_block_info(Doc, Para, Info) = PD_OK) and
        (Info.role = PD_ROLE_HEADING) do
    Para := pd_doc_next_paragraph(Doc, Para);
  if Para = 0 then Exit;
  { Resolved through one of the paragraph's own runs: a format has to be
    one the paragraph carries, and PD_FORMAT_INHERIT is not one of them --
    passing it walks off the end of the format table. }
  pd_doc_para_runs(Doc, Para, nil, 0, N);
  if N <= 0 then Exit;
  SetLength(Runs, N);
  pd_doc_para_runs(Doc, Para, @Runs[0], N, N);
  if pd_doc_format_resolve(Doc, Para, Runs[0].format, Cp) <> PD_OK then Exit;
  if Cp.size > 0 then Result := Cp.size / PD_SP_PER_PT;
end;

procedure TLedParadeView.SpaceParagraphs;
var
  Style: pd_style_id;
  Pp: pd_para_props;
  Cp: pd_char_props;
  Kind: Int32;
  Based: UInt32;        { the style this one is based on }
  Para: pd_block_id;
  Info: pd_block_info;
  Own: pd_para_props;
begin
  if Doc = nil then Exit;
  Style := pd_doc_style_find(Doc, 'Normal');
  if Style = 0 then Exit;
  FillChar(Pp, SizeOf(Pp), 0);
  FillChar(Cp, SizeOf(Cp), 0);
  if pd_doc_style_info(Doc, Style, @Kind, @Based, @Pp, @Cp) <> PD_OK then Exit;
  { Whatever the document already says about it is left alone: a .docx
    opened in the visual editor has its own spacing and this view is not
    the place to argue with it. }
  if ((Pp.mask and PD_PP_SPACE_AFTER) <> 0) and (Pp.space_after > 0) then Exit;
  Pp.mask := Pp.mask or PD_PP_SPACE_AFTER;
  Pp.space_after := Round(PageSpacePt * PD_SP_PER_PT);
  pd_doc_style_define(Doc, 'Normal', PD_STYLE_PARAGRAPH, Based, @Pp, @Cp, nil);

  { Not between the items of a list, though: a gap belongs between one
    thing and the next thing, and the items of a list are one thing.  The
    style is the whole document's, so the items say otherwise themselves. }
  Para := pd_doc_child(Doc, pd_doc_root(Doc), 0);
  while (Para <> 0) and (pd_doc_block_info(Doc, Para, Info) = PD_OK) and
        (Info.kind <> PD_BLOCK_PARAGRAPH) do
    Para := pd_doc_child(Doc, Para, 0);
  while Para <> 0 do
  begin
    if (pd_doc_block_info(Doc, Para, Info) = PD_OK) and (Info.list <> 0) and
       (pd_doc_para_props(Doc, Para, Own) = PD_OK) then
    begin
      Own.mask := Own.mask or PD_PP_SPACE_AFTER;
      Own.space_after := 0;
      pd_doc_set_para_props(Doc, Para, Own);
    end;
    Para := pd_doc_next_paragraph(Doc, Para);
  end;
end;

procedure TLedParadeView.CollectAnchors;
var
  Root, Para: pd_block_id;
  Info: pd_block_info;
  O: pd_inline;
  P: pd_pos;
  N, I, Line: Integer;
  Name_: string;
begin
  SetLength(FAnchors, 0);
  N := 0;
  if Doc = nil then Exit;
  Para := pd_doc_child(Doc, pd_doc_root(Doc), 0);
  while (Para <> 0) and (pd_doc_block_info(Doc, Para, Info) = PD_OK) and
        (Info.kind <> PD_BLOCK_PARAGRAPH) do
  begin
    Root := Para;
    Para := pd_doc_child(Doc, Root, 0);
  end;
  while Para <> 0 do
  begin
    { The bookmark is written at the head of the block, so this looks
      there and not through the whole of it: a scan of every offset of
      every paragraph would be a million calls into the layout for a
      megabyte of text. }
    for I := 0 to 2 do
    begin
      P.block := Para;
      P.offset := I;
      if pd_doc_inline_at(Doc, P, O) <> PD_OK then Continue;
      if O.kind <> PD_INLINE_BOOKMARK then Continue;
      Name_ := StrPas(@O.name[0]);
      if (Length(Name_) < 2) or (Name_[1] <> 'L') then Continue;
      Line := StrToIntDef(Copy(Name_, 2, MaxInt), 0);
      if Line <= 0 then Continue;
      { rising, so the search below can be a binary one }
      if (N > 0) and (Line <= FAnchors[N - 1].Line) then Continue;
      if N = Length(FAnchors) then SetLength(FAnchors, N * 2 + 32);
      FAnchors[N].Line := Line;
      FAnchors[N].Pos := P;
      Inc(N);
      Break;
    end;
    Para := pd_doc_next_paragraph(Doc, Para);
  end;
  SetLength(FAnchors, N);
end;

function TLedParadeView.RoomForPage: Integer;
var
  Info: pd_page_info;
begin
  Result := 0;
  if (Layout = nil) or (PageCount = 0) then Exit;
  if pd_layout_page_info(Layout, 0, Info) <> PD_OK then Exit;
  Result := Round(PageWidthZoom * (Info.width / PD_SP_PER_PT) *
    ScreenPPI / 72.0);
end;

procedure TLedParadeView.LayOutForWidth;
var
  Room: Integer;
  WidthPt, Bottom, TallPt, Whole: Double;
  Items, Pages: Int32;
  Was: Boolean;
begin
  TallPt := PageTallPt;
  if Doc = nil then Exit;
  if (FWantPt > 0) and (FBodyPt > 0) then
    Zoom := FWantPt / FBodyPt;
  Room := RoomForPage;
  if Room <= 0 then Exit;
  { The page is drawn at Zoom, so the width it is given in points is the
    room it has in pixels taken back through the zoom. }
  WidthPt := Room / (Zoom * ScreenPPI / 72.0);
  if WidthPt < 4 * PageMarginPt then Exit;
  { Page setup is an edit, and TParadeEdit refuses an edit while it is read
    only -- so a read-only view would quietly keep the US Letter page the
    HTML reader gave it and clip the text at the right of the pane.  This
    edit is the pane's own and not the reader's, so it is made with the
    lock briefly off and the document is not marked as changed by it. }
  Inc(FLayouts);
  Was := ReadOnly;
  ReadOnly := False;
  try
    SetMargins(PageMarginPt, PageMarginPt, PageMarginPt, PageMarginPt);
    SetPageSize(WidthPt, TallPt);
    { Down to what a press can afford, when the page came out dense:
      see PageItemBudget. }
    if PageCount > 0 then
    begin
      Items := 0;
      if pd_layout_page_items(Layout, 0, nil, 0, Items) <> PD_OK then
        Items := 0;
      if Items > PageItemBudget then
      begin
        TallPt := TallPt * PageItemBudget / Items;
        if TallPt < 400 then TallPt := 400;
        SetPageSize(WidthPt, TallPt);
      end;
    end;
    { and then down to the text, so the page ends where the document
      does rather than a mile of blank paper below it.

      Every page of a section is the same height, so the last one cannot
      simply be cut: instead the height is the text divided by however
      many pages it needs, which lands the end of the document on the
      end of the last page.  A line that moves as the pages change can
      spill over into one more; that is one page of slack and not a
      mile, and taking the first height back is worse than living with
      it. }
    for Pages := 1 to 3 do
    begin
      Bottom := ContentBottom;
      if (PageCount = 0) or (Bottom <= 0) then Break;
      { the paper left under the text on the last page }
      if TallPt - (Bottom + PageMarginPt) < 24 then Break;
      Whole := ((PageCount - 1) * TallPt + Bottom + PageMarginPt) / PageCount;
      if (Whole < 4 * PageMarginPt) or (Abs(Whole - TallPt) < 1) then Break;
      TallPt := Whole;
      SetPageSize(WidthPt, TallPt);
    end;
  finally
    ReadOnly := Was;
    Modified := False;
  end;
  FLaidOutFor := ClientWidth;
end;

procedure TLedParadeView.ShowHtml(const AHtml, ABaseDir: string;
  APictures: TLedPictureSource);
var
  S: TStringStream;
  Base: string;
begin
  FPics := APictures;
  Base := ABaseDir;
  if Base = '' then Base := GetCurrentDir;
  S := TStringStream.Create(LedParadeAnchors(AHtml));
  try
    { The name is the document's folder and a name that stands for it:
      Parade resolves the pictures a page points at against the folder of
      the file it was read from. }
    LoadFromStream(S, PD_CONV_HTML,
      IncludeTrailingPathDelimiter(Base) + 'preview.html');
  finally
    S.Free;
  end;
  { and everything it could not fetch for itself -- an SVG, a data: URI, a
    picture on the web -- from the pane's source, which has all three }
  if FPics <> nil then
    pd_doc_load_images(Doc, @FetchPicture, Self);
  UseProseFace;
  SpaceParagraphs;
  FBodyPt := BodyPointSize;
  CollectAnchors;
  FLaidOutFor := -1;
  LayOutForWidth;
end;

procedure TLedParadeView.SetProseFont(const AFace: string; APoints: Integer);
begin
  if APoints < 4 then APoints := 4;
  if (FWantPt = APoints) and (FWantFace = AFace) then Exit;
  if FWantFace <> AFace then
  begin
    FWantFace := AFace;
    if Doc <> nil then UseProseFace;
  end;
  FWantPt := APoints;
  FLaidOutFor := -1;
  if Doc <> nil then LayOutForWidth;
end;

function TLedParadeView.FaceNamed(const AWanted: string): string;
var
  List: TStringList;
  Want: string;
  i: Integer;
begin
  Result := '';
  Want := LowerCase(Trim(AWanted));
  if Want = '' then Exit;
  { The names Preferences offers for "whatever this desktop calls it" are
    not families any font file carries; LedParadeAddFonts registers the
    faces it chose under these as well, so they resolve. }
  if (Want = 'sans') or (Want = 'sans-serif') then Want := 'sans'
  else if Want = 'serif' then Want := 'serif'
  else if (Want = 'mono') or (Want = 'fixed') then Want := 'monospace';
  List := TStringList.Create;
  try
    GetFontFamilies(List);
    for i := 0 to List.Count - 1 do
      if LowerCase(List[i]) = Want then
        Exit(List[i]);
  finally
    List.Free;
  end;
end;

procedure TLedParadeView.UseProseFace;
var
  Style: pd_style_id;
  Pp: pd_para_props;
  Cp: pd_char_props;
  Kind: Int32;
  Based: UInt32;
  Face: string;
begin
  if Doc = nil then Exit;
  Face := FaceNamed(FWantFace);
  if Face = '' then Exit;
  Style := pd_doc_style_find(Doc, 'Normal');
  if Style = 0 then Exit;
  FillChar(Pp, SizeOf(Pp), 0);
  FillChar(Cp, SizeOf(Cp), 0);
  if pd_doc_style_info(Doc, Style, @Kind, @Based, @Pp, @Cp) <> PD_OK then Exit;
  Cp.mask := Cp.mask or PD_CP_FAMILY;
  StrPLCopy(Cp.family, Face, High(Cp.family));
  pd_doc_style_define(Doc, 'Normal', PD_STYLE_PARAGRAPH, Based, @Pp, @Cp, nil);
end;

function TLedParadeView.Reflow: Boolean;
begin
  Result := (Doc <> nil) and (ClientWidth > 0) and (ClientWidth <> FLaidOutFor);
  if Result then LayOutForWidth;
end;

function TLedParadeView.ContentBottom: Double;
var
  Para, Last: pd_block_id;
  Info: pd_block_info;
  P: pd_pos;
  Page: Int32;
  X, Base, Asc, Desc: pd_sp;
begin
  Result := 0;
  if (Doc = nil) or (Layout = nil) then Exit;
  { the end of the last paragraph, which is where the document stops }
  Last := 0;
  Para := pd_doc_next_paragraph(Doc, 0);
  while Para <> 0 do
  begin
    Last := Para;
    Para := pd_doc_next_paragraph(Doc, Para);
  end;
  if Last = 0 then Exit;
  if pd_doc_block_info(Doc, Last, Info) <> PD_OK then Exit;
  P.block := Last;
  P.offset := Info.text_length;
  if pd_layout_caret(Layout, P, Page, X, Base, Asc, Desc) <> PD_OK then Exit;
  Result := (Base + Desc) / PD_SP_PER_PT;
end;

function TLedParadeView.ClientYOf(const APos: pd_pos): Integer;
var
  Page: Int32;
  X, Base, Asc, Desc: pd_sp;
begin
  Result := MaxInt;
  if Layout = nil then Exit;
  if pd_layout_caret(Layout, APos, Page, X, Base, Asc, Desc) <> PD_OK then Exit;
  Result := PageToClient(Page, 0, (Base - Asc) / PD_SP_PER_PT).Y;
end;

function TLedParadeView.LineAtY(AY: Integer): Integer;
var
  I, Y: Integer;
begin
  Result := 0;
  for I := 0 to High(FAnchors) do
  begin
    Y := ClientYOf(FAnchors[I].Pos);
    if Y = MaxInt then Continue;
    { A block that starts at or above the mark is one the reader has
      reached; the last of those is the one they are looking at. }
    if Y <= AY then
      Result := FAnchors[I].Line
    else
      Break;
  end;
  if (Result = 0) and (Length(FAnchors) > 0) then Result := FAnchors[0].Line;
end;

procedure TLedParadeView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FDownOn := True;
  FDragged := False;
  FDownAt := Point(X, Y);
end;

procedure TLedParadeView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  { Far enough to be a drag: a click with a shaking hand in it is still a
    click. }
  if FDownOn and ((Abs(X - FDownAt.X) > 3) or (Abs(Y - FDownAt.Y) > 3)) then
    FDragged := True;
end;

procedure TLedParadeView.DblClick;
var
  T: QWord;
begin
  T := GetTickCount64;
  inherited DblClick;
  WriteLn('    [DblClick took ', GetTickCount64 - T, ' ms]');
  Flush(Output);
end;

procedure TLedParadeView.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Clicked: Boolean;
  Line: Integer;
  SelA, SelB: pd_pos;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  { A double click selects the word and a triple one the paragraph, and
    the second button-up of either arrives here looking exactly like a
    click.  What the pane does with a reported line is move the text
    view and take the focus, which is not what somebody selecting a word
    asked for -- so a gesture that left a selection behind reports
    nothing. }
  Clicked := FDownOn and not FDragged and not SelectionRange(SelA, SelB);
  FDownOn := False;
  if not (Clicked and Assigned(FOnClickedLine)) then Exit;
  Line := LineAtCaret;
  if Line > 0 then FOnClickedLine(Self, Line);
end;

function TLedParadeView.ScrollToLine(ALine: Integer): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Result := False;
  if Length(FAnchors) = 0 then Exit;
  Lo := 0;
  Hi := High(FAnchors);
  if ALine > FAnchors[0].Line then
    while Lo < Hi do
    begin
      Mid := (Lo + Hi + 1) div 2;
      if FAnchors[Mid].Line <= ALine then Lo := Mid else Hi := Mid - 1;
    end;
  GoToPos(FAnchors[Lo].Pos);
  Result := True;
end;

function TLedParadeView.LineAtTop: Integer;
begin
  { Slack, because scrolling to a block does not put its first pixel at
    the top of the view: TParadeEdit.GoToPos leaves it three page gaps
    down, which is 48 pixels, so a block anywhere in that band is the one
    the reader was taken to and not the one above it. }
  Result := LineAtY(56);
end;

function TLedParadeView.LineAtCaret: Integer;
var
  Y: Integer;
begin
  Result := 0;
  if Doc = nil then Exit;
  Y := ClientYOf(CaretPos);
  if Y = MaxInt then Exit;
  Result := LineAtY(Y + 1);
end;

function TLedParadeView.ScrollTop: Integer;
begin
  Result := 0;
  if (Layout = nil) or (PageCount = 0) then Exit;
  { The top of the first page, which moves up as the view scrolls down. }
  Result := -PageToClient(0, 0, 0).Y;
end;

function TLedParadeView.PaperUnderText: Integer;
var
  Info: pd_page_info;
  Para, Last: pd_block_id;
  BI: pd_block_info;
  P: pd_pos;
  Foot: Integer;
begin
  Result := 0;
  if (Doc = nil) or (Layout = nil) or (PageCount = 0) then Exit;
  if pd_layout_page_info(Layout, PageCount - 1, Info) <> PD_OK then Exit;
  Last := 0;
  Para := pd_doc_next_paragraph(Doc, 0);
  while Para <> 0 do
  begin
    Last := Para;
    Para := pd_doc_next_paragraph(Doc, Para);
  end;
  if (Last = 0) or (pd_doc_block_info(Doc, Last, BI) <> PD_OK) then Exit;
  P.block := Last;
  P.offset := BI.text_length;
  Foot := PageToClient(PageCount - 1, 0, Info.height / PD_SP_PER_PT).Y;
  Result := Foot - ClientYOf(P);
  if Result < 0 then Result := 0;
end;

function TLedParadeView.LastLine: Integer;
begin
  if Length(FAnchors) = 0 then
    Result := 0
  else
    Result := FAnchors[High(FAnchors)].Line;
end;

function TLedParadeView.Layouts: Integer;
begin
  Result := FLayouts;
end;

function TLedParadeView.AnchorCount: Integer;
begin
  Result := Length(FAnchors);
end;

{$ENDIF}

end.
