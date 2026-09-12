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
    function OffsetEndCol: Integer;
    function TextStartCol: Integer;
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
  end;

implementation

{ A between A and B, AFactorNum parts in AFactorDen.  The same mixing the
  fold gutter does, for the same reason: a colour that has to sit against the
  background without being invented. }
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
  FOffsetBack := Blend(AText, ABack, 7, 100);

  { The text column sits between the two: clearly not the bytes, clearly not
    the margin. }
  FTextFore := Blend(AText, ABack, 78, 100);

  { And the row being edited has its offset lifted back out.  The theme's
    current-line colour when it has one, so the band agrees with the row
    highlight the editor is already drawing. }
  FCurrentFore := AText;
  if ACurrentLine <> clNone then
    FCurrentBack := ACurrentLine
  else
    FCurrentBack := Blend(AText, ABack, 20, 100);
end;

function TLedHexMarkup.GetMarkupAttributeAtRowCol(const aRow: Integer;
  const aStartCol: TLazSynDisplayTokenBound;
  const AnRtlInfo: TLazSynDisplayRtlInfo): TSynSelectedColor;
var
  Col: Integer;
  OnCaretRow: Boolean;
begin
  Result := nil;
  if (not FEnabled) or (FOffsetFore = clNone) then Exit;
  Col := aStartCol.Logical;

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
  Col: Integer;
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
end;

end.
