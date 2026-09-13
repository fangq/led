{ led - a lightweight editor.  Telling a hex dump's three columns apart.

  A row is three things in a trench coat -- an offset, sixteen bytes, and the
  printable ones again -- and rendered in one colour they read as one wall of
  hexadecimal.  Every hex editor worth using colours them differently, and a
  reader relies on it: the eye finds the text column by its colour long
  before it finds it by counting.

  A markup rather than a highlighter.  A highlighter would have to be handed
  to the view, taking the place of the language one, and would still know
  nothing about where the caret is -- which is the other half of the job,
  because the offset of the row being edited wants picking out.  A markup is
  asked about every token as it is drawn, and can see the editor it belongs
  to, so both fall out of the same object.

  The colours are derived from the theme rather than fixed, because led ships
  eight schemes and half of them are light.  What is constant is the
  relationship: offsets recede, bytes are the ordinary text colour, the text
  column sits between the two, and the row the caret is on has its offset
  lifted out with a band behind it. }
unit Led.UI.HexMarkup;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, SynEdit, SynEditMarkup, SynEditMiscClasses,
  SynEditTypes, LazSynEditText,
  Led.Core.Hex;

type
  TLedHexMarkup = class(TSynEditMarkup)
  private
    FEnabled: Boolean;
    FOffsetFore: TColor;
    FOffsetBack: TColor;
    FCurrentFore: TColor;
    FCurrentBack: TColor;
    FTextFore: TColor;
    FActiveBack: TColor;
    FMirrorBack: TColor;
    function OffsetEndCol: Integer;
    function TextStartCol: Integer;
    function ByteAtColumn(ACol: Integer): Integer;
    function RowHighlight(ARow: Integer; out AFirst, ALast: Integer;
      out AActiveIsText: Boolean): Boolean;
  public
    constructor Create(ASynEdit: TSynEditBase);

    function GetMarkupAttributeAtRowCol(const aRow: Integer;
      const aStartCol: TLazSynDisplayTokenBound;
      const AnRtlInfo: TLazSynDisplayRtlInfo): TSynSelectedColor; override;
    procedure GetNextMarkupColAfterRowCol(const aRow: Integer;
      const aStartCol: TLazSynDisplayTokenBound;
      const AnRtlInfo: TLazSynDisplayRtlInfo;
      out ANextPhys, ANextLog: Integer); override;

    { Recomputed from the theme whenever the editor's own colours change.
      ALineNumberFore is the gutter's, which is already the colour this
      theme uses for "a number in the margin". }
    procedure SetColours(AText, ABack, ALineNumberFore, ACurrentLine: TColor);

    { Off for an ordinary document, so the markup costs a comparison. }
    property Enabled: Boolean read FEnabled write FEnabled;
    { What the markup would paint behind the cell at ACol on ARow, or clNone
      where it paints nothing.  Public so the pairing can be checked without
      a screen: which cells light up, and which of the two is the brighter. }
    function BackgroundAt(ARow, ACol: Integer): TColor;
  end;

implementation

{ A between A and B, AFactorNum parts in AFactorDen.  The same mixing the
  fold gutter does, for the same reason: a colour that has to sit against the
  background without being invented. }
{ How far apart two colours are, summed over the three channels.  Crude on
  purpose: this decides whether one colour can be read off another, and a
  perceptual metric would be a lot of arithmetic for a threshold that is
  chosen by eye anyway. }
function Contrast(A, B: TColor): Integer;
begin
  A := ColorToRGB(A);
  B := ColorToRGB(B);
  Result := Abs((A and $FF) - (B and $FF))
          + Abs(((A shr 8) and $FF) - ((B shr 8) and $FF))
          + Abs(((A shr 16) and $FF) - ((B shr 16) and $FF));
end;

function Blend(A, B: TColor; AFactorNum, AFactorDen: Integer): TColor;
var
  R, G, Bl: Integer;
begin
  R  := ((A and $FF) * AFactorNum +
        (B and $FF) * (AFactorDen - AFactorNum)) div AFactorDen;
  G  := (((A shr 8) and $FF) * AFactorNum +
        ((B shr 8) and $FF) * (AFactorDen - AFactorNum)) div AFactorDen;
  Bl := (((A shr 16) and $FF) * AFactorNum +
        ((B shr 16) and $FF) * (AFactorDen - AFactorNum)) div AFactorDen;
  Result := TColor(R or (G shl 8) or (Bl shl 16));
end;

constructor TLedHexMarkup.Create(ASynEdit: TSynEditBase);
begin
  inherited Create(ASynEdit);
  FOffsetFore := clNone;
  FOffsetBack := clNone;
  FCurrentFore := clNone;
  FCurrentBack := clNone;
  FTextFore := clNone;
end;

