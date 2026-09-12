{ led - a lightweight editor.  Headless tests for the Markdown converter. }
unit Led.Core.Tests.Markdown;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Led.Core.Markdown;

type
  TTestMarkdown = class(TTestCase)
  private
    function Conv(const S: string): string;
    procedure AssertHas(const AWhat, AHtml, ANeedle: string);
  published
    procedure Headings;
    procedure HeadingNeedsASpace;
    procedure Paragraphs;
    procedure Emphasis;
    procedure BoldAndItalicTogether;
    procedure InlineCodeIsNotMarkup;
    procedure Links;
    procedure Images;
    procedure BareUrls;
    procedure BulletList;
    procedure OrderedList;
    procedure FencedCode;
    procedure FencedCodeIsEscaped;
    procedure BlockQuote;
    procedure ThematicBreak;
    procedure Table;
    procedure HtmlIsEscaped;
    procedure BackslashEscape;
    procedure WholePageHasAStylesheet;
    procedure WrappingLeavesShortCodeAlone;
    procedure WrappingBreaksALongCodeLineAtASpace;
    procedure WrappingBreaksATokenThatHasNoSpaces;
    procedure WrappingLeavesTheProseAlone;
    procedure WrappingNeverSplitsAnEntity;
    procedure WrappingKeepsEveryLineOfABlock;
    procedure WrappingOffIsTheDocumentItself;
    procedure SplittingBreaksAMultiWordSpan;
    procedure SplittingLeavesAOneWordSpanAlone;
    procedure SplittingKeepsNestingInOrder;
    procedure SplittingLeavesAnUnderlineWhole;
    procedure SplittingLeavesPreformattedTextAlone;
    procedure SplittingKeepsTheAttributesOfATag;
    procedure SplittingPutsAWholeRunOfSpacesOutside;
    procedure LineIdsAreOffUnlessAskedFor;
    procedure LineIdsMarkEveryBlock;
    procedure AParagraphBelongsToItsFirstLine;
    procedure LineIdsCountBlankLines;
    procedure ListItemsAreMarkedOneByOne;
    procedure LineIdsSurviveTheWholePage;
  end;

implementation

function TTestMarkdown.Conv(const S: string): string;
begin
  Result := LedMarkdownToHTML(S);
end;

procedure TTestMarkdown.AssertHas(const AWhat, AHtml, ANeedle: string);
begin
  AssertTrue(AWhat + ' -- looked for "' + ANeedle + '" in: ' + AHtml,
    Pos(ANeedle, AHtml) > 0);
end;

procedure TTestMarkdown.Headings;
begin
  AssertHas('h1', Conv('# Title'), '<h1>Title</h1>');
  AssertHas('h3', Conv('### Deeper'), '<h3>Deeper</h3>');
end;

procedure TTestMarkdown.HeadingNeedsASpace;
begin
  { "#hashtag" is a paragraph, not a heading. }
  AssertHas('not a heading', Conv('#hashtag'), '<p>#hashtag</p>');
end;

procedure TTestMarkdown.Paragraphs;
var
  H: string;
begin
  { Consecutive lines join into one paragraph; a blank line separates. }
  H := Conv('one' + LineEnding + 'two' + LineEnding + LineEnding + 'three');
  AssertHas('joined', H, '<p>one two</p>');
  AssertHas('separated', H, '<p>three</p>');
end;

procedure TTestMarkdown.Emphasis;
begin
  AssertHas('italic', Conv('a *word* here'), '<i>word</i>');
  AssertHas('bold', Conv('a **word** here'), '<b>word</b>');
end;

procedure TTestMarkdown.BoldAndItalicTogether;
begin
  AssertHas('bold wins over italic at the same spot',
    Conv('**strong** and *soft*'), '<b>strong</b>');
  AssertHas('and the italic still works',
    Conv('**strong** and *soft*'), '<i>soft</i>');
end;

procedure TTestMarkdown.InlineCodeIsNotMarkup;
begin
  { Inside a code span, an asterisk is an asterisk. }
  AssertHas('code span', Conv('use `a*b` here'), '<code>a*b</code>');
  AssertFalse('no emphasis inside code',
    Pos('<i>', Conv('use `a*b` here')) > 0);
end;

procedure TTestMarkdown.Links;
begin
  AssertHas('link', Conv('see [docs](http://x.example)'),
    '<a href="http://x.example">docs</a>');
end;

procedure TTestMarkdown.Images;
begin
  AssertHas('image', Conv('![alt](pic.png)'), '<img src="pic.png" alt="alt">');
end;

procedure TTestMarkdown.BareUrls;
begin
  AssertHas('bare url becomes a link', Conv('go to https://x.example now'),
    '<a href="https://x.example">https://x.example</a>');
end;

procedure TTestMarkdown.BulletList;
var
  H: string;
