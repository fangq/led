{ LED - a lightweight editor.  One notebook tab: a document and its views.

  The tab holds a tree of TPairSplitter, so splitting is recursive: splitting
  the focused view wraps that view in a new splitter and puts a fresh view of
  the same document beside it.  Up to four views, matching medit. }
unit Led.UI.Tab;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, PairSplitter, ComCtrls, Menus,
  Led.UI.Document, Led.UI.Edit, Led.UI.Focus,
  Led.UI.MiniMap,
  Led.UI.Splitter, Led.UI.Visual;

const
  LedMaxViewsPerTab = 4;

type
  TLedTab = class(TPanel)
  private
    FDocument: TLedDocument;
    FViews: TFPList;            // of TLedEdit, in creation order
    FActiveView: TLedEdit;
    FSheet: TTabSheet;          // the page this tab lives on
    FViewPopupMenu: TPopupMenu;
    FViewBreakpointClick: TLedBreakpointClick;
    FViewHoverExpression: TLedHoverExpression;
    FViewBJEdit: TLedBJOpenEvent;
    FViewDragOver: TDragOverEvent;
    FViewDragDrop: TDragDropEvent;
    FMiniMap: TLedMiniMap;
    FShowMiniMap: Boolean;
    FVisual: TLedVisualPane;
    FVisualMode: Boolean;
    procedure ShowViews(AShow: Boolean);
    procedure VisualChanged(Sender: TObject);
    procedure VisualFlush(Sender: TObject);
    procedure SetShowMiniMap(AValue: Boolean);
    procedure ViewEnter(Sender: TObject);
    function AddView(AParent: TWinControl): TLedEdit;
    procedure SetViewPopupMenu(AValue: TPopupMenu);
    procedure SetViewBreakpointClick(AValue: TLedBreakpointClick);
    procedure SetViewHoverExpression(AValue: TLedHoverExpression);
    procedure SetViewBJEdit(AValue: TLedBJOpenEvent);
    procedure SetViewDragOver(AValue: TDragOverEvent);
    procedure SetViewDragDrop(AValue: TDragDropEvent);
    function GetViewCount: Integer;
    function GetView(AIndex: Integer): TLedEdit;
  public
    constructor CreateForDocument(AOwner: TComponent; ADoc: TLedDocument);
    destructor Destroy; override;

    { AVertical selects a top/bottom arrangement; otherwise the views sit
      side by side. }
    procedure SplitView(AVertical: Boolean);
    procedure Unsplit;
    procedure CycleViews;
    function CanSplit: Boolean;

    property Document: TLedDocument read FDocument;
    property ActiveView: TLedEdit read FActiveView;
    property Views[AIndex: Integer]: TLedEdit read GetView;
    property ViewCount: Integer read GetViewCount;
    { How the tab was last split, so a session can put it back the same way.
      False -- and meaningless -- when there is only one view. }
    function SplitIsVertical: Boolean;
    { Applied to every view the tab creates, including the ones a later split
      adds, so the context menu does not go missing after Split View. }
    property ViewPopupMenu: TPopupMenu read FViewPopupMenu write SetViewPopupMenu;
    { Set on every view, splits included, the same way the popup menu is:
      a breakpoint is toggled by clicking the gutter of whichever view of the
      document happens to be under the pointer. }
    property ViewBreakpointClick: TLedBreakpointClick
      read FViewBreakpointClick write SetViewBreakpointClick;
    property ViewHoverExpression: TLedHoverExpression
      read FViewHoverExpression write SetViewHoverExpression;
    { Return or a double click over a record of a BJData file.  On every view
      for the same reason as the two above: whichever half of a split tab the
      reader is looking at is the one they will press Return in. }
    property ViewBJEdit: TLedBJOpenEvent read FViewBJEdit write SetViewBJEdit;
    { What a file dragged out of the file list lands on.  On every view for
      the same reason as the three above: the editor area is covered by
      them, so whichever one the reader is pointing at is the one that has
      to take the drop. }
    property ViewDragOver: TDragOverEvent
      read FViewDragOver write SetViewDragOver;
    property ViewDragDrop: TDragDropEvent
      read FViewDragDrop write SetViewDragDrop;
    property Sheet: TTabSheet read FSheet write FSheet;

    { The minimap, and whether it is shown.

      One for the tab rather than one per view.  A split tab has up to four
      views of the same document, and four strips of the same picture down
      one window is four times the width for no more information; the map
      follows whichever view has the focus instead, which is the one the
      question "where am I in this file" is about. }
    { Re-decides whether the map is shown and what it is of.  Public because a
      document can turn into a hex dump, or stop being one, without the tab
      being told -- Open as Text is the case that does it. }
    procedure RefreshMiniMap;

    property MiniMap: TLedMiniMap read FMiniMap;
    property ShowMiniMap: Boolean read FShowMiniMap write SetShowMiniMap;

    { The visual editor: the document as pages, in place of the views.

      Only for a Markdown, HTML or Word file, and only in a LED built with
      Parade.  The page is a translation of what the document holds, made on
      the way in; what is changed on it goes back on the way out, or at the
      next save, whichever comes first -- the document asks for it through
      OnFlushVisual.  The views stay where they are, hidden, so the split
      they were in is the split they come back to. }
    function CanVisual: Boolean;
    function EnterVisual(out AWhy: string): Boolean;
    procedure LeaveVisual;
    { The page made again from the document, after it was reloaded from
      disk underneath it. }
    function ReloadVisual(out AWhy: string): Boolean;
    property VisualMode: Boolean read FVisualMode;
    property Visual: TLedVisualPane read FVisual;
  end;

