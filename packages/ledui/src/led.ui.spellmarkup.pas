{ led - a light editor.  The red squiggle under a misspelled word.

  A TSynEditMarkup rather than custom painting, because SynEdit already knows
  how to draw a wavy underline -- slsWaved on the bottom frame edge -- and
  already asks, for every token it draws, whether any markup wants a say.
  That is more than medit managed: moospellcheck.cpp settled for a straight
  red line because Pango's error underline rendered flat in MooTextView.

  Words are checked lazily, one visible line at a time, and the answers for
  that line are cached until the line changes.  A document is only ever a
  screenful of lines away from the user, so there is nothing to gain from
  checking the rest. }
unit Led.UI.SpellMarkup;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, SynEdit, SynEditMarkup, SynEditMiscClasses,
  SynEditTypes, SynEditHighlighter, LazSynEditText,
  Led.Core.Spell;

type
  TLedSpellScope = (lssAll, lssCode, lssOff);

  TLedSpellMarkup = class(TSynEditMarkup)
  private
    FScope: TLedSpellScope;
    FCachedRow: Integer;
    FStarts, FEnds: array of Integer;   // 1-based logical, [start, end)
    FCount: Integer;
    procedure ScanRow(ARow: Integer);
    function InSpellableToken(ARow, ACol: Integer): Boolean;
  public
    constructor Create(ASynEdit: TSynEditBase);
    function GetMarkupAttributeAtRowCol(const aRow: Integer;
      const aStartCol: TLazSynDisplayTokenBound;
      const AnRtlInfo: TLazSynDisplayRtlInfo): TSynSelectedColor; override;
    procedure GetNextMarkupColAfterRowCol(const aRow: Integer;
      const aStartCol: TLazSynDisplayTokenBound;
      const AnRtlInfo: TLazSynDisplayRtlInfo;
      out ANextPhys, ANextLog: Integer); override;

    { Forces the next paint to re-check, after the dictionary changes. }
    procedure Invalidate;

    property Scope: TLedSpellScope read FScope write FScope;
  end;

{ The word under a logical column, and where it starts.  Shared with the
  context menu, so that what is offered corrections is exactly what was
  underlined. }
function LedWordAt(const ALine: string; ACol: Integer;
  out AStart, ALen: Integer): string;

implementation

function LedWordAt(const ALine: string; ACol: Integer;
  out AStart, ALen: Integer): string;

  function IsWordChar(C: Char): Boolean;
  begin
    Result := C in ['a'..'z', 'A'..'Z', ''''];
  end;

var
  i, j: Integer;
begin
  Result := '';
  AStart := 0;
  ALen := 0;
  if (ACol < 1) or (ACol > Length(ALine)) then Exit;
  if not IsWordChar(ALine[ACol]) then Exit;

  i := ACol;
  while (i > 1) and IsWordChar(ALine[i - 1]) do Dec(i);
  j := ACol;
  while (j < Length(ALine)) and IsWordChar(ALine[j + 1]) do Inc(j);

  { A leading or trailing apostrophe is quoting, not spelling. }
  while (i <= j) and (ALine[i] = '''') do Inc(i);
  while (j >= i) and (ALine[j] = '''') do Dec(j);
  if i > j then Exit;

  AStart := i;
  ALen := j - i + 1;
  Result := Copy(ALine, i, ALen);
end;

constructor TLedSpellMarkup.Create(ASynEdit: TSynEditBase);
begin
  inherited Create(ASynEdit);
  FScope := lssOff;
  FCachedRow := -1;
  { No foreground or background of its own: only the wavy underline, so the
    syntax colours underneath are untouched. }
  MarkupInfo.Foreground := clNone;
  MarkupInfo.Background := clNone;
  MarkupInfo.FrameColor := clRed;
  MarkupInfo.FrameEdges := sfeBottom;
  MarkupInfo.FrameStyle := slsWaved;
end;

procedure TLedSpellMarkup.Invalidate;
begin
  FCachedRow := -1;
end;

{ In code, only comments and strings are prose; everything else is
  identifiers and keywords, and underlining those makes the feature
  unusable.  With no highlighter there is nothing to ask, so everything
  counts as prose -- which is right for a plain text file. }
function TLedSpellMarkup.InSpellableToken(ARow, ACol: Integer): Boolean;
var
  Attr: TSynHighlighterAttributes;
  Stored, Token: string;
begin
  if FScope = lssAll then Exit(True);
  if TCustomSynEdit(SynEdit).Highlighter = nil then Exit(True);

  if not TCustomSynEdit(SynEdit).GetHighlighterAttriAtRowCol(
       Point(ACol, ARow), Token, Attr) then Exit(False);
  if Attr = nil then Exit(False);
  Stored := LowerCase(Attr.StoredName);
  Result := (Pos('comment', Stored) > 0) or (Pos('string', Stored) > 0) or
            (Pos('text', Stored) > 0) or (Pos('doc', Stored) > 0);
end;

procedure TLedSpellMarkup.ScanRow(ARow: Integer);
var
  Line, W: string;
  i, S, L: Integer;
begin
  FCount := 0;
  FCachedRow := ARow;
  if FScope = lssOff then Exit;
  if (ARow < 1) or (ARow > TCustomSynEdit(SynEdit).Lines.Count) then Exit;

  Line := TCustomSynEdit(SynEdit).Lines[ARow - 1];
  if Line = '' then Exit;

  i := 1;
  while i <= Length(Line) do
  begin
    W := LedWordAt(Line, i, S, L);
    if W = '' then
    begin
      Inc(i);
      Continue;
    end;
    if (not LedSpell.Check(W)) and InSpellableToken(ARow, S) then
    begin
      if FCount >= Length(FStarts) then
      begin
        SetLength(FStarts, FCount + 16);
        SetLength(FEnds, FCount + 16);
      end;
      FStarts[FCount] := S;
      FEnds[FCount] := S + L;
      Inc(FCount);
    end;
    i := S + L;
  end;
end;

function TLedSpellMarkup.GetMarkupAttributeAtRowCol(const aRow: Integer;
  const aStartCol: TLazSynDisplayTokenBound;
  const AnRtlInfo: TLazSynDisplayRtlInfo): TSynSelectedColor;
var
  i: Integer;
begin
  Result := nil;
  if FScope = lssOff then Exit;
  if aRow <> FCachedRow then ScanRow(aRow);

  for i := 0 to FCount - 1 do
    if (aStartCol.Logical >= FStarts[i]) and (aStartCol.Logical < FEnds[i]) then
    begin
      Result := MarkupInfo;
      MarkupInfo.SetFrameBoundsLog(FStarts[i], FEnds[i]);
      Exit;
    end;
end;

procedure TLedSpellMarkup.GetNextMarkupColAfterRowCol(const aRow: Integer;
  const aStartCol: TLazSynDisplayTokenBound;
  const AnRtlInfo: TLazSynDisplayRtlInfo; out ANextPhys, ANextLog: Integer);
var
  i: Integer;
begin
  ANextPhys := -1;
  ANextLog := -1;
  if FScope = lssOff then Exit;
  if aRow <> FCachedRow then ScanRow(aRow);

  { The next boundary at or after the caller's column: either the start of a
    misspelling or the end of the one we are inside. }
  for i := 0 to FCount - 1 do
  begin
    if FStarts[i] > aStartCol.Logical then
    begin
      ANextLog := FStarts[i];
      Exit;
    end;
    if FEnds[i] > aStartCol.Logical then
    begin
      ANextLog := FEnds[i];
      Exit;
    end;
  end;
end;

end.
