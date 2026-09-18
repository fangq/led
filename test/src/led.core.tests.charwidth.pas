// led - a lightweight editor.  Tests for the cell width of a character.
//
// The two answers that are not 1 are what matter: an East Asian character
// takes two cells, and a combining mark takes none.  Get either wrong and a
// terminal line is drawn over itself.

unit Led.Core.Tests.CharWidth;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.CharWidth;

type
  TTestCharWidth = class(TTestCase)
  published
    procedure AsciiIsOneCell;
    procedure ALatinAccentIsOneCell;
    procedure HanIsTwoCells;
    procedure KanaAndHangulAreTwoCells;
    procedure FullwidthFormsAreTwoCells;
    procedure AnEmojiIsTwoCells;
    procedure ACombiningMarkIsNoCells;
    procedure AControlCharacterIsNoCells;
    procedure NothingIsStillOneCell;
    procedure BrokenUtf8IsOneCell;
    procedure TheFirstCodepointIsDecoded;
  end;

implementation

procedure TTestCharWidth.AsciiIsOneCell;
begin
  AssertEquals('a letter', 1, LedCharCells('a'));
  AssertEquals('a space', 1, LedCharCells(' '));
  AssertEquals('a brace', 1, LedCharCells('}'));
end;

procedure TTestCharWidth.ALatinAccentIsOneCell;
begin
  { Two bytes, one cell: the width is not the byte count, which is the bug
    this exists to stop. }
  AssertEquals('e acute', 1, LedCharCells(#$C3#$A9));
end;

procedure TTestCharWidth.HanIsTwoCells;
begin
  AssertEquals('ni', 2, LedCharCells(#$E4#$BD#$A0));        { U+4F60 你 }
  AssertEquals('hao', 2, LedCharCells(#$E5#$A5#$BD));       { U+597D 好 }
end;

procedure TTestCharWidth.KanaAndHangulAreTwoCells;
begin
  AssertEquals('hiragana a', 2, LedCharCells(#$E3#$81#$82)); { U+3042 あ }
  AssertEquals('katakana a', 2, LedCharCells(#$E3#$82#$A2)); { U+30A2 ア }
  AssertEquals('hangul han', 2, LedCharCells(#$ED#$95#$9C)); { U+D55C 한 }
end;

procedure TTestCharWidth.FullwidthFormsAreTwoCells;
begin
  AssertEquals('fullwidth A', 2, LedCharCells(#$EF#$BC#$A1)); { U+FF21 Ａ }
  AssertEquals('ideographic comma', 2,
    LedCharCells(#$E3#$80#$81));                             { U+3001 、 }
  { And the halfwidth kana beside them are one cell, which is the whole
    reason the property exists. }
  AssertEquals('halfwidth katakana', 1,
    LedCharCells(#$EF#$BD#$B1));                             { U+FF71 ｱ }
end;

procedure TTestCharWidth.AnEmojiIsTwoCells;
begin
  { Four bytes, above the basic plane: the decoder has to carry all three
    continuation bytes or the code point lands in the wrong table. }
  AssertEquals('grinning face', 2,
    LedCharCells(#$F0#$9F#$98#$80));                         { U+1F600 }
end;

procedure TTestCharWidth.ACombiningMarkIsNoCells;
begin
  AssertEquals('combining acute', 0, LedCharCells(#$CC#$81)); { U+0301 }
  AssertEquals('variation selector', 0,
    LedCharCells(#$EF#$B8#$8F));                             { U+FE0F }
end;

procedure TTestCharWidth.AControlCharacterIsNoCells;
begin
  AssertEquals('tab', 0, LedCharCells(#9));
  AssertEquals('escape', 0, LedCharCells(#27));
  AssertEquals('delete', 0, LedCharCells(#127));
end;

procedure TTestCharWidth.NothingIsStillOneCell;
begin
  { An empty cell is a cell: the terminal grid has no zero-width columns. }
  AssertEquals('the empty string', 1, LedCharCells(''));
end;

procedure TTestCharWidth.BrokenUtf8IsOneCell;
begin
  { A lone continuation byte, and a lead byte with nothing after it.  Both
    turn up when a program writes half a character and the read splits it. }
  AssertEquals('a stray continuation byte', 1, LedCharCells(#$A0));
  AssertEquals('a truncated sequence', 1, LedCharCells(#$E4#$BD));
end;

procedure TTestCharWidth.TheFirstCodepointIsDecoded;
begin
  AssertEquals('ascii', $61, LedFirstCodepoint('a'));
  AssertEquals('two bytes', $E9, LedFirstCodepoint(#$C3#$A9));
  AssertEquals('three bytes', $4F60, LedFirstCodepoint(#$E4#$BD#$A0));
  AssertEquals('four bytes', $1F600, LedFirstCodepoint(#$F0#$9F#$98#$80));
  AssertEquals('and the rest of the string is ignored', $4F60,
    LedFirstCodepoint(#$E4#$BD#$A0 + 'abc'));
end;

initialization
  RegisterTest(TTestCharWidth);

end.
