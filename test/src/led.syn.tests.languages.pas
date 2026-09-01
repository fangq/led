{ led - a light editor.  Headless tests for the language registry.

  These read the real 128 grammars out of data/langs, so they double as a
  check that the vendored data is intact and parses. }
unit Led.Syn.Tests.Languages;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Led.Syn.Languages;

type
  TTestLanguages = class(TTestCase)
  private
    FReg: TLedLangRegistry;
    function DataDir: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AllShippedGrammarsParse;
    procedure MetadataIsRead;
    procedure GlobsAreSplit;
    procedure MimeTypesAreSplit;
    procedure DetectsBySuffix;
    procedure DetectsMakefileByCharacterClass;
    procedure DetectsByShebang;
    procedure DetectsVersionedShebang;
    procedure ShellVariantsMapToSh;
    procedure UnknownFileHasNoLanguage;
    procedure HiddenGrammarsAreNotOffered;
    procedure CommentMarkersAreAvailable;
    procedure MenuListIsGroupedBySection;
  end;

implementation

function TTestLanguages.DataDir: string;
var
  Dir: string;
begin
  { The test binary lives in bin/, the data one level up. }
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  Result := ExpandFileName(Dir + '..' + PathDelim + 'data' + PathDelim + 'langs');
end;

procedure TTestLanguages.SetUp;
begin
  FReg := TLedLangRegistry.Create;
  FReg.ScanDirectory(DataDir);
end;

procedure TTestLanguages.TearDown;
begin
  FReg.Free;
end;

procedure TTestLanguages.AllShippedGrammarsParse;
begin
  { If this number moves, either a grammar was added or one stopped parsing;
    both are worth noticing. }
  AssertEquals('all 128 shipped grammars are understood', 128, FReg.Count);
end;

procedure TTestLanguages.MetadataIsRead;
var
  L: TLedLangInfo;
begin
  L := FReg.FindById('c');
  AssertNotNull('the C grammar is present', L);
  AssertEquals('C', L.Name);
  AssertEquals('Source', L.Section);
  AssertEquals('//', L.LineComment);
  AssertEquals('/*', L.BlockCommentStart);
  AssertEquals('*/', L.BlockCommentEnd);
  AssertTrue(L.HasComments);
end;

procedure TTestLanguages.GlobsAreSplit;
var
  L: TLedLangInfo;
begin
  L := FReg.FindById('cpp');
  AssertNotNull(L);
  AssertTrue('several globs are recorded', L.Globs.Count > 1);
end;

procedure TTestLanguages.MimeTypesAreSplit;
var
  L: TLedLangInfo;
begin
  L := FReg.FindById('c');
  AssertTrue('mime types are split on the semicolon', L.MimeTypes.Count >= 2);
  AssertTrue(L.MatchesMimeType('text/x-csrc'));
  AssertFalse(L.MatchesMimeType('text/x-nonsense'));
end;

procedure TTestLanguages.DetectsBySuffix;
var
  L: TLedLangInfo;
begin
  L := FReg.FindForFile('/home/me/hello.c');
  AssertNotNull(L);
  AssertEquals('c', L.Id);

  L := FReg.FindForFile('script.py');
  AssertNotNull(L);
  AssertTrue('a .py file resolves to a python grammar',
    Pos('python', L.Id) = 1);
end;

procedure TTestLanguages.DetectsMakefileByCharacterClass;
var
  L: TLedLangInfo;
begin
  { The only grammar using a [Mm] character class, so it is the one that
    proves the glob matcher is more than a suffix test. }
  L := FReg.FindForFile('/src/Makefile');
  AssertNotNull('Makefile is recognised', L);
  AssertEquals('makefile', L.Id);
  L := FReg.FindForFile('/src/makefile');
  AssertNotNull('lower-case makefile too', L);
end;

procedure TTestLanguages.DetectsByShebang;
var
  L: TLedLangInfo;
begin
  { No usable suffix, so the interpreter line has to carry it. }
  L := FReg.FindForFile('/usr/local/bin/deploy', '#!/bin/sh');
  AssertNotNull(L);
  AssertEquals('sh', L.Id);
end;

procedure TTestLanguages.DetectsVersionedShebang;
var
  L: TLedLangInfo;
begin
  L := FReg.FindForFile('runme', '#!/usr/bin/env python3');
  AssertNotNull(L);
  AssertTrue('python3 or python', Pos('python', L.Id) = 1);

  { A version suffix that names no grammar falls back to the base name. }
  L := FReg.FindForFile('runme', '#!/usr/bin/perl5');
  AssertNotNull(L);
  AssertEquals('perl', L.Id);
end;

procedure TTestLanguages.ShellVariantsMapToSh;
var
  L: TLedLangInfo;
begin
  L := FReg.FindForFile('x', '#!/bin/bash');
  AssertNotNull(L);
  AssertEquals('sh', L.Id);
  L := FReg.FindForFile('x', '#!/usr/bin/zsh');
  AssertNotNull(L);
  AssertEquals('sh', L.Id);
end;

procedure TTestLanguages.UnknownFileHasNoLanguage;
begin
  AssertNull(FReg.FindForFile('notes.qqzz'));
  AssertNull(FReg.FindForFile(''));
end;

procedure TTestLanguages.HiddenGrammarsAreNotOffered;
var
  i: Integer;
  L: TStringList;
begin
  { def.lang and friends exist only to be included by other grammars. }
  L := TStringList.Create;
  try
    FReg.ListForMenu(L);
    for i := 0 to L.Count - 1 do
      AssertFalse('no hidden grammar in the menu',
        TLedLangInfo(L.Objects[i]).Hidden);
    AssertTrue('the menu is shorter than the registry', L.Count < FReg.Count);
  finally
    L.Free;
  end;
end;

procedure TTestLanguages.CommentMarkersAreAvailable;
var
  L: TLedLangInfo;
begin
  L := FReg.FindById('python');
  AssertNotNull(L);
  AssertEquals('#', L.LineComment);

  { Not every language has comments; comment/uncomment must stay disabled
    for those rather than inserting nothing. }
  L := FReg.FindById('diff');
  if L <> nil then
    AssertFalse('diff has no comment syntax', L.HasComments);
end;

procedure TTestLanguages.MenuListIsGroupedBySection;
var
  L: TStringList;
  i: Integer;
  Section, Prev: string;
begin
  L := TStringList.Create;
  try
    FReg.ListForMenu(L);
    AssertTrue(L.Count > 100);
    Prev := '';
    for i := 0 to L.Count - 1 do
    begin
      Section := Copy(L[i], 1, Pos(#1, L[i]) - 1);
      AssertTrue('sections are contiguous', Section >= Prev);
      Prev := Section;
    end;
  finally
    L.Free;
  end;
end;

initialization
  RegisterTest(TTestLanguages);

end.
