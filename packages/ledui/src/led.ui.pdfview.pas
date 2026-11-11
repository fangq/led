{ LED - a lightweight editor.  PDF files: their pages shown, read, marked
  and filled in.

  Parade's PDF reader does the work -- it parses the file, draws a page at
  any scale, lists its text with each character's box, and makes and saves
  the changes.  This unit is the window onto it: pages one under another,
  scrolled and zoomed; text selected by dragging, copied and found;
  highlights, underlines, notes, text boxes, freehand ink and shapes made
  with the tools along the top; form fields filled in where they are.

  Nothing is written over: a save is the file as it was with the changes
  appended to it (an incremental update), which is what Acrobat does, so a
  signed file keeps its signature over the part that was signed.  The
  document's bytes are given the file with the update whenever it is saved
  (TLedTab.VisualFlush), and the pages go on editing the same reader, so
  undo reaches back past a save. }
unit Led.UI.PdfView;

{$mode objfpc}{$H+}
{$I led.parade.inc}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, StdCtrls, Graphics, Forms, Dialogs, LCLType, LCLIntf, Menus, ComCtrls,
  Buttons, Types, IntfGraphics, GraphType, ImgList, Contnrs, ExtDlgs, led.ui.pdfsign
  {$IFDEF LED_PARADE}, paradepdf{$ENDIF};

{ a file the PDF pages open: its name says so }
function LedPdfFileName(const AFileName: string): Boolean;
{ this LED reads PDF (it was built with Parade) }
function LedPdfAvailable: Boolean;

