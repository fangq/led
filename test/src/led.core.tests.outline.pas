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
    procedure ALatexArticleIsNumberedAsLatexNumbersIt;
    procedure ALatexBookHasChaptersAboveSections;
    procedure LatexCommentsVerbatimAndMacrosAreNotSections;
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

procedure TTestOutline.ALatexArticleIsNumberedAsLatexNumbersIt;
var
  O: TLedOutline;
begin
  O := LedOutlineOfLatex(
    '\documentclass{article}' + #10 +
    '\begin{document}' + #10 +
    '\section{Introduction}\label{sec:intro}' + #10 +
    '\subsection[Short]{A long \emph{title}' + #10 +
    '  over two lines}' + #10 +
    '\subsubsection{Deep~one}' + #10 +
    '\section*{Acknowledgments}' + #10 +
    '\section{Methods \& Results}' + #10 +
    '\subsection{First}' + #10 +
    '\paragraph{A paragraph}' + #10 +
    '\appendix' + #10 +
    '\section{Data}' + #10 +
    '\subsection{More}' + #10);
  AssertEquals('nine', 9, Length(O));
  AssertEquals('numbered, its label not in it', '1  Introduction', O[0].Title);
  AssertEquals('at the section level', 3, O[0].Level);
  AssertEquals('on its line', 3, O[0].Line);
  AssertEquals('the short title, as the contents shows it', '1.1  Short', O[1].Title);
  AssertEquals('a level down', 4, O[1].Level);
  AssertEquals('a subsubsection numbered in an article', '1.1.1  Deep one', O[2].Title);
  AssertEquals('on its line, past the title over two', 6, O[2].Line);
  AssertEquals('a starred one not numbered', 'Acknowledgments', O[3].Title);
  AssertEquals('nor counted', '2  Methods & Results', O[4].Title);
  AssertEquals('the subsection under it starts again', '2.1  First', O[5].Title);
  AssertEquals('a paragraph not numbered', 'A paragraph', O[6].Title);
  AssertEquals('deeper', 6, O[6].Level);
  AssertEquals('the appendix lettered', 'A  Data', O[7].Title);
  AssertEquals('and under it', 'A.1  More', O[8].Title);
end;

procedure TTestOutline.ALatexBookHasChaptersAboveSections;
var
  O: TLedOutline;
begin
  O := LedOutlineOfLatex(
    '\part{One}' + #10 +
    '\chapter{Start}' + #10 +
    '\section{Begin}' + #10 +
    '\subsubsection{Not numbered in a book}' + #10 +
    '\chapter{Next}' + #10 +
    '\section{Again}' + #10);
  AssertEquals('six', 6, Length(O));
  AssertEquals('a part, not numbered', 'One', O[0].Title);
  AssertEquals('at the top', 1, O[0].Level);
  AssertEquals('a chapter', '1  Start', O[1].Title);
  AssertEquals('under the part', 2, O[1].Level);
  AssertEquals('its section', '1.1  Begin', O[2].Title);
  AssertEquals('a book''s subsubsection unnumbered', 'Not numbered in a book', O[3].Title);
  AssertEquals('the next chapter', '2  Next', O[4].Title);
  AssertEquals('its sections from one', '2.1  Again', O[5].Title);
end;

procedure TTestOutline.LatexCommentsVerbatimAndMacrosAreNotSections;
var
  O: TLedOutline;
begin
  O := LedOutlineOfLatex(
    '\newcommand{\mysec}[1]{\section{#1}}' + #10 +
    '% \section{Commented out}' + #10 +
    'A 50\% rise \section{Real}' + #10 +
    '\begin{verbatim}' + #10 +
    '\section{In verbatim}' + #10 +
    '\end{verbatim}' + #10 +
    '\begin{frame}[t]{A Slide}' + #10 +
    '\end{frame}' + #10);
  AssertEquals('two', 2, Length(O));
  AssertEquals('after a \% the line goes on', '1  Real', O[0].Title);
  AssertEquals('on line three', 3, O[0].Line);
  AssertEquals('a beamer frame by its title', 'A Slide', O[1].Title);
  AssertEquals('on its line', 7, O[1].Line);
end;

initialization
  RegisterTest(TTestOutline);

end.
