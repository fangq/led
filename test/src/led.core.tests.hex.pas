{ led - a lightweight editor.  Headless tests for the hex dump. }
unit Led.Core.Tests.Hex;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Led.Core.Hex;

type
  TTestHex = class(TTestCase)
  private
    function Line(const ADump: string; AIndex: Integer): string;
  published
    procedure NulMakesItBinary;
    procedure PlainTextIsNot;
    procedure OnlyTheStartIsRead;
    procedure EmptyDumpsToNothing;
    procedure OneRowHasOffsetBytesAndText;
    procedure UnprintableBytesBecomeDots;
    procedure HighBytesBecomeDotsToo;
    procedure RowsAreSixteenBytes;
    procedure AShortLastRowKeepsItsColumns;
    procedure EveryRowIsTheSameWidth;
    procedure ColumnsMapBackToBytes;
    procedure PunctuationMapsToNoByte;
    procedure NoTrailingNewline;
    procedure ARowRendersTheSameAloneAsInADump;
    procedure NibblesAreHighThenLow;
    procedure TextColumnsAreNotHexColumns;
    procedure TypingAdvancesAcrossAByteThenOn;
    procedure TypingInTextAdvancesOneByte;
    procedure TheEndOfARowSaysSo;
    procedure SettingANibbleLeavesTheOtherAlone;
    procedure HexDigitsAreEitherCase;
  end;

implementation

function TTestHex.Line(const ADump: string; AIndex: Integer): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LineBreak := #10;
    L.Text := ADump;
    if AIndex < L.Count then Result := L[AIndex] else Result := '';
  finally
    L.Free;
  end;
end;

