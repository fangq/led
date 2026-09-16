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
  Graphics, Forms, ImgList, LazUTF8,
  IpHtml, Ipfilebroker,
  Led.Core.NBFormat, Led.Core.NBView, Led.Core.NBImage, Led.Core.Markdown,
  Led.Syn.Factory, Led.Syn.Theme, Led.UI.Icons,
  Led.UI.Document, Led.UI.Edit, Led.UI.Dpi;

type
  TLedNBCellEvent = procedure(Sender: TObject; ACell: Integer) of object;

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

  { The colours the pane draws with; see LedNBColours. }
  TLedNBColourSet = record
    Page, Text, Muted, CodeBg, Border, Link: TColor;
  end;

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
    FEdit: TLedEdit;
    FRender: TLedNBProse;
    FProvider: TIpFileDataProvider;
    FOnRun: TLedNBCellEvent;
    FOnEdited: TLedNBCellEvent;
    FEditing: Boolean;         // a markdown cell being typed into
    procedure RunClicked(Sender: TObject);
    procedure RenderClicked(Sender: TObject);
    procedure EditClicked(Sender: TObject);
    procedure EditExited(Sender: TObject);
    procedure MakeEditor;
    procedure MakeRender;
    procedure ProvideImage(Sender: TIpHtmlNode; const URL: string;
      var Picture: TPicture);
    { The wheel, from a child that would otherwise swallow it, handed to the
      page the reader was trying to scroll. }
    procedure ChildWheel(Sender: TObject; AShift: TShiftState;
      AWheelDelta: Integer; AMousePos: TPoint; var AHandled: Boolean);
    procedure BuildOutputs(var AY: Integer; AWidth: Integer);
    function RenderedHeight(const APage: string; AWidth: Integer): Integer;
    function ProsePage(const ASource: string): string;

  public
    constructor Create(AOwner: TComponent; ADoc: TLedDocument;
      ACell: Integer; AImages: TCustomImageList); reintroduce;
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
    property Editor: TLedEdit read FEdit;
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

type
  TLedNotebookPane = class(TScrollBox)
  private
    FDoc: TLedDocument;
    FBoxes: TFPList;           // of TLedNBCellBox
    FNote: TLabel;
    FImages: TCustomImageList;
    FOnRun: TLedNBCellEvent;
    { Resizing is coalesced.  Dragging the splitter fires a resize per pixel,
      and every one of them would re-wrap every cell and re-measure every
      piece of prose; the pane waits until the dragging stops.  The preview
      pane does the same, for the same reason. }
    FResizeTimer: TTimer;
    FLaidOutFor: Integer;      // the width the boxes were laid out for
    procedure CellRun(Sender: TObject; ACell: Integer);
    procedure CellEdited(Sender: TObject; ACell: Integer);
    procedure ResizeSettled(Sender: TObject);
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Lays the boxes out again for the pane's current width: the wrapped
      height of a cell and the size a wide picture is scaled to both depend
      on it. }
    procedure Relayout;

    { Shows a document's cells, or a note saying why there are none.  Called
      when the pane is shown and when the tab changes. }
    procedure ShowDocument(ADoc: TLedDocument);
    { Builds the cells again from the notebook -- after a run, or after the
      line view has been typed into. }
    procedure Reload;
    { One cell again, which is what a run needs: its label, its output and
      its height. }
    procedure RefreshCell(ACell: Integer);

    function CellCount: Integer;
    function Box(AIndex: Integer): TLedNBCellBox;
    { The box for a cell, or nil. }
    function BoxOf(ACell: Integer): TLedNBCellBox;

    property Document: TLedDocument read FDoc;
    { Where the cells take their button icons from.  The window's own list,
      so a notebook's Run button is the same glyph as the toolbar's. }
    property Images: TCustomImageList read FImages write FImages;
    { Fired when a cell's Run button is pressed; the window runs it, because
      the kernel is the document's and the reporting is the window's. }
    property OnRunCell: TLedNBCellEvent read FOnRun write FOnRun;
  end;

implementation

const
  Pad = 6;
  LabelWidth = 76;
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

function LedNBColours: TLedNBColourSet;
var
  Style: TLedStyle;
