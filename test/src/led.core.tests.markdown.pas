{ led - a light editor.  Headless tests for the Markdown converter. }
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

initialization
  RegisterTest(TTestMarkdown);

end.