procedure TTestHex.NulMakesItBinary;
begin
  AssertTrue(LedLooksBinary('abc'#0'def'));
end;

procedure TTestHex.PlainTextIsNot;
begin
  AssertFalse(LedLooksBinary('plain text'));
  AssertFalse(LedLooksBinary(''));
  { UTF-8 is not binary, which is the misreading that would hurt most. }
  AssertFalse(LedLooksBinary('na'#$C3#$AF've r'#$C3#$A9'sum'#$C3#$A9));
end;

procedure TTestHex.OnlyTheStartIsRead;
var
  S: string;
begin
  { A NUL past the window is not looked for -- deciding costs a fixed amount
    of reading however big the file is. }
  S := StringOfChar('x', 9000) + #0;
  AssertFalse(LedLooksBinary(S));
end;

procedure TTestHex.EmptyDumpsToNothing;
begin
  AssertEquals('', LedHexDump(''));
end;

procedure TTestHex.OneRowHasOffsetBytesAndText;
begin
  AssertEquals('00000000  41 42 43                                          |ABC             |',
    LedHexDump('ABC'));
end;

procedure TTestHex.UnprintableBytesBecomeDots;
begin
  AssertEquals('00000000  09 0a 41', Copy(LedHexDump(#9#10'A'), 1, 18));
  { Tab and newline are not printable characters as far as a dump goes. }
  AssertTrue(Pos('|..A', LedHexDump(#9#10'A')) > 0);
end;

procedure TTestHex.HighBytesBecomeDotsToo;
begin
  { Above 127 there is no character without an encoding, and a hex dump is
    what you open when there is not one. }
  AssertEquals('..', Copy(LedHexDump(#$C3#$A9),
    LedHexTextColumn(0), 2));
end;

procedure TTestHex.RowsAreSixteenBytes;
var
  D: string;
begin
  D := LedHexDump(StringOfChar('A', 33));
  AssertEquals('the third row starts at 0x20', '00000020', Copy(Line(D, 2), 1, 8));
  AssertEquals('and there are three', '', Line(D, 3));
end;

procedure TTestHex.AShortLastRowKeepsItsColumns;
var
  D: string;
begin
  D := LedHexDump(StringOfChar('A', 17));
  AssertEquals('a short row is as wide as a full one',
    Length(Line(D, 0)), Length(Line(D, 1)));
end;

procedure TTestHex.EveryRowIsTheSameWidth;
var
  D: string;
  i, W: Integer;
  L: TStringList;
begin
  D := LedHexDump(StringOfChar('Z', 100));
  L := TStringList.Create;
  try
    L.LineBreak := #10;
    L.Text := D;
    W := Length(L[0]);
    for i := 1 to L.Count - 1 do
      AssertEquals('row ' + IntToStr(i), W, Length(L[i]));
  finally
    L.Free;
  end;
end;

procedure TTestHex.ColumnsMapBackToBytes;
var
  D: string;
  i: Integer;
begin
  D := LedHexDump('0123456789ABCDEF');
  { The column arithmetic has to agree with the line it describes, or a caret
    lands on the wrong byte.  Checked against the rendered row rather than
    against itself. }
  for i := 0 to LedHexBytesPerLine - 1 do
  begin
    { The column really holds that byte's character ... }
    AssertEquals('byte ' + IntToStr(i) + ' sits in its text column',
      '0123456789ABCDEF'[i + 1], D[LedHexTextColumn(i)]);
    { ... and both columns lead back to it. }
    AssertEquals('byte ' + IntToStr(i) + ' maps back from its hex column',
      i, LedHexColumnToIndex(LedHexByteColumn(i)));
    AssertEquals('and from its text column',
      i, LedHexColumnToIndex(LedHexTextColumn(i)));
  end;
end;

procedure TTestHex.PunctuationMapsToNoByte;
begin
  AssertEquals('the offset is not a byte', -1, LedHexColumnToIndex(1));
  AssertEquals('nor the space between the groups', -1,
    LedHexColumnToIndex(LedHexByteColumn(7) + 2));
end;

procedure TTestHex.NoTrailingNewline;
var
  D: string;
begin
  D := LedHexDump('AB');
  AssertTrue('a trailing LF would show as an extra empty line',
    D[Length(D)] <> #10);
end;

procedure TTestHex.ARowRendersTheSameAloneAsInADump;
var
  Data: string;
begin
  { The dump is built from the single-row renderer, and editing re-renders one
    row: the two have to agree or an edited row would not match its
    neighbours. }
  Data := StringOfChar('Q', 40);
  AssertEquals(Line(LedHexDump(Data), 1), LedHexDumpLine(Data, 16));
end;

procedure TTestHex.NibblesAreHighThenLow;
begin
  AssertEquals('first digit is the high nibble',
    0, LedHexColumnToNibble(LedHexByteColumn(3)));
  AssertEquals('second is the low one',
    1, LedHexColumnToNibble(LedHexByteColumn(3) + 1));
  AssertEquals('the space after is neither',
    -1, LedHexColumnToNibble(LedHexByteColumn(3) + 2));
end;

procedure TTestHex.TextColumnsAreNotHexColumns;
begin
  AssertTrue(LedHexColumnIsText(LedHexTextColumn(0)));
  AssertTrue(LedHexColumnIsText(LedHexTextColumn(15)));
  AssertFalse(LedHexColumnIsText(LedHexByteColumn(0)));
  AssertFalse(LedHexColumnIsText(LedHexByteColumn(15) + 1));
  AssertEquals('a text column has no nibble',
    -1, LedHexColumnToNibble(LedHexTextColumn(0)));
end;

procedure TTestHex.TypingAdvancesAcrossAByteThenOn;
begin
  { Two keystrokes make a byte, so the caret crosses the pair and then moves
    to the next byte -- which is what hexedit does and what makes typing a
    run of bytes possible without touching the arrow keys. }
  AssertEquals('high nibble goes to low',
    LedHexByteColumn(0) + 1, LedHexNextColumn(LedHexByteColumn(0)));
  AssertEquals('low nibble goes to the next byte',
    LedHexByteColumn(1), LedHexNextColumn(LedHexByteColumn(0) + 1));
end;

procedure TTestHex.TypingInTextAdvancesOneByte;
begin
  AssertEquals(LedHexTextColumn(1), LedHexNextColumn(LedHexTextColumn(0)));
end;

procedure TTestHex.TheEndOfARowSaysSo;
begin
  { Zero rather than a column, so the caller moves to the next row instead of
    running off the end of this one. }
  AssertEquals('after the last byte',
    0, LedHexNextColumn(LedHexByteColumn(LedHexBytesPerLine - 1) + 1));
  AssertEquals('and after the last character',
    0, LedHexNextColumn(LedHexTextColumn(LedHexBytesPerLine - 1)));
end;

procedure TTestHex.SettingANibbleLeavesTheOtherAlone;
begin
  AssertEquals($AF, LedHexSetNibble($3F, True, $A));
  AssertEquals($3A, LedHexSetNibble($3F, False, $A));
  { Only four bits are taken, so a caller cannot smear a digit across the
    byte. }
  AssertEquals($3A, LedHexSetNibble($3F, False, $FA));
end;

procedure TTestHex.HexDigitsAreEitherCase;
begin
  AssertEquals(0, LedHexDigitValue('0'));
  AssertEquals(15, LedHexDigitValue('f'));
  AssertEquals(15, LedHexDigitValue('F'));
  AssertEquals(10, LedHexDigitValue('A'));
  AssertEquals('not a digit', -1, LedHexDigitValue('g'));
  AssertEquals('nor a space', -1, LedHexDigitValue(' '));
end;

initialization
  RegisterTest(TTestHex);

end.
