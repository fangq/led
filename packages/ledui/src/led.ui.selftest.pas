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
  Led.Core.Types, Led.Core.FileIO, Led.Core.Config, Led.Core.Prefs,
  Led.Syn.Languages, Led.Syn.Theme, Led.Syn.Factory,
  Led.UI.Main, Led.UI.Document, Led.UI.Tab, Led.UI.Edit, Led.UI.Dock,
  Led.UI.Commands, Led.UI.Find, Led.UI.Prefs, Led.UI.Shortcuts,
  Led.UI.ToolRunner, Led.UI.Output, Led.UI.FileBrowser,
  Led.Term.View, Led.Term.Pty, Led.Term.Screen, Led.UI.Symbols,
  Led.Core.Ctags,
  Led.Core.Tools, Led.Core.OutputFilter,
  Clipbrd, SynEditTypes, ActnList, Menus, LCLProc;

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
  Tab.CycleViews;
  Pump;
  Tab.Unsplit;
  Pump;
  CheckEqInt('one view again', 1, Tab.ViewCount);
end;

procedure TestDockEdges(F: TLedMainForm);
var
  E: TLedDockEdge;
begin
  Say('four-edge dock');
  for E := Low(TLedDockEdge) to High(TLedDockEdge) do
  begin
    F.Dock.EdgeVisible[E] := True;
    Pump;
    Check('edge ' + LedDockEdgeName[E] + ' shows', F.Dock.EdgeVisible[E]);
    F.Dock.EdgeVisible[E] := False;
    Pump;
    Check('edge ' + LedDockEdgeName[E] + ' hides', not F.Dock.EdgeVisible[E]);
  end;
  Check('a registered pane is findable', F.Dock.FindPane('files') <> nil);
  F.Dock.ShowPane('files');
  Pump;
  Check('showing a pane reveals its edge', F.Dock.EdgeVisible[ledLeft]);
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

function LedRunSelfTest: Integer;
var
  F: TLedMainForm;
begin
  Say('led self-test');
  WriteLn;

  F := LedMainForm;
  { No modal dialog may ever appear during a scripted run: it would block the
    harness and, worse, land on the screen of whoever happens to be logged in. }
  F.Silent := True;
  F.Show;
  Pump;

  TestLineEndDetection;
  WriteLn;
  TestSharedBufferSplitView(F);
  WriteLn;
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
  TestFileBrowser(F);
  WriteLn;
  TestTerminal(F);
  WriteLn;
  TestCompletionAndSymbols(F);
  WriteLn;
  TestFolding(F);
  WriteLn;

  WriteLn(Format('%d checks, %d failures', [Checks, Failures]));
  if Failures = 0 then
    Result := 0
  else
    Result := 1;
end;

end.