begin
  H := Conv('- one' + LineEnding + '- two');
  AssertHas('opens', H, '<ul>');
  AssertHas('item', H, '<li>one</li>');
  AssertHas('closes', H, '</ul>');
end;

procedure TTestMarkdown.OrderedList;
var
  H: string;
begin
  H := Conv('1. one' + LineEnding + '2. two');
  AssertHas('opens', H, '<ol>');
  AssertHas('item', H, '<li>two</li>');
end;

procedure TTestMarkdown.FencedCode;
var
  H: string;
begin
  H := Conv('```' + LineEnding + 'code line' + LineEnding + '```');
  AssertHas('opens', H, '<pre>');
  AssertHas('content', H, 'code line');
  AssertHas('closes', H, '</pre>');
end;

procedure TTestMarkdown.FencedCodeIsEscaped;
begin
  { The output goes to an HTML control, so a code block containing tags must
    not become markup. }
  AssertHas('escaped',
    Conv('```' + LineEnding + '<script>x</script>' + LineEnding + '```'),
    '&lt;script&gt;');
end;

procedure TTestMarkdown.BlockQuote;
begin
  AssertHas('quote', Conv('> quoted'), '<blockquote>quoted</blockquote>');
end;

procedure TTestMarkdown.ThematicBreak;
begin
  AssertHas('dashes', Conv('---'), '<hr>');
  AssertHas('stars', Conv('***'), '<hr>');
  AssertFalse('two dashes are not a break', Pos('<hr>', Conv('--')) > 0);
end;

procedure TTestMarkdown.Table;
var
  H: string;
begin
  H := Conv('| a | b |' + LineEnding + '|---|---|' + LineEnding + '| 1 | 2 |');
  AssertHas('table', H, '<table');
  AssertHas('header cell', H, '<th>a</th>');
  AssertHas('body cell', H, '<td>1</td>');
end;

procedure TTestMarkdown.HtmlIsEscaped;
begin
  AssertHas('angle brackets', Conv('a < b & c'), '&lt;');
  AssertHas('ampersand', Conv('a < b & c'), '&amp;');
end;

procedure TTestMarkdown.BackslashEscape;
begin
  AssertFalse('an escaped asterisk is literal',
    Pos('<i>', Conv('a \*not italic\* b')) > 0);
end;

procedure TTestMarkdown.WholePageHasAStylesheet;
var
  P: string;
begin
  P := LedMarkdownToPage('# Hi', 'doc');
  AssertHas('title', P, '<title>doc</title>');
  AssertHas('style', P, '<style>');
  AssertHas('body', P, '<h1>Hi</h1>');
end;

{ --- wrapping preformatted text -------------------------------------------- }

procedure TTestMarkdown.WrappingLeavesShortCodeAlone;
begin
  AssertEquals('<pre>make all</pre>',
    LedWrapPreLines('<pre>make all</pre>', 40));
end;

procedure TTestMarkdown.WrappingBreaksALongCodeLineAtASpace;
var
  H: string;