begin
  Result.Page := clWindow;
  Result.Text := clWindowText;
  if LedCurrentTheme <> nil then
  begin
    if LedCurrentTheme.Find(LedStyleText, Style) then
    begin
      if lsfBackground in Style.Flags then
        Result.Page := LedColourToTColor(Style.Background);
      if lsfForeground in Style.Flags then
        Result.Text := LedColourToTColor(Style.Foreground);
    end;
  end;
  if Result.Page = clNone then Result.Page := clWindow;
  if Result.Text = clNone then Result.Text := clWindowText;

  { A code cell sits on a block a little away from the page, the way it does
    in a notebook front end; the label beside it recedes.

    LedMixColours takes the percentage of its *first* colour, so "mostly the
    page" is a high number.  Getting that backwards put the code block at 93
    per cent of the text colour -- a near-white slab on a dark theme -- which
    is what the check against two themes caught. }
  Result.CodeBg := LedMixColours(Result.Page, Result.Text, 93);
  Result.Border := LedMixColours(Result.Page, Result.Text, 78);
  Result.Muted := LedEnsureReadable(
    LedMixColours(Result.Text, Result.Page, 62), Result.Page, 3.0);
  { Links have to be readable on the page as well as look like links. }
  Result.Link := LedEnsureReadable($00D08040, Result.Page, 4.0);
end;

{ A colour as HTML says it.  TColor is $00BBGGRR and HTML wants RRGGBB, so
  this is not a hex dump of the number. }
function HtmlColour(AColour: TColor): string;
begin
  Result := Format('#%.2x%.2x%.2x',
    [AColour and $FF, (AColour shr 8) and $FF, (AColour shr 16) and $FF]);
end;

{ How tall a page wants to be is worked out by TIpHtml.GetPageRect, which is
  protected -- so it is reached the way LED reaches SynEdit's protected parts
  elsewhere: a descendant declared here, which may see them. }
type
  TIpHtmlMeasure = class(TIpHtml)
  public
    function PageHeightAt(ACanvas: TCanvas; AWidth: Integer): Integer;
  end;

function TIpHtmlMeasure.PageHeightAt(ACanvas: TCanvas;
  AWidth: Integer): Integer;
var
  R: TRect;
begin
  R := GetPageRect(ACanvas, AWidth, 1000000);
  Result := R.Bottom - R.Top;
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
  Box: TScrollBox;
  Notches: Integer;
begin
  if not (Parent is TScrollBox) then Exit;
  Box := TScrollBox(Parent);
  Notches := AWheelDelta div 120;
  if Notches = 0 then
    if AWheelDelta > 0 then Notches := 1 else Notches := -1;
  Box.VertScrollBar.Position :=
    Box.VertScrollBar.Position - Notches * LedScale96(48);
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
procedure TLedNBCellBox.MakeEditor;
var
  Lang: string;
begin
  if FEdit <> nil then Exit;
  FEdit := TLedEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Gutter.Visible := False;
  FEdit.RightEdge := 0;
  FEdit.ScrollBars := ssNone;
  { Wrapped, because this pane is narrow and a box with no scrollbar of its
    own would otherwise cut a long line off where nobody can see that it
    continues.  The line view is where a long line is read unwrapped. }
  FEdit.WrapEnabled := True;
  FEdit.Font.Assign(FDoc.Master.Font);
  LedApplyThemeToEditor(LedCurrentTheme, FEdit);
  { On the code block's shade rather than the page's, which is what makes a
    cell read as a cell.  After the theme, so it is not overwritten by it. }
  FEdit.Color := LedNBColours.CodeBg;

  { Coloured by the language of this cell: prose as Markdown, code as
    whatever the notebook says, and a cell magic naming its own language is
    not handled here -- the line view does that, and a box a reader is typing
    into can be told when they ask for it. }
  if FDoc.Notebook.CellKind(FCell) = nbkMarkdown then
    Lang := 'markdown'
  else
    Lang := FDoc.Notebook.LanguageName;
  FEdit.Highlighter := LedHighlighterFor(Lang);
  if FEdit.Highlighter <> nil then
    LedApplyThemeToHighlighter(LedCurrentTheme, FEdit.Highlighter);

  FEdit.OnExit := @EditExited;
  FEdit.OnMouseWheel := @ChildWheel;
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
procedure TLedNBCellBox.ProvideImage(Sender: TIpHtmlNode; const URL: string;
  var Picture: TPicture);
var
  FN, Bytes, Mime: string;
  Stream: TStringStream;
begin
  Picture := nil;
  if URL = '' then Exit;

  { A picture that is in the notebook: a data: URI, or an attachment pasted
    into the cell.  Decoded rather than fetched, and nothing is written to a
    temporary file on the way. }
  if LedNBEmbeddedImage(FDoc.Notebook, FCell, URL, Bytes, Mime) then
  begin
    Picture := TPicture.Create;
    Stream := TStringStream.Create(Bytes);
    try
      try
        Picture.LoadFromStreamWithFileExt(Stream, LedNBImageExt(Mime));
      except
        FreeAndNil(Picture);
      end;
    finally
      Stream.Free;
    end;
    Exit;
  end;

  { Anything with a scheme is on the web, and RewriteImages has already
    taken those out of the page -- so this is a file beside the notebook. }
  if Pos('://', URL) > 0 then Exit;

  if (URL[1] = '/') or ((Length(URL) > 1) and (URL[2] = ':')) then
    FN := URL
  else
    FN := IncludeTrailingPathDelimiter(ExtractFileDir(FDoc.FileName)) + URL;
  if not FileExists(FN) then Exit;

  Picture := TPicture.Create;
  try
    Picture.LoadFromFile(FN);
  except
    FreeAndNil(Picture);
  end;