type
  TLedPdfTool = (ptSelect, ptHighlight, ptUnderline, ptStrikeOut, ptSquiggly, ptNote, ptTextBox, ptInk,
    ptRect, ptEllipse, ptLine, ptArrow);
  { what the Insert buttons put on a page, where it is clicked or dragged out next }
  TLedPdfPlace = (ppNone, ppPicture, ppSignature, ppCheck, ppCross, ppDot, ppDate, ppLink);

  { The pages: what is drawn, where each page is, the mouse on them. }
  TLedPdfPane = class;

  { A PDF presented: its pages one at a time, as large as the screen takes them, on black. A click, the arrows,
    Space, Page Down go on; the right button, Backspace, Page Up back; Home, End; a page's number then Enter; B or .
    black, W or , white; a link followed where it is clicked; Esc the end, the view at the page shown last. The next
    page is drawn while the one shown is looked at. }
  TLedPdfShow = class(TForm)
  private
    FPane: TLedPdfPane;
    FPage: Integer;
    FBmp: array[0..2] of TBitmap;     { the page shown, the one after it, the one before }
    FBmpPage: array[0..2] of Integer;
    FBmpW, FBmpH: Integer;            { the screen they were drawn for }
    FBlank: TColor;
    FBlanked: Boolean;
    FTyped: string;
    FIdle: TTimer;
    FAhead: TTimer;
    FLastMove: QWord;
    function PageBitmap(APage: Integer): TBitmap;
    procedure GoTo_(APage: Integer);
    procedure IdleTick(Sender: TObject);
    procedure AheadTick(Sender: TObject);
    function PageRect(APage: Integer): TRect;
  protected
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure Resize; override;
    procedure DoClose(var CloseAction: TCloseAction); override;
  public
    constructor CreateShow(APane: TLedPdfPane; AFrom: Integer);
    destructor Destroy; override;
    property Page: Integer read FPage;
  end;

  TLedPdfView = class(TCustomControl)
  private
    FPane: TLedPdfPane;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure DblClick; override;
    procedure TripleClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TLedPdfCharArray = {$IFDEF LED_PARADE}TPdfChars{$ELSE}array of Integer{$ENDIF};
  TLedPdfSpanArray = {$IFDEF LED_PARADE}TPdfSpans{$ELSE}array of Integer{$ENDIF};

  TLedPdfPane = class(TCustomPanel)
  private
    {$IFDEF LED_PARADE}
    FPdf: Ppd_pdfr;
    {$ENDIF}
    FFileName: string;
    FView: TLedPdfView;
    FVBar, FHBar: TScrollBar;
    FTools: TToolBar;
    FToolImages: TImageList;
    FToolButtons: array[TLedPdfTool] of TToolButton;
    FColorBtn: TColorButton;
    FZoomBox: TComboBox;
    FFindBar: TPanel;
    FFindEdit: TEdit;
    FFindNote: TLabel;
    FMenu: TPopupMenu;
    FTool: TLedPdfTool;
    FScale: Double;             // pixels a point
    FFit: Integer;              // 0 none, 1 width, 2 page, 3 the opening zoom (FFitCap) no wider than the view
    FFitCap: Double;            // that zoom, pixels a point
    FZoomBar: TPanel;           // -, the slider, +, the percentage: as under a Word document
    FZoomSlider: TTrackBar;
    FZoomLabel: TLabel;
    FZoomSliding: Boolean;
    FScrollX, FScrollY: Integer;
    FPageTop: array of Integer;     // each page's top, in pixels at the scale (the gaps included)
    FPageW, FPageH: array of Double; // its size in points
    FChars: array of TLedPdfCharArray;
    FLines, FBlocks: array of TLedPdfSpanArray;   { the page's text as lines and as blocks (made with FChars) }
    FMenuAt: TPoint;                { where the right button's menu was opened, in the view }
    FCharsOk: array of Boolean;
    FCache: array of TBitmap;       // each page drawn whole at the scale (nil: not yet, or too big to keep)
    FCacheImg: array of TLazIntfImage;  // its pixels (the selection is tinted into a copy)
    FCacheScale: Double;
    FCacheChanges: Integer;
    FCacheOrder: TList;             // pages with a cached bitmap, the most recently drawn last
    FPrefetch: TTimer;              // the pages next to those shown drawn ahead, once scrolling pauses
    { the text selected: on one page, characters FSelA..FSelB-1 }
    FSelPage, FSelA, FSelB, FSelAnchor: Integer;
    FSelecting: Boolean;
    { what Find found }
    FFoundPage, FFoundA, FFoundB: Integer;
    { an annotation picked (Delete, drag, colour) }
    FAnnPage, FAnnIndex: Integer;
    FDragAnn: Boolean;
    FMoveText: Boolean;             { the selection being dragged to a new place (FDragStart..FDragNow) }
    FDragStart, FDragNow: TPoint;
    { a shape, box or ink being drawn }
    FDrawing: Boolean;
    FDrawPage: Integer;
    FDrawStart, FDrawNow: TPoint;
    FInk: array of TPoint;
    { a picture, signature or mark to put where the page is clicked (or a box dragged out) }
    FPlacing: TLedPdfPlace;
    FPlaceRGBA, FPlaceJpeg: RawByteString;
    FPlaceW, FPlaceH: Integer;
    FPlaceSig: TLedSignature;       { (one of FSigs, or FNewSig) }
    FPlaceDown: Boolean;
    FGhostPage: Integer;            { where it would go, shown while the mouse is over a page }
    FGhost: TRect;
    FSigs: TObjectList;             { the signatures kept }
    FNewSig: TLedSignature;         { one made and not kept }
    FPictureBtn, FSignBtn, FStampBtn, FLinkBtn: TToolButton;
    FSignMenu, FStampMenu: TPopupMenu;
    { the annotation picked being resized by a corner (0 top left, 1 top right, 2 bottom right, 3 bottom left) }
    FResizing: Integer;
    { a form field being typed into }
    FFieldEdit: TEdit;
    FFieldMemo: TMemo;
    FFieldCombo: TComboBox;
    FFieldIndex: Integer;
    FSavedChanges: Integer;
    FOnChange: TNotifyEvent;
    FOnStatus: TNotifyEvent;
    FLastWhy: string;
    procedure BuildTools;
    procedure ToolClick(Sender: TObject);
    procedure ZoomChange(Sender: TObject);
    procedure PresentClick(Sender: TObject);
    procedure BuildZoomBar;
    procedure ZoomSliderChanged(Sender: TObject);
    procedure ZoomInClicked(Sender: TObject);
    procedure ZoomOutClicked(Sender: TObject);
    procedure ShowZoom;
    procedure RememberZoom;
    procedure ScrollChange(Sender: TObject);
    procedure FindKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FindClose(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure MenuCopy(Sender: TObject);
    procedure MenuMark(Sender: TObject);
    procedure MenuEditText(Sender: TObject);
    procedure MenuDeleteAnn(Sender: TObject);
    procedure MenuColorAnn(Sender: TObject);
    procedure MenuNoteText(Sender: TObject);
    procedure FieldDone(Sender: TObject);
    procedure FieldKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FieldComboSelect(Sender: TObject);
    procedure SetTool(AValue: TLedPdfTool);
    procedure Relayout;
    procedure UpdateBars;
    procedure ClearCache;
    function DocHeight: Integer;
    function PageLeft(APage: Integer): Integer;
    function PageRectOnView(APage: Integer): TRect;
    function PageAt(X, Y: Integer; out PX, PY: Double): Integer;
    function ToView(APage: Integer; PX, PY: Double): TPoint;
    function Chars(APage: Integer): TLedPdfCharArray;
    function CharAt(APage: Integer; PX, PY: Double; ANearest: Boolean): Integer;
    procedure DrawPage(C: TCanvas; APage: Integer; const R, AClip: TRect);
    procedure KickPrefetch;
    procedure PrefetchTick(Sender: TObject);
    function PageImage(APage: Integer): TLazIntfImage;
    procedure Tint(Img: TLazIntfImage; APage, AFrom, ATo: Integer; AColor: TColor; AOffX, AOffY: Integer);
    procedure Changed;
    procedure Status;
    procedure ScrollTo(APage: Integer; PY: Double);
    procedure MarkSelection(AKind: Integer);
    function SelectionQuads(out Q: TDoubleDynArray): Integer;
    procedure CancelField;
    procedure StartField(AField: Integer; APage: Integer);
    function AskText(const ATitle, APrompt: string; var AText: string; AMulti: Boolean): Boolean;
    function PenColor: UInt32;
    procedure FindNext(AForward: Boolean);
    procedure SetScaleKeep(AScale: Double);
    procedure ViewMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure ViewMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewDblClick;
    procedure ViewTripleClick;
    function Lines(APage: Integer): TLedPdfSpanArray;
    function Blocks(APage: Integer): TLedPdfSpanArray;
    function BlockAt(APage, AChar: Integer): Integer;
    procedure BlockRange(APage, ABlock: Integer; ASkipMark: Boolean; out AFrom, ATo: Integer);
    function EditableText(APage, AFrom, ATo: Integer): string;
    function OnSelection(APage: Integer; PX, PY: Double): Boolean;
    procedure MenuEditParagraph(Sender: TObject);
    procedure ViewKey(var Key: Word; Shift: TShiftState);
    procedure PictureClick(Sender: TObject);
    procedure SignClick(Sender: TObject);
    procedure SignMenuPopup(Sender: TObject);
    procedure SignItemClick(Sender: TObject);
    procedure SignNewClick(Sender: TObject);
    procedure SignForgetClick(Sender: TObject);
    procedure StampClick(Sender: TObject);
    procedure StampItemClick(Sender: TObject);
    procedure LinkClick(Sender: TObject);
    procedure StartPlacing(AKind: TLedPdfPlace);
    procedure StopPlacing;
    function PlaceBox(APage: Integer; const AFrom, ATo: TPoint; out X0, Y0, X1, Y1: Double): Boolean;
    function PlaceAspect: Double;
    function Resizable(APage, AIndex: Integer; out AKeepAspect: Boolean): Boolean;
    function PickedViewRect(out R: TRect): Boolean;
    function HandleAt(X, Y: Integer): Integer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { the file's bytes opened as pages; False (and why) when they cannot be }
    function Load(const ABytes: RawByteString; const AFileName: string; out AWhy: string): Boolean;
    { the file as it was with the changes appended: what is saved }
    function Export: RawByteString;
    procedure MarkSaved;
    function Modified: Boolean;
    function PageCount: Integer;
    function CurrentPage: Integer;
    procedure GoToPage(APage: Integer);
    function StatusText: string;
    function SelAvail: Boolean;
    function SelectedText: string;
    procedure CopyToClipboard;
    procedure SelectAll;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    procedure Undo;
    procedure Redo;
    procedure ShowFind;
    procedure ZoomBy(AFactor: Double);
    procedure ZoomFitWidth;
    { the pages full screen, one at a time (F5: from the first; Shift+F5, the button: from the one shown) }
    procedure Present(FromCurrent: Boolean);
    { the text selected marked: PD_ANNOT_HIGHLIGHT, _UNDERLINE, _STRIKEOUT or _SQUIGGLY, in the tool's colour }
    procedure MarkSelectionAs(AKind: Integer);
    { the text found, from the start of APage on: True if it was (the page shows it, it is selected) }
    function FindText(const AText: string; AFromPage: Integer = 0): Boolean;
    { the paragraph (block) at a point of the view selected (ASkipMark: less a list item's mark); False if no text }
    function SelectParagraphAt(X, Y: Integer; ASkipMark: Boolean): Boolean;
    { the selection as text to edit (a block's wrapped lines joined) }
    function SelectionEditText: string;
    { the selection written again as AText (a '\n' a new line); False if it could not be }
    function ReplaceSelection(const AText: string): Boolean;
    { the selection moved by (DX, DY) points on the page (y down), each glyph as it was; False if it could not be }
    function MoveSelection(DX, DY: Double): Boolean;
    property Tool: TLedPdfTool read FTool write SetTool;
    { Insert: a picture (RGBA pixels, or a JPEG's own bytes) in a box on a page, as shown (points, y down); the new
      annotation's index, picked, or -1 }
    function PlacePicture(APage: Integer; X0, Y0, X1, Y1: Double; const ARGBA, AJpeg: RawByteString;
      AW, AH: Integer): Integer;
    { a signature in a box: its strokes drawn as ink, or its picture }
    function PlaceSignature(S: TLedSignature; APage: Integer; X0, Y0, X1, Y1: Double): Integer;
    { a check mark, a cross, a dot or today's date in a box }
    function PlaceMark(AKind: TLedPdfPlace; APage: Integer; X0, Y0, X1, Y1: Double): Integer;
    { a link over a box: to a web address (mailto: too), or '#page=N' }
    function PlaceLink(APage: Integer; X0, Y0, X1, Y1: Double; const AUri: string): Integer;
    { the text selected made a link (a box a line); False if nothing is selected or the address is empty }
    function LinkSelection(const AUri: string): Boolean;
    { an annotation's box (as shown) set: what it draws scaled into it }
    function ResizeAnnotation(APage, AIndex: Integer; X0, Y0, X1, Y1: Double): Boolean;
    { a picture file put on the page where it is clicked next (False: it cannot be read) }
    function InsertPictureFile(const AFileName: string): Boolean;
    { the clipboard's picture put on the page where it is clicked next (False: it has none) }
    function PasteFromClipboard: Boolean;
    { a point of a page (points, as shown) on the view }
    function PageToView(APage: Integer; PX, PY: Double): TPoint;
    property Placing: TLedPdfPlace read FPlacing;
    property PickedPage: Integer read FAnnPage;
    property PickedIndex: Integer read FAnnIndex;
    property Scale: Double read FScale;
    property View: TLedPdfView read FView;
    property LastWhy: string read FLastWhy;
    {$IFDEF LED_PARADE}
    property Pdf: Ppd_pdfr read FPdf;
    {$ENDIF}
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnStatus: TNotifyEvent read FOnStatus write FOnStatus;
  end;

implementation

uses
  Clipbrd, Math, StrUtils, Led.UI.Dpi, Led.Core.Prefs, Led.UI.Icons;

{ the zoom slider's positions: 0..100 is 10%..100%, 100..200 is 100%..500%, as under a Word document }
function SliderToZoom(V: Integer): Double;
begin
  if V <= 100 then
    Result := (10 + V * 0.9) / 100
  else
    Result := (100 + (V - 100) * 4) / 100;
end;

function ZoomToSlider(Z: Double): Integer;
begin
  Z := Z * 100;
  if Z <= 100 then
    Result := Round((Z - 10) / 0.9)
  else
    Result := 100 + Round((Z - 100) / 4);
  Result := EnsureRange(Result, 0, 200);
end;

{ the zoom a Word document opens at (the last one chosen, 110% to begin with), as pixels a point; 100% is 96 dpi }
function OpeningScale: Double;
begin
  Result := EnsureRange(LedPrefs.GetInt(LedPrefVisualZoom, 110), 10, 500) / 100 * 96 / 72;
end;

const
  PageGap = 12;

function LedPdfFileName(const AFileName: string): Boolean;
begin
  Result := LowerCase(ExtractFileExt(AFileName)) = '.pdf';
end;

function LedPdfAvailable: Boolean;
begin
  Result := {$IFDEF LED_PARADE}True{$ELSE}False{$ENDIF};
end;

{ ------------------------------------------------------------------ }
{ the view                                                           }
{ ------------------------------------------------------------------ }

constructor TLedPdfView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque, csTripleClicks];
  TabStop := True;
  DoubleBuffered := True;
  Color := $00808080;
end;

procedure TLedPdfView.Paint;
var
  i: Integer;
  R, Clip: TRect;
begin
  { only the part asked for: after a scroll, the strip that came into view }
  Clip := Canvas.ClipRect;
  if (Clip.Right <= Clip.Left) or (Clip.Bottom <= Clip.Top) then Clip := ClientRect;
  Canvas.Brush.Color := $00707070;
  Canvas.FillRect(Clip);
  if FPane = nil then Exit;
  for i := 0 to FPane.PageCount - 1 do
  begin
    R := FPane.PageRectOnView(i);
    if R.Bottom + 3 < Clip.Top then Continue;
    if R.Top > Clip.Bottom then Break;
    FPane.DrawPage(Canvas, i, R, Clip);
  end;
  FPane.KickPrefetch;
end;

procedure TLedPdfView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
  if FPane <> nil then FPane.ViewMouseDown(Button, Shift, X, Y);
end;

procedure TLedPdfView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FPane <> nil then FPane.ViewMouseMove(Shift, X, Y);
end;

procedure TLedPdfView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FPane <> nil then FPane.ViewMouseUp(Button, Shift, X, Y);
end;

function TLedPdfView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if FPane = nil then Exit;
  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then FPane.ZoomBy(1.1) else FPane.ZoomBy(1 / 1.1);
  end
  else if ssShift in Shift then
    FPane.FHBar.Position := FPane.FHBar.Position - WheelDelta
  else
    FPane.FVBar.Position := FPane.FVBar.Position - WheelDelta;
end;

procedure TLedPdfView.DblClick;
begin
  inherited DblClick;
  if FPane <> nil then FPane.ViewDblClick;
end;

procedure TLedPdfView.TripleClick;
begin
  inherited TripleClick;
  if FPane <> nil then FPane.ViewTripleClick;
end;

procedure TLedPdfView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if FPane <> nil then FPane.ViewKey(Key, Shift);
  if Key <> 0 then inherited KeyDown(Key, Shift);
end;

procedure TLedPdfView.Resize;
begin
  inherited Resize;
  if FPane <> nil then FPane.Relayout;
end;

{ ------------------------------------------------------------------ }
{ the pane                                                           }
{ ------------------------------------------------------------------ }

constructor TLedPdfPane.Create(AOwner: TComponent);
var
  Item: TMenuItem;
  B: TButton;

  procedure AddItem(const ACaption: string; AHandler: TNotifyEvent; ATag: Integer = 0);
  begin
    Item := TMenuItem.Create(FMenu);
    Item.Caption := ACaption;
    Item.OnClick := AHandler;
    Item.Tag := ATag;
    FMenu.Items.Add(Item);
  end;

begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  FScale := 96 / 72 * 1.1;
  FFit := 3;
  FFitCap := FScale;
  FSelPage := -1;
  FFoundPage := -1;
  FAnnPage := -1;
  FFieldIndex := -1;
  FResizing := -1;
  FGhostPage := -1;
  FSigs := TObjectList.Create(True);
  FCacheOrder := TList.Create;
  FPrefetch := TTimer.Create(Self);
  FPrefetch.Enabled := False;
  FPrefetch.Interval := 120;
  FPrefetch.OnTimer := @PrefetchTick;
  BuildTools;

  FFindBar := TPanel.Create(Self);
  FFindBar.Parent := Self;
  FFindBar.Align := alTop;
  FFindBar.Height := LedScale96(30);
  FFindBar.BevelOuter := bvNone;
  FFindBar.Visible := False;
  FFindEdit := TEdit.Create(FFindBar);
  FFindEdit.Parent := FFindBar;
  FFindEdit.Left := LedScale96(6);
  FFindEdit.Top := LedScale96(3);
  FFindEdit.Width := LedScale96(260);
  FFindEdit.TextHint := 'Find in the PDF';
  FFindEdit.OnKeyDown := @FindKey;
  B := TButton.Create(FFindBar);
  B.Parent := FFindBar;
  B.Caption := 'Close';
  B.Left := FFindEdit.Left + FFindEdit.Width + LedScale96(6);
  B.Top := LedScale96(2);
  B.AutoSize := True;
  B.OnClick := @FindClose;
  FFindNote := TLabel.Create(FFindBar);
  FFindNote.Parent := FFindBar;
  FFindNote.Left := B.Left + LedScale96(70);
  FFindNote.Top := LedScale96(7);
  FFindNote.Caption := '';

  FVBar := TScrollBar.Create(Self);
  FVBar.Kind := sbVertical;
  FVBar.Parent := Self;
  FVBar.Align := alRight;
  FVBar.OnChange := @ScrollChange;
  FHBar := TScrollBar.Create(Self);
  FHBar.Kind := sbHorizontal;
  FHBar.Parent := Self;
  FHBar.Align := alBottom;
  FHBar.OnChange := @ScrollChange;
  BuildZoomBar;

  FView := TLedPdfView.Create(Self);
  FView.FPane := Self;
  FView.Parent := Self;
  FView.Align := alClient;

  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := @MenuPopup;
  AddItem('&Copy', @MenuCopy);
  AddItem('&Highlight', @MenuMark, PD_ANNOT_HIGHLIGHT);
  AddItem('&Underline', @MenuMark, PD_ANNOT_UNDERLINE);
  AddItem('&Strike Out', @MenuMark, PD_ANNOT_STRIKEOUT);
  AddItem('S&quiggly', @MenuMark, PD_ANNOT_SQUIGGLY);
  AddItem('&Edit Text...', @MenuEditText);
  AddItem('-', nil);
  AddItem('Edit &Paragraph...', @MenuEditParagraph);
  AddItem('-', nil);
  AddItem('Note &Text...', @MenuNoteText);
  AddItem('Annotation C&olour...', @MenuColorAnn);
  AddItem('&Delete Annotation', @MenuDeleteAnn);
  FView.PopupMenu := FMenu;
end;

destructor TLedPdfPane.Destroy;
begin
  FreeAndNil(FPrefetch);
  ClearCache;
  FCacheOrder.Free;
  FSigs.Free;
  FNewSig.Free;
  {$IFDEF LED_PARADE}
  if FPdf <> nil then pd_pdfr_free(FPdf);
  FPdf := nil;
  {$ENDIF}
  inherited Destroy;
end;

procedure TLedPdfPane.BuildTools;
const
  Names: array[TLedPdfTool] of string = ('Select', 'Highlight', 'Underline', 'Strike', 'Squiggly', 'Note',
    'Text Box', 'Draw', 'Rectangle', 'Ellipse', 'Line', 'Arrow');
  { the ribbon's own pictures where it has them (highlight, underline, strike), drawn ones in its style else }
  Icons: array[TLedPdfTool] of string = ('pdfselect', 'highlight', 'fmtunderline', 'fmtstrike', 'pdfsquiggly',
    'pdfnote', 'pdftextbox', 'pdfink', 'pdfrect', 'pdfellipse', 'pdfline', 'pdfarrow');
  Hints: array[TLedPdfTool] of string = ('Select text (a third click: a paragraph; drag the selection to move it), ' +
    'links, form fields and annotations',
    'Highlight text: drag over it', 'Underline text', 'Strike text out', 'A wavy underline',
    'A sticky note: click where it goes', 'A box of text: drag it out', 'Draw freehand',
    'A rectangle: drag it out', 'An ellipse: drag it out', 'A line: drag it out', 'An arrow: drag it out');
var
  T: TLedPdfTool;
  B: TToolButton;
  Sep: TToolButton;
  IconNames: array[0..Ord(High(TLedPdfTool)) + 5] of string;
  Mi: TMenuItem;

  function InsertButton(ALeft, AImage: Integer; const AHint: string; AMenu: TPopupMenu;
    AClick: TNotifyEvent): TToolButton;
  begin
    Result := TToolButton.Create(FTools);
    Result.Left := ALeft;
    Result.Parent := FTools;
    Result.ImageIndex := AImage;
    Result.Hint := AHint;
    Result.ShowHint := True;
    Result.OnClick := AClick;
    if AMenu <> nil then
    begin
      Result.Style := tbsDropDown;
      Result.DropdownMenu := AMenu;
    end
    else
      Result.Style := tbsButton;
  end;

  procedure StampItem(const ACaption: string; AKind: TLedPdfPlace);
  begin
    Mi := TMenuItem.Create(FStampMenu);
    Mi.Caption := ACaption;
    Mi.Tag := Ord(AKind);
    Mi.OnClick := @StampItemClick;
    FStampMenu.Items.Add(Mi);
  end;

begin
  FTools := TToolBar.Create(Self);
  FTools.Parent := Self;
  FTools.Align := alTop;
  FToolImages := TImageList.Create(Self);
  FToolImages.Width := LedScale96(20);
  FToolImages.Height := LedScale96(20);
  for T := Low(TLedPdfTool) to High(TLedPdfTool) do
    IconNames[Ord(T)] := Icons[T];
  IconNames[Ord(High(TLedPdfTool)) + 1] := 'pdfpresent';
  IconNames[Ord(High(TLedPdfTool)) + 2] := 'insertpicture';
  IconNames[Ord(High(TLedPdfTool)) + 3] := 'pdfsign';
  IconNames[Ord(High(TLedPdfTool)) + 4] := 'pdfstamp';
  IconNames[Ord(High(TLedPdfTool)) + 5] := 'insertlink';
  LedBuildIconList(FToolImages, IconNames, clBtnText);
  FTools.Images := FToolImages;
  FTools.ShowCaptions := False;
  FTools.ButtonWidth := LedScale96(28);
  FTools.ButtonHeight := LedScale96(28);
  FTools.AutoSize := True;
  FTools.EdgeBorders := [];
  LedStyleToolBar(FTools);
  for T := Low(TLedPdfTool) to High(TLedPdfTool) do
  begin
    B := TToolButton.Create(FTools);
    B.Left := 1000 * (Ord(T) + 1);
    B.Parent := FTools;
    B.Caption := Names[T];
    B.ImageIndex := Ord(T);
    B.Hint := Names[T] + ': ' + Hints[T];
    B.ShowHint := True;
    B.Style := tbsCheck;
    B.Tag := Ord(T);
    B.OnClick := @ToolClick;
    FToolButtons[T] := B;
    if T = ptInk then
    begin
      Sep := TToolButton.Create(FTools);
      Sep.Left := 1000 * (Ord(T) + 1) + 500;
      Sep.Parent := FTools;
      Sep.Style := tbsDivider;
    end;
  end;
  FToolButtons[ptSelect].Down := True;

  { Insert: a picture, a signature, a mark -- put where the page is clicked next }
  Sep := TToolButton.Create(FTools);
  Sep.Left := 1000 * (Ord(High(TLedPdfTool)) + 1) + 500;
  Sep.Parent := FTools;
  Sep.Style := tbsDivider;
  FSignMenu := TPopupMenu.Create(Self);
  FSignMenu.OnPopup := @SignMenuPopup;
  FStampMenu := TPopupMenu.Create(Self);
  StampItem('Check Mark ✓', ppCheck);
  StampItem('Cross ✗', ppCross);
  StampItem('Dot ●', ppDot);
  StampItem('Today''s Date', ppDate);
  FPictureBtn := InsertButton(Sep.Left + 100, Ord(High(TLedPdfTool)) + 2,
    'Picture: a picture from a file, put where you click (or drag out its box); Ctrl+V pastes one', nil,
    @PictureClick);
  FSignBtn := InsertButton(Sep.Left + 200, Ord(High(TLedPdfTool)) + 3,
    'Sign: your signature (drawn, typed or a picture of it) put where you click; the arrow for others and a new ' +
    'one. A picture of a signature, as one signed on paper: not a certificate signature', FSignMenu, @SignClick);
  FStampBtn := InsertButton(Sep.Left + 300, Ord(High(TLedPdfTool)) + 4,
    'Mark: a check mark, a cross, a dot or today''s date, put where you click (Esc when done)', FStampMenu,
    @StampClick);
  FLinkBtn := InsertButton(Sep.Left + 400, Ord(High(TLedPdfTool)) + 5,
    'Link: the text selected, or a box you drag out, made a link to a web page or to a page of this file', nil,
    @LinkClick);

  FColorBtn := TColorButton.Create(FTools);
  FColorBtn.Parent := FTools;
  FColorBtn.Width := LedScale96(40);
  FColorBtn.ButtonColor := RGBToColor(255, 220, 0);
  FColorBtn.Hint := 'The colour of what the tools make';
  FColorBtn.ShowHint := True;
  FColorBtn.Left := FLinkBtn.Left + FLinkBtn.Width + 1;
  { the pages full screen }
  B := TToolButton.Create(FTools);
  B.Left := 900;   { (before the tools: a reader's first button) }
  B.Parent := FTools;
  B.Style := tbsButton;
  B.ImageIndex := Ord(High(TLedPdfTool)) + 1;
  B.Hint := 'Present: the pages full screen, from this one (F5 from the first, Shift+F5 from this one; Esc ends)';
  B.ShowHint := True;
  B.OnClick := @PresentClick;
  B.Name := 'PdfPresentBtn';

  FZoomBox := TComboBox.Create(FTools);
  FZoomBox.Parent := FTools;
  FZoomBox.Width := LedScale96(90);
  FZoomBox.Style := csDropDownList;
  FZoomBox.Items.CommaText := '"Fit width","Fit page",50%,75%,100%,110%,125%,150%,200%,300%,400%';
  FZoomBox.ItemIndex := 5;
  FZoomBox.OnChange := @ZoomChange;
  FZoomBox.Left := FColorBtn.Left + FColorBtn.Width + 1;
end;

procedure TLedPdfPane.ToolClick(Sender: TObject);
begin
  SetTool(TLedPdfTool(TToolButton(Sender).Tag));
  { text selected, then a marking tool: the mark made on what is selected }
  if (FTool in [ptHighlight, ptUnderline, ptStrikeOut, ptSquiggly]) and SelAvail then
  begin
    case FTool of
      ptHighlight: MarkSelection(PD_ANNOT_HIGHLIGHT);
      ptUnderline: MarkSelection(PD_ANNOT_UNDERLINE);
      ptStrikeOut: MarkSelection(PD_ANNOT_STRIKEOUT);
      ptSquiggly: MarkSelection(PD_ANNOT_SQUIGGLY);
    end;
  end;
  if FView.CanFocus then FView.SetFocus;
end;

procedure TLedPdfPane.SetTool(AValue: TLedPdfTool);
var
  T: TLedPdfTool;
begin
  FTool := AValue;
  { one down at a time (the divider splits the buttons into two groups, so the toolbar's grouping does not) }
  for T := Low(TLedPdfTool) to High(TLedPdfTool) do
    FToolButtons[T].Down := T = AValue;
  if AValue = ptSelect then
    FView.Cursor := crDefault
  else if AValue in [ptHighlight, ptUnderline, ptStrikeOut, ptSquiggly] then
    FView.Cursor := crIBeam
  else
    FView.Cursor := crCross;
  { the colour a tool starts with: yellow to highlight, red to strike, blue for shapes }
  case AValue of
    ptHighlight: FColorBtn.ButtonColor := RGBToColor(255, 220, 0);
    ptUnderline, ptSquiggly: FColorBtn.ButtonColor := RGBToColor(0, 120, 0);
    ptStrikeOut: FColorBtn.ButtonColor := RGBToColor(220, 0, 0);
    ptNote: FColorBtn.ButtonColor := RGBToColor(255, 215, 0);
    ptTextBox: FColorBtn.ButtonColor := RGBToColor(0, 0, 128);
    ptInk, ptRect, ptEllipse, ptLine, ptArrow: FColorBtn.ButtonColor := RGBToColor(220, 0, 0);
  else
  end;
end;

function TLedPdfPane.PenColor: UInt32;
var
  C: TColor;
begin
  C := ColorToRGB(FColorBtn.ButtonColor);
  Result := (UInt32(Red(C)) shl 16) or (UInt32(Green(C)) shl 8) or UInt32(Blue(C));
end;

{ ---- Insert: pictures, signatures, marks ---- }

procedure TLedPdfPane.StartPlacing(AKind: TLedPdfPlace);
begin
  SetTool(ptSelect);
  FPlacing := AKind;
  FPlaceDown := False;
  FAnnPage := -1;
  FSelPage := -1;
  FView.Cursor := crCross;
  FView.Invalidate;
  if FView.CanFocus then FView.SetFocus;
  Status;
end;

procedure TLedPdfPane.StopPlacing;
begin
  FPlacing := ppNone;
  FPlaceDown := False;
  FGhostPage := -1;
  FView.Cursor := crDefault;
  FView.Invalidate;
  Status;
end;

{ width over height of what is placed (0: any) }
function TLedPdfPane.PlaceAspect: Double;
begin
  Result := 0;
  case FPlacing of
    ppPicture: if FPlaceH > 0 then Result := FPlaceW / FPlaceH;
    ppSignature: if FPlaceSig <> nil then Result := FPlaceSig.Aspect;
    ppCheck, ppCross, ppDot: Result := 1;
  else
  end;
end;

{ where it goes on the page (points, as shown): a box dragged out from AFrom to ATo (fitted to the picture's
  shape), or, a click, its own size round the point; False if it is off the page }
function TLedPdfPane.PlaceBox(APage: Integer; const AFrom, ATo: TPoint; out X0, Y0, X1, Y1: Double): Boolean;
var
  R: TRect;
  PX, PY, QX, QY, W, H, Asp, PW, PH: Double;
begin
  Result := False;
  X0 := 0; Y0 := 0; X1 := 0; Y1 := 0;
  if (APage < 0) or (APage >= PageCount) then Exit;
  R := PageRectOnView(APage);
  PW := FPageW[APage];
  PH := FPageH[APage];
  PX := (AFrom.X - R.Left) / FScale;
  PY := (AFrom.Y - R.Top) / FScale;
  QX := (ATo.X - R.Left) / FScale;
  QY := (ATo.Y - R.Top) / FScale;
  Asp := PlaceAspect;
  if (Abs(ATo.X - AFrom.X) > 4) or (Abs(ATo.Y - AFrom.Y) > 4) then
  begin   { dragged: the box, the picture's shape kept inside it from where the drag began }
    W := Abs(QX - PX);
    H := Abs(QY - PY);
    if Asp > 0 then
    begin
      if W / Max(H, 0.01) > Asp then W := H * Asp else H := W / Asp;
    end;
    if QX < PX then X0 := PX - W else X0 := PX;
    if QY < PY then Y0 := PY - H else Y0 := PY;
  end
  else
  begin   { clicked: its own size, centred there }
    case FPlacing of
      ppPicture:
        begin
          W := FPlaceW * 0.75;   { (a pixel a 96th of an inch) }
          H := FPlaceH * 0.75;
          if W > PW * 0.5 then begin H := H * PW * 0.5 / W; W := PW * 0.5; end;
          if H > PH * 0.5 then begin W := W * PH * 0.5 / H; H := PH * 0.5; end;
        end;
      ppSignature:
        begin   { two inches wide at most, three quarters of one tall }
          W := 144;
          H := W / Max(Asp, 0.01);
          if H > 54 then begin W := W * 54 / H; H := 54; end;
        end;
      ppCheck, ppCross:
        begin W := 12; H := 12; end;
      ppDot:
        begin W := 8; H := 8; end;
      ppDate:
        begin W := 11 * 0.55 * Length(DateToStr(Date)) + 8; H := 16; end;
      ppLink:
        begin W := 120; H := 16; end;
    else
      Exit;
    end;
    X0 := PX - W / 2;
    Y0 := PY - H / 2;
    if FPlacing in [ppDate, ppLink] then X0 := PX;
  end;
  if (W < 1) or (H < 1) then Exit;
  { on the page }
  X0 := Max(0, Min(X0, PW - W));
  Y0 := Max(0, Min(Y0, PH - H));
  X1 := X0 + W;
  Y1 := Y0 + H;
  Result := True;
end;

function TLedPdfPane.PlacePicture(APage: Integer; X0, Y0, X1, Y1: Double; const ARGBA, AJpeg: RawByteString;
  AW, AH: Integer): Integer;
begin
  Result := -1;
  {$IFDEF LED_PARADE}
  if (FPdf = nil) or (APage < 0) or (APage >= PageCount) then Exit;
  if AJpeg <> '' then
    Result := pd_pdfr_add_image(FPdf, APage, X0, Y0, X1, Y1, nil, AW, AH, @AJpeg[1], Length(AJpeg))
  else if Length(ARGBA) >= AW * AH * 4 then
    Result := pd_pdfr_add_image(FPdf, APage, X0, Y0, X1, Y1, PByte(@ARGBA[1]), AW, AH, nil, 0);
  if Result >= 0 then
  begin
    FAnnPage := APage;
    FAnnIndex := Result;
    Changed;
  end;
  {$ENDIF}
end;

function TLedPdfPane.PlaceSignature(S: TLedSignature; APage: Integer; X0, Y0, X1, Y1: Double): Integer;
{$IFDEF LED_PARADE}
var
  Pts: array of Double;
  Cnt: array of Int32;
  i, k, N: Integer;
  Sx, Sy: Double;
  C: TColor;
{$ENDIF}
begin
  Result := -1;
  {$IFDEF LED_PARADE}
  if (FPdf = nil) or (S = nil) or (APage < 0) or (APage >= PageCount) then Exit;
  if S.Kind = lskImage then
    Exit(PlacePicture(APage, X0, Y0, X1, Y1, S.RGBA, '', S.PixW, S.PixH));
  if (S.W <= 0) or (S.H <= 0) or (Length(S.Strokes) = 0) then Exit;
  Sx := (X1 - X0) / S.W;
  Sy := (Y1 - Y0) / S.H;
  N := 0;
  for i := 0 to High(S.Strokes) do Inc(N, Length(S.Strokes[i]) div 2);
  SetLength(Pts, 2 * N);
  SetLength(Cnt, Length(S.Strokes));
  N := 0;
  for i := 0 to High(S.Strokes) do
  begin
    Cnt[i] := Length(S.Strokes[i]) div 2;
    for k := 0 to Cnt[i] - 1 do
    begin
      Pts[2 * N] := X0 + S.Strokes[i][2 * k] * Sx;
      Pts[2 * N + 1] := Y0 + S.Strokes[i][2 * k + 1] * Sy;
      Inc(N);
    end;
  end;
  C := ColorToRGB(S.Color);
  { the pen as wide on the page as it was on the pad (3 of its pixels), within reason }
  Result := pd_pdfr_add_ink(FPdf, APage, @Pts[0], @Cnt[0], Length(Cnt),
    (UInt32(Red(C)) shl 16) or (UInt32(Green(C)) shl 8) or UInt32(Blue(C)), Max(0.6, Min(2.5, 3 * Sx)));
  if Result >= 0 then
  begin
    FAnnPage := APage;
    FAnnIndex := Result;
    Changed;
  end;
  {$ENDIF}
end;

function TLedPdfPane.PlaceMark(AKind: TLedPdfPlace; APage: Integer; X0, Y0, X1, Y1: Double): Integer;
{$IFDEF LED_PARADE}
var
  Pts: array[0..7] of Double;
  Cnt: array[0..1] of Int32;
  W, H, Pen: Double;
  S: string;
{$ENDIF}
begin
  Result := -1;
  {$IFDEF LED_PARADE}
  if (FPdf = nil) or (APage < 0) or (APage >= PageCount) then Exit;
  W := X1 - X0;
  H := Y1 - Y0;
  Pen := Max(0.8, Min(W, H) * 0.12);
  case AKind of
    ppCheck:
      begin   { a tick: down to the left, then a long stroke up }
        Pts[0] := X0 + 0.08 * W; Pts[1] := Y0 + 0.55 * H;
        Pts[2] := X0 + 0.38 * W; Pts[3] := Y0 + 0.88 * H;
        Pts[4] := X0 + 0.95 * W; Pts[5] := Y0 + 0.1 * H;
        Cnt[0] := 3;
        Result := pd_pdfr_add_ink(FPdf, APage, @Pts[0], @Cnt[0], 1, PenColor, Pen);
      end;
    ppCross:
      begin
        Pts[0] := X0 + 0.12 * W; Pts[1] := Y0 + 0.12 * H;
        Pts[2] := X1 - 0.12 * W; Pts[3] := Y1 - 0.12 * H;
        Pts[4] := X1 - 0.12 * W; Pts[5] := Y0 + 0.12 * H;
        Pts[6] := X0 + 0.12 * W; Pts[7] := Y1 - 0.12 * H;
        Cnt[0] := 2;
        Cnt[1] := 2;
        Result := pd_pdfr_add_ink(FPdf, APage, @Pts[0], @Cnt[0], 2, PenColor, Pen);
      end;
    ppDot:
      Result := pd_pdfr_add_shape(FPdf, APage, PD_ANNOT_CIRCLE, X0, Y0, X1, Y1, PenColor, $FF000000 or PenColor, 0.5);
    ppDate:
      begin
        S := DateToStr(Date);
        Result := pd_pdfr_add_text_box(FPdf, APage, X0, Y0, X1, Y1, PAnsiChar(S), 11, PenColor);
      end;
  else
  end;
  if Result >= 0 then
  begin
    FAnnPage := APage;
    FAnnIndex := Result;
    Changed;
  end;
  {$ENDIF}
end;

function TLedPdfPane.PlaceLink(APage: Integer; X0, Y0, X1, Y1: Double; const AUri: string): Integer;
begin
  Result := -1;
  {$IFDEF LED_PARADE}
  if (FPdf = nil) or (Trim(AUri) = '') then Exit;
  Result := pd_pdfr_add_link(FPdf, APage, X0, Y0, X1, Y1, PAnsiChar(Trim(AUri)));
  if Result >= 0 then Changed;
  {$ENDIF}
end;

function TLedPdfPane.LinkSelection(const AUri: string): Boolean;
var
  Q: TDoubleDynArray;
  i, N: Integer;
begin
  Result := False;
  if not SelAvail or (Trim(AUri) = '') then Exit;
  N := SelectionQuads(Q);
  for i := 0 to N - 1 do    { a quad: top left, top right, bottom left, bottom right }
    if PlaceLink(FSelPage, Min(Q[8 * i], Q[8 * i + 4]), Min(Q[8 * i + 1], Q[8 * i + 3]),
      Max(Q[8 * i + 2], Q[8 * i + 6]), Max(Q[8 * i + 5], Q[8 * i + 7]), AUri) >= 0 then
      Result := True;
end;

{ Link: over the selection when there is one, else a box dragged out (or clicked) next }
procedure TLedPdfPane.LinkClick(Sender: TObject);
var
  S: string;
begin
  if SelAvail then
  begin
    S := 'https://';
    if AskText('Link', 'Where it goes (a web address, mailto:..., or #page=3 for a page of this file):', S, False) and
       not LinkSelection(S) then
      MessageDlg('Link', 'That link could not be made.', mtWarning, [mbOK], 0);
    Exit;
  end;
  StartPlacing(ppLink);
end;

function TLedPdfPane.ResizeAnnotation(APage, AIndex: Integer; X0, Y0, X1, Y1: Double): Boolean;
begin
  Result := False;
  {$IFDEF LED_PARADE}
  if FPdf = nil then Exit;
  Result := pd_pdfr_annot_set_rect(FPdf, APage, AIndex, Min(X0, X1), Min(Y0, Y1), Max(X0, X1), Max(Y0, Y1)) = 0;
  if Result then Changed;
  {$ENDIF}
end;

function TLedPdfPane.PageToView(APage: Integer; PX, PY: Double): TPoint;
begin
  Result := ToView(APage, PX, PY);
end;

function TLedPdfPane.InsertPictureFile(const AFileName: string): Boolean;
var
  W, H: Integer;
  RGBA, J: RawByteString;
begin
  Result := LedLoadPictureRGBA(AFileName, W, H, RGBA, J);
  if not Result then Exit;
  FPlaceRGBA := RGBA;
  FPlaceJpeg := J;
  FPlaceW := W;
  FPlaceH := H;
  StartPlacing(ppPicture);
end;

function TLedPdfPane.PasteFromClipboard: Boolean;
var
  W, H: Integer;
  RGBA: RawByteString;
begin
  Result := LedClipboardPictureRGBA(W, H, RGBA);
  if not Result then Exit;
  FPlaceRGBA := RGBA;
  FPlaceJpeg := '';
  FPlaceW := W;
  FPlaceH := H;
  StartPlacing(ppPicture);
end;

procedure TLedPdfPane.PictureClick(Sender: TObject);
var
  Dlg: TOpenPictureDialog;
begin
  Dlg := TOpenPictureDialog.Create(Self);
  try
    Dlg.Title := 'Insert Picture';
    Dlg.Filter := 'Pictures|*.png;*.jpg;*.jpeg;*.bmp;*.gif|All files|*';
    if Dlg.Execute and not InsertPictureFile(Dlg.FileName) then
      MessageDlg('Insert Picture', 'That picture cannot be read.', mtWarning, [mbOK], 0);
  finally
    Dlg.Free;
  end;
end;

{ the button: the signature last made (or kept), else a new one }
procedure TLedPdfPane.SignClick(Sender: TObject);
begin
  if FSigs.Count = 0 then LedLoadSignatures(FSigs);
  if FNewSig <> nil then
    FPlaceSig := FNewSig
  else if FSigs.Count > 0 then
    FPlaceSig := TLedSignature(FSigs[FSigs.Count - 1])
  else
  begin
    SignNewClick(Sender);
    Exit;
  end;
  StartPlacing(ppSignature);
end;

procedure TLedPdfPane.SignMenuPopup(Sender: TObject);
var
  i: Integer;
  Mi: TMenuItem;
  B: TBitmap;
begin
  LedLoadSignatures(FSigs);
  FSignMenu.Items.Clear;
  for i := FSigs.Count - 1 downto 0 do
  begin
    Mi := TMenuItem.Create(FSignMenu);
    Mi.Caption := 'Signature ' + IntToStr(i + 1);
    B := TLedSignature(FSigs[i]).Thumb(LedScale96(96), LedScale96(32));
    try
      Mi.Bitmap := B;
    finally
      B.Free;
    end;
    Mi.Tag := i;
    Mi.OnClick := @SignItemClick;
    FSignMenu.Items.Add(Mi);
  end;
  if FSigs.Count > 0 then FSignMenu.Items.AddSeparator;
  Mi := TMenuItem.Create(FSignMenu);
  Mi.Caption := 'New Signature…';
  Mi.OnClick := @SignNewClick;
  FSignMenu.Items.Add(Mi);
  if FSigs.Count > 0 then
  begin
    Mi := TMenuItem.Create(FSignMenu);
    Mi.Caption := 'Forget the Signatures Kept';
    Mi.OnClick := @SignForgetClick;
    FSignMenu.Items.Add(Mi);
  end;
end;

procedure TLedPdfPane.SignItemClick(Sender: TObject);
var
  i: Integer;
begin
  i := TMenuItem(Sender).Tag;
  if (i < 0) or (i >= FSigs.Count) then Exit;
  FreeAndNil(FNewSig);
  FPlaceSig := TLedSignature(FSigs[i]);
  StartPlacing(ppSignature);
end;

procedure TLedPdfPane.SignNewClick(Sender: TObject);
var
  S: TLedSignature;
  Keep: Boolean;
begin
  S := LedNewSignature(GetParentForm(Self), Keep);
  if S = nil then Exit;
  FreeAndNil(FNewSig);
  if Keep and LedSaveSignature(S) then
  begin
    LedLoadSignatures(FSigs);
    S.Free;
    if FSigs.Count = 0 then Exit;
    FPlaceSig := TLedSignature(FSigs[FSigs.Count - 1]);
  end
  else
  begin
    FNewSig := S;
    FPlaceSig := S;
  end;
  StartPlacing(ppSignature);
end;

procedure TLedPdfPane.SignForgetClick(Sender: TObject);
var
  i: Integer;
begin
  if MessageDlg('Signatures', 'Forget the ' + IntToStr(FSigs.Count) + ' signature(s) kept on this computer?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  for i := 0 to FSigs.Count - 1 do
    LedForgetSignature(TLedSignature(FSigs[i]));
  if FPlacing = ppSignature then StopPlacing;
  FPlaceSig := nil;
  FSigs.Clear;
end;

procedure TLedPdfPane.StampClick(Sender: TObject);
begin
  if FStampBtn.Tag = 0 then FStampBtn.Tag := Ord(ppCheck);
  FColorBtn.ButtonColor := clBlack;
  StartPlacing(TLedPdfPlace(FStampBtn.Tag));
end;

procedure TLedPdfPane.StampItemClick(Sender: TObject);
begin
  FStampBtn.Tag := TMenuItem(Sender).Tag;   { the button then puts the same mark again }
  FColorBtn.ButtonColor := clBlack;
  StartPlacing(TLedPdfPlace(TMenuItem(Sender).Tag));
end;

{ the kinds a corner drag resizes (pictures and signatures keep their shape) }
function TLedPdfPane.Resizable(APage, AIndex: Integer; out AKeepAspect: Boolean): Boolean;
{$IFDEF LED_PARADE}
var
  A: pd_pdfr_annot;
{$ENDIF}
begin
  Result := False;
  AKeepAspect := False;
  {$IFDEF LED_PARADE}
  if (FPdf = nil) or (APage < 0) or (AIndex < 0) or (pd_pdfr_annot_get(FPdf, APage, AIndex, A) <> 0) then Exit;
  Result := A.kind in [PD_ANNOT_STAMP, PD_ANNOT_INK, PD_ANNOT_SQUARE, PD_ANNOT_CIRCLE, PD_ANNOT_FREETEXT,
    PD_ANNOT_LINE, PD_ANNOT_ARROW, PD_ANNOT_POLYGON, PD_ANNOT_POLYLINE, PD_ANNOT_LINK];
  AKeepAspect := A.kind in [PD_ANNOT_STAMP, PD_ANNOT_INK];
  {$ENDIF}
end;

{ the annotation picked, on the view: where it is, or where a drag or a corner is taking it }
function TLedPdfPane.PickedViewRect(out R: TRect): Boolean;
{$IFDEF LED_PARADE}
var
  A: pd_pdfr_annot;
  P0, P1: TPoint;
  Keep: Boolean;
  W, H, NW, NH: Integer;
{$ENDIF}
begin
  Result := False;
  R := Rect(0, 0, 0, 0);
  {$IFDEF LED_PARADE}
  if (FPdf = nil) or (FAnnPage < 0) or (FAnnIndex < 0) or
     (pd_pdfr_annot_get(FPdf, FAnnPage, FAnnIndex, A) <> 0) then Exit;
  P0 := ToView(FAnnPage, A.x0, A.y0);
  P1 := ToView(FAnnPage, A.x1, A.y1);
  R := Rect(P0.X, P0.Y, P1.X, P1.Y);
  if FDragAnn then
    OffsetRect(R, FDragNow.X - FDragStart.X, FDragNow.Y - FDragStart.Y)
  else if FResizing >= 0 then
  begin
    W := R.Right - R.Left;
    H := R.Bottom - R.Top;
    { the corner moved as far as the mouse has (the handle sits a little outside the frame) }
    case FResizing of
      0: begin Inc(R.Left, FDragNow.X - FDragStart.X); Inc(R.Top, FDragNow.Y - FDragStart.Y); end;
      1: begin Inc(R.Right, FDragNow.X - FDragStart.X); Inc(R.Top, FDragNow.Y - FDragStart.Y); end;
      2: begin Inc(R.Right, FDragNow.X - FDragStart.X); Inc(R.Bottom, FDragNow.Y - FDragStart.Y); end;
      3: begin Inc(R.Left, FDragNow.X - FDragStart.X); Inc(R.Bottom, FDragNow.Y - FDragStart.Y); end;
    end;
    Resizable(FAnnPage, FAnnIndex, Keep);
    if Keep and (W > 0) and (H > 0) and not (ssShift in GetKeyShiftState) then
    begin   { its shape kept: the new height from the new width, the corner opposite where it was }
      NW := Abs(R.Right - R.Left);
      NH := Round(NW * H / W);
      case FResizing of
        0, 1: R.Top := R.Bottom - NH;
        2, 3: R.Bottom := R.Top + NH;
      end;
    end;
    if R.Right < R.Left then begin W := R.Left; R.Left := R.Right; R.Right := W; end;
    if R.Bottom < R.Top then begin H := R.Top; R.Top := R.Bottom; R.Bottom := H; end;
  end;
  Result := True;
  {$ENDIF}
end;

{ the corner of the picked annotation's frame under (X, Y): 0..3, or -1 }
function TLedPdfPane.HandleAt(X, Y: Integer): Integer;
var
  R: TRect;
  Keep: Boolean;
  D: Integer;
  i: Integer;
  C: array[0..3] of TPoint;
begin
  Result := -1;
  if (FResizing >= 0) or FDragAnn or not Resizable(FAnnPage, FAnnIndex, Keep) or not PickedViewRect(R) then Exit;
  D := LedScale96(6);
  C[0] := Point(R.Left - 3, R.Top - 3);
  C[1] := Point(R.Right + 3, R.Top - 3);
  C[2] := Point(R.Right + 3, R.Bottom + 3);
  C[3] := Point(R.Left - 3, R.Bottom + 3);
  for i := 0 to 3 do
    if (Abs(X - C[i].X) <= D) and (Abs(Y - C[i].Y) <= D) then Exit(i);
end;

{ ---- loading ---- }

function TLedPdfPane.Load(const ABytes: RawByteString; const AFileName: string; out AWhy: string): Boolean;
{$IFDEF LED_PARADE}
var
  P: Ppd_pdfr;
  St: Integer;
  Pw: string;
  i: Integer;
  W, H: Double;
  Fresh: Boolean;
{$ENDIF}
begin
  Result := False;
  AWhy := '';
  {$IFDEF LED_PARADE}
  P := nil;
  Pw := '';
  St := pd_pdfr_open_memory(PAnsiChar(ABytes), Length(ABytes), nil, P);
  while (St = -6) and (P <> nil) and (pd_pdfr_encrypted(P) = 1) do
  begin
    pd_pdfr_free(P);
    P := nil;
    if not InputQuery('Password', ExtractFileName(AFileName) + ' needs a password to open:', True, Pw) then
    begin
      AWhy := 'the file needs a password';
      Exit;
    end;
    St := pd_pdfr_open_memory(PAnsiChar(ABytes), Length(ABytes), PAnsiChar(Pw), P);
  end;
  if St <> 0 then
  begin
    if P <> nil then
    begin
      AWhy := pd_pdfr_error(P);
      pd_pdfr_free(P);
    end
    else
      AWhy := 'not a PDF file';
    Exit;
  end;
  Fresh := FPdf = nil;   { not the file read again after a change on disk: that keeps its zoom and place }
  if FPdf <> nil then pd_pdfr_free(FPdf);
  FPdf := P;
  FFileName := AFileName;
  ClearCache;
  SetLength(FPageW, pd_pdfr_page_count(P));
  SetLength(FPageH, Length(FPageW));
  SetLength(FChars, Length(FPageW));
  SetLength(FCharsOk, Length(FPageW));
  SetLength(FLines, Length(FPageW));
  SetLength(FBlocks, Length(FPageW));
  SetLength(FCache, Length(FPageW));
  SetLength(FCacheImg, Length(FPageW));
  for i := 0 to High(FPageW) do
  begin
    pd_pdfr_page_size(P, i, W, H);
    FPageW[i] := W;
    FPageH[i] := H;
    FCharsOk[i] := False;
    FCache[i] := nil;
    FCacheImg[i] := nil;
  end;
  FSavedChanges := pd_pdfr_changes(P);
  FSelPage := -1;
  FFoundPage := -1;
  FAnnPage := -1;
  { as a Word document opens: at the zoom chosen last, centred, narrowed only to fit a narrower view }
  if Fresh then
  begin
    FFit := 3;
    FFitCap := OpeningScale;
    FScrollX := 0;
    FScrollY := 0;
  end;
  Relayout;
  FView.Invalidate;
  Status;
  Result := True;
  {$ELSE}
  AWhy := 'this LED was built without Parade';
  {$ENDIF}
end;

function TLedPdfPane.Export: RawByteString;
begin
  Result := '';
  {$IFDEF LED_PARADE}
  CancelField;
  if FPdf <> nil then Result := PdfSaveToString(FPdf);
  {$ENDIF}
end;

procedure TLedPdfPane.MarkSaved;
begin
  {$IFDEF LED_PARADE}
  if FPdf <> nil then FSavedChanges := pd_pdfr_changes(FPdf);
  {$ENDIF}
end;

function TLedPdfPane.Modified: Boolean;
begin
  Result := False;
  {$IFDEF LED_PARADE}
  if FPdf <> nil then Result := pd_pdfr_changes(FPdf) <> FSavedChanges;
  {$ENDIF}
end;

function TLedPdfPane.PageCount: Integer;
begin
  Result := Length(FPageW);
end;

{ ---- layout ---- }

procedure TLedPdfPane.Relayout;
var
  i, Y, CW: Integer;
  MaxW, MaxH: Double;
begin
  if FView = nil then Exit;
  CW := FView.ClientWidth;
  if (FFit > 0) and (PageCount > 0) and (CW > 50) then
  begin
    MaxW := 0;
    MaxH := 0;
    for i := 0 to PageCount - 1 do
    begin
      MaxW := Max(MaxW, FPageW[i]);
      MaxH := Max(MaxH, FPageH[i]);
    end;
    if FFit = 1 then
      FScale := (CW - 2 * PageGap) / Max(MaxW, 1)
    else if FFit = 3 then
      FScale := Min(FFitCap, (CW - 2 * PageGap) / Max(MaxW, 1))
    else
      FScale := Min((CW - 2 * PageGap) / Max(MaxW, 1), (FView.ClientHeight - 2 * PageGap) / Max(MaxH, 1));
    FScale := EnsureRange(FScale, 0.1, 16);
  end;
  SetLength(FPageTop, PageCount);
  Y := PageGap;
  for i := 0 to PageCount - 1 do
  begin
    FPageTop[i] := Y;
    Inc(Y, Round(FPageH[i] * FScale) + PageGap);
  end;
  UpdateBars;
  ShowZoom;
end;

function TLedPdfPane.DocHeight: Integer;
begin
  if PageCount = 0 then Exit(0);
  Result := FPageTop[PageCount - 1] + Round(FPageH[PageCount - 1] * FScale) + PageGap;
end;

procedure TLedPdfPane.UpdateBars;
var
  MaxW: Integer;
  i: Integer;
begin
  MaxW := 0;
  for i := 0 to PageCount - 1 do
    MaxW := Max(MaxW, Round(FPageW[i] * FScale) + 2 * PageGap);
  FVBar.SetParams(EnsureRange(FScrollY, 0, Max(0, DocHeight - FView.ClientHeight)), 0,
    Max(DocHeight, 1), Max(FView.ClientHeight, 1));
  FVBar.LargeChange := Max(FView.ClientHeight - 40, 20);
  FVBar.SmallChange := 40;
  FHBar.Visible := MaxW > FView.ClientWidth + 2;
  FHBar.SetParams(EnsureRange(FScrollX, 0, Max(0, MaxW - FView.ClientWidth)), 0, Max(MaxW, 1),
    Max(FView.ClientWidth, 1));
  FScrollY := FVBar.Position;
  FScrollX := FHBar.Position;
end;

procedure TLedPdfPane.ScrollChange(Sender: TObject);
var
  DX, DY: Integer;
begin
  DX := FHBar.Position - FScrollX;
  DY := FVBar.Position - FScrollY;
  FScrollY := FVBar.Position;
  FScrollX := FHBar.Position;
  CancelField;
  { what is on the screen moved over and only the strip that comes into view drawn: a whole repaint at each
    step of the wheel is a screenful of pixels sent again, slow over a remote display (x2go, ssh -X). A shape
    being drawn or an annotation dragged is in window coordinates, and is drawn whole }
  if (DX = 0) and (DY = 0) then
  else if FView.HandleAllocated and FView.IsVisible and not FDrawing and not FDragAnn and not FMoveText and
     (Abs(DX) < FView.ClientWidth) and (Abs(DY) < FView.ClientHeight) and
     ScrollWindowEx(FView.Handle, -DX, -DY, nil, nil, 0, nil, SW_INVALIDATE) then
  else
    FView.Invalidate;
  Status;
end;

procedure TLedPdfPane.KickPrefetch;
begin
  if FPrefetch = nil then Exit;
  FPrefetch.Enabled := False;
  FPrefetch.Enabled := True;
end;

{ one page near those shown, not yet drawn, drawn into the cache: the ones below first, then the one above }
procedure TLedPdfPane.PrefetchTick(Sender: TObject);
var
  First, Last, i, P: Integer;
  R: TRect;
  Order: array[0..3] of Integer;
begin
  FPrefetch.Enabled := False;
  {$IFDEF LED_PARADE}
  if (FPdf = nil) or (PageCount = 0) or not FView.IsVisible then Exit;
  First := -1;
  Last := -1;
  for i := 0 to PageCount - 1 do
  begin
    R := PageRectOnView(i);
    if R.Bottom < 0 then Continue;
    if R.Top > FView.ClientHeight then Break;
    if First < 0 then First := i;
    Last := i;
  end;
  if First < 0 then Exit;
  Order[0] := Last + 1;
  Order[1] := Last + 2;
  Order[2] := First - 1;
  Order[3] := Last + 3;
  for i := 0 to High(Order) do
  begin
    P := Order[i];
    if (P < 0) or (P >= PageCount) then Continue;
    if (FCacheScale = FScale) and (FCacheChanges = pd_pdfr_changes(FPdf)) and (FCacheImg[P] <> nil) then Continue;
    if Int64(Round(FPageW[P] * FScale)) * Round(FPageH[P] * FScale) > 8000000 then Continue;
    { drawn without taking the place of the pages shown: those are touched again after it }
    PageImage(P);
    for P := Last downto First do
      if FCacheImg[P] <> nil then PageImage(P);
    FPrefetch.Enabled := True;  { the next one, at the next pause }
    Exit;
  end;
  {$ENDIF}
end;

function TLedPdfPane.PageLeft(APage: Integer): Integer;
var
  W: Integer;
begin
  W := Round(FPageW[APage] * FScale);
  if W + 2 * PageGap <= FView.ClientWidth then
    Result := (FView.ClientWidth - W) div 2
  else
    Result := PageGap - FScrollX;
end;

function TLedPdfPane.PageRectOnView(APage: Integer): TRect;
begin
  Result.Left := PageLeft(APage);
  Result.Top := FPageTop[APage] - FScrollY;
  Result.Right := Result.Left + Round(FPageW[APage] * FScale);
  Result.Bottom := Result.Top + Round(FPageH[APage] * FScale);
end;

function TLedPdfPane.PageAt(X, Y: Integer; out PX, PY: Double): Integer;
var
  i: Integer;
  R: TRect;
begin
  Result := -1;
  PX := 0;
  PY := 0;
  for i := 0 to PageCount - 1 do
  begin
    R := PageRectOnView(i);
    if (Y >= R.Top - PageGap div 2) and (Y < R.Bottom + PageGap div 2) then
    begin
      PX := (X - R.Left) / FScale;
      PY := (Y - R.Top) / FScale;
      Exit(i);
    end;
  end;
end;

function TLedPdfPane.ToView(APage: Integer; PX, PY: Double): TPoint;
var
  R: TRect;
begin
  R := PageRectOnView(APage);
  Result := Point(R.Left + Round(PX * FScale), R.Top + Round(PY * FScale));
end;

function TLedPdfPane.CurrentPage: Integer;
var
  i, Mid: Integer;
begin
  Result := 0;
  Mid := FScrollY + FView.ClientHeight div 3;
  for i := 0 to PageCount - 1 do
    if FPageTop[i] <= Mid then Result := i else Break;
end;

procedure TLedPdfPane.GoToPage(APage: Integer);
begin
  if (APage < 0) or (APage >= PageCount) then Exit;
  FVBar.Position := FPageTop[APage] - PageGap;
end;

procedure TLedPdfPane.ScrollTo(APage: Integer; PY: Double);
var
  Y: Integer;
begin
  if (APage < 0) or (APage >= PageCount) then Exit;
  Y := FPageTop[APage] + Round(PY * FScale);
  if (Y < FScrollY + 20) or (Y > FScrollY + FView.ClientHeight - 40) then
    FVBar.Position := Y - FView.ClientHeight div 3;
end;

procedure TLedPdfPane.SetScaleKeep(AScale: Double);
var
  Page: Integer;
  Frac: Double;
begin
  AScale := EnsureRange(AScale, 0.1, 16);
  Page := CurrentPage;
  Frac := 0;
  if (PageCount > 0) and (FPageH[Page] > 0) then
    Frac := (FScrollY - FPageTop[Page]) / (FPageH[Page] * FScale);
  FScale := AScale;
  Relayout;
  if PageCount > 0 then
    FVBar.Position := FPageTop[Page] + Round(Frac * FPageH[Page] * FScale);
  CancelField;
  FView.Invalidate;
  Status;
end;

procedure TLedPdfPane.ZoomBy(AFactor: Double);
begin
  FFit := 0;
  SetScaleKeep(FScale * AFactor);
  RememberZoom;
end;

procedure TLedPdfPane.ZoomFitWidth;
begin
  FFit := 1;
  SetScaleKeep(FScale);
end;

procedure TLedPdfPane.BuildZoomBar;
var
  B: TSpeedButton;
begin
  FZoomBar := TPanel.Create(Self);
  FZoomBar.Parent := Self;
  FZoomBar.Align := alBottom;
  FZoomBar.Top := 30000;      { under the sideways scroll bar }
  FZoomBar.BevelOuter := bvNone;
  FZoomBar.Caption := '';
  FZoomBar.Height := LedScale96(24);
  FZoomLabel := TLabel.Create(Self);
  FZoomLabel.Parent := FZoomBar;
  FZoomLabel.Align := alRight;
  FZoomLabel.Layout := tlCenter;
  FZoomLabel.Alignment := taRightJustify;
  FZoomLabel.AutoSize := False;
  FZoomLabel.Width := LedScale96(48);
  FZoomLabel.BorderSpacing.Right := LedScale96(8);
  FZoomLabel.Caption := '110%';
  FZoomLabel.Name := 'PdfZoomPercent';
  B := TSpeedButton.Create(Self);
  B.Parent := FZoomBar;
  B.Align := alRight;
  B.Width := LedScale96(22);
  B.Caption := '+';
  B.Flat := True;
  B.Hint := 'Zoom in';
  B.ShowHint := True;
  B.OnClick := @ZoomInClicked;
  B.Left := 9000;
  FZoomSlider := TTrackBar.Create(Self);
  FZoomSlider.Parent := FZoomBar;
  FZoomSlider.Align := alRight;
  FZoomSlider.Width := LedScale96(160);
  FZoomSlider.Constraints.MinWidth := LedScale96(160);
  FZoomSlider.Left := 8000;
  FZoomSlider.Min := 0;
  FZoomSlider.Max := 200;
  FZoomSlider.Frequency := 100;
  FZoomSlider.TickStyle := tsNone;
  FZoomSlider.Position := ZoomToSlider(1.1);
  FZoomSlider.Hint := 'Zoom: 10% to 500%, 100% in the middle';
  FZoomSlider.ShowHint := True;
  FZoomSlider.OnChange := @ZoomSliderChanged;
  FZoomSlider.Name := 'PdfZoomSlider';
  B := TSpeedButton.Create(Self);
  B.Parent := FZoomBar;
  B.Align := alRight;
  B.Width := LedScale96(22);
  B.Caption := #$E2#$88#$92;    { minus }
  B.Flat := True;
  B.Hint := 'Zoom out';
  B.ShowHint := True;
  B.OnClick := @ZoomOutClicked;
  B.Left := 7000;
  FZoomLabel.Left := 10000;   { from the right: the percentage, +, the bar, - }
end;

procedure TLedPdfPane.ZoomSliderChanged(Sender: TObject);
begin
  if FZoomSliding then Exit;
  FFit := 0;
  SetScaleKeep(SliderToZoom(FZoomSlider.Position) * 96 / 72);
  RememberZoom;
end;

procedure TLedPdfPane.ZoomInClicked(Sender: TObject);
begin
  ZoomBy(1.25);
  if FView.CanFocus then FView.SetFocus;
end;

procedure TLedPdfPane.ZoomOutClicked(Sender: TObject);
begin
  ZoomBy(1 / 1.25);
  if FView.CanFocus then FView.SetFocus;
end;

{ the slider, the percentage and the box after any zoom }
procedure TLedPdfPane.ShowZoom;
var
  Pct: Integer;
begin
  if (FZoomSlider = nil) or (FZoomBox = nil) or FZoomSliding then Exit;
  FZoomSliding := True;
  try
    Pct := Round(FScale * 72 / 96 * 100);
    FZoomSlider.Position := ZoomToSlider(FScale * 72 / 96);
    FZoomLabel.Caption := IntToStr(Pct) + '%';
    if FFit = 1 then
      FZoomBox.ItemIndex := 0
    else if FFit = 2 then
      FZoomBox.ItemIndex := 1
    else
      FZoomBox.ItemIndex := FZoomBox.Items.IndexOf(IntToStr(Pct) + '%');
  finally
    FZoomSliding := False;
  end;
end;

{ a zoom chosen is the one the next document opens at, a PDF or a Word one }
procedure TLedPdfPane.RememberZoom;
begin
  LedPrefs.SetInt(LedPrefVisualZoom, EnsureRange(Round(FScale * 72 / 96 * 100), 10, 500));
end;

procedure TLedPdfPane.ZoomChange(Sender: TObject);
var
  S: string;
begin
  if FZoomSliding then Exit;
  S := FZoomBox.Text;
  if FZoomBox.ItemIndex = 0 then
    FFit := 1
  else if FZoomBox.ItemIndex = 1 then
    FFit := 2
  else
  begin
    FFit := 0;
    SetScaleKeep(StrToFloatDef(StringReplace(S, '%', '', []), 100) / 100 * 96 / 72);
    RememberZoom;
    if FView.CanFocus then FView.SetFocus;
    Exit;
  end;
  SetScaleKeep(FScale);
  if FView.CanFocus then FView.SetFocus;
end;

function TLedPdfPane.StatusText: string;
begin
  if PageCount = 0 then Exit('PDF');
  Result := Format('PDF  page %d of %d  %d%%', [CurrentPage + 1, PageCount, Round(FScale * 72 / 96 * 100)]);
  if SelAvail then
    Result := Result + Format('  %d characters selected', [FSelB - FSelA]);
end;

procedure TLedPdfPane.Status;
begin
  if Assigned(FOnStatus) then FOnStatus(Self);
end;

{ ---- drawing ---- }

procedure TLedPdfPane.ClearCache;
var
  i: Integer;
begin
  for i := 0 to High(FCache) do
  begin
    FreeAndNil(FCache[i]);
    FreeAndNil(FCacheImg[i]);
  end;
  FCacheOrder.Clear;
end;

{ a page's part drawn into an image of W x H pixels: the part from (OX, OY) of the page at the scale. A
  TLazIntfImage's pixels, whatever the widget set keeps its bitmaps as, are what Parade draws into }
function RenderImage(APdf: Pointer; APage: Integer; AScale: Double; OX, OY, W, H: Integer): TLazIntfImage;
{$IFDEF LED_PARADE}
var
  Flags: Int32;
{$ENDIF}
begin
  Result := TLazIntfImage.Create(W, H, [riqfRGB, riqfAlpha]);
  {$IFDEF LED_PARADE}
  Flags := 0;
  if Result.DataDescription.RedShift = 16 then Flags := PD_PDFR_BGRA;
  if (Result.PixelData <> nil) and (Result.DataDescription.BitsPerPixel = 32) then
    pd_pdfr_render(APdf, APage, AScale, OX, OY, Result.PixelData, W, H, Result.DataDescription.BytesPerLine, Flags);
  {$ENDIF}
end;

function ImageCopy(Src: TLazIntfImage): TLazIntfImage;
begin
  Result := TLazIntfImage.Create(Src.Width, Src.Height, [riqfRGB, riqfAlpha]);
  if (Result.PixelData <> nil) and (Src.PixelData <> nil) and
     (Result.DataDescription.BytesPerLine = Src.DataDescription.BytesPerLine) then
    Move(Src.PixelData^, Result.PixelData^, PtrInt(Src.DataDescription.BytesPerLine) * Src.Height);
end;

function ImageBitmap(Img: TLazIntfImage): TBitmap;
begin
  Result := TBitmap.Create;
  Result.LoadFromIntfImage(Img);
end;

function TLedPdfPane.PageImage(APage: Integer): TLazIntfImage;
var
  W, H, k: Integer;
begin
  Result := nil;
  {$IFDEF LED_PARADE}
  if FPdf = nil then Exit;
  if (FCacheScale <> FScale) or (FCacheChanges <> pd_pdfr_changes(FPdf)) then
  begin
    ClearCache;
    FCacheScale := FScale;
    FCacheChanges := pd_pdfr_changes(FPdf);
  end;
  if FCacheImg[APage] <> nil then
  begin
    k := FCacheOrder.IndexOf(Pointer(PtrInt(APage)));
    if k >= 0 then FCacheOrder.Move(k, FCacheOrder.Count - 1);
    Exit(FCacheImg[APage]);
  end;
  W := Round(FPageW[APage] * FScale);
  H := Round(FPageH[APage] * FScale);
  if (W <= 0) or (H <= 0) or (Int64(W) * H > 8000000) then Exit;  { too big to keep whole: drawn as shown }
  Result := RenderImage(FPdf, APage, FScale, 0, 0, W, H);
  FCacheImg[APage] := Result;
  FCache[APage] := ImageBitmap(Result);
  FCacheOrder.Add(Pointer(PtrInt(APage)));
  { kept within about 40 million pixels (twice: the pixels and the bitmap), the least recently drawn going first }
  while (FCacheOrder.Count > 1) and (Int64(FCacheOrder.Count) * W * H > 40000000) do
  begin
    k := PtrInt(FCacheOrder[0]);
    FreeAndNil(FCache[k]);
    FreeAndNil(FCacheImg[k]);
    FCacheOrder.Delete(0);
  end;
  {$ENDIF}
end;

{ characters AFrom..ATo-1 of a page tinted in Img (whose top left is the page's (AOffX, AOffY) pixel): the colour
  multiplied in, so the text stays readable }
procedure TLedPdfPane.Tint(Img: TLazIntfImage; APage, AFrom, ATo: Integer; AColor: TColor; AOffX, AOffY: Integer);
{$IFDEF LED_PARADE}
var
  C: TLedPdfCharArray;
  i, X, Y, X0, Y0, X1, Y1, Bpp, Stride: Integer;
  P: PByte;
  RR, GG, BB: Integer;
  RIdx, BIdx: Integer;
  Ls: TLedPdfSpanArray;
  k: Integer;
  FX0, FX1: Double;
{$ENDIF}
begin
  {$IFDEF LED_PARADE}
  C := Chars(APage);
  if AFrom < 0 then AFrom := 0;
  if ATo > Length(C) then ATo := Length(C);
  if (AFrom >= ATo) or (Img.PixelData = nil) then Exit;
  AColor := ColorToRGB(AColor);
  RR := Red(AColor);
  GG := Green(AColor);
  BB := Blue(AColor);
  Bpp := Img.DataDescription.BitsPerPixel div 8;
  Stride := Img.DataDescription.BytesPerLine;
  if Bpp < 3 then Exit;
  if Img.DataDescription.RedShift = 16 then
  begin
    RIdx := 2;
    BIdx := 0;
  end
  else
  begin
    RIdx := 0;
    BIdx := 2;
  end;
  { a band a line: from the first character chosen on it to the last, as tall as the line, not a box a character }
  Ls := Lines(APage);
  for k := 0 to High(Ls) do
  begin
    if (Ls[k].end_ <= AFrom) or (Ls[k].first >= ATo) then Continue;
    FX0 := 1e30;
    FX1 := -1e30;
    for i := Max(AFrom, Ls[k].first) to Min(ATo, Ls[k].end_) - 1 do
    begin
      if (C[i].flags <> 0) or (C[i].cp = 32) then
      begin
        { a space chosen between two words: the gap to the next one }
        if (C[i].flags and PD_PDFR_CHAR_NEWLINE = 0) and (i + 1 < Min(ATo, Ls[k].end_)) and (FX1 > -1e29) then
          FX1 := Max(FX1, C[i + 1].x0);
        Continue;
      end;
      FX0 := Min(FX0, C[i].x0);
      FX1 := Max(FX1, C[i].x1);
    end;
    if FX1 < FX0 then Continue;
    X0 := Max(Floor(FX0 * FScale) - AOffX, 0);
    Y0 := Max(Floor(Ls[k].y0 * FScale) - AOffY, 0);
    X1 := Min(Ceil(FX1 * FScale) - AOffX, Img.Width);
    Y1 := Min(Ceil(Ls[k].y1 * FScale) - AOffY, Img.Height);
    for Y := Y0 to Y1 - 1 do
    begin
      P := PByte(Img.PixelData) + PtrInt(Y) * Stride + PtrInt(X0) * Bpp;
      for X := X0 to X1 - 1 do
      begin
        P[RIdx] := P[RIdx] * RR div 255;
        P[1] := P[1] * GG div 255;
        P[BIdx] := P[BIdx] * BB div 255;
        Inc(P, Bpp);
      end;
    end;
  end;
  {$ENDIF}
end;

procedure TLedPdfPane.DrawPage(C: TCanvas; APage: Integer; const R, AClip: TRect);
var
  Img, TmpImg: TLazIntfImage;
  Tmp: TBitmap;
  Vis: TRect;
  i: Integer;
  {$IFDEF LED_PARADE}
  A: pd_pdfr_annot;
  {$ENDIF}
  P0, P1: TPoint;
  Tinted: Boolean;
  {$IFDEF LED_PARADE}
  Ls: TLedPdfSpanArray;
  Cs: TLedPdfCharArray;
  j: Integer;
  MX0, MX1: Double;
  HR: TRect;
  HKeep: Boolean;
  HD: Integer;
  {$ENDIF}
begin
  {$IFDEF LED_PARADE}
  if FPdf = nil then Exit;
  { the page's shadow }
  C.Brush.Color := $00505050;
  C.FillRect(Rect(R.Left + 3, R.Top + 3, R.Right + 3, R.Bottom + 3));
  Tinted := ((FSelPage = APage) and (FSelB > FSelA)) or ((FFoundPage = APage) and (FFoundB > FFoundA));
  Img := PageImage(APage);
  if Img <> nil then
  begin
    if Tinted then
    begin
      TmpImg := ImageCopy(Img);
      try
        if FFoundPage = APage then Tint(TmpImg, APage, FFoundA, FFoundB, RGBToColor(255, 170, 60), 0, 0);
        if FSelPage = APage then Tint(TmpImg, APage, FSelA, FSelB, RGBToColor(150, 190, 255), 0, 0);
        Tmp := ImageBitmap(TmpImg);
        try
          C.Draw(R.Left, R.Top, Tmp);
        finally
          Tmp.Free;
        end;
      finally
        TmpImg.Free;
      end;
    end
    else if FCache[APage] <> nil then
      C.Draw(R.Left, R.Top, FCache[APage]);
  end
  else
  begin
    { too large to keep: the part on the screen drawn now }
    Vis := R;
    if Vis.Left < AClip.Left then Vis.Left := AClip.Left;
    if Vis.Top < AClip.Top then Vis.Top := AClip.Top;
    if Vis.Right > AClip.Right then Vis.Right := AClip.Right;
    if Vis.Bottom > AClip.Bottom then Vis.Bottom := AClip.Bottom;
    if (Vis.Right > Vis.Left) and (Vis.Bottom > Vis.Top) then
    begin
      TmpImg := RenderImage(FPdf, APage, FScale, Vis.Left - R.Left, Vis.Top - R.Top, Vis.Right - Vis.Left,
        Vis.Bottom - Vis.Top);
      try
        if FFoundPage = APage then
          Tint(TmpImg, APage, FFoundA, FFoundB, RGBToColor(255, 170, 60), Vis.Left - R.Left, Vis.Top - R.Top);
        if FSelPage = APage then
          Tint(TmpImg, APage, FSelA, FSelB, RGBToColor(150, 190, 255), Vis.Left - R.Left, Vis.Top - R.Top);
        Tmp := ImageBitmap(TmpImg);
        try
          C.Draw(Vis.Left, Vis.Top, Tmp);
        finally
          Tmp.Free;
        end;
      finally
        TmpImg.Free;
      end;
    end;
  end;

  { the annotation picked: a dashed frame (where it is dragged to, while it is), its corners' handles when it can be
    resized }
  if (FAnnPage = APage) and (FAnnIndex >= 0) and (pd_pdfr_annot_get(FPdf, APage, FAnnIndex, A) = 0) and
     PickedViewRect(HR) then
  begin
    C.Brush.Style := bsClear;
    C.Pen.Color := RGBToColor(0, 90, 220);
    C.Pen.Style := psDash;
    C.Pen.Width := 1;
    C.Rectangle(HR.Left - 3, HR.Top - 3, HR.Right + 3, HR.Bottom + 3);
    C.Pen.Style := psSolid;
    if Resizable(APage, FAnnIndex, HKeep) then
    begin
      C.Brush.Style := bsSolid;
      C.Brush.Color := clWhite;
      HD := LedScale96(4);
      C.Rectangle(HR.Left - 3 - HD, HR.Top - 3 - HD, HR.Left - 3 + HD, HR.Top - 3 + HD);
      C.Rectangle(HR.Right + 3 - HD, HR.Top - 3 - HD, HR.Right + 3 + HD, HR.Top - 3 + HD);
      C.Rectangle(HR.Right + 3 - HD, HR.Bottom + 3 - HD, HR.Right + 3 + HD, HR.Bottom + 3 + HD);
      C.Rectangle(HR.Left - 3 - HD, HR.Bottom + 3 - HD, HR.Left - 3 + HD, HR.Bottom + 3 + HD);
    end;
    C.Brush.Style := bsSolid;
  end;

  { what Insert puts down: where it would go }
  if (FPlacing <> ppNone) and (FGhostPage = APage) then
  begin
    C.Brush.Style := bsClear;
    C.Pen.Color := RGBToColor(0, 90, 220);
    C.Pen.Style := psDot;
    C.Pen.Width := 1;
    C.Rectangle(FGhost);
    C.Pen.Style := psSolid;
    C.Brush.Style := bsSolid;
  end;

  { the selection being moved: its lines' outlines where they are going }
  if FMoveText and (FSelPage = APage) then
  begin
    Ls := Lines(APage);
    Cs := Chars(APage);
    C.Brush.Style := bsClear;
    C.Pen.Color := RGBToColor(0, 90, 220);
    C.Pen.Style := psDash;
    C.Pen.Width := 1;
    for i := 0 to High(Ls) do
    begin
      if (Ls[i].end_ <= FSelA) or (Ls[i].first >= FSelB) then Continue;
      MX0 := 1e30;
      MX1 := -1e30;
      for j := Max(FSelA, Ls[i].first) to Min(FSelB, Ls[i].end_) - 1 do
        if (Cs[j].flags = 0) and (Cs[j].cp <> 32) then
        begin
          MX0 := Min(MX0, Cs[j].x0);
          MX1 := Max(MX1, Cs[j].x1);
        end;
      if MX1 < MX0 then Continue;
      P0 := ToView(APage, MX0, Ls[i].y0);
      P1 := ToView(APage, MX1, Ls[i].y1);
      C.Rectangle(P0.X + FDragNow.X - FDragStart.X, P0.Y + FDragNow.Y - FDragStart.Y,
        P1.X + FDragNow.X - FDragStart.X, P1.Y + FDragNow.Y - FDragStart.Y);
    end;
    C.Pen.Style := psSolid;
    C.Brush.Style := bsSolid;
  end;

  { a shape or ink being drawn }
  if FDrawing and (FDrawPage = APage) then
  begin
    C.Brush.Style := bsClear;
    C.Pen.Color := FColorBtn.ButtonColor;
    C.Pen.Width := Max(1, Round(2 * FScale));
    case FTool of
      ptRect, ptTextBox:
        C.Rectangle(FDrawStart.X, FDrawStart.Y, FDrawNow.X, FDrawNow.Y);
      ptEllipse:
        C.Ellipse(FDrawStart.X, FDrawStart.Y, FDrawNow.X, FDrawNow.Y);
      ptLine, ptArrow:
        C.Line(FDrawStart.X, FDrawStart.Y, FDrawNow.X, FDrawNow.Y);
      ptInk:
        if Length(FInk) > 1 then
        begin
          C.MoveTo(FInk[0].X, FInk[0].Y);
          for i := 1 to High(FInk) do
            C.LineTo(FInk[i].X, FInk[i].Y);
        end;
    else
    end;
    C.Pen.Width := 1;
    C.Brush.Style := bsSolid;
  end;
  {$ENDIF}
end;

{ ---- text ---- }

function TLedPdfPane.Chars(APage: Integer): TLedPdfCharArray;
begin
  Result := nil;
  {$IFDEF LED_PARADE}
  if (FPdf = nil) or (APage < 0) or (APage >= PageCount) then Exit;
  if not FCharsOk[APage] then
  begin
    FChars[APage] := PdfPageChars(FPdf, APage);
    FLines[APage] := PdfPageSpans(FPdf, APage, PD_PDFR_LINES);
    FBlocks[APage] := PdfPageSpans(FPdf, APage, PD_PDFR_BLOCKS);
    FCharsOk[APage] := True;
  end;
  Result := FChars[APage];
  {$ENDIF}
end;

function TLedPdfPane.Lines(APage: Integer): TLedPdfSpanArray;
begin
  Result := nil;
  if (APage < 0) or (APage >= PageCount) then Exit;
  Chars(APage);
  Result := FLines[APage];
end;

function TLedPdfPane.Blocks(APage: Integer): TLedPdfSpanArray;
begin
  Result := nil;
  if (APage < 0) or (APage >= PageCount) then Exit;
  Chars(APage);
  Result := FBlocks[APage];
end;

{ the block character AChar is in; -1 none }
function TLedPdfPane.BlockAt(APage, AChar: Integer): Integer;
{$IFDEF LED_PARADE}
var
  B: TLedPdfSpanArray;
  i: Integer;
{$ENDIF}
begin
  Result := -1;
  {$IFDEF LED_PARADE}
  B := Blocks(APage);
  for i := 0 to High(B) do
    if (AChar >= B[i].first) and (AChar < B[i].end_) then Exit(i);
  {$ENDIF}
end;

{ a list item's mark: a bullet, a square, a dash, an arrow (the Symbol and Wingdings ones too) }
function IsListMark(Cp: UInt32): Boolean;
begin
  case Cp of
    $2022, $25AA, $25CF, $25E6, $25A0, $25A1, $2023, $2043, $2013, $2014, $27A2, $2713, $00B7, $F0B7, $F0A7, $F0D8,
    $F076, $F0FC, $F06E, $F071:
      Result := True;
  else
    Result := False;
  end;
end;

{ a block's characters, less the line break and spaces at its end (and, ASkipMark, a list item's mark and the spaces
  after it at its start: the mark stays when its text is written again) }
procedure TLedPdfPane.BlockRange(APage, ABlock: Integer; ASkipMark: Boolean; out AFrom, ATo: Integer);
{$IFDEF LED_PARADE}
var
  B: TLedPdfSpanArray;
  C: TLedPdfCharArray;
{$ENDIF}
begin
  AFrom := 0;
  ATo := 0;
  {$IFDEF LED_PARADE}
  B := Blocks(APage);
  C := Chars(APage);
  if (ABlock < 0) or (ABlock > High(B)) then Exit;
  AFrom := B[ABlock].first;
  ATo := Min(B[ABlock].end_, Length(C));
  while (ATo > AFrom) and ((C[ATo - 1].flags <> 0) or (C[ATo - 1].cp <= 32)) do Dec(ATo);
  while (AFrom < ATo) and ((C[AFrom].flags <> 0) or (C[AFrom].cp <= 32)) do Inc(AFrom);
  if ASkipMark and (AFrom < ATo) and (IsListMark(C[AFrom].cp) or
    (((C[AFrom].cp = Ord('-')) or (C[AFrom].cp = Ord('*'))) and (AFrom + 1 < ATo) and
     ((C[AFrom + 1].cp = 32) or (C[AFrom + 1].flags <> 0)))) then
  begin
    Inc(AFrom);
    while (AFrom < ATo) and ((C[AFrom].flags <> 0) or (C[AFrom].cp <= 32)) do Inc(AFrom);
  end;
  {$ENDIF}
end;

{ characters AFrom..ATo-1 as text to edit: a line break within a block where the line was full (the next word would
  not have fitted on it) a space, the text wrapping there again when it is written; one where the line stops short
  (an address's lines, a heading's) kept, as between blocks; a word broken by a hyphen at a line's end joined }
function TLedPdfPane.EditableText(APage, AFrom, ATo: Integer): string;
{$IFDEF LED_PARADE}
var
  C: TLedPdfCharArray;
  i, K: Integer;
  U: UnicodeString;
  Cp: UInt32;

  { the line break at character AAt only where its line was full }
  function Wrapped(AAt, ABlock: Integer): Boolean;
  var
    L, B: TLedPdfSpanArray;
    j, m, e: Integer;
    W: Double;
  begin
    Result := True;
    L := Lines(APage);
    B := Blocks(APage);
    for j := 0 to High(L) - 1 do
      if (AAt >= L[j].first) and (AAt < L[j].end_) then
      begin
        { the next line's first word, and what it is wide }
        m := L[j + 1].first;
        while (m < L[j + 1].end_) and ((C[m].flags <> 0) or (C[m].cp = 32)) do Inc(m);
        e := m;
        while (e < L[j + 1].end_) and (C[e].flags = 0) and (C[e].cp <> 32) do Inc(e);
        if e <= m then Exit;
        W := C[e - 1].x1 - C[m].x0;
        Result := (L[j].x1 - L[j].x0) + 0.3 * L[j].size + W > (B[ABlock].x1 - B[ABlock].x0) * 0.98;
        Exit;
      end;
  end;
{$ENDIF}

begin
  Result := '';
  {$IFDEF LED_PARADE}
  C := Chars(APage);
  U := '';
  AFrom := Max(AFrom, 0);
  ATo := Min(ATo, Length(C));
  for i := AFrom to ATo - 1 do
  begin
    Cp := C[i].cp;
    if C[i].flags and PD_PDFR_CHAR_NEWLINE <> 0 then
    begin
      K := BlockAt(APage, i);
      if (K >= 0) and (K = BlockAt(APage, i + 1)) and Wrapped(i, K) then
      begin
        if (Length(U) > 1) and (U[Length(U)] = '-') and (U[Length(U) - 1] <> ' ') then
          SetLength(U, Length(U) - 1)
        else if (U = '') or (U[Length(U)] <> ' ') then
          U := U + ' ';
        Continue;
      end;
      U := U + #10;
      Continue;
    end;
    if (Cp = 32) and (U <> '') and (U[Length(U)] = ' ') then Continue;   { spaces setting the line out: one }
    if Cp >= $10000 then
      U := U + WideChar($D800 + ((Cp - $10000) shr 10)) + WideChar($DC00 + ((Cp - $10000) and $3FF))
    else
      U := U + WideChar(Cp);
  end;
  Result := UTF8Encode(U);
  {$ENDIF}
end;

{ the character at a point of a page (or, ANearest, the one nearest it on the line it is on); -1 none }
function TLedPdfPane.CharAt(APage: Integer; PX, PY: Double; ANearest: Boolean): Integer;
{$IFDEF LED_PARADE}
var
  C: TLedPdfCharArray;
  i: Integer;
  D, Best, DX, DY: Double;
{$ENDIF}
begin
  Result := -1;
  {$IFDEF LED_PARADE}
  C := Chars(APage);
  Best := 1e30;
  for i := 0 to High(C) do
  begin
    if C[i].flags and PD_PDFR_CHAR_NEWLINE <> 0 then Continue;
    if (PX >= C[i].x0) and (PX <= C[i].x1) and (PY >= C[i].y0) and (PY <= C[i].y1) then
    begin
      { the half of the character the point is in: the caret goes before it or after it }
      if PX > (C[i].x0 + C[i].x1) / 2 then Exit(i + 1) else Exit(i);
    end;
    if ANearest then
    begin
      DX := 0;
      if PX < C[i].x0 then DX := C[i].x0 - PX else if PX > C[i].x1 then DX := PX - C[i].x1;
      DY := 0;
      if PY < C[i].y0 then DY := C[i].y0 - PY else if PY > C[i].y1 then DY := PY - C[i].y1;
      D := DX + DY * 8;     { the line the point is on counts most }
      if D < Best then
      begin
        Best := D;
        if PX > (C[i].x0 + C[i].x1) / 2 then Result := i + 1 else Result := i;
      end;
    end;
  end;
  {$ENDIF}
end;

function TLedPdfPane.SelAvail: Boolean;
begin
  Result := (FSelPage >= 0) and (FSelB > FSelA);
end;

function TLedPdfPane.SelectedText: string;
begin
  Result := '';
  {$IFDEF LED_PARADE}
  if SelAvail then Result := PdfCharsText(Chars(FSelPage), FSelA, FSelB);
  {$ENDIF}
end;

procedure TLedPdfPane.CopyToClipboard;
begin
  if SelAvail then Clipboard.AsText := SelectedText;
end;

procedure TLedPdfPane.SelectAll;
begin
  FSelPage := CurrentPage;
  FSelA := 0;
  FSelB := Length(Chars(FSelPage));
  FView.Invalidate;
  Status;
end;

{ the selection's lines as quadrilaterals on its page (8 numbers each) }
function TLedPdfPane.SelectionQuads(out Q: TDoubleDynArray): Integer;
{$IFDEF LED_PARADE}
var
  C: TLedPdfCharArray;
  i, n: Integer;
  X0, Y0, X1, Y1: Double;
  Open: Boolean;

  procedure Flush;
  begin
    if not Open then Exit;
    SetLength(Q, (n + 1) * 8);
    Q[n * 8 + 0] := X0; Q[n * 8 + 1] := Y0;
    Q[n * 8 + 2] := X1; Q[n * 8 + 3] := Y0;
    Q[n * 8 + 4] := X0; Q[n * 8 + 5] := Y1;
    Q[n * 8 + 6] := X1; Q[n * 8 + 7] := Y1;
    Inc(n);
    Open := False;
  end;
{$ENDIF}
begin
  Result := 0;
  Q := nil;
  {$IFDEF LED_PARADE}
  if not SelAvail then Exit;
  C := Chars(FSelPage);
  n := 0;
  Open := False;
  X0 := 0; Y0 := 0; X1 := 0; Y1 := 0;
  for i := FSelA to Min(FSelB, Length(C)) - 1 do
  begin
    if C[i].flags and PD_PDFR_CHAR_NEWLINE <> 0 then
    begin
      Flush;
      Continue;
    end;
    if C[i].flags and PD_PDFR_CHAR_SPACE <> 0 then Continue;
    if Open and ((Abs((C[i].y0 + C[i].y1) / 2 - (Y0 + Y1) / 2) > (Y1 - Y0) * 0.5) or (C[i].x0 < X0 - 2)) then
      Flush;
    if not Open then
    begin
      X0 := C[i].x0; Y0 := C[i].y0; X1 := C[i].x1; Y1 := C[i].y1;
      Open := True;
    end
    else
    begin
      X0 := Min(X0, C[i].x0); Y0 := Min(Y0, C[i].y0);
      X1 := Max(X1, C[i].x1); Y1 := Max(Y1, C[i].y1);
    end;
  end;
  Flush;
  Result := n;
  {$ENDIF}
end;

procedure TLedPdfPane.MarkSelectionAs(AKind: Integer);
begin
  MarkSelection(AKind);
end;

procedure TLedPdfPane.MarkSelection(AKind: Integer);
{$IFDEF LED_PARADE}
var
  Q: TDoubleDynArray;
  n: Integer;
{$ENDIF}
begin
  {$IFDEF LED_PARADE}
  n := SelectionQuads(Q);
  if n = 0 then Exit;
  if pd_pdfr_add_markup(FPdf, FSelPage, AKind, @Q[0], n, PenColor, nil) >= 0 then
  begin
    FSelPage := -1;
    Changed;
  end;
  {$ENDIF}
end;

{ ---- find ---- }

procedure TLedPdfPane.ShowFind;
begin
  FFindBar.Visible := True;
  FFindBar.Top := FTools.Top + FTools.Height;
  if SelAvail and (FSelB - FSelA < 80) then FFindEdit.Text := SelectedText;
  FFindEdit.SetFocus;
  FFindEdit.SelectAll;
end;

procedure TLedPdfPane.FindClose(Sender: TObject);
begin
  FFindBar.Visible := False;
  FFoundPage := -1;
  FView.Invalidate;
  if FView.CanFocus then FView.SetFocus;
end;

procedure TLedPdfPane.FindKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    FindNext(not (ssShift in Shift));
    Key := 0;
  end
  else if Key = VK_ESCAPE then
  begin
    FindClose(nil);
    Key := 0;
  end;
end;

{ the next place the text is found after (or before) what was found last }
procedure TLedPdfPane.FindNext(AForward: Boolean);
var
  Needle, Hay: UnicodeString;
  Page, Start, k, Tries, i: Integer;
  C: TLedPdfCharArray;
  Found: Boolean;
begin
  Needle := WideLowerCase(UTF8Decode(FFindEdit.Text));
  if (Needle = '') or (PageCount = 0) then Exit;
  if FFoundPage >= 0 then
  begin
    Page := FFoundPage;
    if AForward then Start := FFoundA + 1 else Start := FFoundA - 1;
  end
  else
  begin
    Page := CurrentPage;
    if AForward then Start := 0 else Start := MaxInt;
  end;
  Found := False;
  for Tries := 0 to PageCount do
  begin
    C := Chars(Page);
    { the page's text, a code unit a character (outside the BMP: a stand-in, so the indices stay the characters') }
    SetLength(Hay, Length(C));
    for i := 0 to High(C) do
      if C[i].cp < $10000 then Hay[i + 1] := WideChar(C[i].cp) else Hay[i + 1] := WideChar($FFFD);
    Hay := WideLowerCase(Hay);
    if AForward then
    begin
      k := Pos(Needle, Copy(Hay, Max(Start, 0) + 1, MaxInt));
      if k > 0 then
      begin
        FFoundA := Max(Start, 0) + k - 1;
        Found := True;
      end;
    end
    else
    begin
      k := Min(Start, Length(Hay) - Length(Needle));
      while (k >= 0) and (Copy(Hay, k + 1, Length(Needle)) <> Needle) do Dec(k);
      if k >= 0 then
      begin
        FFoundA := k;
        Found := True;
      end;
    end;
    if Found then
    begin
      FFoundPage := Page;
      FFoundB := FFoundA + Length(Needle);
      FSelPage := Page;
      FSelA := FFoundA;
      FSelB := FFoundB;
      ScrollTo(Page, C[FFoundA].y0);
      FFindNote.Caption := Format('page %d', [Page + 1]);
      FView.Invalidate;
      Status;
      Exit;
    end;
    if AForward then
    begin
      Page := (Page + 1) mod PageCount;
      Start := 0;
    end
    else
    begin
      Page := (Page + PageCount - 1) mod PageCount;
      Start := MaxInt;
    end;
  end;
  FFindNote.Caption := 'not found';
  FFoundPage := -1;
  FView.Invalidate;
end;

function TLedPdfPane.FindText(const AText: string; AFromPage: Integer): Boolean;
begin
  FFindEdit.Text := AText;
  FFoundPage := -1;
  if PageCount > 0 then FVBar.Position := FPageTop[EnsureRange(AFromPage, 0, PageCount - 1)] - PageGap;
  FindNext(True);
  Result := FFoundPage >= 0;
end;

{ ---- changes ---- }

procedure TLedPdfPane.Changed;
var
  i: Integer;
begin
  for i := 0 to High(FCharsOk) do
    FCharsOk[i] := False;
  FView.Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
  Status;
end;

function TLedPdfPane.CanUndo: Boolean;
begin
  Result := False;
  {$IFDEF LED_PARADE}
  Result := (FPdf <> nil) and (pd_pdfr_can_undo(FPdf) <> 0);
  {$ENDIF}
end;

function TLedPdfPane.CanRedo: Boolean;
begin
  Result := False;
  {$IFDEF LED_PARADE}
  Result := (FPdf <> nil) and (pd_pdfr_can_redo(FPdf) <> 0);
  {$ENDIF}
end;

procedure TLedPdfPane.Undo;
begin
  {$IFDEF LED_PARADE}
  CancelField;
  if CanUndo and (pd_pdfr_undo(FPdf) = 0) then
  begin
    FAnnPage := -1;
    Changed;
  end;
  {$ENDIF}
end;

procedure TLedPdfPane.Redo;
begin
  {$IFDEF LED_PARADE}
  CancelField;
  if CanRedo and (pd_pdfr_redo(FPdf) = 0) then
  begin
    FAnnPage := -1;
    Changed;
  end;
  {$ENDIF}
end;

function TLedPdfPane.AskText(const ATitle, APrompt: string; var AText: string; AMulti: Boolean): Boolean;
var
  F: TForm;
  M: TMemo;
  L: TLabel;
  B: TButton;
begin
  F := TForm.CreateNew(nil);
  try
    F.Caption := ATitle;
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.Width := LedScale96(IfThen(AMulti, 560, 420));
    F.Height := LedScale96(IfThen(AMulti, 320, 140));
    L := TLabel.Create(F);
    L.Parent := F;
    L.Caption := APrompt;
    L.Left := LedScale96(10);
    L.Top := LedScale96(8);
    M := TMemo.Create(F);
    M.Parent := F;
    M.Left := LedScale96(10);
    M.Top := LedScale96(28);
    M.Width := F.ClientWidth - LedScale96(20);
    M.Height := F.ClientHeight - LedScale96(72);
    M.WordWrap := True;
    M.ScrollBars := ssAutoVertical;
    M.WantReturns := AMulti;
    M.Text := AText;
    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := 'OK';
    B.ModalResult := mrOK;
    B.Default := True;
    B.Width := LedScale96(80);
    B.Left := F.ClientWidth - LedScale96(180);
    B.Top := F.ClientHeight - LedScale96(36);
    B := TButton.Create(F);
    B.Parent := F;
    B.Caption := 'Cancel';
    B.ModalResult := mrCancel;
    B.Cancel := True;
    B.Width := LedScale96(80);
    B.Left := F.ClientWidth - LedScale96(90);
    B.Top := F.ClientHeight - LedScale96(36);
    F.ActiveControl := M;
    Result := F.ShowModal = mrOK;
    if Result then AText := M.Text;
  finally
    F.Free;
  end;
end;

{ ---- form fields ---- }

procedure TLedPdfPane.CancelField;
begin
  if FFieldIndex < 0 then Exit;
  FieldDone(nil);
end;

procedure TLedPdfPane.FieldDone(Sender: TObject);
{$IFDEF LED_PARADE}
var
  I: Integer;
  V: string;
  Ctl: TWinControl;
{$ENDIF}
begin
  {$IFDEF LED_PARADE}
  I := FFieldIndex;
  if I < 0 then Exit;
  FFieldIndex := -1;
  V := '';
  Ctl := nil;
  if (FFieldEdit <> nil) and FFieldEdit.Visible then
  begin
    V := FFieldEdit.Text;
    Ctl := FFieldEdit;
  end
  else if (FFieldMemo <> nil) and FFieldMemo.Visible then
  begin
    V := FFieldMemo.Text;
    Ctl := FFieldMemo;
  end
  else if (FFieldCombo <> nil) and FFieldCombo.Visible then
  begin
    V := FFieldCombo.Text;
    Ctl := FFieldCombo;
  end;
  if Ctl = nil then Exit;
  Ctl.Visible := False;
  if Ctl.Tag <> 1 then  { Escape: left as it was }
    if pd_pdfr_field_set(FPdf, I, PAnsiChar(V)) = 0 then Changed;
  Ctl.Tag := 0;
  if FView.CanFocus then FView.SetFocus;
  {$ENDIF}
end;

procedure TLedPdfPane.FieldKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and not ((Sender = FFieldMemo) and not (ssCtrl in Shift)) then
  begin
    Key := 0;
    FieldDone(nil);
  end
  else if Key = VK_ESCAPE then
  begin
    Key := 0;
    TWinControl(Sender).Tag := 1;
    FieldDone(nil);
  end
  else if Key = VK_TAB then
  begin
    Key := 0;
    FieldDone(nil);
  end;
end;

procedure TLedPdfPane.FieldComboSelect(Sender: TObject);
begin
  FieldDone(nil);
end;

procedure TLedPdfPane.StartField(AField: Integer; APage: Integer);
{$IFDEF LED_PARADE}
var
  F: pd_pdfr_field;
  P0, P1: TPoint;
  i: Integer;
  Buf: array[0..1023] of AnsiChar;
  Ctl: TWinControl;
  Sz: Integer;
{$ENDIF}
begin
  {$IFDEF LED_PARADE}
  CancelField;
  if pd_pdfr_field_get(FPdf, AField, F) <> 0 then Exit;
  if F.readonly <> 0 then Exit;
  if F.kind in [PD_PDF_FIELD_CHECK, PD_PDF_FIELD_RADIO] then Exit;    { a click toggles them }
  if not (F.kind in [PD_PDF_FIELD_TEXT, PD_PDF_FIELD_COMBO, PD_PDF_FIELD_LIST]) then Exit;
  P0 := ToView(APage, F.x0, F.y0);
  P1 := ToView(APage, F.x1, F.y1);
  Sz := Round(EnsureRange(IfThen(F.font_size > 0, F.font_size, (F.y1 - F.y0) * 0.6), 6, 40) * FScale * 0.75);
  if F.kind = PD_PDF_FIELD_TEXT then
  begin
    if F.multiline <> 0 then
    begin
      if FFieldMemo = nil then
      begin
        FFieldMemo := TMemo.Create(Self);
        FFieldMemo.Parent := FView;
        FFieldMemo.OnExit := @FieldDone;
        FFieldMemo.OnKeyDown := @FieldKey;
        FFieldMemo.WordWrap := True;
      end;
      FFieldMemo.Text := F.value;
      Ctl := FFieldMemo;
    end
    else
    begin
      if FFieldEdit = nil then
      begin
        FFieldEdit := TEdit.Create(Self);
        FFieldEdit.Parent := FView;
        FFieldEdit.OnExit := @FieldDone;
        FFieldEdit.OnKeyDown := @FieldKey;
        FFieldEdit.BorderStyle := bsNone;
      end;
      FFieldEdit.Text := F.value;
      FFieldEdit.EchoMode := emNormal;
      if F.password <> 0 then FFieldEdit.EchoMode := emPassword;
      if F.maxlen > 0 then FFieldEdit.MaxLength := F.maxlen else FFieldEdit.MaxLength := 0;
      Ctl := FFieldEdit;
    end;
  end
  else
  begin
    if FFieldCombo = nil then
    begin
      FFieldCombo := TComboBox.Create(Self);
      FFieldCombo.Parent := FView;
      FFieldCombo.OnExit := @FieldDone;
      FFieldCombo.OnSelect := @FieldComboSelect;
      FFieldCombo.OnKeyDown := @FieldKey;
    end;
    FFieldCombo.Items.Clear;
    for i := 0 to F.nopts - 1 do
      if pd_pdfr_field_option(FPdf, AField, i, @Buf[0], SizeOf(Buf)) = 0 then
        FFieldCombo.Items.Add(Buf);
    FFieldCombo.Text := F.value;
    FFieldCombo.ItemIndex := FFieldCombo.Items.IndexOf(F.value);
    Ctl := FFieldCombo;
  end;
  Ctl.Font.Height := -Max(Sz, 8);
  Ctl.SetBounds(P0.X, P0.Y, Max(P1.X - P0.X, 20), Max(P1.Y - P0.Y, 16));
  Ctl.Tag := 0;
  Ctl.Visible := True;
  FFieldIndex := AField;
  Ctl.SetFocus;
  if Ctl = FFieldEdit then FFieldEdit.SelectAll;
  {$ENDIF}
end;

{ ---- the mouse ---- }

procedure TLedPdfPane.ViewMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
{$IFDEF LED_PARADE}
var
  Page, A, Fi, K: Integer;
  PX, PY: Double;
  Ann: pd_pdfr_annot;
  F: pd_pdfr_field;
  Buf: array[0..127] of AnsiChar;
{$ENDIF}
begin
  {$IFDEF LED_PARADE}
  if FPdf = nil then Exit;
  CancelField;
  Page := PageAt(X, Y, PX, PY);
  if Page < 0 then Exit;
  if Button = mbRight then
  begin
    { the menu acts on the annotation under it (a link too: to delete it), or the selection }
    A := pd_pdfr_annot_at(FPdf, Page, PX, PY);
    if (A >= 0) and (pd_pdfr_annot_get(FPdf, Page, A, Ann) = 0) and not (Ann.kind in [PD_ANNOT_WIDGET]) then
    begin
      FAnnPage := Page;
      FAnnIndex := A;
      FView.Invalidate;
    end;
    Exit;
  end;
  if Button <> mbLeft then Exit;

  { Insert: where it goes, clicked or dragged out }
  if FPlacing <> ppNone then
  begin
    FPlaceDown := True;
    FDrawPage := Page;
    FDrawStart := Point(X, Y);
    FDrawNow := FDrawStart;
    Exit;
  end;

  { a corner of the annotation picked: resized }
  if FTool = ptSelect then
  begin
    K := HandleAt(X, Y);
    if K >= 0 then
    begin
      FResizing := K;
      FDragStart := Point(X, Y);
      FDragNow := FDragStart;
      Exit;
    end;
  end;

  case FTool of
    ptSelect:
      begin
        { a third click: the block (the paragraph) the mouse is on, over a highlight of it too }
        if (ssTriple in Shift) and SelectParagraphAt(X, Y, False) then
        begin
          FAnnPage := -1;
          Exit;
        end;
        { on the selection: dragged, it moves there }
        if not (ssDouble in Shift) and OnSelection(Page, PX, PY) then
        begin
          FMoveText := True;
          FDragStart := Point(X, Y);
          FDragNow := FDragStart;
          FAnnPage := -1;
          Exit;
        end;
        { a form field }
        Fi := pd_pdfr_field_at(FPdf, Page, PX, PY);
        if (Fi >= 0) and (pd_pdfr_field_get(FPdf, Fi, F) = 0) and (F.readonly = 0) then
        begin
          if F.kind in [PD_PDF_FIELD_CHECK, PD_PDF_FIELD_RADIO] then
          begin
            Buf[0] := #0;
            K := pd_pdfr_annot_at(FPdf, Page, PX, PY);
            if K >= 0 then pd_pdfr_widget_state(FPdf, Page, K, @Buf[0], SizeOf(Buf));
            if (F.kind = PD_PDF_FIELD_CHECK) and (string(F.value) <> 'Off') then
              pd_pdfr_field_set(FPdf, Fi, 'Off')
            else
              pd_pdfr_field_set(FPdf, Fi, @Buf[0]);
            Changed;
            Exit;
          end;
          if F.kind in [PD_PDF_FIELD_TEXT, PD_PDF_FIELD_COMBO, PD_PDF_FIELD_LIST] then
          begin
            StartField(Fi, Page);
            Exit;
          end;
        end;
        { an annotation: picked, and dragged if the mouse moves }
        A := pd_pdfr_annot_at(FPdf, Page, PX, PY);
        if (A >= 0) and (pd_pdfr_annot_get(FPdf, Page, A, Ann) = 0) and
           not (Ann.kind in [PD_ANNOT_LINK, PD_ANNOT_WIDGET, PD_ANNOT_POPUP]) then
        begin
          FAnnPage := Page;
          FAnnIndex := A;
          FDragAnn := True;
          FDragStart := Point(X, Y);
          FDragNow := FDragStart;
          FSelPage := -1;
          FView.Invalidate;
          Exit;
        end;
        FAnnPage := -1;
        { a link: followed when the mouse comes up where it went down }
        if (A >= 0) and (Ann.kind = PD_ANNOT_LINK) then
        begin
          FDragStart := Point(X, Y);
          FSelecting := False;
          FDrawPage := -2 - A;   { the link remembered }
          FDrawStart := Point(Page, 0);
          Exit;
        end;
        { text }
        FSelPage := Page;
        FSelAnchor := CharAt(Page, PX, PY, True);
        FSelA := FSelAnchor;
        FSelB := FSelAnchor;
        FSelecting := FSelAnchor >= 0;
        FFoundPage := -1;
        FView.Invalidate;
      end;
    ptHighlight, ptUnderline, ptStrikeOut, ptSquiggly:
      begin
        FSelPage := Page;
        FSelAnchor := CharAt(Page, PX, PY, True);
        FSelA := FSelAnchor;
        FSelB := FSelAnchor;
        FSelecting := FSelAnchor >= 0;
      end;
    ptNote:
      begin
        FDrawPage := Page;
        FDrawStart := Point(X, Y);
      end;
    ptTextBox, ptRect, ptEllipse, ptLine, ptArrow, ptInk:
      begin
        FDrawing := True;
        FDrawPage := Page;
        FDrawStart := Point(X, Y);
        FDrawNow := FDrawStart;
        SetLength(FInk, 1);
        FInk[0] := FDrawStart;
      end;
  end;
  {$ENDIF}
end;

procedure TLedPdfPane.ViewMouseMove(Shift: TShiftState; X, Y: Integer);
{$IFDEF LED_PARADE}
var
  Page, K, A: Integer;
  PX, PY, GX0, GY0, GX1, GY1: Double;
  Ann: pd_pdfr_annot;
{$ENDIF}
begin
  {$IFDEF LED_PARADE}
  if FPdf = nil then Exit;
  if FSelecting then
  begin
    Page := PageAt(X, Y, PX, PY);
    if Page = FSelPage then
    begin
      K := CharAt(Page, PX, PY, True);
      if K >= 0 then
      begin
        FSelA := Min(FSelAnchor, K);
        FSelB := Max(FSelAnchor, K);
        FView.Invalidate;
      end;
    end;
    { past the top or bottom: scrolled along }
    if Y < 0 then FVBar.Position := FVBar.Position - 20
    else if Y > FView.ClientHeight then FVBar.Position := FVBar.Position + 20;
    Exit;
  end;
  if FDragAnn or FMoveText or (FResizing >= 0) then
  begin
    FDragNow := Point(X, Y);
    FView.Invalidate;
    Exit;
  end;
  if FPlacing <> ppNone then
  begin   { where it would go, shown }
    if FPlaceDown then
    begin
      FDrawNow := Point(X, Y);
      Page := FDrawPage;
    end
    else
      Page := PageAt(X, Y, PX, PY);
    FGhostPage := -1;
    if FPlaceDown then
    begin
      if PlaceBox(Page, FDrawStart, FDrawNow, GX0, GY0, GX1, GY1) then FGhostPage := Page;
    end
    else if PlaceBox(Page, Point(X, Y), Point(X, Y), GX0, GY0, GX1, GY1) then
      FGhostPage := Page;
    if FGhostPage >= 0 then
      FGhost := Rect(ToView(Page, GX0, GY0).X, ToView(Page, GX0, GY0).Y, ToView(Page, GX1, GY1).X,
        ToView(Page, GX1, GY1).Y);
    FView.Invalidate;
    Exit;
  end;
  if FDrawing then
  begin
    FDrawNow := Point(X, Y);
    if FTool = ptInk then
    begin
      SetLength(FInk, Length(FInk) + 1);
      FInk[High(FInk)] := FDrawNow;
    end;
    FView.Invalidate;
    Exit;
  end;
  { the pointer: a hand over a link, a beam over text, the move cross over the selection, the resize arrows over a
    picked annotation's corner }
  if FTool = ptSelect then
  begin
    case HandleAt(X, Y) of
      0, 2: begin FView.Cursor := crSizeNWSE; Exit; end;
      1, 3: begin FView.Cursor := crSizeNESW; Exit; end;
    end;
    Page := PageAt(X, Y, PX, PY);
    if Page < 0 then
    begin
      FView.Cursor := crDefault;
      Exit;
    end;
    if OnSelection(Page, PX, PY) then
    begin
      FView.Cursor := crSizeAll;
      FView.Hint := 'Drag to move the selected text';
      Exit;
    end;
    A := pd_pdfr_annot_at(FPdf, Page, PX, PY);
    if (A >= 0) and (pd_pdfr_annot_get(FPdf, Page, A, Ann) = 0) then
    begin
      if Ann.kind = PD_ANNOT_LINK then
      begin
        FView.Cursor := crHandPoint;
        FView.Hint := Ann.uri;
        FView.ShowHint := Ann.uri <> '';
        Exit;
      end;
      if Ann.kind = PD_ANNOT_WIDGET then
      begin
        FView.Cursor := crHandPoint;
        Exit;
      end;
      FView.Cursor := crSizeAll;
      FView.Hint := Ann.contents;
      FView.ShowHint := Ann.contents <> '';
      Exit;
    end;
    FView.ShowHint := False;
    if CharAt(Page, PX, PY, False) >= 0 then FView.Cursor := crIBeam else FView.Cursor := crDefault;
  end;
  {$ENDIF}
end;

procedure TLedPdfPane.ViewMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
{$IFDEF LED_PARADE}
var
  Page: Integer;
  PX, PY, QX, QY, W, GX0, GY0, GX1, GY1: Double;
  GR, GR0: TRect;
  S: string;
  Pts: array of Double;
  Cnt: array[0..0] of Int32;
  i, Kind: Integer;
  Ann: pd_pdfr_annot;
  Link: Integer;
{$ENDIF}
begin
  {$IFDEF LED_PARADE}
  if FPdf = nil then Exit;
  if Button <> mbLeft then Exit;
  if FSelecting then
  begin
    FSelecting := False;
    Status;
    if FTool in [ptHighlight, ptUnderline, ptStrikeOut, ptSquiggly] then
    begin
      case FTool of
        ptHighlight: Kind := PD_ANNOT_HIGHLIGHT;
        ptUnderline: Kind := PD_ANNOT_UNDERLINE;
        ptStrikeOut: Kind := PD_ANNOT_STRIKEOUT;
      else
        Kind := PD_ANNOT_SQUIGGLY;
      end;
      MarkSelection(Kind);
    end;
    Exit;
  end;
  if FMoveText then
  begin
    FMoveText := False;
    if (Abs(X - FDragStart.X) > 2) or (Abs(Y - FDragStart.Y) > 2) then
    begin
      if not MoveSelection((X - FDragStart.X) / FScale, (Y - FDragStart.Y) / FScale) then
        MessageDlg('Move Text', 'This text cannot be moved: it is drawn from a part of the page that cannot be ' +
          'changed here.', mtWarning, [mbOK], 0);
    end
    else
    begin   { a click on the selection, not a drag: it goes, the caret's place a new start }
      FSelPage := -1;
      Status;
    end;
    FView.Invalidate;
    Exit;
  end;
  if FPlacing <> ppNone then
  begin
    if FPlaceDown and PlaceBox(FDrawPage, FDrawStart, Point(X, Y), GX0, GY0, GX1, GY1) then
    begin
      case FPlacing of
        ppPicture: PlacePicture(FDrawPage, GX0, GY0, GX1, GY1, FPlaceRGBA, FPlaceJpeg, FPlaceW, FPlaceH);
        ppSignature: PlaceSignature(FPlaceSig, FDrawPage, GX0, GY0, GX1, GY1);
        ppLink:
          begin
            S := 'https://';
            if AskText('Link', 'Where it goes (a web address, mailto:..., or #page=3 for a page of this file):', S,
              False) and (PlaceLink(FDrawPage, GX0, GY0, GX1, GY1, S) < 0) then
              MessageDlg('Link', 'That link could not be made.', mtWarning, [mbOK], 0);
          end;
      else
        PlaceMark(FPlacing, FDrawPage, GX0, GY0, GX1, GY1);
      end;
    end;
    FPlaceDown := False;
    { a mark again where clicked next (Esc when done); a picture, a signature, once }
    if not (FPlacing in [ppCheck, ppCross, ppDot]) then
      StopPlacing;
    FView.Invalidate;
    Exit;
  end;
  if FResizing >= 0 then
  begin
    if ((Abs(X - FDragStart.X) > 2) or (Abs(Y - FDragStart.Y) > 2)) and PickedViewRect(GR) then
    begin
      GR0 := PageRectOnView(FAnnPage);
      FResizing := -1;
      if (GR.Right - GR.Left > 2) and (GR.Bottom - GR.Top > 2) then
        ResizeAnnotation(FAnnPage, FAnnIndex, (GR.Left - GR0.Left) / FScale, (GR.Top - GR0.Top) / FScale,
          (GR.Right - GR0.Left) / FScale, (GR.Bottom - GR0.Top) / FScale);
    end;
    FResizing := -1;
    FView.Invalidate;
    Exit;
  end;
  if FDragAnn then
  begin
    FDragAnn := False;
    if (Abs(X - FDragStart.X) > 2) or (Abs(Y - FDragStart.Y) > 2) then
    begin
      if pd_pdfr_annot_move(FPdf, FAnnPage, FAnnIndex, (X - FDragStart.X) / FScale,
        (Y - FDragStart.Y) / FScale) = 0 then
        Changed;
    end;
    FView.Invalidate;
    Exit;
  end;
  if FDrawPage <= -2 then   { a link clicked }
  begin
    Link := -2 - FDrawPage;
    FDrawPage := -1;
    if (Abs(X - FDragStart.X) <= 3) and (Abs(Y - FDragStart.Y) <= 3) and
       (pd_pdfr_annot_get(FPdf, FDrawStart.X, Link, Ann) = 0) then
    begin
      S := Ann.uri;
      if Copy(S, 1, 6) = '#page=' then
        GoToPage(StrToIntDef(Copy(S, 7, 10), 1) - 1)
      else if S <> '' then
        OpenURL(S);
    end;
    Exit;
  end;
  if FTool = ptNote then
  begin
    Page := PageAt(X, Y, PX, PY);
    if Page >= 0 then
    begin
      S := '';
      if AskText('Note', 'The note''s text:', S, True) then
        if pd_pdfr_add_note(FPdf, Page, PX, PY, PAnsiChar(S), PenColor) >= 0 then Changed;
    end;
    SetTool(ptSelect);
    Exit;
  end;
  if FDrawing then
  begin
    FDrawing := False;
    Page := FDrawPage;
    PageAt(FDrawStart.X, FDrawStart.Y, PX, PY);
    PageAt(X, Y, QX, QY);
    { the far corner on the same page as the near one }
    QX := (X - PageRectOnView(Page).Left) / FScale;
    QY := (Y - PageRectOnView(Page).Top) / FScale;
    PX := (FDrawStart.X - PageRectOnView(Page).Left) / FScale;
    PY := (FDrawStart.Y - PageRectOnView(Page).Top) / FScale;
    W := 2;
    case FTool of
      ptTextBox:
        begin
          if (Abs(QX - PX) < 20) or (Abs(QY - PY) < 10) then
          begin
            QX := PX + 200;
            QY := PY + 40;
          end;
          S := '';
          if AskText('Text Box', 'The box''s text:', S, True) and (S <> '') then
            if pd_pdfr_add_text_box(FPdf, Page, Min(PX, QX), Min(PY, QY), Max(PX, QX), Max(PY, QY),
              PAnsiChar(S), 12, PenColor) >= 0 then Changed;
          SetTool(ptSelect);
        end;
      ptRect, ptEllipse:
        if (Abs(QX - PX) > 2) and (Abs(QY - PY) > 2) then
        begin
          if FTool = ptRect then Kind := PD_ANNOT_SQUARE else Kind := PD_ANNOT_CIRCLE;
          if pd_pdfr_add_shape(FPdf, Page, Kind, Min(PX, QX), Min(PY, QY), Max(PX, QX), Max(PY, QY),
            PenColor, 0, W) >= 0 then Changed;
        end;
      ptLine, ptArrow:
        if (Abs(QX - PX) > 2) or (Abs(QY - PY) > 2) then
        begin
          if FTool = ptLine then Kind := PD_ANNOT_LINE else Kind := PD_ANNOT_ARROW;
          if pd_pdfr_add_shape(FPdf, Page, Kind, PX, PY, QX, QY, PenColor, 0, W) >= 0 then Changed;
        end;
      ptInk:
        if Length(FInk) >= 1 then
        begin
          SetLength(Pts, 2 * Length(FInk));
          for i := 0 to High(FInk) do
          begin
            Pts[2 * i] := (FInk[i].X - PageRectOnView(Page).Left) / FScale;
            Pts[2 * i + 1] := (FInk[i].Y - PageRectOnView(Page).Top) / FScale;
          end;
          Cnt[0] := Length(FInk);
          if pd_pdfr_add_ink(FPdf, Page, @Pts[0], @Cnt[0], 1, PenColor, W) >= 0 then Changed;
        end;
    else
    end;
    SetLength(FInk, 0);
    FView.Invalidate;
  end;
  {$ENDIF}
end;

{ the block under the mouse selected }
procedure TLedPdfPane.ViewTripleClick;
var
  P: TPoint;
begin
  if (FPdf = nil) or (FTool <> ptSelect) then Exit;
  P := FView.ScreenToClient(Mouse.CursorPos);
  SelectParagraphAt(P.X, P.Y, False);
end;

function TLedPdfPane.SelectParagraphAt(X, Y: Integer; ASkipMark: Boolean): Boolean;
{$IFDEF LED_PARADE}
var
  Page, K, A, B: Integer;
  PX, PY: Double;
{$ENDIF}
begin
  Result := False;
  {$IFDEF LED_PARADE}
  if FPdf = nil then Exit;
  Page := PageAt(X, Y, PX, PY);
  if Page < 0 then Exit;
  K := BlockAt(Page, CharAt(Page, PX, PY, True));
  if K < 0 then Exit;
  BlockRange(Page, K, ASkipMark, A, B);
  if B <= A then Exit;
  FSelPage := Page;
  FSelA := A;
  FSelB := B;
  FSelecting := False;
  FView.Invalidate;
  Status;
  Result := True;
  {$ENDIF}
end;

function TLedPdfPane.SelectionEditText: string;
begin
  Result := '';
  if SelAvail then Result := EditableText(FSelPage, FSelA, FSelB);
end;

function TLedPdfPane.MoveSelection(DX, DY: Double): Boolean;
begin
  Result := False;
  {$IFDEF LED_PARADE}
  if not SelAvail then Exit;
  Result := pd_pdfr_move_text(FPdf, FSelPage, FSelA, FSelB, DX, DY) = 0;
  if Result then
  begin
    FSelPage := -1;
    Changed;
  end;
  {$ENDIF}
end;

{ a point of a page on the selection: in the band of one of its lines }
function TLedPdfPane.OnSelection(APage: Integer; PX, PY: Double): Boolean;
{$IFDEF LED_PARADE}
var
  Ls: TLedPdfSpanArray;
  C: TLedPdfCharArray;
  k, i: Integer;
  X0, X1: Double;
{$ENDIF}
begin
  Result := False;
  {$IFDEF LED_PARADE}
  if not SelAvail or (APage <> FSelPage) then Exit;
  Ls := Lines(APage);
  C := Chars(APage);
  for k := 0 to High(Ls) do
  begin
    if (Ls[k].end_ <= FSelA) or (Ls[k].first >= FSelB) or (PY < Ls[k].y0) or (PY > Ls[k].y1) then Continue;
    X0 := 1e30;
    X1 := -1e30;
    for i := Max(FSelA, Ls[k].first) to Min(FSelB, Ls[k].end_) - 1 do
      if (C[i].flags = 0) and (C[i].cp <> 32) then
      begin
        X0 := Min(X0, C[i].x0);
        X1 := Max(X1, C[i].x1);
      end;
    if (PX >= X0) and (PX <= X1) then Exit(True);
  end;
  {$ENDIF}
end;

function TLedPdfPane.ReplaceSelection(const AText: string): Boolean;
begin
  Result := False;
  {$IFDEF LED_PARADE}
  if not SelAvail then Exit;
  Result := pd_pdfr_replace_text(FPdf, FSelPage, FSelA, FSelB,
    PAnsiChar(StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]))) = 0;
  if Result then
  begin
    FSelPage := -1;
    Changed;
  end;
  {$ENDIF}
end;

procedure TLedPdfPane.ViewDblClick;
{$IFDEF LED_PARADE}
var
  P: TPoint;
  Page, A, K, i, j: Integer;
  PX, PY: Double;
  Ann: pd_pdfr_annot;
  S: string;
  C: TLedPdfCharArray;
{$ENDIF}
begin
  {$IFDEF LED_PARADE}
  if (FPdf = nil) or (FTool <> ptSelect) then Exit;
  P := FView.ScreenToClient(Mouse.CursorPos);
  Page := PageAt(P.X, P.Y, PX, PY);
  if Page < 0 then Exit;
  A := pd_pdfr_annot_at(FPdf, Page, PX, PY);
  if (A >= 0) and (pd_pdfr_annot_get(FPdf, Page, A, Ann) = 0) and (Ann.kind in [PD_ANNOT_TEXT, PD_ANNOT_FREETEXT]) then
  begin
    FDragAnn := False;
    S := Ann.contents;
    if AskText('Note', 'The text:', S, True) then
      if pd_pdfr_annot_set_contents(FPdf, Page, A, PAnsiChar(S)) = 0 then Changed;
    Exit;
  end;
  { a word selected }
  K := CharAt(Page, PX, PY, False);
  C := Chars(Page);
  if (K >= 0) and (K < Length(C)) then
  begin
    i := K;
    j := K;
    while (i > 0) and (C[i - 1].cp > 32) and (C[i - 1].flags = 0) do Dec(i);
    while (j < Length(C)) and (C[j].cp > 32) and (C[j].flags = 0) do Inc(j);
    FSelPage := Page;
    FSelA := i;
    FSelB := j;
    FSelecting := False;
    FView.Invalidate;
    Status;
  end;
  {$ENDIF}
end;

procedure TLedPdfPane.ViewKey(var Key: Word; Shift: TShiftState);
begin
  {$IFDEF LED_PARADE}
  if FPdf = nil then Exit;
  if (Key = VK_F5) and (Shift * [ssCtrl, ssAlt] = []) then
  begin   { presented: F5 from the first page, Shift+F5 from this one, as a slide show starts }
    Present(ssShift in Shift);
    Key := 0;
    Exit;
  end;
  case Key of
    VK_DELETE:
      if (FAnnPage >= 0) and (FAnnIndex >= 0) then
      begin
        if pd_pdfr_annot_delete(FPdf, FAnnPage, FAnnIndex) = 0 then
        begin
          FAnnPage := -1;
          Changed;
        end;
        Key := 0;
      end;
    VK_V:
      if (ssCtrl in Shift) and PasteFromClipboard then Key := 0;
    VK_ESCAPE:
      begin
        if FPlacing <> ppNone then StopPlacing;
        FResizing := -1;
        SetTool(ptSelect);
        FSelPage := -1;
        FAnnPage := -1;
        FDrawing := False;
        FView.Invalidate;
        Key := 0;
      end;
    VK_NEXT:
      begin
        FVBar.Position := FVBar.Position + FVBar.LargeChange;
        Key := 0;
      end;
    VK_PRIOR:
      begin
        FVBar.Position := FVBar.Position - FVBar.LargeChange;
        Key := 0;
      end;
    VK_DOWN:
      begin
        FVBar.Position := FVBar.Position + 40;
        Key := 0;
      end;
    VK_UP:
      begin
        FVBar.Position := FVBar.Position - 40;
        Key := 0;
      end;
    VK_HOME:
      if ssCtrl in Shift then
      begin
        FVBar.Position := 0;
        Key := 0;
      end;
    VK_END:
      if ssCtrl in Shift then
      begin
        FVBar.Position := FVBar.Max;
        Key := 0;
      end;
    VK_F3:
      begin
        if FFindEdit.Text <> '' then FindNext(not (ssShift in Shift)) else ShowFind;
        Key := 0;
      end;
  end;
  if ssCtrl in Shift then
    case Key of
      VK_C:
        begin
          CopyToClipboard;
          Key := 0;
        end;
      VK_A:
        begin
          SelectAll;
          Key := 0;
        end;
      VK_F:
        begin
          ShowFind;
          Key := 0;
        end;
      VK_Z:
        begin
          if ssShift in Shift then Redo else Undo;
          Key := 0;
        end;
      VK_Y:
        begin
          Redo;
          Key := 0;
        end;
      VK_ADD, VK_OEM_PLUS:
        begin
          ZoomBy(1.2);
          Key := 0;
        end;
      VK_SUBTRACT, VK_OEM_MINUS:
        begin
          ZoomBy(1 / 1.2);
          Key := 0;
        end;
      VK_0, VK_NUMPAD0:
        begin
          ZoomFitWidth;
          Key := 0;
        end;
    end;
  {$ENDIF}
end;

{ ---- the menu ---- }

procedure TLedPdfPane.MenuPopup(Sender: TObject);
var
  i: Integer;
  HasAnn: Boolean;
begin
  HasAnn := FAnnPage >= 0;
  FMenuAt := FView.ScreenToClient(FMenu.PopupPoint);
  for i := 0 to FMenu.Items.Count - 1 do
    case i of
      0..5: FMenu.Items[i].Enabled := SelAvail;
      7: FMenu.Items[i].Enabled := PageCount > 0;
      9..11: FMenu.Items[i].Enabled := HasAnn;
    end;
end;

{ the paragraph (block) where the menu was opened, or the selection is, written again: wrapped as it was, in its
  font when that has the characters; a list item's mark kept }
procedure TLedPdfPane.MenuEditParagraph(Sender: TObject);
var
  S: string;
  At: TPoint;
  C: TLedPdfCharArray;
begin
  {$IFDEF LED_PARADE}
  if FPdf = nil then Exit;
  At := FMenuAt;
  if not SelectParagraphAt(At.X, At.Y, True) then
  begin
    { not over text: the paragraph the selection begins in }
    if SelAvail then
    begin
      C := Chars(FSelPage);
      At := ToView(FSelPage, C[FSelA].x0 + 0.5, (C[FSelA].y0 + C[FSelA].y1) / 2);
    end;
    if not (SelAvail and SelectParagraphAt(At.X, At.Y, True)) then
    begin
      MessageDlg('Edit Paragraph', 'There is no text here to edit.', mtInformation, [mbOK], 0);
      Exit;
    end;
  end;
  S := SelectionEditText;
  if AskText('Edit Paragraph', 'The paragraph as it should read (Enter starts a new line):', S, True) then
    if not ReplaceSelection(S) then
      MessageDlg('Edit Paragraph', 'The text could not be changed here.', mtWarning, [mbOK], 0);
  {$ENDIF}
end;

procedure TLedPdfPane.MenuCopy(Sender: TObject);
begin
  CopyToClipboard;
end;

procedure TLedPdfPane.MenuMark(Sender: TObject);
begin
  MarkSelection(TMenuItem(Sender).Tag);
end;

procedure TLedPdfPane.MenuEditText(Sender: TObject);
var
  S: string;
  Multi: Boolean;

  function LineOf(AChar: Integer): Integer;
  var
    L: TLedPdfSpanArray;
    i: Integer;
  begin
    Result := -1;
    {$IFDEF LED_PARADE}
    L := Lines(FSelPage);
    for i := 0 to High(L) do
      if (AChar >= L[i].first) and (AChar < L[i].end_) then Exit(i);
    {$ENDIF}
  end;

begin
  {$IFDEF LED_PARADE}
  if not SelAvail then Exit;
  S := EditableText(FSelPage, FSelA, FSelB);
  Multi := (Lines(FSelPage) <> nil) and (LineOf(FSelA) <> LineOf(FSelB - 1));
  if AskText('Edit Text', 'The selected text, as it should read:', S, Multi) then
    if pd_pdfr_replace_text(FPdf, FSelPage, FSelA, FSelB,
      PAnsiChar(StringReplace(StringReplace(S, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]))) = 0 then
    begin
      FSelPage := -1;
      Changed;
    end
    else
      MessageDlg('Edit Text', 'The text could not be changed here.', mtWarning, [mbOK], 0);
  {$ENDIF}
end;

procedure TLedPdfPane.MenuDeleteAnn(Sender: TObject);
var
  K: Word;
begin
  K := VK_DELETE;
  ViewKey(K, []);
end;

procedure TLedPdfPane.MenuColorAnn(Sender: TObject);
var
  D: TColorDialog;
  C: TColor;
begin
  {$IFDEF LED_PARADE}
  if FAnnPage < 0 then Exit;
  D := TColorDialog.Create(nil);
  try
    D.Color := FColorBtn.ButtonColor;
    if D.Execute then
    begin
      C := ColorToRGB(D.Color);
      if pd_pdfr_annot_set_color(FPdf, FAnnPage, FAnnIndex,
        (UInt32(Red(C)) shl 16) or (UInt32(Green(C)) shl 8) or UInt32(Blue(C))) = 0 then
        Changed;
    end;
  finally
    D.Free;
  end;
  {$ENDIF}
end;

procedure TLedPdfPane.MenuNoteText(Sender: TObject);
{$IFDEF LED_PARADE}
var
  A: pd_pdfr_annot;
  S: string;
{$ENDIF}
begin
  {$IFDEF LED_PARADE}
  if (FAnnPage < 0) or (pd_pdfr_annot_get(FPdf, FAnnPage, FAnnIndex, A) <> 0) then Exit;
  S := A.contents;
  if AskText('Annotation', 'Its text:', S, True) then
    if pd_pdfr_annot_set_contents(FPdf, FAnnPage, FAnnIndex, PAnsiChar(S)) = 0 then Changed;
  {$ENDIF}
end;


{ ---- presenting ---- }

procedure TLedPdfPane.PresentClick(Sender: TObject);
begin
  Present(True);
end;

procedure TLedPdfPane.Present(FromCurrent: Boolean);
var
  F: TLedPdfShow;
begin
  {$IFDEF LED_PARADE}
  if (FPdf = nil) or (PageCount = 0) then Exit;
  CancelField;
  F := TLedPdfShow.CreateShow(Self, IfThen(FromCurrent, CurrentPage, 0));
  F.Show;
  {$ENDIF}
end;

constructor TLedPdfShow.CreateShow(APane: TLedPdfPane; AFrom: Integer);
var
  i: Integer;
begin
  inherited CreateNew(nil);
  FPane := APane;
  FPage := EnsureRange(AFrom, 0, Max(0, APane.PageCount - 1));
  for i := 0 to 2 do
    FBmpPage[i] := -1;
  Caption := 'Presenting';
  BorderStyle := bsNone;
  Color := clBlack;
  KeyPreview := True;
  FBlank := clBlack;
  { the monitor the window is on, all of it }
  BoundsRect := Screen.MonitorFromWindow(Application.MainForm.Handle).BoundsRect;
  WindowState := wsFullScreen;
  FIdle := TTimer.Create(Self);
  FIdle.Interval := 500;
  FIdle.OnTimer := @IdleTick;
  FAhead := TTimer.Create(Self);
  FAhead.Enabled := False;
  FAhead.Interval := 60;
  FAhead.OnTimer := @AheadTick;
  FLastMove := GetTickCount64;
end;

destructor TLedPdfShow.Destroy;
var
  i: Integer;
begin
  for i := 0 to 2 do
    FBmp[i].Free;
  inherited Destroy;
end;

{ where a page goes on the screen: as large as it fits, in the middle }
function TLedPdfShow.PageRect(APage: Integer): TRect;
var
  Sc: Double;
  W, H: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (APage < 0) or (APage >= FPane.PageCount) or (FPane.FPageW[APage] <= 0) or (FPane.FPageH[APage] <= 0) then
    Exit;
  Sc := Min(ClientWidth / FPane.FPageW[APage], ClientHeight / FPane.FPageH[APage]);
  W := Max(1, Round(FPane.FPageW[APage] * Sc));
  H := Max(1, Round(FPane.FPageH[APage] * Sc));
  Result := Bounds((ClientWidth - W) div 2, (ClientHeight - H) div 2, W, H);
end;

{ a page drawn for the screen, opaque (so the display takes it as it is, nothing read back to blend), kept: the one
  shown, the next, the one before }
function TLedPdfShow.PageBitmap(APage: Integer): TBitmap;
{$IFDEF LED_PARADE}
var
  R: TRect;
  Img: TLazIntfImage;
  Desc: TRawImageDescription;
  i, Slot, Flags: Integer;
{$ENDIF}
begin
  Result := nil;
  {$IFDEF LED_PARADE}
  if (FBmpW <> ClientWidth) or (FBmpH <> ClientHeight) then
  begin
    for i := 0 to 2 do
    begin
      FreeAndNil(FBmp[i]);
      FBmpPage[i] := -1;
    end;
    FBmpW := ClientWidth;
    FBmpH := ClientHeight;
  end;
  for i := 0 to 2 do
    if (FBmpPage[i] = APage) and (FBmp[i] <> nil) then
      Exit(FBmp[i]);
  R := PageRect(APage);
  if (R.Width <= 0) or (R.Height <= 0) then Exit;
  { the slot of a page not near the one shown }
  Slot := 0;
  for i := 0 to 2 do
    if (FBmpPage[i] < 0) or (Abs(FBmpPage[i] - FPage) > 1) then
    begin
      Slot := i;
      Break;
    end;
  Img := TLazIntfImage.Create(0, 0);
  try
    Desc.Init_BPP32_B8G8R8_BIO_TTB(R.Width, R.Height);
    Img.DataDescription := Desc;
    Flags := 0;
    if Desc.RedShift = 16 then Flags := PD_PDFR_BGRA;
    pd_pdfr_render(FPane.FPdf, APage, R.Width / FPane.FPageW[APage], 0, 0, Img.PixelData, R.Width, R.Height,
      Desc.BytesPerLine, Flags);
    FreeAndNil(FBmp[Slot]);
    FBmp[Slot] := TBitmap.Create;
    FBmp[Slot].LoadFromIntfImage(Img);
    FBmpPage[Slot] := APage;
    Result := FBmp[Slot];
  finally
    Img.Free;
  end;
  {$ENDIF}
end;

procedure TLedPdfShow.Paint;
var
  B: TBitmap;
  R: TRect;
begin
  if FBlanked then
  begin
    Canvas.Brush.Color := FBlank;
    Canvas.FillRect(ClientRect);
    Exit;
  end;
  B := PageBitmap(FPage);
  R := PageRect(FPage);
  Canvas.Brush.Color := clBlack;
  { the black around the page, not under it: what is drawn twice is sent twice }
  Canvas.FillRect(Rect(0, 0, ClientWidth, R.Top));
  Canvas.FillRect(Rect(0, R.Bottom, ClientWidth, ClientHeight));
  Canvas.FillRect(Rect(0, R.Top, R.Left, R.Bottom));
  Canvas.FillRect(Rect(R.Right, R.Top, ClientWidth, R.Bottom));
  if B <> nil then
    Canvas.Draw(R.Left, R.Top, B);
  FAhead.Enabled := True;
end;

procedure TLedPdfShow.GoTo_(APage: Integer);
begin
  APage := EnsureRange(APage, 0, Max(0, FPane.PageCount - 1));
  FBlanked := False;
  if APage = FPage then
  begin
    Invalidate;
    Exit;
  end;
  FPage := APage;
  Invalidate;
end;

{ the page after the one shown drawn while it is looked at, then the one before }
procedure TLedPdfShow.AheadTick(Sender: TObject);
begin
  FAhead.Enabled := False;
  if FPage + 1 < FPane.PageCount then
    PageBitmap(FPage + 1);
  if FPage > 0 then
    PageBitmap(FPage - 1);
end;

procedure TLedPdfShow.IdleTick(Sender: TObject);
begin
  if (Cursor <> crNone) and (GetTickCount64 - FLastMove > 2500) then
    Cursor := crNone;
end;

procedure TLedPdfShow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE, VK_F5:
      Close;
    VK_RIGHT, VK_DOWN, VK_NEXT, VK_SPACE, VK_N, VK_RETURN:
      if (Key = VK_RETURN) and (FTyped <> '') then
      begin
        GoTo_(StrToIntDef(FTyped, FPage + 1) - 1);
        FTyped := '';
      end
      else
        GoTo_(FPage + 1);
    VK_LEFT, VK_UP, VK_PRIOR, VK_BACK, VK_P:
      GoTo_(FPage - 1);
    VK_HOME:
      GoTo_(0);
    VK_END:
      GoTo_(FPane.PageCount - 1);
    VK_B, VK_OEM_PERIOD, VK_W, VK_OEM_COMMA:
      begin   { the screen blanked, black or white; the same key again, the page }
        if FBlanked and (FBlank = IfThen((Key = VK_B) or (Key = VK_OEM_PERIOD), clBlack, clWhite)) then
          FBlanked := False
        else
        begin
          FBlanked := True;
          if (Key = VK_B) or (Key = VK_OEM_PERIOD) then FBlank := clBlack else FBlank := clWhite;
        end;
        Invalidate;
      end;
    VK_0..VK_9:
      FTyped := FTyped + Chr(Ord('0') + Key - VK_0);
    VK_NUMPAD0..VK_NUMPAD9:
      FTyped := FTyped + Chr(Ord('0') + Key - VK_NUMPAD0);
  else
    Exit;
  end;
  if not (Key in [VK_0..VK_9, VK_NUMPAD0..VK_NUMPAD9]) then
    FTyped := '';
  Key := 0;
end;

procedure TLedPdfShow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
{$IFDEF LED_PARADE}
var
  R: TRect;
  A: Integer;
  Ann: pd_pdfr_annot;
  S: string;
  Sc: Double;
{$ENDIF}
begin
  inherited MouseDown(Button, Shift, X, Y);
  FLastMove := GetTickCount64;
  Cursor := crDefault;
  if Button = mbRight then
  begin
    GoTo_(FPage - 1);
    Exit;
  end;
  if Button <> mbLeft then Exit;
  {$IFDEF LED_PARADE}
  { a link where it is clicked: followed (a page of the file, or the address) }
  R := PageRect(FPage);
  if (R.Width > 0) and PtInRect(R, Point(X, Y)) and not FBlanked then
  begin
    Sc := R.Width / FPane.FPageW[FPage];
    A := pd_pdfr_annot_at(FPane.FPdf, FPage, (X - R.Left) / Sc, (Y - R.Top) / Sc);
    if (A >= 0) and (pd_pdfr_annot_get(FPane.FPdf, FPage, A, Ann) = 0) and (Ann.kind = PD_ANNOT_LINK) then
    begin
      S := Ann.uri;
      if Copy(S, 1, 6) = '#page=' then
        GoTo_(StrToIntDef(Copy(S, 7, 10), 1) - 1)
      else if S <> '' then
        OpenURL(S);
      Exit;
    end;
  end;
  {$ENDIF}
  GoTo_(FPage + 1);
end;

procedure TLedPdfShow.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  FLastMove := GetTickCount64;
  if Cursor = crNone then
    Cursor := crDefault;
end;

function TLedPdfShow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta < 0 then GoTo_(FPage + 1) else GoTo_(FPage - 1);
  Result := True;
end;

procedure TLedPdfShow.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TLedPdfShow.DoClose(var CloseAction: TCloseAction);
begin
  inherited DoClose(CloseAction);
  CloseAction := caFree;
  { back in the view at the page shown last }
  if FPane <> nil then
  begin
    FPane.GoToPage(FPage);
    if FPane.FView.CanFocus then FPane.FView.SetFocus;
  end;
end;

end.