begin
  { Twelve columns: "make all and" is as much as fits, and the break goes
    after a space rather than through "install". }
  H := LedWrapPreLines('<pre>make all and install it</pre>', 12);
  AssertHas('broken', H, #10);
  AssertHas('at the space', H, 'make all and ' + #10);
  AssertHas('with the rest following', H, 'install it</pre>');
end;

procedure TTestMarkdown.WrappingBreaksATokenThatHasNoSpaces;
var
  H: string;
begin
  { A path or a URL has to fit too, so a token with nowhere to break is cut. }
  H := LedWrapPreLines('<pre>aaaaaaaaaa</pre>', 4);
  AssertEquals('<pre>aaaa' + #10 + 'aaaa' + #10 + 'aa</pre>', H);
end;

procedure TTestMarkdown.WrappingLeavesTheProseAlone;
var
  H: string;
begin
  { Paragraphs wrap themselves -- it is only the block that cannot that is
    touched. }
  H := LedWrapPreLines('<p>a paragraph much longer than four columns</p>', 4);
  AssertEquals('<p>a paragraph much longer than four columns</p>', H);
end;

procedure TTestMarkdown.WrappingNeverSplitsAnEntity;
var
  H: string;
begin
  { IpHtmlPanel draws "&amp;" inside a <pre> as those five characters rather
    than as an ampersand, so that is what it costs; what must not happen
    either way is "&am" on one line and "p;" on the next. }
  H := LedWrapPreLines('<pre>ab&amp;cd</pre>', 3);
  AssertEquals('<pre>ab&amp;' + #10 + 'cd</pre>', H);
end;

procedure TTestMarkdown.WrappingKeepsEveryLineOfABlock;
var
  H: string;
begin
  H := LedWrapPreLines('<pre>' + #10 + 'one two' + #10 + 'three' + #10 +
    '</pre>', 3);
  AssertHas('the first line is wrapped', H, 'one ' + #10 + 'two');
  AssertHas('the second as well', H, 'thr' + #10 + 'ee');
  AssertHas('and the break before the close tag survives', H, #10 + '</pre>');
end;

procedure TTestMarkdown.WrappingOffIsTheDocumentItself;
begin
  AssertEquals('<pre>a very long line indeed</pre>',
    LedWrapPreLines('<pre>a very long line indeed</pre>', 0));
end;

{ --- splitting inline runs ------------------------------------------------- }

procedure TTestMarkdown.SplittingBreaksAMultiWordSpan;
begin
  AssertEquals('<p><b>two</b> <b>words</b></p>',
    LedSplitInlineRuns('<p><b>two words</b></p>'));
end;

procedure TTestMarkdown.SplittingLeavesAOneWordSpanAlone;
begin
  AssertEquals('<p>a <b>word</b> here</p>',
    LedSplitInlineRuns('<p>a <b>word</b> here</p>'));
end;

procedure TTestMarkdown.SplittingKeepsNestingInOrder;
begin
  { Closed innermost first and reopened outermost first, or the document
    stops being well formed. }
  AssertEquals('<b><i>two</i></b> <b><i>words</i></b>',
    LedSplitInlineRuns('<b><i>two words</i></b>'));
end;

procedure TTestMarkdown.SplittingLeavesAnUnderlineWhole;
begin
  { The line runs through the space, so breaking the span would show. }
  AssertEquals('<u>two words</u>', LedSplitInlineRuns('<u>two words</u>'));
  AssertEquals('<s>two words</s>', LedSplitInlineRuns('<s>two words</s>'));
end;

procedure TTestMarkdown.SplittingLeavesPreformattedTextAlone;
begin
  AssertEquals('<pre><code>two words</code></pre>',
    LedSplitInlineRuns('<pre><code>two words</code></pre>'));
end;

procedure TTestMarkdown.SplittingKeepsTheAttributesOfATag;
var
  H: string;
begin
  H := LedSplitInlineRuns('<code class="x">two words</code>');
  AssertEquals('<code class="x">two</code> <code class="x">words</code>', H);
end;

procedure TTestMarkdown.SplittingPutsAWholeRunOfSpacesOutside;
begin
  { Both spaces belong to neither word; reopening between them would leave a
    span holding nothing but a space. }
  AssertEquals('<b>two</b>  <b>words</b>',
    LedSplitInlineRuns('<b>two  words</b>'));
end;

{ --- source line ids ------------------------------------------------------- }

procedure TTestMarkdown.LineIdsAreOffUnlessAskedFor;
begin
  { The converter's own output is unchanged for every caller that has no use
    for them. }
  AssertEquals('<h1>Title</h1>' + LineEnding, LedMarkdownToHTML('# Title'));
end;

procedure TTestMarkdown.LineIdsMarkEveryBlock;
var
  H: string;
begin
  H := LedMarkdownToHTML('# Title' + LineEnding + LineEnding + 'Words.' +
    LineEnding + LineEnding + '> quoted' + LineEnding + LineEnding +
    '    code', True);
  AssertHas('the heading', H, '<h1 id="L1">');
  AssertHas('the paragraph', H, '<p id="L3">');
  AssertHas('the quote', H, '<blockquote id="L5">');
  AssertHas('the code block', H, '<pre id="L7">');
end;

procedure TTestMarkdown.AParagraphBelongsToItsFirstLine;
var
  H: string;
begin
  { A hard-wrapped paragraph is one block; scrolling to it means scrolling to
    where it starts. }
  H := LedMarkdownToHTML('one' + LineEnding + 'two' + LineEnding + 'three',
    True);
  AssertHas('starts at line 1', H, '<p id="L1">');
  AssertFalse('and is not three paragraphs', Pos('<p id="L2">', H) > 0);
end;

procedure TTestMarkdown.LineIdsCountBlankLines;
var
  H: string;
begin
  { The line number has to be the editor's, or the preview scrolls to the
    wrong place in any document with a blank line in it -- which is all of
    them. }
  H := LedMarkdownToHTML(LineEnding + LineEnding + LineEnding + 'Words.', True);
  AssertHas('', H, '<p id="L4">');
end;

procedure TTestMarkdown.ListItemsAreMarkedOneByOne;
var
  H: string;
begin
  H := LedMarkdownToHTML('- one' + LineEnding + '- two', True);
  AssertHas('first item', H, '<li id="L1">');
  AssertHas('second item', H, '<li id="L2">');
end;

procedure TTestMarkdown.LineIdsSurviveTheWholePage;
begin
  AssertHas('the page carries them too',
    LedMarkdownToPage('# Title', 'doc', True), '<h1 id="L1">');
  AssertFalse('and does not when it was not asked',
    Pos('id="L1"', LedMarkdownToPage('# Title', 'doc')) > 0);
end;

initialization
  RegisterTest(TTestMarkdown);

end.