end;

{ One prose cell as a page, in the theme's colours.

  The style is a notebook front end's: the prose in a proportional face at
  reading size, code on a block a little away from the page, links that look
  like links and are still readable against whatever the page is.  The
  colours are set as attributes as well as in the style sheet, because IPro
  reads rather little CSS and the attributes it does read are the ones that
  decide the background. }
function TLedNBCellBox.ProsePage(const ASource: string): string;
var
  C: TLedNBColourSet;
  Html: string;
begin
  C := LedNBColours;
  Html := LedNBHideRemoteImages(LedMarkdownToHTML(ASource));
  Result :=
    '<html><head><style>' +
    'body { margin: 0; font-family: sans-serif; color: ' +
      HtmlColour(C.Text) + '; }' +
    'h1, h2, h3, h4 { margin: 6px 0 4px 0; }' +
    'p { margin: 4px 0 8px 0; }' +
    'pre, code { background: ' + HtmlColour(C.CodeBg) + '; }' +
    'blockquote { border-left: 3px solid ' + HtmlColour(C.Border) +
      '; padding-left: 8px; }' +
    'a { color: ' + HtmlColour(C.Link) + '; }' +
    '</style></head>' +
    '<body bgcolor="' + HtmlColour(C.Page) + '" text="' +
      HtmlColour(C.Text) + '" link="' + HtmlColour(C.Link) + '" vlink="' +
      HtmlColour(C.Link) + '">' + Html + '</body></html>';
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
      { The same face and size the panel was given, for the same reason. }
      Doc.DefaultTypeFace := ProseFace;
      Doc.DefaultFontSize := ProseSize(FDoc);
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
    if LedNBImageOf(FDoc.Notebook, FCell, Index_, Bytes, Mime) then
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
    Page := ProsePage(Source);
    Room := AWidth - LedScale96(ProseGutter + Pad);
    if Room < LedScale96(80) then Room := LedScale96(80);
    { The panel is made as tall as the prose is, so the cell shows all of it
      and never scrolls inside itself.  A cell of prose folded into a box
      with its own scrollbar is the one thing a reader cannot skim.

      How tall that is has to be measured: the renderer does not know what
      height it wants until it has laid the page out, and the panel cannot be
      asked before it has a page in it. }
    FRender.SetBounds(LedScale96(ProseGutter), Y, Room,
      RenderedHeight(Page, Room));
    FRender.SetHtmlFromStr(Page);
    Inc(Y, FRender.Height + LedScale96(4));
  end
  else
  begin
    MakeEditor;
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
  FBoxes := TFPList.Create;
  VertScrollBar.Tracking := True;
  HorzScrollBar.Visible := False;

  Color := LedNBColours.Page;
  ParentColor := False;

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
end;

procedure TLedNotebookPane.Resize;
begin
  inherited Resize;
  if FBoxes = nil then Exit;
  if FBoxes.Count = 0 then Exit;
  if ClientWidth = FLaidOutFor then Exit;
  FResizeTimer.Enabled := False;
  FResizeTimer.Enabled := True;
end;

procedure TLedNotebookPane.ResizeSettled(Sender: TObject);
begin
  FResizeTimer.Enabled := False;
  Relayout;
end;

{ Every box to the pane's width, and every height worked out again for it.

  Not a Reload: that would build the boxes afresh and take the caret out of
  whichever one is being typed into.  Rebuild keeps the editor and its text
  and only redoes what depends on the width -- the wrapped height, the
  rendered prose, the scale a picture is drawn at. }
procedure TLedNotebookPane.Relayout;
var
  i, Y, W: Integer;
begin
  if (FBoxes = nil) or (FBoxes.Count = 0) then Exit;
  { The document may have closed since the boxes were built -- this runs from
    a timer, and a tab can be shut between the resize and the settling.  The
    cells are of a document that is gone, so they go too.  Without this the
    docking checks, which resize every pane, walked into a freed document. }
  if not LedDocumentIsOpen(FDoc) then
  begin
    FDoc := nil;
    Reload;
    Exit;
  end;
  W := ClientWidth - LedScale96(4);
  if W < LedScale96(120) then W := LedScale96(120);

  DisableAutoSizing;
  try
    Y := 0;
    for i := 0 to FBoxes.Count - 1 do
    begin
      TLedNBCellBox(FBoxes[i]).SetBounds(0, Y, W,
        TLedNBCellBox(FBoxes[i]).Height);
      Inc(Y, TLedNBCellBox(FBoxes[i]).Rebuild(W) + LedScale96(4));
    end;
    FLaidOutFor := ClientWidth;
  finally
    EnableAutoSizing;
  end;
