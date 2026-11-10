{ The resources a page's document carries -- its pictures, metafiles, the
  drawings made from them, fonts, the parts kept to write back -- listed in
  the preview pane: a small picture of each, what it is, how large, and what
  it is made from or makes; sorted by any column, by size to find what makes
  a file large.

  The pane is the preview's: a document shown as pages has nothing for a
  Markdown preview to say, and what it is made of is the question that pane
  answers best for it.

  Pictures are decoded as the panes decode them (Led.UI.Pictures: WebP and
  SVG too); a drawing is drawn by Parade at a thumbnail's size, and a
  metafile shows the drawing its records make.  Each thumbnail is made the
  first time its row is drawn, and kept. }

unit Led.UI.ResPane;

{$mode objfpc}{$H+}
{$I led.parade.inc}

interface

{$IFDEF LED_PARADE}
uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Grids, Graphics, Types, Math, IntfGraphics, FPImage,
  GraphType, ctypes, parade, paradeedit, Led.UI.Pictures;

type
  TLedResSort = (lrsId, lrsKind, lrsSize, lrsDetails);

  TLedResItem = class
    Id: pd_res_id;
    Mime: string;
    Size: Int64;
    Kind: string;            { picture, metafile, drawing, font, ... }
    Details: string;
    DrawingOf: pd_res_id;    { a metafile: the drawing made from it }
    MadeFrom: pd_res_id;     { a drawing: the metafile it is made from }
    DW, DH: Int64;           { a drawing: its size, sp }
    Thumb: TBitmap;          { made when first drawn; nil until then }
    ThumbTried: Boolean;
    destructor Destroy; override;
  end;

  TLedResourcePane = class(TPanel)
  private
    FHead: TPanel;
    FSummary: TLabel;
    FGrid: TDrawGrid;
    FTimer: TTimer;
    FEdit: TParadeEdit;
    FDoc: Ppd_doc;
    FItems: TFPList;         { TLedResItem, in the order shown }
    FSort: TLedResSort;
    FDescending: Boolean;
    FPictures: TLedPictureCache;
    FThumbsMade: Integer;
    procedure ClearItems;
    procedure Build;
    procedure Order;
    procedure ShowCount;
    function Item(ARow: Integer): TLedResItem;
    function MakeThumb(It: TLedResItem): TBitmap;
    function DrawingThumb(AId: pd_res_id; W, H: Int64): TBitmap;
    function FindItem(AId: pd_res_id): TLedResItem;
    procedure GridDraw(Sender: TObject; ACol, ARow: Integer; ARect: TRect; AState: TGridDrawState);
    procedure GridHeader(Sender: TObject; IsColumn: Boolean; Index: Integer);
    procedure TimerTick(Sender: TObject);
    function Count_(ADoc: Ppd_doc): Integer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { the resources of the page's document (nil: none to show); built again only when the document or how many
      resources it has changes }
    procedure ShowPage(AEdit: TParadeEdit);
    { sorted by a column; Descending the other way round }
    procedure SortBy(ASort: TLedResSort; ADescending: Boolean);
    function RowCount_: Integer;
    { for tests: the item shown at row ARow (0 the first under the header) }
    function ItemAt(ARow: Integer): TLedResItem;
    { for tests: how many thumbnails have been made }
    property ThumbsMade: Integer read FThumbsMade;
    property Grid: TDrawGrid read FGrid;
    property Summary: TLabel read FSummary;
    property Sort: TLedResSort read FSort;
    property Descending: Boolean read FDescending;
  end;

{ a number of bytes as people read it: 940 B, 12.3 KB, 4.6 MB }
function LedByteSize(N: Int64): string;
{$ENDIF}

implementation

{$IFDEF LED_PARADE}
const
  ThumbW = 72;
  ThumbH = 54;
  DrawingMime = 'application/vnd.parade.drawing+json';

function LedByteSize(N: Int64): string;
begin
  if N < 1024 then
    Result := IntToStr(N) + ' B'
  else if N < 1024 * 1024 then
    Result := FormatFloat('0.#', N / 1024) + ' KB'
  else if N < Int64(1024) * 1024 * 1024 then
    Result := FormatFloat('0.#', N / (1024 * 1024)) + ' MB'
  else
    Result := FormatFloat('0.##', N / (Int64(1024) * 1024 * 1024)) + ' GB';
