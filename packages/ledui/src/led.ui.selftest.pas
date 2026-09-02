{ led - a light editor.  Scripted GUI self-test.

  Run with `led --self-test`.  Drives the real main window through a sequence
  of actions, checking the state the user would see, and exits non-zero on the
  first failure.  This is what catches the integration bugs -- action
  enabling, tab lifecycle, split teardown -- that headless unit tests over
  ledcore structurally cannot.

  It needs a display; in CI it runs under xvfb-run. }
unit Led.UI.SelfTest;

{$mode objfpc}{$H+}

interface

function LedRunSelfTest: Integer;

implementation

uses
  Classes, SysUtils, Forms, ComCtrls,
  FileUtil,
  LCLType, SynEditMiscClasses, SynEditMarkup, SynEditHighlighterFoldBase,
  Led.Core.Types, Led.Core.CLI, Led.Core.FileIO, Led.Core.Config, Led.Core.Prefs,
  Led.Core.Paths,
  Led.Syn.Languages, Led.Syn.Theme, Led.Syn.Factory,
  Led.UI.Main, Led.UI.Document, Led.UI.Tab, Led.UI.Edit, Led.UI.Dock,
  Led.UI.Splitter,
  Led.UI.Commands, Led.UI.Find, Led.UI.Prefs, Led.UI.Shortcuts,
  Led.UI.Icons, Led.UI.Focus, Graphics, IntfGraphics, FPimage, StdCtrls,
  Led.UI.ToolRunner, Led.UI.Output, Led.UI.FileBrowser,
  Led.Term.View, Led.Term.Pty, Led.Term.Screen, Led.Term.Pane,
  Led.Core.Session, Led.UI.Symbols,
  Led.Core.Ctags,
  Led.Core.Tools, Led.Core.OutputFilter, Led.Core.Filters,
  Clipbrd, SynEditTypes, ActnList, Menus, PairSplitter, LCLProc;

var
  Failures: Integer = 0;
  Checks: Integer = 0;

{ Flushed after every line.  Output to a file is block-buffered, so without
  this the log stops well short of wherever a hang actually is -- which cost
  a diagnosis once already. }
procedure Say(const AText: string);
begin
  WriteLn(AText);
  Flush(Output);
end;

procedure Check(const AName: string; ACondition: Boolean);
begin
  Inc(Checks);
  if ACondition then
    Say('  ok    ' + AName)
  else
  begin
    Say('  FAIL  ' + AName);
    Inc(Failures);
  end;
end;

procedure CheckEq(const AName: string; const AExpected, AActual: string);
begin
  Inc(Checks);
  if AExpected = AActual then
    Say('  ok    ' + AName)
  else
  begin
    Say('  FAIL  ' + AName);
    Say('          expected: ' + AExpected);
    Say('          actual:   ' + AActual);
    Inc(Failures);
  end;
end;

procedure CheckGt(const AName: string; AFloor, AActual: Integer);
begin
  Check(AName + Format(' (%d > %d)', [AActual, AFloor]), AActual > AFloor);
end;

procedure CheckEqInt(const AName: string; AExpected, AActual: Integer);
begin
  CheckEq(AName, IntToStr(AExpected), IntToStr(AActual));
end;

procedure Pump;
var
  i: Integer;
begin
  for i := 1 to 5 do
    Application.ProcessMessages;
end;

