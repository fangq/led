{ LED - a lightweight editor.  Headless tests for the terminal screen model.

  A terminal emulator is only testable this way: drive the parser with the
  byte sequences a program would emit and inspect the grid.  Every case here
  is one a real shell session produces within the first few seconds. }
unit Led.Term.Tests.Screen;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Led.Term.Screen;

type
  TTestTermScreen = class(TTestCase)
  private
    S: TLedTermScreen;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure PlainText;
    procedure NewlineAndCarriageReturn;
    procedure Backspace;
    procedure Tab;
    procedure WrapAtMargin;
    procedure NoBlankLineWhenLineEndsExactlyAtMargin;
    procedure CursorPositioning;
    procedure CursorMovementClamps;
    procedure EraseToEndOfLine;
    procedure EraseWholeScreen;
    procedure ScrollWhenPastTheBottom;
    procedure ScrollbackKeepsWhatScrolledOff;
    procedure ScrollRegion;
    procedure InsertAndDeleteLines;
    procedure DeleteCharacters;
    procedure Colours;
    procedure BoldAndReset;
    procedure Colour256;
    procedure Utf8Character;
    procedure Utf8SplitAcrossReads;
    procedure AlternateScreenIsSeparate;
    procedure AlternateScreenKeepsNoScrollback;
    procedure CursorVisibility;
    procedure WindowTitle;
    procedure UnknownSequenceIsIgnored;
    procedure ResizeKeepsContent;
    procedure AWideCharacterTakesTwoCells;
    procedure AWideCharacterAtTheMarginWrapsWhole;
    procedure OverwritingHalfAPairClearsTheOther;
    procedure ErasingTakesBothHalves;
    procedure CopiedTextHasNoGapInIt;
    procedure ACombiningMarkJoinsTheCharacterBeforeIt;
    procedure DeletingACharacterKeepsPairsWhole;
    procedure InsertingACharacterKeepsPairsWhole;
  end;

implementation

procedure TTestTermScreen.SetUp;
begin
  S := TLedTermScreen.Create(20, 5);
end;

procedure TTestTermScreen.TearDown;
begin
  S.Free;
end;

procedure TTestTermScreen.PlainText;
begin
  S.Feed('hello');
  AssertEquals('hello', S.RowText(0));
  AssertEquals(5, S.CursorX);
end;

