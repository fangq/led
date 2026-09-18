// led - a lightweight editor.  How many cells a character takes on a grid.
//
// A terminal is a grid of equal cells, and most characters fill one.  Two
// kinds do not: an East Asian ideograph, kana or fullwidth form is drawn two
// cells wide, and a combining mark is drawn on top of the character before it
// and takes none of its own.  Every terminal emulator carries a table like
// this one -- it is wcwidth(3) in POSIX, and the ranges come from Unicode's
// East Asian Width property (UAX #11).
//
// Why LED needs it: the terminal pane draws one cell per character at a fixed
// advance, so without this a Chinese character was drawn over the top of its
// right-hand neighbour and every column after it on the line was wrong.
//
// The table is the common set rather than the complete property: the ranges
// below cover Han, kana, Hangul, the fullwidth forms, the CJK compatibility
// blocks and the emoji that are Wide, which is what turns up in a terminal.
// A character outside them counts as one cell, which is what an unknown
// character should do -- it is what the font will draw.

unit Led.Core.CharWidth;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{ The cells one character takes: 2 for a double-width character, 0 for a
  combining mark, 1 for everything else -- including the empty string, since
  a cell that holds nothing still is one. }
function LedCharCells(const AChar: string): Integer;

{ The same question asked of a code point. }
function LedCodepointCells(ACode: Cardinal): Integer;

{ The first code point of a UTF-8 string, or 0.  Malformed input gives the
  byte itself, so a broken sequence is still one cell wide rather than an
  exception. }
function LedFirstCodepoint(const AText: string): Cardinal;

implementation

type
  TLedRange = record
    First, Last: Cardinal;
  end;

const
  { Combining marks and other zero-width characters, in order.  A mark is
    drawn over the character it follows, so it advances the cursor by
    nothing. }
  Zero: array[0..17] of TLedRange = (
    (First: $0300; Last: $036F),      // combining diacritical marks
    (First: $0483; Last: $0489),      // Cyrillic
    (First: $0591; Last: $05BD),      // Hebrew points
    (First: $05BF; Last: $05BF),
    (First: $0610; Last: $061A),      // Arabic
    (First: $064B; Last: $065F),
    (First: $0670; Last: $0670),
    (First: $0900; Last: $0903),      // Devanagari
    (First: $093A; Last: $093C),
    (First: $0941; Last: $0948),
    (First: $0E31; Last: $0E31),      // Thai
    (First: $0E34; Last: $0E3A),
    (First: $0E47; Last: $0E4E),
    (First: $200B; Last: $200F),      // zero width space, marks
    (First: $20D0; Last: $20F0),      // combining marks for symbols
    (First: $FE00; Last: $FE0F),      // variation selectors
    (First: $FE20; Last: $FE2F),      // combining half marks
    (First: $FEFF; Last: $FEFF)       // byte order mark
  );

  { Double-width, in order. }
  Wide: array[0..20] of TLedRange = (
    (First: $1100; Last: $115F),      // Hangul Jamo, initial consonants
    (First: $2E80; Last: $303E),      // CJK radicals .. CJK symbols
    (First: $3041; Last: $33FF),      // kana .. CJK compatibility
    (First: $3400; Last: $4DBF),      // CJK extension A
    (First: $4E00; Last: $9FFF),      // CJK unified ideographs
    (First: $A000; Last: $A4CF),      // Yi
    (First: $A960; Last: $A97F),      // Hangul Jamo extended A
    (First: $AC00; Last: $D7A3),      // Hangul syllables
    (First: $F900; Last: $FAFF),      // CJK compatibility ideographs
    (First: $FE10; Last: $FE19),      // vertical forms
    (First: $FE30; Last: $FE6F),      // CJK compatibility forms
    (First: $FF00; Last: $FF60),      // fullwidth forms
    (First: $FFE0; Last: $FFE6),      // fullwidth signs
    (First: $16FE0; Last: $16FE4),    // Tangut, Nushu marks
    (First: $17000; Last: $187F7),    // Tangut
    (First: $18800; Last: $18CD5),    // Tangut components
    (First: $1B000; Last: $1B2FF),    // kana supplement
    (First: $1F300; Last: $1F64F),    // emoji
    (First: $1F900; Last: $1F9FF),    // supplemental symbols, emoji
    (First: $20000; Last: $2FFFD),    // CJK extension B ..
    (First: $30000; Last: $3FFFD)     // CJK extension G ..
  );

function InRanges(ACode: Cardinal; const ARanges: array of TLedRange): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Result := False;
  { Binary search: the tables are in order, and this is asked once per
    character drawn. }
  Lo := 0;
  Hi := High(ARanges);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if ACode < ARanges[Mid].First then
      Hi := Mid - 1
    else if ACode > ARanges[Mid].Last then
      Lo := Mid + 1
    else
      Exit(True);
  end;
end;

function LedCodepointCells(ACode: Cardinal): Integer;
begin
  { Control characters have no width of their own; the terminal acts on them
    rather than drawing them. }
  if ACode < 32 then Exit(0);
  if (ACode >= $7F) and (ACode < $A0) then Exit(0);
  if ACode < $300 then Exit(1);       { the common case, before any table }
  if InRanges(ACode, Zero) then Exit(0);
  if InRanges(ACode, Wide) then Exit(2);
  Result := 1;
end;

function LedFirstCodepoint(const AText: string): Cardinal;
var
  B: Byte;
  Need, i: Integer;
begin
  Result := 0;
  if AText = '' then Exit;
  B := Byte(AText[1]);
  if B < $80 then Exit(B);

  if (B and $E0) = $C0 then begin Result := B and $1F; Need := 1; end
  else if (B and $F0) = $E0 then begin Result := B and $0F; Need := 2; end
  else if (B and $F8) = $F0 then begin Result := B and $07; Need := 3; end
  else Exit(B);                       { a stray continuation byte: itself }

  if Length(AText) < Need + 1 then Exit(B);
  for i := 2 to Need + 1 do
  begin
    B := Byte(AText[i]);
    if (B and $C0) <> $80 then Exit(Byte(AText[1]));
    Result := (Result shl 6) or (B and $3F);
  end;
end;

function LedCharCells(const AChar: string): Integer;
begin
  if AChar = '' then Exit(1);
  if Byte(AChar[1]) < $80 then
  begin
    { ASCII, which is every cell of every log file: answered without
      decoding anything. }
    if Byte(AChar[1]) < 32 then Exit(0);
    if Byte(AChar[1]) = $7F then Exit(0);
    Exit(1);
  end;
  Result := LedCodepointCells(LedFirstCodepoint(AChar));
end;

end.
