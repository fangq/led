{ led - a light editor.  The wiki-to-HTML converter.

  Every check asserts something in the produced HTML rather than that the
  converter ran, and the fixtures are the syntax medit's own converter
  documents, so a rule that silently stops matching fails here. }
unit Led.Core.Tests.Wiki;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, fpcunit, testregistry, Led.Core.Wiki;

type
  TTestWiki = class(TTestCase)
  private
    function H(const AWiki: string): string;
    procedure AssertHas(const AMsg, ANeedle, AHaystack: string);
    procedure AssertHasNot(const AMsg, ANeedle, AHaystack: string);
    function CountOf(const ANeedle, AHaystack: string): Integer;
  published
    procedure Paragraphs;
    procedure Headings;
    procedure NumberedHeadingsAndToc;
    procedure HorizontalRules;
    procedure UnorderedLists;
    procedure OrderedLists;
    procedure NestedLists;
    procedure DefinitionLists;
    procedure IndentedText;
    procedure Tables;
    procedure HeaderCells;
    procedure Emphasis;
    procedure BoldItalicTogether;
    procedure InlineCode;
    procedure FreeLinks;
    procedure LabelledFreeLinks;
    procedure BracketedUrls;
    procedure BareUrls;
    procedure WikiWords;
    procedure NamedAnchors;
    procedure NowikiIsNotInterpreted;
    procedure PreKeepsItsContent;
    procedure HtmlIsEscaped;
    procedure UnknownSyntaxSurvivesAsText;
    procedure DetectsWikiFilesByExtension;
    procedure DetectsWikiFilesByFirstLine;
    procedure DoesNotClaimOtherFiles;
    procedure EmptyInputIsHarmless;
    procedure PageWrapsTheBody;
  end;

implementation

function TTestWiki.H(const AWiki: string): string;
begin
  Result := LedWikiToHTML(AWiki);
end;

procedure TTestWiki.AssertHas(const AMsg, ANeedle, AHaystack: string);
begin
  AssertTrue(AMsg + ' -- looking for "' + ANeedle + '" in: ' + AHaystack,
    Pos(ANeedle, AHaystack) > 0);
end;

procedure TTestWiki.AssertHasNot(const AMsg, ANeedle, AHaystack: string);
begin
  AssertTrue(AMsg + ' -- did not expect "' + ANeedle + '" in: ' + AHaystack,
    Pos(ANeedle, AHaystack) = 0);
end;

function TTestWiki.CountOf(const ANeedle, AHaystack: string): Integer;
var
  P, From_: Integer;
begin
  Result := 0;
  From_ := 1;
  repeat
    P := PosEx(ANeedle, AHaystack, From_);
    if P = 0 then Break;
    Inc(Result);
    From_ := P + Length(ANeedle);
  until False;
end;

procedure TTestWiki.Paragraphs;
var
  S: string;
begin
  S := H('first line' + #10 + 'still the same paragraph' + #10 + #10 +
         'a second one');
  AssertHas('a paragraph opens', '<p>', S);
  AssertTrue('two paragraphs, not one',
    Pos('<p>', S) < Pos('</p>', S));
  AssertHas('the text is there', 'first line', S);
  AssertHas('and the later text too', 'a second one', S);
end;

procedure TTestWiki.Headings;
var
  S: string;
