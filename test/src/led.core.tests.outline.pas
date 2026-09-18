// led - a lightweight editor.  Tests for the outline of a document.
//
// What the Outline pane shows for a Markdown file, a wiki page or a notebook:
// the headings, nested, in the order they appear.  The interesting cases are
// the ones where something looks like a heading and is not -- a hash inside
// a fenced block is a comment in half the languages a notebook holds -- and
// the older spelling, where the heading is underlined rather than marked.

unit Led.Core.Tests.Outline;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.Outline;

type
  TTestOutline = class(TTestCase)
  published
    procedure HeadingsComeBackInOrderWithTheirLevels;
    procedure TheMarkersAndTheirClosersAreTakenOff;
    procedure AHashInAFencedBlockIsNotAHeading;
    procedure AFenceEndsWithTheCharacterItOpenedWith;
    procedure AnUnderlinedHeadingIsOne;
    procedure SomethingThatIsNotAHeadingIsNotOne;
    procedure AWikiPageHasHeadingsToo;
    procedure NothingAtAllGivesNothing;
  end;

implementation

procedure TTestOutline.HeadingsComeBackInOrderWithTheirLevels;
var
  O: TLedOutline;
begin
  O := LedOutlineOfMarkdown(
    '# Top' + #10 +
    'some prose' + #10 +
    '## First section' + #10 +
    '### Under it' + #10 +
    '## Second section' + #10);
  AssertEquals('four headings', 4, Length(O));
  AssertEquals('the first is the title', 'Top', O[0].Title);
  AssertEquals('at level one', 1, O[0].Level);
  AssertEquals('on line one', 1, O[0].Line);
  AssertEquals('then the first section', 'First section', O[1].Title);
  AssertEquals('at level two', 2, O[1].Level);
  AssertEquals('on line three', 3, O[1].Line);
  AssertEquals('then the one inside it', 3, O[2].Level);
  AssertEquals('and the second section', 'Second section', O[3].Title);
  AssertEquals('back at level two', 2, O[3].Level);
end;

procedure TTestOutline.TheMarkersAndTheirClosersAreTakenOff;
var
  O: TLedOutline;
begin
  O := LedOutlineOfMarkdown('##   Spaced   ##' + #10);
  AssertEquals('one heading', 1, Length(O));
  AssertEquals('with nothing but its words', 'Spaced', O[0].Title);
end;

procedure TTestOutline.AHashInAFencedBlockIsNotAHeading;
var
  O: TLedOutline;
begin
  { The one thing an outline has to get right about code: the reader's
    notebooks are full of shell and Python, and both start comments with a
    hash. }
  O := LedOutlineOfMarkdown(
    '# Real heading' + #10 +
    '```sh' + #10 +
    '#!/bin/sh' + #10 +
    '# not a heading' + #10 +
    '```' + #10 +
    '## After the block' + #10);
  AssertEquals('two headings, not four', 2, Length(O));
  AssertEquals('the real one', 'Real heading', O[0].Title);
  AssertEquals('and the one after the block', 'After the block', O[1].Title);
end;

procedure TTestOutline.AFenceEndsWithTheCharacterItOpenedWith;
var
  O: TLedOutline;
begin
  { A ``` block may have ~~~ inside it, and closing on the wrong one would
    let the rest of the block be read as headings. }
  O := LedOutlineOfMarkdown(
    '```' + #10 +
    '~~~' + #10 +
    '# still inside' + #10 +
    '```' + #10 +
    '# outside' + #10);
  AssertEquals('one heading', 1, Length(O));
  AssertEquals('the one after the block', 'outside', O[0].Title);
end;

procedure TTestOutline.AnUnderlinedHeadingIsOne;
var
  O: TLedOutline;
begin
  O := LedOutlineOfMarkdown(
    'A title' + #10 +
    '=======' + #10 +
    #10 +
    'A section' + #10 +
    '---------' + #10);
  AssertEquals('two headings', 2, Length(O));
  AssertEquals('the title', 'A title', O[0].Title);
  AssertEquals('at level one, which is what = means', 1, O[0].Level);
  AssertEquals('on its own line and not the ruling', 1, O[0].Line);
  AssertEquals('the section', 'A section', O[1].Title);
  AssertEquals('at level two, which is what - means', 2, O[1].Level);
  AssertEquals('on line four', 4, O[1].Line);
end;

procedure TTestOutline.SomethingThatIsNotAHeadingIsNotOne;
var
  O: TLedOutline;
begin
  { A tag, seven hashes, and a rule of dashes under nothing. }
  O := LedOutlineOfMarkdown(
    '#hashtag' + #10 +
    '####### too deep' + #10 +
    #10 +
    '-----' + #10 +
    'prose' + #10);
  AssertEquals('none of them', 0, Length(O));
end;

procedure TTestOutline.AWikiPageHasHeadingsToo;
var
  O: TLedOutline;
begin
  O := LedOutlineOfWiki(
    '= The page =' + #10 +
    'prose' + #10 +
    '== A section ==' + #10 +
    '=== Deeper ===' + #10);
  AssertEquals('three headings', 3, Length(O));
  AssertEquals('the page', 'The page', O[0].Title);
  AssertEquals('at level one', 1, O[0].Level);
  AssertEquals('a section', 'A section', O[1].Title);
  AssertEquals('at level two', 2, O[1].Level);
  AssertEquals('and one inside it', 3, O[2].Level);
  AssertEquals('on line four', 4, O[2].Line);
end;

procedure TTestOutline.NothingAtAllGivesNothing;
begin
  AssertEquals('empty markdown', 0, Length(LedOutlineOfMarkdown('')));
  AssertEquals('empty wiki', 0, Length(LedOutlineOfWiki('')));
  AssertEquals('prose with no headings', 0,
    Length(LedOutlineOfMarkdown('just a paragraph' + #10 + 'and another')));
end;

initialization
  RegisterTest(TTestOutline);

end.
