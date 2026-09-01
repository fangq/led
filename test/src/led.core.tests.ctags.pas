{ led - a light editor.  Headless tests for the tags-file reader. }
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
  AssertEquals('an unknown kind is shown as-is', 'zz', FTags.KindName('zz'));
end;

initialization
  RegisterTest(TTestCtags);

end.