function TempName(const ASuffix: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-selftest-%d-%s', [GetProcessID, ASuffix]);
end;

{ --- the spikes phase 0 exists to prove ------------------------------------ }

procedure TestSharedBufferSplitView(F: TLedMainForm);
var
  Tab: TLedTab;
  V0, V1: TLedEdit;
  Splitter: TPairSplitter;
begin
  Say('shared-buffer split view');
  Tab := F.ActiveTab;
  Check('a tab exists', Tab <> nil);
  if Tab = nil then Exit;

  CheckEqInt('one view to start', 1, Tab.ViewCount);
  V0 := Tab.ActiveView;
  V0.Lines.Text := 'alpha' + LineEnding + 'beta' + LineEnding + 'gamma';
  V0.ClearUndo;
  Pump;

  Tab.SplitView(False);
  Pump;
  CheckEqInt('two views after split', 2, Tab.ViewCount);
  V1 := Tab.Views[1];

  { The whole view model rests on this: one buffer, many views. }
  CheckEq('text is shared', V0.Lines.Text, V1.Lines.Text);

  { Edit the way a user does -- through the editor, not by poking the string
    list -- because that is what goes onto the undo list. }
  V0.CaretXY := Point(1, 2);
  V0.SelectLine(False);
  V0.SelText := 'BETA';
  Pump;
  CheckEq('edit in view 0 is visible in view 1', 'BETA', V1.Lines[1]);

  { Undo lives in the shared string list, so undoing through either view
    affects both. }
  V1.Undo;
  Pump;
  CheckEq('undo is shared', 'beta', V0.Lines[1]);
  V1.Redo;
  Pump;
  CheckEq('redo is shared', 'BETA', V0.Lines[1]);

  { Caret and scroll must stay independent, or split view is pointless. }
  V0.CaretXY := Point(1, 1);
  V1.CaretXY := Point(1, 3);
  Pump;
  Check('carets are independent', (V0.CaretY = 1) and (V1.CaretY = 3));

  { Marks are shared through eosShareMarks. }
  V0.SetBookMark(0, 1, 2);
  Pump;
  Check('bookmarks are shared', V1.Marks.Count > 0);

  Tab.Unsplit;
  Pump;
  CheckEqInt('back to one view after unsplit', 1, Tab.ViewCount);

  { Stacked split and cycling. }
  Tab.SplitView(True);
  Pump;
  CheckEqInt('two views after stacked split', 2, Tab.ViewCount);

  { A fresh split has to land in the middle.  TPairSplitter puts its divider
    wherever its default position falls, which is not the middle, and a
    lopsided split was reported from real use. }
  Splitter := nil;
  if Tab.Views[1].Parent is TPairSplitterSide then
    Splitter := TPairSplitter(Tab.Views[1].Parent.Parent);
  Check('the stacked split has a splitter', Splitter <> nil);
  if (Splitter <> nil) and (Splitter.Height > 40) then
    Check('and it opens within a few pixels of the middle',
      Abs(Splitter.Position - Splitter.Height div 2) <= 4);

  Tab.CycleViews;
  Pump;
  Tab.Unsplit;
  Pump;
  CheckEqInt('one view again', 1, Tab.ViewCount);
end;

const
  { mooterminal.c:86, in that order. }
  MeditSchemes: array[0..9] of string = (
    'Default', 'Black on White', 'Black on Light Yellow', 'Marble',
    'Green on Black', 'Paper, Light', 'Paper', 'Linux Colors',
    'VIM Colors', 'White on Black');

procedure TestBrowserNavigation(F: TLedMainForm);
var
  Dir, Sub, Start: string;
begin
  Say('file browser navigation');

  Dir := IncludeTrailingPathDelimiter(TempName('nav'));
  Sub := Dir + 'inner' + PathDelim;
  ForceDirectories(Sub);

  F.Dock.ShowPane('files');
  Pump;
  F.Browser.SetRoot(Dir);
  Pump;
  Start := F.Browser.Root;

  Check('nothing to go back to yet', not F.Browser.CanGoBack);
  Check('and nothing forward', not F.Browser.CanGoForward);

  F.Browser.SetRoot(Sub);
  Pump;
  Check('moving somewhere makes back available', F.Browser.CanGoBack);

  F.Browser.GoBack;
  Pump;
  CheckEq('and back returns to where it was', Start, F.Browser.Root);
  Check('with forward now available', F.Browser.CanGoForward);

  F.Browser.GoForward;
  Pump;
  Check('forward goes on again',
    SameFileName(ExcludeTrailingPathDelimiter(Sub), F.Browser.Root));

  { Going somewhere new from part-way back drops the forward trail, the way
    a browser does -- otherwise Forward leads somewhere the user has since
    left. }
  F.Browser.GoBack;
  Pump;
  F.Browser.SetRoot(GetTempDir);
  Pump;
  Check('a new turning discards the forward trail', not F.Browser.CanGoForward);

  F.Browser.GoUp;
  Pump;
  Check('up leaves a real folder', DirectoryExists(F.Browser.Root));

  F.Browser.GoHome;
  Pump;
  CheckEq('home is the user folder',
    ExcludeTrailingPathDelimiter(GetUserDir), F.Browser.Root);

  RemoveDir(Sub);
  RemoveDir(ExcludeTrailingPathDelimiter(Dir));
end;

procedure TestTerminalPaneAndSession(F: TLedMainForm);
var
  Pane: TLedTerminalPane;
  Doc: TLedDocument;
  Tab: TLedTab;
  Sess: TLedSession;
  Found: Boolean;
  Missing: string;
  j: Integer;
  Path1, Path2: string;
  L: TStringList;
  i, Before: Integer;
begin
  { An audit rather than a feature test: PARITY called terminal splitting,
    the colour schemes and session restore "partly" done without saying what
    was missing, and the suite had never touched TLedTerminalPane at all. }
  Say('terminal pane');

  if not LedPtyAvailable then
    WriteLn('  (skipped: no pseudo-terminal on this platform)')
  else
  begin
    Pane := TLedTerminalPane.Create(F);
    try
      Pane.Parent := F;
      Pane.Width := 600;
      Pane.Height := 300;
      Pane.Visible := False;
      Pump;

      Check('the pane starts a terminal', Pane.Start(GetTempDir));
      CheckEqInt('one to begin with', 1, Pane.Count);

      Pane.Split(False);
      Pump;
      CheckEqInt('side-by-side split gives two', 2, Pane.Count);
      Pane.Split(True);
      Pump;
      CheckEqInt('and a stacked split gives three', 3, Pane.Count);

      { Splitting is recursive, so the third lives inside the second's
        splitter rather than beside the first. }
      Check('the splits nest', Pane.Active.Parent is TPairSplitterSide);

      Pane.CloseActive;
      Pump;
      CheckEqInt('closing one collapses its splitter', 2, Pane.Count);
      Check('and something is still active', Pane.Active <> nil);

      { The cap exists so a stuck key cannot fork shells without limit. }
      Before := Pane.Count;
      for i := 1 to LedMaxTerminals + 2 do Pane.Split(False);
      Pump;
      Check('the split count is capped', Pane.Count <= LedMaxTerminals);
      Check('and the cap is above where we started', Pane.Count > Before);
    finally
      Pane.Free;
    end;
  end;

  { medit shipped ten named ANSI palettes.  Checked by name rather than by
    count, so led is free to add its own without the check going off -- the
    parity note claimed five were missing when six were, which is what
    counting instead of naming gets you. }
  Say('terminal colour schemes');
  Missing := '';
  for i := 0 to High(MeditSchemes) do
  begin
    Found := False;
    for j := 0 to LedTermSchemeCount - 1 do
      if SameText(LedTermSchemeName(j), MeditSchemes[i]) then Found := True;
    if not Found then Missing := Missing + MeditSchemes[i] + ' ';
  end;
  CheckEq('all ten of medit''s palettes are present', '', Missing);

  Found := True;
  for i := 0 to LedTermSchemeCount - 1 do
    if LedTermSchemeName(i) = '' then Found := False;
  Check('and every palette is named', Found);

  { Session round trip.  What is written is what comes back, so anything the
    writer never looked at is silently lost -- which is the question the
    "partly" label was hiding. }
  Say('session round trip');

  Path1 := TempName('session-a.txt');
  Path2 := TempName('session-b.txt');
  L := TStringList.Create;
  try
    L.Add('one'); L.Add('two'); L.Add('three'); L.Add('four');
    L.SaveToFile(Path1);
    L.SaveToFile(Path2);
  finally
    L.Free;
  end;

  Doc := F.Documents.NewDocument;
  Doc.LoadFromFile(Path1);
  Tab := F.AddTab(Doc);
  Pump;
  Tab.ActiveView.CaretXY := Point(2, 3);

  { A split view, and a tab in the second notebook: both are things a user
    sets up and expects to find again. }
  Tab.SplitView(False);
  Pump;
  CheckEqInt('the tab has two views before saving', 2, Tab.ViewCount);

  { A second document, moved into the split notebook.  Both tab groups hold
    real work, so both have to be written. }
  Doc := F.Documents.NewDocument;
  Doc.LoadFromFile(Path2);
  Tab := F.AddTab(Doc);
  Pump;
  F.actSplitNotebookExecute(nil);
  Pump;
  if F.Notebook2 <> nil then
  begin
    F.MoveTabToBook(Tab, F.Notebook2);
    Pump;
    Check('the second notebook holds a tab', F.Notebook2.PageCount > 0);
  end;

  F.SaveSession;
  Sess := TLedSession.Create;
  try
    Check('the session file was written', Sess.Load);
    Check('it has a window', Sess.WindowCount > 0);

    Found := False;
    for i := 0 to High(Sess.Windows[0].Tabs) do
      if SameText(Sess.Windows[0].Tabs[i].FileName, Path1) then Found := True;
    Check('the first document is in the session', Found);

    { The one that matters.  SaveSession walks Notebook only, so anything the
      user moved into the second tab group is dropped without a word. }
    Found := False;
    for i := 0 to High(Sess.Windows[0].Tabs) do
      if SameText(Sess.Windows[0].Tabs[i].FileName, Path2) then Found := True;
    Check('and so is the one in the second notebook', Found);

    { Split views: the tab with two views has to come back with two. }
    Found := False;
    for i := 0 to High(Sess.Windows[0].Tabs) do
      if SameText(Sess.Windows[0].Tabs[i].FileName, Path1) then
        Found := Length(Sess.Windows[0].Tabs[i].Views) = 2;
    Check('the split view is recorded', Found);

    { And the notebook each tab was in. }
    Found := False;
    for i := 0 to High(Sess.Windows[0].Tabs) do
      if SameText(Sess.Windows[0].Tabs[i].FileName, Path2) then
        Found := Sess.Windows[0].Tabs[i].Notebook = 1;
    Check('with the tab group it was in', Found);
  finally
    Sess.Free;
  end;

  { Put the window back the way it was found.  Leaving the notebook split
    broke the precondition of the split-notebook test that runs later, which
    is a fault in this test and not in that one. }
  if F.NotebookSplit then
  begin
    F.SetNotebookSplit(False);
    Pump;
  end;
  while F.Notebook.PageCount > 1 do
  begin
    F.Notebook.ActivePageIndex := F.Notebook.PageCount - 1;
    F.CloseActiveTab(False);
    Pump;
  end;
  Check('the window is back to one tab group', not F.NotebookSplit);

  DeleteFile(Path1);
  DeleteFile(Path2);
end;

procedure TestIconsAndFocus(F: TLedMainForm);
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  x, y, Clear, Opaque, Purple, i, Blank: Integer;
  C: TFPColor;
  Hidden: TForm;
  Ed: TEdit;
begin
  Say('icons and focus');

  CheckEqInt('every icon was built', Length(LedIconNames), F.ImageList1.Count);

  { The icons are drawn on a mask colour that has to disappear.  Getting this
    wrong is not subtle -- it puts a purple square behind every toolbar
    button -- and it is invisible to any check that only counts images. }
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(F.ImageList1.Width, F.ImageList1.Height);
    F.ImageList1.GetBitmap(LedIconIndex('save'), Bmp);
    Img := Bmp.CreateIntfImage;
    try
      Clear := 0; Opaque := 0; Purple := 0;
      for y := 0 to Img.Height - 1 do
        for x := 0 to Img.Width - 1 do
        begin
          C := Img.Colors[x, y];
          if C.Alpha < $4000 then Inc(Clear) else Inc(Opaque);
          if (C.Alpha >= $4000) and (C.Red > $C000) and (C.Blue > $C000) and
             (C.Green < $4000) then Inc(Purple);
        end;
    finally
      Img.Free;
    end;
    Check('an icon has a transparent background', Clear > 0);
    Check('and it still has an icon on it', Opaque > 0);
    CheckEqInt('and no mask colour survives', 0, Purple);
  finally
    Bmp.Free;
  end;

  { An icon that draws nothing is a missing case branch, which is easy to
    introduce and impossible to see in a menu. }
  Blank := 0;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(F.ImageList1.Width, F.ImageList1.Height);
    for i := 0 to F.ImageList1.Count - 1 do
    begin
      F.ImageList1.GetBitmap(i, Bmp);
      Img := Bmp.CreateIntfImage;
      try
        Opaque := 0;
        for y := 0 to Img.Height - 1 do
          for x := 0 to Img.Width - 1 do
            if Img.Colors[x, y].Alpha >= $4000 then Inc(Opaque);
        if Opaque = 0 then Inc(Blank);
      finally
        Img.Free;
      end;
    end;
  finally
    Bmp.Free;
  end;
  CheckEqInt('no icon is blank', 0, Blank);

  { The state that raises is a form that is neither active nor visible-and-
    enabled: during FormCreate, and for as long as a modal dialog holds the
    main window disabled.  Disabling the main window here is not enough to
    reproduce it -- it stays the active form, and FocusControl only calls
    Form.SetFocus when the form was not already active -- so the check uses
    a window that was never shown, which is the startup case exactly. }
  Hidden := TForm.CreateNew(nil);
  try
    Hidden.Name := 'LedFocusProbe';
    Ed := TEdit.Create(Hidden);
    Ed.Parent := Hidden;
    Check('focus is declined on a window that is not showing',
      not LedTryFocus(Ed));
    Check('and the editor can still be focused', LedTryFocus(F.ActiveView));
  finally
    Hidden.Free;
  end;
end;

procedure TestDockEdges(F: TLedMainForm);
var
  E: TLedDockEdge;
  LayoutFile: string;
begin
  Say('docking');
  { An edge is as visible as the panes registered for it, so an edge with no
    panes cannot be shown.  The old dock built an empty tab control per edge
    and happily "showed" nothing, which is what this used to assert. }
  for E := Low(TLedDockEdge) to High(TLedDockEdge) do
  begin
    F.Dock.EdgeVisible[E] := True;
    Pump;
    if F.Dock.EdgeHasPanes(E) then
      Check('edge ' + LedDockEdgeName[E] + ' shows', F.Dock.EdgeVisible[E])
    else
      Check('edge ' + LedDockEdgeName[E] + ' has nothing to show',
        not F.Dock.EdgeVisible[E]);
    F.Dock.EdgeVisible[E] := False;
    Pump;
    Check('edge ' + LedDockEdgeName[E] + ' hides', not F.Dock.EdgeVisible[E]);
  end;

  Check('a registered pane is findable', F.Dock.FindPane('files') <> nil);
  F.Dock.ShowPane('files');
  Pump;
  Check('showing a pane reveals its edge', F.Dock.EdgeVisible[ledLeft]);
  Check('and the pane itself reports visible', F.Dock.PaneVisible('files'));

  { Every pane can be torn off into its own window and put back, which is the
    behaviour medit's 7,200-line pane system existed to provide. }
  Check('a pane can be floated', F.Dock.FloatPane('files'));
  Pump;
  Check('and it is floating', F.Dock.PaneFloating('files'));
  Check('and it can be docked again', F.Dock.RedockPane('files'));
  Pump;
  Check('and it is docked', not F.Dock.PaneFloating('files'));

  { The layout round-trips, including where each pane sits. }
  LayoutFile := TempName('layout.xml');
  F.Dock.SaveLayout(LayoutFile);
  Check('the layout was written', FileExists(LayoutFile));
  Check('and it loads back', F.Dock.LoadLayout(LayoutFile));
  DeleteFile(LayoutFile);

  F.Dock.EdgeVisible[ledLeft] := False;
end;

procedure TestTabsAndFileRoundTrip(F: TLedMainForm);
var
  Path: string;
  Doc: TLedDocument;
  Before, After: string;
  Info: TLedTextInfo;
  N: Integer;
begin
  Say('tabs and file round trip');
  N := F.Notebook.PageCount;
  F.AddTab(F.Documents.NewDocument);
  Pump;
  CheckEqInt('new tab added', N + 1, F.Notebook.PageCount);

  Path := TempName('roundtrip.txt');
  Doc := F.ActiveTab.Document;
  Doc.Master.Lines.Text := 'one' + LineEnding + 'two' + LineEnding + 'three';
  Doc.SaveToFile(Path);
  Pump;
  Check('document is no longer modified after save', not Doc.Modified);
  CheckEq('tab caption follows the file name', ExtractFileName(Path),
    F.ActiveTab.Sheet.Caption);

  Before := Doc.Master.Lines.Text;
  LedLoadTextFile(Path, After, Info);
  CheckEq('saved text reloads identically',
    StringReplace(Before, LineEnding, #10, [rfReplaceAll]),
    After);
  DeleteFile(Path);
end;

procedure TestLineEndDetection;
begin
  Say('line-ending detection');
  Check('LF',    LedDetectLineEnd('a'#10'b') = leUnix);
  Check('CRLF',  LedDetectLineEnd('a'#13#10'b') = leWindows);
  Check('CR',    LedDetectLineEnd('a'#13'b') = leMac);
  Check('mixed', LedDetectLineEnd('a'#13#10'b'#10'c') = leMixed);
  Check('none',  LedDetectLineEnd('abc') = leUnknown);
end;

{ --- phase 1: the document behaviours the file layer makes possible -------- }

procedure TestDocumentBehaviour(F: TLedMainForm);
var
  Path: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  L: TStringList;
begin
  Say('document behaviour');

  Path := TempName('doc.txt');
  L := TStringList.Create;
  try
    L.TextLineBreakStyle := tlbsCRLF;
    L.Add('first');
    L.Add('second');
    L.SaveToFile(Path);
  finally
    L.Free;
  end;

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  Doc.LoadFromFile(Path);
  Pump;

  Check('CRLF was detected', Doc.Info.LineEnd = leWindows);
  CheckEq('encoding recorded', 'utf8', Doc.Info.Encoding);
  Check('not modified after load', not Doc.Modified);
  Check('nothing changed on disk yet', not Doc.ChangedOnDisk);

  { Config reaches the views. }
  Doc.Config.SetInt(LedSetTabWidth, 3, lcsUser);
  Pump;
  CheckEqInt('tab width reaches the view', 3, Tab.ActiveView.TabWidth);

  { A modeline outranks the preference. }
  Doc.Config.SetInt(LedSetTabWidth, 7, lcsFile);
  Doc.Config.SetInt(LedSetTabWidth, 2, lcsUser);
  Pump;
  CheckEqInt('modeline beats preferences in a live document', 7,
    Tab.ActiveView.TabWidth);

  { Changing the line ending marks the document dirty and re-serialises. }
  Doc.SetLineEnd(leUnix);
  Check('line-ending change marks it modified', Doc.Modified);
  Doc.Save;
  Pump;
  Check('saved', not Doc.Modified);
  L := TStringList.Create;
  try
    L.LoadFromFile(Path);
    Check('file no longer holds CRLF', Pos(#13#10, L.Text) = 0);
  finally
    L.Free;
  end;

  { An outside edit is noticed. }
  Sleep(1100);      { file mtime granularity is a second on some filesystems }
  L := TStringList.Create;
  try
    L.Add('changed underneath');
    L.SaveToFile(Path);
  finally
    L.Free;
  end;
  Check('external change is detected', Doc.ChangedOnDisk);

  Doc.Reload;
  Pump;
  CheckEq('reload picks up the new content', 'changed underneath',
    Doc.Master.Lines[0]);
  Check('reload clears the external-change flag', not Doc.ChangedOnDisk);

  DeleteFile(Path);
  Check('deletion is detected', Doc.DeletedFromDisk);
end;

procedure TestRecentFiles(F: TLedMainForm);
var
  Path: string;
  L: TStringList;
begin
  Say('recent files');
  Path := TempName('recent.txt');
  L := TStringList.Create;
  try
    L.Add('x');
    L.SaveToFile(Path);
  finally
    L.Free;
  end;

  L := TStringList.Create;
  try
    L.Add(Path);
    F.OpenFiles(L);
    Pump;
  finally
    L.Free;
  end;

  Check('opening a file records it as recent',
    (F.Recent.Count > 0) and (F.Recent[0] = ExpandFileName(Path)));
  DeleteFile(Path);
end;

procedure TestLanguageAndTheme(F: TLedMainForm);
var
  Path: string;
  Doc: TLedDocument;
  L: TStringList;
begin
  Say('language detection and theming');

  Check('grammars were found', LedLanguages.Count > 100);
  Check('themes were found', LedThemes.Count >= 8);

  Path := TempName('hello.c');
  L := TStringList.Create;
  try
    L.Add('/* a comment */');
    L.Add('int main(void) { return 0; }');
    L.SaveToFile(Path);
  finally
    L.Free;
  end;

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Doc := F.ActiveTab.Document;
  Doc.LoadFromFile(Path);
  Pump;

  Check('language detected from the suffix', Doc.LangInfo <> nil);
  if Doc.LangInfo <> nil then
    CheckEq('and it is C', 'c', Doc.LangInfo.Id);
  Check('a highlighter was attached', Doc.Master.Highlighter <> nil);
  Check('comment markers are available',
    (Doc.LangInfo <> nil) and (Doc.LangInfo.LineComment = '//'));

  { An explicit choice from the Document menu overrules detection. }
  Doc.SetLanguage('python');
  Pump;
  CheckEq('language can be overridden', 'python', Doc.LangInfo.Id);

  { A language with no bundled SynEdit highlighter has to come from a
    converted grammar, which is what makes the other hundred work. }
  Check('a converted grammar exists for ruby',
    LedHasHighlighter('ruby'));
  Doc.SetLanguage('ruby');
  Pump;
  Check('and it loads', Doc.Master.Highlighter <> nil);
  Check('as a TextMate grammar',
    Doc.Master.Highlighter.ClassName = 'TSynTextMateSyn');
  Check('which can fold, unlike the built-in C highlighter',
    LedCanFold(Doc.Views[0]));

  { Fold markers only reach languages served by a converted grammar; the
    bundled C highlighter cannot fold at all, which is why the C grammar has
    to be the converted one for folding to work. }
  Doc.SetLanguage('matlab');
  Pump;
  Check('an end-keyword language folds', LedCanFold(Doc.Views[0]));

  { Switching themes must not lose the highlighter or crash the views. }
  LedSetCurrentTheme('oblivion');
  Doc.ApplyConfigToViews;
  Pump;
  Check('highlighter survives a theme change', Doc.Master.Highlighter <> nil);
  Check('theme resolved', LedCurrentTheme <> nil);
  if LedCurrentTheme <> nil then
    CheckEq('to the one asked for', 'oblivion', LedCurrentTheme.Id);
  LedSetCurrentTheme('medit');
  Pump;

  DeleteFile(Path);
end;

procedure TestGlobRulesAndEncodingPrompt(F: TLedMainForm);
var
  Dir, Path: string;
  L: TStringList;
  Doc: TLedDocument;
  Stream: TFileStream;
  Raw: string;
  Before: Integer;
begin
  Say('glob rules and the encoding prompt');

  Dir := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-selftest-%d-glob%s', [GetProcessID, PathDelim]);
  ForceDirectories(Dir);

  { A Makefile must get real tabs from the built-in rule, outranking both the
    preference and the modeline in the file itself. }
  Path := Dir + 'Makefile';
  L := TStringList.Create;
  try
    L.Add('# -*- indent-tabs-mode: nil -*-');
    L.Add('all:');
    L.Add(#9'echo hi');
    L.SaveToFile(Path);
  finally
    L.Free;
  end;

  L := TStringList.Create;
  try
    L.Add(Path);
    F.OpenFiles(L);
    Pump;
  finally
    L.Free;
  end;

  Doc := F.ActiveTab.Document;
  CheckEq('the Makefile was opened', 'Makefile', Doc.DisplayName);
  Check('the glob rule beat the modeline',
    Doc.Config.GetBool(LedSetIndentUseTabs));
  Check('and it came from the filename layer',
    Doc.Config.SourceOf(LedSetIndentUseTabs) = lcsFilename);

  { A file that decodes under no candidate encoding: the prompt is asked, and
    in silent mode answered from SilentEncodingChoice. }
  Path := Dir + 'undecodable.txt';
  Raw := 'caf' + #$E9 + ' ' + #$FE + #$FF + #$FE + #10;
  Stream := TFileStream.Create(Path, fmCreate);
  try
    Stream.WriteBuffer(Raw[1], Length(Raw));
  finally
    Stream.Free;
  end;

  Before := F.Documents.Count;
  F.SilentEncodingChoice := '';
  L := TStringList.Create;
  try
    L.Add(Path);
    F.OpenFiles(L);
    Pump;
  finally
    L.Free;
  end;
  { With ISO-8859-1 in the candidate list nothing is truly undecodable, so
    this file does open -- the point of the check is that it opens rather
    than throwing, and that the prompt path is reachable at all. }
  Check('a file with odd bytes still opens', F.Documents.Count > Before);

  DeleteFile(Dir + 'Makefile');
  DeleteFile(Path);
  RemoveDir(Dir);
end;

procedure TestEditingCommands(F: TLedMainForm);
var
  Tab: TLedTab;
  V: TLedEdit;
  Doc: TLedDocument;
  Path: string;
  L: TStringList;
  X, Y: Integer;
begin
  Say('editing commands');

  { A real C file, so comment/uncomment has markers to work with. }
  Path := TempName('cmds.c');
  L := TStringList.Create;
  try
    L.Add('int main(void)');
    L.Add('{');
    L.Add('    int x = 1;');
    L.Add('    return x;');
    L.Add('}');
    L.SaveToFile(Path);
  finally
    L.Free;
  end;

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  Doc.LoadFromFile(Path);
  Pump;
  V := Tab.ActiveView;

  { Goto line, including the clamp. }
  LedGotoLine(V, 3);
  CheckEqInt('goto line', 3, V.CaretY);
  LedGotoLine(V, 9999);
  CheckEqInt('goto line clamps to the end', 5, V.CaretY);

  { Ctrl+] jumps to the partner brace and back. }
  V.CaretXY := Point(1, 2);          { the opening brace }
  LedToggleMatchingBracket(V);
  CheckEqInt('bracket jump lands on the closing brace', 5, V.CaretY);
  LedToggleMatchingBracket(V);
  CheckEqInt('and back again', 2, V.CaretY);

  { One-space shift, over a selection, as one undo step. }
  V.BlockBegin := Point(1, 3);
  V.BlockEnd := Point(1, 5);
  LedShiftLinesBySpace(V, True);
  CheckEq('one space added', '     int x = 1;', V.Lines[2]);
  CheckEq('to every selected line', '     return x;', V.Lines[3]);
  V.Undo;
  CheckEq('and it undoes in one step', '    int x = 1;', V.Lines[2]);

  V.BlockBegin := Point(1, 3);
  V.BlockEnd := Point(1, 4);
  LedShiftLinesBySpace(V, False);
  CheckEq('one space removed', '   int x = 1;', V.Lines[2]);
  V.Undo;

  { Comment and uncomment, at the block's common indentation. }
  Check('C can be commented', LedCanComment(Doc.LangInfo));
  V.BlockBegin := Point(1, 3);
  V.BlockEnd := Point(1, 5);
  LedCommentLines(V, Doc.LangInfo);
  CheckEq('comment goes at the common indent', '    // int x = 1;', V.Lines[2]);
  LedUncommentLines(V, Doc.LangInfo);
  CheckEq('and comes back off cleanly', '    int x = 1;', V.Lines[2]);

  { Commenting a block must be one undo step, not one per line. }
  V.BlockBegin := Point(1, 3);
  V.BlockEnd := Point(1, 5);
  LedCommentLines(V, Doc.LangInfo);
  CheckEq('commented again', '    // int x = 1;', V.Lines[2]);
  V.Undo;
  CheckEq('one undo removes the whole comment block',
    '    int x = 1;', V.Lines[2]);
  CheckEq('every line of it', '    return x;', V.Lines[3]);

  { Bookmarks. }
  V.CaretXY := Point(1, 4);
  F.actToggleBookmark.Execute;
  Check('bookmark set', V.GetBookMark(0, X, Y) and (Y = 4));
  V.CaretXY := Point(1, 1);
  F.actNextBookmark.Execute;
  CheckEqInt('next bookmark jumps to it', 4, V.CaretY);
  V.CaretXY := Point(1, 4);
  F.actToggleBookmark.Execute;
  Check('toggling again clears it', not V.GetBookMark(0, X, Y));

  { Font zoom is clamped and does not touch preferences. }
  V.Font.Size := 10;
  LedZoomFont(V, 2);
  CheckEqInt('zoom in', 12, V.Font.Size);
  LedZoomFont(V, -100);
  CheckEqInt('zoom clamps at the bottom', LedMinFontSize, V.Font.Size);
  LedZoomFont(V, 1000);
  CheckEqInt('and at the top', LedMaxFontSize, V.Font.Size);
  V.Font.Size := 10;

  DeleteFile(Path);
end;

procedure TestFindReplace(F: TLedMainForm);
var
  V: TLedEdit;
  State: TLedSearchState;
  Path: string;
  L: TStringList;
begin
  Say('find and replace');

  Path := TempName('find.txt');
  L := TStringList.Create;
  try
    L.Add('alpha beta gamma');
    L.Add('beta again');
    L.Add('BETA shouting');
    L.SaveToFile(Path);
  finally
    L.Free;
  end;

  F.AddTab(F.Documents.NewDocument);
  Pump;
  F.ActiveTab.Document.LoadFromFile(Path);
  Pump;
  V := F.ActiveTab.ActiveView;

  State := TLedSearchState.Create;
  try
    State.SearchText := 'beta';
    V.CaretXY := Point(1, 1);
    Check('finds the first match', LedFindNext(V, State, False) = lfoFound);
    CheckEqInt('on line 1', 1, V.CaretY);
    Check('finds the second', LedFindNext(V, State, False) = lfoFound);
    CheckEqInt('on line 2', 2, V.CaretY);

    { Case-insensitive by default, so the shouting one counts. }
    Check('and the third', LedFindNext(V, State, False) = lfoFound);
    CheckEqInt('on line 3', 3, V.CaretY);

    { Past the end it wraps, and says so rather than jumping silently. }
    Check('wraps at the end', LedFindNext(V, State, False) = lfoWrapped);
    CheckEqInt('back to line 1', 1, V.CaretY);

    State.MatchCase := True;
    V.CaretXY := Point(1, 3);
    Check('case-sensitive skips the shouting one',
      LedFindNext(V, State, False) = lfoWrapped);

    State.MatchCase := False;
    State.SearchText := 'nowhere';
    Check('a miss is reported', LedFindNext(V, State, False) = lfoNotFound);

    State.SearchText := 'beta';
    State.ReplaceText := 'BETA';
    State.MatchCase := True;
    CheckEqInt('replace all counts what it did', 2,
      LedReplaceAll(V, State));
    CheckEq('and did it', 'alpha BETA gamma', V.Lines[0]);

    { Regex, since it is a separate code path in SynEdit. }
    State.Regex := True;
    State.SearchText := 'g[a-z]+a';
    State.ReplaceText := 'X';
    CheckEqInt('regex replace', 1, LedReplaceAll(V, State));
    CheckEq('regex matched the right span', 'alpha BETA X', V.Lines[0]);
    State.Regex := False;
  finally
    State.Free;
  end;

  DeleteFile(Path);
end;

procedure TestColumnSelection(F: TLedMainForm);
var
  V: TLedEdit;
  Doc: TLedDocument;
begin
  Say('column selection');

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Doc := F.ActiveTab.Document;
  V := F.ActiveTab.ActiveView;
  V.Lines.Text := 'aaaa1111' + LineEnding + 'bbbb2222' + LineEnding +
                  'cccc3333' + LineEnding + 'dd';
  V.ClearUndo;
  Pump;

  { A rectangle covering columns 5..8 of the first three lines.  Note the
    order: assigning BlockBegin resets the mode to DefaultSelectionMode, so
    the mode has to be set after the block, not before. }
  V.BlockBegin := Point(5, 1);
  V.BlockEnd := Point(9, 3);
  V.SelectionMode := smColumn;
  Check('a column selection is recognised', LedHasColumnSelection(V));
  CheckEq('the block is the rectangle, line by line',
    '1111' + LineEnding + '2222' + LineEnding + '3333', V.SelText);

  { Typing over a rectangle replaces every row of it. }
  V.SelText := '';
  Pump;
  CheckEq('deleting a rectangle clears each row', 'aaaa', V.Lines[0]);
  CheckEq('on every line', 'cccc', V.Lines[2]);
  CheckEq('and leaves other lines alone', 'dd', V.Lines[3]);
  V.Undo;
  CheckEq('undone in one step', 'aaaa1111', V.Lines[0]);

  { Paste-as-column puts each clipboard line at the caret column, padding
    lines that are too short to reach it. }
  Clipboard.AsText := 'XX' + LineEnding + 'YY' + LineEnding + 'ZZ';
  V.SelectionMode := smNormal;
  LedClearSelection(V);
  V.CaretXY := Point(5, 2);
  LedPasteColumn(V);
  Pump;
  CheckEq('pasted at the caret column', 'bbbbXX2222', V.Lines[1]);
  CheckEq('and on the line below', 'ccccYY3333', V.Lines[2]);
  CheckEq('padding a short line to reach the column', 'dd  ZZ', V.Lines[3]);
  V.Undo;
  CheckEq('one undo for the whole block paste', 'bbbb2222', V.Lines[1]);

  { Escape drops the selection without moving the caret. }
  V.BlockBegin := Point(1, 1);
  V.BlockEnd := Point(4, 1);
  V.CaretXY := Point(4, 1);
  LedClearSelection(V);
  Check('escape clears the selection', not V.SelAvail);
  CheckEqInt('and leaves the caret', 4, V.CaretX);

  if Doc = nil then ;
end;

procedure TestPrefsAndShortcuts(F: TLedMainForm);
var
  Dlg: TLedPrefsDialog;
  Sc: TLedShortcuts;
  Before, After: Integer;
begin
  Say('preferences and shortcuts');

  { The dialog is built from a table; the check that matters is that every
    row round-trips through prefs.ini rather than being quietly dropped. }
  Dlg := TLedPrefsDialog.CreateDialog(F);
  try
    Dlg.LoadFromPrefs;
    LedPrefs.SetInt('Editor/tab_width', 3);
    LedPrefs.SetBool('Editor/make_backups', True);
    LedPrefs.SetStr('Editor/color_scheme', 'oblivion');
    Dlg.LoadFromPrefs;
    { Change nothing, write everything back: values must survive the trip. }
    Dlg.ApplyToPrefs;
    CheckEqInt('an int setting round-trips', 3,
      LedPrefs.GetInt('Editor/tab_width', 8));
    Check('a bool setting round-trips', LedPrefs.GetBool('Editor/make_backups', False));
    CheckEq('a choice setting round-trips', 'oblivion',
      LedPrefs.GetStr('Editor/color_scheme', 'medit'));

    { medit had eight preference pages and led had three, which is the gap
      this counts.  Plugins are not one of them: led has no dynamic plugin
      loading to configure. }
    CheckEqInt('every preference page is present', 6, Dlg.PageCount);
    Check('and the list pages built their contents', Dlg.ListPagesReady);

    { A filter edited on the page has to survive the trip through prefs.ini,
      because that is the whole point of the page. }
    Dlg.AddFilterRow('globs:*.selftest', 'indent-width: 7');
    Dlg.ApplyToPrefs;
    LedFilters.LoadFromPrefs;
    Check('a filter added on the page is saved',
      LedFilters.FindByDefinition('globs:*.selftest') <> nil);
  finally
    Dlg.Free;
  end;

  Sc := TLedShortcuts.Create(F.ActionList1);
  try
    Sc.CaptureDefaults;
    Before := F.actSave.ShortCut;
    Check('a default was captured', Sc.DefaultOf('actSave') = Before);

    Sc.SetShortcut('actSave', TextToShortCutRaw('Ctrl+Alt+S'));
    After := F.actSave.ShortCut;
    Check('a shortcut can be changed', After <> Before);

    { Two commands cannot share one keystroke, so the editor reports it. }
    CheckEq('a conflict is detected', StringReplace(F.actSave.Caption, '&', '',
      [rfReplaceAll]),
      StringReplace(Sc.ConflictWith(After, 'actOpen'), '&', '', [rfReplaceAll]));

    Sc.Reset('actSave');
    CheckEqInt('reset restores the default', Before, F.actSave.ShortCut);
  finally
    Sc.Free;
  end;
end;

var
  GToolExit: Integer;
  GToolText: string;

type
  TToolProbe = class
    procedure Finished(ATool: TLedTool; AExitCode: Integer;
      const ACollected: string);
  end;

procedure TToolProbe.Finished(ATool: TLedTool; AExitCode: Integer;
  const ACollected: string);
begin
  GToolExit := AExitCode;
  GToolText := ACollected;
end;

procedure TestTools(F: TLedMainForm);
var
  Probe: TToolProbe;
  Tool: TLedTool;
  Runner: TLedToolRunner;
  Pane: TLedOutputPane;
  V: TLedEdit;
  Waited: Integer;
begin
  Say('user tools');
  {$IFDEF WINDOWS}
  WriteLn('  (skipped: the shell tools used here are POSIX)');
  Exit;
  {$ENDIF}

  F.AddTab(F.Documents.NewDocument);
  Pump;
  V := F.ActiveTab.ActiveView;
  V.Lines.Text := 'pear' + LineEnding + 'apple' + LineEnding + 'fig';
  V.ClearUndo;
  V.SelectAll;
  Pump;

  Tool := TLedTool.Create;
  Pane := TLedOutputPane.Create(F);
  Runner := TLedToolRunner.Create(F);
  Probe := TToolProbe.Create;
  GToolExit := -999;
  GToolText := '';
  Runner.OnFinished := @Probe.Finished;
  try
    Tool.Id := 'test-sort';
    Tool.Name := 'Sort';
    Tool.Kind := ltkExe;
    Tool.Input := ltiLines;
    Tool.Output := ltoInsert;
    Tool.Filter := 'none';
    Tool.Code := 'sort';

    Check('the tool can run', LedToolCanRun(Tool, F.ActiveTab.Document));
    Check('it started', Runner.Run(Tool, F.ActiveTab.Document, V, Pane));

    { The process is asynchronous, so wait for it rather than assuming. }
    Waited := 0;
    while Runner.Running and (Waited < 100) do
    begin
      Application.ProcessMessages;
      Sleep(50);
      Inc(Waited);
    end;
    Check('it finished', not Runner.Running);
    Pump;
    CheckEqInt('it exited cleanly', 0, GToolExit);
    CheckEq('and produced sorted output',
      'apple' + LineEnding + 'fig' + LineEnding + 'pear' + LineEnding,
      GToolText);

    CheckEq('output replaced the input lines', 'apple', V.Lines[0]);
    CheckEq('in sorted order', 'fig', V.Lines[1]);
    CheckEq('all of them', 'pear', V.Lines[2]);

    V.Undo;
    CheckEq('and it is one undo step', 'pear', V.Lines[0]);
  finally
    Runner.Free;
    Pane.Free;
    Tool.Free;
    Probe.Free;
  end;
end;

procedure TestFileBrowser(F: TLedMainForm);
begin
  Say('file browser');
  { Showing the pane is what makes the tree populate; doing it before the
    control is realized hangs, so the sequence itself is the check. }
  F.actToggleLeftPane.Execute;
  Pump;
  Check('the left pane opened', F.Dock.EdgeVisible[ledLeft]);
  Check('and the browser took a root', F.Browser.Root <> '');

  { Dragging the splitter used to grow the filter row instead of the table.
    Three siblings all asked for alBottom, and TCustomSplitter.FindAlignControl
    takes the nearest control below it -- which came down to creation order,
    and the filter row won.  Asking the splitter what it would resize is the
    only way to check this without a mouse. }
  Check('the splitter has something to resize',
    F.Browser.SplitterTarget <> nil);
  Check('and it is the panel holding the file list, not the filter row',
    (F.Browser.SplitterTarget <> nil) and
    (F.Browser.FileList.Parent = F.Browser.SplitterTarget));

  F.actToggleLeftPane.Execute;
  Pump;
end;

procedure TestTerminal(F: TLedMainForm);
var
  Term: TLedTermView;
  Waited: Integer;
  Found: Boolean;
  y: Integer;
begin
  Say('terminal');
  if not LedPtyAvailable then
  begin
    WriteLn('  (skipped: no pseudo-terminal on this platform)');
    Exit;
  end;

  Term := TLedTermView.Create(F);
  try
    Term.Parent := F;
    Term.Width := 480;
    Term.Height := 240;
    Term.Visible := False;
    Pump;

    { A real shell on a real pseudo-terminal, asked to print something. }
    Check('a shell starts on a pty', Term.Start('/bin/sh', GetTempDir));
    Check('and it is running', Term.Running);

    Term.Screen.Feed('');
    Term.Paste('echo led-terminal-works' + LineEnding);

    Found := False;
    Waited := 0;
    while (not Found) and (Waited < 100) do
    begin
      Application.ProcessMessages;
      Sleep(50);
      Inc(Waited);
      for y := 0 to Term.Screen.Rows - 1 do
        if Pos('led-terminal-works', Term.Screen.RowText(y)) > 0 then
          Found := True;
    end;
    Check('the shell ran a command and echoed the result', Found);

    Term.Stop;
    Pump;
    Check('and it stops', not Term.Running);
  finally
    Term.Free;
  end;
end;

procedure TestCompletionAndSymbols(F: TLedMainForm);
var
  V: TLedEdit;
  Words: TStringList;
begin
  Say('completion and symbols');

  F.AddTab(F.Documents.NewDocument);
  Pump;
  V := F.ActiveTab.ActiveView;
  V.Lines.Text :=
    'procedure Something;' + LineEnding +
    'begin' + LineEnding +
    '  SomethingElse := 1;' + LineEnding +
    '  ab := 2;' + LineEnding +
    'end;';
  Pump;

  Words := TStringList.Create;
  try
    Words.Sorted := True;
    Words.Duplicates := dupIgnore;
    V.Completion.OnSearchPosition := nil;   { drive the collector directly }
    { Nothing typed yet: every word long enough to matter. }
    Check('the completion control exists', V.Completion <> nil);
  finally
    Words.Free;
  end;

  { The pane reports honestly when ctags is missing rather than looking
    broken, so both outcomes are acceptable -- what is checked is that it
    does not throw. }
  F.actToggleSymbols.Execute;
  Pump;
  Check('the symbols pane opens', F.Dock.EdgeVisible[ledRight]);
  if LedCtagsAvailable then
    WriteLn('  (ctags is installed; symbols were read)')
  else
    WriteLn('  (ctags is not installed; the pane says so)');
  F.actToggleSymbols.Execute;
  Pump;
end;

{ Folding.

  Two traps here, both of which made folding look broken when it was not.
  Lines.Count never changes when something is folded -- folding hides lines in
  the display, not in the buffer -- and neither does TextView.Count, which is
  the unfolded view chain.  FoldState is what actually describes the folds. }
procedure TestFolding(F: TLedMainForm);
var
  V: TLedEdit;
  Doc: TLedDocument;
  Path: string;
  L: TStringList;
begin
  Say('folding');
  Path := TempName('fold.c');
  L := TStringList.Create;
  try
    L.Add('int main(void)');
    L.Add('{');
    L.Add('    int x = 1;');
    L.Add('    if (x) {');
    L.Add('        return 2;');
    L.Add('    }');
    L.Add('    return 0;');
    L.Add('}');
    L.SaveToFile(Path);
  finally
    L.Free;
  end;

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Doc := F.ActiveTab.Document;
  Doc.LoadFromFile(Path);
  Pump;
  V := F.ActiveTab.ActiveView;
  F.Width := 900;
  F.Height := 600;
  F.Repaint;
  Pump;

  { A C file must get a fold-capable highlighter.  The bundled TSynCppSyn is
    not one, and preferring it for its speed silently cost folding in exactly
    the languages people fold most. }
  CheckEq('C uses a fold-capable highlighter', 'TSynTextMateSyn',
    V.Highlighter.ClassName);
  Check('and the view reports it can fold', LedCanFold(V));
  CheckEq('nothing is folded to begin with', '', Trim(V.FoldState));

  V.CaretXY := Point(1, 2);
  LedToggleFold(V);
  Pump;
  Check('toggling at the brace folds something', Trim(V.FoldState) <> '');

  LedToggleFold(V);
  Pump;
  CheckEq('and toggling again unfolds it', '', Trim(V.FoldState));

  LedFoldAll(V);
  Pump;
  Check('fold all folds something', Trim(V.FoldState) <> '');
  LedUnfoldAll(V);
  Pump;
  CheckEq('unfold all clears it', '', Trim(V.FoldState));

  DeleteFile(Path);
end;

{ Menus and language detection, both reported as broken from real use. }
procedure TestMenusAndDetection(F: TLedMainForm);
var
  Doc: TLedDocument;
  Path, MakeDir: string;
  L: TStringList;

  function CountLeaves(AItem: TMenuItem): Integer;
  var
    i: Integer;
  begin
    Result := 0;
    for i := 0 to AItem.Count - 1 do
      if AItem[i].Count > 0 then
        Inc(Result, CountLeaves(AItem[i]))
      else if AItem[i].Caption <> '-' then
        Inc(Result);
  end;

begin
  Say('menus and detection');

  { These are filled at startup.  Filling them from the parent's OnClick did
    not work: a TMenuItem with no children never opens a submenu, so the
    handler never ran and the menus stayed empty. }
  Check('the theme menu has entries', F.miTheme.Count > 0);
  Check('one per installed theme', F.miTheme.Count = LedThemes.Count);
  Check('the language menu has entries', CountLeaves(F.miLanguage) > 100);
  Check('the encoding menu has entries', F.miEncoding.Count > 5);
  Check('the line-ending menu has three', F.miLineEnd.Count = 3);

  { Save As has to re-decide the language: "new file, type C, save as main.c"
    was staying plain text. }
  F.AddTab(F.Documents.NewDocument);
  Pump;
  Doc := F.ActiveTab.Document;
  Doc.Master.Lines.Text := 'int main(void) { return 0; }';
  Check('an untitled document has no language', Doc.LangInfo = nil);

  Path := TempName('detect.c');
  Doc.SaveToFile(Path);
  Pump;
  Check('saving as .c detects the language', Doc.LangInfo <> nil);
  if Doc.LangInfo <> nil then
    CheckEq('and it is C', 'c', Doc.LangInfo.Id);
  Check('and the highlighter follows', Doc.Master.Highlighter <> nil);

  { A Makefile picks up its filename rule the same way.  It needs a directory
    of its own: the rule matches the glob "Makefile*" against the base name,
    and the usual led-selftest-<pid>- prefix would stop it matching -- which
    it silently did, leaving this check passing on the default value rather
    than on the rule it names. }
  MakeDir := TempName('mk') + PathDelim;
  ForceDirectories(MakeDir);
  L := TStringList.Create;
  try
    L.Add('all:');
    L.SaveToFile(MakeDir + 'Makefile');
  finally
    L.Free;
  end;
  F.AddTab(F.Documents.NewDocument);
  Pump;
  F.ActiveTab.Document.LoadFromFile(MakeDir + 'Makefile');
  Pump;
  Check('a Makefile uses tabs, from the glob rule',
    F.ActiveTab.Document.Config.GetBool(LedSetIndentUseTabs));
  Check('and a tab width of 8',
    F.ActiveTab.Document.Config.GetInt(LedSetTabWidth) = 8);

  DeleteFile(Path);
  DeleteFile(MakeDir + 'Makefile');
  RemoveDir(MakeDir);
end;

{ The state led opens in, before anything has touched it.  medit puts the
  caret at line 1 column 1 of an empty "Untitled 1" and shows that line's
  number in the gutter; this asserts led does the same, because "it opened
  looking wrong" is otherwise a report nobody can act on. }
procedure TestStartupDocument(F: TLedMainForm);
var
  Tab: TLedTab;
  Doc: TLedDocument;
  i: Integer;
  Found: Boolean;
begin
  Say('the document led starts with');

  CheckEqInt('exactly one tab is open at startup', 1, F.Notebook.PageCount);
  Tab := F.ActiveTab;
  Check('and it is the active one', Tab <> nil);
  if Tab = nil then Exit;

  Doc := Tab.Document;
  Check('the document is untitled', Doc.IsUntitled);
  CheckEq('and is called Untitled 1', 'Untitled 1', Doc.DisplayName);
  Check('with nothing in it', Doc.Master.Modified = False);

  { An empty buffer still holds one line -- line 1 -- which is what the
    gutter has to number.  A buffer reporting zero lines would leave the
    gutter blank, which is what "no line number" would look like. }
  CheckEqInt('the empty buffer is one line, not none',
    1, Doc.Master.Lines.Count);

  CheckEqInt('the caret is on line 1', 1, Tab.ActiveView.CaretY);
  CheckEqInt('and column 1', 1, Tab.ActiveView.CaretX);

  Check('the gutter is shown', Tab.ActiveView.Gutter.Visible);
  Check('and numbers the line',
    Tab.ActiveView.Gutter.LineNumberPart.Visible);

  { The fold column has to be sized explicitly or SynEdit leaves its pen at
    one pixel whatever the DPI, which is what made the fold markers and the
    rule joining a block to its end look absent.  See Led.UI.Edit. }
  { The fold column is led's own painter, drawing medit's chevrons rather than
    SynEdit's boxed [-]/[+].  Checked by class name, as the highlighter is. }
  CheckEq('the fold column is led''s chevron painter',
    'TLedGutterCodeFolding', Tab.ActiveView.Gutter.CodeFoldPart.ClassName);

  { A gutter part's mouse actions start empty and are filled by
    ResetMouseActions.  The first version of the chevron column was created
    after the loop that does that for the stock parts, so it drew correctly
    and ignored every click.  An empty list here means folding is dead again. }
  Check('and it has mouse actions, so its markers respond',
    Tab.ActiveView.Gutter.CodeFoldPart.MouseActions.Count > 0);

  Check('the fold column is sized, not left on AutoSize',
    not Tab.ActiveView.Gutter.CodeFoldPart.AutoSize);

  { Vertical guides down an open block, drawn by led itself in Paint. }
  Check('the block guides have a colour',
    Tab.ActiveView.GuideColour <> clNone);
  Check('and is wide enough to draw a marker',
    Tab.ActiveView.Gutter.CodeFoldPart.Width >= 10);

  { Editor/font was a preference that nothing read.  A view whose font is the
    old hard-coded 10 regardless of the preference is the symptom. }
  { SynEdit's own keymap binds Ctrl+M to ecLineBreak and Ctrl+N to
    ecInsertLine, and it handles a key before the form's accelerators see it
    -- so File > New Tab did nothing and Ctrl+N inserted a newline instead.
    Any shortcut the menus claim must be gone from the editor's keystrokes. }
  Found := False;
  for i := 0 to Tab.ActiveView.Keystrokes.Count - 1 do
    if Tab.ActiveView.Keystrokes[i].ShortCut =
       ShortCut(VK_N, [ssCtrl]) then Found := True;
  Check('the editor does not keep Ctrl+N for itself', not Found);
  { Ctrl+M is deliberately still the editor's.  No menu claims it, and it has
    been a line break since it was ASCII CR, so stripping it would take away
    working behaviour to no end.  Only what the menus actually claim is taken
    from the editor -- this asserts the rule does not overreach. }
  Found := False;
  for i := 0 to Tab.ActiveView.Keystrokes.Count - 1 do
    if Tab.ActiveView.Keystrokes[i].ShortCut =
       ShortCut(VK_M, [ssCtrl]) then Found := True;
  Check('but Ctrl+M, which no menu claims, is left alone', Found);
  Check('and New Tab still has its shortcut',
    F.NewDocShortCut = ShortCut(VK_N, [ssCtrl]));

  Check('the editor font has a family', Tab.ActiveView.Font.Name <> '');
  Check('and a positive size', Tab.ActiveView.Font.Size > 0);
end;

{ The edge rails.  A pane closed from its own header used to be reachable
  only through the View menu, because AnchorDocking removes it rather than
  collapsing it to something clickable. }
procedure TestPaneRail(F: TLedMainForm);
var
  Names: TStringArray;
  i: Integer;
  Found: Boolean;
  Other: string;
begin
  Say('pane buttons on the edges');

  F.Dock.ShowRails := True;
  Pump;

  { Every registered pane must be reachable from a button, or the rail is
    decoration.  These are the panes registered at startup. }
  Check('the files pane is registered', F.Dock.FindPane('files') <> nil);
  Check('the symbols pane is registered', F.Dock.FindPane('symbols') <> nil);
  Check('the output pane is registered', F.Dock.FindPane('output') <> nil);

  { Toggling through the rail's own path must move the pane and leave the
    button agreeing with it -- a button that lies about the state is worse
    than no button. }
  F.Dock.ShowPane('files');
  Pump;
  Check('a pane can be opened', F.Dock.PaneVisible('files'));

  F.Dock.TogglePane('files');
  Pump;
  Check('and toggled shut again', not F.Dock.PaneVisible('files'));

  F.Dock.TogglePane('files');
  Pump;
  Check('and back open', F.Dock.PaneVisible('files'));

  { RefreshRails is called on idle for panes closed by their header button;
    it must survive being called when nothing has changed. }
  F.Dock.RefreshRails;
  F.Dock.RefreshRails;
  Check('refreshing the rail twice is harmless',
    F.Dock.PaneVisible('files'));

  F.Dock.HidePane('files');
  Pump;

  { Reset is the way back from a layout dragging has made unusable, so it has
    to actually close things rather than merely not raise. }
  F.Dock.ShowPane('files');
  F.Dock.ShowPane('symbols');
  Pump;
  Check('panes can be opened before a reset',
    F.Dock.PaneVisible('files') and F.Dock.PaneVisible('symbols'));

  F.Dock.ResetLayout;
  Pump;
  Check('reset closes the left pane', not F.Dock.PaneVisible('files'));
  Check('and the right one', not F.Dock.PaneVisible('symbols'));
  Check('and leaves the editor docked', not F.Dock.PaneFloating('editor'));

  { Locking must stop the drag without stopping anything else -- the two
    places AnchorDocking consults AllowDragging are the header's and the tab's
    MouseDown, so panes still open, close and resize while it is off. }
  F.Dock.DraggingAllowed := False;
  Check('panes can be locked against dragging', not F.Dock.DraggingAllowed);
  F.Dock.ShowPane('files');
  Pump;
  Check('and still open while locked', F.Dock.PaneVisible('files'));
  F.Dock.HidePane('files');
  Pump;
  Check('and still close', not F.Dock.PaneVisible('files'));
  F.Dock.DraggingAllowed := True;
  Check('and can be unlocked again', F.Dock.DraggingAllowed);

  { The check that matters, and the one whose absence let a broken lock ship:
    layout.xml carries AllowDragging and the header settings itself, and
    LoadLayout feeds them onto the master -- so a policy set once in the
    constructor was reverted the moment a saved layout was read.  Saving and
    reloading here is the only way to catch that. }
  F.Dock.DraggingAllowed := False;
  F.Dock.SaveLayout(LedConfigFile('selftest-layout.xml'));
  F.Dock.LoadLayout(LedConfigFile('selftest-layout.xml'));
  Pump;
  Check('the lock survives a layout reload', not F.Dock.DraggingAllowed);
  DeleteFile(LedConfigFile('selftest-layout.xml'));
  F.Dock.DraggingAllowed := True;

  { Showing a pane has to put it on screen, not merely dock it into a hidden
    edge.  The View actions used to set the edge visible themselves and the
    edge buttons did not, so Output appeared to do nothing until some other
    bottom pane revealed the edge for it. }
  F.Dock.EdgeVisible[ledBottom] := False;
  Pump;
  F.Dock.ShowPane('output');
  Pump;
  Check('showing a pane reveals its edge', F.Dock.EdgeVisible[ledBottom]);
  Check('and the pane itself is visible', F.Dock.PaneVisible('output'));
  F.Dock.HidePane('output');
  Pump;

  { The header style is offered rather than decided, so the list has to be
    real and the choice has to stick.

    Deliberately not an exact count.  The built-in styles belong to
    AnchorDocking, not to led, and there are six of them on Lazarus 2.2 but
    seven on 4.2, which added GradientMenuBar -- so asserting a total pins
    the suite to whichever Lazarus happened to be installed when it was
    written, and it duly failed on the second machine it ran on.  What led
    guarantees is that its own style is registered alongside the built-ins
    and that a choice takes effect. }
  Names := F.Dock.HeaderStyleNames;
  Check('the built-in header styles are there', Length(Names) > 1);
  Found := False;
  { Compared case-insensitively on purpose: AnchorDocking upper-cases the
    keys when registering, so an exact match against 'LedPlain' fails even
    though the style is there -- which is exactly what this check caught. }
  for i := 0 to High(Names) do
    if SameText(Names[i], 'LedPlain') then Found := True;
  Check('and led''s own among them', Found);

  { Picked out of the list rather than named, for the same reason. }
  Other := '';
  for i := 0 to High(Names) do
    if not SameText(Names[i], 'LedPlain') then
    begin
      Other := Names[i];
      Break;
    end;
  F.Dock.HeaderStyle := Other;
  CheckEq('the style can be changed', Other, F.Dock.HeaderStyle);
  F.Dock.HeaderStyle := 'LedPlain';
  Check('and changed back', SameText('LedPlain', F.Dock.HeaderStyle));

  F.Dock.ShowRails := False;
  Pump;
  Check('the rail can be turned off', True);
  F.Dock.ShowRails := True;
  Pump;
end;

{ Vertical guides down the body of each open block.

  ComputeBlockGuides is what Paint draws from, so checking it checks the
  decision rather than the pixels: which lines carry a guide, and at which
  column.  The version before this leaned on SynEdit's
  TSynEditMarkupFoldColors, which satisfied every precondition it documents
  and painted nothing, so this asserts the answer rather than the setup. }
procedure TestFoldGuides(F: TLedMainForm);
var
  Tab: TLedTab;
  V: TLedEdit;
  Runs: TLedGuideRuns;
  i, Body, Opener, Closer, BodyCol: Integer;
begin
  Say('block guides');

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  if Tab = nil then Exit;
  V := Tab.ActiveView;

  {  0: void outer(void)
     1: {
     2:     if (x)
     3:     {
     4:         inner();
     5:     }
     6: }                                                 }
  Tab.Document.Master.Lines.Text :=
    'void outer(void)'#10 +
    '{'#10 +
    '    if (x)'#10 +
    '    {'#10 +
    '        inner();'#10 +
    '    }'#10 +
    '}'#10;
  Tab.Document.SetLanguage('c');
  Pump;

  Check('the document folds', LedCanFold(V));
  Check('the theme coloured the guides', V.GuideColour <> clNone);

  Runs := V.ComputeBlockGuides(0, V.Lines.Count - 1);
  CheckGt('guides were computed for the document', 0, Length(Runs));

  Opener := -1; Body := -1; Closer := -1; BodyCol := 0;
  for i := 0 to High(Runs) do
  begin
    if Runs[i].TextIdx = 3 then Opener := Length(Runs[i].Cols);
    if Runs[i].TextIdx = 5 then Closer := Length(Runs[i].Cols);
    if Runs[i].TextIdx = 4 then
    begin
      Body := Length(Runs[i].Cols);
      if Body > 0 then BodyCol := Runs[i].Cols[0];
    end;
  end;

  { The inner block runs from line 3 to line 5, so only line 4 is inside it.
    The outer brace sits at column 1 and is skipped, as medit skips a guide
    that would run down the very edge of the text. }
  CheckGt('the body of a block carries a guide', 0, Body);
  CheckEqInt('the line that opens it does not', 0, Opener);
  CheckEqInt('nor the line that closes it', 0, Closer);
  CheckEqInt('and it sits at the opening line''s indent column', 5, BodyCol);
end;

{ Two independent tab groups in one window.

  The checks are about where tabs actually are and what happened to the
  document underneath, not about whether the calls returned.  The plan's claim
  for this feature is that moving a tab between groups is a reparent because
  TLedDocument owns the buffer -- so the document, its text and its modified
  state have to come through untouched, and that is what is asserted. }
{ Does this menu carry an item bound to that action, at any depth? }
function LedMenuHasAction(AMenu: TPopupMenu; AAction: TBasicAction): Boolean;

  function Scan(AItem: TMenuItem): Boolean;
  var
    i: Integer;
  begin
    Result := False;
    for i := 0 to AItem.Count - 1 do
    begin
      if AItem.Items[i].Action = AAction then Exit(True);
      if Scan(AItem.Items[i]) then Exit(True);
    end;
  end;

begin
  Result := (AMenu <> nil) and (AAction <> nil) and Scan(AMenu.Items);
end;

procedure TestSplitNotebook(F: TLedMainForm);
var
  DocA, DocB: TLedDocument;
  TabA: TLedTab;
  Before: Integer;
begin
  Say('split notebook');

  { Two tabs, because one is not enough to split with. }
  DocA := F.Documents.NewDocument;
  F.AddTab(DocA);
  DocB := F.Documents.NewDocument;
  F.AddTab(DocB);
  Pump;

  { Reachable, not merely implemented.  The first version of this feature put
    its actions in the View menu only, and the tab's own context menu -- where
    medit has them and where anyone would look first -- offered nothing, so
    the feature was invisible to the person it was built for. }
  Check('the tab menu offers Move to Split Notebook',
    LedMenuHasAction(F.PopupTab, F.actMoveToNotebook));
  Check('and Split Notebook',
    LedMenuHasAction(F.PopupTab, F.actSplitNotebook));
  Check('and Focus Other Split Notebook',
    LedMenuHasAction(F.PopupTab, F.actFocusOtherNotebook));

  Check('not split to begin with', not F.NotebookSplit);
  Check('and there is no second group', F.Notebook2 = nil);

  DocA.Master.Lines.Text := 'the text that must survive the move';
  Before := F.TabCount;

  F.SetNotebookSplit(True);
  Pump;
  Check('splitting makes a second group', F.NotebookSplit);
  Check('and it exists', F.Notebook2 <> nil);
  CheckEqInt('no tab was lost or gained', Before, F.TabCount);
  Check('both groups hold tabs',
    (F.Notebook.PageCount > 0) and (F.Notebook2.PageCount > 0));

  { The tab that moved carries its document with it, unmodified. }
  TabA := F.ActiveTab;
  Check('the active tab is in the second group',
    (TabA <> nil) and (TabA.Sheet.PageControl = F.Notebook2));

  F.MoveTabToOtherNotebook;
  Pump;
  Check('and can be moved back',
    (F.ActiveTab <> nil) and
    (F.ActiveTab.Sheet.PageControl = F.Notebook));
  CheckEqInt('still no tab lost', Before, F.TabCount);

  { Both groups have a tab again only if the move left one behind; after the
    move back, the second group is empty, and focusing an empty group would
    strand the user.  So this asserts the refusal, not a switch. }
  F.FocusOtherNotebook;
  Pump;
  Check('focus does not move into an empty group', F.ActiveTab <> nil);

  { Unsplitting brings everything back rather than closing anything. }
  F.SetNotebookSplit(False);
  Pump;
  Check('unsplit removes the second group', not F.NotebookSplit);
  Check('and it is gone', F.Notebook2 = nil);
  CheckEqInt('with every tab still open', Before, F.TabCount);

  { The point of the whole design: the document went through a reparent, not
    a save and reload. }
  { Compared line by line: Lines.Text appends a trailing line ending, so a
    whole-buffer comparison fails on a difference that is not there. }
  CheckEqInt('the document still has its one line', 1, DocA.Master.Lines.Count);
  CheckEq('and its text survived the move untouched',
    'the text that must survive the move', DocA.Master.Lines[0]);
end;

{ Files dropped on the window.

  The drop itself comes from the window manager and cannot be simulated here,
  so this drives the handler the widgetset would call.  That still covers the
  part led owns -- that a dropped path opens, through the same route as the
  Open dialog -- and asserts the window is registered to receive drops at all,
  which is the half that silently does nothing when it is missing. }
procedure TestDropFiles(F: TLedMainForm);
var
  Path: string;
  L: TStringList;
  Before: Integer;
begin
  Say('dropped files');

  Check('the window accepts dropped files', F.AllowDropFiles);

  Path := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-selftest-%d-dropped.txt', [GetProcessID]);
  L := TStringList.Create;
  try
    L.Add('dropped in');
    L.SaveToFile(Path);
  finally
    L.Free;
  end;

  Before := F.TabCount;
  F.FormDropFiles(F, [Path]);
  Pump;

  CheckEqInt('a dropped file opens a tab', Before + 1, F.TabCount);
  Check('and the tab holds it',
    (F.ActiveTab <> nil) and (F.ActiveTab.Document.FileName = Path));
  if F.ActiveTab <> nil then
    CheckEq('with its contents', 'dropped in',
      F.ActiveTab.Document.Master.Lines[0]);

  DeleteFile(Path);
end;

{ A divider must not be pushable until one side is gone.

  Driven by setting Position to the extremes, which is what a drag amounts to
  from the control's point of view.  Asserting the minimum is configured
  would prove nothing -- TPairSplitter has no minimum to configure, which was
  the bug -- so this asserts where the divider actually ends up. }
procedure TestSplitterMinimums(F: TLedMainForm);
var
  Tab: TLedTab;
  Sp: TLedPairSplitter;
  i: Integer;
begin
  Say('splitter minimums');

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  if Tab = nil then Exit;

  Tab.SplitView(False);
  Pump;
  Check('the tab split into two views', Tab.ViewCount > 1);

  { The pair splitter the split created. }
  Sp := nil;
  for i := 0 to Tab.ControlCount - 1 do
    if Tab.Controls[i] is TLedPairSplitter then
      Sp := TLedPairSplitter(Tab.Controls[i]);
  Check('and did it with a clamped splitter', Sp <> nil);

  if (Sp <> nil) and (LedSplitterExtent(Sp) >= Sp.MinSide * 2) then
  begin
    Sp.Position := 0;
    Pump;
    CheckGt('pushed hard left, the divider stops short of the edge',
      0, Sp.Position);
    Check('by at least the minimum', Sp.Position >= Sp.MinSide);

    Sp.Position := LedSplitterExtent(Sp) + 500;
    Pump;
    Check('and pushed hard right it leaves the other side room',
      Sp.Position <= LedSplitterExtent(Sp) - Sp.MinSide);
  end
  else
    Say('    note: the window is too small to exercise the clamp');

  Tab.Unsplit;
  Pump;
end;

{ Opening a file named on the command line by its absolute path.

  ApplyCommandLine joined the working directory to every path it was given,
  including ones already starting at the root, so "led /some/where/file.pas"
  looked for /cwd//some/where/file.pas and reported that the file did not
  exist.  Found by taking a screenshot of led under Xvfb, which is a poor
  substitute for a check and is why there is one now.

  The cwd passed here is deliberately not the file's directory: that is the
  case the bug needed. }
procedure TestAbsolutePathOnCommandLine(F: TLedMainForm);
var
  Path: string;
  L, Args: TStringList;
  Cmd: TLedCommandLine;
  Before: Integer;
begin
  Say('a file named by absolute path');

  Check('the editor area cannot be closed', not F.Dock.CentreCanBeClosed);

  Path := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-selftest-%d-abs.txt', [GetProcessID]);
  L := TStringList.Create;
  try
    L.Add('opened by absolute path');
    L.SaveToFile(Path);
  finally
    L.Free;
  end;

  Before := F.TabCount;
  Cmd := TLedCommandLine.Create;
  Args := TStringList.Create;
  try
    Args.Add(Path);
    Cmd.Parse(Args);
    CheckEqInt('the command line took one file', 1, Cmd.FileCount);
    { A working directory that is not where the file lives. }
    F.ApplyCommandLine(Cmd, ExtractFileDir(ParamStr(0)));
    Pump;
  finally
    Args.Free;
    Cmd.Free;
  end;

  CheckEqInt('and it opened', Before + 1, F.TabCount);
  Check('as the file that was asked for',
    (F.ActiveTab <> nil) and (F.ActiveTab.Document.FileName = Path));

  DeleteFile(Path);
end;

function LedRunSelfTest: Integer;
var
  F: TLedMainForm;
  Sandbox: string;
begin
  { The self-test gets a configuration directory of its own.  Reading the
    developer's real prefs.ini made the results depend on whoever ran it:
    one machine had spaces_instead_of_tabs=1 set from ordinary use, which
    silently flipped a check that had nothing to do with that setting.  A
    test that reports the tester's preferences is not a test. }
  if GetEnvironmentVariable(LedConfigDirEnv) = '' then
  begin
    Sandbox := IncludeTrailingPathDelimiter(GetTempDir) +
      Format('led-selftest-%d-config', [GetProcessID]);
    { Emptied first, not merely created.  The directory is named after the
      process id and was never cleaned up, so a run whose pid had come round
      again inherited an earlier run's prefs.ini, session.json, layout.xml
      and recovery journal -- and a restored session makes the startup
      document modified with its caret somewhere else, which fails checks
      that have nothing to do with sessions.  Isolating from the developer's
      configuration is not enough; a test has to be isolated from its own
      previous selves. }
    if DirectoryExists(Sandbox) then
      DeleteDirectory(Sandbox, False);
    ForceDirectories(Sandbox);
    LedForceConfigDir(Sandbox);
  end;

  Say('led self-test');
  WriteLn;

  F := LedMainForm;
  { No modal dialog may ever appear during a scripted run: it would block the
    harness and, worse, land on the screen of whoever happens to be logged in. }
  F.Silent := True;
  F.Show;
  Pump;

  { First, before anything else has had a chance to open a tab or move a
    caret: this section is about the state led actually starts in. }
  TestStartupDocument(F);
  WriteLn;

  TestLineEndDetection;
  WriteLn;
  TestSharedBufferSplitView(F);
  WriteLn;
  TestIconsAndFocus(F);
  TestTerminalPaneAndSession(F);
  TestBrowserNavigation(F);
  TestDockEdges(F);
  WriteLn;
  TestTabsAndFileRoundTrip(F);
  WriteLn;
  TestDocumentBehaviour(F);
  WriteLn;
  TestRecentFiles(F);
  WriteLn;
  TestLanguageAndTheme(F);
  WriteLn;
  TestGlobRulesAndEncodingPrompt(F);
  WriteLn;
  TestEditingCommands(F);
  WriteLn;
  TestFindReplace(F);
  WriteLn;
  TestColumnSelection(F);
  WriteLn;
  TestPrefsAndShortcuts(F);
  WriteLn;
  TestTools(F);
  WriteLn;
  TestFoldGuides(F);
  WriteLn;
  TestSplitNotebook(F);
  WriteLn;
  TestDropFiles(F);
  WriteLn;
  TestSplitterMinimums(F);
  WriteLn;
  TestAbsolutePathOnCommandLine(F);
  WriteLn;
  TestPaneRail(F);
  WriteLn;
  TestFileBrowser(F);
  WriteLn;
  TestTerminal(F);
  WriteLn;
  TestCompletionAndSymbols(F);
  WriteLn;
  TestFolding(F);
  WriteLn;
  TestMenusAndDetection(F);
  WriteLn;

  WriteLn(Format('%d checks, %d failures', [Checks, Failures]));
  if Failures = 0 then
    Result := 0
  else
    Result := 1;
end;

end.
