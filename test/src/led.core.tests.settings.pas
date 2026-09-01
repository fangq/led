{ led - a light editor.  Headless tests for preferences, session and recent
  files.  All three write to disk, so they are exercised against a temporary
  config directory rather than the user's real one. }
unit Led.Core.Tests.Settings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.Types, Led.Core.Config, Led.Core.Paths, Led.Core.Prefs,
  Led.Core.Session;

type
  TTempDirTest = class(TTestCase)
  protected
    FDir: string;
    procedure SetUp; override;
    procedure TearDown; override;
    function Path(const AName: string): string;
  end;

  TTestPrefs = class(TTempDirTest)
  published
    procedure DottedKeysBecomeSections;
    procedure RoundTripsThroughDisk;
    procedure DefaultsWhenAbsent;
    procedure BoolSpellingsAreAccepted;
    procedure MissingFileIsNotAnError;
    procedure AppliesToConfigAtUserPrecedence;
    procedure SpacesInsteadOfTabsIsInverted;
    procedure RemoveDropsTheKey;
  end;

  TTestSession = class(TTempDirTest)
  published
    procedure RoundTrip;
    procedure MissingFileLoadsNothing;
    procedure CorruptFileIsIgnoredNotFatal;
    procedure WrongVersionIsIgnored;
    procedure TabsWithoutAFileAreDropped;
  end;

  TTestRecent = class(TTempDirTest)
  published
    procedure NewestFirst;
    procedure ReAddingMovesToFront;
    procedure CapIsEnforced;
    procedure RoundTrip;
    procedure RemoveWorks;
  end;

  TTestAtomicWrite = class(TTempDirTest)
  published
    procedure WritesContent;
    procedure KeepsOneBackup;
    procedure LeavesNoTempFile;
  end;

implementation

{ TTempDirTest }

procedure TTempDirTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-set-%d-%s%s', [GetProcessID, TestName, PathDelim]);
  ForceDirectories(FDir);
end;

procedure TTempDirTest.TearDown;
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

function TTempDirTest.Path(const AName: string): string;
begin
  Result := FDir + AName;
end;

{ TTestPrefs }

procedure TTestPrefs.DottedKeysBecomeSections;
var
  P: TLedPrefs;
  L: TStringList;
begin
  P := TLedPrefs.Create(Path('p.ini'));
  try
    P.SetInt('Editor/tab_width', 4);
    P.SetStr('Plugins/Terminal/font', 'Fira Code 13');
    P.Save;
  finally
    P.Free;
  end;

  L := TStringList.Create;
  try
    L.LoadFromFile(Path('p.ini'));
    AssertTrue('[Editor] section exists', Pos('[Editor]', L.Text) > 0);
    AssertTrue('nested key becomes a dotted section',
      Pos('[Plugins.Terminal]', L.Text) > 0);
    AssertTrue('value is written', Pos('tab_width=4', L.Text) > 0);
  finally
    L.Free;
  end;
end;

procedure TTestPrefs.RoundTripsThroughDisk;
var
  P: TLedPrefs;
begin
  P := TLedPrefs.Create(Path('p.ini'));
  try
    P.SetStr(LedPrefFont, 'Fira Code 10');
    P.SetInt(LedPrefTabWidth, 3);
    P.SetBool(LedPrefSpacesNotTabs, True);
    P.Save;
  finally
    P.Free;
  end;

  P := TLedPrefs.Create(Path('p.ini'));
  try
    P.Load;
    AssertEquals('Fira Code 10', P.GetStr(LedPrefFont, ''));
    AssertEquals(3, P.GetInt(LedPrefTabWidth, 8));
    AssertTrue(P.GetBool(LedPrefSpacesNotTabs, False));
  finally
    P.Free;
  end;
end;

procedure TTestPrefs.DefaultsWhenAbsent;
var
  P: TLedPrefs;
begin
  P := TLedPrefs.Create(Path('p.ini'));
  try
    AssertEquals('fallback', P.GetStr('Editor/nothing', 'fallback'));
    AssertEquals(42, P.GetInt('Editor/nothing', 42));
    AssertTrue(P.GetBool('Editor/nothing', True));
  finally
    P.Free;
  end;
end;

procedure TTestPrefs.BoolSpellingsAreAccepted;
var
  P: TLedPrefs;
  L: TStringList;
begin
  { A hand-edited file may say true/yes/on rather than 1. }
  L := TStringList.Create;
  try
    L.Add('[Editor]');
    L.Add('a=true');
    L.Add('b=yes');
    L.Add('c=off');
    L.Add('d=rubbish');
    L.SaveToFile(Path('p.ini'));
  finally
    L.Free;
  end;

  P := TLedPrefs.Create(Path('p.ini'));
  try
    P.Load;
    AssertTrue(P.GetBool('Editor/a', False));
    AssertTrue(P.GetBool('Editor/b', False));
    AssertFalse(P.GetBool('Editor/c', True));
    AssertTrue('unparsable falls back to the default',
      P.GetBool('Editor/d', True));
  finally
    P.Free;
  end;
end;

procedure TTestPrefs.MissingFileIsNotAnError;
var
  P: TLedPrefs;
begin
  P := TLedPrefs.Create(Path('never-written.ini'));
  try
    P.Load;
    AssertEquals(8, P.GetInt(LedPrefTabWidth, 8));
  finally
    P.Free;
  end;
end;

procedure TTestPrefs.AppliesToConfigAtUserPrecedence;
var
  P: TLedPrefs;
  C: TLedDocConfig;
begin
  P := TLedPrefs.Create(Path('p.ini'));
  C := TLedDocConfig.Create;
  try
    P.SetInt(LedPrefTabWidth, 2);
    P.ApplyToConfig(C);
    AssertEquals(2, C.GetInt(LedSetTabWidth));
    AssertTrue('written at user precedence', C.SourceOf(LedSetTabWidth) = lcsUser);
    { A modeline must still win over it. }
    C.SetInt(LedSetTabWidth, 9, lcsFile);
    AssertEquals(9, C.GetInt(LedSetTabWidth));
  finally
    C.Free;
    P.Free;
  end;
end;

procedure TTestPrefs.SpacesInsteadOfTabsIsInverted;
var
  P: TLedPrefs;
  C: TLedDocConfig;
begin
  { The preference asks for spaces; the setting records whether tabs are used.
    Getting the inversion wrong silently retabs files. }
  P := TLedPrefs.Create(Path('p.ini'));
  C := TLedDocConfig.Create;
  try
    P.SetBool(LedPrefSpacesNotTabs, True);
    P.ApplyToConfig(C);
    AssertFalse(C.GetBool(LedSetIndentUseTabs));

    P.SetBool(LedPrefSpacesNotTabs, False);
    C.UnsetBySource(lcsUser);
    P.ApplyToConfig(C);
    AssertTrue(C.GetBool(LedSetIndentUseTabs));
  finally
    C.Free;
    P.Free;
  end;
end;

procedure TTestPrefs.RemoveDropsTheKey;
var
  P: TLedPrefs;
begin
  P := TLedPrefs.Create(Path('p.ini'));
  try
    P.SetInt('Editor/x', 1);
    AssertTrue(P.HasKey('Editor/x'));
    P.Remove('Editor/x');
    AssertFalse(P.HasKey('Editor/x'));
  finally
    P.Free;
  end;
end;

{ TTestSession }

procedure TTestSession.RoundTrip;
var
  S: TLedSession;
  W: TLedWindowState;
  T: TLedTabState;
begin
  S := TLedSession.Create(Path('s.json'));
  try
    S.AddWindow;
    W := S.Windows[0];
    W.Left := 10; W.Top := 20; W.Width := 800; W.Height := 600;
    W.Maximized := True; W.ActiveTab := 1;
    W.Docks[0].Visible := True; W.Docks[0].Size := 240;
    W.Docks[0].ActivePane := 'files';
    S.SetWindow(0, W);

    T := Default(TLedTabState);
    T.FileName := '/tmp/a.c'; T.Encoding := 'utf8'; T.Language := 'c';
    T.Line := 42; T.Column := 7; T.TopLine := 30;
    S.AddTab(0, T);
    T.FileName := '/tmp/b.c'; T.Line := 1;
    S.AddTab(0, T);
    S.Save;
  finally
    S.Free;
  end;

  S := TLedSession.Create(Path('s.json'));
  try
    AssertTrue(S.Load);
    AssertEquals(1, S.WindowCount);
    W := S.Windows[0];
    AssertEquals(800, W.Width);
    AssertTrue(W.Maximized);
    AssertEquals(1, W.ActiveTab);
    AssertEquals(2, Length(W.Tabs));
    AssertEquals('/tmp/a.c', W.Tabs[0].FileName);
    AssertEquals(42, W.Tabs[0].Line);
    AssertEquals(30, W.Tabs[0].TopLine);
    AssertEquals('c', W.Tabs[0].Language);
    AssertTrue(W.Docks[0].Visible);
    AssertEquals(240, W.Docks[0].Size);
    AssertEquals('files', W.Docks[0].ActivePane);
  finally
    S.Free;
  end;
end;

procedure TTestSession.MissingFileLoadsNothing;
var
  S: TLedSession;
begin
  S := TLedSession.Create(Path('none.json'));
  try
    AssertFalse(S.Load);
    AssertEquals(0, S.WindowCount);
  finally
    S.Free;
  end;
end;

procedure TTestSession.CorruptFileIsIgnoredNotFatal;
var
  S: TLedSession;
  L: TStringList;
begin
  { Starting the editor must survive a half-written session file. }
  L := TStringList.Create;
  try
    L.Text := '{ "version": 1, "windows": [ { "left": ';
    L.SaveToFile(Path('bad.json'));
  finally
    L.Free;
  end;

  S := TLedSession.Create(Path('bad.json'));
  try
    AssertFalse(S.Load);
    AssertEquals(0, S.WindowCount);
  finally
    S.Free;
  end;
end;

procedure TTestSession.WrongVersionIsIgnored;
var
  S: TLedSession;
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := '{"version": 99, "windows": [{"left": 1}]}';
    L.SaveToFile(Path('v.json'));
  finally
    L.Free;
  end;

  S := TLedSession.Create(Path('v.json'));
  try
    AssertFalse(S.Load);
  finally
    S.Free;
  end;
end;

procedure TTestSession.TabsWithoutAFileAreDropped;
var
  S: TLedSession;
  L: TStringList;
begin
  { An untitled document has nothing to restore from. }
  L := TStringList.Create;
  try
    L.Text := '{"version": 1, "windows": [{"tabs": [{"file": ""},' +
              '{"file": "/tmp/x"}]}]}';
    L.SaveToFile(Path('u.json'));
  finally
    L.Free;
  end;

  S := TLedSession.Create(Path('u.json'));
  try
    AssertTrue(S.Load);
    AssertEquals(1, Length(S.Windows[0].Tabs));
    AssertEquals('/tmp/x', S.Windows[0].Tabs[0].FileName);
  finally
    S.Free;
  end;
end;

{ TTestRecent }

procedure TTestRecent.NewestFirst;
var
  R: TLedRecentFiles;
begin
  R := TLedRecentFiles.Create(Path('r.json'));
  try
    R.Add('/tmp/one');
    R.Add('/tmp/two');
    AssertEquals(2, R.Count);
    AssertEquals('/tmp/two', R[0]);
  finally
    R.Free;
  end;
end;

procedure TTestRecent.ReAddingMovesToFront;
var
  R: TLedRecentFiles;
begin
  R := TLedRecentFiles.Create(Path('r.json'));
  try
    R.Add('/tmp/one');
    R.Add('/tmp/two');
    R.Add('/tmp/one');
    AssertEquals('no duplicate', 2, R.Count);
    AssertEquals('/tmp/one', R[0]);
  finally
    R.Free;
  end;
end;

procedure TTestRecent.CapIsEnforced;
var
  R: TLedRecentFiles;
  i: Integer;
begin
  R := TLedRecentFiles.Create(Path('r.json'), 3);
  try
    for i := 1 to 10 do
      R.Add('/tmp/f' + IntToStr(i));
    AssertEquals(3, R.Count);
    AssertEquals('/tmp/f10', R[0]);
    AssertEquals('/tmp/f8', R[2]);
  finally
    R.Free;
  end;
end;

procedure TTestRecent.RoundTrip;
var
  R: TLedRecentFiles;
begin
  R := TLedRecentFiles.Create(Path('r.json'));
  try
    R.Add('/tmp/one');
    R.Add('/tmp/two');
    R.Save;
  finally
    R.Free;
  end;

  R := TLedRecentFiles.Create(Path('r.json'));
  try
    R.Load;
    AssertEquals(2, R.Count);
    AssertEquals('/tmp/two', R[0]);
  finally
    R.Free;
  end;
end;

procedure TTestRecent.RemoveWorks;
var
  R: TLedRecentFiles;
begin
  R := TLedRecentFiles.Create(Path('r.json'));
  try
    R.Add('/tmp/one');
    R.Add('/tmp/two');
    R.Remove('/tmp/one');
    AssertEquals(1, R.Count);
    AssertEquals('/tmp/two', R[0]);
  finally
    R.Free;
  end;
end;

{ TTestAtomicWrite }

procedure TTestAtomicWrite.WritesContent;
var
  L: TStringList;
begin
  LedWriteFileAtomic(Path('a.txt'), 'hello');
  L := TStringList.Create;
  try
    L.LoadFromFile(Path('a.txt'));
    AssertEquals('hello', Trim(L.Text));
  finally
    L.Free;
  end;
end;

procedure TTestAtomicWrite.KeepsOneBackup;
var
  L: TStringList;
begin
  LedWriteFileAtomic(Path('a.txt'), 'first');
  LedWriteFileAtomic(Path('a.txt'), 'second');
  AssertTrue('backup exists', FileExists(Path('a.txt.bak')));
  L := TStringList.Create;
  try
    L.LoadFromFile(Path('a.txt.bak'));
    AssertEquals('first', Trim(L.Text));
    L.LoadFromFile(Path('a.txt'));
    AssertEquals('second', Trim(L.Text));
  finally
    L.Free;
  end;
end;

procedure TTestAtomicWrite.LeavesNoTempFile;
begin
  LedWriteFileAtomic(Path('a.txt'), 'x');
  AssertFalse(FileExists(Path('a.txt.tmp')));
end;

initialization
  RegisterTest(TTestPrefs);
  RegisterTest(TTestSession);
  RegisterTest(TTestRecent);
  RegisterTest(TTestAtomicWrite);

end.