end;

destructor TLedNotebookPane.Destroy;
begin
  FBoxes.Free;
  inherited Destroy;
end;

function TLedNotebookPane.CellCount: Integer;
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

procedure TLedNotebookPane.ShowDocument(ADoc: TLedDocument);
begin
  if (ADoc <> nil) and (not ADoc.IsNotebook) then ADoc := nil;
  FDoc := ADoc;
  Reload;
end;

procedure TLedNotebookPane.Reload;
var
  i, Y: Integer;
  B: TLedNBCellBox;
begin
  { Same reason as in Relayout, and this is the other way in. }
  if (FDoc <> nil) and (not LedDocumentIsOpen(FDoc)) then FDoc := nil;
  { The theme may have changed since the cells were built, and every colour
    in here comes from it. }
  Color := LedNBColours.Page;
  FNote.Font.Color := LedNBColours.Muted;
  DisableAutoSizing;
  try
    { Released rather than freed.  A cell box holds the controls a reader
      clicks, and freeing one while the LCL still has it in hand is what
      "TLedNBCellBox.Destroy with LCLRefCount>0.  Maybe the component is
      processing an event?" means -- after which the editor is standing on
      freed memory.  Nothing should rebuild the pane from inside a cell's own
      event any more, and this is the guard for the paths nobody thought of:
      the box goes away once the event that was using it has finished. }
    for i := 0 to FBoxes.Count - 1 do
    begin
      TLedNBCellBox(FBoxes[i]).Visible := False;
      Application.ReleaseComponent(TLedNBCellBox(FBoxes[i]));
    end;
    FBoxes.Clear;

    if FDoc = nil then
    begin
      FNote.Caption := 'This is not a Jupyter notebook.';
      FNote.Visible := True;
      Exit;
    end;
    FNote.Visible := False;

    Y := 0;
    for i := 0 to FDoc.Notebook.CellCount - 1 do
    begin
      B := TLedNBCellBox.Create(Self, FDoc, i, FImages);
      B.Parent := Self;
      B.OnRunCell := @CellRun;
      B.OnEdited := @CellEdited;
      B.SetBounds(0, Y, ClientWidth - LedScale96(4), LedScale96(40));
      Inc(Y, B.Rebuild(ClientWidth - LedScale96(4)) + LedScale96(4));
      FBoxes.Add(B);
    end;
    FLaidOutFor := ClientWidth;
  finally
    EnableAutoSizing;
  end;
end;

procedure TLedNotebookPane.RefreshCell(ACell: Integer);
var
  i, Y: Integer;
  B: TLedNBCellBox;
begin
  if not LedDocumentIsOpen(FDoc) then Exit;
  B := BoxOf(ACell);
  if B = nil then Exit;
  B.Rebuild(B.Width);
  { Everything under it moves: a cell that has just produced a plot is
    taller than it was. }
  Y := 0;
  for i := 0 to FBoxes.Count - 1 do
  begin
    TLedNBCellBox(FBoxes[i]).Top := Y;
    Inc(Y, TLedNBCellBox(FBoxes[i]).Height + LedScale96(4));
  end;
end;

procedure TLedNotebookPane.CellRun(Sender: TObject; ACell: Integer);
begin
  if Assigned(FOnRun) then FOnRun(Self, ACell);
end;

procedure TLedNotebookPane.CellEdited(Sender: TObject; ACell: Integer);
var
  B: TLedNBCellBox;
  i, Y: Integer;
begin
  { A cell grows as it is typed into, so the ones below it move.  Its own
    box is not rebuilt -- that would take the caret out of the editor the
    reader is typing in. }
  B := BoxOf(ACell);
  if B = nil then Exit;
  if B.Editor <> nil then B.Editor.Height := B.EditorHeight;
  Y := 0;
  for i := 0 to FBoxes.Count - 1 do
  begin
    TLedNBCellBox(FBoxes[i]).Top := Y;
    if TLedNBCellBox(FBoxes[i]).Cell = ACell then
      TLedNBCellBox(FBoxes[i]).Height :=
        B.Editor.Top + B.Editor.Height + LedScale96(Pad);
    Inc(Y, TLedNBCellBox(FBoxes[i]).Height + LedScale96(4));
  end;
end;

end.
