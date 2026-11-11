unit led.ui.pdfsign;

{ Signatures for a PDF's forms: one drawn with the mouse or a pen, a name typed in a handwriting font, or a picture
  of one (a scan, a photograph), kept in LED's settings to be put on page after page. These are pictures of a
  signature, as one signed on paper and scanned would be: not a digital (certificate) signature. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Graphics, Controls, Forms, StdCtrls, ExtCtrls, ComCtrls, Dialogs, ExtDlgs,
  IntfGraphics, GraphType, FPImage, FPReadPNG, FPReadJPEG, FPReadBMP, FPReadGIF, FPWritePNG, Contnrs,
  Clipbrd, LCLType;

type
  TLedSignatureKind = (lskInk, lskImage);

  { A signature: strokes in a box W by H (drawn), or pixels (typed, or a picture) }
  TLedSignature = class
  public
    Kind: TLedSignatureKind;
    W, H: Double;                       { ink: its box; the strokes' points lie in it }
    Strokes: array of TDoubleDynArray;  { ink: x, y pairs }
    Color: TColor;                      { ink: its colour }
    PixW, PixH: Integer;                { image: its size }
    RGBA: RawByteString;                { image: 4 bytes a pixel, top row first }
    Jpeg: RawByteString;                { a JPEG's own bytes when it came as one ('' else) }
    Path: string;                       { where it is kept ('' if it is not) }
    function Aspect: Double;            { width over height }
    { a picture of it, for a menu or the dialog }
    function Thumb(AW, AH: Integer): TBitmap;
  end;

{ where signatures are kept }
function LedSignatureDir: string;
{ those kept, oldest first (the list owns them) }
procedure LedLoadSignatures(AList: TObjectList);
function LedSaveSignature(S: TLedSignature): Boolean;
procedure LedForgetSignature(S: TLedSignature);
{ the New Signature dialog: Draw, Type or Image; nil if cancelled (AKeep: to be kept for later) }
function LedNewSignature(AOwner: TComponent; out AKeep: Boolean): TLedSignature;

{ a picture file read as RGBA pixels; a JPEG, unless APixels, as its own bytes instead (RGBA ''); False if it cannot
  be read }
function LedLoadPictureRGBA(const AFileName: string; out W, H: Integer; out RGBA, Jpeg: RawByteString;
  APixels: Boolean = False): Boolean;
{ the picture on the clipboard as RGBA pixels; False if there is none }
function LedClipboardPictureRGBA(out W, H: Integer; out RGBA: RawByteString): Boolean;
{ a bitmap's pixels as RGBA (opaque) }
function LedBitmapRGBA(B: TBitmap; out W, H: Integer): RawByteString;
{ near-white made clear (a signature scanned on paper): alpha from how dark each pixel is }
procedure LedClearWhite(var RGBA: RawByteString; W, H: Integer);

implementation

uses
  led.core.paths;

const
  SIG_MAX_PIXELS = 4096 * 4096;

function TLedSignature.Aspect: Double;
begin
  if Kind = lskInk then
  begin
    if H > 0 then Result := W / H else Result := 3;
  end
  else if PixH > 0 then
    Result := PixW / PixH
  else
    Result := 3;
end;

function TLedSignature.Thumb(AW, AH: Integer): TBitmap;
var
  Sc, OX, OY: Double;
  i, k, X, Y, SX, SY: Integer;
  R, G, B, A: Integer;
  P: PByte;
begin
  Result := TBitmap.Create;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := clWhite;
  Result.Canvas.FillRect(0, 0, AW, AH);
  if Kind = lskInk then
  begin
    if (W <= 0) or (H <= 0) then Exit;
    Sc := Min((AW - 4) / W, (AH - 4) / H);
    OX := (AW - W * Sc) / 2;
    OY := (AH - H * Sc) / 2;
    Result.Canvas.Pen.Color := Color;
    Result.Canvas.Pen.Width := Max(1, Round(AH / 24));
    for i := 0 to High(Strokes) do
      for k := 0 to Length(Strokes[i]) div 2 - 1 do
      begin
        X := Round(OX + Strokes[i][2 * k] * Sc);
        Y := Round(OY + Strokes[i][2 * k + 1] * Sc);
        if k = 0 then Result.Canvas.MoveTo(X, Y) else Result.Canvas.LineTo(X, Y);
        if Length(Strokes[i]) = 2 then Result.Canvas.LineTo(X + 1, Y);
      end;
  end
  else if (PixW > 0) and (PixH > 0) and (Length(RGBA) >= PixW * PixH * 4) then
  begin
    Sc := Min((AW - 4) / PixW, (AH - 4) / PixH);
    OX := (AW - PixW * Sc) / 2;
    OY := (AH - PixH * Sc) / 2;
    for Y := 0 to AH - 1 do
      for X := 0 to AW - 1 do
      begin
        SX := Floor((X - OX) / Sc);
        SY := Floor((Y - OY) / Sc);
        if (SX < 0) or (SY < 0) or (SX >= PixW) or (SY >= PixH) then Continue;
        P := PByte(@RGBA[1]) + (SY * PixW + SX) * 4;
        A := P[3];
        R := (P[0] * A + 255 * (255 - A)) div 255;
        G := (P[1] * A + 255 * (255 - A)) div 255;
        B := (P[2] * A + 255 * (255 - A)) div 255;
        Result.Canvas.Pixels[X, Y] := RGBToColor(R, G, B);
      end;
  end;
end;

{ ---- the pixels of pictures ---- }

function LedBitmapRGBA(B: TBitmap; out W, H: Integer): RawByteString;
var
  Img: TLazIntfImage;
  X, Y: Integer;
  C: TFPColor;
  P: PByte;
begin
  Result := '';
  W := B.Width;
  H := B.Height;
  if (W <= 0) or (H <= 0) or (Int64(W) * H > SIG_MAX_PIXELS) then Exit;
  Img := B.CreateIntfImage;
  try
    SetLength(Result, W * H * 4);
    P := PByte(@Result[1]);
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        C := Img.Colors[X, Y];
        P[0] := C.red shr 8;
        P[1] := C.green shr 8;
        P[2] := C.blue shr 8;
        P[3] := 255;
        Inc(P, 4);
      end;
  finally
    Img.Free;
  end;
end;

{ a JPEG's size from its frame header; False if it has none }
function JpegSize(const J: RawByteString; out W, H: Integer): Boolean;
var
  i, Len: Integer;
  M: Byte;
begin
  Result := False;
  W := 0;
  H := 0;
  if (Length(J) < 4) or (J[1] <> #$FF) or (J[2] <> #$D8) then Exit;
  i := 3;
  while i + 8 <= Length(J) do
  begin
    if J[i] <> #$FF then
    begin
      Inc(i);
      Continue;
    end;
    M := Ord(J[i + 1]);
    if (M = $FF) then
    begin
      Inc(i);
      Continue;
    end;
    if (M = $D8) or (M = $01) or ((M >= $D0) and (M <= $D7)) then
    begin
      Inc(i, 2);
      Continue;
    end;
    Len := (Ord(J[i + 2]) shl 8) or Ord(J[i + 3]);
    if (M in [$C0..$C3, $C5..$C7, $C9..$CB, $CD..$CF]) then
    begin
      H := (Ord(J[i + 5]) shl 8) or Ord(J[i + 6]);
      W := (Ord(J[i + 7]) shl 8) or Ord(J[i + 8]);
      Exit((W > 0) and (H > 0));
    end;
    if (M = $D9) or (M = $DA) then Exit;
    Inc(i, 2 + Len);
  end;
end;

function LedLoadPictureRGBA(const AFileName: string; out W, H: Integer; out RGBA, Jpeg: RawByteString;
  APixels: Boolean): Boolean;
var
  Img: TLazIntfImage;
  Fs: TFileStream;
  X, Y: Integer;
  C: TFPColor;
  P: PByte;
  Ext: string;
begin
  Result := False;
  RGBA := '';
  Jpeg := '';
  W := 0;
  H := 0;
  Ext := LowerCase(ExtractFileExt(AFileName));
  try
    { a JPEG goes in as it is: no second compression, its size from its header }
    if not APixels and ((Ext = '.jpg') or (Ext = '.jpeg')) then
    begin
      Fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
      try
        SetLength(Jpeg, Fs.Size);
        if Fs.Size > 0 then Fs.ReadBuffer(Jpeg[1], Fs.Size);
      finally
        Fs.Free;
      end;
      if JpegSize(Jpeg, W, H) then Exit(True);
      Jpeg := '';
    end;
    Img := TLazIntfImage.Create(0, 0, [riqfRGB, riqfAlpha]);
    try
      Img.LoadFromFile(AFileName);
      W := Img.Width;
      H := Img.Height;
      if (W <= 0) or (H <= 0) or (Int64(W) * H > SIG_MAX_PIXELS) then Exit;
      SetLength(RGBA, W * H * 4);
      P := PByte(@RGBA[1]);
      for Y := 0 to H - 1 do
        for X := 0 to W - 1 do
        begin
          C := Img.Colors[X, Y];
          P[0] := C.red shr 8;
          P[1] := C.green shr 8;
          P[2] := C.blue shr 8;
          P[3] := C.alpha shr 8;
          Inc(P, 4);
        end;
      Result := True;
    finally
      Img.Free;
    end;
  except
    Result := False;
  end;
end;

function LedClipboardPictureRGBA(out W, H: Integer; out RGBA: RawByteString): Boolean;
var
  Pic: TPicture;
  B: TBitmap;
begin
  Result := False;
  RGBA := '';
  W := 0;
  H := 0;
  if not Clipboard.HasPictureFormat then Exit;
  Pic := TPicture.Create;
  B := TBitmap.Create;
  try
    try
      Pic.Assign(Clipboard);
      B.SetSize(Pic.Width, Pic.Height);
      B.Canvas.Brush.Color := clWhite;
      B.Canvas.FillRect(0, 0, B.Width, B.Height);
      B.Canvas.Draw(0, 0, Pic.Graphic);
      RGBA := LedBitmapRGBA(B, W, H);
      Result := RGBA <> '';
    except
      Result := False;
    end;
  finally
    B.Free;
    Pic.Free;
  end;
end;

procedure LedClearWhite(var RGBA: RawByteString; W, H: Integer);
var
  i, L, A: Integer;
  P: PByte;
begin
  if Length(RGBA) < W * H * 4 then Exit;
  UniqueString(RGBA);
  P := PByte(@RGBA[1]);
  for i := 0 to W * H - 1 do
  begin
    L := (P[0] * 299 + P[1] * 587 + P[2] * 114) div 1000;
    { paper (lighter than 225) clear; ink dark; between, partly }
    if L >= 225 then A := 0
    else if L <= 120 then A := 255
    else A := (225 - L) * 255 div 105;
    P[3] := Min(P[3], A);
    Inc(P, 4);
  end;
end;

{ ---- kept ---- }

function LedSignatureDir: string;
begin
  Result := IncludeTrailingPathDelimiter(LedConfigDir) + 'signatures' + PathDelim;
end;

function ColorHex(C: TColor): string;
begin
  C := ColorToRGB(C);
  Result := IntToHex(Red(C), 2) + IntToHex(Green(C), 2) + IntToHex(Blue(C), 2);
end;

function LoadInk(const APath: string): TLedSignature;
var
  Sl, Parts: TStringList;
  i, k: Integer;
  Line: string;
  V: TDoubleDynArray;
  Fmt: TFormatSettings;
begin
  Result := nil;
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  Sl := TStringList.Create;
  Parts := TStringList.Create;
  try
    Sl.LoadFromFile(APath);
    if (Sl.Count < 3) or (Sl[0] <> 'led-signature 1') then Exit;
    Result := TLedSignature.Create;
    Result.Kind := lskInk;
    Result.Path := APath;
    Result.Color := clBlack;
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    for i := 1 to Sl.Count - 1 do
    begin
      Line := Trim(Sl[i]);
      Parts.DelimitedText := Line;
      if Parts.Count = 0 then Continue;
      if (Parts[0] = 'color') and (Parts.Count = 2) and (Length(Parts[1]) = 6) then
        Result.Color := RGBToColor(StrToIntDef('$' + Copy(Parts[1], 1, 2), 0),
          StrToIntDef('$' + Copy(Parts[1], 3, 2), 0), StrToIntDef('$' + Copy(Parts[1], 5, 2), 0))
      else if (Parts[0] = 'box') and (Parts.Count = 3) then
      begin
        Result.W := StrToFloatDef(Parts[1], 0, Fmt);
        Result.H := StrToFloatDef(Parts[2], 0, Fmt);
      end
      else if (Parts[0] = 'stroke') and (Parts.Count >= 3) then
      begin
        SetLength(V, (Parts.Count - 1) and not 1);
        for k := 0 to High(V) do
          V[k] := StrToFloatDef(Parts[k + 1], 0, Fmt);
        SetLength(Result.Strokes, Length(Result.Strokes) + 1);
        Result.Strokes[High(Result.Strokes)] := V;
      end;
    end;
    if (Result.W <= 0) or (Result.H <= 0) or (Length(Result.Strokes) = 0) then
      FreeAndNil(Result);
  finally
    Parts.Free;
    Sl.Free;
  end;
end;

function LoadImageSig(const APath: string): TLedSignature;
var
  W, H: Integer;
  RGBA, Jpeg: RawByteString;
begin
  Result := nil;
  if not LedLoadPictureRGBA(APath, W, H, RGBA, Jpeg, True) or (RGBA = '') then Exit;
  Result := TLedSignature.Create;
  Result.Kind := lskImage;
  Result.PixW := W;
  Result.PixH := H;
  Result.RGBA := RGBA;
  Result.Path := APath;
end;

procedure LedLoadSignatures(AList: TObjectList);
var
  Sr: TSearchRec;
  Names: TStringList;
  i: Integer;
  S: TLedSignature;
begin
  AList.Clear;
  Names := TStringList.Create;
  try
    if FindFirst(LedSignatureDir + 'sig-*', faAnyFile, Sr) = 0 then
    begin
      repeat
        if (Sr.Attr and faDirectory) = 0 then Names.Add(Sr.Name);
      until FindNext(Sr) <> 0;
      FindClose(Sr);
    end;
    Names.Sort;
    for i := 0 to Names.Count - 1 do
    begin
      S := nil;
      try
        if LowerCase(ExtractFileExt(Names[i])) = '.ink' then
          S := LoadInk(LedSignatureDir + Names[i])
        else if LowerCase(ExtractFileExt(Names[i])) = '.png' then
          S := LoadImageSig(LedSignatureDir + Names[i]);
      except
        S := nil;
      end;
      if S <> nil then AList.Add(S);
    end;
  finally
    Names.Free;
  end;
end;

function LedSaveSignature(S: TLedSignature): Boolean;
var
  Sl: TStringList;
  i, k: Integer;
  Line, Base: string;
  Img: TLazIntfImage;
  Wr: TFPWriterPNG;
  X, Y: Integer;
  P: PByte;
  C: TFPColor;
  Fmt: TFormatSettings;
begin
  Result := False;
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  try
    ForceDirectories(LedSignatureDir);
    Base := LedSignatureDir + 'sig-' + FormatDateTime('yyyymmdd-hhnnsszzz', Now);
    if S.Kind = lskInk then
    begin
      Sl := TStringList.Create;
      try
        Sl.Add('led-signature 1');
        Sl.Add('color ' + ColorHex(S.Color));
        Sl.Add('box ' + FloatToStrF(S.W, ffFixed, 0, 2, Fmt) + ' ' + FloatToStrF(S.H, ffFixed, 0, 2, Fmt));
        for i := 0 to High(S.Strokes) do
        begin
          Line := 'stroke';
          for k := 0 to High(S.Strokes[i]) do
            Line := Line + ' ' + FloatToStrF(S.Strokes[i][k], ffFixed, 0, 2, Fmt);
          Sl.Add(Line);
        end;
        Sl.SaveToFile(Base + '.ink');
        S.Path := Base + '.ink';
      finally
        Sl.Free;
      end;
    end
    else
    begin
      Img := TLazIntfImage.Create(S.PixW, S.PixH, [riqfRGB, riqfAlpha]);
      Wr := TFPWriterPNG.Create;
      try
        Img.CreateData;
        P := PByte(@S.RGBA[1]);
        for Y := 0 to S.PixH - 1 do
          for X := 0 to S.PixW - 1 do
          begin
            C.red := P[0] * 257;
            C.green := P[1] * 257;
            C.blue := P[2] * 257;
            C.alpha := P[3] * 257;
            Img.Colors[X, Y] := C;
            Inc(P, 4);
          end;
        Wr.UseAlpha := True;
        Img.SaveToFile(Base + '.png', Wr);
        S.Path := Base + '.png';
      finally
        Wr.Free;
        Img.Free;
      end;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

procedure LedForgetSignature(S: TLedSignature);
begin
  if (S <> nil) and (S.Path <> '') and (Pos(LedSignatureDir, S.Path) = 1) then
    DeleteFile(S.Path);
end;

{ ---- the dialog ---- }

type
  TSigDialog = class(TForm)
  public
    Pages: TPageControl;
    Pad: TPaintBox;
    NameEdit: TEdit;
    FontBox: TComboBox;
    TypedView: TPaintBox;
    ImageView: TPaintBox;
    ClearPaper: TCheckBox;
    InkBlue: TCheckBox;
    Keep: TCheckBox;
    Strokes: array of TDoubleDynArray;
    Drawing: Boolean;
    ImgW, ImgH: Integer;
    ImgRGBA, ImgShown: RawByteString;
    ImgThumb: TBitmap;
    procedure PadPaint(Sender: TObject);
    procedure PadDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PadMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PadUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ClearClick(Sender: TObject);
    procedure TypedChange(Sender: TObject);
    procedure TypedPaint(Sender: TObject);
    procedure ChooseClick(Sender: TObject);
    procedure ImagePaint(Sender: TObject);
    procedure ClearPaperClick(Sender: TObject);
    procedure InkChange(Sender: TObject);
    function InkColor: TColor;
    function Make: TLedSignature;
    destructor Destroy; override;
  end;

destructor TSigDialog.Destroy;
begin
  ImgThumb.Free;
  inherited Destroy;
end;

function TSigDialog.InkColor: TColor;
begin
  if InkBlue.Checked then Result := RGBToColor(0, 40, 140) else Result := clBlack;
end;

procedure TSigDialog.InkChange(Sender: TObject);
begin
  Pad.Invalidate;
  TypedView.Invalidate;
end;

procedure TSigDialog.PadPaint(Sender: TObject);
var
  i, k: Integer;
  C: TCanvas;
begin
  C := Pad.Canvas;
  C.Brush.Color := clWhite;
  C.FillRect(0, 0, Pad.Width, Pad.Height);
  { the line it is signed on }
  C.Pen.Color := RGBToColor(190, 190, 190);
  C.Pen.Width := 1;
  C.Line(16, Pad.Height * 3 div 4, Pad.Width - 16, Pad.Height * 3 div 4);
  if Length(Strokes) = 0 then
  begin
    C.Font.Color := RGBToColor(150, 150, 150);
    C.TextOut(16, 8, 'Sign here with the mouse, a touchpad or a pen');
  end;
  C.Pen.Color := InkColor;
  C.Pen.Width := 3;
  for i := 0 to High(Strokes) do
    for k := 0 to Length(Strokes[i]) div 2 - 1 do
      if k = 0 then
      begin
        C.MoveTo(Round(Strokes[i][0]), Round(Strokes[i][1]));
        C.LineTo(Round(Strokes[i][0]) + 1, Round(Strokes[i][1]));
      end
      else
        C.LineTo(Round(Strokes[i][2 * k]), Round(Strokes[i][2 * k + 1]));
end;

procedure TSigDialog.PadDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then Exit;
  Drawing := True;
  SetLength(Strokes, Length(Strokes) + 1);
  SetLength(Strokes[High(Strokes)], 2);
  Strokes[High(Strokes)][0] := X;
  Strokes[High(Strokes)][1] := Y;
  Pad.Invalidate;
end;

procedure TSigDialog.PadMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  N: Integer;
begin
  if not Drawing then Exit;
  N := Length(Strokes[High(Strokes)]);
  { a point only when it has moved a little: a smoother line, a smaller file }
  if (Abs(Strokes[High(Strokes)][N - 2] - X) + Abs(Strokes[High(Strokes)][N - 1] - Y)) < 2 then Exit;
  SetLength(Strokes[High(Strokes)], N + 2);
  Strokes[High(Strokes)][N] := X;
  Strokes[High(Strokes)][N + 1] := Y;
  Pad.Invalidate;
end;

procedure TSigDialog.PadUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  Drawing := False;
end;

procedure TSigDialog.ClearClick(Sender: TObject);
begin
  Strokes := nil;
  Pad.Invalidate;
end;

{ the typed name drawn large in its font, black on white (its own bitmap: the caller frees it) }
function TypedBitmap(const AName, AFont: string; AColor: TColor; APx: Integer): TBitmap;
var
  Sz: TSize;
begin
  Result := TBitmap.Create;
  Result.Canvas.Font.Name := AFont;
  Result.Canvas.Font.Height := -APx;
  Result.Canvas.Font.Quality := fqAntialiased;
  Sz := Result.Canvas.TextExtent(AName);
  Result.SetSize(Max(1, Sz.cx + APx div 2), Max(1, Sz.cy + APx div 4));
  Result.Canvas.Brush.Color := clWhite;
  Result.Canvas.FillRect(0, 0, Result.Width, Result.Height);
  Result.Canvas.Font.Name := AFont;
  Result.Canvas.Font.Height := -APx;
  Result.Canvas.Font.Quality := fqAntialiased;
  Result.Canvas.Font.Color := AColor;
  Result.Canvas.Brush.Style := bsClear;
  Result.Canvas.TextOut(APx div 4, APx div 8, AName);
end;

procedure TSigDialog.TypedChange(Sender: TObject);
begin
  TypedView.Invalidate;
end;

procedure TSigDialog.TypedPaint(Sender: TObject);
var
  B: TBitmap;
  Sc: Double;
  R: TRect;
begin
  TypedView.Canvas.Brush.Color := clWhite;
  TypedView.Canvas.FillRect(0, 0, TypedView.Width, TypedView.Height);
  if Trim(NameEdit.Text) = '' then Exit;
  B := TypedBitmap(NameEdit.Text, FontBox.Text, InkColor, 64);
  try
    Sc := Min((TypedView.Width - 8) / B.Width, (TypedView.Height - 8) / B.Height);
    R := Rect(4, 4, 4 + Round(B.Width * Sc), 4 + Round(B.Height * Sc));
    TypedView.Canvas.StretchDraw(R, B);
  finally
    B.Free;
  end;
end;

procedure TSigDialog.ChooseClick(Sender: TObject);
var
  Dlg: TOpenPictureDialog;
  J: RawByteString;
  W, H: Integer;
begin
  Dlg := TOpenPictureDialog.Create(Self);
  try
    Dlg.Title := 'A picture of your signature';
    Dlg.Filter := 'Pictures|*.png;*.jpg;*.jpeg;*.bmp;*.gif|All files|*';
    if not Dlg.Execute then Exit;
    if not LedLoadPictureRGBA(Dlg.FileName, W, H, ImgRGBA, J, True) or (ImgRGBA = '') then
    begin
      MessageDlg('Signature', 'That picture cannot be read.', mtWarning, [mbOK], 0);
      Exit;
    end;
    ImgW := W;
    ImgH := H;
    ClearPaperClick(nil);
  finally
    Dlg.Free;
  end;
end;

procedure TSigDialog.ClearPaperClick(Sender: TObject);
var
  S: TLedSignature;
begin
  ImgShown := ImgRGBA;
  if ClearPaper.Checked then LedClearWhite(ImgShown, ImgW, ImgH);
  FreeAndNil(ImgThumb);
  if ImgShown <> '' then
  begin
    S := TLedSignature.Create;
    try
      S.Kind := lskImage;
      S.PixW := ImgW;
      S.PixH := ImgH;
      S.RGBA := ImgShown;
      ImgThumb := S.Thumb(Max(1, ImageView.Width), Max(1, ImageView.Height));
    finally
      S.Free;
    end;
  end;
  ImageView.Invalidate;
end;

procedure TSigDialog.ImagePaint(Sender: TObject);
begin
  ImageView.Canvas.Brush.Color := clWhite;
  ImageView.Canvas.FillRect(0, 0, ImageView.Width, ImageView.Height);
  if ImgThumb <> nil then
    ImageView.Canvas.Draw(0, 0, ImgThumb)
  else
  begin
    ImageView.Canvas.Font.Color := RGBToColor(150, 150, 150);
    ImageView.Canvas.TextOut(8, 8, 'A scan or a photograph of your signature on white paper');
  end;
end;

function TSigDialog.Make: TLedSignature;
var
  i, k: Integer;
  X0, Y0, X1, Y1: Double;
  B: TBitmap;
  W, H: Integer;
begin
  Result := nil;
  case Pages.ActivePageIndex of
    0:
      begin
        if Length(Strokes) = 0 then Exit;
        X0 := 1e30; Y0 := 1e30; X1 := -1e30; Y1 := -1e30;
        for i := 0 to High(Strokes) do
          for k := 0 to Length(Strokes[i]) div 2 - 1 do
          begin
            X0 := Min(X0, Strokes[i][2 * k]);
            X1 := Max(X1, Strokes[i][2 * k]);
            Y0 := Min(Y0, Strokes[i][2 * k + 1]);
            Y1 := Max(Y1, Strokes[i][2 * k + 1]);
          end;
        Result := TLedSignature.Create;
        Result.Kind := lskInk;
        Result.Color := InkColor;
        { its box: what it covers, a little round it (a dot: some width) }
        Result.W := Max(X1 - X0, 4) + 6;
        Result.H := Max(Y1 - Y0, 4) + 6;
        SetLength(Result.Strokes, Length(Strokes));
        for i := 0 to High(Strokes) do
        begin
          SetLength(Result.Strokes[i], Length(Strokes[i]));
          for k := 0 to Length(Strokes[i]) div 2 - 1 do
          begin
            Result.Strokes[i][2 * k] := Strokes[i][2 * k] - X0 + 3;
            Result.Strokes[i][2 * k + 1] := Strokes[i][2 * k + 1] - Y0 + 3;
          end;
        end;
      end;
    1:
      begin
        if Trim(NameEdit.Text) = '' then Exit;
        B := TypedBitmap(Trim(NameEdit.Text), FontBox.Text, clBlack, 160);
        try
          Result := TLedSignature.Create;
          Result.Kind := lskImage;
          Result.RGBA := LedBitmapRGBA(B, W, H);
          Result.PixW := W;
          Result.PixH := H;
          LedClearWhite(Result.RGBA, W, H);
          { the ink's colour where it is dark }
          for i := 0 to W * H - 1 do
          begin
            Result.RGBA[4 * i + 1] := Chr(Red(ColorToRGB(InkColor)));
            Result.RGBA[4 * i + 2] := Chr(Green(ColorToRGB(InkColor)));
            Result.RGBA[4 * i + 3] := Chr(Blue(ColorToRGB(InkColor)));
          end;
        finally
          B.Free;
        end;
      end;
    2:
      begin
        if ImgShown = '' then Exit;
        Result := TLedSignature.Create;
        Result.Kind := lskImage;
        Result.PixW := ImgW;
        Result.PixH := ImgH;
        Result.RGBA := ImgShown;
      end;
  end;
end;

{ fonts that look written by hand, those this computer has, the likeliest first: a word of the name starting so
  ("Z003", "URW Chancery", "Dancing Script", "Homemade Apple"), not a script's letters for mathematics or an old
  inscription }
procedure HandFonts(AItems: TStrings);
const
  Hints: array[0..15] of string = ('z003', 'signature', 'chancery', 'script', 'brush', 'handwriting', 'hand',
    'cursive', 'dancing', 'vibes', 'allura', 'sacramento', 'pacifico', 'caveat', 'homemade', 'comic');
  Skip: array[0..3] of string = ('math', 'inscriptional', 'mono', 'symbol');

  function WordStarts(const AName, AHint: string): Boolean;
  var
    i: Integer;
  begin
    Result := False;
    for i := 1 to Length(AName) - Length(AHint) + 1 do
      if ((i = 1) or not (AName[i - 1] in ['a'..'z'])) and (Copy(AName, i, Length(AHint)) = AHint) then
        Exit(True);
  end;

var
  i, k, j: Integer;
  L: string;
  Bad: Boolean;
begin
  AItems.Clear;
  for k := 0 to High(Hints) do
    for i := 0 to Screen.Fonts.Count - 1 do
    begin
      L := LowerCase(Screen.Fonts[i]);
      Bad := False;
      for j := 0 to High(Skip) do
        if Pos(Skip[j], L) > 0 then Bad := True;
      if not Bad and WordStarts(L, Hints[k]) and (AItems.IndexOf(Screen.Fonts[i]) < 0) then
        AItems.Add(Screen.Fonts[i]);
    end;
  if AItems.Count = 0 then
  begin
    AItems.Add('Serif');
    AItems.Add('Sans');
  end;
end;

function LedNewSignature(AOwner: TComponent; out AKeep: Boolean): TLedSignature;
var
  D: TSigDialog;
  Tab: TTabSheet;
  B: TButton;
  Bottom: TPanel;
  L: TLabel;
begin
  Result := nil;
  AKeep := False;
  D := TSigDialog.CreateNew(AOwner);
  try
    D.Caption := 'New Signature';
    D.Position := poOwnerFormCenter;
    D.Width := 560;
    D.Height := 340;
    D.BorderStyle := bsDialog;

    Bottom := TPanel.Create(D);
    Bottom.Parent := D;
    Bottom.Align := alBottom;
    Bottom.Height := 44;
    Bottom.BevelOuter := bvNone;
    D.InkBlue := TCheckBox.Create(D);
    D.InkBlue.Parent := Bottom;
    D.InkBlue.Caption := 'Blue ink';
    D.InkBlue.Left := 10;
    D.InkBlue.Top := 12;
    D.InkBlue.OnChange := @D.InkChange;
    D.Keep := TCheckBox.Create(D);
    D.Keep.Parent := Bottom;
    D.Keep.Caption := 'Keep it for next time';
    D.Keep.Checked := True;
    D.Keep.Left := 110;
    D.Keep.Top := 12;
    B := TButton.Create(D);
    B.Parent := Bottom;
    B.Caption := 'Cancel';
    B.ModalResult := mrCancel;
    B.Cancel := True;
    B.SetBounds(D.Width - 100, 8, 88, 28);
    B := TButton.Create(D);
    B.Parent := Bottom;
    B.Caption := 'OK';
    B.ModalResult := mrOK;
    B.Default := True;
    B.SetBounds(D.Width - 196, 8, 88, 28);

    D.Pages := TPageControl.Create(D);
    D.Pages.Parent := D;
    D.Pages.Align := alClient;

    Tab := D.Pages.AddTabSheet;
    Tab.Caption := 'Draw';
    D.Pad := TPaintBox.Create(D);
    D.Pad.Parent := Tab;
    D.Pad.SetBounds(8, 8, 520, 190);
    D.Pad.OnPaint := @D.PadPaint;
    D.Pad.OnMouseDown := @D.PadDown;
    D.Pad.OnMouseMove := @D.PadMove;
    D.Pad.OnMouseUp := @D.PadUp;
    D.Pad.Cursor := crCross;
    B := TButton.Create(D);
    B.Parent := Tab;
    B.Caption := 'Clear';
    B.SetBounds(8, 204, 80, 26);
    B.OnClick := @D.ClearClick;

    Tab := D.Pages.AddTabSheet;
    Tab.Caption := 'Type';
    L := TLabel.Create(D);
    L.Parent := Tab;
    L.Caption := 'Your name:';
    L.SetBounds(8, 12, 80, 20);
    D.NameEdit := TEdit.Create(D);
    D.NameEdit.Parent := Tab;
    D.NameEdit.SetBounds(90, 8, 200, 26);
    D.NameEdit.OnChange := @D.TypedChange;
    D.FontBox := TComboBox.Create(D);
    D.FontBox.Parent := Tab;
    D.FontBox.SetBounds(300, 8, 228, 26);
    D.FontBox.Style := csDropDownList;
    HandFonts(D.FontBox.Items);
    D.FontBox.ItemIndex := 0;
    D.FontBox.OnChange := @D.TypedChange;
    D.TypedView := TPaintBox.Create(D);
    D.TypedView.Parent := Tab;
    D.TypedView.SetBounds(8, 44, 520, 150);
    D.TypedView.OnPaint := @D.TypedPaint;

    Tab := D.Pages.AddTabSheet;
    Tab.Caption := 'Image';
    B := TButton.Create(D);
    B.Parent := Tab;
    B.Caption := 'Choose a Picture…';
    B.SetBounds(8, 8, 150, 26);
    B.OnClick := @D.ChooseClick;
    D.ClearPaper := TCheckBox.Create(D);
    D.ClearPaper.Parent := Tab;
    D.ClearPaper.Caption := 'Make the paper clear';
    D.ClearPaper.Checked := True;
    D.ClearPaper.SetBounds(170, 12, 200, 20);
    D.ClearPaper.OnChange := @D.ClearPaperClick;
    D.ImageView := TPaintBox.Create(D);
    D.ImageView.Parent := Tab;
    D.ImageView.SetBounds(8, 44, 520, 150);
    D.ImageView.OnPaint := @D.ImagePaint;

    D.Pages.ActivePageIndex := 0;
    if D.ShowModal = mrOK then
    begin
      Result := D.Make;
      AKeep := D.Keep.Checked;
      if (Result = nil) then
        MessageDlg('New Signature', 'There is no signature yet: draw it, type your name or choose a picture.',
          mtInformation, [mbOK], 0);
    end;
  finally
    D.Free;
  end;
end;

end.
