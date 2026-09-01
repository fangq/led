{ led - a light editor.  Headless tests for the terminal screen model.

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

initialization
  RegisterTest(TTestTermScreen);

end.