function TLedHexMarkup.OffsetEndCol: Integer;
begin
  { The offset is everything before the first byte, less the two spaces that
    separate them -- those belong to neither and are left alone. }
  Result := LedHexByteColumn(0) - 2;
end;

function TLedHexMarkup.TextStartCol: Integer;
begin
  { From the opening bar rather than the first character, so the bars are
    part of the column they delimit rather than stray punctuation. }
  Result := LedHexTextColumn(0) - 1;
end;

procedure TLedHexMarkup.SetColours(AText, ABack, ALineNumberFore,
  ACurrentLine: TColor);
begin
  if (AText = clNone) or (ABack = clNone) then Exit;

  { Offsets recede.  The line-number colour when the theme has one, because
    that is what this column is; three of the shipped schemes do not, and
    there it is mixed by hand so the column still reads as secondary. }
  if ALineNumberFore <> clNone then
    FOffsetFore := ALineNumberFore
  else
    FOffsetFore := Blend(AText, ABack, 55, 100);
  { A band behind the whole column, faint enough to be a boundary rather than
    a stripe.  This is what makes three columns visible as three columns even
    where a theme's foregrounds are close together. }
  FOffsetBack := Blend(AText, ABack, 12, 100);

  { And the offsets are pushed away from that band until they can be read
    off it.  A theme's line-number colour is chosen to sit quietly against
    the page, not against a band mixed from it -- on oblivion the two came
    out close enough that the column was legible only if you knew it was
    there.  Pushed towards the text, which is the direction that gains
    contrast on a light scheme and on a dark one alike. }
  while (Contrast(FOffsetFore, FOffsetBack) < 60) and
        (FOffsetFore <> AText) do
    FOffsetFore := Blend(AText, FOffsetFore, 20, 100);

  { The text column sits between the two: clearly not the bytes, clearly not
    the margin. }
  FTextFore := Blend(AText, ABack, 78, 100);

  { The byte the caret is on, and the same byte on the other side.  Two
    strengths of the one colour rather than two colours: they are the same
    byte, and the pair should read as one thing seen twice.  The side being
    typed into is the stronger, which is the only way to tell from the shading
    alone which half a keystroke will reach. }
  if ACurrentLine <> clNone then
  begin
    FActiveBack := Blend(ACurrentLine, ABack, 170, 100);
    FMirrorBack := Blend(ACurrentLine, ABack, 80, 100);
  end
  else
  begin
    FActiveBack := Blend(AText, ABack, 34, 100);
    FMirrorBack := Blend(AText, ABack, 16, 100);
  end;

  { And the row being edited has its offset lifted back out.  The theme's
    current-line colour when it has one, so the band agrees with the row
    highlight the editor is already drawing. }
  FCurrentFore := AText;
  if ACurrentLine <> clNone then
    FCurrentBack := ACurrentLine
  else
    FCurrentBack := Blend(AText, ABack, 20, 100);
end;


{ The byte a column falls on, rounded onto the nearest one rather than
  refusing.  Led.Core.Hex answers -1 for the punctuation between pairs, which
  is right when deciding where a caret may rest and wrong when deciding what
  a drag covered -- a selection that starts on a space still means the byte
  beside it. }
function TLedHexMarkup.BackgroundAt(ARow, ACol: Integer): TColor;
var
  FirstB, LastB, Idx: Integer;
  ActiveIsText: Boolean;
begin
  Result := clNone;
  if (not FEnabled) or (ACol <= OffsetEndCol) then Exit;
  if not RowHighlight(ARow, FirstB, LastB, ActiveIsText) then Exit;
  Idx := LedHexColumnToIndex(ACol);
  if (Idx < FirstB) or (Idx > LastB) then Exit;
  if LedHexColumnIsText(ACol) = ActiveIsText then
    Result := FActiveBack
  else
    Result := FMirrorBack;
end;

function TLedHexMarkup.ByteAtColumn(ACol: Integer): Integer;
var
  i, Best, BestDist, C, D: Integer;
begin
  Result := LedHexColumnToIndex(ACol);
  if Result >= 0 then Exit;

  Best := -1;
  BestDist := MaxInt;
  for i := 0 to LedHexBytesPerLine - 1 do
  begin
    C := LedHexByteColumn(i);
    D := Abs(ACol - C);
    if D < BestDist then begin BestDist := D; Best := i; end;
    C := LedHexTextColumn(i);
    D := Abs(ACol - C);
    if D < BestDist then begin BestDist := D; Best := i; end;
  end;
  Result := Best;
end;

{ Which bytes of ARow are being pointed at, and from which side.

  A selection when there is one, the caret's own byte when there is not.  The
  side is taken from where the caret is, because that is where a keystroke
  would land -- including during a drag, where the caret travels with the
  moving end of the block. }
function TLedHexMarkup.RowHighlight(ARow: Integer; out AFirst, ALast: Integer;
  out AActiveIsText: Boolean): Boolean;
var
  Ed: TSynEdit;
  B1, B2: TPoint;
begin
  Result := False;
  AFirst := -1;
  ALast := -1;
  Ed := TSynEdit(SynEdit);
  AActiveIsText := LedHexColumnIsText(Ed.CaretX);

  if Ed.SelAvail then
  begin
    B1 := Ed.BlockBegin;
    B2 := Ed.BlockEnd;
    if (ARow < B1.Y) or (ARow > B2.Y) then Exit;
    AFirst := 0;
    ALast := LedHexBytesPerLine - 1;
    if ARow = B1.Y then AFirst := ByteAtColumn(B1.X);
    if ARow = B2.Y then ALast := ByteAtColumn(B2.X - 1);
  end
  else
  begin
    if ARow <> Ed.CaretY then Exit;
    AFirst := ByteAtColumn(Ed.CaretX);
    ALast := AFirst;
  end;

  if (AFirst < 0) or (ALast < AFirst) then Exit;
  if ALast > LedHexBytesPerLine - 1 then ALast := LedHexBytesPerLine - 1;
  Result := True;
end;

function TLedHexMarkup.GetMarkupAttributeAtRowCol(const aRow: Integer;
  const aStartCol: TLazSynDisplayTokenBound;
  const AnRtlInfo: TLazSynDisplayRtlInfo): TSynSelectedColor;
var
  Col, Idx, FirstB, LastB: Integer;
  OnCaretRow, ActiveIsText: Boolean;
begin
  Result := nil;
  if (not FEnabled) or (FOffsetFore = clNone) then Exit;
  Col := aStartCol.Logical;

  { The byte under the caret, or the run under the selection, shaded on both
    sides of the row: strongly where the typing would go, faintly on the
    matching cell opposite.  Reading a dump means going back and forth
    between the two halves, and this is the line between them drawn. }
  if (Col > OffsetEndCol) and RowHighlight(aRow, FirstB, LastB, ActiveIsText) then
  begin
    Idx := LedHexColumnToIndex(Col);
    if (Idx >= FirstB) and (Idx <= LastB) then
    begin
      if LedHexColumnIsText(Col) then
        MarkupInfo.Foreground := FTextFore
      else
        MarkupInfo.Foreground := clNone;
      if LedHexColumnIsText(Col) = ActiveIsText then
        MarkupInfo.Background := FActiveBack
      else
        MarkupInfo.Background := FMirrorBack;
      MarkupInfo.SetFrameBoundsLog(Col, Col + 1);
      Exit(MarkupInfo);
    end;
  end;

  if Col <= OffsetEndCol then
  begin
    OnCaretRow := aRow = TSynEdit(SynEdit).CaretY;
    MarkupInfo.Foreground := FCurrentFore;
    MarkupInfo.Background := FCurrentBack;
    if not OnCaretRow then
    begin
      MarkupInfo.Foreground := FOffsetFore;
      MarkupInfo.Background := FOffsetBack;
    end;
    MarkupInfo.SetFrameBoundsLog(1, OffsetEndCol + 1);
    Exit(MarkupInfo);
  end;

  if Col >= TextStartCol then
  begin
    MarkupInfo.Foreground := FTextFore;
    MarkupInfo.Background := clNone;
    MarkupInfo.SetFrameBoundsLog(TextStartCol,
      LedHexTextColumn(LedHexBytesPerLine - 1) + 2);
    Exit(MarkupInfo);
  end;

  { The bytes themselves keep the editor's own text colour: they are what the
    reader is reading, so they are the one column not tinted. }
end;

procedure TLedHexMarkup.GetNextMarkupColAfterRowCol(const aRow: Integer;
  const aStartCol: TLazSynDisplayTokenBound;
  const AnRtlInfo: TLazSynDisplayRtlInfo; out ANextPhys, ANextLog: Integer);
var
  Col, FirstB, LastB: Integer;
  ActiveIsText: Boolean;
begin
  ANextPhys := -1;
  ANextLog := -1;
  if not FEnabled then Exit;
  Col := aStartCol.Logical;

  { The next column boundary at or after the caller's, so SynEdit splits its
    tokens where the colour changes and nowhere else. }
  if Col <= OffsetEndCol then
    ANextLog := OffsetEndCol + 1
  else if Col < TextStartCol then
    ANextLog := TextStartCol;

  { On a row that carries the caret or part of the selection the colour can
    change at every column, so the answer is the next column.  That is a
    token per character on those rows and a handful on all the others, which
    is the right way round: the rows it costs anything on are the ones being
    looked at. }
  if RowHighlight(aRow, FirstB, LastB, ActiveIsText) then
    if (ANextLog < 0) or (Col + 1 < ANextLog) then
      ANextLog := Col + 1;
end;

end.
