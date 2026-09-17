// led - a lightweight editor.  Tests for turning a picture into one the LCL
// can draw.
//
// SVG and WebP both turn up in notebooks and the LCL draws neither, so LED
// asks whatever converter the machine has.  What is checked here is the
// recognition, which is LED's own, and then the conversion itself -- against
// the converter that is actually installed, and skipped where there is none,
// because a test cannot install ImageMagick.

unit Led.Core.Tests.NBConvert;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.NBConvert;

type
  TTestNBConvert = class(TTestCase)
  published
    procedure AnSvgIsRecognisedHoweverItOpens;
    procedure AWebpIsRecognisedByItsHeader;
    procedure APictureThatNeedsNoConvertingIsNotOne;
    procedure HtmlIsNotAnSvgEvenWithAnSvgInIt;
    procedure AConverterIsFoundOrHonestlyNot;
    procedure AnSvgBecomesAPng;
    procedure RubbishThatClaimsToBeAnSvgFails;
    procedure SomethingDrawableIsLeftExactlyAsItWas;
    procedure TheSamePictureIsConvertedOnce;
  end;

implementation

const
  { A real one, small enough to read: a red square. }
  Svg =
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">' +
    '<rect width="8" height="8" fill="#ff0000"/></svg>';
  PngHead = #$89'PNG'#13#10#26#10;

procedure TTestNBConvert.AnSvgIsRecognisedHoweverItOpens;
begin
  AssertEquals('svg', LedNBConvertKind(Svg));
  { The tag need not be first: a declaration, a doctype or a comment may
    come before it, and often does. }
  AssertEquals('svg', LedNBConvertKind('<!-- drawn by hand -->'#10 +
    '<svg width="1" height="1"></svg>'));
  AssertEquals('svg', LedNBConvertKind('<svg></svg>          '));
end;

procedure TTestNBConvert.AWebpIsRecognisedByItsHeader;
begin
  { RIFF, four bytes of length, then WEBP. }
  AssertEquals('webp', LedNBConvertKind('RIFF' + #10#0#0#0 + 'WEBPVP8 rest'));
  AssertEquals('', LedNBConvertKind('RIFF' + #10#0#0#0 + 'WAVEfmt  rest'));
end;

procedure TTestNBConvert.APictureThatNeedsNoConvertingIsNotOne;
begin
  { A PNG and a JPEG go straight to the LCL and never come through here. }
  AssertEquals('', LedNBConvertKind(PngHead + 'whatever follows'));
  AssertEquals('', LedNBConvertKind(#$FF#$D8#$FF#$E0'JFIF and so on'));
  AssertEquals('', LedNBConvertKind(''));
  AssertEquals('', LedNBConvertKind('short'));
end;

procedure TTestNBConvert.HtmlIsNotAnSvgEvenWithAnSvgInIt;
begin
  { What a server sends instead of the picture when it refuses the request,
    and pages do carry inline SVG.  Handing that to a converter would be a
    slow way of getting nothing. }
  AssertEquals('', LedNBConvertKind(
    '<!DOCTYPE html><html><body><svg width="1"></svg></body></html>'));
end;

procedure TTestNBConvert.AConverterIsFoundOrHonestlyNot;
var
  Tool: string;
begin
  Tool := LedNBConverterFor('svg');
  { Either there is one and it is a program that exists, or there is none.
    Both are correct answers; what would not be is a name nobody can run. }
  if Tool <> '' then
    AssertTrue('the converter it named exists: ' + Tool, FileExists(Tool));
  AssertEquals('and nothing is offered for a kind this does not convert',
    '', LedNBConverterFor('pdf'));
  AssertEquals('or for no kind at all', '', LedNBConverterFor(''));
end;

procedure TTestNBConvert.AnSvgBecomesAPng;
var
  Png: string;
begin
  if LedNBConverterFor('svg') = '' then
  begin
    { No converter here, and the answer then has to be "no" rather than
      something half-converted. }
    AssertFalse('with no converter it declines', LedNBToPng(Svg, Png));
    AssertEquals('and hands back nothing', '', Png);
    Exit;
  end;

  AssertTrue('the converter was asked and answered: ' +
    LedNBConverterFor('svg'), LedNBToPng(Svg, Png));
  AssertEquals('and what came back is a png',
    PngHead, Copy(Png, 1, Length(PngHead)));
  AssertTrue('with something in it', Length(Png) > Length(PngHead));
end;

procedure TTestNBConvert.RubbishThatClaimsToBeAnSvgFails;
var
  Png: string;
begin
  { Recognised as an SVG by its tag and not one: the converter fails, and the
    caller is told so rather than handed an empty file. }
  AssertFalse('it declines',
    LedNBToPng('<svg' + #10 + 'this is not XML at all' + #10, Png));
  AssertEquals('with nothing in hand', '', Png);
end;

procedure TTestNBConvert.SomethingDrawableIsLeftExactlyAsItWas;
var
  Bytes, Mime: string;
begin
  Bytes := PngHead + 'the rest of a picture';
  Mime := 'image/png';
  AssertTrue('a png is drawable as it stands',
    LedNBMakeDrawable(Bytes, Mime));
  AssertEquals('and untouched', PngHead + 'the rest of a picture', Bytes);
  AssertEquals('mime and all', 'image/png', Mime);

  { And one that had to be converted comes back saying what it now is. }
  if LedNBConverterFor('svg') <> '' then
  begin
    Bytes := Svg;
    Mime := 'image/svg+xml';
    AssertTrue('an svg is made drawable', LedNBMakeDrawable(Bytes, Mime));
    AssertEquals('as a png', 'image/png', Mime);
    AssertEquals('and the bytes are the png''s',
      PngHead, Copy(Bytes, 1, Length(PngHead)));
  end;
end;

{ A conversion is a process, and starting one costs more than the conversion
  -- measured here, 41 milliseconds against the four the drawing itself takes
  -- so the answers are kept.  It matters because the same picture is asked
  for again every time the cell holding it is drawn, which is what scrolling
  a notebook of plots does: without this, a cell coming back on screen
  started a process.

  Asked of the count of converter runs rather than of a stopwatch. }
procedure TTestNBConvert.TheSamePictureIsConvertedOnce;
var
  Png: string;
  Was, i: Integer;
begin
  if LedNBConverterFor('svg') = '' then Exit;

  { Something no other test has converted, so this starts from nothing. }
  AssertTrue('converted', LedNBToPng(StringReplace(Svg, '#ff0000', '#00ff40',
    [rfReplaceAll]), Png));
  Was := LedNBConversions;

  for i := 1 to 5 do
    AssertTrue('converted again: ' + IntToStr(i),
      LedNBToPng(StringReplace(Svg, '#ff0000', '#00ff40', [rfReplaceAll]),
        Png));
  AssertEquals('and the converter was not run again', Was,
    LedNBConversions);
  AssertEquals('while what comes back is still a png',
    PngHead, Copy(Png, 1, Length(PngHead)));

  { A different picture is a different answer, so it is converted.  A
    different colour and not a different size: replacing the "8"s would
    have caught the one in "UTF-8" and handed the converter a drawing that
    names an encoding nobody has. }
  AssertTrue('a different drawing', LedNBToPng(
    StringReplace(Svg, '#ff0000', '#0000c8', [rfReplaceAll]), Png));
  AssertTrue('runs the converter', LedNBConversions > Was);
end;

initialization
  RegisterTest(TTestNBConvert);

end.
