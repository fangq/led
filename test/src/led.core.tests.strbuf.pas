// led - a lightweight editor.  Tests for the append-only string buffer.
//
// The buffer exists for one reason -- "Result := Result + X" in a loop copies
// the whole string every time -- so the tests are about the two things that
// go wrong when a buffer grows itself: the content coming back wrong across a
// reallocation, and a slice being taken past the end of its source.
//
// LedFindCI is here for the same reason: it replaced lowering the case of a
// whole document once per match.

unit Led.Core.Tests.StrBuf;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.StrBuf;

type
  TTestStrBuf = class(TTestCase)
  published
    procedure AnEmptyBufferIsAnEmptyString;
    procedure PiecesComeBackInOrder;
    procedure GrowingPastTheGuessKeepsEverything;
    procedure ASliceIsTheCharactersAsked;
    procedure ASliceIsClippedToItsSource;
    procedure LenIsWhatWasAdded;
    procedure FindIgnoresCase;
    procedure FindStartsWhereAsked;
    procedure FindMissingIsZero;
    procedure SameComparesOneSpot;
  end;

implementation

procedure TTestStrBuf.AnEmptyBufferIsAnEmptyString;
var
  B: TLedStrBuf;
begin
  B.Init(64);
  AssertEquals('nothing in it', '', B.Text);
  AssertEquals('and no length', 0, B.Len);
end;

procedure TTestStrBuf.PiecesComeBackInOrder;
var
  B: TLedStrBuf;
begin
  B.Init(0);
  B.Add('one ');
  B.AddChar('t');
  B.Add('wo');
  AssertEquals('one t' + 'wo', 'one two', B.Text);
end;

procedure TTestStrBuf.GrowingPastTheGuessKeepsEverything;
var
  B: TLedStrBuf;
  Want: string;
  i: Integer;
begin
  { A capacity of one, so every append but the first reallocates: the shape
    of bug this catches is a Move to the wrong offset after a grow. }
  B.Init(1);
  Want := '';
  for i := 1 to 500 do
  begin
    B.Add('piece' + IntToStr(i) + ';');
    Want := Want + 'piece' + IntToStr(i) + ';';
  end;
  AssertEquals('every piece, in order', Want, B.Text);
  AssertEquals('and the length agrees', Length(Want), Length(B.Text));
end;

procedure TTestStrBuf.ASliceIsTheCharactersAsked;
var
  B: TLedStrBuf;
begin
  B.Init(0);
  B.AddSlice('abcdefgh', 3, 4);
  AssertEquals('from the third, four of them', 'cdef', B.Text);
end;

procedure TTestStrBuf.ASliceIsClippedToItsSource;
var
  B: TLedStrBuf;
begin
  B.Init(0);
  B.AddSlice('abc', 2, 100);
  AssertEquals('what there was of it', 'bc', B.Text);
  B.Init(0);
  B.AddSlice('abc', 9, 2);
  AssertEquals('nothing past the end', '', B.Text);
  B.Init(0);
  B.AddSlice('abc', 1, 0);
  AssertEquals('nor a slice of nothing', '', B.Text);
end;

procedure TTestStrBuf.LenIsWhatWasAdded;
var
  B: TLedStrBuf;
begin
  B.Init(4);
  B.Add('abcdef');
  AssertEquals('six, not the capacity', 6, B.Len);
end;

procedure TTestStrBuf.FindIgnoresCase;
begin
  AssertEquals('the upper-case one matches', 6,
    LedFindCI('word CODE more', 'code', 1));
  AssertEquals('so does a mixed one', 1, LedFindCI('CoDe', 'code', 1));
end;

procedure TTestStrBuf.FindStartsWhereAsked;
begin
  AssertEquals('the second one', 9,
    LedFindCI('one two onetwo', 'one', 5));
end;

procedure TTestStrBuf.FindMissingIsZero;
begin
  AssertEquals('not there', 0, LedFindCI('abc', 'xyz', 1));
  AssertEquals('nor in nothing', 0, LedFindCI('', 'x', 1));
  AssertEquals('and nothing is not somewhere', 0, LedFindCI('abc', '', 1));
  AssertEquals('nor is a needle longer than the haystack', 0,
    LedFindCI('ab', 'abc', 1));
end;

procedure TTestStrBuf.SameComparesOneSpot;
begin
  AssertTrue('at the third character', LedSameCI('xxCODExx', 3, 'code'));
  AssertFalse('not at the second', LedSameCI('xxCODExx', 2, 'code'));
  AssertFalse('nor off the end', LedSameCI('xxCODE', 5, 'code'));
  AssertFalse('nor before the start', LedSameCI('code', 0, 'code'));
end;

initialization
  RegisterTest(TTestStrBuf);

end.
