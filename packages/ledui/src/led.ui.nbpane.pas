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
  Classes, SysUtils, Controls, ExtCtrls, StdCtrls, Buttons, Graphics, Forms,
  LazUTF8,
  IpHtml, Ipfilebroker,
  Led.Core.NBFormat, Led.Core.NBView, Led.Core.NBImage, Led.Core.Markdown,
  Led.Syn.Factory, Led.Syn.Theme,
  Led.UI.Document, Led.UI.Edit, Led.UI.Dpi;

type
  TLedNBCellEvent = procedure(Sender: TObject; ACell: Integer) of object;

  { One cell: its label, its Run button, its source, and whatever it
    produced. }
  TLedNBCellBox = class(TPanel)
  private
    FDoc: TLedDocument;
    FCell: Integer;
    FHead: TLabel;
    FRun: TSpeedButton;
    FEdit: TLedEdit;
    FRender: TIpHtmlPanel;
    FProvider: TIpFileDataProvider;
    FOnRun: TLedNBCellEvent;
    FOnEdited: TLedNBCellEvent;
    FEditing: Boolean;         // a markdown cell being typed into
    procedure RunClicked(Sender: TObject);
    procedure RenderClicked(Sender: TObject);
    procedure EditExited(Sender: TObject);
    procedure MakeEditor;
    procedure MakeRender;
    procedure ProvideImage(Sender: TIpHtmlNode; const URL: string;
      var Picture: TPicture);
    procedure BuildOutputs(var AY: Integer);
    function RenderedHeight(const APage: string; AWidth: Integer): Integer;

  public
    constructor Create(AOwner: TComponent; ADoc: TLedDocument;
      ACell: Integer); reintroduce;
    { Lays the cell out for its current contents and answers how tall it is. }
    function Rebuild: Integer;
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
    property Rendered: TIpHtmlPanel read FRender;
    property RunButton: TSpeedButton read FRun;
    property OnRunCell: TLedNBCellEvent read FOnRun write FOnRun;
    property OnEdited: TLedNBCellEvent read FOnEdited write FOnEdited;
  end;

  TLedNotebookPane = class(TScrollBox)
  private
    FDoc: TLedDocument;
    FBoxes: TFPList;           // of TLedNBCellBox
    FNote: TLabel;
    FOnRun: TLedNBCellEvent;
    procedure CellRun(Sender: TObject; ACell: Integer);
    procedure CellEdited(Sender: TObject; ACell: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

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
    { Fired when a cell's Run button is pressed; the window runs it, because
      the kernel is the document's and the reporting is the window's. }
    property OnRunCell: TLedNBCellEvent read FOnRun write FOnRun;
  end;

implementation

const
  Pad = 6;
  LabelWidth = 76;

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

{ ---- one cell ---- }

constructor TLedNBCellBox.Create(AOwner: TComponent; ADoc: TLedDocument;
  ACell: Integer);
begin
  inherited Create(AOwner);
  FDoc := ADoc;
  FCell := ACell;
  BevelOuter := bvNone;
  ParentColor := True;

  FHead := TLabel.Create(Self);
  FHead.Parent := Self;
  FHead.SetBounds(LedScale96(Pad), LedScale96(Pad), LedScale96(LabelWidth),
    LedScale96(16));

  { Code cells get a Run button; prose has nothing to run. }
  if FDoc.Notebook.CellKind(FCell) = nbkCode then
  begin
    FRun := TSpeedButton.Create(Self);
    FRun.Parent := Self;
    FRun.Caption := '>';
    FRun.Hint := 'Run this cell';
    FRun.ShowHint := True;
    FRun.Flat := True;
    FRun.SetBounds(LedScale96(Pad), LedScale96(Pad + 18),
      LedScale96(20), LedScale96(20));
    FRun.OnClick := @RunClicked;
  end;
end;

procedure TLedNBCellBox.RunClicked(Sender: TObject);
begin
  { What is on screen is what runs, so the typing goes in first. }
  Commit;
  if Assigned(FOnRun) then FOnRun(Self, FCell);
end;

procedure TLedNBCellBox.Commit;
begin
  if (FEdit = nil) or (FDoc = nil) then Exit;
  if not FEdit.Modified then Exit;
  FDoc.NBSetCellSource(FCell, FEdit.Lines.Text);
  FEdit.Modified := False;
  if Assigned(FOnEdited) then FOnEdited(Self, FCell);
end;

{ A rendered prose cell, clicked: prose is shown rendered and edited as
  Markdown, which is what every notebook front end does. }
procedure TLedNBCellBox.RenderClicked(Sender: TObject);
begin
  FEditing := True;
  Rebuild;
  if FEdit <> nil then FEdit.SetFocus;
end;

procedure TLedNBCellBox.EditExited(Sender: TObject);
begin
  Commit;
  if FEditing then
  begin
    FEditing := False;
    Rebuild;
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
end;

procedure TLedNBCellBox.MakeRender;
begin
  if FRender <> nil then Exit;
  FProvider := TIpFileDataProvider.Create(Self);
  { Every picture on the page comes through here.  Without it the renderer
    opens the file itself and raises when there is not one -- which a real
    notebook managed on the first try: a Markdown cell referring to an image
    by a bare name took the error out through the paint. }
  FProvider.OnGetImage := @ProvideImage;
  FRender := TIpHtmlPanel.Create(Self);
  FRender.Parent := Self;
  FRender.DataProvider := FProvider;
  FRender.OnClick := @RenderClicked;
end;

{ A picture named by a Markdown cell: beside the notebook, or nothing.

  Nothing is fetched over the network -- a preview that reaches out to the
  internet while somebody reads their own file is not what they asked for --
  and a name that is not there is simply not drawn.  Neither is an error: a
  cell whose picture is missing still has its prose. }
procedure TLedNBCellBox.ProvideImage(Sender: TIpHtmlNode; const URL: string;
  var Picture: TPicture);
var
  FN: string;
begin
  Picture := nil;
  if (URL = '') or (Pos('://', URL) > 0) then Exit;

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
begin
  Result := LedScale96(40);
  Doc := TIpHtmlMeasure.Create;
  Stream := TStringStream.Create(APage);
  try
    try
      Doc.LoadFromStream(Stream);
      { A height of nothing lays nothing out: the page is measured with as
        much room as it could want and comes back with what it used. }
      H := Doc.PageHeightAt(Canvas, AWidth);
      if H > 0 then Result := H + LedScale96(4);
    except
      { A page that will not lay out gets the default height rather than
        taking the cell down with it. }
    end;
  finally
    Stream.Free;
    Doc.Free;
  end;
  { A cell of prose can be long, but a single cell taller than a few screens
    is a cell nobody scrolls through on purpose. }
  if Result > LedScale96(2000) then Result := LedScale96(2000);
end;

{ The pictures and the text a cell produced, as widgets under it. }
procedure TLedNBCellBox.BuildOutputs(var AY: Integer);
var
  Outs: TStringList;
  Flags: TLedNBFlags;
  i, Index_, Count: Integer;
  Bytes, Mime: string;
  Img: TImage;
  Room: Integer;
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
      Img.AutoSize := True;
      Img.Proportional := True;
      Img.Stretch := False;
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
        Room := Width - LedScale96(LabelWidth + Pad * 2);
        if Room < LedScale96(40) then Room := LedScale96(40);
        Img.Left := LedScale96(LabelWidth + Pad);
        Img.Top := AY;
        { A plot is saved at the size the plotting library chose, which is
          usually wider than a side pane.  Shown at its own size it is cut
          off at the edge with no sign that there is more of it, so one that
          does not fit is scaled down whole. }
        if Img.Picture.Width > Room then
        begin
          Img.AutoSize := False;
          Img.Stretch := True;
          Img.Proportional := True;
          Img.Width := Room;
          Img.Height :=
            Round(Img.Picture.Height * (Room / Img.Picture.Width));
        end;
        Inc(AY, Img.Height + LedScale96(4));
      end;
    end;

  { And the text, rendered the same way the line view renders it -- one
    place decides what an output says. }
  Outs := TStringList.Create;
  try
    Outs.TextLineBreakStyle := tlbsLF;
    LedNBOutputLines(FDoc.Notebook, FCell, Outs, Flags);
    if Outs.Count = 0 then Exit;
    for i := 0 to Outs.Count - 1 do
    begin
      Note := TLabel.Create(Self);
      Note.Parent := Self;
      Note.Font.Name := FEdit.Font.Name;
      Note.Font.Size := FEdit.Font.Size;
      if (i <= High(Flags)) and Flags[i] then Note.Font.Color := clRed;
      Note.Caption := Outs[i];
      Note.SetBounds(LedScale96(LabelWidth + Pad), AY,
        Width - LedScale96(LabelWidth + Pad * 2), FEdit.LineHeight);
      Inc(AY, FEdit.LineHeight);
    end;
  finally
    Outs.Free;
  end;
end;

function TLedNBCellBox.Rebuild: Integer;
var
  Y, Count, i, Room: Integer;
  Source, Page: string;
  Prose: Boolean;
begin
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
    nbkMarkdown: FHead.Caption := 'Markdown';
  else
    FHead.Caption := 'Raw';
  end;

  Source := FDoc.Notebook.CellSource(FCell);
  Prose := (FDoc.Notebook.CellKind(FCell) = nbkMarkdown) and (not FEditing);

  Y := LedScale96(Pad);
  if Prose then
  begin
    MakeRender;
    if FEdit <> nil then FEdit.Visible := False;
    FRender.Visible := True;
    Page := '<html><body style="margin:0">' +
      LedMarkdownToHTML(Source) + '</body></html>';
    Room := Width - LedScale96(LabelWidth + Pad * 2);
    if Room < LedScale96(80) then Room := LedScale96(80);
    { How tall the prose comes out at that width, asked of a throwaway
      document of its own.  Without this every prose cell was given forty
      pixels and showed its first line -- the renderer has no idea what
      height it wants until it has laid the page out, and the panel cannot be
      asked before it has one. }
    FRender.SetBounds(LedScale96(LabelWidth + Pad), Y, Room,
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
    Room := Width - LedScale96(LabelWidth + Pad * 2);
    if Room < LedScale96(80) then Room := LedScale96(80);
    FEdit.SetBounds(LedScale96(LabelWidth + Pad), Y, Room,
      FEdit.LineHeight * 2);
    FEdit.SetBounds(LedScale96(LabelWidth + Pad), Y, Room, EditorHeight);
    Inc(Y, FEdit.Height + LedScale96(4));
  end;

  BuildOutputs(Y);
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

  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.Align := alTop;
  FNote.BorderSpacing.Around := LedScale96(8);
  FNote.Visible := False;
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
  DisableAutoSizing;
  try
    for i := 0 to FBoxes.Count - 1 do
      TLedNBCellBox(FBoxes[i]).Free;
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
      B := TLedNBCellBox.Create(Self, FDoc, i);
      B.Parent := Self;
      B.OnRunCell := @CellRun;
      B.OnEdited := @CellEdited;
      B.SetBounds(0, Y, ClientWidth - LedScale96(4), LedScale96(40));
      Inc(Y, B.Rebuild + LedScale96(4));
      FBoxes.Add(B);
    end;
  finally
    EnableAutoSizing;
  end;
end;

procedure TLedNotebookPane.RefreshCell(ACell: Integer);
var
  i, Y: Integer;
  B: TLedNBCellBox;
begin
  B := BoxOf(ACell);
  if B = nil then Exit;
  B.Rebuild;
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