procedure TTestTermScreen.NewlineAndCarriageReturn;
begin
  S.Feed('one'#13#10'two');
  AssertEquals('one', S.RowText(0));
  AssertEquals('two', S.RowText(1));
end;

procedure TTestTermScreen.Backspace;
begin
  S.Feed('abc'#8#8'X');
  AssertEquals('aXc', S.RowText(0));
end;

procedure TTestTermScreen.Tab;
begin
  S.Feed('a'#9'b');
  AssertEquals(8, Pos('b', S.RowText(0)) - 1);
end;

procedure TTestTermScreen.WrapAtMargin;
begin
  S.Feed(StringOfChar('x', 25));
  AssertEquals(20, Length(S.RowText(0)));
  AssertEquals(5, Length(S.RowText(1)));
end;

procedure TTestTermScreen.NoBlankLineWhenLineEndsExactlyAtMargin;
begin
  { Wrapping on the character after the last column, not on filling it: a
    line of exactly the terminal width followed by a newline must not leave
    an empty line behind. }
  S.Feed(StringOfChar('x', 20) + #13#10 + 'next');
  AssertEquals(StringOfChar('x', 20), S.RowText(0));
  AssertEquals('next', S.RowText(1));
end;

procedure TTestTermScreen.CursorPositioning;
begin
  S.Feed(#27'[3;5Hhere');
  AssertEquals(2, S.CursorY);
  AssertEquals('    here', S.RowText(2));
end;

procedure TTestTermScreen.CursorMovementClamps;
begin
  S.Feed(#27'[99;99H');
  AssertEquals(4, S.CursorY);
  AssertEquals(19, S.CursorX);
  S.Feed(#27'[99A');
  AssertEquals(0, S.CursorY);
end;

procedure TTestTermScreen.EraseToEndOfLine;
begin
  S.Feed('abcdef'#27'[1;4H'#27'[K');
  AssertEquals('abc', S.RowText(0));
end;

procedure TTestTermScreen.EraseWholeScreen;
begin
  S.Feed('one'#13#10'two'#27'[2J');
  AssertEquals('', S.RowText(0));
  AssertEquals('', S.RowText(1));
  AssertEquals(0, S.CursorY);
end;

procedure TTestTermScreen.ScrollWhenPastTheBottom;
begin
  S.Feed('1'#13#10'2'#13#10'3'#13#10'4'#13#10'5'#13#10'6');
  AssertEquals('the top line scrolled away', '2', S.RowText(0));
  AssertEquals('6', S.RowText(4));
end;

procedure TTestTermScreen.ScrollbackKeepsWhatScrolledOff;
begin
  S.Feed('1'#13#10'2'#13#10'3'#13#10'4'#13#10'5'#13#10'6');
  AssertTrue('something was kept', S.ScrollbackCount >= 1);
end;

procedure TTestTermScreen.ScrollRegion;
begin
  { Full-screen programs set a region and scroll inside it; text outside must
    not move. }
  S.Feed('top'#13#10);
  S.Feed(#27'[2;4r');           { region is rows 2..4 }
  S.Feed(#27'[4;1Ha'#13#10'b');
  AssertEquals('the line above the region is untouched', 'top', S.RowText(0));
end;

procedure TTestTermScreen.InsertAndDeleteLines;
begin
  S.Feed('one'#13#10'two'#13#10'three');
  S.Feed(#27'[2;1H'#27'[L');
  AssertEquals('', S.RowText(1));
  AssertEquals('two', S.RowText(2));
  S.Feed(#27'[2;1H'#27'[M');
  AssertEquals('two', S.RowText(1));
end;

procedure TTestTermScreen.DeleteCharacters;
begin
  S.Feed('abcdef'#27'[1;2H'#27'[2P');
  AssertEquals('adef', S.RowText(0));
end;

procedure TTestTermScreen.Colours;
begin
  S.Feed(#27'[31mred');
  AssertEquals(1, S.Cell(0, 0).FG);
  S.Feed(#27'[0mplain');
  AssertEquals(-1, S.Cell(3, 0).FG);
end;

procedure TTestTermScreen.BoldAndReset;
begin
  S.Feed(#27'[1mB');
  AssertTrue(caBold in S.Cell(0, 0).Attr);
  S.Feed(#27'[22mN');
  AssertFalse(caBold in S.Cell(1, 0).Attr);
end;

procedure TTestTermScreen.Colour256;
begin
  S.Feed(#27'[38;5;200mx');
  AssertEquals(200, S.Cell(0, 0).FG);
end;

procedure TTestTermScreen.Utf8Character;
begin
  S.Feed('caf'#$C3#$A9);
  AssertEquals(#$C3#$A9, S.Cell(3, 0).Ch);
  AssertEquals('one cell, not two', 4, S.CursorX);
end;

procedure TTestTermScreen.Utf8SplitAcrossReads;
begin
  { A read can end in the middle of a multi-byte character; the tail has to
    be carried over rather than shown as rubbish. }
  S.Feed('caf'#$C3);
  S.Feed(#$A9'!');
  AssertEquals(#$C3#$A9, S.Cell(3, 0).Ch);
  AssertEquals('!', S.Cell(4, 0).Ch);
end;

procedure TTestTermScreen.AlternateScreenIsSeparate;
begin
  S.Feed('main text');
  S.Feed(#27'[?1049h');
  AssertEquals('the alternate screen starts blank', '', S.RowText(0));
  S.Feed('full screen app');
  S.Feed(#27'[?1049l');
  AssertEquals('and the main screen comes back', 'main text', S.RowText(0));
end;

procedure TTestTermScreen.AlternateScreenKeepsNoScrollback;
var
  Before: Integer;
begin
  S.Feed(#27'[?1049h');
  Before := S.ScrollbackCount;
  S.Feed('1'#13#10'2'#13#10'3'#13#10'4'#13#10'5'#13#10'6'#13#10'7');
  AssertEquals('a full-screen program does not fill the history',
    Before, S.ScrollbackCount);
end;

procedure TTestTermScreen.CursorVisibility;
begin
  AssertTrue(S.CursorVisible);
  S.Feed(#27'[?25l');
  AssertFalse(S.CursorVisible);
  S.Feed(#27'[?25h');
  AssertTrue(S.CursorVisible);
end;

procedure TTestTermScreen.WindowTitle;
begin
  S.Feed(#27']0;my title'#7);
  AssertEquals('my title', S.Title);
end;

procedure TTestTermScreen.UnknownSequenceIsIgnored;
begin
  { An unimplemented sequence must be swallowed whole, not printed as text. }
  S.Feed('a'#27'[>4;2mb');
  AssertEquals('ab', S.RowText(0));
end;

procedure TTestTermScreen.ResizeKeepsContent;
begin
  S.Feed('hello');
  S.Resize(40, 10);
  AssertEquals('hello', S.RowText(0));
  AssertEquals(40, S.Cols);
end;


{ ---- double-width characters ----

  An ideograph, kana or fullwidth form is drawn two cells wide, so the model
  has to hold it as a pair: the left cell carries the character, the right one
  is a placeholder the glyph reaches into.  Before this, a Chinese character
  advanced the cursor by one and every column after it on the line was drawn
  over its neighbour. }

procedure TTestTermScreen.AWideCharacterTakesTwoCells;
begin
  S.Feed(#$E4#$BD#$A0#$E5#$A5#$BD);             { 你好 }
  AssertEquals('the character is in the first cell', #$E4#$BD#$A0,
    S.Cell(0, 0).Ch);
  AssertTrue('and is marked as wide', S.Cell(0, 0).Wide);
  AssertTrue('the cell beside it is its other half', S.Cell(1, 0).Tail);
  AssertEquals('which carries no character of its own', '', S.Cell(1, 0).Ch);
  AssertEquals('the second character is two cells along', #$E5#$A5#$BD,
    S.Cell(2, 0).Ch);
  AssertTrue('also wide', S.Cell(2, 0).Wide);
  AssertTrue('with its own other half', S.Cell(3, 0).Tail);
  AssertEquals('and the cursor has moved by four cells, not two', 4,
    S.CursorX);
end;

procedure TTestTermScreen.AWideCharacterAtTheMarginWrapsWhole;
begin
  { One cell left at the right margin is not enough for a pair: the pair goes
    to the next line whole rather than straddling the edge. }
  S.Feed(StringOfChar('a', S.Cols - 1) + #$E4#$BD#$A0);
  AssertEquals('the last cell of the first row is left blank', ' ',
    S.Cell(S.Cols - 1, 0).Ch);
  AssertEquals('and the character is at the start of the next row',
    #$E4#$BD#$A0, S.Cell(0, 1).Ch);
  AssertTrue('still whole', S.Cell(0, 1).Wide and S.Cell(1, 1).Tail);
end;

procedure TTestTermScreen.OverwritingHalfAPairClearsTheOther;
begin
  { Half a pair left behind would draw a wide glyph over its neighbour, so
    writing into either half takes the other with it. }
  S.Feed(#$E4#$BD#$A0);
  S.Feed(#27'[1;1H' + 'x');                     { over the left half }
  AssertEquals('the new character is there', 'x', S.Cell(0, 0).Ch);
  AssertFalse('nothing is left of the pair', S.Cell(1, 0).Tail);
  AssertEquals('and its other half is blank', ' ', S.Cell(1, 0).Ch);

  S.Feed(#27'[2J' + #27'[1;1H' + #$E4#$BD#$A0);
  S.Feed(#27'[1;2H' + 'y');                     { over the right half }
  AssertEquals('the new character is there', 'y', S.Cell(1, 0).Ch);
  AssertFalse('and the wide character is gone', S.Cell(0, 0).Wide);
  AssertEquals('leaving a blank where it was', ' ', S.Cell(0, 0).Ch);
end;

procedure TTestTermScreen.ErasingTakesBothHalves;
begin
  S.Feed('ab' + #$E4#$BD#$A0 + 'cd');
  { Erase from the right half onwards: the left half is outside the range and
    would otherwise survive on its own. }
  S.Feed(#27'[1;4H' + #27'[K');
  AssertFalse('the wide character did not survive alone',
    S.Cell(2, 0).Wide);
  AssertEquals('it is blank', ' ', S.Cell(2, 0).Ch);
  AssertEquals('what was before it is untouched', 'a', S.Cell(0, 0).Ch);
end;

procedure TTestTermScreen.CopiedTextHasNoGapInIt;
begin
  S.Feed(#$E4#$BD#$A0#$E5#$A5#$BD + 'ok');
  { The placeholder cells are not characters of the line: copying them would
    put a space inside every Chinese word. }
  AssertEquals(#$E4#$BD#$A0#$E5#$A5#$BD + 'ok', S.RowText(0));
end;

procedure TTestTermScreen.ACombiningMarkJoinsTheCharacterBeforeIt;
begin
  S.Feed('e' + #$CC#$81);                       { e + combining acute }
  AssertEquals('the mark joined the letter', 'e' + #$CC#$81,
    S.Cell(0, 0).Ch);
  AssertEquals('and took no cell of its own', 1, S.CursorX);
end;

procedure TTestTermScreen.DeletingACharacterKeepsPairsWhole;
begin
  S.Feed('a' + #$E4#$BD#$A0 + 'b');
  { Delete the 'a': the pair shifts left by one cell, and a shift by an odd
    number is exactly what leaves half a pair behind. }
  S.Feed(#27'[1;1H' + #27'[P');
  AssertEquals('the pair shifted left whole', #$E4#$BD#$A0,
    S.Cell(0, 0).Ch);
  AssertTrue('with its base marked', S.Cell(0, 0).Wide);
  AssertTrue('and its other half beside it', S.Cell(1, 0).Tail);
  AssertEquals('and what followed it came with it', 'b', S.Cell(2, 0).Ch);

  { And a delete that lands on the left half of a pair takes the pair: the
    right half would otherwise shift into place with no base. }
  S.Feed(#27'[2J' + #27'[1;1H' + 'a' + #$E4#$BD#$A0 + 'b');
  S.Feed(#27'[1;2H' + #27'[P');
  AssertFalse('no orphaned half is left', S.Cell(1, 0).Tail);
  AssertFalse('nor an orphaned base', S.Cell(1, 0).Wide);
end;

procedure TTestTermScreen.InsertingACharacterKeepsPairsWhole;
begin
  S.Feed('a' + #$E4#$BD#$A0 + 'b');
  { Insert before the pair: everything to the right of the cursor shifts by
    one, so the pair's two halves land one cell apart with a blank between
    them.  Nothing else notices -- the shift is a copy of cells -- so the row
    has to be mended afterwards or a wide glyph is drawn over the character
    beside it. }
  S.Feed(#27'[1;2H' + #27'[@');
  AssertEquals('the inserted blank is where the cursor was', ' ',
    S.Cell(1, 0).Ch);
  AssertFalse('and no base is left without its other half',
    S.Cell(2, 0).Wide and (not S.Cell(3, 0).Tail));
  AssertFalse('nor an other half without its base',
    S.Cell(3, 0).Tail and (not S.Cell(2, 0).Wide));
end;

initialization
  RegisterTest(TTestTermScreen);

end.