implementation

{ A TPairSplitter leaves its divider wherever the default position puts it,
  which is not the middle, so a fresh split looks lopsided.  The size is only
  known once the layout has run, hence the InitialSize fallback for a splitter
  that is not on screen yet. }
procedure CentreSplitter(ASplitter: TPairSplitter);
var
  Extent: Integer;
begin
  ASplitter.HandleNeeded;
  if ASplitter.SplitterType = pstHorizontal then
    Extent := ASplitter.Width
  else
    Extent := ASplitter.Height;
  if Extent < 40 then
  begin
    if ASplitter.SplitterType = pstHorizontal then
      Extent := ASplitter.Parent.ClientWidth
    else
      Extent := ASplitter.Parent.ClientHeight;
  end;
  if Extent >= 40 then
    ASplitter.Position := Extent div 2;
end;


constructor TLedTab.CreateForDocument(AOwner: TComponent; ADoc: TLedDocument);
begin
  inherited Create(AOwner);
  FDocument := ADoc;
  FViews := TFPList.Create;

  BevelOuter := bvNone;
  Caption := '';
  Align := alClient;

  { Created before the views and aligned to the right edge of the tab, so the
    splitter tree that holds them fills what is left.  Hidden until asked
    for -- see SetShowMiniMap. }
  FMiniMap := TLedMiniMap.Create(Self);
  FMiniMap.Parent := Self;
  FMiniMap.Align := alRight;
  FMiniMap.Visible := False;

  AddView(Self);
end;

procedure TLedTab.SetShowMiniMap(AValue: Boolean);
begin
  FShowMiniMap := AValue;
  RefreshMiniMap;
end;

{ Shown when it is asked for and there is something for it to be a map of.

  A hex dump is not.  Every row of one is the same shape -- an address, the
  same sixteen byte cells, the same sixteen characters -- so the map of it is
  a solid rectangle the height of the file, which tells the reader nothing
  and takes a strip of the window to do it.  The structure view keeps its
  map: those rows have an outline, and an outline is what a minimap draws.

  Called whenever what the tab is showing might have changed, because a
  document turns into a dump and back -- Open as Text -- without the tab
  being told. }
procedure TLedTab.RefreshMiniMap;
begin
  if FMiniMap = nil then Exit;
  FMiniMap.Visible := FShowMiniMap and (FActiveView <> nil) and
    (not FActiveView.HexMode) and (not FVisualMode);
  if FMiniMap.Visible then
    FMiniMap.Attach(FActiveView);
end;

destructor TLedTab.Destroy;
var
  i: Integer;
