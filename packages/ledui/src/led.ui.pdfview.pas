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
  Buttons, Types, IntfGraphics, GraphType
  {$IFDEF LED_PARADE}, paradepdf{$ENDIF};

{ a file the PDF pages open: its name says so }
function LedPdfFileName(const AFileName: string): Boolean;
{ this LED reads PDF (it was built with Parade) }
function LedPdfAvailable: Boolean;

type
  TLedPdfTool = (ptSelect, ptHighlight, ptUnderline, ptStrikeOut, ptSquiggly, ptNote, ptTextBox, ptInk,
    ptRect, ptEllipse, ptLine, ptArrow);

  { The pages: what is drawn, where each page is, the mouse on them. }
  TLedPdfPane = class;

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
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TLedPdfCharArray = {$IFDEF LED_PARADE}TPdfChars{$ELSE}array of Integer{$ENDIF};

  TLedPdfPane = class(TCustomPanel)
  private
    {$IFDEF LED_PARADE}
    FPdf: Ppd_pdfr;
    {$ENDIF}
    FFileName: string;
    FView: TLedPdfView;
    FVBar, FHBar: TScrollBar;
    FTools: TToolBar;
    FToolButtons: array[TLedPdfTool] of TToolButton;
    FColorBtn: TColorButton;
    FZoomBox: TComboBox;
    FFindBar: TPanel;
    FFindEdit: TEdit;
    FFindNote: TLabel;
    FMenu: TPopupMenu;
    FTool: TLedPdfTool;
    FScale: Double;             // pixels a point
    FFit: Integer;              // 0 none, 1 width, 2 page
    FScrollX, FScrollY: Integer;
    FPageTop: array of Integer;     // each page's top, in pixels at the scale (the gaps included)
    FPageW, FPageH: array of Double; // its size in points
    FChars: array of TLedPdfCharArray;
    FCharsOk: array of Boolean;
    FCache: array of TBitmap;       // each page drawn whole at the scale (nil: not yet, or too big to keep)
    FCacheImg: array of TLazIntfImage;  // its pixels (the selection is tinted into a copy)
    FCacheScale: Double;
    FCacheChanges: Integer;
    FCacheOrder: TList;             // pages with a cached bitmap, the most recently drawn last
    { the text selected: on one page, characters FSelA..FSelB-1 }
    FSelPage, FSelA, FSelB, FSelAnchor: Integer;
    FSelecting: Boolean;
    { what Find found }
    FFoundPage, FFoundA, FFoundB: Integer;
    { an annotation picked (Delete, drag, colour) }
    FAnnPage, FAnnIndex: Integer;
    FDragAnn: Boolean;
    FDragStart, FDragNow: TPoint;
    { a shape, box or ink being drawn }
    FDrawing: Boolean;
    FDrawPage: Integer;
    FDrawStart, FDrawNow: TPoint;
    FInk: array of TPoint;
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
    procedure DrawPage(C: TCanvas; APage: Integer; const R: TRect);
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
    procedure ViewKey(var Key: Word; Shift: TShiftState);
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
    { the text selected marked: PD_ANNOT_HIGHLIGHT, _UNDERLINE, _STRIKEOUT or _SQUIGGLY, in the tool's colour }
    procedure MarkSelectionAs(AKind: Integer);
    { the text found, from the start of APage on: True if it was (the page shows it, it is selected) }
    function FindText(const AText: string; AFromPage: Integer = 0): Boolean;
    property Tool: TLedPdfTool read FTool write SetTool;
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
  Clipbrd, Math, StrUtils, Led.UI.Dpi;

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
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := True;
  DoubleBuffered := True;
  Color := $00808080;
end;

procedure TLedPdfView.Paint;
var
  i: Integer;
  R: TRect;
begin
  Canvas.Brush.Color := $00707070;
  Canvas.FillRect(ClientRect);
  if FPane = nil then Exit;
  for i := 0 to FPane.PageCount - 1 do
  begin
    R := FPane.PageRectOnView(i);
    if R.Bottom < 0 then Continue;
    if R.Top > ClientHeight then Break;
    FPane.DrawPage(Canvas, i, R);
  end;
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
  FFit := 1;
  FSelPage := -1;
  FFoundPage := -1;
  FAnnPage := -1;
  FFieldIndex := -1;
  FCacheOrder := TList.Create;
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
  AddItem('Note &Text...', @MenuNoteText);
  AddItem('Annotation C&olour...', @MenuColorAnn);
  AddItem('&Delete Annotation', @MenuDeleteAnn);
  FView.PopupMenu := FMenu;
end;

destructor TLedPdfPane.Destroy;
begin
  ClearCache;
  FCacheOrder.Free;
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
  Hints: array[TLedPdfTool] of string = ('Select text, links, form fields and annotations',
    'Highlight text: drag over it', 'Underline text', 'Strike text out', 'A wavy underline',
    'A sticky note: click where it goes', 'A box of text: drag it out', 'Draw freehand',
    'A rectangle: drag it out', 'An ellipse: drag it out', 'A line: drag it out', 'An arrow: drag it out');
var
  T: TLedPdfTool;
  B: TToolButton;
  Sep: TToolButton;
begin
  FTools := TToolBar.Create(Self);
  FTools.Parent := Self;
  FTools.Align := alTop;
  FTools.ShowCaptions := True;
  FTools.List := True;
  FTools.AutoSize := True;
  FTools.EdgeBorders := [];
  for T := Low(TLedPdfTool) to High(TLedPdfTool) do
  begin
    B := TToolButton.Create(FTools);
    B.Left := 1000 * (Ord(T) + 1);
    B.Parent := FTools;
    B.Caption := Names[T];
    B.Hint := Hints[T];
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

  FColorBtn := TColorButton.Create(FTools);
  FColorBtn.Parent := FTools;
  FColorBtn.Width := LedScale96(40);
  FColorBtn.ButtonColor := RGBToColor(255, 220, 0);
  FColorBtn.Hint := 'The colour of what the tools make';
  FColorBtn.ShowHint := True;
  FColorBtn.Left := FToolButtons[ptArrow].Left + FToolButtons[ptArrow].Width + 1;

  FZoomBox := TComboBox.Create(FTools);
  FZoomBox.Parent := FTools;
  FZoomBox.Width := LedScale96(90);
  FZoomBox.Style := csDropDownList;
  FZoomBox.Items.CommaText := '"Fit width","Fit page",50%,75%,100%,110%,125%,150%,200%,300%,400%';
  FZoomBox.ItemIndex := 0;
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

{ ---- loading ---- }

function TLedPdfPane.Load(const ABytes: RawByteString; const AFileName: string; out AWhy: string): Boolean;
{$IFDEF LED_PARADE}
var
  P: Ppd_pdfr;
  St: Integer;
  Pw: string;
  i: Integer;
  W, H: Double;
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
  if FPdf <> nil then pd_pdfr_free(FPdf);
  FPdf := P;
  FFileName := AFileName;
  ClearCache;
  SetLength(FPageW, pd_pdfr_page_count(P));
  SetLength(FPageH, Length(FPageW));
  SetLength(FChars, Length(FPageW));
  SetLength(FCharsOk, Length(FPageW));
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
begin
  FScrollY := FVBar.Position;
  FScrollX := FHBar.Position;
  CancelField;
  FView.Invalidate;
  Status;
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
  FZoomBox.ItemIndex := -1;
  SetScaleKeep(FScale * AFactor);
end;

procedure TLedPdfPane.ZoomFitWidth;
begin
  FFit := 1;
  FZoomBox.ItemIndex := 0;
  SetScaleKeep(FScale);
end;

procedure TLedPdfPane.ZoomChange(Sender: TObject);
var
  S: string;
begin
  S := FZoomBox.Text;
  if FZoomBox.ItemIndex = 0 then
    FFit := 1
  else if FZoomBox.ItemIndex = 1 then
    FFit := 2
  else
  begin
    FFit := 0;
    SetScaleKeep(StrToFloatDef(StringReplace(S, '%', '', []), 100) / 100 * 96 / 72);
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
  for i := AFrom to ATo - 1 do
  begin
    if C[i].flags and PD_PDFR_CHAR_NEWLINE <> 0 then Continue;
    X0 := Floor(C[i].x0 * FScale) - AOffX;
    Y0 := Floor(C[i].y0 * FScale) - AOffY;
    X1 := Ceil(C[i].x1 * FScale) - AOffX;
    Y1 := Ceil(C[i].y1 * FScale) - AOffY;
    { a space put in where words are apart spans the gap between them }
    if (C[i].flags and PD_PDFR_CHAR_SPACE <> 0) and (i + 1 < Length(C)) then
      X1 := Floor(C[i + 1].x0 * FScale) - AOffX;
    X0 := Max(X0, 0);
    Y0 := Max(Y0, 0);
    X1 := Min(X1, Img.Width);
    Y1 := Min(Y1, Img.Height);
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

procedure TLedPdfPane.DrawPage(C: TCanvas; APage: Integer; const R: TRect);
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
    if Vis.Left < 0 then Vis.Left := 0;
    if Vis.Top < 0 then Vis.Top := 0;
    if Vis.Right > FView.ClientWidth then Vis.Right := FView.ClientWidth;
    if Vis.Bottom > FView.ClientHeight then Vis.Bottom := FView.ClientHeight;
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

  { the annotation picked: a dashed frame (where it is dragged to, while it is) }
  if (FAnnPage = APage) and (FAnnIndex >= 0) and (pd_pdfr_annot_get(FPdf, APage, FAnnIndex, A) = 0) then
  begin
    P0 := ToView(APage, A.x0, A.y0);
    P1 := ToView(APage, A.x1, A.y1);
    if FDragAnn then
    begin
      Inc(P0.X, FDragNow.X - FDragStart.X);
      Inc(P1.X, FDragNow.X - FDragStart.X);
      Inc(P0.Y, FDragNow.Y - FDragStart.Y);
      Inc(P1.Y, FDragNow.Y - FDragStart.Y);
    end;
    C.Brush.Style := bsClear;
    C.Pen.Color := RGBToColor(0, 90, 220);
    C.Pen.Style := psDash;
    C.Pen.Width := 1;
    C.Rectangle(P0.X - 3, P0.Y - 3, P1.X + 3, P1.Y + 3);
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
    FCharsOk[APage] := True;
  end;
  Result := FChars[APage];
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
    F.Width := LedScale96(420);
    F.Height := LedScale96(IfThen(AMulti, 240, 140));
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
    { the menu acts on the annotation under it, or the selection }
    A := pd_pdfr_annot_at(FPdf, Page, PX, PY);
    if (A >= 0) and (pd_pdfr_annot_get(FPdf, Page, A, Ann) = 0) and not (Ann.kind in [PD_ANNOT_LINK, PD_ANNOT_WIDGET]) then
    begin
      FAnnPage := Page;
      FAnnIndex := A;
      FView.Invalidate;
    end;
    Exit;
  end;
  if Button <> mbLeft then Exit;

  case FTool of
    ptSelect:
      begin
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
  PX, PY: Double;
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
  if FDragAnn then
  begin
    FDragNow := Point(X, Y);
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
  { the pointer: a hand over a link, a beam over text }
  if FTool = ptSelect then
  begin
    Page := PageAt(X, Y, PX, PY);
    if Page < 0 then
    begin
      FView.Cursor := crDefault;
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
  PX, PY, QX, QY, W: Double;
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
    VK_ESCAPE:
      begin
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
  for i := 0 to FMenu.Items.Count - 1 do
    case i of
      0..5: FMenu.Items[i].Enabled := SelAvail;
      7..9: FMenu.Items[i].Enabled := HasAnn;
    end;
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
begin
  {$IFDEF LED_PARADE}
  if not SelAvail then Exit;
  S := SelectedText;
  if AskText('Edit Text', 'The selected text, as it should read:', S, False) then
    if pd_pdfr_replace_text(FPdf, FSelPage, FSelA, FSelB, PAnsiChar(S)) = 0 then
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

end.
