{ led - a light editor.  Headless tests for user tools and output filters. }
unit Led.Core.Tests.Tools;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.Tools, Led.Core.OutputFilter;

type
  TTestToolFile = class(TTestCase)
  private
    FDir: string;
    function Write(const AName, AContent: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure RoundTrip;
    procedure CodeBodyIsVerbatim;
    procedure MeditVocabularyIsAccepted;
    procedure MissingNameIsRejected;
    procedure AppliesToByLanguage;
    procedure AppliesToByGlob;
    procedure DisabledToolNeverApplies;
    procedure DirectoryLoadIsSorted;
  end;

  TTestOutputFilter = class(TTestCase)
  published
    procedure GccError;
    procedure GccWarning;
    procedure ColumnIsOptional;
    procedure BareFileLine;
    procedure PythonTraceback;
    procedure RelativePathsResolveAgainstTheBase;
    procedure MakeDirectoryStack;
    procedure MakePopRestoresThePrevious;
    procedure NoneFilterMatchesNothing;
  end;

implementation

{ TTestToolFile }

procedure TTestToolFile.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-tools-%d%s', [GetProcessID, PathDelim]);
  ForceDirectories(FDir);
end;

procedure TTestToolFile.TearDown;
var
  Info: TSearchRec;
begin
  if FindFirst(FDir + '*', faAnyFile, Info) = 0 then
  begin
    repeat
      if (Info.Name <> '.') and (Info.Name <> '..') then
        DeleteFile(FDir + Info.Name);
    until FindNext(Info) <> 0;
    FindClose(Info);
  end;
  RemoveDir(FDir);
end;

function TTestToolFile.Write(const AName, AContent: string): string;
var
  L: TStringList;
begin
  Result := FDir + AName;
  L := TStringList.Create;
  try
    L.Text := AContent;
    L.SaveToFile(Result);
  finally
    L.Free;
  end;
end;

procedure TTestToolFile.RoundTrip;
var
  T, U: TLedTool;
  Path: string;
begin
  T := TLedTool.Create;
  U := TLedTool.Create;
  try
    T.Id := 'sort-lines';
    T.Name := 'Sort Lines';
    T.Options := [ltoNeedDoc];
    T.Kind := ltkExe;
    T.Input := ltiLines;
    T.Output := ltoInsert;
    T.Code := 'sort';
    Path := FDir + 'sort.ini';
    T.SaveToFile(Path);

    AssertTrue(U.LoadFromFile(Path));
    AssertEquals('Sort Lines', U.Name);
    AssertTrue(U.Options = [ltoNeedDoc]);
    AssertTrue(U.Input = ltiLines);
    AssertTrue(U.Output = ltoInsert);
    AssertEquals('sort', Trim(U.Code));
  finally
    U.Free;
    T.Free;
  end;
end;

procedure TTestToolFile.CodeBodyIsVerbatim;
var
  T: TLedTool;
  Path: string;
begin
  { The body is a shell script: semicolons, brackets and equals signs must
    survive, which is why it is split off by hand instead of read as INI. }
  Path := Write('odd.ini',
    '[tool]' + LineEnding +
    'name=Odd' + LineEnding +
    '[code]' + LineEnding +
    'a=1; b=[2]; echo "x=y"' + LineEnding +
    '# a comment with ; and =' + LineEnding);
  T := TLedTool.Create;
  try
    AssertTrue(T.LoadFromFile(Path));
    AssertTrue('semicolons survive', Pos('a=1; b=[2]', T.Code) > 0);
    AssertTrue('comment lines survive', Pos('# a comment with ; and =', T.Code) > 0);
  finally
    T.Free;
  end;
end;

procedure TTestToolFile.MeditVocabularyIsAccepted;
var
  T: TLedTool;
  Path: string;
begin
  { A tool written for medit should port by copying the body, so its spelling
    of the options has to be understood. }
  Path := Write('medit.ini',
    '[tool]' + LineEnding +
    'name=Old' + LineEnding +
    'options=need-doc,save' + LineEnding +
    'type=lua' + LineEnding +
    'output=console' + LineEnding +
    '[code]' + LineEnding + 'x' + LineEnding);
  T := TLedTool.Create;
  try
    AssertTrue(T.LoadFromFile(Path));
    AssertTrue('"save" means need-save', ltoNeedSave in T.Options);
    AssertTrue(ltoNeedDoc in T.Options);
    AssertTrue('lua maps onto the script engine', T.Kind = ltkScript);
    AssertTrue('console degrades to a pane', T.Output = ltoPane);
  finally
    T.Free;
  end;
end;

procedure TTestToolFile.MissingNameIsRejected;
var
  T: TLedTool;
  Path: string;
begin
  Path := Write('bad.ini', '[tool]' + LineEnding + 'type=exe' + LineEnding);
  T := TLedTool.Create;
  try
    AssertFalse('a tool with no name is not a tool', T.LoadFromFile(Path));
  finally
    T.Free;
  end;
end;

procedure TTestToolFile.AppliesToByLanguage;
var
  T: TLedTool;
begin
  T := TLedTool.Create;
  try
    T.Name := 'x';
    T.Langs := 'c,cpp';
    AssertTrue(T.AppliesTo('cpp', 'a.cpp'));
    AssertFalse(T.AppliesTo('python', 'a.py'));
  finally
    T.Free;
  end;
end;

procedure TTestToolFile.AppliesToByGlob;
var
  T: TLedTool;
begin
  T := TLedTool.Create;
  try
    T.Name := 'x';
    T.FileFilter := '*.tex;*.latex';
    AssertTrue(T.AppliesTo('', '/doc/paper.tex'));
    AssertFalse(T.AppliesTo('', '/doc/paper.txt'));
  finally
    T.Free;
  end;
end;

procedure TTestToolFile.DisabledToolNeverApplies;
var
  T: TLedTool;
begin
  T := TLedTool.Create;
  try
    T.Name := 'x';
    T.Enabled := False;
    AssertFalse(T.AppliesTo('c', 'a.c'));
  finally
    T.Free;
  end;
end;

procedure TTestToolFile.DirectoryLoadIsSorted;
var
  Tools: TLedTools;
begin
  { Menu order must not depend on the order the filesystem hands names back. }
  Write('b.ini', '[tool]' + LineEnding + 'id=b' + LineEnding + 'name=Bee' + LineEnding);
  Write('a.ini', '[tool]' + LineEnding + 'id=a' + LineEnding + 'name=Ay' + LineEnding);
  Tools := TLedTools.Create;
  try
    AssertEquals(2, Tools.LoadDirectory(FDir));
    AssertEquals('a', Tools[0].Id);
    AssertEquals('b', Tools[1].Id);
  finally
    Tools.Free;
  end;
end;

{ TTestOutputFilter }

procedure TTestOutputFilter.GccError;
var
  F: TLedOutputFilter;
  M: TLedOutputMatch;
begin
  F := LedFilters.Find('default');
  F.Reset('/build');
  M := F.Process('src/main.c:42:7: error: expected '';'' before ''}''');
  AssertTrue(M.Kind = lmkError);
  AssertEquals(42, M.Line);
  AssertEquals(7, M.Column);
  AssertTrue(Pos('main.c', M.FileName) > 0);
end;

procedure TTestOutputFilter.GccWarning;
var
  M: TLedOutputMatch;
  F: TLedOutputFilter;
begin
  F := LedFilters.Find('default');
  F.Reset('');
  M := F.Process('a.c:3: warning: unused variable');
  AssertTrue(M.Kind = lmkWarning);
  AssertEquals(3, M.Line);
end;

procedure TTestOutputFilter.ColumnIsOptional;
var
  M: TLedOutputMatch;
  F: TLedOutputFilter;
begin
  F := LedFilters.Find('default');
  F.Reset('');
  M := F.Process('a.c:3: error: boom');
  AssertTrue(M.Kind = lmkError);
  AssertEquals(0, M.Column);
end;

procedure TTestOutputFilter.BareFileLine;
var
  M: TLedOutputMatch;
  F: TLedOutputFilter;
begin
  { grep -n and most linters print this and nothing else; it still names a
    place worth jumping to. }
  F := LedFilters.Find('default');
  F.Reset('');
  M := F.Process('notes.txt:17: some text');
  AssertTrue(M.Kind = lmkInfo);
  AssertEquals(17, M.Line);
end;

procedure TTestOutputFilter.PythonTraceback;
var
  M: TLedOutputMatch;
  F: TLedOutputFilter;
begin
  F := LedFilters.Find('python');
  F.Reset('');
  M := F.Process('  File "/tmp/script.py", line 9, in <module>');
  AssertTrue(M.Kind = lmkError);
  AssertEquals('/tmp/script.py', M.FileName);
  AssertEquals(9, M.Line);
end;

procedure TTestOutputFilter.RelativePathsResolveAgainstTheBase;
var
  M: TLedOutputMatch;
  F: TLedOutputFilter;
begin
  F := LedFilters.Find('default');
  F.Reset('/home/me/project');
  M := F.Process('src/a.c:1: error: x');
  AssertEquals('/home/me/project/src/a.c', M.FileName);
end;

procedure TTestOutputFilter.MakeDirectoryStack;
var
  M: TLedOutputMatch;
  F: TLedOutputFilter;
begin
  { The case that makes this filter worth having: in a recursive build the
    file names after "Entering directory" are relative to that directory. }
  F := LedFilters.Find('make');
  F.Reset('/top');
  F.Process('make[1]: Entering directory `/top/sub''');
  AssertEquals('/top/sub', F.CurrentDir);
  M := F.Process('a.c:5: error: nope');
  AssertEquals('/top/sub/a.c', M.FileName);
end;

procedure TTestOutputFilter.MakePopRestoresThePrevious;
var
  M: TLedOutputMatch;
  F: TLedOutputFilter;
begin
  F := LedFilters.Find('make');
  F.Reset('/top');
  F.Process('make[1]: Entering directory `/top/sub''');
  F.Process('make[1]: Leaving directory `/top/sub''');
  AssertEquals('/top', F.CurrentDir);
  M := F.Process('b.c:1: error: nope');
  AssertEquals('/top/b.c', M.FileName);
end;

procedure TTestOutputFilter.NoneFilterMatchesNothing;
var
  M: TLedOutputMatch;
  F: TLedOutputFilter;
begin
  F := LedFilters.Find('none');
  F.Reset('');
  M := F.Process('a.c:1: error: x');
  AssertTrue(M.Kind = lmkNone);
end;

initialization
  RegisterTest(TTestToolFile);
  RegisterTest(TTestOutputFilter);

end.
