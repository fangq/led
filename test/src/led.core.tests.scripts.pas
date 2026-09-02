{ led - a light editor.  Detecting text that needs a wide font. }
unit Led.Core.Tests.Scripts;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Led.Core.Scripts;

type
  TTestScripts = class(TTestCase)
  published
    procedure PlainAsciiDoesNot;
    procedure EmptyTextDoesNot;
    procedure AccentedLatinDoesNot;
    procedure GreekAndCyrillicDoNot;
    procedure HanDoes;
    procedure KanaDoes;
    procedure HangulDoes;
    procedure FullwidthPunctuationDoes;
    procedure CjkPunctuationDoes;
    procedure ExtensionBDoes;
    procedure FindsItAnywhereInTheText;
    procedure StopsAtTheScanLimit;
    procedure MalformedUtf8IsSurvivable;
    procedure DecodesEachSequenceLength;
  end;

implementation

{ The fixtures are written as byte sequences rather than as literals so the
  file itself stays ASCII and cannot be mangled by a re-encoding. }
function U(const ABytes: array of Byte): string;
var
  i: Integer;
begin
  SetLength(Result, Length(ABytes));
  for i := 0 to High(ABytes) do
    Result[i + 1] := Chr(ABytes[i]);
end;

procedure TTestScripts.PlainAsciiDoesNot;
begin
  AssertFalse('ordinary source needs nothing special',
    LedTextNeedsWideFont('int main(void) { return 0; }'));
end;

procedure TTestScripts.EmptyTextDoesNot;
begin
  AssertFalse('nor does an empty document', LedTextNeedsWideFont(''));
end;

procedure TTestScripts.AccentedLatinDoesNot;
begin
  { U+00E9 and U+00FC -- every monospace font has these. }
  AssertFalse('accented latin is covered by ordinary fonts',
    LedTextNeedsWideFont('caf' + U([$C3, $A9]) + ' f' + U([$C3, $BC]) + 'r'));
end;

procedure TTestScripts.GreekAndCyrillicDoNot;
begin
  { U+03B1 alpha, U+0416 zhe.  Widely covered, and switching font for them
    would change the look of files that render perfectly well today. }
  AssertFalse('greek does not force a font change',
    LedTextNeedsWideFont(U([$CE, $B1])));
  AssertFalse('nor does cyrillic', LedTextNeedsWideFont(U([$D0, $96])));
end;

procedure TTestScripts.HanDoes;
begin
  { U+5929 U+6D25 -- the first two of the reported file. }
  AssertTrue('han needs a wide font',
    LedTextNeedsWideFont(U([$E5, $A4, $A9, $E6, $B4, $A5])));
end;

procedure TTestScripts.KanaDoes;
begin
  AssertTrue('hiragana too', LedTextNeedsWideFont(U([$E3, $81, $82])));
  AssertTrue('and katakana', LedTextNeedsWideFont(U([$E3, $82, $A2])));
end;

procedure TTestScripts.HangulDoes;
begin
  AssertTrue('hangul too', LedTextNeedsWideFont(U([$ED, $95, $9C])));
end;

procedure TTestScripts.FullwidthPunctuationDoes;
begin
  { U+FF0C, the fullwidth comma in the reported line.  On its own it is
    enough: it is as absent from DejaVu Sans Mono as the ideographs are. }
  AssertTrue('a fullwidth comma is enough',
    LedTextNeedsWideFont('a' + U([$EF, $BC, $8C]) + 'b'));
end;

procedure TTestScripts.CjkPunctuationDoes;
begin
  { U+3001 ideographic comma. }
  AssertTrue('so is an ideographic comma',
    LedTextNeedsWideFont(U([$E3, $80, $81])));
end;

procedure TTestScripts.ExtensionBDoes;
begin
  { U+20000, a four-byte sequence. }
  AssertTrue('and a plane-2 ideograph',
    LedTextNeedsWideFont(U([$F0, $A0, $80, $80])));
end;

procedure TTestScripts.FindsItAnywhereInTheText;
var
  S: string;
begin
  S := StringOfChar('x', 5000) + U([$E5, $A4, $A9]) + StringOfChar('y', 5000);
  AssertTrue('a single ideograph in the middle counts',
    LedTextNeedsWideFont(S));
end;

procedure TTestScripts.StopsAtTheScanLimit;
var
  S: string;
begin
  { Past the limit it is not looked at, which is the point of the limit --
    the alternative is reading eight megabytes to choose a font. }
  S := StringOfChar('x', 4000) + U([$E5, $A4, $A9]);
  AssertTrue('inside the limit it is found', LedTextNeedsWideFont(S, 5000));
  AssertFalse('outside it, it is not', LedTextNeedsWideFont(S, 100));
end;

procedure TTestScripts.MalformedUtf8IsSurvivable;
begin
  { A lead byte with no continuation, a stray continuation byte, and a
    truncated sequence.  None of these may hang or read past the end. }
  AssertFalse('a bare lead byte is not a wide script',
    LedTextNeedsWideFont(U([$E5])));
  AssertFalse('nor a stray continuation byte',
    LedTextNeedsWideFont(U([$A9, $A9, $A9])));
  AssertFalse('nor a truncated sequence',
    LedTextNeedsWideFont(U([$E5, $A4]) + 'abc'));
  { And a valid ideograph after the damage is still found, which is what the
    resynchronising step length is for. }
  AssertTrue('and text after the damage is still scanned',
    LedTextNeedsWideFont(U([$A9]) + U([$E5, $A4, $A9])));
end;

procedure TTestScripts.DecodesEachSequenceLength;
var
  L: Integer;
begin
  AssertEquals('one byte', Cardinal($41), LedCodepointAt('A', 1, L));
  AssertEquals('and one byte long', 1, L);
  AssertEquals('two bytes', Cardinal($E9), LedCodepointAt(U([$C3, $A9]), 1, L));
  AssertEquals('and two bytes long', 2, L);
  AssertEquals('three bytes', Cardinal($5929),
    LedCodepointAt(U([$E5, $A4, $A9]), 1, L));
  AssertEquals('and three bytes long', 3, L);
  AssertEquals('four bytes', Cardinal($20000),
    LedCodepointAt(U([$F0, $A0, $80, $80]), 1, L));
  AssertEquals('and four bytes long', 4, L);
end;

initialization
  RegisterTest(TTestScripts);

end.