begin
  S := H('= One =' + #10 + '=== Three ===');
  AssertHas('one equals is h1', '<h1>One</h1>', S);
  AssertHas('three is h3', '<h3>Three</h3>', S);
end;

procedure TTestWiki.NumberedHeadingsAndToc;
var
  S: string;
begin
  S := H('<toc>' + #10 + '= # Alpha =' + #10 + '== # Beta ==' + #10 +
         '== # Gamma ==' + #10 + '= # Delta =');
  AssertHas('a numbered heading carries its number', '1', S);
  AssertHas('the second level counts within the first', '1.1', S);
  AssertHas('and keeps counting', '1.2', S);
  AssertHas('a new top level resets the deeper ones', '2', S);
  AssertHas('the heading is anchored', 'id="alpha"', S);
  AssertHas('the toc is a list', 'wikitoc', S);
  AssertHas('and links to the anchor', 'href="#beta"', S);
end;

procedure TTestWiki.HorizontalRules;
var
  S: string;
begin
  S := H('----');
  AssertHas('four dashes rule', '<hr>', S);
  S := H('--------');
  AssertHas('and six or more is the thick one', 'wikiline-thick', S);
end;

procedure TTestWiki.UnorderedLists;
var
  S: string;
begin
  S := H('* one' + #10 + '* two');
  AssertHas('a ul opens', '<ul>', S);
  AssertHas('with an item', '<li>one', S);
  AssertHas('and another', '<li>two', S);
  AssertHas('and closes', '</ul>', S);
end;

procedure TTestWiki.OrderedLists;
var
  S: string;
begin
  S := H('# first' + #10 + '# second');
  AssertHas('an ol opens', '<ol>', S);
  AssertHas('with an item', '<li>first', S);
  AssertHasNot('and is not a ul', '<ul>', S);
end;

procedure TTestWiki.NestedLists;
var
  S: string;
begin
  S := H('* outer' + #10 + '** inner' + #10 + '* outer again');
  AssertEquals('two lists open, an outer and an inner', 2, CountOf('<ul>', S));
  AssertEquals('and both close', 2, CountOf('</ul>', S));
  AssertEquals('three items in all', 3, CountOf('<li>', S));
  { The nested list has to sit inside the parent item, so the outer <li> is
    still open when the inner <ul> starts. }
  AssertTrue('the inner list is inside the outer item',
    Pos('<li>second', S) < Pos('<ul>', Copy(S, Pos('<li>second', S),
      Length(S))) + Pos('<li>second', S));
  AssertHas('the nested item is there', 'inner', S);
  AssertHas('and the outer list resumes', 'outer again', S);
end;

procedure TTestWiki.DefinitionLists;
var
  S: string;
begin
  S := H('; term : what it means');
  AssertHas('a dl opens', '<dl>', S);
  AssertHas('the term is a dt', '<dt>term</dt>', S);
  AssertHas('and the definition follows', 'what it means', S);
  { A dt is not allowed inside a dd, and the first version put it there. }
  AssertHasNot('the dt is not nested in the dd', '<dd><dt>', S);
  AssertTrue('the term comes before the definition',
    Pos('<dt>', S) < Pos('<dd>', S));
end;

procedure TTestWiki.IndentedText;
var
  S: string;
begin
  S := H(': indented once');
  AssertHas('indenting uses a dl', '<dl>', S);
  AssertHas('and a dd', '<dd>', S);
  AssertHas('with the text', 'indented once', S);
end;

procedure TTestWiki.Tables;
var
  S: string;
begin
  S := H('||one||two||');
  AssertHas('a table opens', '<table', S);
  AssertHas('with a row', '<tr>', S);
  AssertHas('and cells', '<td>one</td>', S);
  AssertHas('both of them', '<td>two</td>', S);
end;

procedure TTestWiki.HeaderCells;
var
  S: string;
begin
  S := H('!!head||');
  AssertHas('bang cells are th', '<th>', S);
  AssertHasNot('and not td', '<td>', S);
end;

procedure TTestWiki.Emphasis;
var
  S: string;
begin
  S := H('some ''''italic'''' and ''''''bold'''''' here');
  AssertHas('two quotes is em', '<em>italic</em>', S);
  AssertHas('three is strong', '<strong>bold</strong>', S);
end;

procedure TTestWiki.BoldItalicTogether;
var
  S: string;
begin
  S := H('''''''''''both''''''''''');
  AssertHas('five quotes is both', '<strong><em>both</em></strong>', S);
end;

procedure TTestWiki.InlineCode;
var
  S: string;
begin
  S := H('a `snippet` here');
  AssertHas('backticks are code', '<code>snippet</code>', S);
end;

procedure TTestWiki.FreeLinks;
var
  S: string;
begin
  S := H('see [[Some Page]] for more');
  AssertHas('a free link becomes an anchor', '<a href="Some_Page">', S);
  AssertHas('shown under its own name', '>Some Page</a>', S);
end;

procedure TTestWiki.LabelledFreeLinks;
var
  S: string;
begin
  S := H('see [[Target|the label]]');
  AssertHas('the target is the href', 'href="Target"', S);
  AssertHas('and the label is shown', '>the label</a>', S);
end;

procedure TTestWiki.BracketedUrls;
var
  S: string;
begin
  S := H('[http://example.com/ the site]');
  AssertHas('the url is the href', 'href="http://example.com/"', S);
  AssertHas('and the text is the label', '>the site</a>', S);
end;

procedure TTestWiki.BareUrls;
var
  S: string;
begin
  S := H('go to http://example.com/page now');
  AssertHas('a bare address is linked', 'href="http://example.com/page"', S);
  S := H('see http://example.com/page.');
  AssertHasNot('and the full stop is not part of it',
    'href="http://example.com/page."', S);
end;

procedure TTestWiki.WikiWords;
var
  S: string;
begin
  S := H('a CamelCase word links');
  AssertHas('CamelCase is a link', 'href="CamelCase"', S);
  S := H('but lowercase and ALLCAPS do not');
  AssertHasNot('lowercase is not', 'href="lowercase"', S);
  AssertHasNot('nor is a run of capitals', 'href="ALLCAPS"', S);
end;

procedure TTestWiki.NamedAnchors;
var
  S: string;
begin
  S := H('[#spot] text');
  AssertHas('an anchor is emitted', '<a name="spot">', S);
  { A duplicate anchor name makes an HTML renderer complain about a repeated
    id, so the second use is dropped.  The first version of this check
    compared Pos(x) with Pos(x), which is true whatever the converter does. }
  S := H('[#twice] and [#twice]');
  AssertEquals('a repeated anchor is emitted once', 1,
    CountOf('name="twice"', S));
end;

procedure TTestWiki.NowikiIsNotInterpreted;
var
  S: string;
begin
  S := H('<nowiki>''''not italic'''' and [[not a link]]</nowiki>');
  AssertHasNot('markup inside nowiki is left alone', '<em>', S);
  AssertHasNot('and so are links', '<a href=', S);
  AssertHas('the text itself survives', 'not italic', S);
end;

procedure TTestWiki.PreKeepsItsContent;
var
  S: string;
begin
  S := H('<pre>  spaced  ''''text''''</pre>');
  AssertHas('pre is preserved as a block', '<pre>', S);
  AssertHasNot('and its content is not marked up', '<em>', S);
end;

procedure TTestWiki.HtmlIsEscaped;
var
  S: string;
begin
  S := H('a <script>alert(1)</script> line');
  AssertHasNot('raw html does not reach the output', '<script>', S);
  AssertHas('it is escaped instead', '&lt;script&gt;', S);
end;

procedure TTestWiki.UnknownSyntaxSurvivesAsText;
var
  S: string;
begin
  S := H('a @@strange@@ construct');
  AssertHas('an unknown rule leaves the text visible', '@@strange@@', S);
end;

procedure TTestWiki.DetectsWikiFilesByExtension;
begin
  AssertTrue('.wiki is one', LedIsWikiFile('notes.wiki', ''));
  AssertTrue('.wp too', LedIsWikiFile('notes.wp', ''));
  AssertTrue('and .usemod', LedIsWikiFile('notes.usemod', ''));
end;

procedure TTestWiki.DetectsWikiFilesByFirstLine;
begin
  AssertTrue('the marker comment names it',
    LedIsWikiFile('notes.txt', '<!-- wiki -->'));
end;

procedure TTestWiki.DoesNotClaimOtherFiles;
begin
  AssertFalse('a markdown file is not wiki',
    LedIsWikiFile('readme.md', '# Heading'));
  AssertFalse('nor a plain text file', LedIsWikiFile('notes.txt', 'hello'));
end;

procedure TTestWiki.EmptyInputIsHarmless;
begin
  AssertEquals('nothing in, nothing out', '', Trim(H('')));
end;

procedure TTestWiki.PageWrapsTheBody;
var
  S: string;
begin
  S := LedWikiToPage('= Title =', 'doc');
  AssertHas('the page is a document', '<html', LowerCase(S));
  AssertHas('carrying the rendered body', '<h1>Title</h1>', S);
  AssertHasNot('and no placeholder is left behind', '%LEDWIKIBODY%', S);
end;

initialization
  RegisterTest(TTestWiki);

end.