end;

{ a number after "Key": in a drawing's JSON head, or -1 }
function JsonInt(const S, Key: string): Int64;
var
  P, E: Integer;
begin
  Result := -1;
  P := Pos('"' + Key + '":', S);
  if P = 0 then
    Exit;
  P := P + Length(Key) + 3;
  E := P;
  while (E <= Length(S)) and (S[E] in ['0'..'9', '-']) do
    Inc(E);
  Result := StrToInt64Def(Copy(S, P, E - P), -1);
end;

function KindOf(const Mime: string): string;
begin
  if Mime = DrawingMime then
    Result := 'drawing'
  else if (Mime = 'image/x-emf') or (Mime = 'image/x-wmf') or (Mime = 'image/emf') or (Mime = 'image/wmf') then
    Result := 'metafile'
  else if Pos('image/', Mime) = 1 then
    Result := 'picture'
  else if (Pos('font/', Mime) = 1) or (Pos('font', Mime) > 0) then
    Result := 'font'
  else if Pos('video/', Mime) = 1 then
    Result := 'video'
  else if Pos('audio/', Mime) = 1 then
    Result := 'audio'
  else if Pos('vnd.parade', Mime) > 0 then
    Result := 'kept for writing back'
  else
    Result := 'data';
end;

function PictureExt(const Mime: string): string;
begin
  if Mime = 'image/png' then Result := '.png'
  else if (Mime = 'image/jpeg') or (Mime = 'image/jpg') then Result := '.jpg'
  else if Mime = 'image/gif' then Result := '.gif'
  else if Mime = 'image/bmp' then Result := '.bmp'
  else if Mime = 'image/tiff' then Result := '.tif'
  else if Mime = 'image/webp' then Result := '.webp'
  else if Mime = 'image/svg+xml' then Result := '.svg'
  else Result := '';
end;

destructor TLedResItem.Destroy;
begin
  Thumb.Free;
  inherited Destroy;
end;

constructor TLedResourcePane.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Name := 'ResPane';
  Caption := '';
  BevelOuter := bvNone;
  FItems := TFPList.Create;
  FPictures := TLedPictureCache.Create(4 * 1000 * 1000);
  FHead := TPanel.Create(Self);
  FHead.Parent := Self;
  FHead.Align := alTop;
  FHead.BevelOuter := bvNone;
  FHead.Height := 24;
  FHead.Caption := '';
  FSummary := TLabel.Create(Self);
  FSummary.Parent := FHead;
  FSummary.Name := 'ResSummary';
  FSummary.Align := alClient;
  FSummary.Layout := tlCenter;
  FSummary.BorderSpacing.Left := 6;
  FSummary.Caption := '';
  FGrid := TDrawGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Name := 'ResGrid';
  FGrid.Align := alClient;
  FGrid.ColCount := 4;
  FGrid.RowCount := 1;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.DefaultRowHeight := ThumbH + 6;
  FGrid.RowHeights[0] := 22;
  FGrid.ColWidths[0] := ThumbW + 8;     { the picture, its size, what it is, what it is made from }
  FGrid.ColWidths[1] := 70;
  FGrid.ColWidths[2] := 110;
  FGrid.ColWidths[3] := 240;
  FGrid.Options := FGrid.Options - [goRangeSelect, goVertLine] + [goRowSelect, goThumbTracking, goColSizing,
    goHeaderHotTracking, goHeaderPushedLook];
  FGrid.OnDrawCell := @GridDraw;
  FGrid.OnHeaderClick := @GridHeader;
  { a picture inserted while the pane shows: the list follows within a second, and is drawn again only then }
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 1000;
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTick;
  FSort := lrsId;
end;

destructor TLedResourcePane.Destroy;
begin
  ClearItems;
  FItems.Free;
  FPictures.Free;
  inherited Destroy;
end;

procedure TLedResourcePane.ClearItems;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    TLedResItem(FItems[I]).Free;
  FItems.Clear;
  FPictures.Clear;
end;

function TLedResourcePane.Count_(ADoc: Ppd_doc): Integer;
var
  M: PAnsiChar;
  D: Pointer;
  L: csize_t;
begin
  Result := 0;
  if ADoc = nil then
    Exit;
  while pd_doc_resource(ADoc, Result + 1, @M, @D, @L) = PD_OK do
    Inc(Result);
end;

function TLedResourcePane.FindItem(AId: pd_res_id): TLedResItem;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    if TLedResItem(FItems[I]).Id = AId then
      Exit(TLedResItem(FItems[I]));
  Result := nil;
end;

procedure TLedResourcePane.Build;
var
  N, I: Integer;
  M: PAnsiChar;
  D: Pointer;
  L: csize_t;
  It, Src: TLedResItem;
  Head: string;
begin
  ClearItems;
  N := Count_(FDoc);
  for I := 1 to N do
    if pd_doc_resource(FDoc, I, @M, @D, @L) = PD_OK then
    begin
      It := TLedResItem.Create;
      It.Id := I;
      It.Mime := StrPas(M);
      It.Size := L;
      It.Kind := KindOf(It.Mime);
      if (It.Mime = DrawingMime) and (L > 0) then
      begin   { its size and where it comes from: in the first bytes }
        SetString(Head, PAnsiChar(D), Min(Int64(L), 200));
        It.DW := JsonInt(Head, 'w');
        It.DH := JsonInt(Head, 'h');
        It.MadeFrom := Max(0, JsonInt(Head, 'src'));
      end;
      FItems.Add(It);
    end;
  for I := 0 to FItems.Count - 1 do
  begin
    It := TLedResItem(FItems[I]);
    if It.MadeFrom > 0 then
    begin
      Src := FindItem(It.MadeFrom);
      if (Src <> nil) and (Src.Kind = 'metafile') then
      begin
        Src.DrawingOf := It.Id;
        Src.DW := It.DW;
        Src.DH := It.DH;
      end;
    end;
  end;
  for I := 0 to FItems.Count - 1 do
  begin
    It := TLedResItem(FItems[I]);
    if It.Kind = 'drawing' then
    begin
      It.Details := FormatFloat('0.#', It.DW / PD_SP_PER_PT) + ' x ' + FormatFloat('0.#', It.DH / PD_SP_PER_PT) + ' pt';
      Src := FindItem(It.MadeFrom);
      if (Src <> nil) and (Src.Kind = 'metafile') then
        It.Details := It.Details + ', drawn from #' + IntToStr(It.MadeFrom) + ' (made again on load)'
      else if Src <> nil then
        It.Details := It.Details + ', from #' + IntToStr(It.MadeFrom);
    end
    else if It.Kind = 'metafile' then
    begin
      It.Details := It.Mime;
      if It.DrawingOf > 0 then
        It.Details := It.Details + ', drawn as #' + IntToStr(It.DrawingOf);
    end
    else
      It.Details := It.Mime;
  end;
  Order;
  ShowCount;
end;

procedure TLedResourcePane.ShowCount;
var
  I: Integer;
  Total: Int64;
begin
  Total := 0;
  for I := 0 to FItems.Count - 1 do
    Inc(Total, TLedResItem(FItems[I]).Size);
  if FDoc = nil then
    FSummary.Caption := 'No document shown as pages.'
  else if FItems.Count = 0 then
    FSummary.Caption := 'No embedded resources.'
  else
    FSummary.Caption := Format('%d resources, %s in all (click a heading to sort)', [FItems.Count, LedByteSize(Total)]);
  FGrid.RowCount := 1 + FItems.Count;
  FGrid.RowHeights[0] := 22;    { the headings' row: not a thumbnail's height }
  FGrid.Invalidate;
end;

var
  GSort: TLedResSort;
  GDesc: Boolean;

function CompareItems(A, B: Pointer): Integer;
var
  X: TLedResItem absolute A;
  Y: TLedResItem absolute B;
begin
  case GSort of
    lrsSize: Result := CompareValue(X.Size, Y.Size);
    lrsKind: Result := CompareText(X.Kind + ' ' + X.Mime, Y.Kind + ' ' + Y.Mime);
    lrsDetails: Result := CompareText(X.Details, Y.Details);
  else
    Result := 0;
  end;
  if Result = 0 then
    Result := CompareValue(Int64(X.Id), Int64(Y.Id));     { the same: in the document's order }
  if GDesc then
    Result := -Result;
end;

procedure TLedResourcePane.Order;
begin
  GSort := FSort;
  GDesc := FDescending;
  FItems.Sort(@CompareItems);
end;

procedure TLedResourcePane.SortBy(ASort: TLedResSort; ADescending: Boolean);
begin
  FSort := ASort;
  FDescending := ADescending;
  Order;
  FGrid.Invalidate;
end;

procedure TLedResourcePane.GridHeader(Sender: TObject; IsColumn: Boolean; Index: Integer);
var
  S: TLedResSort;
begin
  if not IsColumn then
    Exit;
  case Index of
    1: S := lrsSize;
    2: S := lrsKind;
    3: S := lrsDetails;
  else
    S := lrsId;
  end;
  if S = FSort then
    SortBy(S, not FDescending)
  else
    SortBy(S, S = lrsSize);     { by size: the largest first }
end;

procedure TLedResourcePane.ShowPage(AEdit: TParadeEdit);
var
  D: Ppd_doc;
begin
  FEdit := AEdit;
  if AEdit <> nil then
    D := AEdit.Doc
  else
    D := nil;
  if (D <> FDoc) or (Count_(D) <> FItems.Count) then
  begin
    FDoc := D;
    Build;
  end;
  FTimer.Enabled := (FDoc <> nil) and Visible;
end;

procedure TLedResourcePane.TimerTick(Sender: TObject);
begin
  if not IsVisible then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  if (FEdit <> nil) and ((FEdit.Doc <> FDoc) or (Count_(FEdit.Doc) <> FItems.Count)) then
  begin
    FDoc := FEdit.Doc;
    Build;
  end;
end;

function TLedResourcePane.Item(ARow: Integer): TLedResItem;
begin
  if (ARow >= 1) and (ARow <= FItems.Count) then
    Result := TLedResItem(FItems[ARow - 1])
  else
    Result := nil;
end;

function TLedResourcePane.ItemAt(ARow: Integer): TLedResItem;
begin
  Result := Item(ARow + 1);
end;

function TLedResourcePane.RowCount_: Integer;
begin
  Result := FItems.Count;
end;

{ a drawing drawn by Parade to fit a thumbnail, over white }
function TLedResourcePane.DrawingThumb(AId: pd_res_id; W, H: Int64): TBitmap;
var
  Sc: Double;
  PW, PH, X, Y, K, A: Integer;
  Buf: array of Byte;
  Img: TLazIntfImage;
  Col: TFPColor;
begin
  Result := nil;
  if (W <= 0) or (H <= 0) then
    Exit;
  Sc := Min(ThumbW / (W / PD_SP_PER_PT), ThumbH / (H / PD_SP_PER_PT));    { pixels a point }
  PW := Max(1, Round(W / PD_SP_PER_PT * Sc));
  PH := Max(1, Round(H / PD_SP_PER_PT * Sc));
  SetLength(Buf, PW * PH * 4);
  FillChar(Buf[0], Length(Buf), 0);
  if pd_drawing_render(FDoc, AId, W, H, Round(Sc * 65536), @Buf[0], PW, PH, PW * 4) <> PD_OK then
    Exit;
  Img := TLazIntfImage.Create(PW, PH, [riqfRGB]);
  try
    for Y := 0 to PH - 1 do
      for X := 0 to PW - 1 do
      begin   { premultiplied: over white }
        K := (Y * PW + X) * 4;
        A := 255 - Buf[K + 3];
        Col.Red := Min(255, Buf[K] + A) * 257;
        Col.Green := Min(255, Buf[K + 1] + A) * 257;
        Col.Blue := Min(255, Buf[K + 2] + A) * 257;
        Col.Alpha := alphaOpaque;
        Img.Colors[X, Y] := Col;
      end;
    Result := TBitmap.Create;
    Result.LoadFromIntfImage(Img);
  finally
    Img.Free;
  end;
end;

function TLedResourcePane.MakeThumb(It: TLedResItem): TBitmap;
var
  M: PAnsiChar;
  D: Pointer;
  L: csize_t;
  Bytes, Ext: string;
  Pic: TPicture;
  Sc: Double;
  W, H: Integer;
begin
  Result := nil;
  if It.Kind = 'drawing' then
    Result := DrawingThumb(It.Id, It.DW, It.DH)
  else if (It.Kind = 'metafile') and (It.DrawingOf > 0) then
    Result := DrawingThumb(It.DrawingOf, It.DW, It.DH)
  else if It.Kind = 'picture' then
  begin
    Ext := PictureExt(It.Mime);
    if (Ext = '') or (pd_doc_resource(FDoc, It.Id, @M, @D, @L) <> PD_OK) then
      Exit;
    SetString(Bytes, PAnsiChar(D), L);
    Pic := nil;
    try
      Pic := FPictures.Get('res' + IntToStr(It.Id), Bytes, Ext, 0);
      if (Pic = nil) or (Pic.Width <= 0) or (Pic.Height <= 0) then
        Exit;
      Sc := Min(1.0, Min(ThumbW / Pic.Width, ThumbH / Pic.Height));
      W := Max(1, Round(Pic.Width * Sc));
      H := Max(1, Round(Pic.Height * Sc));
      Result := TBitmap.Create;
      Result.PixelFormat := pf24bit;
      Result.SetSize(W, H);
      Result.Canvas.Brush.Color := clWhite;
      Result.Canvas.FillRect(0, 0, W, H);
      Result.Canvas.StretchDraw(Rect(0, 0, W, H), Pic.Graphic);
    except
      FreeAndNil(Result);
    end;
    Pic.Free;
  end;
  if Result <> nil then
    Inc(FThumbsMade);
end;

procedure TLedResourcePane.GridDraw(Sender: TObject; ACol, ARow: Integer; ARect: TRect; AState: TGridDrawState);
const
  Heads: array[0..3] of string = ('#', 'Size', 'Kind', 'Details');
  ColOf: array[TLedResSort] of Integer = (0, 2, 1, 3);
var
  C: TCanvas;
  It: TLedResItem;
  S: string;
  X, Y: Integer;
  TS: TTextStyle;
begin
  C := FGrid.Canvas;
  TS := C.TextStyle;
  TS.Layout := tlCenter;
  TS.SingleLine := True;
  TS.EndEllipsis := True;
  if ARow = 0 then
  begin
    S := Heads[ACol];
    if ACol = ColOf[FSort] then
      if FDescending then S := S + ' '#$E2#$96#$BC else S := S + ' '#$E2#$96#$B2;
    TS.Alignment := taLeftJustify;
    C.TextRect(Rect(ARect.Left + 4, ARect.Top, ARect.Right - 2, ARect.Bottom), ARect.Left + 4, ARect.Top, S, TS);
    Exit;
  end;
  It := Item(ARow);
  if It = nil then
    Exit;
  case ACol of
    0:
      begin
        if not It.ThumbTried then
        begin   { made once, when first seen }
          It.ThumbTried := True;
          It.Thumb := MakeThumb(It);
        end;
        if It.Thumb <> nil then
        begin
          X := ARect.Left + (ARect.Right - ARect.Left - It.Thumb.Width) div 2;
          Y := ARect.Top + (ARect.Bottom - ARect.Top - It.Thumb.Height) div 2;
          C.Draw(X, Y, It.Thumb);
          C.Pen.Color := clGray;
          C.Brush.Style := bsClear;
          C.Rectangle(X - 1, Y - 1, X + It.Thumb.Width + 1, Y + It.Thumb.Height + 1);
        end
        else
        begin
          TS.Alignment := taCenter;
          C.Font.Color := clGrayText;
          C.TextRect(ARect, ARect.Left, ARect.Top, '#' + IntToStr(It.Id), TS);
          C.Font.Color := clWindowText;
        end;
      end;
    1:
      begin
        TS.Alignment := taRightJustify;
        C.TextRect(Rect(ARect.Left + 2, ARect.Top, ARect.Right - 6, ARect.Bottom), ARect.Left + 2, ARect.Top,
          LedByteSize(It.Size), TS);
      end;
    2:
      begin
        TS.Alignment := taLeftJustify;
        C.TextRect(Rect(ARect.Left + 4, ARect.Top, ARect.Right - 2, ARect.Bottom), ARect.Left + 4, ARect.Top,
          '#' + IntToStr(It.Id) + ' ' + It.Kind, TS);
      end;
    3:
      begin
        TS.Alignment := taLeftJustify;
        C.TextRect(Rect(ARect.Left + 4, ARect.Top, ARect.Right - 2, ARect.Bottom), ARect.Left + 4, ARect.Top,
          It.Details, TS);
      end;
  end;
end;
{$ENDIF}

end.
