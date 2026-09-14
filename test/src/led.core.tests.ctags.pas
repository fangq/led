{ LED - a lightweight editor.  Headless tests for the tags-file reader. }
unit Led.Core.Tests.Ctags;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Led.Core.Ctags;

type
  TTestCtags = class(TTestCase)
  private
    FTags: TLedTags;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure MetadataLinesAreSkipped;
    procedure NumericAddress;
    procedure LineFieldWins;
    procedure KindIsRead;
    procedure ScopeIsRead;
    procedure PatternAddressLeavesLineUnknown;
    procedure ShortLinesAreIgnored;
    procedure KindNames;
    procedure RealCtagsOutputCarriesWholeWords;
    procedure MarkdownHeadingsAreAnOutline;
    procedure TyperefIsNotAScope;
  end;

implementation

procedure TTestCtags.SetUp;
begin
  FTags := TLedTags.Create;
end;

procedure TTestCtags.TearDown;
begin
  FTags.Free;
end;

procedure TTestCtags.MetadataLinesAreSkipped;
begin
  FTags.ParseText(
    '!_TAG_FILE_FORMAT	2	/extended format/'#10 +
    '!_TAG_PROGRAM_NAME	Universal Ctags	//'#10 +
    'main	a.c	12;"	f'#10);
  AssertEquals(1, FTags.Count);
  AssertEquals('main', FTags[0].Name);
end;

procedure TTestCtags.NumericAddress;
begin
  FTags.ParseText('main	a.c	12;"	f'#10);
  AssertEquals(12, FTags[0].Line);
  AssertEquals('a.c', FTags[0].FileName);
end;

procedure TTestCtags.LineFieldWins;
begin
  { --fields=+n adds an explicit line: field, which is more reliable than the
    address when the address is a pattern. }
  FTags.ParseText('main	a.c	/^int main/;"	f	line:42'#10);
  AssertEquals(42, FTags[0].Line);
end;

procedure TTestCtags.KindIsRead;
begin
  FTags.ParseText('Widget	a.cpp	3;"	kind:class'#10);
  AssertEquals('class', FTags[0].Kind);
end;

procedure TTestCtags.ScopeIsRead;
begin
  FTags.ParseText('draw	a.cpp	9;"	f	class:Widget'#10);
  AssertEquals('Widget', FTags[0].Scope);
end;

procedure TTestCtags.PatternAddressLeavesLineUnknown;
begin
  FTags.ParseText('main	a.c	/^int main(void)$/;"	f'#10);
  AssertEquals('a pattern address is not a line number', 0, FTags[0].Line);
end;

procedure TTestCtags.ShortLinesAreIgnored;
begin
  FTags.ParseText('rubbish'#10'also	rubbish'#10);
  AssertEquals(0, FTags.Count);
end;

procedure TTestCtags.KindNames;
begin
  AssertEquals('Functions', FTags.KindName('f'));
  AssertEquals('Classes', FTags.KindName('c'));
  AssertEquals('Other', FTags.KindName(''));
  { An unknown kind is still a group heading, so it is capitalised and made
    plural rather than shown raw: ctags kinds are lower-case singular nouns,
    and "zz" sat in the tree between Functions and Structs. }
  AssertEquals('an unknown kind is made into a heading', 'Zzs',
    FTags.KindName('zz'));
  AssertEquals('and one already plural is left alone', 'Aliass',
    FTags.KindName('aliass'));
end;

{ What ctags actually prints for --fields=+nKs, which is what LED asks it
  for.  Every other case here was written against a tags file with one-letter
  kinds, and against that the reader looked right; run over real output it
  read no kind at all and filed everything under Other. }
procedure TTestCtags.RealCtagsOutputCarriesWholeWords;
begin
  FTags.ParseText(
    'S	t.c	5;"	struct	line:5	file:'#10 +
    'a	t.c	5;"	member	line:5	struct:S	typeref:typename:int	file:'#10 +
    'f	t.c	1;"	function	line:1	typeref:typename:int	file:'#10);
  AssertEquals(3, FTags.Count);
  AssertEquals('struct', FTags[0].Kind);
  AssertEquals('Structs', FTags.KindName(FTags[0].Kind));
  AssertEquals('member', FTags[1].Kind);
  AssertEquals('S', FTags[1].Scope);
  AssertEquals('function', FTags[2].Kind);
  AssertEquals('Functions', FTags.KindName(FTags[2].Kind));
end;

procedure TTestCtags.MarkdownHeadingsAreAnOutline;
begin
  FTags.ParseText(
    'One	t.md	1;"	chapter	line:1'#10 +
    'Two	t.md	5;"	section	line:5	chapter:One'#10);
  AssertEquals('chapter', FTags[0].Kind);
  AssertEquals('Headings', FTags.KindName(FTags[0].Kind));
  AssertEquals('Sections', FTags.KindName(FTags[1].Kind));
  AssertEquals('the section knows the heading it is under', 'One',
    FTags[1].Scope);
end;

procedure TTestCtags.TyperefIsNotAScope;
begin
  { typeref and file are spelled like a scope and are not one.  Reading them
    as one puts "typename:int::" in front of a symbol's name. }
  FTags.ParseText('f	t.c	1;"	function	line:1	typeref:typename:int	file:'#10);
  AssertEquals('', FTags[0].Scope);
end;

initialization
  RegisterTest(TTestCtags);

end.