begin
  { The map holds a reference to a view, and the views are about to go. }
  if FMiniMap <> nil then FMiniMap.Attach(nil);
  { And the document a way back to the page. }
  if (FDocument <> nil) and FVisualMode then FDocument.OnFlushVisual := nil;
  { Detach the views from the document before they are destroyed with us, so
    the document's view list never holds dangling pointers. }
  if FDocument <> nil then
    for i := 0 to FViews.Count - 1 do
      FDocument.RemoveView(TLedEdit(FViews[i]));
  FViews.Free;
  inherited Destroy;
end;

function TLedTab.GetViewCount: Integer;
begin
  Result := FViews.Count;
end;

function TLedTab.GetView(AIndex: Integer): TLedEdit;
begin
  Result := TLedEdit(FViews[AIndex]);
end;

procedure TLedTab.SetViewPopupMenu(AValue: TPopupMenu);
var
  i: Integer;
begin
  FViewPopupMenu := AValue;
  for i := 0 to FViews.Count - 1 do
    TLedEdit(FViews[i]).PopupMenu := AValue;
end;

procedure TLedTab.SetViewBreakpointClick(AValue: TLedBreakpointClick);
var
  i: Integer;
begin
  FViewBreakpointClick := AValue;
  for i := 0 to FViews.Count - 1 do
    TLedEdit(FViews[i]).OnBreakpointClick := AValue;
end;

procedure TLedTab.SetViewHoverExpression(AValue: TLedHoverExpression);
var
  i: Integer;
begin
  FViewHoverExpression := AValue;
  for i := 0 to FViews.Count - 1 do
    TLedEdit(FViews[i]).OnHoverExpression := AValue;
end;

procedure TLedTab.SetViewDragOver(AValue: TDragOverEvent);
var
  i: Integer;
begin
  FViewDragOver := AValue;
  for i := 0 to FViews.Count - 1 do
    TLedEdit(FViews[i]).OnDragOver := AValue;
end;

procedure TLedTab.SetViewDragDrop(AValue: TDragDropEvent);
var
  i: Integer;
begin
  FViewDragDrop := AValue;
  for i := 0 to FViews.Count - 1 do
    TLedEdit(FViews[i]).OnDragDrop := AValue;
end;

procedure TLedTab.SetViewBJEdit(AValue: TLedBJOpenEvent);
var
  i: Integer;
begin
  FViewBJEdit := AValue;
  for i := 0 to FViews.Count - 1 do
    TLedEdit(FViews[i]).OnBJEdit := AValue;
end;

function TLedTab.AddView(AParent: TWinControl): TLedEdit;
begin
  Result := FDocument.CreateView(Self);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.OnEnter := @ViewEnter;
  Result.PopupMenu := FViewPopupMenu;
  Result.OnBreakpointClick := FViewBreakpointClick;
  Result.OnHoverExpression := FViewHoverExpression;
  Result.OnBJEdit := FViewBJEdit;
  Result.OnDragOver := FViewDragOver;
  Result.OnDragDrop := FViewDragDrop;
  FViews.Add(Result);
  if FActiveView = nil then
  begin
    FActiveView := Result;
    RefreshMiniMap;
  end;
end;

procedure TLedTab.ViewEnter(Sender: TObject);
begin
  FActiveView := TLedEdit(Sender);
  { The map is of the view being looked at.  In a split tab that is whichever
    one has just taken the focus. }
  RefreshMiniMap;
end;

function TLedTab.SplitIsVertical: Boolean;
var
  Side: TWinControl;
begin
  { Read back off the splitter that actually holds the views, rather than
    remembering what was asked for -- the two can differ once a split has
    been closed and remade. }
  Result := False;
  if FViews.Count < 2 then Exit;
  Side := TLedEdit(FViews[1]).Parent;
  if not (Side is TPairSplitterSide) then Exit;
  Result := TPairSplitter(Side.Parent).SplitterType = pstVertical;
end;

function TLedTab.CanSplit: Boolean;
begin
  Result := (FViews.Count < LedMaxViewsPerTab) and (not FVisualMode);
end;

function TLedTab.CanVisual: Boolean;
var
  Kind: TLedVisualKind;
begin
  Result := False;
  if not LedVisualAvailable then Exit;
  Kind := LedVisualKindOf(FDocument.KindName);
  if Kind = lvkNone then Exit;
  { A .docx is bytes, and an HTML or Markdown file is text; one that was
    opened the other way round -- Open as Text on a .docx -- holds nothing
    the page could be made from. }
  Result := (Kind = lvkDocx) = FDocument.IsBinary;
end;

procedure TLedTab.ShowViews(AShow: Boolean);
var
  i: Integer;
  C: TControl;
begin
  for i := 0 to ControlCount - 1 do
  begin
    C := Controls[i];
    if (C <> FVisual) and (C <> FMiniMap) then C.Visible := AShow;
  end;
  RefreshMiniMap;
end;

function TLedTab.EnterVisual(out AWhy: string): Boolean;
var
  Made: Boolean;
begin
  Result := FVisualMode;
  AWhy := '';
  if FVisualMode then Exit;
  if not LedVisualAvailable then
  begin
    AWhy := 'this LED was built without Parade, the visual editor';
    Exit;
  end;
  if not CanVisual then
  begin
    if LedVisualKindOf(FDocument.KindName) = lvkNone then
      AWhy := 'the visual editor opens Markdown, HTML and Word (.docx) files'
    else
      AWhy := 'the file is not open as what its name says it is';
    Exit;
  end;
  Made := FVisual = nil;
  if Made then
  begin
    FVisual := TLedVisualPane.Create(Self);
    FVisual.Visible := False;
    FVisual.Parent := Self;
    FVisual.Align := alClient;
    FVisual.OnChange := @VisualChanged;
  end;
  FVisualMode := True;
  if not ReloadVisual(AWhy) then
  begin
    FVisualMode := False;
    if Made then FreeAndNil(FVisual);
    FDocument.EnsureHexText;    { the pages could not be made: the bytes are what is shown }
    Exit;
  end;
  FDocument.OnFlushVisual := @VisualFlush;
  ShowViews(False);
  FVisual.Visible := True;
  LedTryFocus(FVisual.Editor);
  Result := True;
end;

function TLedTab.ReloadVisual(out AWhy: string): Boolean;
var
  Kind: TLedVisualKind;
  Data: string;
begin
  Result := False;
  AWhy := '';
  if (not FVisualMode) or (FVisual = nil) then Exit;
  Kind := LedVisualKindOf(FDocument.KindName);
  if Kind = lvkDocx then
    Data := FDocument.Bytes
  else
    Data := FDocument.Master.Lines.Text;
  Result := FVisual.Load(Data, Kind, FDocument.FileName, AWhy);
end;

procedure TLedTab.LeaveVisual;
begin
  if not FVisualMode then Exit;
  { Written back while the page still exists to be read. }
  FDocument.FlushVisual;
  FDocument.OnFlushVisual := nil;
  FVisualMode := False;
  FVisual.Visible := False;
  FDocument.EnsureHexText;
  ShowViews(True);
  { Made again next time, from the text as it is then: a page kept from now
    would not know what is typed into the text in between. }
  FreeAndNil(FVisual);
  LedTryFocus(FActiveView);
end;

procedure TLedTab.VisualChanged(Sender: TObject);
begin
  FDocument.NoteVisualEdit;
end;

procedure TLedTab.VisualFlush(Sender: TObject);
var
  Data: string;
begin
  if FVisual = nil then Exit;
  Data := FVisual.Export;
  if FVisual.Kind = lvkDocx then
    FDocument.TakeVisualBytes(Data)
  else
    FDocument.TakeVisualText(Data);
  FVisual.MarkSaved;
end;

procedure TLedTab.SplitView(AVertical: Boolean);
var
  Old: TLedEdit;
  Host: TWinControl;
  Splitter: TPairSplitter;
  NewView: TLedEdit;
begin
  if not CanSplit then Exit;
  Old := FActiveView;
  if Old = nil then Exit;

  Host := Old.Parent;

  Splitter := TLedPairSplitter.Create(Self);
  Splitter.Parent := Host;
  Splitter.Align := alClient;
  { pstHorizontal moves the divider horizontally, i.e. the views sit side by
    side; pstVertical stacks them.  Named here by the arrangement, not by the
    divider, because that is what the menu item promises. }
  if AVertical then
    Splitter.SplitterType := pstVertical
  else
    Splitter.SplitterType := pstHorizontal;

  Old.Parent := Splitter.Sides[0];
  Old.Align := alClient;

  NewView := AddView(Splitter.Sides[1]);
  { Start the new view where the old one is looking. }
  NewView.TopLine := Old.TopLine;
  NewView.CaretXY := Old.CaretXY;

  CentreSplitter(Splitter);
end;

procedure TLedTab.Unsplit;
var
  Doomed: TLedEdit;
  Side: TWinControl;
  Splitter: TPairSplitter;
  Keeper: TControl;
  Host: TWinControl;
begin
  if FViews.Count < 2 then Exit;
  Doomed := FActiveView;
  if (Doomed = nil) or not (Doomed.Parent is TPairSplitterSide) then Exit;

  Side := Doomed.Parent;
  Splitter := TPairSplitter(Side.Parent);
  Host := Splitter.Parent;

  { Whatever lives on the other side takes the splitter's place. }
  if Splitter.Sides[0] = Side then
    Side := Splitter.Sides[1]
  else
    Side := Splitter.Sides[0];
  if Side.ControlCount = 0 then Exit;
  Keeper := Side.Controls[0];

  FViews.Remove(Doomed);
  FDocument.RemoveView(Doomed);
  FActiveView := nil;
  { Before it is freed, not after: the map would otherwise be mapping a view
    that no longer exists for as long as it takes to pick the next one. }
  if (FMiniMap <> nil) and (FMiniMap.Editor = Doomed) then
    FMiniMap.Attach(nil);
  Doomed.Free;

  Keeper.Parent := Host;
  Keeper.Align := alClient;
  Splitter.Free;

  if FViews.Count > 0 then
    FActiveView := TLedEdit(FViews[0]);
  RefreshMiniMap;
  LedTryFocus(FActiveView);
end;

procedure TLedTab.CycleViews;
var
  i: Integer;
begin
  if FViews.Count < 2 then Exit;
  i := FViews.IndexOf(FActiveView);
  i := (i + 1) mod FViews.Count;
  FActiveView := TLedEdit(FViews[i]);
  RefreshMiniMap;
  LedTryFocus(FActiveView);
end;

end.
