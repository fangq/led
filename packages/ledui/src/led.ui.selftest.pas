{ LED - a lightweight editor.  Scripted GUI self-test.

  Run with `led --self-test`.  Drives the real main window through a sequence
  of actions, checking the state the user would see, and exits non-zero on the
  first failure.  This is what catches the integration bugs -- action
  enabling, tab lifecycle, split teardown -- that headless unit tests over
  ledcore structurally cannot.

  It needs a display; in CI it runs under xvfb-run. }
unit Led.UI.SelfTest;

{$mode objfpc}{$H+}

interface

{ Points the whole process at a private, empty configuration directory.
  Must be called before anything reads a preference, which in practice means
  before the main form is constructed. }
procedure LedPrepareSelfTestSandbox;

function LedRunSelfTest: Integer;

implementation

uses
  Classes, SysUtils, DateUtils, Math, Forms, ComCtrls,
  FileUtil,
  LCLType, SynEditMiscClasses, SynEditMarkup, SynEditHighlighter,
  SynEditHighlighterFoldBase,
  ShellCtrls, Dialogs, Led.Core.Hex, Led.Core.BJDView, Led.Core.BJDEdit,
  Led.Core.NBFormat, Led.Core.NBView, fpjson, Led.Syn.Notebook, Led.Core.Kernel,
  Led.UI.NBPane, Led.UI.PageStyle, Led.Core.Markdown, IpHtml, IpHtmlProp,
  Led.UI.BJEdit,
  Led.Core.Types, Led.Core.CLI, Led.Core.FileIO, Led.Core.Config, Led.Core.Prefs,
  Led.Core.Paths,
  Led.Syn.Languages, Led.Syn.Theme, Led.Syn.Factory,
  Buttons,
  Led.Core.AppFont,
  Led.UI.Main, Led.UI.Document, Led.UI.Tab, Led.UI.Edit, Led.UI.Dock,
  Led.UI.Splitter, Led.UI.Dpi,
  Led.UI.Commands, Led.UI.Find, Led.UI.Prefs, Led.UI.Shortcuts,
  Led.UI.Icons, Led.UI.Focus, Led.UI.Preview, Led.Core.Wiki,
  Led.UI.Debug, Led.Core.Gdb, Led.Core.Project, Led.UI.XError, process,
  Led.UI.HexMarkup, Led.UI.MiniMap, Led.Syn.BJData, AnchorDocking, LazFileUtils,
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  SynEditMarkupHighAll,
  {$IF DEFINED(UNIX) and not DEFINED(DARWIN) and DEFINED(LCLGtk2)}
  ctypes, x, xlib,
  {$ENDIF}
  Graphics, IntfGraphics, FPimage, StdCtrls, ExtCtrls,
  Led.UI.ToolRunner, Led.UI.Output, Led.UI.FileBrowser,
  Led.Term.View, Led.Term.Pty, Led.Term.Screen, Led.Term.Pane,
  Led.Core.Session, Led.UI.Bookmarks, Led.Core.Spell, Led.UI.SpellMarkup,
  Led.UI.Symbols,
  Led.Core.Ctags,
  Led.Core.Tools, Led.Core.OutputFilter, Led.Core.Filters,
  Clipbrd, SynEditTypes, SynEditKeyCmds, SynEditMouseCmds, ActnList, Menus,
  Controls,
  PairSplitter, LCLProc;

type
  { The gtk widget behind each menu item, watched for being replaced. }
  TLedHandleArray = array of THandle;

  { The view chain is protected on TSynEdit. }
  TLedViewPeek = class(TLedEdit);

var
  Failures: Integer = 0;
  Checks: Integer = 0;
  { The configuration directory the run is meant to be using.  Empty means
    LedPrepareSelfTestSandbox never ran, which is itself the failure. }
  FSandboxDir: string = '';

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

{ Every menu item in the window that has a gtk widget, and the widget it has.

  A handle is what is destroyed when the LCL rebuilds an item, so it is what
  has to be watched.  Items with no handle yet -- a submenu nobody has opened
  -- are skipped: they have nothing to lose. }
procedure CollectMenuHandles(F: TLedMainForm; out AItems: TFPList;
  out AHandles: TLedHandleArray);

  procedure Walk(AItem: TMenuItem);
  var
    i: Integer;
  begin
    if AItem = nil then Exit;
    if AItem.HandleAllocated then
    begin
      AItems.Add(AItem);
      SetLength(AHandles, AItems.Count);
      AHandles[AItems.Count - 1] := AItem.Handle;
    end;
    for i := 0 to AItem.Count - 1 do
      Walk(AItem.Items[i]);
  end;

var
  i: Integer;
begin
  AItems := TFPList.Create;
  SetLength(AHandles, 0);
  for i := 0 to F.ComponentCount - 1 do
    if F.Components[i] is TMenu then
      Walk(TMenu(F.Components[i]).Items);
end;

{ How many of them have been given a different widget since. }
function ChangedHandles(AItems: TFPList;
  const AHandles: TLedHandleArray): Integer;
var
  i: Integer;
  Item: TMenuItem;
begin
  Result := 0;
  for i := 0 to AItems.Count - 1 do
  begin
    Item := TMenuItem(AItems[i]);
    if not Item.HandleAllocated then
      Inc(Result)
    else if Item.Handle <> AHandles[i] then
      Inc(Result);
  end;
end;

{ How many of a menu's entries the user can actually see. }
function VisibleItems(AParent: TMenuItem): Integer;
var
  i: Integer;
begin
  Result := 0;
  if AParent = nil then Exit;
  for i := 0 to AParent.Count - 1 do
    if AParent.Items[i].Visible then Inc(Result);
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

procedure TestSpelling(F: TLedMainForm);
var
  V: TLedEdit;
  Start, Len: Integer;
  W: string;
  Before: Integer;
  Bound: TLazSynDisplayTokenBound;
  Rtl: TLazSynDisplayRtlInfo;
  Attr: TSynSelectedColor;
  L: TStringList;
  i, Ms: Integer;
  T0: TDateTime;
begin
  Say('spelling');

  Check('the shipped dictionary loaded', LedSpell.Loaded);
  Check('with a plausible number of words', LedSpell.WordCount > 50000);

  { The word finder is shared between the squiggle and the context menu, so
    that what gets offered corrections is exactly what was underlined. }
  W := LedWordAt('the recieve word', 6, Start, Len);
  CheckEq('the word under a column is found', 'recieve', W);
  CheckEqInt('at the right place', 5, Start);
  CheckEqInt('with the right length', 7, Len);

  W := LedWordAt('call foo_bar(x)', 7, Start, Len);
  CheckEq('an identifier stops at the underscore', 'foo', W);

  W := LedWordAt('it''s here', 2, Start, Len);
  CheckEq('a contraction is one word', 'it''s', W);

  W := LedWordAt(#39 + 'quoted' + #39, 3, Start, Len);
  CheckEq('but surrounding quotes are not part of it', 'quoted', W);

  Before := F.Notebook.PageCount;
  F.AddTab(F.Documents.NewDocument);
  Pump;
  V := F.ActiveView;
  V.Lines.Text := 'I recieve the notice';
  V.CaretXY := Point(3, 1);

  { Off by default, so nothing is underlined until asked. }
  LedPrefs.SetBool('Editor/spell_enabled', False);
  F.ActiveTab.Document.ApplyConfigToViews;
  Pump;
  F.PopupEditorPopup(nil);
  Check('the spelling menu is hidden while the feature is off',
    not F.miSpelling.Visible);

  LedPrefs.SetBool('Editor/spell_enabled', True);
  LedPrefs.SetStr('Editor/spell_scope', 'all');
  F.ActiveTab.Document.ApplyConfigToViews;
  Pump;
  V.CaretXY := Point(4, 1);      { inside "recieve" }
  F.PopupEditorPopup(nil);
  Check('and shown when it is on', F.miSpelling.Visible);
  Check('naming the misspelled word',
    Pos('recieve', F.miSpelling.Caption) > 0);
  Check('with suggestions under it', F.miSpelling.Count > 0);
  Check('the first of which is the correction',
    F.miSpelling.Items[0].Caption = 'receive');

  { The markup itself, not just the menu.  SynEdit markups are the part of
    this that can be wired up correctly and still paint nothing -- the fold
    colours did exactly that -- so the contract is asserted directly: the
    editor asks GetMarkupAttributeAtRowCol for each token, and the answer has
    to be the wavy underline inside the misspelling and nil outside it. }
  Bound := Default(TLazSynDisplayTokenBound);
  Rtl := Default(TLazSynDisplayRtlInfo);

  { PrepareMarkupForRow first, because that is the order SynEdit uses: it
    prepares a row, then asks about each token on it.  Querying without
    preparing is not a case the editor produces, and the markup answers
    nothing for it rather than scanning behind the caller's back. }
  V.SpellMarkup.PrepareMarkupForRow(1);

  Bound.Logical := 3;          { inside "recieve", which spans 3..9 }
  Attr := V.SpellMarkup.GetMarkupAttributeAtRowCol(1, Bound, Rtl);
  Check('the markup claims a column inside the misspelling', Attr <> nil);
  if Attr <> nil then
  begin
    Check('and asks for a wavy underline', Attr.FrameStyle = slsWaved);
    Check('along the bottom edge', Attr.FrameEdges = sfeBottom);
    Check('in red', Attr.FrameColor = clRed);
  end;

  Bound.Logical := 1;          { "I", which is correct }
  Attr := V.SpellMarkup.GetMarkupAttributeAtRowCol(1, Bound, Rtl);
  Check('and claims nothing on a correctly spelled word', Attr = nil);

  Bound.Logical := 12;         { "the" }
  Attr := V.SpellMarkup.GetMarkupAttributeAtRowCol(1, Bound, Rtl);
  Check('nor on a short common one', Attr = nil);

  { --- the bug this was reported for -------------------------------------

    Typing a misspelling one character at a time.  The old markup cached its
    scan against the row number and rescanned only when that changed, so
    typing on one line -- which repaints only that line -- reused the scan
    from the first keystroke.  The first assertion below passed and every
    later one failed.  Scanning happens per paint now, so each keystroke is
    seen. }
  V.Lines.Text := 'ready ';
  V.CaretXY := Point(7, 1);
  Pump;
  CheckEqInt('nothing wrong before typing', 0, V.SpellMarkup.MarksOnRow(1));

  V.CommandProcessor(ecChar, 'z', nil);
  V.CommandProcessor(ecChar, 'q', nil);
  Pump;
  CheckEqInt('two letters is too short to judge', 0,
    V.SpellMarkup.MarksOnRow(1));

  V.CommandProcessor(ecChar, 'x', nil);
  Pump;
  CheckEqInt('a third letter makes it a word, and a wrong one', 1,
    V.SpellMarkup.MarksOnRow(1));

  V.CommandProcessor(ecChar, 'j', nil);
  Pump;
  CheckEqInt('and it stays flagged as more is typed', 1,
    V.SpellMarkup.MarksOnRow(1));

  { Typing it into a real word must clear the mark again. }
  V.Lines.Text := 'recieve';
  Pump;
  CheckEqInt('a misspelling is flagged', 1, V.SpellMarkup.MarksOnRow(1));
  V.Lines.Text := 'receive';
  Pump;
  CheckEqInt('and correcting it clears the mark', 0,
    V.SpellMarkup.MarksOnRow(1));

  { Adding a word silences it everywhere, not just here. }
  LedSpell.Ignore('recieve');
  Check('an ignored word is accepted', LedSpell.Check('recieve'));
  V.CaretXY := Point(4, 1);
  F.PopupEditorPopup(nil);
  Check('and the menu stops offering corrections for it',
    Pos('recieve', F.miSpelling.Caption) = 0);

  { --- the "auto" scope, which is the default ---------------------------

    medit's preference page promises "everything in prose, comments and
    strings in code" and its implementation does neither -- it switches
    checking off for any file with a language, Markdown and LaTeX included.
    LED does what the label says, so this pins down both halves.

    Note the word: an earlier check above ignores "recieve" for the session,
    so reusing it here would test nothing. }
  LedPrefs.SetStr('Editor/spell_scope', 'auto');

  { Prose: a Markdown document is checked end to end. }
  V.Lines.Text := 'A paragraph with seperate spelled wrong.';
  F.ActiveTab.Document.SetLanguage('markdown');
  F.ActiveTab.Document.ApplyConfigToViews;
  Pump;
  CheckEqInt('auto checks prose in a Markdown document', 1,
    V.SpellMarkup.MarksOnRow(1));

  { Source: the same word is checked in a comment and left alone as code. }
  F.ActiveTab.Document.SetLanguage('c');
  F.ActiveTab.Document.ApplyConfigToViews;
  V.Lines.Text := '/* seperate this */';
  Pump;
  CheckEqInt('auto checks comments in source', 1,
    V.SpellMarkup.MarksOnRow(1));

  { A block comment continued onto a second line: that line carries no
    delimiter of its own, so the scan has to know it starts inside one. }
  V.Lines.Text := '/* seperate here' + LineEnding + '   seperate there */';
  Pump;
  CheckEqInt('and a continuation line of a block comment', 1,
    V.SpellMarkup.MarksOnRow(2));
  CheckEqInt('and the line the block comment opens on', 1,
    V.SpellMarkup.MarksOnRow(1));

  V.Lines.Text := 'int seperate = 0;';
  Pump;
  CheckEqInt('but leaves identifiers alone', 0,
    V.SpellMarkup.MarksOnRow(1));

  V.Lines.Text := 'char *s = "seperate";';
  Pump;
  CheckEqInt('and checks strings too', 1, V.SpellMarkup.MarksOnRow(1));

  { An escape splits the string into three tokens; the word after it still
    has to be checked. }
  V.Lines.Text := 'char *s = "one\nseperate word";';
  Pump;
  CheckEqInt('and a string broken up by an escape', 1,
    V.SpellMarkup.MarksOnRow(1));

  { "all" overrides the language and checks the identifier as well. }
  LedPrefs.SetStr('Editor/spell_scope', 'all');
  F.ActiveTab.Document.ApplyConfigToViews;
  V.Lines.Text := 'int seperate = 0;';
  Pump;
  CheckEqInt('"all" checks even an identifier', 1,
    V.SpellMarkup.MarksOnRow(1));

  { Defaults: with nothing in prefs.ini at all, checking is on and scoped
    to auto.  Read them the way the editor reads them, so a call site that
    passed the wrong fallback would show up here. }
  LedPrefs.Remove('Editor/spell_enabled');
  LedPrefs.Remove('Editor/spell_scope');
  F.ActiveTab.Document.SetLanguage('c');
  F.ActiveTab.Document.ApplyConfigToViews;
  Check('spell checking defaults to on',
    LedPrefs.GetBool('Editor/spell_enabled', True));
  Check('and the default scope resolves to code for a source file',
    F.ActiveTab.Document.SpellScopeForDocument = lssCode);
  F.ActiveTab.Document.SetLanguage('markdown');
  Check('and to all for prose',
    F.ActiveTab.Document.SpellScopeForDocument = lssAll);

  { Cost: the scan now runs on every paint of every row, so it has to stay
    far below a frame.  Forty rows is a screenful. }
  F.ActiveTab.Document.SetLanguage('c');
  F.ActiveTab.Document.ApplyConfigToViews;
  L := TStringList.Create;
  try
    for i := 1 to 10 do
    begin
      L.Add('/* Collect the runs of prose on this row, and nothing else. */');
      L.Add('static int count_words (const char *text, size_t len)');
      L.Add('  { return moo_str_count (text, len, "a seperate word"); }');
      L.Add('');
    end;
    V.Lines.Assign(L);
  finally
    L.Free;
  end;
  Pump;
  T0 := Now;
  for i := 1 to 40 do
    V.SpellMarkup.MarksOnRow(i);
  Ms := MilliSecondsBetween(Now, T0);
  Check('scanning a screenful of source costs under 20 ms, took ' +
    IntToStr(Ms) + ' ms', Ms < 20);

  LedPrefs.SetStr('Editor/spell_scope', 'auto');
  LedPrefs.SetBool('Editor/spell_enabled', False);
  F.ActiveTab.Document.Master.Modified := False;
  while F.Notebook.PageCount > Before do
  begin
    F.Notebook.ActivePageIndex := F.Notebook.PageCount - 1;
    F.CloseActiveTab(False);
    Pump;
  end;
end;

procedure TestProjectList(F: TLedMainForm);
var
  L: TStringList;
  P1, P2, Store: string;
  G, N: TTreeNode;
begin
  Say('project file list');

  P1 := TempName('proj-1.txt');
  P2 := TempName('proj-2.txt');
  Store := TempName('filelist.json');
  L := TStringList.Create;
  try
    L.Add('a'); L.SaveToFile(P1); L.SaveToFile(P2);
  finally
    L.Free;
  end;

  F.Dock.ShowPane('project');
  Pump;
  F.Project.Tree.Items.Clear;

  { With no group yet, adding a file makes one -- otherwise the first Add to
    Project would silently do nothing. }
  N := F.Project.AddFile(P1);
  Check('adding a file to an empty list works', N <> nil);
  CheckEqInt('and it made a group to hold it', 1, F.Project.GroupCount);
  CheckEqInt('with the file in it', 1, F.Project.FileCount);
  Check('the node shows the base name, not the path',
    F.Project.Tree.Items[1].Text = ExtractFileName(P1));
  CheckEq('while the list remembers where it is', ExpandFileName(P1),
    F.Project.PathOf(F.Project.Tree.Items[1]));

  { The same file twice would be two entries for one file, and removing one
    would leave the other. }
  Check('adding the same file again is refused', F.Project.AddFile(P1) = nil);
  CheckEqInt('so the count is unchanged', 1, F.Project.FileCount);

  G := F.Project.AddGroup('Second');
  Check('a second group can be added', G <> nil);
  F.Project.Tree.Selected := G;
  F.Project.AddFile(P2);
  CheckEqInt('and a file goes into the selected group', 2, F.Project.GroupCount);
  CheckEqInt('with two files listed now', 2, F.Project.FileCount);
  CheckEqInt('the second group holds one', 1, G.Count);

  { Round trip.  A list that does not survive the session is a tab bar. }
  F.Project.SaveTo(Store);
  Check('the list was written', FileExists(Store));
  F.Project.Tree.Items.Clear;
  CheckEqInt('cleared', 0, F.Project.GroupCount);
  F.Project.LoadFrom(Store);
  CheckEqInt('both groups came back', 2, F.Project.GroupCount);
  CheckEqInt('and both files', 2, F.Project.FileCount);

  { Removing a group takes its files with it. }
  F.Project.Tree.Selected := F.Project.Tree.Items.GetFirstNode;
  F.Project.Tree.Selected.Delete;
  CheckEqInt('removing a group removes its files too', 1, F.Project.FileCount);

  { A corrupt list must not stop the editor starting. }
  L := TStringList.Create;
  try
    L.Text := 'this is not json';
    L.SaveToFile(Store);
  finally
    L.Free;
  end;
  F.Project.LoadFrom(Store);
  CheckEqInt('a corrupt list loads as an empty one', 0, F.Project.GroupCount);

  F.Project.Tree.Items.Clear;
  DeleteFile(P1); DeleteFile(P2); DeleteFile(Store);
end;

procedure TestSharedDocuments(F: TLedMainForm);
var
  W: TLedMainForm;
  Doc, Other: TLedDocument;
  L: TStringList;
  Path: string;
  Before, WinsBefore: Integer;
  Files: TStringList;
begin
  Say('documents across windows');

  Path := TempName('shared.txt');
  L := TStringList.Create;
  try
    L.Add('shared line'); L.SaveToFile(Path);
  finally
    L.Free;
  end;

  Before := F.Notebook.PageCount;
  WinsBefore := LedWindows.Count;
  Check('this window is in the registry', WinsBefore >= 1);

  Files := TStringList.Create;
  try
    Files.Add(Path);
    F.OpenFiles(Files);
    Pump;
    Doc := F.Documents.FindByFileName(Path);
    Check('the file opened', Doc <> nil);

    { A second window shares the registry, so asking it for the same path has
      to give the same document -- not a second one on the same file, which
      is how one save silently discarded the other's work. }
    W := TLedMainForm.Create(Application);
    try
      W.Show;
      Pump;
      CheckEqInt('the second window registered', WinsBefore + 1,
        LedWindows.Count);

      Other := W.Documents.FindByFileName(Path);
      Check('both windows see the same document', Other = Doc);
      Check('and the registry is one object', W.Documents = F.Documents);

      { Opening it from the other window reveals the tab that has it rather
        than making another -- medit's moo_editor_set_active_doc. }
      Check('the other window can reveal it', W.RevealDocument(Doc));
      CheckEqInt('and no extra tab was made', Before + 1, F.Notebook.PageCount);
      CheckEqInt('nor in the second window', 1, W.Notebook.PageCount);

      { An edit through one window is visible from the other, because there
        is only one document. }
      F.ActiveTab.ActiveView.SelectAll;
      F.ActiveTab.ActiveView.SelText := 'edited once';
      Pump;
      CheckEq('an edit is visible from either window', 'edited once',
        Trim(Other.Master.Lines.Text));

      Doc.Master.Modified := False;
    finally
      { Closing it must not raise.  It did: a pane the window never created
        was asked to save itself on the way out, and every close -- of any
        window, not just this one -- died on it. }
      W.Close;
      Pump;
      Application.ProcessMessages;
      Check('closing the second window is clean', True);
    end;

    { Closing the second window must not take the first window's document
      with it. }
    Check('the document survives the other window closing',
      F.Documents.FindByFileName(Path) <> nil);
    Check('and its tab is still here', F.ActiveTab <> nil);
  finally
    Files.Free;
  end;

  while F.Notebook.PageCount > Before do
  begin
    F.Notebook.ActivePageIndex := F.Notebook.PageCount - 1;
    F.CloseActiveTab(False);
    Pump;
  end;
  DeleteFile(Path);
end;

procedure TestBookmarkList(F: TLedMainForm);
var
  V: TLedEdit;
  Marks: TLedBookmarkArray;
  i: Integer;
begin
  Say('bookmark list');

  F.AddTab(F.Documents.NewDocument);
  Pump;
  V := F.ActiveView;
  V.Lines.Text := 'one' + LineEnding + 'two' + LineEnding + 'three' +
    LineEnding + 'four' + LineEnding + 'five';
  for i := 0 to 9 do V.ClearBookMark(i);

  { Set them out of order, so the collector has something to sort. }
  V.CaretXY := Point(1, 4); F.actAddBookmarkExecute(nil);
  V.CaretXY := Point(1, 2); F.actAddBookmarkExecute(nil);
  Pump;

  Marks := LedCollectBookmarks(V);
  CheckEqInt('both bookmarks are found', 2, Length(Marks));
  CheckEqInt('and they come back in line order, not slot order',
    2, Marks[0].Line);
  CheckEqInt('with the later one second', 4, Marks[1].Line);
  CheckEq('each carrying the text of its line', 'two', Marks[0].Text);

  { Add is not toggle: asking twice on the same line leaves one. }
  V.CaretXY := Point(1, 2);
  F.actAddBookmarkExecute(nil);
  Pump;
  CheckEqInt('adding twice on one line leaves one', 2,
    Length(LedCollectBookmarks(V)));

  { Toggle still removes, which is the difference between the two. }
  F.actToggleBookmarkExecute(nil);
  Pump;
  CheckEqInt('toggling the same line removes it', 1,
    Length(LedCollectBookmarks(V)));

  { The menu lists them, with the line number and its text. }
  F.PopulateBookmarkMenu;
  CheckEqInt('the menu has one entry', 1, F.miBookmarks.Count);
  Check('naming the line it jumps to',
    Pos('4:', F.miBookmarks.Items[0].Caption) = 1);
  Check('and showing the text there',
    Pos('four', F.miBookmarks.Items[0].Caption) > 0);

  for i := 0 to 9 do V.ClearBookMark(i);
  F.PopulateBookmarkMenu;
  { Nothing shown -- which is not the same as nothing there.  A dynamic
    submenu is refilled from its own parent's OnClick, so its old contents
    are hidden rather than destroyed: freeing the widgets of a menu gtk is in
    the middle of opening is what crashed LED when the pointer was swept
    quickly along the menu bar. }
  CheckEqInt('with none set the menu shows nothing', 0,
    VisibleItems(F.miBookmarks));
  Check('and says so', not F.miBookmarks.Enabled);

  F.ActiveTab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
end;

procedure TestRememberedState(F: TLedMainForm);
var
  Doc: TLedDocument;
  Tab: TLedTab;
  L: TStringList;
  Path, Saved: string;
  Before: Integer;
begin
  Say('remembered state');

  { The window title comes from a format string, with medit's placeholders,
    so a title configured there carries over. }
  Path := TempName('title.txt');
  L := TStringList.Create;
  try
    L.Add('hello'); L.SaveToFile(Path);
  finally
    L.Free;
  end;

  Before := F.Notebook.PageCount;
  Doc := F.Documents.OpenFile(Path);
  Tab := F.AddTab(Doc);
  Pump;

  Saved := LedPrefs.GetStr('Editor/window_title', '%a - %f%s');
  try
    LedPrefs.SetStr('Editor/window_title', '%a | %b');
    CheckEq('the title uses the format and the base name',
      'LED | ' + ExtractFileName(Path), F.FormatWindowTitle(Doc));

    LedPrefs.SetStr('Editor/window_title', '%%literal');
    CheckEq('a doubled per cent is one per cent',
      '%literal', F.FormatWindowTitle(Doc));

    LedPrefs.SetStr('Editor/window_title', '%z');
    CheckEq('an unknown placeholder is left visible',
      '%z', F.FormatWindowTitle(Doc));

    { The status suffix is the part that has to follow the document. }
    LedPrefs.SetStr('Editor/window_title', '%s');
    CheckEq('a saved document has no status suffix', '',
      F.FormatWindowTitle(Doc));
    Tab.ActiveView.SelectAll;
    Tab.ActiveView.SelText := 'changed';
    Pump;
    CheckEq('a modified one says so', ' [modified]', F.FormatWindowTitle(Doc));

    LedPrefs.SetStr('Editor/window_title_no_doc', 'nothing open');
    CheckEq('and there is a separate format for no document',
      'nothing open', F.FormatWindowTitle(nil));
  finally
    LedPrefs.SetStr('Editor/window_title', Saved);
    LedPrefs.SetStr('Editor/window_title_no_doc', '%a');
  end;

  { The search toggles survive a restart. }
  F.Search.MatchCase := True;
  F.Search.Regex := True;
  F.Search.WholeWord := False;
  F.Search.SaveFlags;
  F.Search.MatchCase := False;
  F.Search.Regex := False;
  F.Search.WholeWord := True;
  F.Search.LoadFlags;
  Check('match case came back on', F.Search.MatchCase);
  Check('regex came back on', F.Search.Regex);
  Check('and whole word came back off', not F.Search.WholeWord);
  { Direction is deliberately not restored. }
  Check('but the direction is not remembered', not F.Search.Backwards);

  { The tab strip can be hidden while a single document is open. }
  LedPrefs.SetBool('Editor/use_tabs', False);
  F.ApplyTabVisibility;
  Pump;
  if F.Notebook.PageCount = 1 then
    Check('one document can hide the tab strip', not F.Notebook.ShowTabs);
  LedPrefs.SetBool('Editor/use_tabs', True);
  F.ApplyTabVisibility;
  Pump;
  Check('and it comes back', F.Notebook.ShowTabs);

  Doc.Master.Modified := False;
  while F.Notebook.PageCount > Before do
  begin
    F.Notebook.ActivePageIndex := F.Notebook.PageCount - 1;
    F.CloseActiveTab(False);
    Pump;
  end;
  DeleteFile(Path);
end;

procedure TestSaveTheRightDocument(F: TLedMainForm);
var
  A, B: TLedTab;
  L: TStringList;
  P1, P2: string;
  Before: Integer;
begin
  Say('saving a named document');

  P1 := TempName('save-a.txt');
  P2 := TempName('save-b.txt');
  L := TStringList.Create;
  try
    L.Add('original a'); L.SaveToFile(P1);
    L.Clear; L.Add('original b'); L.SaveToFile(P2);
  finally
    L.Free;
  end;

  Before := F.Notebook.PageCount;
  A := F.AddTab(F.Documents.OpenFile(P1));
  B := F.AddTab(F.Documents.OpenFile(P2));
  Pump;

  { Both dirty, with B in front.  Edited through the editor, not by assigning
    Lines.Text -- a direct write to the string list bypasses the undo list,
    so the document never becomes Modified and this test would pass without
    testing anything. }
  A.ActiveView.SelectAll;
  A.ActiveView.SelText := 'changed a';
  B.ActiveView.SelectAll;
  B.ActiveView.SelText := 'changed b';
  Pump;
  Check('both documents are modified', A.Document.Modified and B.Document.Modified);

  { Saving A by name has to save A, whichever tab is in front.  ConfirmClose
    used to call actSaveExecute, which saves the *active* tab -- so closing a
    window with several modified documents saved the front one repeatedly and
    left the others on disk unchanged. }
  Check('B is the tab in front', F.ActiveTab = B);
  Check('saving A by name reports success', F.SaveDocument(A.Document));
  Pump;
  Check('A is no longer modified', not A.Document.Modified);
  Check('and B still is', B.Document.Modified);

  L := TStringList.Create;
  try
    L.LoadFromFile(P1);
    CheckEq('A''s own file holds A''s text', 'changed a', Trim(L.Text));
    L.LoadFromFile(P2);
    CheckEq('and B''s file is untouched', 'original b', Trim(L.Text));
  finally
    L.Free;
  end;

  B.Document.Master.Modified := False;
  while F.Notebook.PageCount > Before do
  begin
    F.Notebook.ActivePageIndex := F.Notebook.PageCount - 1;
    F.CloseActiveTab(False);
    Pump;
  end;
  DeleteFile(P1); DeleteFile(P2);
end;

procedure TestTabReordering(F: TLedMainForm);
var
  A, B, C: TLedTab;
  L: TStringList;
  P1, P2, P3: string;
  Before: Integer;
begin
  Say('tab reordering');

  P1 := TempName('order-1.txt');
  P2 := TempName('order-2.txt');
  P3 := TempName('order-3.txt');
  L := TStringList.Create;
  try
    L.Add('x');
    L.SaveToFile(P1); L.SaveToFile(P2); L.SaveToFile(P3);
  finally
    L.Free;
  end;

  Before := F.Notebook.PageCount;
  A := F.AddTab(F.Documents.OpenFile(P1));
  B := F.AddTab(F.Documents.OpenFile(P2));
  C := F.AddTab(F.Documents.OpenFile(P3));
  Pump;
  CheckEqInt('three tabs added', Before + 3, F.Notebook.PageCount);

  CheckEqInt('they start in the order they were opened',
    A.Sheet.PageIndex + 1, B.Sheet.PageIndex);
  CheckEqInt('and so does the third', B.Sheet.PageIndex + 1, C.Sheet.PageIndex);

  { Moving a page is what a drag does; the drag itself is mouse plumbing,
    but the reordering underneath it is the part that can be wrong. }
  C.Sheet.PageIndex := A.Sheet.PageIndex;
  Pump;
  Check('the third tab moved ahead of the first',
    C.Sheet.PageIndex < A.Sheet.PageIndex);
  Check('and the others shifted along',
    A.Sheet.PageIndex < B.Sheet.PageIndex);
  CheckEqInt('with no tab lost', Before + 3, F.Notebook.PageCount);

  Check('every tab still knows its document',
    (A.Document <> nil) and (B.Document <> nil) and (C.Document <> nil));
  Check('and the moved one kept its file',
    SameFileName(P3, C.Document.FileName));

  while F.Notebook.PageCount > Before do
  begin
    F.Notebook.ActivePageIndex := F.Notebook.PageCount - 1;
    F.CloseActiveTab(False);
    Pump;
  end;
  DeleteFile(P1); DeleteFile(P2); DeleteFile(P3);
end;

procedure TestBrowserNavigation(F: TLedMainForm);
var
  Dir, Sub, Start: string;
  T0: TDateTime;
  Ms: Integer;
begin
  Say('file browser navigation');

  Dir := IncludeTrailingPathDelimiter(TempName('nav'));
  Sub := Dir + 'inner' + PathDelim;
  ForceDirectories(Sub);

  { The first show is the expensive one: the tree's handle is created here,
    and until its Root is set the LCL populates it with every logical drive.
    On Windows that is reported to take about ten seconds. }
  T0 := Now;
  F.Dock.ShowPane('files');
  Pump;
  Ms := MilliSecondsBetween(Now, T0);
  Check('the first show of the file pane is quick, took ' + IntToStr(Ms) +
    ' ms', Ms < 1500);

  F.Browser.SetRoot(Dir);
  Pump;
  Start := F.Browser.Root;

  { The pane roots itself the first time it is shown, so setting a root here
    is the second place it has been and there is genuinely a step behind it.
    That is a change in premise, not in behaviour: what used to make this
    assertion pass was the trail never being seeded at all, which is the bug
    that left the crumb bar empty.  A browser that really has been nowhere is
    checked in TestFileBrowser, on one built there. }
  Check('the root it opened at is behind us', F.Browser.CanGoBack);
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
  Term: TLedTermView;
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
      { The same 96-dpi literals as in TestTerminal, scaled for the same
        reason.  Nothing here counts columns, so this was not failing -- but
        it rests on the same assumption. }
      Pane.Width := LedScale96(600);
      Pane.Height := LedScale96(300);
      Pane.Visible := False;
      Pump;

      Check('the pane starts a terminal', Pane.Start(GetTempDir));
      CheckEqInt('one to begin with', 1, Pane.Count);

      { The terminal drew at the Xft DPI while the window around it was scaled
        to the display -- the same gtk2 point-size trap the editor was in.  It
        showed up worse here than elsewhere because the cell grid is measured
        off the font, so the whole terminal was small, not just its text. }
      CheckEqInt('the terminal font is scaled for the display',
        LedScalePointSize(10), Pane.Active.Font.Size);

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

      { Mouse selection.  Driven through the cell model rather than by
        synthesising mouse events, because what can be wrong here is which
        cells the selection covers and what text comes out of them. }
      Term := Pane.Active;
      Term.Screen.Feed('hello world' + #13#10 + 'second line' + #13#10);
      Pump;
      Check('nothing is selected to begin with', not Term.HasSelection);
      CheckEq('so there is no text to copy', '', Term.SelectedText);

      Term.SelectAll;
      Check('select all selects something', Term.HasSelection);
      Check('and the text includes what was written',
        Pos('hello world', Term.SelectedText) > 0);
      Check('and the second line too',
        Pos('second line', Term.SelectedText) > 0);

      { Every row is padded to the full width; the padding must not come
        out with the text. }
      Check('without the row padding',
        Pos('hello world  ', Term.SelectedText) = 0);

      Term.ClearSelection;
      Check('and it can be cleared', not Term.HasSelection);
    finally
      Pane.Free;
    end;
  end;

  { medit shipped ten named ANSI palettes.  Checked by name rather than by
    count, so LED is free to add its own without the check going off -- the
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

{ How many pixels of AName's icon, as the application builds it, are still
  the mask colour -- which is what a purple block in a menu is. }
function IconMaskLeak(const AName: string): Integer;
var
  Images: TImageList;
  Bmp: TBitmap;
  Img: TLazIntfImage;
  x, y: Integer;
  C: TFPColor;
begin
  Result := 0;
  Images := TImageList.Create(nil);
  Bmp := TBitmap.Create;
  try
    Images.Width := 20;
    Images.Height := 20;
    LedBuildIconList(Images, [AName], clBtnText);
    if Images.Count = 0 then Exit;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(20, 20);
    Images.GetBitmap(0, Bmp);
    Img := Bmp.CreateIntfImage;
    try
      for y := 0 to Img.Height - 1 do
        for x := 0 to Img.Width - 1 do
        begin
          C := Img.Colors[x, y];
          if (C.Alpha >= $4000) and (C.Red > $C000) and (C.Blue > $C000) and
             (C.Green < $4000) then Inc(Result);
        end;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
    Images.Free;
  end;
end;

{ How many pixels of AName's icon, as the application builds it, are exactly
  AColour.  Built here rather than read out of ImageList1 so the check is of
  the drawing and not of one particular list. }
function IconColourCount(const AName: string; AColour: TColor): Integer;
var
  Images: TImageList;
  Bmp: TBitmap;
  Img: TLazIntfImage;
  x, y: Integer;
  C, Want: TFPColor;
begin
  Result := 0;
  if AColour = clNone then Exit;
  Want := TColorToFPColor(ColorToRGB(AColour));
  Images := TImageList.Create(nil);
  Bmp := TBitmap.Create;
  try
    Images.Width := 16;
    Images.Height := 16;
    LedBuildIconList(Images, [AName], clBtnText);
    if Images.Count = 0 then Exit;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(16, 16);
    Images.GetBitmap(0, Bmp);
    Img := Bmp.CreateIntfImage;
    try
      for y := 0 to Img.Height - 1 do
        for x := 0 to Img.Width - 1 do
        begin
          C := Img.Colors[x, y];
          if (C.Red = Want.Red) and (C.Green = Want.Green) and
             (C.Blue = Want.Blue) then Inc(Result);
        end;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
    Images.Free;
  end;
end;

{ True when an icon has a hole in it: a background pixel with ink above,
  below, left and right of it.

  Which is what tells an outlined shape from a solid one, and is the point
  of the stop sign.  A run triangle and the filled disc that used to be the
  breakpoint icon are both solid, so neither has one -- at sixteen pixels
  they are two blobs of the same weight, which is how they came to be
  mistaken for each other. }
function IconHasHole(const AName: string): Boolean;
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  x, y, k: Integer;
  Ink: array of array of Boolean;
  C: TFPColor;
  Up, Down, Left, Right: Boolean;
begin
  Result := False;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(16, 16);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.FillRect(0, 0, 16, 16);
    Bmp.Canvas.AntialiasingMode := amOff;
    LedDrawIcon(Bmp, AName, clBlack);
    Img := Bmp.CreateIntfImage;
    try
      SetLength(Ink, Img.Width, Img.Height);
      for y := 0 to Img.Height - 1 do
        for x := 0 to Img.Width - 1 do
        begin
          C := Img.Colors[x, y];
          Ink[x, y] := (C.Red < $4000) and (C.Green < $4000) and
                       (C.Blue < $4000);
        end;
      for y := 1 to Img.Height - 2 do
        for x := 1 to Img.Width - 2 do
          if not Ink[x, y] then
          begin
            Up := False; Down := False; Left := False; Right := False;
            for k := 0 to y - 1 do if Ink[x, k] then Up := True;
            for k := y + 1 to Img.Height - 1 do if Ink[x, k] then Down := True;
            for k := 0 to x - 1 do if Ink[k, y] then Left := True;
            for k := x + 1 to Img.Width - 1 do if Ink[k, y] then Right := True;
            if Up and Down and Left and Right then Exit(True);
          end;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ The width of the topmost row of ink in an icon, which is what tells a
  flat-topped shape from a round or pointed one. }
function IconTopRun(const AName: string): Integer;
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  x, y, Run: Integer;
  C: TFPColor;
begin
  Result := 0;
  { Drawn into a bitmap of this function's own.  LedIconBitmap hands back a
    shared one that the unit owns and reuses, so freeing it is a crash. }
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.SetSize(16, 16);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.FillRect(0, 0, 16, 16);
    Bmp.Canvas.AntialiasingMode := amOff;
    LedDrawIcon(Bmp, AName, clBlack);
    Img := Bmp.CreateIntfImage;
    try
      for y := 0 to Img.Height - 1 do
      begin
        Run := 0;
        for x := 0 to Img.Width - 1 do
        begin
          C := Img.Colors[x, y];
          if (C.Red < $4000) and (C.Green < $4000) and (C.Blue < $4000) then
            Inc(Run);
        end;
        if Run > 0 then Exit(Run);
      end;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{$IF DEFINED(UNIX) and not DEFINED(DARWIN) and DEFINED(LCLGtk2)}
  {$DEFINE LED_X11_TEST}
{$ENDIF}

{$IFDEF LED_X11_TEST}
type
  { Only the fields the request needs.  Declared here rather than taken from a
    binding FPC does not ship. }
  TLedShmSegmentInfo = record
    shmseg: TXID;
    shmid: cint;
    shmaddr: PChar;
    readOnly: TBoolResult;
  end;

function XShmAttach(D: PDisplay; var Info: TLedShmSegmentInfo): TBoolResult;
  cdecl; external 'Xext';
{$ENDIF}

{ Surviving the X error that ssh X forwarding produces.

  Not a simulation: this sends a real X_ShmAttach for a segment the server
  cannot attach to, which is exactly what GDK sends when the display is on
  another machine, and gets back exactly what the user reported --
  error_code 10, request_code <MIT-SHM>, minor_code 1.  Without the handler
  in Led.UI.XError, GTK's own handler prints a paragraph and calls exit(),
  and this procedure never returns. }
procedure TestXErrorSurvival(F: TLedMainForm);
{$IFDEF LED_X11_TEST}
var
  D: PDisplay;
  Info: TLedShmSegmentInfo;
  Before, Major, FirstEvent, FirstError: cint;
{$ENDIF}
begin
  Say('x error handling');
{$IFDEF LED_X11_TEST}
  { The handler has to be in: without it the request below reaches GTK's own
    handler, which prints a paragraph and calls exit() -- so this check
    failing is the last thing this suite would ever print. }
  CheckGt('the MIT-SHM opcode was looked up', 0, LedXShmOpcode);

  D := XOpenDisplay(nil);
  Check('a second connection opens', D <> nil);
  if D = nil then Exit;
  try
    { Looked up here as well as in Led.UI.XError, so the request is sent
      whether or not LED installed anything -- a check that provokes nothing
      when the fix is missing proves nothing about the fix. }
    Major := 0;
    if not XQueryExtension(D, 'MIT-SHM', @Major, @FirstEvent, @FirstError) then
    begin
      Say('  (no MIT-SHM on this server; nothing to provoke)');
      Exit;
    end;
    Before := LedXErrorsIgnored;
    { A shmid nothing owns, so the server's own shmat fails and it answers
      BadAccess -- the same answer it gives when the segment is on a
      different machine. }
    Info.shmseg := 0;
    Info.shmid := 999999999;
    Info.shmaddr := nil;
    Info.readOnly := False;
    XShmAttach(D, Info);
    { Forces the error to arrive now rather than at some later flush. }
    XSync(D, False);
    CheckGt('the shm error was caught and ignored', Before,
      LedXErrorsIgnored);
  finally
    XCloseDisplay(D);
  end;
  { Reached at all only because the process did not exit. }
  Check('and LED is still running', F <> nil);
{$ELSE}
  Say('  (not an X11 build; nothing to provoke)');
  Check('the stub reports no opcode', LedXShmOpcode = -1);
{$ENDIF}
end;

procedure TestIconsAndFocus(F: TLedMainForm);
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  x, y, Clear, Opaque, Purple, i, Blank: Integer;
  Leaky: string;
  C: TFPColor;
  Hidden: TForm;
  Ed: TEdit;
begin
  Say('icons and focus');

  CheckEqInt('every icon was built', Length(LedIconNames), F.ImageList1.Count);

  { The window icon comes from the MAINICON resource that make-icon.py
    writes into app/led.res.  Worth asserting rather than assuming: the
    resource is a Windows .res, and whether it reaches the LCL on a gtk2
    build is not obvious from the fact that it linked. }
  { The window icon, and where it came from.

    Size is the tell.  MAINICON is a multi-size .ico whose first entry is
    16x16, and taking the window icon from it is the bug this replaced: the
    picture survives in process and reaches the window manager with striped
    colour channels and no transparency.  LedApplyWindowIcon assigns the
    256x256 PNG instead, so a width of 256 says the right source won.  If
    this ever reads 16 again, the title bar is garbled. }
  Check('the application has a window icon', not Application.Icon.Empty);
  CheckEqInt('taken from the PNG resource, not MAINICON', 256,
    Application.Icon.Width);
  { The form's own Icon stays empty on purpose -- that is how the LCL is
    told to fall back to the application's. }
  CheckEq('the title names the editor', 'LED - a lightweight editor',
    LedAppTitle);

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

  { Every icon, not just one of them.  Two in the Help menu were showing the
    mask as a purple block, which a check on 'save' alone could never see. }
  Leaky := '';
  for i := 0 to High(LedIconNames) do
    if IconMaskLeak(LedIconNames[i]) > 0 then
      Leaky := Leaky + LedIconNames[i] + ' ';
  CheckEq('no icon lets the mask colour through: ' + Leaky, '', Leaky);

  { Breakpoint against Run.  Both are solid shapes in the same ink on a
    monochrome toolbar, and a filled disc and a filled triangle at sixteen
    pixels were being taken for one another.  A stop sign is the shape that
    reads as "stop" without colour, and its tell is a flat top: the topmost
    row with any ink in it is a run several pixels wide, where a disc's is a
    short arc and a triangle's is a single point. }
  Say(Format('  (top row ink: breakpoint %d, run %d)',
    [IconTopRun('breakpoint'), IconTopRun('run')]));
  CheckGt('the breakpoint icon has a flat top, like a stop sign',
    IconTopRun('run'), IconTopRun('breakpoint'));
  { The stronger half, and the one a disc fails: an outline encloses
    background, a solid shape does not. }
  Check('and it is an outline, so it cannot read as another solid blob',
    IconHasHole('breakpoint'));
  Check('where Run is solid', not IconHasHole('run'));

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

{ Pane geometry.  AnchorDocking sizes a newly docked pane from the one it
  lands beside -- Max(1, Min(NewSite.Width, Sibling.Width div 2)) -- so before
  LED re-asserted the size itself, three panes down one edge came out 229, 114,
  57, and closing and reopening them walked the edge down to the Max(1,...)
  floor and left it there.  A pane one pixel wide is not a pane. }
procedure TestPaneSizes(F: TLedMainForm);
var
  i, round_: Integer;
  Ids: array[0..2] of string = ('symbols', 'preview', 'debug');
  First: array[0..2] of Integer;
  Smallest, W0, W1: Integer;

  function SmallestPane: Integer;
  var
    k, Sz: Integer;
  begin
    Result := MaxInt;
    for k := 0 to 2 do
    begin
      Sz := F.Dock.PaneSize(Ids[k]);
      if (Sz >= 0) and (Sz < Result) then Result := Sz;
    end;
    if Result = MaxInt then Result := -1;
  end;

begin
  Say('pane sizes');

  for i := 0 to 2 do
  begin
    F.Dock.ShowPane(Ids[i]);
    Pump;
  end;

  { Not a strip.  The floor is well below the 220 an edge asks for -- a narrow
    window has to be allowed to give them less -- but far above the single
    pixel this used to collapse to. }
  Smallest := SmallestPane;
  CheckGt('three panes on one edge all stay usably wide', 40, Smallest);

  { And the editor is not squeezed out to pay for them. }
  CheckGt('and the editor keeps its room', 100, F.Dock.Center.Width);

  for i := 0 to 2 do
    First[i] := F.Dock.PaneSize(Ids[i]);

  { The floor the editor is protected by comes off the editor, not off a
    constant.  It was two numbers with nothing behind them -- 240 by 160 --
    which scaled up to 750 by 500 on a 3.125x display and left no budget for
    a pane to open into. }
  Check('the editor floor is set, not left at the fallback',
    F.Dock.MinCentreWidth > 0);
  if (F.ActiveView <> nil) and (F.ActiveView.CharWidth > 0) then
    CheckEqInt('and it is forty columns of the editor''s own font, plus gutter',
      F.ActiveView.CharWidth * 40 + F.ActiveView.Gutter.Width,
      F.Dock.MinCentreWidth);

  { A window too small for what is being asked of it grows, rather than the
    panes being shaved to fit.  Opening a pane on a narrow window used to give
    it whatever was left -- a strip, at the scales where the editor's own
    floor ate the budget. }
  W0 := F.Width;
  for i := 0 to 2 do
  begin
    F.Dock.HidePane(Ids[i]);
    Pump;
  end;
  F.Dock.HidePane('files');
  Pump; Pump;
  { As narrow as the window will go.  Not 400: the window has a floor of its
    own -- the toolbar, checked further down -- and on a desktop whose fonts
    make that floor 548, a pane and the editor's own floor both fit at it and
    there is correctly nothing to grow for.  Asking for growth unconditionally
    made this fail on the machine it was written on and pass elsewhere, which
    says nothing about the dock either way.

    So what is asserted is the property, which holds at any width: the pane
    gets a usable size and the editor keeps its floor.  The growth is
    asserted only where the two genuinely do not both fit. }
  F.Width := 400;
  Pump; Pump;
  W1 := F.Width;
  F.Dock.ShowPane('files');
  Pump; Pump;
  if W1 < LedScale96(120) + LedScale96(240) then
    CheckGt('a narrow window grows to fit a pane rather than shrinking it',
      W1, F.Width)
  else
    Say(Format('  (the window will not go below %d, where a pane and the ' +
      'editor both fit; no growth to check)', [W1]));
  CheckGt('and the pane it made room for is usable', 120,
    F.Dock.PaneSize('files'));
  CheckGt('and the editor keeps its floor', 200, F.Dock.Center.Width);

  { Right size on the dock that opened it, not one action later.
    AnchorDocking moves its splitters through a queued call, so the sizing
    that ran inline was working from a layout still in flight: the pane came
    out at 163 of 229 with the editor sitting on room it could have spared,
    and only caught up when some later dock happened to run the sizing again.

    This does not reproduce that.  Taking the queued pass out again leaves it
    passing: the failure needs the layout to still be in flight when the
    sizing runs, and by the time this check is reached the suite has opened
    and closed enough that everything fits on the inline pass.  It was
    measured directly instead -- 163 before the queued pass, 229 after, same
    window and same two panes -- and what is left here is the invariant, not
    a guard on it. }
  for i := 0 to 2 do
  begin
    F.Dock.HidePane(Ids[i]);
    Pump;
  end;
  F.Dock.HidePane('files');
  Pump; Pump;
  F.Width := 560;
  Pump; Pump;
  F.Dock.ShowPane('files');
  Pump; Pump;
  F.Dock.ShowPane('symbols');
  Pump; Pump;
  CheckGt('a second pane is its full size at once, not on the next dock',
    200, F.Dock.PaneSize('symbols'));
  F.Dock.HidePane('files');
  F.Dock.HidePane('symbols');
  F.Width := W0;
  Pump; Pump;
  for i := 0 to 2 do
  begin
    F.Dock.ShowPane(Ids[i]);
    Pump;
  end;
  F.Dock.HidePane('files');
  F.Width := W0;
  Pump; Pump;
  for i := 0 to 2 do
  begin
    F.Dock.ShowPane(Ids[i]);
    Pump;
  end;

  { The ratchet: the size a dock produced used to be the size fed into the
    next one, so every close and reopen shrank the edge again. }
  for round_ := 1 to 3 do
    for i := 0 to 2 do
    begin
      F.Dock.HidePane(Ids[i]);
      Pump;
      F.Dock.ShowPane(Ids[i]);
      Pump;
    end;

  CheckGt('and still usably wide after three reopen rounds', 40, SmallestPane);

  for i := 0 to 2 do
    CheckEqInt('pane ' + Ids[i] + ' is the same size after three reopen rounds',
      First[i], F.Dock.PaneSize(Ids[i]));

  for i := 0 to 2 do
  begin
    F.Dock.HidePane(Ids[i]);
    Pump;
  end;
end;

{ A pane keeps the size it was dragged to when it is closed and opened again.

  Two sizes are in play and only one of them may be remembered.  The size a
  layout pass produced must not be: feeding that back in is what made every
  reopen shrink the edge a little further, which TestPaneSizes above still
  guards.  The size a splitter drag produced must be, and that is what this
  covers -- the user set it by hand and closing the pane is not a reason to
  throw it away.

  The drag is done in two pieces because a real one cannot be had headless:
  TCustomSplitter reads the pointer with GetCursorPos, so synthetic MouseMove
  events all compute an offset of zero.  So the size is moved by MoveSplitter,
  which is what a drag calls, and the drag is then ended by the MouseUp the
  dock hangs its recording off.  Both halves are the real code. }
type
  { MouseUp is protected, and ending a drag is the whole point here. }
  TSplitAccess = class(TCustomSplitter);

procedure TestPaneSizeMemory(F: TLedMainForm);
var
  Pane: TLedPaneForm;
  Site: TAnchorDockHostSite;
  Split: TAnchorDockSplitter;
  W0, W1, W2: Integer;
begin
  Say('pane size memory');

  F.Dock.ShowPane('files');
  Pump; Pump;
  W0 := F.Dock.PaneSize('files');
  CheckGt('the files pane opens at a usable width', 40, W0);

  Pane := F.Dock.FindPane('files');
  Site := nil;
  if Pane <> nil then Site := DockMaster.GetAnchorSite(Pane);
  Split := nil;
  { A left pane is anchored to the splitter on its right. }
  if (Site <> nil) and (Site.AnchorSide[akRight].Control is TAnchorDockSplitter) then
    Split := TAnchorDockSplitter(Site.AnchorSide[akRight].Control);
  Check('the files pane has a splitter to drag', Split <> nil);
  if Split = nil then Exit;

  Split.MoveSplitter(LedScale96(70));
  Pump;
  W1 := F.Dock.PaneSize('files');
  CheckGt('dragging the splitter widens the pane', W0 + LedScale96(20), W1);

  { The end of the drag.  No MouseDown preceded it, so StopSplitterMove has
    nothing to undo and this is only the notification. }
  TSplitAccess(Split).MouseUp(mbLeft, [], 0, 0);

  F.Dock.HidePane('files');
  Pump; Pump;
  F.Dock.ShowPane('files');
  Pump; Pump;
  W2 := F.Dock.PaneSize('files');

  { Within a few pixels: the reopened pane is put back by moving a splitter,
    and a splitter lands on whole steps of whatever the layout can give. }
  CheckGt('a reopened pane comes back at the width it was dragged to',
    W1 - LedScale96(12), W2);
  CheckGt('and not wider than it was dragged to', W2 - LedScale96(12), W1);

  { Back to where it started, so what follows sees the default edge.  The
    same two pieces: move, then end the drag. }
  Split := nil;
  Site := DockMaster.GetAnchorSite(F.Dock.FindPane('files'));
  if (Site <> nil) and (Site.AnchorSide[akRight].Control is TAnchorDockSplitter) then
    Split := TAnchorDockSplitter(Site.AnchorSide[akRight].Control);
  if Split <> nil then
  begin
    Split.MoveSplitter(W0 - F.Dock.PaneSize('files'));
    Pump;
    TSplitAccess(Split).MouseUp(mbLeft, [], 0, 0);
  end;
  F.Dock.HidePane('files');
  Pump;
end;

{ The tab strip's close button, the window's minimum size, and the band that
  marks the active terminal -- the three medit details that could be had the
  same way on every platform.  The fourth, a coloured line along the top of
  the active tab, could not: no widgetset implements owner-drawn tabs, so it
  would have existed on none of them. }
procedure TestMeditTrim(F: TLedMainForm);
var
  Btn: TSpeedButton;
  Host: TWinControl;
  R: TRect;
  Before, TbH, W0, H0: Integer;
  X, Y, Lo, Hi, BtnTop, Out_: Integer;
begin
  Say('medit trim');

  W0 := F.Width;
  H0 := F.Height;

  { The minimum size.  TToolBar is wrapable, so without a floor the buttons
    fold onto a second row and the toolbar grows a band taller. }
  TbH := F.ToolBar1.Height;
  F.Width := 100;
  F.Height := 80;
  Pump; Pump;
  CheckGt('the window will not shrink past its toolbar', 200, F.Width);
  CheckEqInt('and the toolbar does not wrap to a second row', TbH,
    F.ToolBar1.Height);

  F.Width := W0;
  F.Height := H0;
  Pump; Pump;

  { The close button.  Two tabs, so the strip is certainly showing. }
  while F.TabCount > 1 do F.CloseActiveTab(True);
  F.actNewExecute(nil);
  Pump;
  Btn := F.TabCloseButton(0);
  Check('the tab strip has a close button', Btn <> nil);
  if Btn = nil then Exit;
  Host := Btn.Parent;
  Check('and it is showing', Btn.Visible and Host.Visible);

  { It has a window of its own, and that is the point of the host.

    A TSpeedButton is a TGraphicControl: no handle, painted onto whatever it
    is parented to.  Parented straight onto the panel the notebook sits in it
    was drawn in the right place and did nothing at all when clicked -- the
    windowed controls stacked above that panel took the mouse first.  It
    looked correct and was inert, which is exactly the shape of bug a test
    that calls Btn.Click cannot see, because that calls the handler directly
    and never asks whether a click could have reached it.

    Measured with a synthetic X button event at the middle of the cross, two
    tabs open:

      button on the shared panel   2 tabs -> 2 tabs, nothing happened
      button in a windowed host    2 tabs -> 1 tab

    So what is asserted here is the structure that made the difference: the
    button lives in its own windowed host, not in the panel that also holds
    the notebook. }
  Check('the close button has a host of its own, not the notebook''s panel',
    Host <> F.Notebook.Parent);

  { On the tabs, and centred on them.

    Measured by asking the notebook which tab is at a point, scanning down
    the middle of the first tab until it stops answering.  TabRect would say
    the same thing on this desktop, but it is the rectangle the placement is
    computed from, and a check that reads it back cannot see the placement
    being wrong -- which it was: gtk2 measures that rectangle from the page
    area, and the button was hung from the top of the control instead, five
    pixels above the tab.

    In the notebook's client coordinates throughout, which is what
    IndexOfTabAt takes; on gtk2 those are the page area's, so the strip is at
    negative y and the numbers below are meant to be negative. }
  R := F.Notebook.TabRect(0);
  Lo := 9999;
  Hi := -9999;
  X := (R.Left + R.Right) div 2;
  for Y := -F.Notebook.Height to F.Notebook.ClientHeight do
    if F.Notebook.IndexOfTabAt(Point(X, Y)) = 0 then
    begin
      if Y < Lo then Lo := Y;
      if Y > Hi then Hi := Y;
    end;
  Check('the notebook says where its first tab is', Hi >= Lo);

  { Both edges of the cross inside the band, with a pixel of slack for the
    rounding in the middle of an odd number of them. }
  BtnTop := Host.ControlOrigin.y - F.Notebook.ClientOrigin.y;
  Check('the close button is on the tab band, not above it',
    (BtnTop >= Lo - 1) and (BtnTop + Host.Height <= Hi + 2));
  Out_ := Abs((BtnTop + Host.Height div 2) - ((Lo + Hi) div 2));
  Check(Format('and is centred on it, not hung from one edge (%d px out)',
    [Out_]), Out_ <= 1);
  Check('and at the right-hand end of it',
    Host.Left + Host.Width <= F.Notebook.Left + F.Notebook.Width);
  CheckGt('well to the right of the middle', F.Notebook.Width div 2, Host.Left);


  Before := F.TabCount;
  Btn.Click;
  Pump;
  CheckEqInt('and closing a tab is what it does', Before - 1, F.TabCount);
end;

{ The font LED brings with it.

  Bundled rather than assumed installed, so the default is the same face on
  every machine instead of whatever the desktop calls "Monospace".  The two
  halves that can each fail quietly are checked separately: the platform
  accepting the file, and the toolkit then being able to resolve the family
  by name -- which is what every caller does, and what LedParseFontSpec
  rejects an unknown name for.

  Both must hold before the family may be the default, because a default the
  toolkit cannot resolve is worse than the platform one: it falls back per
  control, so the editor and the terminal can disagree. }
procedure TestBundledFont(F: TLedMainForm);
var
  Term: TLedTermView;
  FontName: string;
  FontSize: Integer;
begin
  Say('bundled font');

  Check('the bundled fonts loaded', LedBundledFontsLoaded);
  Check('and the toolkit can resolve the family',
    Screen.Fonts.IndexOf(LedBundledFontName) >= 0);
  CheckEq('so it is the default', LedBundledFontName, LedDefaultFontName);

  { What the two consumers actually ended up with.  They are set from
    LedDefaultFontName in different units, so agreeing is worth asserting. }
  if F.ActiveView <> nil then
    CheckEq('the editor is in it', LedBundledFontName, F.ActiveView.Font.Name);

  F.Dock.ShowPane('terminal');
  Pump; Pump;
  Term := nil;
  if F.Terminal <> nil then
    Term := F.Terminal.Active;
  if Term <> nil then
    CheckEq('and so is the terminal', LedBundledFontName, Term.Font.Name);
  F.Dock.HidePane('terminal');
  Pump;

  { Upgrading from a prefs.ini written before the font was bundled.

    "Monospace 10" is not a choice anyone made: it is what the Preferences
    dialog stored when it was accepted, back when it was the resolved
    default.  Left alone it shadows the shipped font for ever, and it
    survives the not-installed check because the toolkit lists the alias
    among its families -- which is why this is asserted rather than assumed. }
  Check('the toolkit lists the alias as though it were a family',
    Screen.Fonts.IndexOf('Monospace') >= 0);
  Check('and it is recognised as an alias all the same',
    LedIsGenericFamily('Monospace'));

  LedParseFontSpec('Monospace 10', FontName, FontSize);
  CheckEq('so an upgraded preference falls through to the bundled font',
    LedBundledFontName, FontName);
  CheckEqInt('keeping the size that was chosen', 10, FontSize);

  { And a real face is left exactly where it is -- the whole point of the
    distinction.  Checked with the bundled family itself, which is the one
    name this suite knows is installed. }
  LedParseFontSpec(LedBundledFontName + ' 13', FontName, FontSize);
  CheckEq('a real family is never second-guessed',
    LedBundledFontName, FontName);
  CheckEqInt('nor its size', 13, FontSize);

  Check('an alias is told from a face', not LedIsGenericFamily(LedBundledFontName));
end;

{ Untitled numbering.

  Closing the last tab opens a fresh untitled document to replace it, and the
  number used to come from a counter that only ever climbed -- so clicking the
  tab strip's close button over and over walked the title up, Untitled 9, 10,
  11, with one empty document on screen throughout.  File > Close had always
  done it; the button only made it easy enough to sit there noticing.

  The number is now the lowest one not in use, so it is bounded by how many
  documents are actually open.

  Nothing here asserts a particular number.  By the time this runs the suite
  has opened and closed a good deal, and at least one document is alive
  without a tab of its own, so "the next one is Untitled 3" would be a test of
  what ran before it.  What is checked is the behaviour: the name does not
  move when a document is replaced, and a number comes back into use once the
  document holding it has gone. }
procedure TestUntitledNumbering(F: TLedMainForm);
var
  i: Integer;
  Btn: TSpeedButton;
  Lone, Taken: string;
begin
  Say('untitled numbering');

  while F.TabCount > 1 do F.CloseActiveTab(True);
  Pump;
  Lone := F.ActiveTab.Document.DisplayName;
  Check('a lone document is an untitled one', F.ActiveTab.Document.IsUntitled);

  { The regression: closing the last tab replaces it, and the replacement
    used to take the next number every time. }
  for i := 1 to 5 do
  begin
    F.actCloseTabExecute(nil);
    Pump;
  end;
  CheckEq('closing and replacing it five times does not count up',
    Lone, F.ActiveTab.Document.DisplayName);

  Btn := F.TabCloseButton(0);
  if Btn <> nil then
  begin
    F.actNewExecute(nil);
    Pump;
    for i := 1 to 5 do
    begin
      Btn.Click;
      Pump;
    end;
    CheckEq('and neither does the close button', Lone,
      F.ActiveTab.Document.DisplayName);
  end;

  { Numbering still tells two open documents apart, which is what it is for. }
  F.actNewExecute(nil);
  Pump;
  Taken := F.ActiveTab.Document.DisplayName;
  Check('a second document gets a name of its own', Taken <> Lone);

  { And the number it had is free again once it closes. }
  F.actCloseTabExecute(nil);
  Pump;
  F.actNewExecute(nil);
  Pump;
  CheckEq('a number goes back into the pool when its document closes',
    Taken, F.ActiveTab.Document.DisplayName);

  while F.TabCount > 1 do F.CloseActiveTab(True);
  Pump;
end;

{ A binary that fails to reopen as text must still be the binary.

  LoadFromFile used to clear FIsBinary and FBytes on its way into the text
  branch, and that branch can raise: a decode it cannot do leaves the document
  claiming not to be binary, with no bytes, and the hex dump still sitting in
  the buffer.  SaveToFile believed all three and took the text path, writing
  the dump -- in ASCII -- over the file.  Twenty bytes in, a hundred and sixty
  two out.

  Both routes that reach it are here: Open as Text, which a UTF-32 BOM makes
  fail, and Reopen with Encoding, which fails on any binary. }
procedure TestBinarySurvivesFailedDecode(F: TLedMainForm);
var
  Doc: TLedDocument;
  Path, Raw, OnDisk: string;
  St: TFileStream;
  Raised: Boolean;

  function FileBytes(const AName: string): string;
  var S2: TFileStream;
  begin
    Result := '';
    S2 := TFileStream.Create(AName, fmOpenRead);
    try
      SetLength(Result, S2.Size);
      if S2.Size > 0 then S2.Read(Result[1], S2.Size);
    finally
      S2.Free;
    end;
  end;

begin
  Say('a binary survives a decode that fails');

  { A UTF-32 BOM, then bytes that make it plainly binary.  The BOM is what
    Open as Text cannot get past. }
  Path := TempName('failed-decode.bin');
  Raw := #$FF#$FE#$00#$00 + 'MZ'#0#0#1#2#3#0#0'hello'#0#0;
  St := TFileStream.Create(Path, fmCreate);
  try St.Write(Raw[1], Length(Raw)); finally St.Free; end;

  Doc := F.ActiveTab.Document;
  Doc.LoadFromFile(Path);
  Pump;
  Check('it opens as a dump', Doc.IsBinary);
  CheckEqInt('with its bytes', Length(Raw), Doc.HexSize);

  Raised := False;
  try
    Doc.OpenAsText;
  except
    on E: Exception do Raised := True;
  end;
  Pump;
  Check('Open as Text fails on it', Raised);
  Check('and it is still a binary afterwards', Doc.IsBinary);
  CheckEqInt('with its bytes still there', Length(Raw), Doc.HexSize);

  { The one that matters: what a save writes now. }
  Doc.SaveToFile(Path);
  OnDisk := FileBytes(Path);
  CheckEq('and saving writes the file, not the dump', Raw, OnDisk);

  { The other route in. }
  Raised := False;
  try
    Doc.Reload('utf-8');
  except
    on E: Exception do Raised := True;
  end;
  Pump;
  Check('Reopen with Encoding fails too', Raised);
  Check('and leaves it a binary', Doc.IsBinary);
  Doc.SaveToFile(Path);
  CheckEq('and it still saves the file', Raw, FileBytes(Path));

  DeleteFile(Path);
end;

{ Asking for a pane shows that pane, and only that pane.

  ShowPane docks what was asked for and then, if the edge still does not
  report itself visible, used to call SetEdgeVisible -- which shows "the first
  pane registered for the edge".  That is the same pane only when the first
  one happens to be the one wanted: clicking Preview, with Symbols registered
  first on the right, opened Symbols too.  One button, two panes.

  Read the second half of this before trusting the first.  The fallback only
  runs when the edge does not report itself visible in the instant after the
  dock, and here it always does -- so these checks pass on the old code as
  well, and putting the old call back does not fail them.  They say what the
  behaviour should be; they do not reproduce the report.

  What is reproducible is the hazard underneath, and that is checked
  separately below: SetEdgeVisible opens the edge's first pane whatever it is
  asked about, which is why nothing that wants a particular pane may go
  through it. }
procedure TestShowPaneShowsThatPane(F: TLedMainForm);
var
  i: Integer;
  { Every pane on the right-hand edge.  The list has to be all of them: the
    check hides the edge's panes and then asks which one showing the edge
    opens, and a pane left off the list is a pane left showing. }
  Right: array[0..3] of string = ('symbols', 'preview', 'notebook', 'debug');
begin
  Say('showing a pane shows that pane');

  for i := 0 to High(Right) do
  begin
    F.Dock.HidePane(Right[i]);
    Pump;
  end;
  Pump;

  { The second one registered for the edge, so a fallback to the first would
    be visible as a pane nobody asked for. }
  F.Dock.ShowPane('preview');
  Pump; Pump;
  Check('the pane asked for is open', F.Dock.PaneVisible('preview'));
  Check('and the edge''s first pane was not opened as well',
    not F.Dock.PaneVisible('symbols'));
  Check('nor the third', not F.Dock.PaneVisible('debug'));

  { And from cold on the last one registered, which is the furthest from
    whatever SetEdgeVisible would have picked. }
  F.Dock.HidePane('preview');
  Pump; Pump;
  F.Dock.TogglePane('debug');
  Pump; Pump;
  Check('toggling the last pane on an empty edge opens it',
    F.Dock.PaneVisible('debug'));
  Check('and nothing else', (not F.Dock.PaneVisible('symbols')) and
    (not F.Dock.PaneVisible('preview')));

  F.Dock.HidePane('debug');
  Pump;

  { The hazard itself.  SetEdgeVisible is not pane-specific and cannot be:
    "show this edge" has no pane in it.  Asked to show the right-hand edge it
    opens Symbols -- the first registered there -- and would do so no matter
    which pane the click had been on. }
  for i := 0 to High(Right) do
  begin
    F.Dock.HidePane(Right[i]);
    Pump;
  end;
  Pump;
  F.Dock.EdgeVisible[ledRight] := True;
  Pump; Pump;
  Check('showing an edge opens its first pane, whichever was wanted',
    F.Dock.PaneVisible('symbols'));
  Check('which is why ShowPane must not go through it',
    not F.Dock.PaneVisible('debug'));

  for i := 0 to High(Right) do
  begin
    F.Dock.HidePane(Right[i]);
    Pump;
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

{ The clipboard is left alone while a menu is open.

  Asking whether it holds text is a synchronous X round trip on gtk2, and the
  LCL waits for the answer by running the event loop -- so asking it from the
  action-update pass, which runs on every idle including every idle while a
  menu is open, re-enters gtk's menu handling from inside the menu.  Rows stay
  lit behind the pointer, and sweeping the pointer up and down an open submenu
  is an access violation inside gtk with none of LED's frames near it.
  TLedMainForm.ClipboardHasText carries the stack it dies on.

  Reproduced with the pointer driven by XTest over the Open Recent submenu and
  another client owning the selection: nine runs out of nine died before the
  guard, none of eleven after.  The selection owner is what two earlier hunts
  were missing -- a clipboard nobody owns answers with no round trip at all,
  so on a bare Xvfb this cannot happen.

  The check asserts the number of times LED has actually asked, because a
  round trip is what crashes: a flag holding the right value would say nothing
  about whether the question went out.  Removing the guard fails it. }
procedure TestClipboardUnderGrab(F: TLedMainForm);
const
  { Longer than the poll's own cache, which would otherwise be the reason
    nothing was asked, and the check would pass with the guard removed. }
  PastTheCache = 300;
var
  V: TLedEdit;
  Before, i: Integer;
begin
  Say('the clipboard while a menu is open');
  if (F.ActiveTab = nil) or (F.ActiveTab.ActiveView = nil) then
  begin
    Say('  (no document; skipped)');
    Exit;
  end;
  V := F.ActiveTab.ActiveView;

  Pump;
  F.ClipboardHasText(V);
  Sleep(PastTheCache);

  Before := F.ClipboardPolls;
  F.ClipboardHasText(V);
  CheckEqInt('with nothing grabbing, the clipboard is asked',
    Before + 1, F.ClipboardPolls);

  if not LedToolkitGrabTake(F) then
  begin
    Say('  (this toolkit has no grab a check can raise; skipped)');
    Exit;
  end;
  try
    Check('a grab is visible while it is held', LedToolkitGrabActive);
    Sleep(PastTheCache);
    Before := F.ClipboardPolls;
    for i := 1 to 20 do
      F.ClipboardHasText(V);
    CheckEqInt('and while it is held the clipboard is not asked once',
      Before, F.ClipboardPolls);
  finally
    LedToolkitGrabRelease(F);
  end;

  Check('the grab is gone once it is given back', not LedToolkitGrabActive);
  Before := F.ClipboardPolls;
  F.ClipboardHasText(V);
  CheckEqInt('and asking resumes', Before + 1, F.ClipboardPolls);
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

{ Reaching TControl.MouseDown from outside the control.

  Protected members are open to code inside a method of a descendant, so a
  descendant with a class method is the whole trick.  Worth the four lines:
  without it a check can only ask the mouse-action tables what they would do,
  and the Ctrl+drag bug was not in the tables -- the entry was correct, it was
  just in the list SynEdit asks last. }
type
  TLedMousePoke = class(TLedEdit)
  public
    class procedure Press(AView: TLedEdit; AShift: TShiftState; X, Y: Integer);
    class procedure Move(AView: TLedEdit; AShift: TShiftState; X, Y: Integer);
    class procedure Release(AView: TLedEdit; AShift: TShiftState; X, Y: Integer);
    class procedure Drag(AView: TLedEdit; AShift: TShiftState;
      X1, Y1, X2, Y2, ASteps: Integer);
  end;

{ The same trick for the keyboard.  Key comes back as the handler left it,
  so a check can tell a key that was taken from one that fell through. }
type
  TLedKeyPoke = class(TLedEdit)
  public
    class procedure Press(AView: TLedEdit; var AKey: Word;
      AShift: TShiftState);
    class procedure Double(AView: TLedEdit);
  end;

class procedure TLedKeyPoke.Press(AView: TLedEdit; var AKey: Word;
  AShift: TShiftState);
begin
  TLedKeyPoke(AView).KeyDown(AKey, AShift);
end;

{ The same, for the value panel: its Return and Escape are a form's KeyDown,
  which KeyPreview brings there from whichever control has the focus. }
type
  TLedPanelPoke = class(TLedBJValuePopup)
  public
    class procedure Press(AForm: TLedBJValuePopup; var AKey: Word;
      AShift: TShiftState);
  end;

class procedure TLedPanelPoke.Press(AForm: TLedBJValuePopup; var AKey: Word;
  AShift: TShiftState);
begin
  TLedPanelPoke(AForm).KeyDown(AKey, AShift);
end;

class procedure TLedKeyPoke.Double(AView: TLedEdit);
begin
  TLedKeyPoke(AView).DblClick;
end;

{ The notebook prose control's wheel and double click are protected, and
  what is worth checking is that they are routed at all -- so they are
  reached the way every other protected part is in here. }
type
  TLedProsePoke = class(TLedNBProse)
  public
    class function Wheel(AProse: TLedNBProse; ADelta: Integer): Boolean;
    class procedure DoubleClick(AProse: TLedNBProse);
  end;

class function TLedProsePoke.Wheel(AProse: TLedNBProse;
  ADelta: Integer): Boolean;
begin
  Result := TLedProsePoke(AProse).DoMouseWheel([], ADelta, Point(10, 10));
end;

class procedure TLedProsePoke.DoubleClick(AProse: TLedNBProse);
begin
  TLedProsePoke(AProse).DblClick;
end;

class procedure TLedMousePoke.Press(AView: TLedEdit; AShift: TShiftState;
  X, Y: Integer);
begin
  TLedMousePoke(AView).MouseDown(mbLeft, AShift, X, Y);
end;

class procedure TLedMousePoke.Move(AView: TLedEdit; AShift: TShiftState;
  X, Y: Integer);
begin
  TLedMousePoke(AView).MouseMove(AShift, X, Y);
end;

class procedure TLedMousePoke.Release(AView: TLedEdit; AShift: TShiftState;
  X, Y: Integer);
begin
  TLedMousePoke(AView).MouseUp(mbLeft, AShift, X, Y);
end;

{ A drag the way a mouse makes one: many small moves, each with the message
  queue drained so the repaint it triggers actually happens.  One Press, one
  Move and one Release exercises the selection arithmetic but never the paint
  that runs *during* a selection, which is where a reported crash lived. }
class procedure TLedMousePoke.Drag(AView: TLedEdit; AShift: TShiftState;
  X1, Y1, X2, Y2, ASteps: Integer);
var
  i, X, Y: Integer;
begin
  if ASteps < 1 then ASteps := 1;
  Press(AView, AShift, X1, Y1);
  Application.ProcessMessages;
  for i := 1 to ASteps do
  begin
    X := X1 + ((X2 - X1) * i) div ASteps;
    Y := Y1 + ((Y2 - Y1) * i) div ASteps;
    Move(AView, AShift, X, Y);
    Application.ProcessMessages;
  end;
  Release(AView, AShift, X2, Y2);
  Application.ProcessMessages;
end;

{ Which mouse command a gesture resolves to, through SynEdit's own tables and
  in the order MouseDown consults them: the selection list only when the press
  landed in a selection, then the text list, then the global one. }
function LedGestureCommand(AView: TLedEdit;
  AShift: TShiftState): TSynEditorMouseCommand;
var
  Info: TSynEditMouseActionInfo;
  A: TSynEditMouseAction;
begin
  Result := emcNone;
  FillChar(Info, SizeOf(Info), 0);
  Info.Button := mbXLeft;
  Info.Shift := AShift;
  Info.CCount := ccSingle;
  Info.Dir := cdDown;
  A := AView.MouseTextActions.FindCommand(Info);
  if A = nil then
    A := AView.MouseActions.FindCommand(Info);
  if A <> nil then Result := A.Command;
end;

procedure TestColumnSelection(F: TLedMainForm);
var
  V: TLedEdit;
  Doc: TLedDocument;
  Found: Boolean;
  i: Integer;
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
  { First, the gestures.  Everything below this drives SelectionMode straight
    from code, which is how Ctrl+drag stayed broken while the column feature
    was covered: the machinery worked, and nothing asked whether a mouse
    gesture ever reached it. }
  CheckEqInt('a plain drag starts an ordinary selection',
    Ord(emcStartSelections), Ord(LedGestureCommand(V, [])));
  CheckEqInt('and Shift+drag extends one',
    Ord(emcStartSelections), Ord(LedGestureCommand(V, [ssShift])));
  CheckEqInt('Ctrl+drag starts a column selection',
    Ord(emcStartColumnSelections), Ord(LedGestureCommand(V, [ssCtrl])));
  CheckEqInt('and Ctrl+Shift+drag extends one',
    Ord(emcStartColumnSelections),
    Ord(LedGestureCommand(V, [ssCtrl, ssShift])));
  CheckEqInt('Alt+drag still does too, for SynEdit habits',
    Ord(emcStartColumnSelections), Ord(LedGestureCommand(V, [ssAlt])));

  { And end to end: a real press, move and release with Ctrl held has to
    leave a rectangle behind, not a stream selection. }
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  TLedMousePoke.Press(V, [ssCtrl], V.Gutter.Width + 2 + 4 * V.CharWidth,
    0 * V.LineHeight + 2);
  TLedMousePoke.Move(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  TLedMousePoke.Release(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  Pump;
  Check('dragging with Ctrl held leaves a column selection',
    LedHasColumnSelection(V));
  CheckEq('covering the rectangle it was dragged over',
    '1111' + LineEnding + '2222' + LineEnding + '3333', V.SelText);

  { A plain drag must still be an ordinary selection, or the fix traded one
    broken gesture for another. }
  V.SelectionMode := smNormal;
  LedClearSelection(V);
  Pump;
  TLedMousePoke.Press(V, [], V.Gutter.Width + 2 + 4 * V.CharWidth, 2);
  TLedMousePoke.Move(V, [], V.Gutter.Width + 2 + 8 * V.CharWidth,
    1 * V.LineHeight + 2);
  TLedMousePoke.Release(V, [], V.Gutter.Width + 2 + 8 * V.CharWidth,
    1 * V.LineHeight + 2);
  Pump;
  Check('a plain drag is not a column selection',
    not LedHasColumnSelection(V));

  { The whole gesture, end to end, through the commands the menus call:
    Ctrl+drag a rectangle, Copy, put the caret somewhere else, Paste.  The
    checks below drive LedPasteColumn directly with a hand-built selection,
    which is not the path a user takes -- an access violation was reported
    here that none of them saw. }
  V.SelectionMode := smNormal;
  LedClearSelection(V);
  V.CaretXY := Point(1, 1);
  Pump;
  TLedMousePoke.Press(V, [ssCtrl], V.Gutter.Width + 2 + 4 * V.CharWidth, 2);
  TLedMousePoke.Move(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  TLedMousePoke.Release(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  Pump;
  LedCopy(V);
  Pump;
  Check('a dragged rectangle copies', Clipboard.AsText <> '');

  LedClearSelection(V);
  V.SelectionMode := smNormal;
  V.CaretXY := Point(1, 1);
  Pump;
  LedPaste(V);
  Pump;
  CheckEq('and pastes back as a rectangle at the caret',
    '1111aaaa1111', V.Lines[0]);
  CheckEq('on the second line too', '2222bbbb2222', V.Lines[1]);
  V.Undo;
  Pump;
  CheckEq('and undoes in one step', 'aaaa1111', V.Lines[0]);

  { And pasting a rectangle *over* a dragged rectangle, which is the case
    that has to clear the block before inserting. }
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  Pump;
  TLedMousePoke.Press(V, [ssCtrl], V.Gutter.Width + 2 + 0 * V.CharWidth, 2);
  TLedMousePoke.Move(V, [ssCtrl], V.Gutter.Width + 2 + 4 * V.CharWidth,
    2 * V.LineHeight + 2);
  TLedMousePoke.Release(V, [ssCtrl], V.Gutter.Width + 2 + 4 * V.CharWidth,
    2 * V.LineHeight + 2);
  Pump;
  LedPaste(V);
  Pump;
  Check('pasting over a dragged rectangle leaves the document intact',
    V.Lines.Count >= 4);
  V.Undo;
  Pump;

  V.SelectionMode := smNormal;
  LedClearSelection(V);
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

  { --- what the earlier checks never asked --------------------------------

    Deleting a rectangle and pasting one explicitly were covered; copying
    one, pasting over one, and typing over one were not, and those are what
    the feature is actually used for. }

  V.Lines.Text := 'aaaa1111' + LineEnding + 'bbbb2222' + LineEnding +
                  'cccc3333' + LineEnding + 'dd';
  V.BlockBegin := Point(5, 1);
  V.BlockEnd := Point(9, 3);
  V.SelectionMode := smColumn;

  Clipboard.AsText := '';
  V.CopyToClipboard;
  CheckEq('copying a rectangle puts its rows on the clipboard',
    '1111' + LineEnding + '2222' + LineEnding + '3333',
    Trim(Clipboard.AsText));

  { Typing with a rectangle selected replaces it on every line. }
  V.BlockBegin := Point(5, 1);
  V.BlockEnd := Point(9, 3);
  V.SelectionMode := smColumn;
  V.CommandProcessor(ecChar, 'Z', nil);
  Pump;
  CheckEq('typing over a rectangle replaces it on the first line',
    'aaaaZ', V.Lines[0]);
  CheckEq('and on the last', 'ccccZ', V.Lines[2]);

  V.Undo;
  CheckEq('and undoes in one step', 'aaaa1111', V.Lines[0]);

  { Pasting over a rectangle should replace it, not insert beside it. }
  V.Lines.Text := 'aaaa1111' + LineEnding + 'bbbb2222' + LineEnding +
                  'cccc3333';
  Clipboard.AsText := 'XX' + LineEnding + 'YY' + LineEnding + 'ZZ';
  V.BlockBegin := Point(5, 1);
  V.BlockEnd := Point(9, 3);
  V.SelectionMode := smColumn;
  LedPasteColumn(V);
  Pump;
  CheckEq('pasting over a rectangle replaces the first row', 'aaaaXX', V.Lines[0]);
  CheckEq('and the last', 'ccccZZ', V.Lines[2]);

  { A plain Ctrl+V of text that was column-copied should come back as a
    column, not as three inserted lines.  This is the part medit got wrong
    often enough to be remembered for it. }
  V.Lines.Text := 'aaaa1111' + LineEnding + 'bbbb2222' + LineEnding +
                  'cccc3333';
  V.BlockBegin := Point(5, 1);
  V.BlockEnd := Point(9, 3);
  V.SelectionMode := smColumn;
  V.CopyToClipboard;
  V.SelectionMode := smNormal;
  V.CaretXY := Point(1, 1);
  LedPaste(V);
  Pump;
  CheckEq('a column copy pastes back as a column', '1111aaaa1111', V.Lines[0]);
  CheckEq('on the second line too', '2222bbbb2222', V.Lines[1]);
  CheckEqInt('without inserting any lines', 3, V.Lines.Count);

  { Backspace and Delete take a character from every line of the block. }
  V.Lines.Text := 'aaXbb' + LineEnding + 'ccXdd' + LineEnding + 'eeXff';
  V.BlockBegin := Point(4, 1);
  V.BlockEnd := Point(4, 3);
  V.SelectionMode := smColumn;
  V.CommandProcessor(ecDeleteLastChar, #0, nil);
  Pump;
  CheckEq('backspace over a zero-width block takes one from each line',
    'aabb', V.Lines[0]);
  CheckEq('including the last', 'eeff', V.Lines[2]);
  V.Undo;
  CheckEq('and undoes in one step', 'aaXbb', V.Lines[0]);

  { A rectangle can be made from the keyboard, not only with the mouse.
    SynEdit binds Alt+Shift, which several Linux window managers eat, so
    Ctrl+Shift is bound too -- this checks the keystroke reaches a command
    rather than falling through to plain cursor movement. }
  Found := False;
  for i := 0 to V.Keystrokes.Count - 1 do
    if (V.Keystrokes[i].Command = ecColSelDown) and
       (V.Keystrokes[i].Shift = [ssCtrl, ssShift]) then Found := True;
  Check('Ctrl+Shift+Down extends a rectangle', Found);

  { Ctrl and the left button start a rectangle, as medit did.

    This used to search MouseActions for an entry with emcStartColumnSelections
    and ssCtrl, find it, and pass -- for as long as the gesture did not work at
    all.  The entry was real; it was in the list MouseDown consults last, and
    the default stream-selection entry in the list it consults first matched a
    Ctrl+press because its mask names only Shift and Alt.  So ask what the
    gesture resolves to instead of whether a row exists somewhere. }
  CheckEqInt('Ctrl and the left button start a rectangle',
    Ord(emcStartColumnSelections), Ord(LedGestureCommand(V, [ssCtrl])));
  CheckEqInt('and a bare left button still does not',
    Ord(emcStartSelections), Ord(LedGestureCommand(V, [])));

  { Pasting rows of unequal length over a rectangle: each row replaces the
    block on its own line, so the text after it shifts by that row's own
    width, not by a single amount for the whole block. }
  V.Lines.Text := 'aa[..]zz' + LineEnding +
                  'bb[..]yy' + LineEnding +
                  'cc[..]xx';
  Clipboard.AsText := 'LONGER' + LineEnding + 'M' + LineEnding + 'MID';
  V.BlockBegin := Point(3, 1);
  V.BlockEnd := Point(7, 3);      { the four characters "[..]" on each line }
  V.SelectionMode := smColumn;
  LedPasteColumn(V);
  Pump;
  CheckEq('a longer row pushes the rest right', 'aaLONGERzz', V.Lines[0]);
  CheckEq('a shorter one pulls it left', 'bbMyy', V.Lines[1]);
  CheckEq('and each line shifts by its own width', 'ccMIDxx', V.Lines[2]);
  V.Undo;
  Pump;
  CheckEq('one undo puts all three back', 'aa[..]zz', V.Lines[0]);

  { --- edge cases that crash rather than misbehave ----------------------- }

  { An empty document: LedPasteColumn walks Lines[Count - 1] to extend the
    file, which is Lines[-1] when there are none. }
  V.Lines.Clear;
  Clipboard.AsText := 'AA' + LineEnding + 'BB';
  V.CaretXY := Point(1, 1);
  LedPasteColumn(V);
  Pump;
  Check('a column paste into an empty document survives', V.Lines.Count >= 1);

  { A rectangle running past the last line. }
  V.Lines.Text := 'one' + LineEnding + 'two';
  V.BlockBegin := Point(2, 1);
  V.BlockEnd := Point(3, 2);
  V.SelectionMode := smColumn;
  Clipboard.AsText := 'X' + LineEnding + 'Y' + LineEnding + 'Z' + LineEnding + 'W';
  LedPasteColumn(V);
  Pump;
  Check('a paste longer than the document extends it', V.Lines.Count >= 4);

  { Typing over a rectangle whose lines are shorter than the column. }
  V.Lines.Text := 'aaaaaa' + LineEnding + 'bb' + LineEnding + 'cccccc';
  V.BlockBegin := Point(5, 1);
  V.BlockEnd := Point(5, 3);
  V.SelectionMode := smColumn;
  V.CommandProcessor(ecChar, 'Q', nil);
  Pump;
  Check('typing into a ragged rectangle pads the short line',
    Length(V.Lines[1]) >= 5);
  CheckEq('and lands at the column on the long ones', 'aaaaQaa', V.Lines[0]);

  { Repeated commands through the hook, then undo, then more editing --
    the sequence most likely to leave SynEdit's state inconsistent. }
  V.Lines.Text := 'xxxx' + LineEnding + 'yyyy' + LineEnding + 'zzzz';
  V.BlockBegin := Point(2, 1);
  V.BlockEnd := Point(2, 3);
  V.SelectionMode := smColumn;
  V.CommandProcessor(ecChar, '1', nil);
  V.CommandProcessor(ecChar, '2', nil);
  V.CommandProcessor(ecDeleteLastChar, #0, nil);
  Pump;
  V.Undo; V.Undo; V.Undo;
  Pump;
  V.SelectionMode := smNormal;
  V.CaretXY := Point(1, 1);
  V.CommandProcessor(ecChar, 'k', nil);
  Pump;
  Check('the editor still edits after a run of column commands',
    Pos('k', V.Lines[0]) > 0);

  Found := False;
  for i := 0 to V.Keystrokes.Count - 1 do
    if (V.Keystrokes[i].Command = ecColSelDown) and
       (V.Keystrokes[i].Shift = [ssAlt, ssShift]) then Found := True;
  Check('and SynEdit''s Alt+Shift+Down still does', Found);

  V.Lines.Text := 'aaaa' + LineEnding + 'bbbb' + LineEnding + 'cccc';
  V.CaretXY := Point(2, 1);
  V.CommandProcessor(ecColSelDown, #0, nil);
  V.CommandProcessor(ecColSelRight, #0, nil);
  Pump;
  Check('and doing so makes a column selection',
    LedHasColumnSelection(V));

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

    { An unset font preference used to show and then save the literal
      "Monospace 10", which is not an installed family on Windows and made
      GDI fall back to a pixelated raster font.  It must resolve to this
      platform's real default instead, and Apply must not turn around and
      write the bad literal back. }
    LedPrefs.SetStr('Editor/font', '');
    Dlg.LoadFromPrefs;
    Check('an unset font preference shows the platform default, not "Monospace"',
      Dlg.FontCaption('Editor/font') = Format('%s %d',
        [LedDefaultFontName, LedDefaultFontSize]));
    Dlg.ApplyToPrefs;
    { Against the resolved default rather than the literal string.  "Monospace
      10" is only the wrong answer where it is not also the platform's own --
      on a Linux desktop it is exactly what should be written, so the string
      comparison asserted the opposite of the truth here and failed as soon as
      the default resolved to it.  Comparing against what this platform
      actually resolves to keeps the Windows regression covered, where the
      default is "Consolas 10" and the bad literal still fails. }
    Check('and applying it persists that default rather than a literal',
      LedPrefs.GetStr('Editor/font', '') = Format('%s %d',
        [LedDefaultFontName, LedDefaultFontSize]));

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

    { medit had eight preference pages and LED had three, which is the gap
      this counts.  Plugins are not one of them: LED has no dynamic plugin
      loading to configure. }
    CheckEqInt('every preference page is present', 6, Dlg.PageCount);
    Check('and the list pages built their contents', Dlg.ListPagesReady);

    { Laid out before the dialog has its real size, so every anchor that
      measured a gap to the right or bottom edge measured the wrong one:
      OK, Cancel and Apply sat off the right of the window where they could
      not be clicked, and the pages' edits ran past their right border.
      Nothing may stick out of its parent, on any page. }
    Dlg.Show;
    Pump;
    for Before := 0 to Dlg.PageCount - 1 do
    begin
      Dlg.ShowPage(Before);
      Pump;
      CheckEqInt('page ' + IntToStr(Before + 1) + ' fits inside the dialog',
        0, Dlg.WorstOverflow);
    end;
    Dlg.Hide;

    { A filter edited on the page has to survive the trip through prefs.ini,
      because that is the whole point of the page. }
    Dlg.AddFilterRow('globs:*.selftest', 'indent-width: 7');
    Dlg.ApplyToPrefs;
    LedFilters.LoadFromPrefs;
    Check('a filter added on the page is saved',
      LedFilters.FindByDefinition('globs:*.selftest') <> nil);

    { The same rule twice is one rule.  Until the sandbox above worked, every
      self-test run appended this scratch rule to the developer's own
      prefs.ini; a hundred copies had piled up, and that is what a filters
      page full of repeated rows was.  Reading the file heals it. }
    Dlg.AddFilterRow('globs:*.selftest', 'indent-width: 7');
    Dlg.ApplyToPrefs;
    LedFilters.LoadFromPrefs;
    After := 0;
    for Before := 0 to LedFilters.Count - 1 do
      if LedFilters[Before].Definition = 'globs:*.selftest' then Inc(After);
    CheckEqInt('and a rule repeated in prefs.ini loads once', 1, After);
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
  ToolPath: string;
  L: TStringList;

  { True when a menu, or any submenu of it, offers ACaption. }
  function MenuHas(AItem: TMenuItem; const ACaption: string): Boolean;
  var
    n: Integer;
  begin
    Result := False;
    if AItem = nil then Exit;
    for n := 0 to AItem.Count - 1 do
      if (StringReplace(AItem[n].Caption, '&', '', [rfReplaceAll]) = ACaption)
         or MenuHas(AItem[n], ACaption) then Exit(True);
  end;
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
  { The tools ported from medit have to reach the menus, not just parse.
    PopulateToolMenu filters by language and by file name, so a tool with a
    files= or langs= line that does not match is loaded and then invisible --
    which is indistinguishable from not shipping it. }
  F.AddTab(F.Documents.NewDocument);
  Pump;
  ToolPath := TempName('paper.tex');
  L := TStringList.Create;
  try
    L.Add('\\documentclass{article}');
    L.SaveToFile(ToolPath);
  finally
    L.Free;
  end;
  F.ActiveTab.Document.LoadFromFile(ToolPath);
  Pump;
  F.PopulateToolMenu;
  Check('LaTeX reaches the Tools menu for a .tex file',
    MenuHas(F.miToolList, 'LaTeX'));
  Check('and so does PdfLaTeX', MenuHas(F.miToolList, 'PdfLaTeX'));
  Check('and Make PDF', MenuHas(F.miToolList, 'Make PDF'));
  Check('and View DVI', MenuHas(F.miToolList, 'View DVI'));
  Check('BibTeX is named for what it runs, not "LaTeX" twice',
    MenuHas(F.miToolList, 'BibTeX'));

  F.PopulateContextTools;
  Check('DVI Forward Search is on the context menu, not the Tools menu',
    MenuHas(F.miCtxTools, 'DVI Forward Search'));
  Check('and it is not on the Tools menu',
    not MenuHas(F.miToolList, 'DVI Forward Search'));

  { A C file gets the header switch and none of the LaTeX ones. }
  F.ActiveTab.Document.SaveToFile(TempName('unit.c'));
  Pump;
  F.PopulateToolMenu;
  F.PopulateContextTools;
  Check('Switch Header and Implementation appears for C',
    MenuHas(F.miCtxTools, 'Switch Header and Implementation'));
  Check('and LaTeX does not', not MenuHas(F.miToolList, 'LaTeX'));

  F.ActiveTab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  DeleteFile(ToolPath);
  DeleteFile(TempName('unit.c'));

end;

type
  { Catches what the browser asks to open, so a double-click can be checked
    without the main form actually opening a tab for it.  A class because
    TLedOpenFileEvent is a method pointer. }
  TBrowserOpenCatcher = class
    Last: string;
    procedure Note(const AFileName: string);
  end;

procedure TBrowserOpenCatcher.Note(const AFileName: string);
begin
  Last := AFileName;
end;

procedure TestFileBrowser(F: TLedMainForm);
var
  Fresh: TLedFileBrowser;
  TabForIcon: TLedTab;
  HintRect: TRect;
  Root, Node: TTreeNode;
  RootRaised, BrowseDir, Names, Kinds, LinkDir, LinkPath: string;
  EditH, i, x, Tabs0, Tabs1: Integer;
  SavedOpen: TLedOpenFileEvent;
  Catcher: TBrowserOpenCatcher;
  Pane: TLedPaneForm;
  Host: TWinControl;
  Hdr: TAnchorDockHeader;
  L: TStringList;
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
  { A widget is measured as it is built, and what it measures against is its
    own style font -- not the TFont the LCL may put on it later, which for an
    entry it never does.  Built before the scaled style was installed, a
    GtkEntry asked for the height of 21-pixel text and kept that answer: a
    34-pixel edit box holding 42-pixel text, in the debug pane's watch and
    command rows and anywhere else an edit is autosized.  Asked against the
    scaled style it comes out 57.

    Checked on the debug pane because that is where it was reported, and
    against the font rather than a constant, so it still means something at
    any scale. }
  F.Dock.ShowPane('debug');
  Pump;
  EditH := 0;
  for i := 0 to F.DebugPane.ControlCount - 1 do
    if F.DebugPane.Controls[i] is TCustomEdit then
      EditH := F.DebugPane.Controls[i].Height;
  Check('an autosized edit is tall enough for the text in it',
    EditH >= LedScale96(16));
  Say(Format('    debug pane edit box is %d px tall, floor %d',
    [EditH, LedScale96(16)]));
  { Put the pane back: the checks further on open panes of their own and
    expect the dock to be where they left it. }
  F.Dock.HidePane('debug');
  Pump;

  { The glyph and the button under it came apart twice over.  First the
    glyphs were drawn at a fixed sixteen pixels while the buttons scaled with
    the pane -- four big empty buttons.  Then the buttons were given
    LedScale96 sizes as well, which the startup sweep scaled a second time and
    put them 253 pixels apart.  Asserted on the browser the application built,
    not one made here: the sweep is what scales the buttons, and it has long
    since run by the time a test can create its own. }
  Check('a navigation glyph is drawn at the display''s scale',
    F.Browser.NavGlyphSize >= LedScale96(14));
  Check('and fits inside the button it sits on',
    (F.Browser.NavButtonSize > 0) and
    (F.Browser.NavGlyphSize <= F.Browser.NavButtonSize));
  { Not scaled twice: a button holding a LedScale96(16) glyph should be a
    little bigger than it, not three times over. }
  Check('and the button is not scaled twice over',
    F.Browser.NavButtonSize < LedScale96(16) * 3);
  Say(Format('    nav: %d px glyph on a %d px button',
    [F.Browser.NavGlyphSize, F.Browser.NavButtonSize]));

  { One tree, holding folders and files together.  It replaced a folder tree
    over a file list, so what used to be checked here -- that the splitter
    resized the list and not the filter row -- has nothing left to be about. }
  { The pane headers: a name in small capitals, in the desktop's blue. }
  { The header belongs to the host site a pane is docked into, not to the
    pane, so it is reached by walking up. }
  Pane := F.Dock.FindPane('files');
  Hdr := nil;
  if Pane <> nil then
  begin
    Host := Pane.Parent;
    while (Host <> nil) and (not (Host is TAnchorDockHostSite)) do
      Host := Host.Parent;
    if Host <> nil then Hdr := TAnchorDockHostSite(Host).Header;
  end;
  Check('the files pane has a header', Hdr <> nil);
  if Hdr <> nil then
  begin
    Check('whose caption is not empty, so there is something to shape',
      Trim(Hdr.Caption) <> '');
    CheckEq('and is upper-cased', UpperCase(Hdr.Caption), Hdr.Caption);
    { Against a real number rather than the form's, which reports 0 -- the
      LCL's way of saying "whatever the desktop uses" -- so "smaller than the
      form" compares 7 with 0 and means nothing. }
    Check('sized explicitly rather than inherited', Hdr.Font.Size > 0);
    Check('and set bold, which is what a smaller face needs back',
      fsBold in Hdr.Font.Style);
    CheckGt('and smaller than the nine points it derives from', Hdr.Font.Size,
      9);
    CheckEqInt('in the colour the dock mixes for it',
      ColorToRGB(LedHeaderCaptionColour), ColorToRGB(Hdr.Font.Color));
    { And that colour can actually be read off the band it sits on.  The
      desktop's selection blue is chosen to carry white text, not to be text
      on a dark grey, so on a dark desktop the first version of this was
      unreadable. }
    CheckGt('with enough contrast against the header band to read', 60,
      Abs(LedColourLuma(LedHeaderCaptionColour) -
          LedColourLuma(LedLiftColour(clForm, 12))));
  end;

  Check('the pane is a single tree', F.Browser.Tree <> nil);

  { And painted in the editor's colours rather than the desktop's, so the two
    halves of the window agree. }
  if F.ActiveView <> nil then
  begin
    CheckEqInt('the tree takes the editor''s page colour',
      ColorToRGB(F.ActiveView.Color), ColorToRGB(F.Browser.Tree.Color));
    CheckEqInt('and its text colour',
      ColorToRGB(F.ActiveView.Font.Color),
      ColorToRGB(F.Browser.Tree.Font.Color));
  end;
  Check('there is no splitter left to resize anything',
    F.Browser.SplitterTarget = nil);
  Check('and the tree shows files as well as folders',
    (otNonFolders in F.Browser.Tree.ObjectTypes) and
    (otFolders in F.Browser.Tree.ObjectTypes));
  Check('with the whole row selectable', F.Browser.Tree.RowSelect);
  Check('and a chevron beside anything that opens',
    F.Browser.Tree.ShowButtons);
  { Drawn by LED, not by the LCL: its three built-in signs are a themed box,
    a plus-minus and an outlined triangle, and a file tree wants a chevron. }
  Check('which LED draws itself', F.Browser.DrawsOwnChevron);
  Check('and pictures to put on the rows',
    (F.Browser.Tree.Images <> nil) and (F.Browser.Tree.Images.Count > 0));

  { The pictures are coloured, and the colour is the file kind's own.  Read
    off the built bitmap rather than from the table that produced it: an
    accent that never reaches the image list is a table nobody can see. }
  Check('a file kind has a colour of its own',
    LedIconAccent('filesource') <> clNone);
  { The toolbar is coloured too now, in the Tango palette medit's stock GTK
    icons came from.  This check used to assert the opposite -- that a
    toolbar stays one ink -- which was my judgement before seeing the two
    side by side. }
  Check('and so does a toolbar action', LedIconAccent('save') <> clNone);
  Check('with the kinds of action told apart by it',
    LedIconAccent('save') <> LedIconAccent('delete'));
  Check('while something with no natural colour keeps the caller''s',
    LedIconAccent('wrap') = clNone);
  CheckGt('the source icon is drawn in its blue', 0,
    IconColourCount('filesource', LedIconAccent('filesource')));
  CheckGt('and the pdf icon in its red', 0,
    IconColourCount('filepdf', LedIconAccent('filepdf')));
  CheckGt('and Save is drawn in its own blue', 0,
    IconColourCount('save', LedIconAccent('save')));

  { The fallback page too.  Drawn in the caller's ink it came out black, and
    the file tree is painted in the editor's colours -- so on a dark scheme
    an unrecognised file was a page-shaped hole.  A mid grey reads on both:
    checked against black and white rather than against a taste. }
  Check('the fallback page has a colour of its own',
    LedIconAccent('doc') <> clNone);
  CheckGt('which can be seen on a dark page', 30,
    Round(10 * LedContrastRatio(LedIconAccent('doc'), clBlack)));
  CheckGt('and on a light one', 30,
    Round(10 * LedContrastRatio(LedIconAccent('doc'), clWhite)));
  CheckGt('and it is drawn in it', 0,
    IconColourCount('doc', LedIconAccent('doc')));

  { One extension table, in Led.UI.Icons, so the tree and the tab headers
    cannot disagree about what a file is. }
  CheckEq('a C file is source', 'filesource', LedIconForFile('x.c'));
  CheckEq('a markdown file is its own kind', 'filemarkdown',
    LedIconForFile('README.md'));
  CheckEq('an object file is binary', 'filebinary', LedIconForFile('x.o'));
  CheckEq('and something unknown is a plain page', 'doc',
    LedIconForFile('x.zzz'));

  { And the tab header wears the same picture, which is the point of having
    one rule: a file looks the same in the tree and on its tab. }
  BrowseDir := TempName('tabicon');
  ForceDirectories(BrowseDir);
  L := TStringList.Create;
  try
    L.Add('int main(void) { return 0; }');
    L.SaveToFile(BrowseDir + PathDelim + 'tab.c');
  finally
    L.Free;
  end;
  TabForIcon := F.AddTab(F.Documents.OpenFile(BrowseDir + PathDelim + 'tab.c'));
  Pump;
  if TabForIcon <> nil then
  begin
    CheckEqInt('a C file''s tab wears the source icon',
      LedIconIndex('filesource'), TabForIcon.Sheet.ImageIndex);
    { And says where the file is, which the strip has no room for -- when the
      pointer is on the strip, and only then.

      The path used to be the page's hint.  A page fills the notebook and
      its children inherit the hint, so resting the pointer anywhere in the
      text raised a tooltip with the file's path over the line being read. }
    Check('the page itself carries no hint',
      (TabForIcon.Sheet.Hint = '') and (not TabForIcon.Sheet.ShowHint));
    HintRect := F.Notebook.TabRect(TabForIcon.Sheet.PageIndex);
    if Assigned(F.Notebook.OnMouseMove) then
      F.Notebook.OnMouseMove(F.Notebook, [],
        (HintRect.Left + HintRect.Right) div 2,
        (HintRect.Top + HintRect.Bottom) div 2);
    Pump;
    CheckEq('and hovering its tab carries the whole path',
      BrowseDir + PathDelim + 'tab.c', F.Notebook.Hint);
    Check('and the hint is switched on for it', F.Notebook.ShowHint);

    { Off the strip again -- below the tabs is the page, and the notebook's
      own hint must not linger there. }
    if Assigned(F.Notebook.OnMouseMove) then
      F.Notebook.OnMouseMove(F.Notebook, [], 4,
        HintRect.Bottom + (F.Notebook.Height - HintRect.Bottom) div 2);
    Pump;
    CheckEq('and nothing is left behind when the pointer leaves the strip',
      '', F.Notebook.Hint);
    Check('which is not the plain page it used to wear',
      TabForIcon.Sheet.ImageIndex <> LedIconIndex('doc'));

    { Unsaved changes still take the marked page: which file it is stays in
      the caption, and whether it is saved is what the icon answers. }
    TabForIcon.ActiveView.SelText := ' ';
    Pump;
    CheckEqInt('and a modified one shows that instead',
      LedIconIndex('docmodified'), TabForIcon.Sheet.ImageIndex);

    TabForIcon.Document.Master.Modified := False;
    F.CloseActiveTab(False);
    Pump;
  end;
  if DirectoryExists(BrowseDir) then DeleteDirectory(BrowseDir, False);

  { What is actually in the tree when it is pointed at a real folder.  The
    structure above says the pane is built to show files; this says it does,
    and that each one got the picture its extension asks for. }
  BrowseDir := TempName('browse');
  ForceDirectories(BrowseDir + PathDelim + 'sub');
  for x := 0 to 4 do
  begin
    L := TStringList.Create;
    try
      L.Add('x');
      case x of
        0: L.SaveToFile(BrowseDir + PathDelim + 'a.c');
        1: L.SaveToFile(BrowseDir + PathDelim + 'b.md');
        2: L.SaveToFile(BrowseDir + PathDelim + 'c.txt');
        3: L.SaveToFile(BrowseDir + PathDelim + 'd.pdf');
        4: L.SaveToFile(BrowseDir + PathDelim + 'e.o');
      end;
    finally
      L.Free;
    end;
  end;

  F.Browser.SetRoot(BrowseDir);
  Pump; Pump;
  Names := '';
  Kinds := '';
  Node := F.Browser.Tree.Items.GetFirstNode;
  while Node <> nil do
  begin
    if Node.Parent <> nil then
    begin
      { A directory's path comes back with a trailing separator, so the name
        has to be taken from the path with it stripped. }
      Names := Names + ExtractFileName(ExcludeTrailingPathDelimiter(
        F.Browser.Tree.GetPathFromNode(Node))) + ' ';
      Kinds := Kinds + IntToStr(Node.ImageIndex) + ' ';
    end;
    Node := Node.GetNext;
  end;
  Say('  (tree holds: ' + Names + ')');
  Say('  (icons:      ' + Kinds + ')');

  Check('the folder is in the tree: ' + Names, Pos('sub ', Names) > 0);

  { The root row carries the folder's name, not its whole path -- the crumb
    bar directly above it is where the path belongs. }
  Node := F.Browser.Tree.Items.GetFirstNode;
  Check('there is a root row', Node <> nil);
  if Node <> nil then
  begin
    CheckEq('which shows the folder name alone',
      ExtractFileName(ExcludeTrailingPathDelimiter(BrowseDir)), Node.Text);
    { Retitling it must not break the paths, which the tree builds from each
      node's own record rather than from what is written in it. }
    { A row says where it is and, for a file, how big. }
  CheckEq('a size reads as a person writes one', '1.5 KB',
    LedFormatSize(1536));
  CheckEq('and a small one stays in bytes', '12 bytes', LedFormatSize(12));

  Check('and the tree still knows where that row is',
      SameFileName(ExcludeTrailingPathDelimiter(
        F.Browser.Tree.GetPathFromNode(Node)), BrowseDir));
  end;

  { Double-clicking a file opens it.  Opening was the file list's job before
    the pane became one tree, and went with the list -- leaving the gesture
    doing nothing on the rows people double-click most.  Driven through the
    handler the LCL calls, with a file selected. }
  Catcher := TBrowserOpenCatcher.Create;
  SavedOpen := F.Browser.OnOpenFile;
  F.Browser.OnOpenFile := @Catcher.Note;
  try
    Node := F.Browser.Tree.Items.GetFirstNode;
    while (Node <> nil) and
          (ExtractFileName(F.Browser.Tree.GetPathFromNode(Node)) <> 'a.c') do
      Node := Node.GetNext;
    Check('a file row was found to click', Node <> nil);
    if Node <> nil then
    begin
      Node.Selected := True;
      Pump;
      if Assigned(F.Browser.Tree.OnDblClick) then
        F.Browser.Tree.OnDblClick(F.Browser.Tree);
      Pump;
      Check('double-clicking a file opens it: ' + Catcher.Last,
        Pos('a.c', Catcher.Last) > 0);
    end;
  finally
    F.Browser.OnOpenFile := SavedOpen;
    Catcher.Free;
  end;

  { Opening a file that is already open goes to its tab instead of reading it
    again -- which would be bad enough for the parse and worse for a file with
    unsaved edits in it. }
  Tabs0 := F.Notebook.PageCount;
  Node := F.Browser.Tree.Items.GetFirstNode;
  while (Node <> nil) and
        (ExtractFileName(F.Browser.Tree.GetPathFromNode(Node)) <> 'a.c') do
    Node := Node.GetNext;
  if Node <> nil then
  begin
    F.BrowserOpenFileNow(F.Browser.Tree.GetPathFromNode(Node));
    Pump;
    Tabs1 := F.Notebook.PageCount;
    CheckEqInt('opening a file adds one tab', Tabs0 + 1, Tabs1);

    { Edit it, then ask for it again the way a double-click does. }
    if F.ActiveView <> nil then
    begin
      F.ActiveView.CaretXY := Point(1, 1);
      F.ActiveView.SelText := 'EDITED ';
      Pump;
      Check('the document is now modified', F.ActiveTab.Document.Modified);

      F.BrowserOpenFileNow(F.Browser.Tree.GetPathFromNode(Node));
      Pump;
      CheckEqInt('asking for it again opens no second tab', Tabs1,
        F.Notebook.PageCount);
      Check('and the edit is still there',
        Pos('EDITED', F.ActiveView.Lines[0]) > 0);
      Check('which means it was not read from disk again',
        F.ActiveTab.Document.Modified);

      { And through a second name for the same file.  A home directory that
        links into a mounted volume is the ordinary case here, and matching
        on the literal path opened the file twice -- two documents over one
        file, each able to save over the other.

        Unix only, because the check needs a symlink to exist and FpSymlink
        is the only way this tree makes one.  Importing BaseUnix for it
        regardless is what kept the editor from building on Windows at all. }
      {$IFDEF UNIX}
      LinkDir := TempName('viadir');
      if ForceDirectories(LinkDir) then
      begin
        LinkPath := LinkDir + PathDelim + 'link';
        if FpSymlink(PChar(BrowseDir), PChar(LinkPath)) = 0 then
        begin
          F.BrowserOpenFileNow(LinkPath + PathDelim + 'a.c');
          Pump;
          CheckEqInt('reaching it by a symlinked path opens no second tab',
            Tabs1, F.Notebook.PageCount);
          Check('and still shows the edit',
            Pos('EDITED', F.ActiveView.Lines[0]) > 0);
        end;
        DeleteDirectory(LinkDir, False);
      end;
      {$ENDIF}

      F.ActiveTab.Document.Master.Modified := False;
      F.CloseActiveTab(False);
      Pump;
    end;
  end;

  { The filter row is a row, not a container with two hundred pixels of
    nothing under it -- which is what it was when the file list it had been
    sized for went away. }
  CheckGt('the tree fills the pane rather than a third of it',
    F.Browser.Height div 2, F.Browser.Tree.Height);

  { Making things, not only going places. }
  { The navigation row only -- the breadcrumb trail below it is made of
    speed buttons as well, so counting them by class across the pane finds
    both and answers eight. }
  CheckEqInt('six buttons on the row: four to navigate, two to create', 6,
    F.Browser.NavButtonCount);
  Check('every row got a picture', Pos('-1', Kinds) = 0);
  Check('and so are the files', (Pos('a.c ', Names) > 0) and
    (Pos('b.md ', Names) > 0) and (Pos('e.o ', Names) > 0));

  { 0 folder, 1 source, 2 text, 3 markdown, 4 pdf, 5 image, 6 binary. }
  CheckEqInt('a folder gets the folder icon', 0,
    F.Browser.IconFor(BrowseDir + PathDelim + 'sub'));
  CheckEqInt('a C file gets the source icon', 1,
    F.Browser.IconFor(BrowseDir + PathDelim + 'a.c'));
  CheckEqInt('a markdown file its own', 3,
    F.Browser.IconFor(BrowseDir + PathDelim + 'b.md'));
  CheckEqInt('a text file its own', 2,
    F.Browser.IconFor(BrowseDir + PathDelim + 'c.txt'));
  CheckEqInt('a pdf its own', 4,
    F.Browser.IconFor(BrowseDir + PathDelim + 'd.pdf'));
  CheckEqInt('and an object file reads as binary', 6,
    F.Browser.IconFor(BrowseDir + PathDelim + 'e.o'));

  if DirectoryExists(BrowseDir) then DeleteDirectory(BrowseDir, False);

  { Clicking the tree's top row -- the root folder itself -- used to raise
    EShellCtrl, "The selected item does not exist on disk", and arrive as the
    LCL's ignore-or-abort dialog.  Assigning FileSortType had rebuilt the root
    node without the file info that marks it a directory, so selecting it took
    DoSelectionChanged's branch for files, and a folder is never a file on
    disk.  Selecting it is the whole test: the raise was in the selection
    handler. }
  { A browser of its own, because the reproduction needs the root the
    constructor set and nothing else after it.  TCustomShellTreeView.SetRoot
    early-exits when the path has not changed, so the pane that is already
    open has had its root node rebuilt -- correctly -- by whatever path it was
    pointed at first.  Running the editor from the folder it browses is what
    made the first SetRoot a no-op, and left the damaged node in place. }
  Fresh := TLedFileBrowser.Create(F);
  try
    Fresh.Parent := F;
    Fresh.SetBounds(0, 0, LedScale96(300), LedScale96(400));
    Fresh.Visible := True;
    Pump;
    { Deliberately not told a root.  EnsureRoot was called from the two pane
      toggles and nowhere else, so a session that restored with the Files pane
      already open never called it: FRoot stayed empty for the whole session
      and the crumb trail, which is built from it, came up with nothing in it.
      The tree hid the problem by filling anyway -- the constructor roots that
      separately.  The pane roots itself now, once it has real geometry. }
    Pump;
    Check('a browser nobody told a root to finds one anyway',
      Fresh.Root <> '');
    { And that first root is where it opened, not somewhere it navigated to,
      so there is nothing behind it. }
    Check('and has been nowhere to go back to', not Fresh.CanGoBack);
    Check('nor forward', not Fresh.CanGoForward);

    { "The breadcrumb bar disappeared" -- so first, is there one?  A trail for
      a path several folders deep should have a button per component plus the
      root, and they have to fit inside the bar or the ones that matter, at
      the right-hand end, are the ones that get cut off. }
    Check('the crumb trail has buttons in it', Fresh.CrumbCount >= 2);
    { And they fit.  Laid out left to right they did not: seven buttons
      spanning 982 pixels in a 937-pixel bar, with the folder you are in the
      one hanging off the right-hand edge, which is what "the breadcrumb bar
      disappeared" looked like.  The trail is fitted from the right now, so
      whatever it shows has to be inside the bar. }
    Check('and the whole trail fits inside the bar',
      Fresh.CrumbsWidth <= Fresh.CrumbBarWidth);
    Say(Format('    crumbs: %d buttons spanning %d px in a bar %d px wide',
      [Fresh.CrumbCount, Fresh.CrumbsWidth, Fresh.CrumbBarWidth]));

    Root := Fresh.FileTree.Items.GetFirstNode;
    Check('the tree has a row for the root folder', Root <> nil);
    if Root <> nil then
    begin
      { The reason it raised, before the symptom: assigning FileSortType had
        rebuilt this node without the file info that marks it a directory. }
      Check('the root row knows it is a directory',
        TShellTreeNode(Root).IsDirectory);
      RootRaised := '';
      try
        Fresh.FileTree.Selected := Root;
        Pump;
      except
        on E: Exception do RootRaised := E.Message;
      end;
      { EShellCtrl, "The selected item does not exist on disk", arriving as
        the LCL's ignore-or-abort dialog. }
      CheckEq('and selecting it does not raise', '', RootRaised);
    end;
  finally
    Fresh.Free;
  end;

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
    { Scaled, because the terminal's cell size now is.  These numbers were
      picked to give a shell a comfortable number of columns, and a literal
      480 is a quarter as many on a display scaled by two -- few enough that
      the marker below wraps and no single row holds it, which is exactly how
      this test failed when the terminal font started being scaled. }
    Term.Width := LedScale96(480);
    Term.Height := LedScale96(240);
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

{ The symbol pane follows the active document.

  It is an outline of what ctags found in the file on screen, grouped by kind
  -- functions, classes, headings in a Markdown file -- and clicking an entry
  goes to its line.  Which makes showing the wrong file actively harmful: the
  line numbers are still live, so a click goes somewhere arbitrary in a
  document those symbols were never in. }
procedure TestSymbolsFollowTheDocument(F: TLedMainForm);
var
  MdPath, CPath: string;
  L: TStringList;
  V: TLedEdit;
  Node: TTreeNode;
  i: Integer;

  function TreeText: string;
  var
    i: Integer;
  begin
    Result := '';
    if F.SymbolPane = nil then Exit;
    for i := 0 to F.SymbolPane.Tree.Items.Count - 1 do
      Result := Result + F.SymbolPane.Tree.Items[i].Text + '|';
  end;

begin
  Say('symbols follow the document');
  if not LedCtagsAvailable then
  begin
    Say('  (ctags is not installed; skipped)');
    Exit;
  end;
  if F.SymbolPane = nil then Exit;

  MdPath := TempName('outline.md');
  L := TStringList.Create;
  try
    L.Add('# MarkdownChapterOne');
    L.Add('');
    L.Add('Some prose.');
    L.Add('');
    L.Add('## MarkdownSectionTwo');
    L.SaveToFile(MdPath);
  finally
    L.Free;
  end;

  CPath := TempName('outline.c');
  L := TStringList.Create;
  try
    L.Add('static int a_c_function(int x)');
    L.Add('{');
    L.Add('  return x;');
    L.Add('}');
    L.SaveToFile(CPath);
  finally
    L.Free;
  end;

  F.Dock.ShowPane('symbols');
  Pump; Pump;

  F.AddTab(F.Documents.OpenFile(MdPath));
  Pump; Pump;
  Check('the outline of a Markdown file lists its headings: ' + TreeText,
    Pos('MarkdownChapterOne', TreeText) > 0);

  F.AddTab(F.Documents.OpenFile(CPath));
  Pump; Pump;
  Check('switching document rebuilds the outline: ' + TreeText,
    Pos('a_c_function', TreeText) > 0);
  Check('and nothing of the old file is left in it',
    Pos('Markdown', TreeText) = 0);
  CheckEq('and the pane agrees about which file it is showing',
    CPath, F.SymbolPane.FileName);

  { Grouped by what the symbol is.  ctags is asked for whole-word kinds, and
    the reader understood only the one-letter ones, so every symbol in every
    file was filed under a single group called Other. }
  Check('the groups say what the symbols are, not "Other": ' + TreeText,
    Pos('Function', TreeText) > 0);

  { The line a symbol is on, after the file has been typed in.  ctags read
    the copy on disk, so every line below an edit has moved and the outline's
    numbers are stale the moment anything is inserted above them. }
  V := F.ActiveView;
  if V <> nil then
  begin
    for i := 1 to 5 do
      V.Lines.Insert(0, '/* inserted */');
    Pump;
    Node := nil;
    for i := 0 to F.SymbolPane.Tree.Items.Count - 1 do
      if F.SymbolPane.Tree.Items[i].Text = 'a_c_function' then
        Node := F.SymbolPane.Tree.Items[i];
    Check('the function is in the tree', Node <> nil);
    if Node <> nil then
    begin
      F.SymbolPane.Tree.Selected := Node;
      if Assigned(F.SymbolPane.Tree.OnDblClick) then
        F.SymbolPane.Tree.OnDblClick(F.SymbolPane.Tree);
      Pump;
      CheckEqInt('and clicking it lands on the function, not five lines above',
        6, V.CaretY);
    end;
  end;

  while F.TabCount > 1 do F.CloseActiveTab(True);
  F.Dock.HidePane('symbols');
  Pump;
  DeleteFile(MdPath);
  DeleteFile(CPath);
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

{ Which screen LED opens on.

  The window's position is restored from layout.xml, which carries it along
  with the panes -- so on a desktop with more than one monitor LED reopened
  wherever it was last closed, however far that was from the screen it had
  just been launched from.

  Two monitors cannot be had on a test display: Xvfb has no RandR outputs, so
  neither +xinerama nor xrandr --setmonitor produces a second one, and the LCL
  sees one screen however it is asked.  The arithmetic is therefore checked
  against rectangles, which is where all of it lives, and the wiring is
  checked against the one monitor there is. }
procedure TestWindowPlacement(F: TLedMainForm);
var
  Mons: array[0..1] of TRect;
  R, M, Saved: TRect;
begin
  Say('which screen it opens on');

  { Two 1000x800 monitors side by side. }
  Mons[0] := Rect(0, 0, 1000, 800);
  Mons[1] := Rect(1000, 0, 2000, 800);

  { Saved on the right-hand one, launched from the left: it comes across,
    keeping its size and where it sat within its monitor. }
  R := LedPlaceOnMonitor(Rect(1100, 60, 1700, 560), Mons, Point(400, 400));
  CheckEqInt('a window saved on the other monitor comes to this one', 100,
    R.Left);
  CheckEqInt('at the same height', 60, R.Top);
  CheckEqInt('keeping its width', 600, R.Right - R.Left);
  CheckEqInt('and its height', 500, R.Bottom - R.Top);

  { Launched from the monitor it was already on: untouched, including a
    window the user has deliberately pushed off the left edge. }
  R := LedPlaceOnMonitor(Rect(-40, 60, 560, 560), Mons, Point(400, 400));
  CheckEqInt('a window already on this monitor is left alone', -40, R.Left);
  CheckEqInt('exactly as it was', 60, R.Top);

  { Saved somewhere no monitor covers any more -- the screen it was on is
    unplugged -- and it is centred on the one the launch came from rather
    than left in the void. }
  R := LedPlaceOnMonitor(Rect(3000, 3000, 3600, 3500), Mons, Point(1400, 400));
  Check('a window saved on a monitor that is gone lands on this one',
    (R.Left >= Mons[1].Left) and (R.Right <= Mons[1].Right) and
    (R.Top >= Mons[1].Top) and (R.Bottom <= Mons[1].Bottom));

  { Bigger than the monitor it is moving to: shrunk to fit rather than
    hanging off the edge. }
  Mons[1] := Rect(1000, 0, 1400, 300);
  R := LedPlaceOnMonitor(Rect(20, 20, 920, 720), Mons, Point(1200, 100));
  Check('a window too big for the new monitor is shrunk onto it',
    (R.Left >= Mons[1].Left) and (R.Right <= Mons[1].Right) and
    (R.Top >= Mons[1].Top) and (R.Bottom <= Mons[1].Bottom));
  Mons[1] := Rect(1000, 0, 2000, 800);

  { A pointer on no monitor -- between two of them on an L-shaped desktop, or
    not yet moved -- is not a reason to move anything. }
  R := LedPlaceOnMonitor(Rect(1100, 60, 1700, 560), Mons, Point(5000, 5000));
  CheckEqInt('a pointer on no monitor leaves the window where it was', 1100,
    R.Left);

  { One monitor, and a position saved when the desktop had another one or was
    bigger: the window comes back rather than opening where nobody can see
    it.  This is the case that matters on a single-screen machine, and it is
    the same arithmetic. }
  R := LedPlaceOnMonitor(Rect(2400, 1800, 3000, 2300), Mons[0..0],
    Point(500, 400));
  Check('a position saved off the edge of the desktop comes back',
    (R.Left >= Mons[0].Left) and (R.Right <= Mons[0].Right) and
    (R.Top >= Mons[0].Top) and (R.Bottom <= Mons[0].Bottom));

  { And the same routines against the screen this suite is actually running
    on.  poScreenCenter is what centred the window on the union of every
    monitor, so it has to be off: LED positions the window itself now. }
  Check('the window is positioned by LED, not by the LCL',
    F.Position = poDesigned);

  CheckGt('the test display has a monitor', 0, Screen.MonitorCount);
  Saved := F.BoundsRect;
  try
    LedCentreOnLaunchMonitor(F);
    Pump;
    M := Screen.Monitors[0].WorkareaRect;
    if (M.Right <= M.Left) or (M.Bottom <= M.Top) then
      M := Screen.Monitors[0].BoundsRect;
    { One monitor here, so the pointer is on it whatever it is doing. }
    if Screen.MonitorCount = 1 then
    begin
      CheckEqInt('and centring puts the window in the middle of it',
        M.Left + ((M.Right - M.Left) - F.Width) div 2, F.Left);
      CheckEqInt('in both directions',
        M.Top + ((M.Bottom - M.Top) - F.Height) div 2, F.Top);
    end;
  finally
    F.BoundsRect := Saved;
    Pump;
  end;
end;

{ Word wrap, turned on and off and on again.

  Once was fine and twice was fatal.  TLazSynEditLineWrapPlugin has no
  destructor in Lazarus 2.2: its constructor puts a TSynEditLineMappingView
  into the editor's view chain and hangs a display object on it holding a
  back-reference to the plugin, and freeing the plugin undoes none of that.
  The next repaint asked the freed plugin for its wrap column, in the middle
  of drawing the text.

  Taking the view out as well is what this covers, and it has to be taken out
  in two steps: the manager's own RemoveSynTextView(..., True) frees the view
  before unlinking it and then reconnects the chain through the corpse, which
  is a segmentation fault rather than an exception.

  Four toggles with a repaint after each, because the fault needs a paint to
  show itself, and text long enough to actually wrap at this width. }
procedure TestWordWrapToggling(F: TLedMainForm);
var
  V: TLedEdit;
  i, WrapRows, PlainRows, W0: Integer;
  Long: string;
begin
  Say('word wrap');

  if F.ActiveTab = nil then F.actNewExecute(nil);
  Pump;
  V := F.ActiveView;
  if V = nil then Exit;
  { One line, long enough to wrap at any width this window can be. }
  Long := '';
  for i := 1 to 40 do
    Long := Long + StringOfChar(Char(Ord('a') + i mod 26), 40) + ' ';
  V.Lines.Text := Long;
  Pump;

  PlainRows := V.ViewLineCount;
  for i := 1 to 4 do
  begin
    F.actWrapText.Execute;
    Pump;
    V.Repaint;
    Pump;
    if i = 1 then WrapRows := V.ViewLineCount;
  end;

  { It really wrapped the first time -- one line of text shown as several --
    so what the repaints went through was the wrapped path and not a no-op. }
  { One line of text, shown as many rows.  Counted off the top of the view
    chain, which is the only view that sees both the folding below it and the
    wrapping above: the folded view alone still says one. }
  CheckEqInt('the text is one line', 1, V.Lines.Count);
  CheckGt('turning wrap on shows it as several rows', PlainRows, WrapRows);
  CheckEqInt('and turning it off puts them back', PlainRows, V.ViewLineCount);
  Check('and LED is still running after four toggles', V.Parent <> nil);

  { And a change of width once it is off.  The plugin registers a
    status-changed handler for scCharsInWindow that nothing unregisters, so
    with the plugin freed the next thing to resize the editor -- a window
    resize, or opening a pane -- called into freed memory.  Reaching the next
    line is the assertion: this was a hard crash, not an exception. }
  W0 := F.Width;
  F.Width := W0 - 60;
  Pump;
  F.Width := W0;
  Pump;
  F.Dock.ShowPane('files');
  Pump;
  F.Dock.HidePane('files');
  Pump;
  Check('and a width change after wrapping is off is harmless',
    (V.Parent <> nil) and (F.ActiveView = V));

  V.Lines.Text := '';
  Pump;
end;

{ Menus and language detection, both reported as broken from real use. }
procedure TestMenusAndDetection(F: TLedMainForm);
var
  Doc: TLedDocument;
  MsgDlg: TForm;
  MsgBefore, MsgAfter: Integer;
  HintLess, HintTotal, i: Integer;
  Path, MakeDir: string;
  MenuFont, MenuFace: string;
  MenuSize: Integer;
  FirstTheme, FirstLang: TMenuItem;
  ThemeCount, LangCount: Integer;
  Handles: TLedHandleArray;
  Items: TFPList;
  Fresh: TMenuItem;
  FreshHandle: THandle;
  Recreated: Integer;
  Handled: Boolean;
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

  { Nor may the action-update pass destroy one.

    gtk2 builds a plain menu item for anything that is not checked, is not a
    radio item and has no icon, and a plain item cannot carry a tick -- so the
    LCL answers Checked := True on one by destroying the widget and building a
    check item in its place.  LED assigns Checked from the action-update pass,
    which runs on every idle, including every idle while the pointer is moving
    over an open menu: the shell keeps pointing at the widget that has just
    been freed, which is both the several-rows-highlighted-at-once and the
    access violation that followed it.

    Handles, because that is what is destroyed.  The states are flipped both
    ways first, so every toggle LED owns is actually assigned in the pass
    rather than left at the value it already had -- which is what makes this
    catch a toggle added later and not made checkable. }
  { A menu item built the way the form builds them, then ticked once.

    This is the transition that used to destroy the widget, and it only
    happens once per item: by the time the suite runs, every item the window
    started with has long since been rebuilt as a check item, so watching
    those catches nothing.  A fresh one catches it. }
  { An action with no icon and no tick yet, which is the case gtk builds a
    plain item for -- actToggleLeftPane is one of the three the debugger
    caught being rebuilt.  An action that carries an icon was never affected:
    gtk builds a check item for those anyway. }
  F.actToggleLeftPane.Checked := False;
  Fresh := TMenuItem.Create(F);
  Fresh.Action := F.actToggleLeftPane;
  F.mnuWindow.Add(Fresh);
  try
    F.MakeTogglesCheckable;
    Pump;
    Check('the new item has a widget to lose', Fresh.HandleAllocated);
    if Fresh.HandleAllocated then
    begin
      FreshHandle := Fresh.Handle;
      F.actToggleLeftPane.Checked := True;
      Pump;
      Check('ticking a freshly built menu item does not rebuild it',
        Fresh.HandleAllocated and (Fresh.Handle = FreshHandle));
      F.actToggleLeftPane.Checked := False;
      Pump;
      Check('and unticking it does not either',
        Fresh.HandleAllocated and (Fresh.Handle = FreshHandle));
    end;
  finally
    F.mnuWindow.Remove(Fresh);
    Fresh.Free;
  end;

  CollectMenuHandles(F, Items, Handles);
  try
    CheckGt('there are menu items to watch', 40, Items.Count);

    { A document, because half of these are greyed without one and an action
      that is disabled is not assigned. }
    if F.ActiveTab = nil then F.actNewExecute(nil);
    Pump;

    Recreated := 0;
    for i := 1 to 2 do
    begin
      F.actShowToolbar.Execute;
      F.actToggleLeftPane.Execute;
      F.actToggleOutput.Execute;
      Pump;
      Handled := False;
      F.ActionList1Update(F.actSave, Handled);
      Pump;
      Inc(Recreated, ChangedHandles(Items, Handles));
    end;
    CheckEqInt('ticking a menu item does not destroy it', 0, Recreated);
  finally
    Items.Free;
  end;

  { Refilling one must not destroy what is in it.

    Every dynamic menu here is refilled from its own parent item's OnClick,
    which is the moment gtk is opening that very submenu.  Emptying it first
    destroyed the widgets of a menu the toolkit was in the middle of showing:
    the shell went on drawing entries it no longer owned -- several of them
    highlighted at once -- and sweeping the pointer along the menu bar fast
    enough to refill one menu after another ended in an access violation
    inside gtk, with nothing of LED's on the stack to say so.

    Reported twice from use, and reproduced here by refilling the same menus
    the way a hover does.  The property that makes it safe is that the items
    survive: the same objects, in the same order, with their captions
    rewritten. }
  FirstTheme := nil;
  if F.miTheme.Count > 0 then FirstTheme := F.miTheme.Items[0];
  FirstLang := nil;
  if F.miLanguage.Count > 0 then FirstLang := F.miLanguage.Items[0];
  ThemeCount := F.miTheme.Count;
  LangCount := F.miLanguage.Count;

  for i := 1 to 5 do
  begin
    F.PopulateThemeMenu;
    F.PopulateLanguageMenu;
    F.PopulateEncodingMenu;
    F.PopulateLineEndMenu;
    F.PopulateToolMenu;
    F.PopulateRecentMenu;
    F.PopulateDocMenu;
  end;

  Check('refilling a menu keeps the item that was there',
    (FirstTheme <> nil) and (F.miTheme.Count > 0) and
    (F.miTheme.Items[0] = FirstTheme));
  Check('and so does a menu of submenus',
    (FirstLang <> nil) and (F.miLanguage.Count > 0) and
    (F.miLanguage.Items[0] = FirstLang));
  CheckEqInt('and it does not grow each time', ThemeCount, F.miTheme.Count);
  CheckEqInt('nor does the one with submenus', LangCount,
    F.miLanguage.Count);
  Check('and the contents are still right',
    (CountLeaves(F.miLanguage) > 100) and (F.miTheme.Count = LedThemes.Count));

  { Eight of the ninety-seven actions carried a Hint, so hovering almost any
    toolbar button produced nothing at all -- a TToolButton shows its
    action's hint, and the toolbar had ShowHint set the whole time.  Every
    action that has a caption should now answer a hover. }
  HintLess := 0;
  HintTotal := 0;
  for i := 0 to F.ActionList1.ActionCount - 1 do
    if F.ActionList1.Actions[i] is TCustomAction then
      with TCustomAction(F.ActionList1.Actions[i]) do
        if Trim(StringReplace(Caption, '&', '', [rfReplaceAll])) <> '' then
        begin
          Inc(HintTotal);
          if Hint = '' then Inc(HintLess);
        end;
  Check('there are actions to hint at all', HintTotal > 50);
  CheckEqInt('and every one of them has a hint', 0, HintLess);
  { Derived from the caption, and deliberately *without* the shortcut in it.
    The LCL appends one at display time -- TControlActionLink.DoShowHint does
    it whenever Application.HintShortCuts is on -- so a hint that carried its
    own showed the keys twice: "Save  (Ctrl+S) (Ctrl+S)". }
  Check('a hint drops the caption''s accelerator',
    Pos('&', F.actSave.Hint) = 0);
  Check('and does not carry the shortcut itself',
    Pos('Ctrl+S', F.actSave.Hint) = 0);
  Check('because the LCL is the one that adds it',
    Application.HintShortCuts);

  { gtk2 draws the menus itself, at Xft.dpi, and knows nothing about the
    desktop's integer window-scaling factor -- so on a scaled display led's
    menu bar sat at half the height of every other application's while its own
    text, which goes through TFont, had already grown.  Led.UI.Dpi closes that
    with a gtk resource style; these are the parts of it that can be checked
    on a display of any shape. }
  { The LCL builds its message and unhandled-exception dialogs itself and
    shows them without LED ever holding a reference, so they used to arrive at
    their design size with 10-point text -- a third of the window that raised
    them.  CreateMessageDialog is that construction without the modal loop, so
    the scaling can be checked rather than screenshotted.

    What has to hold is that the labels' point size came up with the display.
    They start at the system font's size, which is the one size
    LedScalePointSizesOn is allowed to touch. }
  MsgDlg := CreateMessageDialog('The selected item does not exist on disk',
    mtError, [mbOK, mbAbort]);
  try
    { The font every control on the dialog inherits.  Measuring the labels
      themselves is no good: they carry no font of their own, which is the
      whole point -- they take the form's. }
    MsgBefore := Abs(MsgDlg.Font.Height);
    LedScaleForm(MsgDlg);
    MsgAfter := Abs(MsgDlg.Font.Height);

    { Nothing of its own to begin with, and that is the trap: gtk2 draws a
      font carrying neither a size nor a height at a hard-coded ten points --
      "use some default", in CreateFontIndirectEx -- and ten points at the Xft
      DPI is 21 pixels inside a window laid out for 48. }
    CheckEqInt('the LCL''s own dialog starts with no font height at all',
      0, MsgBefore);
    { And scaling has to leave it that way.  gtk2 resolves a font carrying
      neither size nor height from the default style, and the default style is
      the scaled one LED installs -- so the dialog is already drawn at the
      right size and there is nothing to put right.  Materialising a height
      here would read it back off that same scaled widget and multiply it by
      the PPI ratio a second time: 42 pixels became 84. }
    CheckEqInt('and scaling leaves it for the scaled theme to answer',
      0, MsgAfter);
    { Once only.  AutoAdjustLayout records the PPI it scaled to and returns
      immediately when asked again, which is what stops the startup sweep and
      the visible-changed hook from scaling the same form twice. }
    LedScaleForm(MsgDlg);
    CheckEqInt('and scaling it again changes nothing', MsgAfter,
      Abs(MsgDlg.Font.Height));
  finally
    MsgDlg.Free;
  end;

  Check('the menu-font correction never shrinks the theme font',
    LedChromeFontFactor >= 1.0);
  MenuFont := LedScaledChromeFont;
  if LedChromeFontFactor > 1.0 then
  begin
    LedParseFontSpec(MenuFont, MenuFace, MenuSize);
    Check('a window-scaled desktop gets a bigger menu font',
      MenuSize >= Screen.SystemFont.Size);
    { The style is scoped to menu items precisely so that the font it is
      derived from -- the default style's -- never gets scaled itself.  Were
      it not, every refresh would multiply the factor in again. }
    Check('and asking a second time does not compound the factor',
      LedScaledChromeFont = MenuFont);
  end
  else
    Check('a desktop that needs no correction gets none', MenuFont = '');

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

{ The state LED opens in, before anything has touched it.  medit puts the
  caret at line 1 column 1 of an empty "Untitled 1" and shows that line's
  number in the gutter; this asserts LED does the same, because "it opened
  looking wrong" is otherwise a report nobody can act on. }
{ Opening something that is not text.  The dump itself is covered headlessly
  in the core suite; what matters here is that the editor notices, refuses to
  write the dump back over the file, and can still be told it was wrong. }
procedure TestBinaryFiles(F: TLedMainForm);
var
  Path: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  Raw, Saved, Expected: string;
  L: TStringList;
  Handled: Boolean;
begin
  Say('binary files');

  Raw := 'MZ' + #0#0 + 'header' + #0 + StringOfChar(#1, 40);
  Path := TempName('probe.bin');
  L := TStringList.Create;
  try
    L.LineBreak := #10;
    L.Text := Raw;
    { Written as bytes, not as lines -- a TStringList would add a terminator
      and change the very thing under test. }
    with TFileStream.Create(Path, fmCreate) do
      try
        Write(Raw[1], Length(Raw));
      finally
        Free;
      end;
  finally
    L.Free;
  end;

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  Doc.LoadFromFile(Path);
  Pump;

  Check('a file with NUL bytes opens as a dump', Doc.IsBinary);
  Check('and the dump is what the buffer holds',
    Pos('00000000  4d 5a 00 00', Doc.Master.Lines.Text) = 1);
  { The view is not offered for editing: letting it be typed into and
    refusing at the save would lose the typing and say so far too late. }
  Check('the view is read-only', Tab.ActiveView.ReadOnly);
  { No encoding and no line ending are claimed, because the buffer is not the
    file and neither would be true of it. }
  CheckEq('no encoding is claimed', '', Doc.Info.Encoding);
  Check('and no language is detected', Doc.LangInfo = nil);

  { Editing.  A byte is overwritten, never inserted: inserting would move
    every byte after it and renumber every offset below, which is not what
    the left-hand column would still be describing. }
  CheckEqInt('the bytes are the file', Length(Raw), Doc.HexSize);
  CheckEqInt('and byte 0 is M', Ord('M'), Doc.HexByte(0));
  Check('an untouched dump is not modified', not Doc.Modified);

  Doc.SetHexByte(0, Ord('Z'));
  Pump;
  CheckEqInt('setting a byte changes it', Ord('Z'), Doc.HexByte(0));
  Check('the row it is in is re-rendered',
    Pos('00000000  5a 5a', Doc.Master.Lines.Text) = 1);
  Check('and the document is modified', Doc.Modified);
  CheckEqInt('the file is no longer than it was',
    Length(Raw), Doc.HexSize);

  { Undo is the document's own: the buffer is rewritten a row at a time
    rather than typed into, so SynEdit's undo knows nothing about it. }
  Check('there is something to undo', Doc.CanUndoHex);
  CheckEqInt('and undo says which byte it put back', 0, Doc.UndoHexByte);
  Pump;
  CheckEqInt('undo puts the byte back', Ord('M'), Doc.HexByte(0));
  CheckEqInt('and there is nothing left to undo', -1, Doc.UndoHexByte);
  Check('and with nothing left to undo the document is clean',
    not Doc.Modified);

  { The view is a hex editor rather than a text one: the caret rests on bytes
    and keys are routed to the document.  Typing itself needs a keyboard, so
    what is checked here is the wiring that makes it possible. }
  Check('the view is in hex mode', Tab.ActiveView.HexMode);
  Check('and has somewhere to send its keys',
    Assigned(Tab.ActiveView.OnHexKey));

  { The offset down the left is a label, not somewhere to type, so the caret
    never rests in it -- clicking there lands on the first byte instead.  The
    same goes for the spaces between the pairs: a caret on one would have
    nothing to edit, and arrowing across a row would pass through dead
    columns where typing did nothing. }
  Tab.ActiveView.CaretXY := Point(3, 1);
  Pump;
  CheckEqInt('the caret cannot rest in the offset column',
    LedHexByteColumn(0), Tab.ActiveView.CaretX);
  Tab.ActiveView.CaretXY := Point(LedHexByteColumn(2) + 2, 1);
  Pump;
  CheckEqInt('nor in the space between two bytes',
    LedHexByteColumn(3), Tab.ActiveView.CaretX);
  Tab.ActiveView.CaretXY := Point(LedHexTextColumn(4), 1);
  Pump;
  CheckEqInt('but it rests in the text column',
    LedHexTextColumn(4), Tab.ActiveView.CaretX);

  { The three columns are told apart by colour, which is what makes the text
    column findable without counting across. }
  Check('the view has a hex markup', Tab.ActiveView.HexMarkup <> nil);

  { Driving that wiring directly, which is what a keystroke does once the
    view has worked out the byte and the half.  A hex digit on the left
    replaces one nibble ... }
  Handled := False;
  Tab.ActiveView.OnHexKey(Tab.ActiveView, 4, 0, 'a', Handled);
  Check('a hex digit in the left column is taken', Handled);
  CheckEqInt('and replaces the high nibble alone',
    $A0 or (Ord('h') and $0F), Doc.HexByte(4));

  Handled := False;
  Tab.ActiveView.OnHexKey(Tab.ActiveView, 4, 1, '7', Handled);
  CheckEqInt('the second press replaces the low one',
    $A7, Doc.HexByte(4));

  { ... and a character on the right replaces the whole byte. }
  Handled := False;
  Tab.ActiveView.OnHexKey(Tab.ActiveView, 4, -1, 'X', Handled);
  Check('a character in the right column is taken', Handled);
  CheckEqInt('and replaces the byte', Ord('X'), Doc.HexByte(4));

  { A key that means nothing here changes nothing.  It still must not reach
    the buffer, which UTF8KeyPress sees to; what matters at this level is
    that no byte moves. }
  Handled := False;
  Tab.ActiveView.OnHexKey(Tab.ActiveView, 4, 0, 'z', Handled);
  Check('a non-hex-digit in the left column is not', not Handled);
  CheckEqInt('and leaves the byte alone', Ord('X'), Doc.HexByte(4));

  Handled := False;
  Tab.ActiveView.OnHexKey(Tab.ActiveView, 4, -1, #9, Handled);
  Check('nor is an unprintable character on the right', not Handled);
  CheckEqInt('which also leaves the byte alone', Ord('X'), Doc.HexByte(4));

  { Put byte 4 back, so what follows measures what it means to. }
  while Doc.CanUndoHex do Doc.UndoHexByte;
  CheckEqInt('undoing everything restores the file',
    Ord('h'), Doc.HexByte(4));
  Check('and leaves it unmodified', not Doc.Modified);

  { Saving writes the bytes, not the buffer -- no encoding, no line-ending
    normalisation, nothing that would rewrite a CR sitting between two bytes
    of a binary. }
  Doc.SetHexByte(1, $FF);
  Doc.SaveToFile(Path);
  Saved := '';
  with TFileStream.Create(Path, fmOpenRead) do
    try
      SetLength(Saved, Size);
      if Size > 0 then Read(Saved[1], Size);
    finally
      Free;
    end;
  CheckEqInt('the saved file is the same length', Length(Raw), Length(Saved));
  Expected := Raw;
  Expected[2] := Chr($FF);
  CheckEq('and differs in exactly the byte that was edited', Expected, Saved);
  Check('saving clears the modified flag', not Doc.Modified);

  { Reloaded, the edit is there and nothing else moved. }
  Doc.LoadFromFile(Path);
  Pump;
  Check('it is still a dump after saving', Doc.IsBinary);
  CheckEqInt('and the edited byte survived the round trip',
    $FF, Doc.HexByte(1));

  { Detection is a heuristic, so it has to be possible to overrule. }
  Doc.OpenAsText;
  Pump;
  Check('opening as text turns the dump off', not Doc.IsBinary);
  { The file's own first byte, not the dump's first row.  Byte 1 was edited
    above, so 'M' is as much of it as is still what it was. }
  Check('and the buffer is the file again',
    Copy(Doc.Master.Lines.Text, 1, 1) = 'M');
  Check('and the view can be edited', not Tab.ActiveView.ReadOnly);

  DeleteFile(Path);
end;

{ Writes ABytes to APath exactly, with no terminator and no line-ending
  translation -- the bytes are the thing under test. }
procedure WriteBytes(const APath: string; const ABytes: string);
begin
  with TFileStream.Create(APath, fmCreate) do
    try
      if ABytes <> '' then Write(ABytes[1], Length(ABytes));
    finally
      Free;
    end;
end;

{ The colour a scheme gave one scope, read off the highlighter that is in
  use -- which is where the answer actually is, after the map-to chain, the
  theme lookup and the readability floor have all had their say. }
function AttrColour(V: TLedEdit; const AScope: string): TColor;
var
  i: Integer;
begin
  Result := clNone;
  if V.Highlighter = nil then Exit;
  for i := 0 to V.Highlighter.AttrCount - 1 do
    if SameText(V.Highlighter.Attribute[i].StoredName, AScope) then
      Exit(V.Highlighter.Attribute[i].Foreground);
end;

{ The scope the highlighter puts on the token at a column: the attribute's
  stored name, which for a grammar-driven highlighter is the scope the
  grammar asked for -- 'def.identifier', 'def.type'.  Empty where the
  highlighter says nothing.

  Asked of the highlighter directly rather than read off the screen, because
  what is being checked is which scope a field gets; whether the theme then
  paints it, and in what colour, is the theme's business and is checked
  separately. }
function ScopeAt(V: TLedEdit; ALine, ACol: Integer): string;
var
  HL: TSynCustomHighlighter;
  Tok: PChar;
  TokLen, TokPos: Integer;
  Attr: TSynHighlighterAttributes;
begin
  Result := '';
  HL := V.Highlighter;
  if (HL = nil) or (ALine < 1) or (ALine > V.Lines.Count) then Exit;
  HL.StartAtLineIndex(ALine - 1);
  while not HL.GetEol do
  begin
    HL.GetTokenEx(Tok, TokLen);
    TokPos := HL.GetTokenPos;
    if (ACol > TokPos) and (ACol <= TokPos + TokLen) then
    begin
      Attr := HL.GetTokenAttribute;
      if Attr <> nil then Result := Attr.StoredName;
      Exit;
    end;
    HL.Next;
  end;
end;

{ What the offset markup would paint at a column, asked the way the painter
  asks it: through the markup's own GetMarkupAttributeAtRowCol. }
function MarkupColourAt(V: TLedEdit; ARow, ACol: Integer): TColor;
var
  Bound: TLazSynDisplayTokenBound;
  Rtl: TLazSynDisplayRtlInfo;
  Attr: TSynSelectedColor;
begin
  Result := clNone;
  if V.HexMarkup = nil then Exit;
  Bound := Default(TLazSynDisplayTokenBound);
  Bound.Logical := ACol;
  Bound.Physical := ACol;
  Rtl := Default(TLazSynDisplayRtlInfo);
  Attr := V.HexMarkup.GetMarkupAttributeAtRowCol(ARow, Bound, Rtl);
  if Attr <> nil then Result := Attr.Foreground;
end;

procedure TestBJDataFiles(F: TLedMainForm);
var
  Good, Bad, Bad2: string;
  Raw, Text: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  V: TLedEdit;
  L1, L2, SavedTheme: string;
  i: Integer;
  KeyCol, MarkCol, ValCol, RemCol: TColor;
  Files, Args: TStringList;
  Cmd: TLedCommandLine;

  { The same checks for either way a file reaches a tab. }
  procedure CheckBadOpen(const ALabel, APath: string);
  var
    D: TLedDocument;
    T: TLedTab;
    W: PtrUInt;
  begin
    T := F.ActiveTab;
    D := T.Document;
    CheckEq(ALabel + ': it is the file on screen', APath, D.FileName);
    Check(ALabel + ': it does not open as a structure', not D.IsBJData);
    Check(ALabel + ': it opens as a dump instead', D.IsBinary);
    Check(ALabel + ': and the buffer is a hex dump',
      Pos('00000000  7b 55 03 70', D.Master.Lines.Text) = 1);

    W := D.BJDataErrorOffset;
    Check(ALabel + ': the failure is placed in the file',
      (W > 0) and (W <= PtrUInt(Length(Raw))));
    { Past the first row of the dump, which is what lets the caret checks
      tell a moved caret from an untouched one. }
    Check(ALabel + ': and past the first row of the dump',
      W >= PtrUInt(LedHexBytesPerLine));
    CheckEqInt(ALabel + ': the caret row is the row of that byte',
      Integer(W) div LedHexBytesPerLine + 1, T.ActiveView.CaretY);
    CheckEqInt(ALabel + ': and the column is that byte',
      LedHexByteColumn(Integer(W) mod LedHexBytesPerLine),
      T.ActiveView.CaretX);
    { Read and cleared: the window reports once, and a redraw or a focus
      change must not bring the dialog back. }
    Check(ALabel + ': the message is taken when it is reported',
      D.TakeBJDataError(W) = '');
  end;

begin
  Say('Binary JData files');

  { { "a": l 7, "hi": S U 2 "hi" } -- small, but every part of the view is in
    it: a container, a key, an integer with its marker, a counted string.

    The 7 is written as an int32 on purpose, so three of the first ten bytes
    are NUL.  That is what makes the ordering check below mean something. }
  Raw := #$7B + #$55#$01'a' + #$6C#$07#$00#$00#$00 +
         #$55#$02'hi' + #$53#$55#$02'hi' +
         { and one of each of the other things a row can carry, so the
           colouring below is asked about all of them }
         #$55#$01'n' + #$5A +                                    { null }
         #$55#$01'f' + #$44#$00#$00#$00#$00#$00#$00#$F8#$3F +    { 1.5 }
         #$55#$03'arr' + #$5B#$24#$55#$23#$55#$03 + #$01#$02#$03 +
         #$7D;
  Good := TempName('probe.bjd');
  WriteBytes(Good, Raw);

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  Doc.LoadFromFile(Good);
  Pump;

  Text := Doc.Master.Lines.Text;
  Check('a .bjd file opens as a structure', Doc.IsBJData);
  { Still a binary: the file is bytes and the buffer is a rendering of them,
    which is what makes it read-only and makes Save write the bytes. }
  Check('and is still a binary', Doc.IsBinary);
  Check('but not a hex dump', not Tab.ActiveView.HexMode);
  Check('the view is read-only', Tab.ActiveView.ReadOnly);
  Check('the marker and length are shown, got: ' + Text, Pos('S #2', Text) > 0);
  Check('and the value', Pos('"hi"', Text) > 0);
  Check('the integer keeps its own marker', Pos('  a  l  7', Text) > 0);
  CheckEq('no encoding is claimed', '', Doc.Info.Encoding);

  { The ordering, stated as two facts rather than one.  These bytes really do
    look binary -- LedLooksBinary says so -- and the file opened as a
    structure anyway, which it only can if BJData is asked about first.  Swap
    the two tests in LoadFromFile and this fails. }
  Check('the bytes do look binary', LedLooksBinary(Raw));
  Check('and a BJData file opens as a structure regardless', Doc.IsBJData);

  { And the status bar says which of the two binary views this is: it said
    hex over a structure view, which is exactly the question that column is
    there to answer. }
  F.UpdateStatusBar;
  Pump;
  CheckEq('the status bar names the structure view', 'Binary (BJData)',
    F.StatusBar1.Panels[3].Text);

  { ---- the structure is colour-coded, by the same machinery as a language ---- }

  { Coloured from the walk that rendered it, not by reading the rendering
    back: the walker tagged every field as it wrote it, and the highlighter
    hands those tags to SynEdit.  So there is no language and no grammar --
    and nothing for a regex to be wrong about. }
  V := Tab.ActiveView;
  CheckEq('the structure view is not a language', '',
    Doc.Config.GetStr(LedSetLang));
  Check('and is coloured by the walk that built it',
    V.Highlighter is TLedBJHighlighter);

  L1 := V.Lines[1];                      { '       4    a  l  7' }
  L2 := V.Lines[2];                      { '      13    hi  S #2  "hi"' }
  CheckEq('the file offset is not data', 'def.comment', ScopeAt(V, 2, 8));
  CheckEq('the key is an identifier', 'def.identifier',
    ScopeAt(V, 2, Pos('a  l', L1)));
  CheckEq('the type marker is a type', 'def.type',
    ScopeAt(V, 2, Pos('l  7', L1)));
  CheckEq('an integer is a number', 'def.decimal', ScopeAt(V, 2, Pos('7', L1)));

  CheckEq('a string keeps its key apart from its marker', 'def.identifier',
    ScopeAt(V, 3, Pos('hi  S', L2)));
  CheckEq('a length is part of the marker', 'def.type',
    ScopeAt(V, 3, Pos('S #2', L2) + 2));
  CheckEq('and the string itself is a string', 'def.string',
    ScopeAt(V, 3, Pos('"hi"', L2) + 1));

  CheckEq('null is a constant, not a word', 'def.special-constant',
    ScopeAt(V, 4, Pos('null', V.Lines[3])));
  CheckEq('a float is a float', 'def.floating-point',
    ScopeAt(V, 5, Pos('1.5', V.Lines[4])));
  CheckEq('an ND-array marker is one marker, brackets and all', 'def.type',
    ScopeAt(V, 6, Pos('[$U#[3]', V.Lines[5]) + 3));
  CheckEq('and the values it was inlined into are numbers', 'def.decimal',
    ScopeAt(V, 6, Pos('1, 2, 3', V.Lines[5])));

  { A container's marker is a marker like any other: a brace is the byte the
    file holds, and the count beside it is LED's. }
  CheckEq('a container marker is a type too', 'def.type',
    ScopeAt(V, 1, Pos('{', V.Lines[0])));

  { And LED's own remarks recede.  This is the distinction the whole scheme
    is for: "5 items" is not in the file, it is LED counting. }
  CheckEq('a count LED worked out reads as a remark', 'def.comment',
    ScopeAt(V, 1, Pos('5 items', V.Lines[0])));

  { ---- and every scheme paints it ---- }

  { The scopes above are the shared def: ones, so a scheme that colours C
    colours this.  What is checked per scheme is that the three fields do not
    all come out the same colour -- a view where the key, the marker and the
    value are one colour is not colour-coded -- and that each of them can be
    read on the page, which is the floor every syntax colour goes through. }
  SavedTheme := LedPrefs.GetStr(LedPrefColorScheme, 'medit');
  try
    for i := 0 to LedThemes.Count - 1 do
    begin
      { Through the path the program uses when the theme is switched -- the
        document re-applies its config to its views, which is also where its
        own highlighter is re-themed.  Reaching past that and colouring the
        editor alone is how the first version of this check reported a marker
        nobody could read: the view had the new page and the highlighter
        still had the old scheme's colours. }
      LedSetCurrentTheme(LedThemes[i].Id);
      LedRetheme(LedCurrentTheme);
      Doc.ApplyConfigToViews;
      Pump;

      KeyCol := AttrColour(V, 'def.identifier');
      MarkCol := AttrColour(V, 'def.type');
      ValCol := AttrColour(V, 'def.string');
      RemCol := AttrColour(V, 'def.comment');

      Check('the fields are told apart by colour in ' + LedThemes[i].Id,
        (KeyCol <> MarkCol) or (MarkCol <> ValCol) or (KeyCol <> ValCol));
      Check('and LED''s remarks are a colour of their own in ' +
        LedThemes[i].Id, (RemCol <> KeyCol) or (RemCol <> MarkCol));
      CheckGt('the marker can be read in ' + LedThemes[i].Id, 39,
        Round(10 * LedContrastRatio(MarkCol, V.Color)));
    end;
  finally
    LedSetCurrentTheme(SavedTheme);
    LedRetheme(LedCurrentTheme);
    Doc.ApplyConfigToViews;
    Pump;
  end;

  { ---- the offset column reads as one, and is not somewhere to put a caret ---- }

  { The same treatment a dump's address column gets.  A structure row starts
    with eight characters of file offset and two spaces, and that is a fact
    about the file rather than text: it recedes, and a click in it lands on
    the record instead of between two digits of a number. }
  V := Tab.ActiveView;
  Check('the structure view is not a hex dump', not V.HexMode);
  Check('but it says it is the structure view', V.BJDataMode);
  Check('and it has an offset markup', V.HexMarkup <> nil);
  if V.HexMarkup <> nil then
  begin
    CheckEqInt('which knows it has only an offset column',
      Ord(lmkOffsetOnly), Ord(V.HexMarkup.Kind));
    CheckEqInt('eight characters wide', LedBJOffsetWidth,
      V.HexMarkup.OffsetWidth);
  end;

  { Coloured, and only there.  Asked of the markup the way the painter asks
    it: a column inside the offset answers with a colour, one past it does
    not. }
  Check('the offset column is given a colour',
    MarkupColourAt(V, 1, 3) <> clNone);
  Check('and the record beside it is left to the highlighter',
    MarkupColourAt(V, 1, LedBJOffsetWidth + 4) = clNone);

  { And the caret cannot be put in it, by click or by code. }
  V.CaretXY := Point(2, 1);
  Pump;
  CheckEqInt('a caret aimed into the offset lands on the record',
    LedBJOffsetWidth + 3, V.CaretX);
  TLedMousePoke.Press(V, [], V.Gutter.Width + 2 + 2 * V.CharWidth,
    V.LineHeight div 2);
  TLedMousePoke.Release(V, [], V.Gutter.Width + 2 + 2 * V.CharWidth,
    V.LineHeight div 2);
  Pump;
  CheckGt('and a click in it does not stay there', LedBJOffsetWidth + 2,
    V.CaretX);

  { The way out is the same as for a dump. }
  Doc.OpenAsText;
  Pump;
  Check('Open as Text leaves the structure view', not Doc.IsBJData);
  Check('and is not binary either', not Doc.IsBinary);

  { ---- a file that says .bjd and is not ---- }

  { { "pad": S U 40 <40 bytes>, "a": S U 64 "short" } -- the second string
    declares 64 bytes and supplies 5, so the reader runs off the end.

    The padding is there so the damage is not on the first row of the dump.
    Without it the caret check passed whether or not the caret had been
    moved, because row 1 is where a freshly opened view already is. }
  Raw := #$7B + #$55#$03'pad' + #$53#$55#$28 + StringOfChar('.', 40) +
         #$55#$01'a' + #$53#$55#$40'short' + #$7D;
  Bad := TempName('broken.bjd');
  WriteBytes(Bad, Raw);
  Bad2 := TempName('broken2.bjd');
  WriteBytes(Bad2, Raw);

  { Through OpenFiles, not LoadFromFile: the caret and the message are the
    window's job, and testing the document alone would not reach them. }
  Files := TStringList.Create;
  try
    Files.Add(Bad);
    F.OpenFiles(Files);
    Pump;
  finally
    Files.Free;
  end;
  CheckBadOpen('opened from the file list', Bad);

  { And again through the command line, which reaches a tab by its own route.
    The first version of this reported only from OpenFiles, so led opened a
    bad file named on the command line as a dump with no message and the
    caret at byte zero.  Running it found that; this test did not. }
  Cmd := TLedCommandLine.Create;
  Args := TStringList.Create;
  try
    Args.Add(Bad2);
    Cmd.Parse(Args);
    F.ApplyCommandLine(Cmd, '');
    Pump;
  finally
    Args.Free;
    Cmd.Free;
  end;
  CheckBadOpen('opened from the command line', Bad2);

  DeleteFile(Good);
  DeleteFile(Bad);
  DeleteFile(Bad2);
end;

{ A notebook of ACells prose cells, each a few paragraphs, so that the whole
  of it is far taller than a control coordinate can hold.  Built rather than
  pasted in: what matters is the size, and four hundred cells of literal JSON
  in a source file is not something anybody should read. }
function TallNotebook(ACells: Integer): string;
var
  i: Integer;
  B: TStringList;
begin
  B := TStringList.Create;
  try
    B.TextLineBreakStyle := tlbsLF;
    B.Add('{');
    B.Add(' "cells": [');
    for i := 0 to ACells - 1 do
    begin
      B.Add('  {');
      B.Add('   "cell_type": "markdown",');
      B.Add('   "metadata": {},');
      B.Add('   "source": [');
      B.Add(Format('    "## Heading %d\n",', [i]));
      B.Add('    "\n",');
      B.Add('    "A paragraph of prose, long enough to take a line or two '
        + 'of any pane it is shown in.\n",');
      B.Add('    "\n",');
      B.Add('    "And a second paragraph after it."');
      B.Add('   ]');
      if i < ACells - 1 then B.Add('  },') else B.Add('  }');
    end;
    B.Add(' ],');
    B.Add(' "metadata": {},');
    B.Add(' "nbformat": 4,');
    B.Add(' "nbformat_minor": 5');
    B.Add('}');
    Result := B.Text;
  finally
    B.Free;
  end;
end;

{ Whether this machine can run a notebook cell: the helper is there and the
  Python it would be run with has the client library.  Asked of that same
  Python, because having jupyter_client is a property of an interpreter and
  not of a machine. }
function NotebookKernelAvailable: Boolean;
var
  P: TProcess;
begin
  Result := FileExists(LedKernelHelper);
  if not Result then Exit;
  P := TProcess.Create(nil);
  try
    P.Executable := LedKernelPython;
    P.Parameters.Add('-c');
    P.Parameters.Add('import jupyter_client, ipykernel');
    P.Options := [poWaitOnExit, poUsePipes, poNoConsole];
    try
      P.Execute;
      Result := P.ExitStatus = 0;
    except
      Result := False;
    end;
  finally
    P.Free;
  end;
end;

{ The notebook pane: the same file as cells rather than as lines.

  Two things are worth checking and they are different things.  What this
  view does that the line view cannot -- prose rendered, pictures drawn -- and
  that the two views of one file never disagree.

  The pane builds only the cells the viewport covers, so a check that wants a
  particular cell asks for it by cell rather than by position: CellBox scrolls
  to it first.  That is not ceremony.  A control's position in the LCL is a
  signed 16-bit number, and a hundred cells of full-height prose stack past
  32767 pixels, which took the editor down -- see the last block here. }
procedure TestNotebookPane(F: TLedMainForm);
var
  Path: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  Pane: TLedNotebookPane;
  B: TLedNBCellBox;
  i, Bottom, Was, WasImage, Deep: Integer;
  Img: TImage;
  Host: TForm;
  Loose: TLedNotebookPane;
  Dark, Light: TLedPageColours;
  WasBox: TLedNBCellBox;
  Handled: Boolean;
  Deadline: TDateTime;
  Page, Shown: string;
  Inner: TControl;
  Opened: TStringList;

  function Fixture: string;
  begin
    Result :=
    '{' + #10 +
    ' "cells": [' + #10 +
    '  {' + #10 +
    '   "cell_type": "markdown",' + #10 +
    '   "metadata": {},' + #10 +
    '   "source": [' + #10 +
    '    "## A heading\n",' + #10 +
    '    "\n",' + #10 +
    '    "prose with **bold** in it, and a second sentence so that the rendered block is more than one line tall.\n",' + #10 +
    '    "\n",' + #10 +
    '    "and a third paragraph."' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": 4,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [' + #10 +
    '    {' + #10 +
    '     "name": "stdout",' + #10 +
    '     "output_type": "stream",' + #10 +
    '     "text": [' + #10 +
    '      "forty-two\n"' + #10 +
    '     ]' + #10 +
    '    }' + #10 +
    '   ],' + #10 +
    '   "source": [' + #10 +
    '    "print(''forty-two'')"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": 5,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [' + #10 +
    '    {' + #10 +
    '     "data": {' + #10 +
    '      "image/png": "iVBORw0KGgoAAAANSUhEUgAAABgAAAAJCAIAAACnn3uRAAAAFUlEQVR4nGM4oaFBFcQwatCoQVRAAMNy7EEtcnPeAAAAAElFTkSuQmCC",' + #10 +
    '      "text/plain": [' + #10 +
    '       "<Figure>"' + #10 +
    '      ]' + #10 +
    '     },' + #10 +
    '     "metadata": {},' + #10 +
    '     "output_type": "display_data"' + #10 +
    '    }' + #10 +
    '   ],' + #10 +
    '   "source": [' + #10 +
    '    "plot()"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": null,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [],' + #10 +
    '   "source": [' + #10 +
    '    "x = 1\n",' + #10 +
    '    "y = 2"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": 6,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [' + #10 +
    '    {' + #10 +
    '     "data": {' + #10 +
    '      "image/png": "iVBORw0KGgoAAAANSUhEUgAAA4QAAAEsCAIAAAAU/OrGAAAFsElEQVR4nO3WMQ0AMAzAsMIZnMEurMHIMUsGkDNz7gIAQGLyAgAAvmVGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMmYUAICMGQUAIGNGAQDImFEAADJmFACAjBkFACBjRgEAyJhRAAAyZhQAgIwZBQAgY0YBAMiYUQAAMg83Vak75JjA2AAAAABJRU5ErkJggg=="' + #10 +
    '     },' + #10 +
    '     "metadata": {},' + #10 +
    '     "output_type": "display_data"' + #10 +
    '    }' + #10 +
    '   ],' + #10 +
    '   "source": [' + #10 +
    '    "wideplot()"' + #10 +
    '   ]' + #10 +
    '  }' + #10 +
    ' ],' + #10 +
    ' "metadata": {' + #10 +
    '  "kernelspec": {' + #10 +
    '   "display_name": "Python 3",' + #10 +
    '   "language": "python",' + #10 +
    '   "name": "python3"' + #10 +
    '  },' + #10 +
    '  "language_info": {' + #10 +
    '   "name": "python"' + #10 +
    '  }' + #10 +
    ' },' + #10 +
    ' "nbformat": 4,' + #10 +
    ' "nbformat_minor": 5' + #10 +
    '}' + #10 +
    '';
  end;

  { The box showing a cell, brought on screen first.  Windowed panes have no
    box for a cell nobody has scrolled to. }
  function CellBox(APane: TLedNotebookPane; ACell: Integer): TLedNBCellBox;
  begin
    APane.ScrollToCell(ACell);
    Pump;
    Result := APane.BoxOf(ACell);
  end;

  function ImageIn(ABox: TLedNBCellBox): TImage;
  var
    k: Integer;
  begin
    Result := nil;
    if ABox = nil then Exit;
    for k := 0 to ABox.ComponentCount - 1 do
      if ABox.Components[k] is TImage then
        Exit(TImage(ABox.Components[k]));
  end;

  { The face a rendered node actually ends up in, found by walking the tree
    the renderer built.

    Asked of the page rather than of the panel, because those are different
    questions and only this one is the reader's: FixedTypeface may be set on
    the panel and still not reach a <pre>, which is exactly what a <font
    face=> in the page did to it.  A check that reads back the assignment
    would have stayed green through all four attempts at this. }
  function FaceOfNode(ANode: TIpHtmlNode; const AClass: string): string;
  var
    k: Integer;
  begin
    Result := '';
    if not (ANode is TIpHtmlNodeMulti) then Exit;
    if SameText(ANode.ClassName, AClass) then
    begin
      if TIpHtmlNodeMulti(ANode).Props <> nil then
        Result := TIpHtmlNodeMulti(ANode).Props.FontName;
      if Result <> '' then Exit;
    end;
    for k := 0 to TIpHtmlNodeMulti(ANode).ChildCount - 1 do
    begin
      Result := FaceOfNode(TIpHtmlNodeMulti(ANode).ChildNode[k], AClass);
      if Result <> '' then Exit;
    end;
  end;

  function FaceInPage(APanel: TIpHtmlPanel; const AClass: string): string;
  begin
    Result := '';
    if (APanel = nil) or (APanel.MasterFrame = nil) or
       (APanel.MasterFrame.Html = nil) then Exit;
    Result := FaceOfNode(APanel.MasterFrame.Html.HtmlNode, AClass);
  end;

  { The theme scope the box's own editor would paint at a 1-based row and
    column.  The cell's colouring is a property of the box, not of the
    document, so it has to be asked of the box. }
  function BoxScope(ABox: TLedNBCellBox; ARow, ACol: Integer): string;
  var
    HL: TSynCustomHighlighter;
    Tok: PChar;
    TokLen, TokPos: Integer;
    Attr: TSynHighlighterAttributes;
  begin
    Result := '';
    if (ABox = nil) or (ABox.Editor = nil) then Exit;
    HL := ABox.Editor.Highlighter;
    if (HL = nil) or (ARow < 1) or (ARow > ABox.Editor.Lines.Count) then Exit;
    HL.StartAtLineIndex(ARow - 1);
    while not HL.GetEol do
    begin
      HL.GetTokenEx(Tok, TokLen);
      TokPos := HL.GetTokenPos;
      if (ACol > TokPos) and (ACol <= TokPos + TokLen) then
      begin
        Attr := HL.GetTokenAttribute;
        if Attr <> nil then Result := Attr.StoredName;
        Exit;
      end;
      HL.Next;
    end;
  end;

  { Every word of a rendered page, in the order it was laid out and decoded
    the way it is drawn.  Asked of the page rather than of the markup, so an
    escape that was written once and read twice shows up here. }
  function TextOfNode(ANode: TIpHtmlNode): string;
  var
    k: Integer;
  begin
    Result := '';
    if ANode is TIpHtmlNodeText then
      Result := TIpHtmlNodeText(ANode).ANSIText
    else if ANode is TIpHtmlNodeMulti then
      for k := 0 to TIpHtmlNodeMulti(ANode).ChildCount - 1 do
        Result := Result + TextOfNode(TIpHtmlNodeMulti(ANode).ChildNode[k]);
  end;

  function TextInPage(APanel: TIpHtmlPanel): string;
  begin
    Result := '';
    if (APanel = nil) or (APanel.MasterFrame = nil) or
       (APanel.MasterFrame.Html = nil) then Exit;
    Result := TextOfNode(APanel.MasterFrame.Html.HtmlNode);
  end;

  function LabelsIn(ABox: TLedNBCellBox): string;
  var
    k: Integer;
  begin
    Result := '';
    if ABox = nil then Exit;
    for k := 0 to ABox.ComponentCount - 1 do
      if ABox.Components[k] is TLabel then
        Result := Result + TLabel(ABox.Components[k]).Caption + '|';
  end;

begin
  Say('Jupyter notebook pane');

  Path := TempName('nbpane.ipynb');
  WriteBytes(Path, Fixture);

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  Doc.LoadFromFile(Path);
  Pump;
  Check('the notebook opened', Doc.IsNotebook);

  Pane := F.NotebookPane;
  Check('the window has a notebook pane', Pane <> nil);
  if Pane = nil then Exit;

  F.actToggleNotebookPane.Execute;
  Pump;
  Check('the pane is showing', F.Dock.PaneVisible('notebook'));
  CheckEqInt('it knows how many cells the notebook has', 5, Pane.CellCount);
  CheckGt('and has built the ones on screen', 0, Pane.BuiltCount);

  { ---- prose ---- }
  B := CellBox(Pane, 0);
  Check('the prose cell is rendered, not shown as source',
    (B <> nil) and (B.Rendered <> nil) and B.Rendered.Visible);
  Check('and has no Run button, because there is nothing to run',
    B.RunButton = nil);
  { Forty pixels was the bug -- one line and a scrollbar -- so the floor is
    set well above that and well below what a heading and three paragraphs
    come to in any font the renderer might choose. }
  CheckGt('a prose cell is as tall as its prose', 70, B.Rendered.Height);

  { ---- code and its text output ---- }
  B := CellBox(Pane, 1);
  Check('a code cell has an editor', (B <> nil) and (B.Editor <> nil));
  CheckEq('holding that cell and nothing else', 'print(''forty-two'')',
    TrimRight(B.Editor.Lines.Text));
  Check('its header says what ran', Pos('In [4]', LabelsIn(B)) > 0);
  Check('its output is under it: ' + LabelsIn(B),
    Pos('forty-two', LabelsIn(B)) > 0);
  Check('and it has a Run button', B.RunButton <> nil);

  { ---- the pictures, which are why this pane exists ---- }
  B := CellBox(Pane, 2);
  Img := ImageIn(B);
  Check('the plot is drawn as a picture', Img <> nil);
  { And only as a picture.  The file carries a text form beside it -- what
    the line view has to fall back on -- and a pane that shows both puts
    "<Figure>" under every plot. }
  Check('and not also as the text beside it: ' + LabelsIn(B),
    Pos('<Figure>', LabelsIn(B)) = 0);
  if Img <> nil then
  begin
    CheckEqInt('at the width it was stored at', 24, Img.Picture.Width);
    CheckEqInt('and the height', 9, Img.Picture.Height);
    CheckEqInt('and small enough to show whole, so it is not scaled',
      24, Img.Width);
  end;

  B := CellBox(Pane, 4);
  Img := ImageIn(B);
  Check('a wide plot is drawn too', Img <> nil);
  if Img <> nil then
  begin
    CheckEqInt('its own width is what the file says', 900, Img.Picture.Width);
    Check(Format('but it is shown no wider than its box (%d in %d)',
      [Img.Width, B.Width]), Img.Width <= B.Width);
    CheckGt('with a height to match, not squashed flat', 18, Img.Height);
    Check(Format('and in proportion (%d by %d, from 900 by 300)',
      [Img.Width, Img.Height]),
      Abs(Img.Width / Img.Height - 3.0) < 0.35);
  end;

  { ---- typing here arrives there ---- }
  B := CellBox(Pane, 3);
  Check('the last code cell has an editor', B.Editor <> nil);
  CheckGt('whose box fits the lines it holds',
    B.Editor.LineHeight * 2, B.Editor.Height);
  B.Editor.Lines.Text := 'x = 1' + #10 + 'y = 2' + #10 + 'z = 3';
  B.Editor.Modified := True;
  B.Commit;
  Pump;
  CheckEq('the notebook has what was typed',
    'x = 1' + #10 + 'y = 2' + #10 + 'z = 3', Doc.Notebook.CellSource(3));
  Check('and so does the line view',
    Pos('z = 3', Doc.Master.Lines.Text) > 0);
  Check('which still knows that line is a cell''s source',
    Doc.NBLineIsSource(Doc.NBSourceLineOf(3) + 2));
  Check('and the document is modified', Doc.Modified);
  CheckEqInt('with no cell added or lost', 5, Doc.NBCellCount);
  Check('and the header above it still a header',
    not Doc.NBLineIsSource(Doc.NBSourceLineOf(3) - 1));

  { ---- pressing Run must not destroy the cell it is in ---- }

  { The reported symptom was the editor going away on a click, with the LCL
    saying "TLedNBCellBox.Destroy with LCLRefCount>0.  Maybe the component is
    processing an event?"  It was: the kernel's change event rebuilt the whole
    pane, which releases every cell box -- including the one whose Run button
    was in the middle of its own click.

    So what is checked is that the box survives its own button.  The same
    box, not merely a box: a rebuilt pane would answer with a new one. }
  WasBox := CellBox(Pane, 1);
  WasBox.RunButton.Click;
  Pump; Pump;
  Check('the cell box outlives a press of its own Run button',
    Pane.BoxOf(1) = WasBox);
  { The deferred refresh has had its chance by now, and must not have swapped
    the box either. }
  Pump; Pump;
  Check('and still does once the deferred redraw has run',
    Pane.BoxOf(1) = WasBox);

  { And with a kernel on the machine, the click does what it is for: the cell
    runs and its output arrives in the box.  This is the whole path the
    report was about -- the button, the document, the helper, the kernel, and
    the redraw that comes back. }
  if NotebookKernelAvailable then
  begin
    { Asked of the cell, not of a position: a windowed pane builds what the
      viewport covers, and the cell has to be on screen to have a box at
      all.  The first version of this check polled a position and read an
      empty box for ninety seconds. }
    Deadline := Now + 90 / 86400.0;
    while (Now < Deadline) and
          (Pos('forty-two', LabelsIn(CellBox(Pane, 1))) = 0) do
    begin
      Pump;
      Sleep(20);
    end;
    Check('the cell ran and its output is in the pane: ' +
      LabelsIn(CellBox(Pane, 1)),
      Pos('forty-two', LabelsIn(CellBox(Pane, 1))) > 0);
    Check('and the header says it ran',
      Pos('In [1]', LabelsIn(CellBox(Pane, 1))) > 0);
    Doc.NBKernelStop;
    Pump;
  end;

  { ---- the wheel belongs to the page, not to the cell under it ---- }

  { Both windowed children swallow the wheel and have nothing to scroll,
    being exactly as tall as their contents, so a notch over a cell moved
    nothing at all. }
  B := CellBox(Pane, 0);
  Check('the prose control takes the wheel and passes it up',
    TLedProsePoke.Wheel(B.Rendered, -120));
  Check('a code cell is asked about the wheel too',
    Assigned(CellBox(Pane, 1).Editor.OnWheelPassedUp));

  Host := TForm.CreateNew(nil);
  try
    Host.SetBounds(0, 0, 500, 260);
    Loose := TLedNotebookPane.Create(Host);
    Loose.Parent := Host;
    Loose.Align := alNone;
    Loose.SetBounds(0, 0, 480, 240);
    Loose.ShowDocument(Doc);
    Pump;
    Host.Show;
    Pump; Pump;
    { There is somewhere to scroll to: asked by trying, because the range
      comes from the cells and not from anything a check should restate. }
    Loose.ScrollPos := 100000;
    Pump;
    CheckGt('this notebook is taller than this pane', 0, Loose.ScrollPos);

    Loose.ScrollPos := 0;
    Pump;
    TLedProsePoke.Wheel(Loose.BoxOf(0).Rendered, -120);
    Pump;
    CheckGt('a notch over the prose scrolls the page of cells', 0,
      Loose.ScrollPos);
    Was := Loose.ScrollPos;
    TLedProsePoke.Wheel(Loose.BoxOf(0).Rendered, 120);
    Pump;
    Check('and a notch the other way scrolls it back',
      Loose.ScrollPos < Was);

    { The same for a code cell, through the handler the editor is given. }
    Loose.ScrollPos := 0;
    Pump;
    Handled := False;
    CellBox(Loose, 1).Editor.OnWheelPassedUp(CellBox(Loose, 1).Editor, [],
      -120, Point(10, 10), Handled);
    Pump;
    Check('a notch over a code cell is taken', Handled);
  finally
    Host.Hide;
    Host.Free;
  end;

  { ---- the gestures and the glyph ---- }

  { Double click, which is what every notebook front end opens prose with.
    A single click is left alone so that text can still be selected and a
    link followed. }
  B := CellBox(Pane, 0);
  Check('prose is not being edited to start with', not B.Editing);
  TLedProsePoke.DoubleClick(B.Rendered);
  Pump;
  Check('a double click on prose opens it for editing', B.Editing);
  { And the way back is the button: once a cell is showing its source the
    rendered prose is not there to be clicked. }
  B.EditButton.Click;
  Pump;
  Check('and the button puts it back', not B.Editing);

  Check('the Run button wears LED''s own run icon rather than a character',
    (CellBox(Pane, 1).RunButton.Images <> nil) and
    (CellBox(Pane, 1).RunButton.ImageIndex >= 0));

  { ---- the box's own colouring follows the cell's magic ---- }

  { The pane used to colour every code cell as the notebook's language, so a
    %%octave cell was Python in the box and Octave in the line view -- the
    same cell, two answers.  A per cent sign tells them apart: it opens a
    remark in Octave and is an operator in Python. }
  Doc.NBSetCellSource(1, '%%octave' + #10 + '% a remark' + #10 +
    'A = [1 2];' + #10);
  Pane.RefreshCell(1);
  Pump;
  B := CellBox(Pane, 1);
  Check('the cell is coloured as Octave, where a per cent is a remark: ' +
    BoxScope(B, 2, 3), Pos('comment', BoxScope(B, 2, 3)) > 0);

  { And the magic line is drawn as a comment -- asked of a shell cell, where
    nothing else would make it one. }
  Doc.NBSetCellSource(1, '%%shell' + #10 + 'echo hello' + #10);
  Pane.RefreshCell(1);
  Pump;
  B := CellBox(Pane, 1);
  Check('the magic line in the box is drawn as a comment: ' +
    BoxScope(B, 1, 3), Pos('comment', BoxScope(B, 1, 3)) > 0);
  Check('and the command under it is not: ' + BoxScope(B, 2, 2),
    Pos('comment', BoxScope(B, 2, 2)) = 0);

  { The code in a cell is set a size up from the editor's own: the pane is a
    reading view, and at the editor's size the code came out smaller than the
    prose around it. }
  CheckGt('the code in a cell is larger than the editor''s own font',
    Doc.Master.Font.Size, CellBox(Pane, 1).Editor.Font.Size);

  { Fixed at ten points the prose came out smaller than the code beside it,
    which is the wrong way round.  It follows the reader's own editor font
    now, so a bigger editor font gives a bigger page. }
  CheckGt('prose is set larger than the code it explains',
    CellBox(Pane, 1).Editor.Font.Size,
    CellBox(Pane, 0).Rendered.DefaultFontSize);

  { ---- the mouse reaches the page, not the renderer's own control ---- }

  { The renderer draws into a control of its own inside the panel, and that
    control is what the mouse actually lands on: a wheel notch over rendered
    prose scrolled the renderer's own little scrollbar and a double click on
    it did nothing at all, because neither ever reached the panel.  So the
    handlers go on its children -- and this checks they landed on something,
    which is the difference between writing a hook and attaching one. }
  B := CellBox(Pane, 0);
  CheckGt('the renderer has a control of its own inside it', 0,
    B.Rendered.ControlCount);
  Inner := nil;
  if B.Rendered.ControlCount > 0 then Inner := B.Rendered.Controls[0];
  Check('which has been given the wheel handler',
    (Inner <> nil) and Assigned(TControlEvents(Inner).OnMouseWheel));
  Check('and the double-click handler',
    (Inner <> nil) and Assigned(TControlEvents(Inner).OnDblClick));

  { And they do what they are for, driven the way the LCL would drive them. }
  if Inner <> nil then
  begin
    Was := Pane.ScrollPos;
    Handled := False;
    TControlEvents(Inner).OnMouseWheel(Inner, [], -120, Point(10, 10),
      Handled);
    Pump;
    Check('a notch on the renderer''s own control is taken', Handled);

    { The notch scrolled the pane, and the pane is windowed: whether the
      cell that was clicked still has a box depends on how tall the cells
      happen to be.  So both are fetched again rather than reused -- holding
      the old ones and calling a handler on them was a jump into freed
      memory, and it only showed up when a change to the prose changed the
      heights. }
    B := CellBox(Pane, 0);
    Inner := nil;
    if (B <> nil) and (B.Rendered <> nil) and (B.Rendered.ControlCount > 0) then
      Inner := B.Rendered.Controls[0];
    Check('the cell is back on screen with its renderer', Inner <> nil);
  end;

  if Inner <> nil then
  begin
    Check('prose is not being edited before the double click', not B.Editing);
    TControlEvents(Inner).OnDblClick(Inner);
    Pump;
    Check('and a double click on it opens the cell for editing', B.Editing);
    B.EditButton.Click;
    Pump;
  end;

  { ---- what a prose cell makes of code and of raw HTML ---- }

  { The page a prose cell renders, asked of the same function the cell uses.
    Four of the five complaints are answered here and each is a line of it. }
  Page := LedPageColourCode(
    LedMarkdownToHTML('Some `inline code` and a block:' + #10 + #10 +
      '```c' + #10 + 'int count = 100;  /* a remark */' + #10 + '```' + #10),
    $00E0E0E0, $00202020);

  { A fence that names its language is coloured by that language's own
    highlighter -- the keyword and the remark cannot come out the same. }
  Check('a fenced block keeps the language it named',
    Pos('language-c', Page) > 0);
  Check('and its code is coloured a token at a time',
    Pos('color="#', Page) > 0);
  { Counted on the colour alone: a token carries its face as well, and a
    check that spelled out the whole tag went quietly green when the face
    was added in front of the colour. }
  Deep := 0;
  for i := 1 to Length(Page) - 7 do
    if Copy(Page, i, 8) = 'color="#' then Inc(Deep);
  CheckGt('with more than one colour in it, so it is not one flat block',
    3, Deep);

  { Monospaced text was in black on a dark theme -- black on near-black. }
  Check('inline code is given the page''s text colour rather than black',
    Pos('<code><font color="#e0e0e0">', LowerCase(Page)) > 0);
  { And deliberately no face is named: the renderer resolves one through
    CommaText, which splits "Fira Code" on the space, fails to find a font
    called Fira and falls back to the menu font -- which is how every
    monospaced stretch came out proportional.  The face comes from the
    panel's FixedTypeface, which is taken as given. }
  Check('and no face is named in the page, because naming one breaks it',
    Pos('face=', LowerCase(Page)) = 0);
  Check('the panel is told the reader''s own monospaced font instead',
    CellBox(Pane, 0).Rendered.FixedTypeface = Doc.Master.Font.Name);

  { And it gets there.  The cell is given a fence and a span of inline code,
    and the face is read off the nodes the renderer built for them: that is
    the question "does the reader see monospaced code", where the line above
    is only "was the panel told". }
  Doc.NBSetCellSource(0, 'Prose with `inline code` and a block:' + #10 +
    #10 + '```c' + #10 + '#include <stdio.h>' + #10 +
    '  if (a < b)  b++;' + #10 + '```' + #10);
  Pane.RefreshCell(0);
  Pump;
  B := CellBox(Pane, 0);
  { Both are <code> in the page -- a fence as much as a span, see
    Led.UI.PageStyle -- so the face is asked of the node that carries it. }
  CheckEq('code is drawn in the reader''s own monospaced face',
    Doc.Master.Font.Name, FaceInPage(B.Rendered, 'TIpHtmlNodePhrase'));

  { What the reader actually sees in the block, read back off the page.

    A fence used to be a <pre>, and this renderer takes the text of a <pre>
    as already decoded and escapes it again: a notebook full of "i < count"
    was drawn as "i &lt; count", six characters for one.  Writing the "<"
    raw instead loses it altogether -- the tokeniser reads "<s" as a tag --
    so neither spelling worked and the block is built out of <code> and
    <br> now. }
  Shown := TextInPage(B.Rendered);
  Check('a "<" in a code block is drawn as itself: ' +
    Copy(Shown, 1, 120), Pos('#include <stdio.h>', Shown) > 0);
  Check('and not as the escape that spells it',
    Pos('&lt;', Shown) = 0);
  { And the shape of the code survives, which is what a <pre> was for: the
    indent of a line and the columns inside it. }
  { The renderer holds a non-breaking space as #2 of its own, so that is
    what a page it has read back says: two of them are the two-space indent
    the line was written with. }
  Check('a line keeps the indent it was written with',
    Pos(#2#2 + 'if', Shown) > 0);
  Check('and the run of spaces inside it',
    Pos('b)' + #2#2 + 'b++', Shown) > 0);

  { Every token of a coloured block keeps the face, not just the block: a
    nested font tag replaces the face here rather than inheriting it, so a
    coloured token came back proportional and the block stopped looking like
    code the moment it was coloured. }
  { Counted on the colour alone, and with the length the literal actually
    has: the first version of this compared thirteen characters against a
    fourteen-character string and counted nothing for ever. }
  Deep := 0;
  for i := 1 to Length(Page) - 7 do
    if Copy(Page, i, 8) = 'color="#' then Inc(Deep);
  CheckGt('every token of a block carries its own colour', 3, Deep);

  { A table is drawn in the renderer's own black whatever the page says, so
    on a dark theme it came out unreadable beside prose that was fine. }
  Page := LedPageColourCode(
    LedMarkdownToHTML('| a | b |' + #10 + '| - | - |' + #10 +
      '| one | two |' + #10),
    $00E0E0E0, $00202020);
  Check('a table is rendered: ' + Copy(Page, 1, 60), Pos('<table', Page) > 0);
  Check('and its cells are given the page''s text colour',
    Pos('<td><font color="#e0e0e0">', LowerCase(Page)) > 0);
  Check('its heading cells too',
    Pos('<th><font color="#e0e0e0">', LowerCase(Page)) > 0);

  { Raw HTML, which markdown allows and notebooks are full of: Jupyter and
    Colab both render <font color=...>, and escaping it showed the reader the
    tag instead of the effect. }
  Page := LedMarkdownToHTML('a <font color="red">warning</font> and '
    + '<b>bold</b>' + #10);
  Check('a font tag written in a cell reaches the page: ' + Page,
    Pos('<font color="red">', Page) > 0);
  Check('and so does the text inside it', Pos('warning', Page) > 0);
  Page := LedMarkdownToHTML('this <script>alert(1)</script> is not markup'
    + #10);
  Check('but a tag that would run something is shown, not obeyed',
    (Pos('&lt;script&gt;', Page) > 0) and (Pos('<script>', Page) = 0));

  { ---- the pane follows the document ---- }

  { A notebook opened while the pane was showing left it on the last file:
    the pane was filled when it was opened and when the tab changed, and
    opening a file is neither of those if the tab it lands in was already the
    active one.  Driven through the window's own open, which is the path a
    reader takes. }
  Path := TempName('nbsecond.ipynb');
  WriteBytes(Path,
    '{"cells":[{"cell_type":"code","execution_count":null,"metadata":{},' +
    '"outputs":[],"source":["marker_of_the_second_file = 1"]}],' +
    '"metadata":{},"nbformat":4,"nbformat_minor":5}' + #10);
  Opened := TStringList.Create;
  try
    Opened.Add(Path);
    F.OpenFiles(Opened);
    Pump; Pump;
  finally
    Opened.Free;
  end;
  Check('the pane shows the notebook that was just opened',
    (F.ActiveTab <> nil) and F.ActiveTab.Document.IsNotebook and
    (Pane.Document = F.ActiveTab.Document));
  CheckEqInt('which has one cell', 1, Pane.CellCount);
  Check('and that cell is the one from the new file',
    Pos('marker_of_the_second_file', CellBox(Pane, 0).Editor.Lines.Text) > 0);
  F.CloseActiveTab(False);
  Pump;
  DeleteFile(Path);

  { ---- the colours are the theme's ---- }

  { The pane sat on a white sheet beside a dark editor until it was told to
    take its colours from the theme.  Two themes are used rather than one,
    because a check against a single scheme cannot tell a colour that was
    taken from the theme from a colour that happens to match it. }
  LedSetCurrentTheme('oblivion');
  Pane.Reload;
  Pump;
  Dark := LedPageColours;
  CheckEqInt('the pane is the theme''s page colour', Dark.Page, Pane.Color);
  CheckEqInt('and so is a cell', Dark.Page, CellBox(Pane, 0).Color);
  Check('a code cell sits on a shade of its own',
    CellBox(Pane, 1).Editor.Color <> Dark.Page);
  Check('which is close to the page rather than a colour of its own',
    Abs(LedColourLuma(CellBox(Pane, 1).Editor.Color) -
        LedColourLuma(Dark.Page)) < 40);
  Check('a dark theme gives a dark page', LedColourLuma(Dark.Page) < 128);

  LedSetCurrentTheme('solarized-light');
  Pane.Reload;
  Pump;
  Light := LedPageColours;
  Check('a light theme gives a light page', LedColourLuma(Light.Page) > 128);
  CheckEqInt('and the pane followed it', Light.Page, Pane.Color);
  Check('the cells followed too', CellBox(Pane, 0).Color = Light.Page);
  Check('and the code shade is still near the page',
    Abs(LedColourLuma(CellBox(Pane, 1).Editor.Color) -
        LedColourLuma(Light.Page)) < 40);
  { The label beside a cell recedes but stays legible, which is the same
    floor every other colour in LED has to clear. }
  Check(Format('the label is readable against the page (%.1f:1)',
    [LedContrastRatio(Light.Muted, Light.Page)]),
    LedContrastRatio(Light.Muted, Light.Page) > 2.5);
  LedSetCurrentTheme('medit');
  Pane.Reload;
  Pump;

  { ---- the boxes are laid out in order, none on top of another ---- }
  Bottom := -1;
  for i := 0 to Pane.BuiltCount - 1 do
  begin
    Check(Format('box %d is below the one before it', [i]),
      Pane.Box(i).Top > Bottom);
    Bottom := Pane.Box(i).Top;
    CheckGt(Format('box %d has a height', [i]), 0, Pane.Box(i).Height);
  end;

  DeleteFile(Path);

  { ---- a notebook taller than a control coordinate ---- }

  { The crash this pane was rewritten for.  A control's position in the LCL
    is a signed 16-bit number; a hundred cells of prose stack past 32767
    pixels, and the report that found it showed a cell being laid out at
    Top = 33133 before the editor came down.

    So the pane builds only what the viewport covers, and every box is
    positioned against the top of it.  What is checked is that: the notebook
    is far taller than the limit, the last cell is reachable, and no box is
    ever placed anywhere near 32767. }
  Path := TempName('nbtall.ipynb');
  WriteBytes(Path, TallNotebook(400));
  Doc.LoadFromFile(Path);
  Pump;
  Check('the tall notebook opened', Doc.IsNotebook);
  CheckEqInt('with four hundred cells', 400, Doc.NBCellCount);
  F.RefreshNotebookPane;
  Pump;

  CheckGt('it is taller than a control coordinate can hold', 32767,
    Pane.ScrollPos + Pane.CellCount * 100);
  Check(Format('but only the cells on screen are built (%d of 400)',
    [Pane.BuiltCount]), Pane.BuiltCount < 40);

  Deep := 0;
  for i := 0 to 12 do
  begin
    Pane.ScrollToCell(i * 30);
    Pump;
    if Pane.BuiltCount > 0 then
    begin
      if Abs(Pane.Box(0).Top) > Deep then Deep := Abs(Pane.Box(0).Top);
      if Abs(Pane.Box(Pane.BuiltCount - 1).Top) > Deep then
        Deep := Abs(Pane.Box(Pane.BuiltCount - 1).Top);
    end;
  end;
  Check(Format('no box is ever placed past a coordinate that fits (%d)',
    [Deep]), Deep < 32000);

  { And the end of the notebook is reachable, which is the other half of
    what windowing has to keep true. }
  Pane.ScrollToCell(399);
  Pump;
  Check('the last cell can be scrolled to', Pane.BoxOf(399) <> nil);
  Check('and it is the one at the top of the viewport',
    Pane.Box(0).Cell = 399);
  Pane.ScrollToCell(0);
  Pump;
  Check('and the first cell can be got back to', Pane.BoxOf(0) <> nil);

  DeleteFile(Path);
end;

{ The end of the file.

  A notebook whose last line is a cell's own source -- which is any notebook
  whose last cell has not been run -- is the shape that makes something ask
  about the line after the last one.  Answering that question wrongly is what
  made LED appear to hang on a real notebook: for a line past the end the
  document said "the last cell's source", so the scan looking for where that
  cell ends never found an end, and each step of it walked the file again.
  Eight thousand million steps, measured, and climbing.

  So the checks here are about the edges rather than the middle: what the
  document says about a line that does not exist, what the highlighter makes
  of the end of the file, and that walking the whole of a small notebook
  takes the time a small notebook should take. }
procedure TestNotebookBounds(F: TLedMainForm);
var
  Path: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  V: TLedEdit;
  i, Last, Spent: Integer;
  T0: TDateTime;

  function Fixture: string;
  begin
    Result :=
    '{' + #10 +
    ' "cells": [' + #10 +
    '  {' + #10 +
    '   "cell_type": "markdown",' + #10 +
    '   "metadata": {},' + #10 +
    '   "source": [' + #10 +
    '    "## A heading\n",' + #10 +
    '    "\n",' + #10 +
    '    "```c\n",' + #10 +
    '    "void main(void) {\n",' + #10 +
    '    "  int i = 0;\n",' + #10 +
    '    "}\n",' + #10 +
    '    "```"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": 1,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [' + #10 +
    '    {' + #10 +
    '     "name": "stdout",' + #10 +
    '     "output_type": "stream",' + #10 +
    '     "text": [' + #10 +
    '      "hi\n"' + #10 +
    '     ]' + #10 +
    '    }' + #10 +
    '   ],' + #10 +
    '   "source": [' + #10 +
    '    "print(''hi'')"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": null,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [],' + #10 +
    '   "source": [' + #10 +
    '    "def f(x):\n",' + #10 +
    '    "    return x + 1\n",' + #10 +
    '    "f(41)"' + #10 +
    '   ]' + #10 +
    '  }' + #10 +
    ' ],' + #10 +
    ' "metadata": {' + #10 +
    '  "kernelspec": {' + #10 +
    '   "display_name": "Python 3",' + #10 +
    '   "language": "python",' + #10 +
    '   "name": "python3"' + #10 +
    '  },' + #10 +
    '  "language_info": {' + #10 +
    '   "name": "python"' + #10 +
    '  }' + #10 +
    ' },' + #10 +
    ' "nbformat": 4,' + #10 +
    ' "nbformat_minor": 5' + #10 +
    '}' + #10 +
    '';
  end;

begin
  Say('Jupyter notebook edges');

  Path := TempName('nbedge.ipynb');
  WriteBytes(Path, Fixture);

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  V := Tab.ActiveView;
  Doc.LoadFromFile(Path);
  Pump;
  Check('it opened', Doc.IsNotebook);

  Last := Doc.Master.Lines.Count - 1;
  Check('the last line of the file is a cell''s own source, which is the '
    + 'shape that asks past the end', Doc.NBLineIsSource(Last));

  { The answers that must be "nothing". }
  Check('the line after the last is not source',
    not Doc.NBLineIsSource(Last + 1));
  CheckEqInt('and belongs to no cell', -1, Doc.NBCellOfLine(Last + 1));
  Check('nor is one far past the end',
    not Doc.NBLineIsSource(Last + 5000));
  CheckEqInt('which also belongs to no cell', -1,
    Doc.NBCellOfLine(Last + 5000));
  Check('nor is a negative line', not Doc.NBLineIsSource(-1));
  CheckEqInt('and that belongs to no cell either', -1, Doc.NBCellOfLine(-2));

  { And the fold consequence: nothing is left open past the end of the file. }
  CheckEqInt('no fold block is open past the last line', 0,
    TLedNBHighlighter(V.Highlighter).FoldBlockEndLevel(Last + 1));

  { The whole file walked, which is what a paint and the fold scan do.  The
    bound is loose on purpose -- what it catches is not a slow machine but a
    scan that does not terminate. }
  T0 := Now;
  for i := 0 to Last do
  begin
    V.CaretXY := Point(1, i + 1);
    TLedNBHighlighter(V.Highlighter).FoldBlockEndLevel(i);
  end;
  Pump;
  Spent := Round((Now - T0) * 86400000);
  CheckGt(Format('walking a %d-line notebook takes a moment, not minutes '
    + '(%d ms)', [Last + 1, Spent]), Spent, 5000);

  DeleteFile(Path);
end;

{ Running cells.

  The whole point of driving a real kernel is that it is a real kernel, so
  this runs one: the checks below start python3, send it a cell and wait for
  the answer to come back into the buffer.  Where the machine has no kernel
  installed they do nothing, which is the bargain the gdb checks already
  make with a missing toolchain -- a check that quietly passes is better than
  a suite that cannot run anywhere but one desk.

  What is asserted is the round trip through everything: the action finds the
  cell, the document sends the source the buffer holds, the helper runs it,
  the output arrives as nbformat, the cell keeps it, and the page shows it. }
procedure TestNotebookRunning(F: TLedMainForm);
var
  Path, Why: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  V: TLedEdit;
  Deadline: TDateTime;
  Have: Boolean;
  P: TProcess;
  Handled: Boolean;
  Line: Integer;

  function Fixture: string;
  begin
    Result :=
    '{' + #10 +
    ' "cells": [' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": null,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [],' + #10 +
    '   "source": [' + #10 +
    '    "print(6 * 7)"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "markdown",' + #10 +
    '   "metadata": {},' + #10 +
    '   "source": [' + #10 +
    '    "# Notes"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": null,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [],' + #10 +
    '   "source": [' + #10 +
    '    "x = 41\n",' + #10 +
    '    "x + 101"' + #10 +
    '   ]' + #10 +
    '  }' + #10 +
    ' ],' + #10 +
    ' "metadata": {' + #10 +
    '  "kernelspec": {' + #10 +
    '   "display_name": "Python 3",' + #10 +
    '   "language": "python",' + #10 +
    '   "name": "python3"' + #10 +
    '  },' + #10 +
    '  "language_info": {' + #10 +
    '   "name": "python"' + #10 +
    '  }' + #10 +
    ' },' + #10 +
    ' "nbformat": 4,' + #10 +
    ' "nbformat_minor": 5' + #10 +
    '}' + #10 +
    '';
  end;

  function LineOfText(const AWhat: string): Integer;
  var
    i: Integer;
  begin
    Result := -1;
    for i := 0 to Doc.Master.Lines.Count - 1 do
      if Pos(AWhat, Doc.Master.Lines[i]) > 0 then Exit(i);
  end;

  { Pumps the message loop until AWhat is on the page, or until time is up.
    The document polls its kernel from a timer, so this is the self-test
    standing in for the reader sitting and waiting. }
  function WaitFor(const AWhat: string; ASeconds: Integer): Boolean;
  begin
    Deadline := Now + ASeconds / 86400.0;
    while Now < Deadline do
    begin
      Pump;
      if LineOfText(AWhat) >= 0 then Exit(True);
      Sleep(20);
    end;
    Result := LineOfText(AWhat) >= 0;
  end;

  { The kernel says a cell has finished in a message of its own, after the
    output of it: waiting for what the cell printed is not waiting for the
    run to be over, and reading the count straight afterwards was a race
    this lost whenever the editor was busy in between. }
  function WaitForCount(ACell, ACount, ASeconds: Integer): Boolean;
  begin
    Deadline := Now + ASeconds / 86400.0;
    while Now < Deadline do
    begin
      Pump;
      if Doc.Notebook.CellExecutionCount(ACell) = ACount then Exit(True);
      Sleep(20);
    end;
    Result := Doc.Notebook.CellExecutionCount(ACell) = ACount;
  end;

begin
  Say('Jupyter notebook running');

  { Is there a kernel to run?  Asked of the Python the document would use. }
  Have := FileExists(LedKernelHelper);
  if Have then
  begin
    P := TProcess.Create(nil);
    try
      P.Executable := LedKernelPython;
      P.Parameters.Add('-c');
      P.Parameters.Add('import jupyter_client, ipykernel');
      P.Options := [poWaitOnExit, poUsePipes, poNoConsole];
      try
        P.Execute;
        Have := P.ExitStatus = 0;
      except
        Have := False;
      end;
    finally
      P.Free;
    end;
  end;

  Path := TempName('nbrun.ipynb');
  WriteBytes(Path, Fixture);

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  V := Tab.ActiveView;
  Doc.LoadFromFile(Path);
  Pump;
  Check('the notebook opened', Doc.IsNotebook);

  { The wiring, which is checked whether or not there is a kernel. }
  Handled := False;
  V.CaretXY := Point(1, 2);
  Pump;
  F.ActionList1Update(F.actRunCell, Handled);
  Check('Run Cell is offered on a code cell', F.actRunCell.Enabled);
  CheckEqInt('and it knows which cell the caret is in', 0, F.CellAtCaret);
  Check('the notebook menu is showing', F.miNotebook.Visible);
  Check('nothing is running yet',
    Doc.NBKernelState = lksOff);
  CheckEq('which the status bar says', 'No kernel', Doc.NBKernelStatus);

  Line := LineOfText('# Notes');
  V.CaretXY := Point(1, Line + 1);
  Pump;
  Check('running a markdown cell is refused',
    not Doc.NBRunCell(F.CellAtCaret, Why));
  Check('with a reason: ' + Why, Pos('code cell', Why) > 0);

  if not Have then
  begin
    Say('  (no kernel on this machine; the rest of this needs one)');
    DeleteFile(Path);
    Exit;
  end;

  { ---- and now for real ---- }

  V.CaretXY := Point(1, 2);
  Pump;
  F.actRunCell.Execute;
  Pump;
  Check('the kernel is starting or already up',
    Doc.NBKernelState in [lksStarting, lksIdle, lksBusy]);

  Check('what the cell printed arrives on the page',
    WaitFor('42', 90));
  Check('the output is in the cell, not just on the screen',
    (Doc.Notebook.CellOutputs(0) <> nil) and
    (Doc.Notebook.CellOutputs(0).Count > 0));
  Check('and the cell knows it has run once', WaitForCount(0, 1, 30));
  Check('which the header shows: ' + Doc.Master.Lines[0],
    Pos('[1]', Doc.Master.Lines[0]) = 1);
  Check('the document is modified, because the file has new output in it',
    Doc.Modified);
  Check('and the output line cannot be typed into',
    not Doc.NBLineIsSource(LineOfText('42')));

  { A second cell, in the same session: it can see what the first one left
    behind, which is the whole reason a kernel is a session and not a
    subprocess per cell. }
  Line := Doc.NBSourceLineOf(2);
  CheckGt('the third cell is on the page', 0, Line);
  V.CaretXY := Point(1, Line + 1);
  Pump;
  CheckEqInt('the caret is in it', 2, F.CellAtCaret);
  F.actRunCell.Execute;
  { A value the first cell did not print.  Waiting for 42 here passed while
    the second run had not finished at all: the 42 on the page was the first
    cell's output, and the check was reading that. }
  Check('its result comes back', WaitFor('142', 90));
  CheckEqInt('as the second thing run in this session',
    2, Doc.Notebook.CellExecutionCount(2));
  Check('so the two cells ran in one session, sharing what the first left '
    + 'behind', LineOfText('142') > 0);

  { Saving writes the outputs the kernel produced. }
  Doc.Save;
  Pump;
  Check('saving leaves it unmodified', not Doc.Modified);
  Doc.LoadFromFile(Path);
  Pump;
  Check('and the output is in the file on disk', LineOfText('42') > 0);
  CheckEqInt('with the execution count', 1,
    Doc.Notebook.CellExecutionCount(0));

  Doc.NBKernelStop;
  Pump;
  DeleteFile(Path);
end;

{ Colouring a notebook.

  Two claims are worth checking and they are different claims.  The lines LED
  writes -- the header, the output -- are coloured from what the document
  knows about them, so they must differ from each other and from the code.
  And a source line must be coloured by the real highlighter for the cell's
  language: not something notebook-shaped that approximates Python, but the
  same tokens the same Python file would get, which is what the last check
  compares against.

  Asked of SynEdit rather than of the highlighter: what is wanted is the
  attribute the editor would paint with at a place on the page. }
procedure TestNotebookColouring(F: TLedMainForm);
var
  Path: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  V: TLedEdit;
  Line: Integer;
  Was: string;

  function Fixture: string;
  begin
    Result :=
    '{' + #10 +
    ' "cells": [' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": 1,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [' + #10 +
    '    {' + #10 +
    '     "name": "stdout",' + #10 +
    '     "output_type": "stream",' + #10 +
    '     "text": [' + #10 +
    '      "3\n"' + #10 +
    '     ]' + #10 +
    '    }' + #10 +
    '   ],' + #10 +
    '   "source": [' + #10 +
    '    "import numpy as np\n",' + #10 +
    '    "def f(x):\n",' + #10 +
    '    "    \"\"\"a docstring\n",' + #10 +
    '    "    over two lines\"\"\"\n",' + #10 +
    '    "    return x\n",' + #10 +
    '    "print(3)"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "markdown",' + #10 +
    '   "metadata": {},' + #10 +
    '   "source": [' + #10 +
    '    "# A heading\n",' + #10 +
    '    "\n",' + #10 +
    '    "some prose"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": 2,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [' + #10 +
    '    {' + #10 +
    '     "ename": "ZeroDivisionError",' + #10 +
    '     "evalue": "division by zero",' + #10 +
    '     "output_type": "error",' + #10 +
    '     "traceback": [' + #10 +
    '      "ZeroDivisionError: division by zero"' + #10 +
    '     ]' + #10 +
    '    }' + #10 +
    '   ],' + #10 +
    '   "source": [' + #10 +
    '    "1/0"' + #10 +
    '   ]' + #10 +
    '  }' + #10 +
    ' ],' + #10 +
    ' "metadata": {' + #10 +
    '  "kernelspec": {' + #10 +
    '   "display_name": "Python 3",' + #10 +
    '   "language": "python",' + #10 +
    '   "name": "python3"' + #10 +
    '  },' + #10 +
    '  "language_info": {' + #10 +
    '   "name": "python"' + #10 +
    '  }' + #10 +
    ' },' + #10 +
    ' "nbformat": 4,' + #10 +
    ' "nbformat_minor": 5' + #10 +
    '}' + #10 +
    '';
  end;

  function MagicFixture: string;
  begin
    Result :=
    '{' + #10 +
    ' "cells": [' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": 1,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [],' + #10 +
    '   "source": [' + #10 +
    '    "%load_ext autoreload\n",' + #10 +
    '    "!pip install numpy\n",' + #10 +
    '    "x = [1, 2]\n",' + #10 +
    '    "disp(x)"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": 2,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [],' + #10 +
    '   "source": [' + #10 +
    '    "%%octave\n",' + #10 +
    '    "A = [1 2; 3 4];\n",' + #10 +
    '    "!x = 1\n",' + #10 +
    '    "disp(A)"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": 3,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [],' + #10 +
    '   "source": [' + #10 +
    '    "%%shell\n",' + #10 +
    '    "echo hello"' + #10 +
    '   ]' + #10 +
    '  }' + #10 +
    ' ],' + #10 +
    ' "metadata": {' + #10 +
    '  "kernelspec": {' + #10 +
    '   "display_name": "Python 3",' + #10 +
    '   "language": "python",' + #10 +
    '   "name": "python3"' + #10 +
    '  },' + #10 +
    '  "language_info": {' + #10 +
    '   "name": "python"' + #10 +
    '  }' + #10 +
    ' },' + #10 +
    ' "nbformat": 4,' + #10 +
    ' "nbformat_minor": 5' + #10 +
    '}' + #10 +
    '';
  end;

  function LineOfText(const AWhat: string): Integer;
  var
    i: Integer;
  begin
    Result := -1;
    for i := 0 to Doc.Master.Lines.Count - 1 do
      if Pos(AWhat, Doc.Master.Lines[i]) > 0 then Exit(i);
  end;

  { The attribute SynEdit would paint at a 1-based row and column, by name.
    The name is the theme scope the highlighter asked for, which is what says
    whether the right thing was decided. }
  function ScopeAt(ARow, ACol: Integer): string;
  var
    Token: string;
    Attr: TSynHighlighterAttributes;
  begin
    Result := '';
    Attr := nil;
    if V.GetHighlighterAttriAtRowCol(Point(ACol, ARow), Token, Attr) and
       (Attr <> nil) then
      Result := Attr.StoredName;
  end;

  function ColourAt(ARow, ACol: Integer): TColor;
  var
    Token: string;
    Attr: TSynHighlighterAttributes;
  begin
    Result := clNone;
    Attr := nil;
    if V.GetHighlighterAttriAtRowCol(Point(ACol, ARow), Token, Attr) and
       (Attr <> nil) then
      Result := Attr.Foreground;
  end;

begin
  Say('Jupyter notebook colouring');

  Path := TempName('nbcolour.ipynb');
  WriteBytes(Path, Fixture);

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  V := Tab.ActiveView;
  Doc.LoadFromFile(Path);
  Pump;

  Check('the notebook opened', Doc.IsNotebook);
  Check('and has a highlighter of its own',
    V.Highlighter is TLedNBHighlighter);

  { The lines LED writes. }
  CheckEq('a header is coloured as a declaration', 'def.type',
    ScopeAt(1, 2));
  Line := LineOfText('out ');
  CheckGt('there is an output block', 0, Line);
  CheckEq('its label is a remark', 'def.comment', ScopeAt(Line + 1, 2));
  CheckEq('and the output under it is not', 'def.doc-comment',
    ScopeAt(Line + 2, 3));

  { A traceback is an error, and every theme has a colour for that. }
  Line := LineOfText('ZeroDivisionError');
  CheckGt('the traceback is on the page', 0, Line);
  CheckEq('and is coloured as an error', 'def.error', ScopeAt(Line + 1, 4));

  { And the code.  What says a real language highlighter ran is that the
    parts of a line of Python are told apart: "import" and the module name
    beside it come back as different scopes, and neither is one of the
    notebook's own.  Which scope Python's grammar gives a keyword is its
    business -- it calls "import" a preprocessor, as it happens -- so the
    check is the distinction rather than a name guessed from outside. }
  Line := LineOfText('import numpy');
  CheckGt('the code is on the page', 0, Line);
  Check('the keyword and the name after it are coloured differently: ' +
    ScopeAt(Line + 1, 2) + ' vs ' + ScopeAt(Line + 1, 9),
    (ScopeAt(Line + 1, 2) <> '') and
    (ScopeAt(Line + 1, 2) <> ScopeAt(Line + 1, 9)));
  Check('and the code is not coloured as one of LED''s own lines',
    (ScopeAt(Line + 1, 2) <> 'def.type') and
    (ScopeAt(Line + 1, 2) <> 'def.comment') and
    (ScopeAt(Line + 1, 2) <> 'def.doc-comment'));

  { A docstring runs over three lines.  The second and third are only inside
    it if the highlighter was told where the first left off, which is the
    state this view has to carry from line to line inside a cell. }
  Line := LineOfText('"""a docstring');
  CheckGt('the docstring is on the page', 0, Line);
  Check('its first line is a string: ' + ScopeAt(Line + 1, 5),
    Pos('string', ScopeAt(Line + 1, 5)) > 0);
  Check('and so is its second, which only holds if the state carried: ' +
    ScopeAt(Line + 2, 5),
    Pos('string', ScopeAt(Line + 2, 5)) > 0);
  Check('while the line after the docstring is not',
    Pos('string', ScopeAt(Line + 4, 5)) = 0);

  { Markdown cells go to the markdown highlighter, not the Python one. }
  Line := LineOfText('# A heading');
  CheckGt('the markdown cell is on the page', 0, Line);
  Check('and its heading is not coloured as Python: ' + ScopeAt(Line + 1, 3),
    Pos('keyword', ScopeAt(Line + 1, 3)) = 0);

  { Folding: a cell is a block, and its output is a block inside it. }
  Line := LineOfText('import numpy');
  CheckGt('the cell body is inside one fold level', 0,
    TLedNBHighlighter(V.Highlighter).FoldBlockEndLevel(Line - 1));
  CheckGt('and the output is a block inside it',
    TLedNBHighlighter(V.Highlighter).FoldBlockEndLevel(Line - 1),
    TLedNBHighlighter(V.Highlighter).FoldBlockEndLevel(LineOfText('out ') + 1));


  { A cell magic names the language for its own cell, whatever the notebook
    says.  These notebooks run MATLAB code in %%octave cells inside a Python
    notebook, so colouring every cell as Python would colour half the file
    as the wrong language. }
  Path := TempName('nbmagic.ipynb');
  WriteBytes(Path, MagicFixture);
  Doc.LoadFromFile(Path);
  Pump;
  Line := LineOfText('disp(x)');
  CheckGt('the Python cell is on the page', 0, Line);
  Was := ScopeAt(Line + 1, 1);
  Line := LineOfText('%%octave');
  CheckGt('and so is the octave cell', 0, Line);
  Check('the magic line itself is not treated as a header',
    Doc.NBLineIsSource(Line));
  { "disp" is a function in both languages but the two grammars are
    different files with different scope names, so what is checked is that
    the same word in the two cells is not coloured the same way. }
  Check('a %%octave cell is coloured as Octave, not as Python: ' +
    Was + ' vs ' + ScopeAt(Line + 3, 1),
    (ScopeAt(Line + 3, 1) <> '') and (ScopeAt(Line + 3, 1) <> Was));
  Check('and a matrix literal is not plain text',
    ScopeAt(Line + 2, 6) <> '');

  { ---- a magic is drawn the way a comment is drawn ---- }

  { It is Jupyter's word and not the language's: no highlighter can read
    "%%octave" or "!pip install numpy" as code, and every one of them called
    it an error or an operator.  A front end draws them as what they are, an
    instruction to itself, which is what a comment looks like. }
  { Asked of the %%shell cell and not of the %%octave one: a per cent opens
    a remark in Octave, so that cell's magic line was drawn as a comment
    whether or not this worked -- the check passed with the whole thing
    switched off.  Nothing in a shell script makes "%%shell" a comment. }
  Line := LineOfText('%%shell');
  CheckGt('the shell cell is on the page', 0, Line);
  Check('the cell magic line is drawn as a comment: ' + ScopeAt(Line + 1, 3),
    Pos('comment', ScopeAt(Line + 1, 3)) > 0);
  Check('and the shell command under it is not: ' + ScopeAt(Line + 2, 2),
    Pos('comment', ScopeAt(Line + 2, 2)) = 0);
  Line := LineOfText('%load_ext');
  CheckGt('the line magic is on the page', 0, Line);
  Check('and a line magic is too: ' + ScopeAt(Line + 1, 3),
    Pos('comment', ScopeAt(Line + 1, 3)) > 0);
  Line := LineOfText('!pip install');
  CheckGt('the shell escape is on the page', 0, Line);
  Check('and a shell escape with it: ' + ScopeAt(Line + 1, 3),
    Pos('comment', ScopeAt(Line + 1, 3)) > 0);

  { But only where they mean anything.  Inside a cell %%octave has handed to
    another language a '!' is that language's own -- Octave's not-equals --
    and drawing it as a comment would be a lie about the code. }
  Line := LineOfText('!x = 1');
  CheckGt('the bang inside the octave cell is on the page', 0, Line);
  Check('and is left to Octave rather than taken for a magic: ' +
    ScopeAt(Line + 1, 1),
    Pos('comment', ScopeAt(Line + 1, 1)) = 0);

  { The header says which language the cell turned out to be, so a reader can
    see that the magic was read rather than having to infer it from the
    colours. }
  Line := LineOfText('%%octave');
  Check('the header above a magic cell names the cell''s language: ' +
    Doc.Master.Lines[Line - 1],
    Pos('] octave', Doc.Master.Lines[Line - 1]) > 0);
  Line := LineOfText('x = [1, 2]');
  Check('and a cell with no magic still names the notebook''s: ' +
    Doc.Master.Lines[Line - 3],
    Pos('] python', Doc.Master.Lines[Line - 3]) > 0);

  { And the code either side of a magic is still code. }
  Line := LineOfText('x = [1, 2]');
  Check('the code below a magic is coloured as code: ' + ScopeAt(Line + 1, 1),
    ScopeAt(Line + 1, 1) <> '');

  DeleteFile(Path);
end;

{ Editing a Jupyter notebook.

  The buffer is a rendering of the file -- headers, source and output -- and
  only the source lines are the file's own text.  What is checked here is
  that the two stay in step: that the lines which are a rendering cannot be
  typed into, that the ones which are the file's text can, that typing moves
  the map of which line belongs to which cell, and that saving writes the
  notebook rather than the page.

  The strongest check is the last one: a notebook opened and saved without
  being touched comes back byte for byte.  Everything else could be right
  and that still fail, and if it fails every save is a whole-file diff. }
procedure TestNotebookEditing(F: TLedMainForm);
var
  Path, Saved, Raw, Was: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  V: TLedEdit;
  Line, Cell, NewLine: Integer;
  NB: TLedNotebook;
  Err: string;
  Written: TJSONObject;

  function Fixture: string;
  begin
    Result :=
    '{' + #10 +
    ' "cells": [' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": 1,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [' + #10 +
    '    {' + #10 +
    '     "name": "stdout",' + #10 +
    '     "output_type": "stream",' + #10 +
    '     "text": [' + #10 +
    '      "3\n"' + #10 +
    '     ]' + #10 +
    '    }' + #10 +
    '   ],' + #10 +
    '   "source": [' + #10 +
    '    "a = 1\n",' + #10 +
    '    "print(a + 2)"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "markdown",' + #10 +
    '   "metadata": {},' + #10 +
    '   "source": [' + #10 +
    '    "# Notes"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": null,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [],' + #10 +
    '   "source": []' + #10 +
    '  }' + #10 +
    ' ],' + #10 +
    ' "metadata": {' + #10 +
    '  "kernelspec": {' + #10 +
    '   "display_name": "Python 3",' + #10 +
    '   "language": "python",' + #10 +
    '   "name": "python3"' + #10 +
    '  },' + #10 +
    '  "language_info": {' + #10 +
    '   "name": "python"' + #10 +
    '  }' + #10 +
    ' },' + #10 +
    ' "nbformat": 4,' + #10 +
    ' "nbformat_minor": 5' + #10 +
    '}' + #10 +
    '';
  end;

  function LineOfText(const AWhat: string): Integer;
  var
    i: Integer;
  begin
    Result := -1;
    for i := 0 to Doc.Master.Lines.Count - 1 do
      if Pos(AWhat, Doc.Master.Lines[i]) > 0 then Exit(i);
  end;

begin
  Say('Jupyter notebook editing');

  Path := TempName('nb.ipynb');
  WriteBytes(Path, Fixture);

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  V := Tab.ActiveView;
  Doc.LoadFromFile(Path);
  Pump;

  Check('a .ipynb opens as a notebook', Doc.IsNotebook);
  Check('and not as a binary', not Doc.IsBinary);
  Check('the buffer shows the cells, not the JSON',
    Pos('"cells"', Doc.Master.Lines.Text) = 0);
  Check('the first line is a header: ' + Doc.Master.Lines[0],
    Pos('[1] python', Doc.Master.Lines[0]) = 1);
  CheckEq('and the line under it is the cell', 'a = 1',
    Doc.Master.Lines[1]);
  CheckEqInt('three cells', 3, Doc.NBCellCount);
  Check('the output is on the page', LineOfText('  3') > 0);

  { ---- which line is what ---- }

  Check('a header is not source', not Doc.NBLineIsSource(0));
  Check('the cell text is', Doc.NBLineIsSource(1));
  CheckEqInt('and belongs to the first cell', 0, Doc.NBCellOfLine(1));
  Line := LineOfText('# Notes');
  Check('the markdown cell is source too', Doc.NBLineIsSource(Line));
  CheckEqInt('in the second cell', 1, Doc.NBCellOfLine(Line));
  Check('the gap between cells is not source',
    not Doc.NBLineIsSource(Line - 2));
  CheckEqInt('and belongs to no cell', -1, Doc.NBCellOfLine(Line - 2));

  { ---- what may be typed into ---- }

  Was := Doc.Master.Lines[0];
  V.CaretXY := Point(3, 1);
  V.CommandProcessor(ecChar, 'x', nil);
  Pump;
  CheckEq('typing on a header does nothing', Was, Doc.Master.Lines[0]);

  V.CaretXY := Point(1, 2);
  V.CommandProcessor(ecChar, 'x', nil);
  Pump;
  CheckEq('typing on the cell text types', 'xa = 1', Doc.Master.Lines[1]);
  V.CommandProcessor(ecDeleteLastChar, '', nil);
  Pump;
  CheckEq('and comes back out again', 'a = 1', Doc.Master.Lines[1]);

  { The edges: a backspace at the left margin of the first line would pull
    the cell into its header, and a delete at the end of the last would
    swallow the output label. }
  V.CaretXY := Point(1, 2);
  V.CommandProcessor(ecDeleteLastChar, '', nil);
  Pump;
  CheckEqInt('backspace at the start of a cell does not eat the header',
    3, Doc.NBCellCount);
  Check('which is still a header', not Doc.NBLineIsSource(0));
  CheckEq('and the cell still starts where it did', 'a = 1',
    Doc.Master.Lines[1]);

  Line := LineOfText('print(a + 2)');
  V.CaretXY := Point(Length(Doc.Master.Lines[Line]) + 1, Line + 1);
  V.CommandProcessor(ecDeleteChar, '', nil);
  Pump;
  CheckEq('and delete at the end does not eat the output label',
    'print(a + 2)', Doc.Master.Lines[Line]);

  { An output line is a rendering as well. }
  Line := LineOfText('  3');
  Was := Doc.Master.Lines[Line];
  V.CaretXY := Point(3, Line + 1);
  V.CommandProcessor(ecChar, 'z', nil);
  Pump;
  CheckEq('output cannot be typed into', Was, Doc.Master.Lines[Line]);

  { ---- typing moves the map ---- }

  Line := LineOfText('print(a + 2)');
  V.CaretXY := Point(Length(Doc.Master.Lines[Line]) + 1, Line + 1);
  V.CommandProcessor(ecLineBreak, '', nil);
  Pump;
  V.CommandProcessor(ecChar, 'b', nil);
  Pump;
  NewLine := Line + 1;
  CheckEq('a new line in a cell takes what is typed', 'b',
    Doc.Master.Lines[NewLine]);
  Check('and is part of the cell', Doc.NBLineIsSource(NewLine));
  CheckEqInt('the same cell', 0, Doc.NBCellOfLine(NewLine));
  Check('the output label moved down with it',
    Pos('out', Doc.Master.Lines[NewLine + 1]) = 1);
  Check('and the markdown cell is still the markdown cell',
    Doc.NBCellOfLine(LineOfText('# Notes')) = 1);

  { ---- saving writes the notebook ---- }

  Doc.Save;
  Pump;
  Check('saving a notebook leaves it unmodified', not Doc.Modified);
  Saved := '';
  with TFileStream.Create(Path, fmOpenRead) do
    try
      SetLength(Saved, Size);
      if Size > 0 then Read(Saved[1], Size);
    finally
      Free;
    end;
  Check('what was written is JSON again', Pos('"cells"', Saved) > 0);
  Check('with the typed line in it', Pos('print(a + 2)\n', Saved) > 0);
  Check('and the line that was added', Pos('"b"', Saved) > 0);

  NB := TLedNotebook.Create;
  try
    Check('and it parses as a notebook: ' + Err, NB.LoadFromText(Saved, Err));
    CheckEq('the cell now holds both lines',
      'a = 1' + #10 + 'print(a + 2)' + #10 + 'b', NB.CellSource(0));
    CheckEq('and the other cells are untouched', '# Notes', NB.CellSource(1));
  finally
    NB.Free;
  end;

  { ---- outputs come from the file, not from the page ---- }

  Doc.Notebook.ClearCellOutputs(0);
  Written := TJSONObject.Create;
  Written.Add('output_type', 'stream');
  Written.Add('name', 'stdout');
  Written.Add('text', TJSONArray.Create(['forty-two' + #10]));
  Doc.Notebook.AddCellOutput(0, Written);
  Doc.NBRefreshCell(0);
  Pump;
  Check('a re-rendered cell shows its new output',
    LineOfText('forty-two') > 0);
  Check('and the old output is gone', LineOfText('  3') < 0);
  CheckEq('while its source is left alone', 'a = 1', Doc.Master.Lines[1]);
  Check('and the source is still source', Doc.NBLineIsSource(1));

  { ---- and the round trip the whole thing rests on ---- }

  Path := TempName('nb2.ipynb');
  WriteBytes(Path, Fixture);
  Doc.LoadFromFile(Path);
  Pump;
  Check('it opens again', Doc.IsNotebook);
  Doc.Save;
  Pump;
  Raw := '';
  with TFileStream.Create(Path, fmOpenRead) do
    try
      SetLength(Raw, Size);
      if Size > 0 then Read(Raw[1], Size);
    finally
      Free;
    end;
  CheckEq('a notebook saved without being touched is the same bytes',
    Fixture, Raw);

  DeleteFile(Path);
end;

{ Changing a value in a structure view, which is the half of the BJData work
  that writes.  What is measured here is the document's side of it -- the
  view is a rendering, so "it worked" means the bytes changed and the page
  agrees with them afterwards -- plus the three gestures that reach it. }
procedure TestBJDataEditing(F: TLedMainForm);
var
  Path, Raw, Opened, Why: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  Kind: TLedBJEditKind;
  Moved: PtrUInt;
  i, Bad: Integer;
  Key: Word;
  Handled: Boolean;

  function L4(AValue: LongInt): string;
  begin
    SetLength(Result, 4);
    Move(AValue, Result[1], 4);
  end;

  function D8(AValue: Double): string;
  begin
    SetLength(Result, 8);
    Move(AValue, Result[1], 8);
  end;

begin
  Say('Binary JData editing');

  { One of each thing an edit has to deal with: a number whose marker is
    wider than it needs, a string, a float, a boolean, an array that is
    rendered on one line, and a container held back for being large. }
  Raw := '{' + #$55#$01'n' + 'l' + L4(1000)
             + #$55#$01's' + 'S' + #$55#$05 + 'hello'
             + #$55#$01'f' + 'D' + D8(1.5)
             + #$55#$01'b' + 'T'
             + #$55#$03'arr' + '[' + 'i'#$01 + 'i'#$02 + ']'
             + #$55#$03'big' + '[';
  for i := 1 to LedBJMaxElements + 1 do
    Raw := Raw + '{' + #$55#$01'a' + #$55#$01 + '}';
  Raw := Raw + ']' + '}';

  Path := TempName('edit.bjd');
  WriteBytes(Path, Raw);

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  Doc.LoadFromFile(Path);
  Pump;

  Check('it opens as a structure', Doc.IsBJData);
  Opened := Doc.Master.Lines.Text;
  Check('and nothing has been changed yet', not Doc.Modified);

  { ---- what can be edited ---- }

  Check('a value can be edited', Doc.BJRowCanEdit(1, Why));
  Check('a container cannot', not Doc.BJRowCanEdit(0, Why));
  Check('and says so in a sentence', Pos('container', Why) > 0);
  Check('nor can a line that is not a record at all',
    not Doc.BJRowCanEdit(9999, Why));
  Check('which also says why', Why <> '');
  CheckEq('a value comes back as text to type over',
    '1000', Doc.BJRowValueText(1));
  CheckEq('a string comes back without its quotes',
    'hello', Doc.BJRowValueText(2));

  { ---- a patch: the same size, so nothing moves ---- }

  Moved := Doc.BJDataRows[2].Offset;
  Kind := Doc.EditBJRow(1, '7', Why);
  Check('a number that still fits its marker is patched', Kind = bjePatched);
  CheckEq('and the new value reads back', '7', Doc.BJRowValueText(1));
  Check('the rows below it did not move', Doc.BJDataRows[2].Offset = Moved);
  CheckEqInt('the file is the length it was', Length(Raw), Doc.HexSize);
  Check('and the document is modified', Doc.Modified);
  { The page against the records it is a rendering of.  A patch re-renders
    one line and a splice rebuilds the lot, and this is what says the right
    one of the two happened: after a splice every offset down the left has
    moved, and a page that kept the old ones reads plausibly and lies. }
  CheckEq('the page agrees with the records',
    LedBJRowsText(Doc.BJDataRows), TrimRight(Doc.Master.Lines.Text));

  Check('there is something to undo', Doc.CanUndoBJEdit);
  CheckEqInt('undo says which line it put back', 1, Doc.UndoBJEdit);
  CheckEq('and the old value is back', '1000', Doc.BJRowValueText(1));
  Check('with nothing left to undo the document is clean', not Doc.Modified);

  { ---- a splice: a different size, so everything below moves ---- }

  Moved := Doc.BJDataRows[3].Offset;
  Kind := Doc.EditBJRow(2, 'hello there', Why);
  Check('a longer string is spliced', Kind = bjeSpliced);
  CheckEq('and reads back', 'hello there', Doc.BJRowValueText(2));
  Check('the rows below it moved', Doc.BJDataRows[3].Offset > Moved);
  CheckEq('and the record below it still reads',
    '1.5', Doc.BJRowValueText(3));
  CheckEqInt('the file grew by the difference',
    Length(Raw) + 6, Doc.HexSize);
  CheckEq('and the page agrees with the records it now has',
    LedBJRowsText(Doc.BJDataRows), TrimRight(Doc.Master.Lines.Text));

  { A second edit above the first, so the bytes the first one would put back
    have moved by the time it is taken back.  Undoing both in the order they
    are offered must still give the file that was opened, byte for byte --
    which is the whole of what makes an edit safe to try. }
  Kind := Doc.EditBJRow(1, '5000000000', Why);
  Check('a number too big for its marker widens, so it splices',
    Kind = bjeSpliced);
  CheckEq('the widened number reads back',
    '5000000000', Doc.BJRowValueText(1));
  CheckEq('and the string below it is where it was left',
    'hello there', Doc.BJRowValueText(2));

  CheckEqInt('undo takes back the last edit made', 1, Doc.UndoBJEdit);
  CheckEq('the number is back', '1000', Doc.BJRowValueText(1));
  CheckEqInt('and undo again takes back the one before it',
    2, Doc.UndoBJEdit);
  CheckEq('the string is back', 'hello', Doc.BJRowValueText(2));
  CheckEq('and the page agrees with the records again',
    LedBJRowsText(Doc.BJDataRows), TrimRight(Doc.Master.Lines.Text));
  Check('with nothing left to undo', not Doc.CanUndoBJEdit);
  Check('and the document is clean again', not Doc.Modified);

  Bad := 0;
  for i := 1 to Length(Raw) do
    if Doc.HexByte(i - 1) <> Ord(Raw[i]) then Inc(Bad);
  CheckEqInt('every byte is the one the file came with', 0, Bad);
  CheckEqInt('and the file is not a byte longer', Length(Raw), Doc.HexSize);
  CheckEq('the page is the one it opened with', Opened, Doc.Master.Lines.Text);

  { ---- refusals write nothing ---- }

  Kind := Doc.EditBJRow(1, 'rubbish', Why);
  Check('text where a number is expected is refused', Kind = bjeRefused);
  Check('and says why', Why <> '');
  Check('nothing was written', not Doc.Modified);
  Kind := Doc.EditBJRow(0, '9', Why);
  Check('so is a container', Kind = bjeRefused);
  Kind := Doc.EditBJRow(5, '9', Why);
  Check('and so is an array shown on one line', Kind = bjeRefused);
  Kind := Doc.EditBJRow(1, '1000', Why);
  Check('typing what is already there does nothing', Kind = bjeUnchanged);
  Check('and leaves the document clean', not Doc.Modified);

  { ---- saving writes the bytes, not the page ---- }

  Doc.EditBJRow(3, '2.5', Why);
  Check('an edited structure view is modified', Doc.Modified);
  Doc.SaveToFile(Path);
  Pump;
  Check('saving leaves it unmodified', not Doc.Modified);
  Check('and with nothing to undo', not Doc.CanUndoBJEdit);
  Doc.LoadFromFile(Path);
  Pump;
  CheckEq('and the change is in the file on disk',
    '2.5', Doc.BJRowValueText(3));

  { ---- the three gestures ---- }

  Check('the view has somewhere to send an edit',
    Assigned(Tab.ActiveView.OnBJEdit));

  Tab.ActiveView.CaretXY := Point(Tab.ActiveView.CaretX, 2);
  Pump;
  { Asked for rather than waited for: an action's state is worked out on the
    idle pass, and a check that reads it without one is reading the value it
    was created with. }
  Handled := False;
  F.ActionList1Update(F.actEditValue, Handled);
  Check('the action is offered on a record', F.actEditValue.Enabled);

  { ---- the panel the gestures open ---- }

  F.actEditValue.Execute;
  Pump;
  Check('the action opens the value panel',
    (F.BJValuePopup <> nil) and F.BJValuePopup.Visible);
  CheckEq('with the value in the box',
    Doc.BJRowValueText(1), F.BJValuePopup.ValueBox.Text);
  CheckEq('and the file''s own type selected', 'int32',
    F.BJValuePopup.TypeList.Text);

  { The type list is what this text could be stored as, not a menu of
    everything BJData has: 1000 does not fit a byte and is not a boolean. }
  Check('a type that holds it is offered',
    F.BJValuePopup.TypeList.Items.IndexOf('int16') >= 0);
  Check('one that cannot is not',
    F.BJValuePopup.TypeList.Items.IndexOf('byte') < 0);
  Check('and neither is a type this is not',
    F.BJValuePopup.TypeList.Items.IndexOf('boolean') < 0);

  { Typing rebuilds it.  0.1 is not a float32, and nothing whole holds it. }
  F.BJValuePopup.ValueBox.Text := '0.1';
  Pump;
  Check('typing rebuilds the list',
    F.BJValuePopup.TypeList.Items.IndexOf('float64') >= 0);
  Check('and drops what has stopped fitting',
    F.BJValuePopup.TypeList.Items.IndexOf('int32') < 0);

  { And picks it back up when the text allows it again.  The panel chose
    float64 a moment ago because nothing else could hold 0.1; that is the
    panel's choice, not the reader's, so it does not outlive the text that
    caused it. }
  F.BJValuePopup.ValueBox.Text := '77';
  Pump;
  CheckEq('a type the panel chose follows the text back', 'int32',
    F.BJValuePopup.TypeList.Text);
  F.BJValuePopup.OkButton.Click;
  Pump;
  Check('accepting closes the panel', not F.BJValuePopup.Visible);
  CheckEq('and edits the record the caret is on',
    '77', Doc.BJRowValueText(1));
  CheckEq('keeping the type the file had', 'l',
    Doc.BJDataRows[1].Value.Marker);

  { Choosing a type writes that type, which is the whole reason the list is
    there: the same number, stored as something else. }
  Key := VK_RETURN;
  TLedKeyPoke.Press(Tab.ActiveView, Key, []);
  Pump;
  CheckEqInt('Return over a record is taken by the view', 0, Key);
  Check('and opens the panel too', F.BJValuePopup.Visible);
  Check('a float64 is on offer for a whole number',
    F.BJValuePopup.SelectType('D'));
  F.BJValuePopup.OkButton.Click;
  Pump;
  CheckEq('the value is the one that was there', '77',
    Doc.BJRowValueText(1));
  CheckEq('stored as the type that was chosen', 'D',
    Doc.BJDataRows[1].Value.Marker);

  { Escape leaves the file alone. }
  TLedKeyPoke.Double(Tab.ActiveView);
  Pump;
  Check('a double click opens it as well', F.BJValuePopup.Visible);
  F.BJValuePopup.ValueBox.Text := '999';
  Pump;
  Key := VK_ESCAPE;
  TLedPanelPoke.Press(F.BJValuePopup, Key, []);
  Pump;
  Check('Escape closes the panel', not F.BJValuePopup.Visible);
  CheckEq('and changes nothing', '77', Doc.BJRowValueText(1));

  { Cancel is the same answer by another route. }
  F.actEditValue.Execute;
  Pump;
  F.BJValuePopup.ValueBox.Text := '123';
  Pump;
  F.BJValuePopup.CancelButton.Click;
  Pump;
  CheckEq('and so does Cancel', '77', Doc.BJRowValueText(1));

  { A word typed into a number field.  There is one type that can hold it --
    a string -- and it is offered, but nothing is selected: turning a number
    into text is a real thing to want and not a thing to fall into by
    pressing Return over a typo. }
  F.actEditValue.Execute;
  Pump;
  F.BJValuePopup.ValueBox.Text := 'orange';
  Pump;
  CheckEqInt('a word can only be a string', 1,
    F.BJValuePopup.TypeList.Items.Count);
  CheckEqInt('and no type is picked for it', -1,
    F.BJValuePopup.TypeList.ItemIndex);
  Check('so it cannot be accepted', not F.BJValuePopup.OkButton.Enabled);

  { Asked for by name, it goes through. }
  Check('a string is on offer', F.BJValuePopup.SelectType('S'));
  Pump;
  Check('and then it can be accepted', F.BJValuePopup.OkButton.Enabled);
  F.BJValuePopup.OkButton.Click;
  Pump;
  CheckEq('the number is text now', 'orange', Doc.BJRowValueText(1));
  CheckEq('stored as a string', 'S', Doc.BJDataRows[1].Value.Marker);
  CheckEqInt('and undo puts the number back', 1, Doc.UndoBJEdit);
  CheckEq('as the number it was', '77', Doc.BJRowValueText(1));

  { Put the number back, so the rows below read as they did. }
  Doc.EditBJRow(1, '1000', Why, 'l');
  Pump;

  { A panel is about one record of one document.  When the window moves to
    another tab it is about nothing, and a small window left floating over a
    file it no longer describes is worse than one that closes. }
  F.actEditValue.Execute;
  Pump;
  Check('the panel is up', F.BJValuePopup.Visible);
  F.AddTab(F.Documents.NewDocument);
  Pump;
  Handled := False;
  F.ActionList1Update(F.actEditValue, Handled);
  Check('and closes when the window moves to another document',
    not F.BJValuePopup.Visible);
  F.CloseActiveTab(False);
  Pump;
  CheckEq('with the record it was about untouched',
    '1000', Doc.BJRowValueText(1));

  { The same two gestures over a container the walk held back open it
    instead, which is the reason the view decides which of the two a line
    wants rather than the window. }
  Bad := Doc.Master.Lines.Count;
  Tab.ActiveView.CaretXY := Point(Tab.ActiveView.CaretX, 7);
  Pump;
  Check('a held-back container is on that line', Doc.BJDataRows[6].CanExpand);
  Handled := False;
  F.ActionList1Update(F.actEditValue, Handled);
  Check('and the action is not offered for it', not F.actEditValue.Enabled);
  Key := VK_RETURN;
  TLedKeyPoke.Press(Tab.ActiveView, Key, []);
  Pump;
  CheckEqInt('Return there is taken too', 0, Key);
  CheckGt('and opens the container rather than editing it',
    Bad, Doc.Master.Lines.Count);
  Check('with no panel in the way', not F.BJValuePopup.Visible);

  DeleteFile(Path);
end;

procedure TestBJDataFolding(F: TLedMainForm);
var
  Path, Raw: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  HL: TLedBJHighlighter;
  i, Before, After: Integer;
  BigLine: Integer;
begin
  Say('Binary JData folding and opening');

  { { "big": [ 101 two-key objects ], "tail": U 7 } -- containers, so the
    flat-array path does not take it and the element cap applies. }
  Raw := #$7B + #$55#$03'big' + #$5B;
  for i := 1 to LedBJMaxElements + 1 do
    Raw := Raw + #$7B + #$55#$01'a' + #$55#$01 + #$7D;
  Raw := Raw + #$5D + #$55#$04'tail' + #$55#$07 + #$7D;

  Path := TempName('fold.bjd');
  WriteBytes(Path, Raw);

  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  Doc.LoadFromFile(Path);
  Pump;

  Check('it opens as a structure', Doc.IsBJData);
  Before := Doc.Master.Lines.Count;
  CheckEqInt('shut, it is three rows', 3, Before);

  { ---- folding ---- }

  { The highlighter is what SynEdit asks for fold levels, and the guides down
    the body read the same numbers.  Both come from the row depths, so this
    is the one place to check that they are there at all. }
  Check('the view has a fold highlighter',
    Tab.ActiveView.Highlighter is TLedBJHighlighter);
  HL := TLedBJHighlighter(Tab.ActiveView.Highlighter);

  { Line 0 is the root object and line 1 is big; both are containers, so the
    root opens a block that line 1 is inside. }
  CheckEqInt('the root is at depth 0', 0, HL.DepthOf(0));
  CheckEqInt('and its children one deeper', 1, HL.DepthOf(1));
  CheckEqInt('a block is open after the root line', 1,
    HL.FoldBlockEndLevel(0));
  CheckEqInt('and still open over its children', 1,
    HL.FoldBlockEndLevel(1));
  CheckEqInt('and closed after the last of them', 0,
    HL.FoldBlockEndLevel(2));

  { ---- opening a container the walk held back ---- }

  BigLine := 1;
  Check('big is held back', Doc.BJDataRows[BigLine].CanExpand);
  CheckEqInt('and says how many are behind it',
    LedBJMaxElements + 1, Doc.BJDataRows[BigLine].ChildCount);
  { That flag is what puts a chevron on a line with nothing folded under it.
    The gutter asks the view, which asks the highlighter. }
  Check('so the gutter is offered a chevron there', HL.CanExpand(BigLine));
  Check('but not on a row that has nothing behind it', not HL.CanExpand(0));

  Check('opening it succeeds', Doc.BJOpenRow(BigLine));
  Pump;
  After := Doc.Master.Lines.Count;
  CheckEqInt('every child is on the page now',
    3 + (LedBJMaxElements + 1) * 2, After);
  Check('and the row no longer offers to open',
    not Doc.BJDataRows[BigLine].CanExpand);
  Check('nor says it is holding anything back',
    Pos('not shown', Doc.Master.Lines[BigLine]) = 0);

  { The rows below big all moved, so tail is no longer line 2.  Its offset is
    what did not change, which is why the expansion set names offsets. }
  Check('the file is unchanged by looking at it', not Doc.Modified);
  Check('and it is still a structure view', Doc.IsBJData);

  { Opening the same row twice is not an error and does not double it. }
  Check('opening it again does nothing', not Doc.BJOpenRow(BigLine));
  CheckEqInt('and the page is the same length', After,
    Doc.Master.Lines.Count);

  DeleteFile(Path);
end;

{ The guides down the body, which come from the same fold levels as the
  chevrons.  Checked as strokes rather than as pixels: they are computed in
  one place and drawn in another, and the bug that made this test necessary
  was entirely in the first. }
procedure TestBJDataGuides(F: TLedMainForm);
var
  Path, Raw: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  Strokes: TLedGuideStrokes;
  i, j, k, Deepest, Reaching, Rows_: Integer;
begin
  Say('Binary JData guides');

  { { a:{ b:1 c:2 } d:{ e:3 ... } } with enough under d to run off the foot
    of the view, which is the case that used to draw nothing. }
  Raw := #$7B +
           #$55#$01'a' + #$7B +
             #$55#$01'b' + #$55#$01 +
             #$55#$01'c' + #$55#$02 +
           #$7D +
           #$55#$01'd' + #$7B;
  for i := 1 to 80 do
    Raw := Raw + #$55#$02 + Chr(Ord('a') + (i mod 26)) +
           Chr(Ord('a') + (i div 26)) + #$55 + Chr(i);
  Raw := Raw + #$7D + #$7D;

  Path := TempName('guides.bjd');
  WriteBytes(Path, Raw);
  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  Doc.LoadFromFile(Path);
  Pump;
  Rows_ := Doc.Master.Lines.Count;
  Check('it opens as a structure', Doc.IsBJData);
  Check('and is taller than the window',
    Rows_ > Tab.ActiveView.LinesInWindow);

  Strokes := Tab.ActiveView.ComputeGuideStrokes;
  Check('there are guides at all, got ' + IntToStr(Length(Strokes)),
    Length(Strokes) > 0);

  { The root's guide starts at the top of the view and is still open at the
    bottom of it.  That is the one that used to vanish: the run builder was
    asked for one row past the last visible, took its out-of-window branch,
    and dropped every run still open instead of ending it.  What was left on
    screen were only the guides that had closed higher up the page. }
  Reaching := 0;
  Deepest := 0;
  for i := 0 to High(Strokes) do
  begin
    { Past LinesInWindow, not merely up to it.  That count is the rows which
      fit whole, and the view almost always shows a sliver of one more below
      them; a rule that stops at the boundary leaves the bottom line of the
      view unruled. }
    if Strokes[i].BottomRow > Tab.ActiveView.LinesInWindow then
      Inc(Reaching);
    if Strokes[i].Col > Deepest then Deepest := Strokes[i].Col;
  end;
  Check('a guide runs past the last whole row, got ' + IntToStr(Reaching),
    Reaching > 0);

  { Column 11 is where a depth-0 record starts: eight of offset, two spaces,
    then the record.  The root's guide belongs under its own brace, not
    under the file positions to its left. }
  Reaching := 0;
  for i := 0 to High(Strokes) do
    if Strokes[i].Col = LedBJOffsetWidth + 3 then Inc(Reaching);
  Check('the outermost guide is at the root record column', Reaching > 0);
  Check('and a nested one is further in', Deepest > LedBJOffsetWidth + 3);

  { Every stroke is a real span; a zero-height one would be a rule that is
    not there. }
  for i := 0 to High(Strokes) do
    Check('stroke ' + IntToStr(i) + ' spans rows',
      Strokes[i].BottomRow > Strokes[i].TopRow);

  DeleteFile(Path);

  { ---- the last row of the file ---- }

  { { a:{ b:1 c:2 } d:{ e:3 f:4 } } -- seven rows, all on screen, and the
    last of them is two deep.  SynEdit keeps a line's fold levels as the
    state the next line starts from, so the last line -- having no next line
    -- reported that every block had closed on it, and the rules stopped one
    row short of the bottom of the file. }
  Raw := #$7B +
           #$55#$01'a' + #$7B +
             #$55#$01'b' + #$55#$01 +
             #$55#$01'c' + #$55#$02 +
           #$7D +
           #$55#$01'd' + #$7B +
             #$55#$01'e' + #$55#$03 +
             #$55#$01'f' + #$55#$04 +
           #$7D +
         #$7D;
  Path := TempName('lastrow.bjd');
  WriteBytes(Path, Raw);
  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  Doc.LoadFromFile(Path);
  Pump;
  Rows_ := Doc.Master.Lines.Count;
  CheckEqInt('seven rows', 7, Rows_);
  Check('and they all fit on screen', Rows_ <= Tab.ActiveView.LinesInWindow);

  Strokes := Tab.ActiveView.ComputeGuideStrokes;
  Reaching := 0;
  for i := 0 to High(Strokes) do
    if (Strokes[i].TopRow <= Rows_ - 1) and
       (Strokes[i].BottomRow > Rows_ - 1) then Inc(Reaching);
  { Two of them: the root's rule and the rule of the container the last row
    sits in. }
  Check('the last row is covered by its guides, got ' + IntToStr(Reaching),
    Reaching >= 2);

  DeleteFile(Path);

  { ---- far from the top of the file ---- }

  { Ten containers of ten containers of ten values: 1,111 rows, four deep,
    and every level within the element cap so nothing is held back.

    Scrolled to the end, the containers enclosing the last screenful opened
    hundreds or thousands of rows above it.  The guide scan used to begin a
    fixed run-up above the screen with an empty stack, so a block that opened
    before that point had no column recorded and drew no rule at all -- which
    is why the end of a deeply nested file showed none. }
  Raw := #$7B;
  for i := 0 to 9 do
  begin
    Raw := Raw + #$55#$02'k' + Chr(Ord('0') + i) + #$7B;
    for j := 0 to 9 do
    begin
      Raw := Raw + #$55#$02'j' + Chr(Ord('0') + j) + #$7B;
      for k := 0 to 9 do
        Raw := Raw + #$55#$02'm' + Chr(Ord('0') + k) + #$55 + Chr(k);
      Raw := Raw + #$7D;
    end;
    Raw := Raw + #$7D;
  end;
  Raw := Raw + #$7D;

  Path := TempName('deep.bjd');
  WriteBytes(Path, Raw);
  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  Doc.LoadFromFile(Path);
  Pump;
  Rows_ := Doc.Master.Lines.Count;
  CheckEqInt('eleven hundred and eleven rows', 1111, Rows_);

  Tab.ActiveView.TopLine := Rows_;
  Pump;
  Check('the view really is at the end',
    Tab.ActiveView.TopLine > Rows_ - Tab.ActiveView.LinesInWindow - 2);

  { The last rows sit three deep, so the columns are the root's, its k
    container's and its j container's -- and all three must be there.

    Counting strokes is not enough, and neither is looking only for the
    outermost column: with the stack starting empty, the first container to
    open within the run-up was pushed at the root's own column.  A rule still
    appeared at column 11; it just belonged to the wrong block.  So the test
    asks for the whole set. }
  Strokes := Tab.ActiveView.ComputeGuideStrokes;
  Deepest := 0;
  for j := 0 to 2 do
  begin
    Reaching := 0;
    for i := 0 to High(Strokes) do
      if Strokes[i].Col = LedBJOffsetWidth + 3 + j * LedBJIndentWidth then
        Inc(Reaching);
    Check('a guide at level ' + IntToStr(j) + ', got ' +
      IntToStr(Length(Strokes)) + ' strokes in all', Reaching > 0);
    if Reaching > 0 then Inc(Deepest);
  end;
  CheckEqInt('all three levels are ruled', 3, Deepest);

  DeleteFile(Path);
end;

{ Finding text in a structure view.

  The buffer is UTF-8 like any other, so Find has nothing special to do --
  but the view is read-only, is driven by a highlighter that does not read
  the text, and its rows are rebuilt underneath it when a container is
  opened, so "nothing special" is worth checking rather than assuming. }
procedure TestBJDataSearch(F: TLedMainForm);
const
  Maeda  = #$E5#$89#$8D#$E7#$94#$B0#$E3#$81#$82#$E3#$82#$86#$E3#$81#$BF;
  Prefix = #$E5#$89#$8D#$E7#$94#$B0#$E3#$81#$82#$E3#$82#$86;
var
  Path, Raw: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  State: TLedSearchState;
  i: Integer;
begin
  Say('searching a Binary JData view');

  { { pad: "...", name: "前田あゆみ" } -- the padding puts the name off the
    first row, so a search that found nothing and a search that never moved
    cannot be confused. }
  Raw := #$7B + #$55#$03'pad' + #$53#$55#$05'aaaaa';
  for i := 1 to 30 do
    Raw := Raw + #$55#$02 + 'k' + Chr(Ord('a') + i) + #$55 + Chr(i);
  Raw := Raw + #$55#$04'name' + #$53#$55#$0F + Maeda + #$7D;

  Path := TempName('jp.bjd');
  WriteBytes(Path, Raw);
  F.AddTab(F.Documents.NewDocument);
  Pump;
  Tab := F.ActiveTab;
  Doc := Tab.Document;
  Doc.LoadFromFile(Path);
  Pump;

  Check('it opens as a structure', Doc.IsBJData);
  Check('and the buffer carries the Japanese',
    Pos(Maeda, Doc.Master.Lines.Text) > 0);

  State := TLedSearchState.Create;
  try
    State.SearchText := Prefix;
    Tab.ActiveView.CaretXY := Point(1, 1);
    Check('Find reaches it',
      LedFindNext(Tab.ActiveView, State, False) in [lfoFound, lfoWrapped]);
    Check('and selects it, got: ' + Tab.ActiveView.SelText,
      Tab.ActiveView.SelText = Prefix);
    Check('on the row it is on',
      Pos(Maeda, Tab.ActiveView.Lines[Tab.ActiveView.CaretY - 1]) > 0);
  finally
    State.Free;
  end;

  DeleteFile(Path);
end;

procedure TestStartupDocument(F: TLedMainForm);
var
  Tab: TLedTab;
  Doc: TLedDocument;
  FontFace: string;
  FontPts, i: Integer;
  Found: Boolean;
begin
  Say('the document LED starts with');

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
  { The fold column is LED's own painter, drawing medit's chevrons rather than
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

  { Vertical guides down an open block, drawn by LED itself in Paint. }
  Check('the block guides have a colour',
    Tab.ActiveView.GuideColour <> clNone);
  Check('and is wide enough to draw a marker',
    Tab.ActiveView.Gutter.CodeFoldPart.Width >= 10);

  { Editor/font was a preference that nothing read.  A view whose font is the
    old hard-coded 10 regardless of the preference is the symptom. }
  LedParseFontSpec(LedPrefs.GetStr(LedPrefFont, ''), FontFace, FontPts);
  CheckEqInt('the editor draws the font preference, at the display''s scale',
    LedScalePointSize(FontPts), Tab.ActiveView.Font.Size);

  { That scaling is the whole of high-DPI support for the editor's text.  On
    gtk2 a font is rendered from its point size at the Xft DPI, and the height
    it carries is ignored on purpose -- so a preference of 10 points drew 21
    pixels tall inside a window scaled to 300 PPI, and neither Font.Height nor
    Font.PixelsPerInch would move it.  Points are the only lever; this asserts
    the lever is connected and pulls the right way. }
  Check('and never smaller than the preference asked for',
    LedScalePointSize(FontPts) >= FontPts);

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
{ What share of a speed button, as a percentage, changes when the pointer
  moves onto it.

  A speed button is a TGraphicControl -- no handle -- so it is painted onto
  whatever it is parented to, and the only way to see what it drew is to
  paint the parent and look at the button's rectangle.  Hovering is done with
  CM_MOUSEENTER rather than by moving a pointer: that is the message the
  widgetset sends, and it is what sets the flag the button paints from. }
function HoverPixels(Btn: TSpeedButton): Integer;
var
  Host: TWinControl;
  R: TRect;
  x, y: Integer;

  function Shot: TLazIntfImage;
  var
    Bmp: TBitmap;
  begin
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(Host.Width, Host.Height);
      Host.PaintTo(Bmp.Canvas, 0, 0);
      Result := Bmp.CreateIntfImage;
    finally
      Bmp.Free;
    end;
  end;

var
  Cold, Hot: TLazIntfImage;
  Area, Changed: Integer;
begin
  Result := -1;
  if (Btn = nil) or (Btn.Parent = nil) then Exit;
  Host := Btn.Parent;
  if (Host.Width <= 0) or (Host.Height <= 0) then Exit;
  R := Btn.BoundsRect;

  Btn.Perform(CM_MOUSELEAVE, 0, 0);
  Pump;
  Cold := Shot;
  try
    Btn.Perform(CM_MOUSEENTER, 0, 0);
    Pump;
    Hot := Shot;
    try
      { A share, not a count.  Counting pixels alone does not tell the two
        apart: gtk2 does draw something for a hot speed button -- a frame
        around the edge, 45% of the button -- and a check that only asked
        whether anything changed passed with LED's painting taken away.
        What a wash does and a frame does not is cover the whole button. }
      Changed := 0;
      Area := 0;
      for y := Max(0, R.Top) to Min(Hot.Height, R.Bottom) - 1 do
        for x := Max(0, R.Left) to Min(Hot.Width, R.Right) - 1 do
        begin
          Inc(Area);
          if Cold.Colors[x, y] <> Hot.Colors[x, y] then Inc(Changed);
        end;
      if Area > 0 then Result := (Changed * 100) div Area;
    finally
      Hot.Free;
    end;
  finally
    Cold.Free;
    Btn.Perform(CM_MOUSELEAVE, 0, 0);
    Pump;
  end;
end;

{ Every row of buttons in LED answers the pointer, not just the ones that
  happen to be TToolBars.

  The main toolbar got a painter of its own because gtk2 asks for
  ttbButtonHot and draws nothing for it.  The file browser's nav row, its
  crumbs and the dock's edge rails are speed buttons, which OnPaintButton
  does not reach, so they kept drawing nothing and looked dead next to the
  bar above them.

  Counted in pixels rather than asked of a property: a painter can be
  assigned and still put down no ink, which is how the toolbar check that
  only asserted OnPaintButton was satisfied by a bar that shaded nothing. }
procedure TestSpeedButtonHover(F: TLedMainForm);
var
  N: Integer;
begin
  Say('hover on the hand-built toolbars');

  F.Dock.ShowPane('files');
  Pump; Pump;

  if (F.Browser <> nil) and (F.Browser.NavButtonCount > 0) then
  begin
    N := HoverPixels(F.Browser.NavButton(0));
    CheckGt('the browser nav buttons shade under the pointer', 90, N);
  end;

  F.Dock.ShowRails := True;
  Pump; Pump;
  N := HoverPixels(F.Dock.RailButton(ledLeft, 0));
  CheckGt('and so do the edge rail buttons', 90, N);

  F.Dock.HidePane('files');
  Pump;
end;

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
  { And opens at a size you can see something in.  EdgeDefault is written at
    96 dpi like every other literal in the dock, but it is weighed against a
    budget taken from live geometry -- so unscaled it asked for 180 pixels of
    a 300-PPI display, which is 58 at the design scale and less than the
    pane's own header.  The edge became visible and appeared to hold nothing,
    which is what "the bottom pane does not show when clicked" was. }
  Check('and opens tall enough to hold something',
    F.Dock.EdgeSize[ledBottom] >= LedScale96(120));
  Say(Format('    bottom edge opened at %d px, floor %d',
    [F.Dock.EdgeSize[ledBottom], LedScale96(120)]));

  { The side edges are the same literal read the same way. }
  F.Dock.EdgeVisible[ledLeft] := False;
  Pump;
  F.Dock.ShowPane('files');
  Pump;
  Check('a side edge opens wide enough too',
    F.Dock.EdgeSize[ledLeft] >= LedScale96(140));
  Say(Format('    left edge opened at %d px', [F.Dock.EdgeSize[ledLeft]]));
  { Put it back: TestFileBrowser toggles this edge and expects the toggle to
    open it, which it will not do from here if this probe left it open. }
  F.Dock.HidePane('files');
  F.Dock.EdgeVisible[ledLeft] := False;
  Pump;
  F.Dock.HidePane('output');
  Pump;

  { The header style is offered rather than decided, so the list has to be
    real and the choice has to stick.

    Deliberately not an exact count.  The built-in styles belong to
    AnchorDocking, not to LED, and there are six of them on Lazarus 2.2 but
    seven on 4.2, which added GradientMenuBar -- so asserting a total pins
    the suite to whichever Lazarus happened to be installed when it was
    written, and it duly failed on the second machine it ran on.  What LED
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

{ Long lines are truncated for display only.

  The whole feature turns on one claim: what the caret and the painter see is
  short, and what reaches the disk is not.  So this asserts the bytes, not
  the setting.  A version of this that only checked IsTruncated passed while
  Lines.Text was returning the truncated string, which would have saved a
  5 MB line as 4 KB. }
procedure TestLongLines(F: TLedMainForm);
const
  Long = 12000;
var
  Tab: TLedTab;
  V: TLedEdit;
  P, Q: string;
  L: TStringList;
  Full: string;
  RealLine, StartByte, ByteLen: Integer;
begin
  Say('long lines');

  Full := StringOfChar('x', Long);
  P := TempName('longline-in.txt');
  Q := TempName('longline-out.txt');
  L := TStringList.Create;
  try
    L.Add('short first line');
    L.Add(Full);
    L.Add('short last line');
    L.SaveToFile(P);
  finally
    L.Free;
  end;

  Tab := F.AddTab(F.Documents.OpenFile(P));
  Pump;
  if Tab = nil then Exit;
  V := Tab.ActiveView;

  { Not "the limit is 4096": that is also TLedLongLineView's constructor
    default, so asserting it cannot tell a preference that was applied from
    one that was never read.  Set it to something no default would produce
    and reopen. }
  CheckEqInt('the limit is medit''s 4096 by default', 4096, V.LongLines.Limit);

  LedPrefs.SetInt('Editor/max_line_len', 700);
  Tab.Document.ApplyConfigToViews;
  Pump;
  CheckEqInt('and a preference changes it', 700, V.LongLines.Limit);
  CheckEqInt('so the line truncates where the preference says',
    700, V.LongLines.VisibleLength(1));
  LedPrefs.SetInt('Editor/max_line_len', 4096);
  Tab.Document.ApplyConfigToViews;
  Pump;
  CheckEqInt('and back again', 4096, V.LongLines.Limit);
  Check('the long line is truncated', V.LongLines.IsTruncated(1));
  Check('the short ones are not',
    (not V.LongLines.IsTruncated(0)) and (not V.LongLines.IsTruncated(2)));
  CheckEqInt('what the caret can see is the limit',
    4096, V.LongLines.VisibleLength(1));
  CheckEqInt('the buffer below still holds all of it',
    Long, V.LongLines.FullLength(1));
  CheckEqInt('and the marker sits one past the visible end',
    4097, V.LongLineMarkerCol(1));

  { What the painter is actually handed.  Asking the view was not enough:
    every check above passed while the editor drew the whole line, because
    SynEdit fetches the row for painting straight from the buffer and never
    consults the view chain. }
  RealLine := 0; StartByte := 0; ByteLen := 0;
  V.LongLines.Display.SetHighlighterTokensLine(1, RealLine, StartByte, ByteLen);
  CheckEqInt('the painter is given only the visible bytes', 4096, ByteLen);

  { The property LED saves through.  This is the check that matters. }
  CheckEqInt('the text LED saves is the untruncated line',
    Long, Length(V.Lines[1]));

  { And end to end, because a length can be right while the bytes are not. }
  Tab.Document.SaveToFile(Q);
  Pump;
  L := TStringList.Create;
  try
    L.LoadFromFile(Q);
    CheckEqInt('a save round-trip keeps every line', 3, L.Count);
    CheckEqInt('and the long line comes back whole', Long, Length(L[1]));
    CheckEq('byte for byte', Full, L[1]);
  finally
    L.Free;
  end;

  { Edit the truncated line and undo it.  SynEdit builds an undo record from
    the line it is about to change, and if it read that through this view the
    record would hold 4 KB and undo would write 4 KB back over 12 KB -- a
    silent truncation with no save involved.  --bench-longline reported
    exactly that shape, printing a first-line length of 4096 after its
    type-then-undo step, which is what sent this check looking. }
  V.CaretXY := Point(1, 2);
  V.InsertTextAtCaret('typed ');
  Pump;
  CheckEqInt('typing on a truncated line leaves the tail alone',
    Long + 6, Length(V.Lines[1]));
  V.Undo;
  Pump;
  CheckEqInt('and undoing it restores the whole line, not the visible part',
    Long, Length(V.Lines[1]));
  CheckEq('byte for byte after undo', Full, V.Lines[1]);

  { Revealing shows one more limit's worth, and only for that line. }
  Check('revealing more reports it did something', V.LongLines.RevealMore(1));
  CheckEqInt('now two limits are visible', 8192, V.LongLines.VisibleLength(1));
  Check('revealing all clears the truncation', V.LongLines.RevealAll(1));
  Check('so nothing is hidden any more', not V.LongLines.IsTruncated(1));
  CheckEqInt('and no marker is offered', 0, V.LongLineMarkerCol(1));

  { A limit of 0 is how a user turns the feature off entirely. }
  V.LongLines.Limit := 0;
  Check('a zero limit truncates nothing', not V.LongLines.IsTruncated(1));
  V.LongLines.Limit := 4096;
  Check('and restoring it truncates again', V.LongLines.IsTruncated(1));

  Tab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  DeleteFile(P);
  DeleteFile(Q);
end;

{ Wiki markup: the language is detected and the preview renders it.

  Led.Core.Tests.Wiki covers the converter itself, headlessly and in detail.
  What that cannot see is the wiring: whether opening a .wiki file picks the
  grammar up, and whether the preview pane chooses the wiki renderer over the
  Markdown one. }
{ The line mapping between the text and the preview.

  The page carries the source line of every block as id="L<n>", and the pane
  turns that into two things: scrolling the page to a line, and reporting the
  line under a click.  Only the first can be driven from here -- a click needs
  a mouse over a laid-out page -- but the mapping itself is the same one, and
  the headless tests cover the ids in the markup. }
{ Clicking the page moves the caret, and leaves the page where it was.

  The two directions of the sync fought each other.  A click reports the
  source line it was made from, the caret goes there, the text view scrolls
  to show the caret -- and that scroll is reported back as a request to put
  the preview at whatever line is now the top one.  That is a different line
  from the clicked one, and usually a different block, so the paragraph the
  reader had just clicked jumped away from under the pointer.

  The click is delivered through OnJumpToLine rather than by clicking the
  widget: the pane reads the block under the pointer from the HTML control's
  own hit-testing, which needs a real pointer over a laid-out page.
  Everything downstream of that -- which is all of what broke -- is the same
  code either way. }
procedure TestPreviewClickKeepsPage(F: TLedMainForm);
var
  Tab: TLedTab;
  P: string;
  L: TStringList;
  i, Before, After, Target: Integer;
  V: TLedEdit;
begin
  Say('preview click');
  if F.Preview = nil then Exit;

  P := TempName('clicked.md');
  L := TStringList.Create;
  try
    { Long enough that the page scrolls and that the caret landing in the
      middle puts a different block at the top of the text view. }
    for i := 1 to 40 do
    begin
      L.Add('## Section ' + IntToStr(i));
      L.Add('');
      L.Add('Paragraph ' + IntToStr(i) + ' of the document.');
      L.Add('');
    end;
    L.SaveToFile(P);
  finally
    L.Free;
  end;

  Tab := F.AddTab(F.Documents.OpenFile(P));
  Pump;
  if Tab = nil then Exit;
  F.actTogglePreviewExecute(nil);
  Pump;
  Check('the preview rendered the long document', F.Preview.RenderNow);

  { The reader has scrolled down the page and is looking at a block in the
    middle of it. }
  Target := 4 * 20 + 1;          { the heading of section 21 }
  F.Preview.ScrollToLine(Target);
  Pump;
  Before := F.Preview.ScrollPos;
  CheckGt('the page is scrolled down before the click', 0, Before);

  { A click on the paragraph under that heading. }
  if Assigned(F.Preview.OnJumpToLine) then
    F.Preview.OnJumpToLine(F.Preview, Target + 2);
  Pump; Pump;

  V := F.ActiveView;
  if V <> nil then
    CheckEqInt('the click put the caret on the line it was made from',
      Target + 2, V.CaretY);

  After := F.Preview.ScrollPos;
  CheckEqInt('and left the page where the reader had it', Before, After);

  { The same request arriving late.  The flag only covers the scroll SynEdit
    reports from inside the move; a widgetset that scrolls again afterwards --
    on the focus change, or on the next repaint -- delivers exactly this, and
    it has to be just as harmless.  Asked for by hand because headless the
    late one does not come. }
  if V <> nil then
  begin
    F.Preview.ScrollToLine(V.TopLine);
    Pump;
    CheckEqInt('and a sync arriving after the jump moves nothing either',
      Before, F.Preview.ScrollPos);
  end;

  F.Dock.EdgeVisible[ledRight] := False;
  Pump;
  Tab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  DeleteFile(P);
end;

procedure TestPreviewLineMapping(F: TLedMainForm);
var
  Tab: TLedTab;
  P: string;
  L: TStringList;
begin
  Say('preview line mapping');
  if F.Preview = nil then Exit;

  P := TempName('mapped.md');
  L := TStringList.Create;
  try
    L.Add('# Title');          { line 1 }
    L.Add('');
    L.Add('First paragraph.'); { line 3 }
    L.Add('');
    L.Add('## Second');        { line 5 }
    L.Add('');
    L.Add('Another paragraph');{ line 7 }
    L.SaveToFile(P);
  finally
    L.Free;
  end;

  Tab := F.AddTab(F.Documents.OpenFile(P));
  Pump;
  if Tab = nil then Exit;

  F.actTogglePreviewExecute(nil);
  Pump;
  Check('the preview rendered the document', F.Preview.RenderNow);

  Check('a line with a block of its own is found',
    F.Preview.ScrollToLine(5));
  Check('and so is a line inside one -- it maps to the block it is in',
    F.Preview.ScrollToLine(6));
  Check('the first block covers everything above it',
    F.Preview.ScrollToLine(1));

  { A document with nothing in it has no block to point at, and the pane has
    to say so rather than scroll somewhere arbitrary. }
  F.Preview.Update('', 'empty', '');
  Pump;
  F.Preview.RenderNow;
  Check('an empty document maps nowhere', not F.Preview.ScrollToLine(1));

  { Put it back the way the wiki section leaves it, or the docking checks
    further down see an edge nobody opened. }
  F.Dock.EdgeVisible[ledRight] := False;
  Pump;

  Tab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  DeleteFile(P);
end;

procedure TestWikiMarkup(F: TLedMainForm);
var
  Tab: TLedTab;
  P: string;
  L: TStringList;
begin
  Say('wiki markup');

  P := TempName('notes.wiki');
  L := TStringList.Create;
  try
    L.Add('= Heading =');
    L.Add('');
    L.Add('Some ''''''bold'''''' text and a [[FreeLink]].');
    L.SaveToFile(P);
  finally
    L.Free;
  end;

  Tab := F.AddTab(F.Documents.OpenFile(P));
  Pump;
  if Tab = nil then Exit;

  { Upstream mediawiki.lang carries no globs, so without LED's patch this
    opens as plain text and nothing below would be true. }
  Check('a .wiki file gets a language', Tab.Document.LangInfo <> nil);
  if Tab.Document.LangInfo <> nil then
    CheckEq('and it is the wiki one', 'mediawiki', Tab.Document.LangInfo.Id);
  Check('with a highlighter to match', Tab.ActiveView.Highlighter <> nil);

  Check('the preview offers to render it', LedPreviewHandles(P, ''));
  Check('and knows it is wiki rather than markdown', LedIsWikiFile(P, ''));
  Check('a .md file is still markdown',
    LedPreviewHandles('x.md', '') and (not LedIsWikiFile('x.md', '')));
  Check('and a plain .txt saying so is wiki too',
    LedIsWikiFile('x.txt', '<!-- wiki -->'));

  { And it has to survive the HTML control.  The converter's output is
    checked in detail headlessly, but IpHtmlPanel is the thing that has to
    accept <dl> nesting, id= attributes and <a name>, and when it throws the
    pane catches it and shows a label -- which looks like success from
    anywhere except here. }
  F.actTogglePreviewExecute(nil);
  Pump;
  if F.Preview <> nil then
  begin
    F.Preview.IsWiki := True;
    F.Preview.Update(Tab.Document.Master.Lines.Text, 'notes', '');
    Check('the html control renders the wiki output', F.Preview.RenderNow);
    F.Preview.IsWiki := False;
    F.Preview.Update('# markdown heading', 'md', '');
    Check('and still renders markdown', F.Preview.RenderNow);

    { A relative image the file does not have used to be able to raise past
      IPro's own narrow except clause; the preview's own OnGetImage handler
      is what turns "file not found" into "no image" instead. }
    F.Preview.Update('# with an image' + LineEnding +
      '![missing](does-not-exist.png)', 'md', ExtractFileDir(P));
    Check('a markdown image that cannot load does not crash the preview',
      F.Preview.RenderNow);
  end;

  { Put the pane back.  Leaving the right edge open changed what the dock
    reported to the next section, which failed on "the editor area cannot be
    closed" -- a check about docking, broken by a test about wiki files. }
  F.Dock.EdgeVisible[ledRight] := False;
  Pump;
  Check('showing and hiding a pane leaves the editor area unclosable',
    not F.Dock.CentreCanBeClosed);

  Tab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  DeleteFile(P);
end;

{ Column copy and paste in a file that has a highlighter and a truncated
  line.  Reported as an access violation, and the plain-document checks above
  do not reach it: the long-line display view only clamps tokens when a
  highlighter is asking for them, and it looks the line up in the buffer
  below by index. }
procedure TestColumnPasteWithHighlighter(F: TLedMainForm);
var
  Tab: TLedTab;
  V: TLedEdit;
  P: string;
  L: TStringList;
begin
  Say('column paste with a highlighter');

  P := TempName('colpaste.c');
  L := TStringList.Create;
  try
    L.Add('int aaaa1111;');
    L.Add('int bbbb2222;');
    L.Add('int cccc3333;');
    { Well past the limit, so the truncating view is live on this line. }
    L.Add('// ' + StringOfChar('x', 9000));
    L.Add('int dd;');
    L.SaveToFile(P);
  finally
    L.Free;
  end;

  Tab := F.AddTab(F.Documents.OpenFile(P));
  Pump;
  if Tab = nil then Exit;
  V := Tab.ActiveView;

  { An index past the end.  A column paste is a run of edits inside one undo
    block, each firing notifications with a paint pending, so the painter can
    ask about a row the document no longer has.  The buffer below does not
    bounds-check in a Release build. }
  Check('asking about a line past the end is safe',
    not V.LongLines.IsTruncated(999999));
  CheckEqInt('and it reports no visible length', 0,
    V.LongLines.VisibleLength(999999));
  CheckEqInt('and no marker column', 0, V.LongLineMarkerCol(999999));

  Check('the file has a highlighter', V.Highlighter <> nil);
  Check('and a truncated line', V.LongLines.IsTruncated(3));

  { Drag a rectangle over the first three lines, copy it, then paste it at
    the start of the long line -- so the insert lands on the very line the
    display view is clamping. }
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  Pump;
  TLedMousePoke.Press(V, [ssCtrl], V.Gutter.Width + 2 + 4 * V.CharWidth, 2);
  TLedMousePoke.Move(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  TLedMousePoke.Release(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  Pump;
  LedCopy(V);
  Pump;
  Check('a rectangle copies out of a highlighted file', Clipboard.AsText <> '');

  LedClearSelection(V);
  V.SelectionMode := smNormal;
  V.CaretXY := Point(1, 4);
  Pump;
  LedPaste(V);
  Pump;
  Check('pasting onto a truncated line does not fall', V.Lines.Count >= 5);
  V.Undo;
  Pump;

  { And the other direction: copy a rectangle that includes the truncated
    line, which asks the view for text past the point it hides. }
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  Pump;
  TLedMousePoke.Press(V, [ssCtrl], V.Gutter.Width + 2 + 0 * V.CharWidth, 2);
  TLedMousePoke.Move(V, [ssCtrl], V.Gutter.Width + 2 + 6 * V.CharWidth,
    4 * V.LineHeight + 2);
  TLedMousePoke.Release(V, [ssCtrl], V.Gutter.Width + 2 + 6 * V.CharWidth,
    4 * V.LineHeight + 2);
  Pump;
  LedCopy(V);
  Pump;
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  LedPaste(V);
  Pump;
  Check('a rectangle spanning a truncated line survives a round trip',
    V.Lines.Count >= 5);

  { A drag that runs up and to the left.  Every check so far drags down and
    right, so BlockBegin has always been the top-left corner; dragged the
    other way it is the *bottom-right* one, and LedPasteColumn takes it as
    the place to start writing. }
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  TLedMousePoke.Press(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  TLedMousePoke.Move(V, [ssCtrl], V.Gutter.Width + 2 + 4 * V.CharWidth, 2);
  TLedMousePoke.Release(V, [ssCtrl], V.Gutter.Width + 2 + 4 * V.CharWidth, 2);
  Pump;
  Check('dragging up and left still makes a rectangle',
    LedHasColumnSelection(V));
  LedCopy(V);
  Pump;
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  LedPaste(V);
  Pump;
  Check('and it pastes back without falling', V.Lines.Count >= 5);
  V.Undo;
  Pump;

  { Paste *over* a rectangle that was dragged upwards, which is the case
    where BlockBegin is the corner the block is cleared from. }
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  TLedMousePoke.Press(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  TLedMousePoke.Move(V, [ssCtrl], V.Gutter.Width + 2 + 4 * V.CharWidth, 2);
  TLedMousePoke.Release(V, [ssCtrl], V.Gutter.Width + 2 + 4 * V.CharWidth, 2);
  Pump;
  LedPaste(V);
  Pump;
  Check('pasting over an upward rectangle survives', V.Lines.Count >= 5);
  V.Undo;
  Pump;

  { Cut a rectangle, then paste it.  LedCut takes a different path from
    LedCopy -- it copies and then clears the block -- and nothing above cuts. }
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  TLedMousePoke.Press(V, [ssCtrl], V.Gutter.Width + 2 + 4 * V.CharWidth, 2);
  TLedMousePoke.Move(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  TLedMousePoke.Release(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  Pump;
  LedCut(V);
  Pump;
  Check('cutting a rectangle leaves the document standing', V.Lines.Count >= 5);
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  LedPaste(V);
  Pump;
  Check('and it pastes back', V.Lines.Count >= 5);
  V.Undo; V.Undo;
  Pump;

  { With the tab split, so a second view shares the buffer and has a long-line
    view of its own.  An edit through one view notifies the other while it is
    scrolled somewhere else entirely. }
  Tab.SplitView(False);
  Pump;
  Check('the tab split', Tab.ViewCount > 1);
  V := Tab.ActiveView;
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  TLedMousePoke.Press(V, [ssCtrl], V.Gutter.Width + 2 + 4 * V.CharWidth, 2);
  TLedMousePoke.Move(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  TLedMousePoke.Release(V, [ssCtrl], V.Gutter.Width + 2 + 8 * V.CharWidth,
    2 * V.LineHeight + 2);
  Pump;
  LedCopy(V);
  V.CaretXY := Point(1, 4);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  LedPaste(V);
  Pump;
  Check('a column paste in a split tab survives', V.Lines.Count >= 5);
  V.Undo;
  Pump;

  { Pasting past the last line, which extends the document as it goes. }
  V.CaretXY := Point(1, V.Lines.Count);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  LedPaste(V);
  Pump;
  Check('and pasting at the end extends the document', V.Lines.Count >= 5);

  Tab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  DeleteFile(P);
end;

{ Three small things reported from real use, each of which a check could
  have caught and none did. }
procedure TestReportedPolish(F: TLedMainForm);
var
  i, WithIcons: Integer;
begin
  Say('reported polish');

  { The Window menu's document submenu.  Its caption in the form file is the
    placeholder "(no documents)", and nothing ever replaced it, so the submenu
    holding the document list was itself labelled "no documents" however many
    there were. }
  F.PopulateDocMenu;
  Pump;
  CheckGt('the window menu lists the open documents', 0,
    F.DocListMenu.Count);
  Check('and is not still labelled "(no documents)"',
    F.DocListMenu.Caption <> '(no documents)');
  Check('the submenu is enabled when it has entries',
    F.DocListMenu.Enabled);

  { The terminal is a text surface, so the pointer over it should say so. }
  if F.Terminal <> nil then
  begin
    F.Terminal.Start(GetTempDir);
    Pump;
    if F.Terminal.Active <> nil then
      CheckEqInt('the terminal shows a text cursor, not an arrow',
        Ord(crIBeam), Ord(F.Terminal.Active.Cursor));

    { And its context menu had no icons at all, alone among LED's menus. }
    Check('the terminal menu has an image list',
      F.Terminal.Menu.Images <> nil);
    WithIcons := 0;
    for i := 0 to F.Terminal.Menu.Items.Count - 1 do
      if F.Terminal.Menu.Items[i].ImageIndex >= 0 then Inc(WithIcons);
    CheckGt('and its items carry icons', 4, WithIcons);
  end;
end;

{ Copy a rectangle in one document and paste it into another.

  Reported as an access violation.  Every column check before this copied and
  pasted inside one view, and FColumnClip -- the "what we last put on the
  clipboard as a rectangle" note -- is a unit-level variable shared by every
  document, so the target view is not the one the rectangle came from. }
procedure TestColumnPasteAcrossTabs(F: TLedMainForm);
var
  Src, Dst: TLedTab;
  V: TLedEdit;
  i: Integer;
begin
  Say('column paste across tabs');

  Src := F.AddTab(F.Documents.NewDocument);
  Pump;
  if Src = nil then Exit;
  V := Src.ActiveView;
  V.Lines.Text := 'aaaa1111' + LineEnding + 'bbbb2222' + LineEnding +
                  'cccc3333';
  V.ClearUndo;
  Pump;

  V.BlockBegin := Point(5, 1);
  V.BlockEnd := Point(9, 3);
  V.SelectionMode := smColumn;
  LedCopy(V);
  Pump;
  Check('the rectangle copied', Clipboard.AsText <> '');

  { A brand new, empty document: one line, and that line is empty, so the
    paste has to extend the document as it goes. }
  Dst := F.AddTab(F.Documents.NewDocument);
  Pump;
  if Dst = nil then Exit;
  Check('the second tab is the active one', F.ActiveTab = Dst);
  V := Dst.ActiveView;
  CheckEqInt('and it starts with one empty line', 1, V.Lines.Count);

  V.CaretXY := Point(1, 1);
  LedPaste(V);
  Pump;
  CheckGt('pasting a rectangle into an empty document grows it', 1,
    V.Lines.Count);
  CheckEq('first row of the rectangle', '1111', V.Lines[0]);
  CheckEq('and the last', '3333', V.Lines[2]);
  Check('the source document is untouched',
    Src.Document.Master.Lines[0] = 'aaaa1111');

  { And into the middle of a document that is shorter than the rectangle,
    at a column past the end of its lines, which is the padding path. }
  V.Lines.Text := 'short';
  V.ClearUndo;
  Pump;
  V.CaretXY := Point(20, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  LedPaste(V);
  Pump;
  CheckGt('pasting past the end of a short line pads and grows', 1,
    V.Lines.Count);

  { The rows after the first land on lines the caret is *not* on, so those
    lines are still truncated -- and TextBetweenPoints works in the view's
    coordinates, not the buffer's.  Paste at a column past the truncation
    point and the second row is written to a line the view believes is 4096
    characters long. }
  V.Lines.Text := StringOfChar('a', 9000) + LineEnding +
                  StringOfChar('b', 9000) + LineEnding +
                  StringOfChar('c', 9000);
  V.ClearUndo;
  Pump;
  Check('the target lines are truncated', V.LongLines.IsTruncated(1));

  V.CaretXY := Point(6000, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  LedPaste(V);
  Pump;
  Check('pasting past a truncation point does not fall', V.Lines.Count >= 3);
  CheckEqInt('and the rectangle landed at the column asked', 9004,
    Length(V.Lines[0]));
  CheckEqInt('on the line below too', 9004, Length(V.Lines[1]));

  { Last of these, because it replaces the clipboard the checks above rely
    on.  A column selection reaching past the truncation point.  This is the shape
    that crashed: while the logical line was shortened, GetPhysicalCharWidths
    built its width array from the 4096-character view of the line and column
    arithmetic then indexed it with buffer columns -- 5000, 6000 -- off the
    end of a dynamic array.  Which is a read of whatever is past it. }
  V.BlockBegin := Point(5000, 1);
  V.BlockEnd := Point(6000, 3);
  V.SelectionMode := smColumn;
  Pump;
  Check('a rectangle past the truncation point can be read',
    Length(V.SelText) > 0);
  LedCopy(V);
  Pump;
  Check('and copied', Clipboard.AsText <> '');
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;

  { The reported sequence: paste a rectangle into Untitled, then select a
    rectangle *in* Untitled with the mouse.  The second selection is where it
    falls over, and it is dragged to places a drag really goes -- past the end
    of a line, and past the last line -- which is where SynEdit has to invent
    positions that are not in the text. }
  V.Lines.Text := '';
  V.ClearUndo;
  Pump;
  V.CaretXY := Point(1, 1);
  LedPaste(V);
  Pump;
  CheckGt('the rectangle landed in the empty document', 1, V.Lines.Count);

  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  { Well past the right-hand end of every line, and past the last line, and
    stepped so the editor repaints on the way -- 7 in 10 attempts crashed for
    the reporter, so whatever it is depends on how the drag unfolds. }
  TLedMousePoke.Drag(V, [ssCtrl],
    V.Gutter.Width + 2 + 1 * V.CharWidth, 2,
    V.Gutter.Width + 2 + 40 * V.CharWidth, 6 * V.LineHeight + 2, 24);
  Check('selecting a rectangle in the pasted document survives',
    V.Lines.Count > 1);

  { And again, dragging back up and to the left over the same region. }
  TLedMousePoke.Drag(V, [ssCtrl],
    V.Gutter.Width + 2 + 30 * V.CharWidth, 5 * V.LineHeight + 2,
    V.Gutter.Width + 2 + 0 * V.CharWidth, 2, 24);
  Check('and so does dragging back over it', V.Lines.Count > 1);

  { Ten times over, because the report was "very often", not "always". }
  for i := 1 to 10 do
  begin
    TLedMousePoke.Drag(V, [ssCtrl],
      V.Gutter.Width + 2 + (i mod 5) * V.CharWidth, 2,
      V.Gutter.Width + 2 + (20 + i) * V.CharWidth,
      (2 + (i mod 4)) * V.LineHeight + 2, 12);
    LedCopy(V);
    Application.ProcessMessages;
  end;
  Check('and ten rectangles in a row do not', V.Lines.Count > 1);
  LedCopy(V);
  Pump;
  V.CaretXY := Point(1, 1);
  LedClearSelection(V);
  V.SelectionMode := smNormal;
  Pump;
  LedPaste(V);
  Pump;
  Check('and copying that second rectangle and pasting it again',
    V.Lines.Count > 1);

  Dst.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  Src.Document.Master.Modified := False;
  if F.ActiveTab = Src then F.CloseActiveTab(False);
  Pump;
end;

{ The crash-recovery journal, over a modified untitled document.

  Reported as: paste a column into Untitled, wait a few seconds, crash.  The
  paste was incidental -- it made the document modified, which is what brings
  it into the journal pass -- and the few seconds were the recovery timer.
  RecoveryTick stands down under --self-test, so this whole subsystem had no
  GUI coverage at all and the nil dereference in it survived every run. }
procedure TestRecoveryJournalPass(F: TLedMainForm);
var
  Tab: TLedTab;
  V: TLedEdit;
begin
  Say('crash-recovery journal pass');

  Tab := F.AddTab(F.Documents.NewDocument);
  Pump;
  if Tab = nil then Exit;
  V := Tab.ActiveView;

  { The precondition the crash needed, and one this suite already asserts
    elsewhere: an untitled document has no language, so LangInfo is nil. }
  Check('an untitled document still has no language',
    Tab.Document.LangInfo = nil);

  V.CaretXY := Point(1, 1);
  V.InsertTextAtCaret('const M' + LineEnding + 'const P');
  Pump;
  Check('and editing it makes it modified', Tab.Document.Modified);

  { This is the line that fell over. }
  F.RunRecoveryPassNow;
  Pump;
  Check('a journal pass over it does not fall', Tab.Document.Modified);

  { Once saved it leaves the journal, which is the other half of the pass. }
  Tab.Document.Master.Modified := False;
  F.RunRecoveryPassNow;
  Pump;
  Check('and a pass with nothing modified is fine too',
    not Tab.Document.Modified);

  F.CloseActiveTab(False);
  Pump;
end;

{ How much red is in the gutter.  A filled breakpoint disc has more of it
  than a hollow ring, which is the only way to tell from outside that a
  conditional breakpoint is drawn differently. }
function GutterRed(V: TLedEdit): Integer;
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  C: TFPColor;
  x, y: Integer;
begin
  Result := 0;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(V.Width, V.Height);
    V.PaintTo(Bmp.Canvas, 0, 0);
    Img := Bmp.CreateIntfImage;
    try
      for y := 0 to Img.Height - 1 do
        for x := 0 to 40 do
          if x < Img.Width then
          begin
            C := Img.Colors[x, y];
            if (C.Red > 40000) and (C.Green < 20000) and (C.Blue < 20000) then
              Inc(Result);
          end;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ The width in pixels of the widest chevron painted in the fold column.

  Nothing else is drawn in that column, so the widest run of non-background
  ink on any row is the chevron at its waist.  The background is taken as the
  commonest colour in the column rather than assumed, because LED ships eight
  themes and half of them are light. }
{ The commonest colour on scanline AY of the text area. }
function DominantColour(V: TLedEdit; AY: Integer): TColor;
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  x, x0, i, Best: Integer;
  C: TFPColor;
  Cols: array of record C: TColor; N: Integer; end;
  Cur: TColor;
  Found: Boolean;
begin
  Result := clNone;
  if (AY < 0) or (AY >= V.Height) then Exit;
  x0 := 0;
  if V.Gutter.Visible then x0 := V.Gutter.Width;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(V.Width, V.Height);
    V.PaintTo(Bmp.Canvas, 0, 0);
    Img := Bmp.CreateIntfImage;
    try
      SetLength(Cols, 0);
      for x := x0 to Img.Width - 1 do
      begin
        C := Img.Colors[x, AY];
        Cur := RGBToColor(C.Red shr 8, C.Green shr 8, C.Blue shr 8);
        Found := False;
        for i := 0 to High(Cols) do
          if Cols[i].C = Cur then begin Inc(Cols[i].N); Found := True; Break; end;
        if not Found then
        begin
          SetLength(Cols, Length(Cols) + 1);
          Cols[High(Cols)].C := Cur; Cols[High(Cols)].N := 1;
        end;
      end;
      Best := -1;
      for i := 0 to High(Cols) do
        if (Best < 0) or (Cols[i].N > Cols[Best].N) then Best := i;
      if Best >= 0 then Result := Cols[Best].C;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ The highlight-all markup keeps both its match list and the routine that
  fills it protected, so both are reached the way this suite reaches any
  protected member: through a descendant that publishes class methods.

  Why the search has to be asked for at all: CheckState only arms a TTimer,
  and the timer's handler is what searches.  A TTimer does not fire under
  Application.ProcessMessages, which is what drives this suite -- the same
  limitation Led.Core.Gdb documents and polls around.  The delay is
  SynEdit's and unmodified; what is checked here is that the search, when it
  runs, finds the right words. }
type
  TLedMarkupPeek = class(TSynEditMarkupHighlightAllCaret)
  public
    class function Count(A: TSynEditMarkupHighlightAllCaret): Integer;
    class procedure SearchNow(A: TSynEditMarkupHighlightAllCaret);
    { Whether those matches would be painted.  Not the same question as how
      many there are: SynEdit drops a lone match unless it is told not to. }
    class function Paints(A: TSynEditMarkupHighlightAllCaret): Boolean;
    { Whether the painter will ask this markup for colours at all.  The
      markup manager checks RealEnabled before every question it asks. }
    class function Live(A: TSynEditMarkupHighlightAllCaret): Boolean;
  end;

class function TLedMarkupPeek.Count(A: TSynEditMarkupHighlightAllCaret): Integer;
begin
  Result := 0;
  if A <> nil then Result := TLedMarkupPeek(A).Matches.Count;
end;

class function TLedMarkupPeek.Paints(A: TSynEditMarkupHighlightAllCaret): Boolean;
begin
  Result := (A <> nil) and TLedMarkupPeek(A).HasVisibleMatch;
end;

class function TLedMarkupPeek.Live(A: TSynEditMarkupHighlightAllCaret): Boolean;
begin
  Result := (A <> nil) and TLedMarkupPeek(A).RealEnabled;
end;

class procedure TLedMarkupPeek.SearchNow(A: TSynEditMarkupHighlightAllCaret);
begin
  if A = nil then Exit;
  TLedMarkupPeek(A).CheckState;
  TLedMarkupPeek(A).ScrollTimerHandler(A);
end;

{ How many pixels of scanline AY, across the text area, are exactly AColour. }
function ScanlineCount(V: TLedEdit; AY: Integer; AColour: TColor): Integer;
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  x, x0: Integer;
  C, Want: TFPColor;
begin
  Result := 0;
  if (AY < 0) or (AY >= V.Height) then Exit;
  Want := TColorToFPColor(ColorToRGB(AColour));
  x0 := 0;
  if V.Gutter.Visible then x0 := V.Gutter.Width;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(V.Width, V.Height);
    V.PaintTo(Bmp.Canvas, 0, 0);
    Img := Bmp.CreateIntfImage;
    try
      for x := x0 to Img.Width - 1 do
      begin
        C := Img.Colors[x, AY];
        if (C.Red = Want.Red) and (C.Green = Want.Green) and
           (C.Blue = Want.Blue) then Inc(Result);
      end;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ The width in pixels of the widest chevron painted in the fold column.

  Nothing else is drawn in that column, so the widest run of non-background
  ink on any row is the chevron at its waist. }
function ChevronSpan(V: TLedEdit): Integer;
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  x, y, x0, x1, Lo, Hi: Integer;
  C, Bg: TFPColor;
begin
  Result := 0;
  if (V.Gutter.CodeFoldPart = nil) or (not V.Gutter.CodeFoldPart.Visible) then
    Exit;
  x0 := V.Gutter.CodeFoldPart.Left;
  x1 := x0 + V.Gutter.CodeFoldPart.Width - 1;

  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(V.Width, V.Height);
    V.PaintTo(Bmp.Canvas, 0, 0);
    Img := Bmp.CreateIntfImage;
    try
      if x1 >= Img.Width then x1 := Img.Width - 1;
      if x1 < x0 then Exit;

      for y := 0 to Img.Height - 1 do
      begin
        { This row's own background, read at the column's left edge.  Taken
          per row rather than once for the view: the caret's line is painted
          in a different colour, and against a single background every pixel
          of that row counts as ink and the column measures full width. }
        Bg := Img.Colors[x0, y];
        Lo := -1; Hi := -1;
        for x := x0 to x1 do
        begin
          C := Img.Colors[x, y];
          if (C.Red <> Bg.Red) or (C.Green <> Bg.Green) or
             (C.Blue <> Bg.Blue) then
          begin
            if Lo < 0 then Lo := x;
            Hi := x;
          end;
        end;
        if (Lo >= 0) and (Hi - Lo + 1 > Result) then Result := Hi - Lo + 1;
      end;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ The same, in grey: a disabled breakpoint is drawn as a grey ring, and
  nothing else about the view says whether it reached the screen.

  Read as a difference rather than as an absolute, because the line numbers
  beside it are grey too -- what matters is that disabling one *adds* grey
  where it took red away. }
function GutterGrey(V: TLedEdit): Integer;
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  C: TFPColor;
  x, y: Integer;
begin
  Result := 0;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(V.Width, V.Height);
    V.PaintTo(Bmp.Canvas, 0, 0);
    Img := Bmp.CreateIntfImage;
    try
      for y := 0 to Img.Height - 1 do
        for x := 0 to 40 do
          if x < Img.Width then
          begin
            C := Img.Colors[x, y];
            { clGray is $808080, which is $8080 in each 16-bit channel. }
            if (Abs(Integer(C.Red) - Integer(C.Green)) < 3000) and
               (Abs(Integer(C.Green) - Integer(C.Blue)) < 3000) and
               (C.Red > 26000) and (C.Red < 40000) then
              Inc(Result);
          end;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ The debugger, end to end, against a real gdb.

  Compiles a C program with gcc, opens it, sets a breakpoint by the same call
  the gutter click makes, starts a session and waits for the stop.  Skipped
  whole when gcc or gdb is missing.

  Worth doing in the GUI suite even though Led.Core.Tests.Gdb already drives
  a session headlessly: what is checked here is the wiring -- that a
  breakpoint reaches the editor as a gutter mark, that stopping moves the
  caret into the right file, and that the panes fill. }
procedure TestDebugger(F: TLedMainForm);
var
  Dir, Src, Bin, LaunchDir: string;
  L: TStringList;
  P: TProcess;
  Tab: TLedTab;
  V: TLedEdit;
  Waited: Integer;
  Built: Boolean;
  Bmp: TBitmap;
  Img: TLazIntfImage;
  C: TFPColor;
  x, y, Reds, Rings, Greys, Ticked: Integer;
  Row: TTreeNode;
  Btn: TToolButton;
begin
  Say('debugger');

  { The pane and the actions exist whether or not gdb does -- a saved layout
    naming the pane has to find it. }
  { Each button wears its own command's icon.

    Read off the button's Tag rather than its position, because position is
    what was wrong: a TToolBar lists Buttons[] in creation order, these are
    created in reverse so they read left to right, and the icons were applied
    by position -- so every one but Step Over's landed on the wrong button.
    Continue wore the breakpoint icon, Toggle Breakpoint wore Run's triangle,
    and Build wore the debugger's bug.  It went unseen while the breakpoint
    icon was a plain disc and only showed when it became a stop sign. }
  Btn := nil;
  for x := 0 to F.DebugPane.Bar.ButtonCount - 1 do
  begin
    y := F.DebugPane.Bar.Buttons[x].ImageIndex;
    case TLedDebugCommand(F.DebugPane.Bar.Buttons[x].Tag) of
      ldcStart:    CheckEqInt('Start wears the debugger icon',
                     LedIconIndex('debug'), y);
      ldcContinue: CheckEqInt('Continue wears Run, not the breakpoint',
                     LedIconIndex('run'), y);
      ldcPause:    CheckEqInt('Pause wears Pause', LedIconIndex('pause'), y);
      ldcStop:     CheckEqInt('Stop wears Stop', LedIconIndex('stop'), y);
      ldcStepOver: CheckEqInt('Step Over wears Step Over',
                     LedIconIndex('stepover'), y);
      ldcStepInto: CheckEqInt('Step Into wears Step Into',
                     LedIconIndex('stepinto'), y);
      ldcStepOut:  CheckEqInt('Step Out wears Step Out',
                     LedIconIndex('stepout'), y);
      ldcToggleBreakpoint:
                   begin
                     Btn := F.DebugPane.Bar.Buttons[x];
                     CheckEqInt('and F9 wears the stop sign',
                       LedIconIndex('breakpoint'), y);
                   end;
    end;
  end;
  Check('the F9 button was found at all', Btn <> nil);

  { Every toolbar LED builds answers the pointer the same way.  The main one
    got its painter first and the panes' did not, so a hover lit a button on
    one toolbar and nothing on the others. }
  Check('the main toolbar paints its own buttons',
    Assigned(F.ToolBar1.OnPaintButton));

  { A theme chooser on the toolbar, so switching does not mean going through
    a menu.  Its list is built when it drops rather than written into the
    form file, because the schemes are read from data/themes at run time. }
  Check('there is a theme button', F.ThemeButton <> nil);
  if F.ThemeButton <> nil then
  begin
    Check('which opens a menu', F.ThemeButton.DropdownMenu <> nil);
    Check('and its face opens it too, not just the arrow',
      Assigned(F.ThemeButton.OnClick));
    F.ThemeButton.DropdownMenu.PopupComponent := F;
    if Assigned(F.ThemeButton.DropdownMenu.OnPopup) then
      F.ThemeButton.DropdownMenu.OnPopup(F.ThemeButton.DropdownMenu);
    CheckEqInt('listing every shipped scheme', LedThemes.Count,
      F.ThemeButton.DropdownMenu.Items.Count);
    Ticked := 0;
    for x := 0 to F.ThemeButton.DropdownMenu.Items.Count - 1 do
      if F.ThemeButton.DropdownMenu.Items[x].Checked then Inc(Ticked);
    CheckEqInt('with exactly one of them ticked', 1, Ticked);
  end;
  Check('and so does the debugger pane''s',
    Assigned(F.DebugPane.Bar.OnPaintButton));

  Check('the debugger pane is registered', F.Dock.FindPane('debug') <> nil);
  Check('and the controller exists', F.Debugger <> nil);
  Check('stepping is off when nothing is running', not F.Debugger.CanStep);
  Check('and so is stopped', not F.Debugger.Stopped);

  if not LedGdbAvailable then
  begin
    Say('  (gdb is not installed; skipping the session)');
    Exit;
  end;
  if FindDefaultExecutablePath('gcc') = '' then
  begin
    Say('  (gcc is not installed; skipping the session)');
    Exit;
  end;

  Dir := TempName('dbgproj');
  LaunchDir := IncludeTrailingPathDelimiter(Dir) + '.led';
  ForceDirectories(LaunchDir);
  Src := IncludeTrailingPathDelimiter(Dir) + 'main.c';
  Bin := IncludeTrailingPathDelimiter(Dir) + 'main';

  L := TStringList.Create;
  try
    L.Add('#include <stdio.h>');
    { The global is on the same physical line as the struct so that the line
      numbers the rest of this test names -- 6, 7 and 11 -- do not move.  The
      char array is there because gdb pads one to its declared length. }
    L.Add('struct P { int x; int y; char tag[8]; }; int hits = 0;');
    L.Add('int twice(int n)');
    L.Add('{');
    L.Add('    struct P p = { n, n + 1, "ab" };');
    L.Add('    int r = n * 2;');      { line 6 -- the breakpoint }
    L.Add('    return r + p.x - p.y;');
    L.Add('}');
    L.Add('int main(void)');
    L.Add('{');
    L.Add('    printf("%d\\n", twice(21));');   { line 11 -- the call }
    L.Add('    hits++;');                        { line 12 -- what is watched }
    L.Add('    return 0;');
    L.Add('}');
    L.SaveToFile(Src);

    { A launch.json, so the project half is exercised too. }
    L.Clear;
    L.Add('{ "configurations": [');
    L.Add('  { "name": "Debug", "program": "${workspaceFolder}/main" }');
    L.Add('] }');
    L.SaveToFile(IncludeTrailingPathDelimiter(LaunchDir) + 'launch.json');
  finally
    L.Free;
  end;

  P := TProcess.Create(nil);
  try
    P.Executable := FindDefaultExecutablePath('gcc');
    P.Parameters.Add('-g');
    P.Parameters.Add('-O0');
    P.Parameters.Add(Src);
    P.Parameters.Add('-o');
    P.Parameters.Add(Bin);
    P.Options := [poWaitOnExit, poUsePipes, poStderrToOutPut, poNoConsole];
    P.Execute;
    Built := (P.ExitStatus = 0) and FileExists(Bin);
  finally
    P.Free;
  end;
  if not Built then
  begin
    Say('  (gcc could not build the fixture; skipping)');
    Exit;
  end;

  Tab := F.AddTab(F.Documents.OpenFile(Src));
  Pump;
  if Tab = nil then Exit;
  V := Tab.ActiveView;

  { The project is found by walking up from the file. }
  F.Debugger.NoteActiveFile(Src);
  Check('the project is found from the source', F.Debugger.Project.Root <> '');
  CheckEqInt('with its one configuration', 1,
    F.Debugger.Project.ConfigCount);

  { A real click in the gutter, not the call it is supposed to make.  What
    was checked here before was ToggleBreakpoint, with a comment claiming it
    was "exactly what a gutter click does" -- which is an assumption, and the
    one thing this suite exists to stop being taken on trust. }
  { The click has to land where a person aims, which is the line number --
    "click the gutter beside the line" means that to anyone who has used
    another debugger.  It used to mean a six-pixel unmarked strip at the far
    left, and clicking the number did nothing. }
  Check('the gutter has a zone for it', V.BreakpointZone(x, y));
  CheckGt('wider than the marks column alone', V.Gutter.MarksPart.Width,
    y - x);
  Check('and it stops before the fold column',
    y <= V.Gutter.CodeFoldPart.Left);

  TLedMousePoke.Press(V, [],
    V.Gutter.LineNumberPart.Left + V.Gutter.LineNumberPart.Width div 2,
    5 * V.LineHeight + V.LineHeight div 2);
  Pump;
  CheckEqInt('clicking the line number sets a breakpoint', 1,
    F.Debugger.BreakpointCount);
  Check('on the line clicked', F.Debugger.HasBreakpoint(Src, 6));

  { And clicking it again clears it, which is the other half of "toggle". }
  TLedMousePoke.Press(V, [],
    V.Gutter.LineNumberPart.Left + V.Gutter.LineNumberPart.Width div 2,
    5 * V.LineHeight + V.LineHeight div 2);
  Pump;
  CheckEqInt('and clicking it again clears it', 0,
    F.Debugger.BreakpointCount);

  { The fold column is not part of the zone: a click there must still fold. }
  TLedMousePoke.Press(V, [],
    V.Gutter.CodeFoldPart.Left + V.Gutter.CodeFoldPart.Width div 2,
    5 * V.LineHeight + V.LineHeight div 2);
  Pump;
  CheckEqInt('but the fold column still folds instead', 0,
    F.Debugger.BreakpointCount);

  F.Debugger.ToggleBreakpoint(Src, 6);
  Pump;
  CheckEqInt('one breakpoint', 1, F.Debugger.BreakpointCount);
  Check('and the editor shows it in the gutter', V.HasBreakpoint(6));
  F.Debugger.ToggleBreakpoint(Src, 6);
  Pump;
  CheckEqInt('toggling again removes it', 0, F.Debugger.BreakpointCount);
  Check('and the mark goes with it', not V.HasBreakpoint(6));
  F.Debugger.ToggleBreakpoint(Src, 6);
  Pump;

  { And that the dot is actually drawn, not merely recorded.  The gutter is
    painted by TLedEdit.Paint, so nothing about the breakpoint list says
    whether anything reached the screen -- which is the shape of bug this
    suite has been caught by before. }
  Reds := GutterRed(V);
  CheckGt('the breakpoint is painted in the gutter', 0, Reds);

  { A condition makes it hollow, so it cannot be mistaken for one that always
    stops.  Set before the session exists, which is also the path that has to
    survive being replayed to gdb at Start. }
  F.Debugger.SetBreakpointCondition(Src, 6, 'n == 21');
  Pump;
  CheckEq('the condition is remembered', 'n == 21',
    F.Debugger.BreakpointCondition(Src, 6));
  Check('and the gutter knows it is conditional', V.BreakpointIsConditional(6));
  { A ring is still drawn -- it must not vanish -- but uses less ink than a
    filled disc.  Asserting only "different" would pass if it disappeared. }
  Rings := GutterRed(V);
  CheckGt('the ring is drawn', 0, Rings);
  CheckGt('but with less ink than a filled disc', Rings, Reds);
  F.Debugger.SetBreakpointCondition(Src, 6, '');
  Pump;
  Check('clearing it fills the dot again', not V.BreakpointIsConditional(6));
  CheckEqInt('and the red comes back', Reds, GutterRed(V));

  { --- the breakpoint list --- }
  Check('the breakpoint pane is registered', F.Dock.FindPane('breaks') <> nil);
  Check('and the debugger has it', F.BreakPane <> nil);
  CheckEqInt('the list has the breakpoint in it', 1, F.BreakPane.RowCount);
  CheckEq('shown as a breakpoint', 'Breakpoint', F.BreakPane.RowText(0, 2));
  CheckEq('at the file and line it was set on', 'main.c:6',
    F.BreakPane.RowText(0, 3));
  CheckEq('with no number until gdb has been told', '--',
    F.BreakPane.RowText(0, 0));
  CheckEq('and switched on', 'yes', F.BreakPane.RowText(0, 1));

  { A condition reaches the list as well as the gutter. }
  F.Debugger.SetBreakpointCondition(Src, 6, 'n == 21');
  Pump;
  CheckEq('a condition is shown beside it', 'n == 21',
    F.BreakPane.RowText(0, 4));
  F.Debugger.SetBreakpointCondition(Src, 6, '');
  Pump;
  CheckEq('and clearing it empties the column', '',
    F.BreakPane.RowText(0, 4));

  { Turning one off keeps it and greys it, which is the whole point: a line
    one has deliberately silenced must not look like a line one forgot. }
  Greys := GutterGrey(V);
  F.Debugger.SetBreakpointEnabled(0, False);
  Pump;
  CheckEq('the list says it is off', 'no', F.BreakPane.RowText(0, 1));
  Check('the editor still has it', V.HasBreakpoint(6));
  Check('and knows it is off', not V.BreakpointIsEnabled(6));
  CheckEqInt('nothing red is drawn for it any more', 0, GutterRed(V));
  CheckGt('but a grey ring is', Greys, GutterGrey(V));

  F.Debugger.SetBreakpointEnabled(0, True);
  Pump;
  CheckEq('switching it back on says so', 'yes', F.BreakPane.RowText(0, 1));
  CheckEqInt('and the red dot returns', Reds, GutterRed(V));

  { The pane's own Start button must do what Ctrl+F5 does.  It did not:
    everything that makes Start work -- noting the active file, which is what
    finds the project and therefore what there is to debug; showing the
    Output pane; rebuilding a stale binary -- lived in the window, and the
    pane's buttons went straight to the debugger instead.  Pressing Start
    there answered "nothing to debug" in a project the key debugged fine.

    Checked by pressing the button and looking for a side effect only the
    window's path produces. }
  F.Dock.HidePane('output');
  { Forgotten on purpose: the error the user saw was "nothing to debug", and
    it came from the project never being looked for.  Pointing the project at
    a folder that has none puts it back in that state, so the check is of the
    button finding it and not of it having been found earlier. }
  F.Debugger.Project.LoadFrom(GetTempDir);
  Pump;
  Check('the output pane starts hidden', not F.Dock.PaneVisible('output'));
  CheckEqInt('and the project has been forgotten', 0,
    F.Debugger.Project.ConfigCount);
  Btn := nil;
  for x := 0 to F.DebugPane.Bar.ButtonCount - 1 do
    if F.DebugPane.Bar.Buttons[x].Tag = Ord(ldcStart) then
      Btn := F.DebugPane.Bar.Buttons[x];
  Check('the pane has a Start button', Btn <> nil);
  if Btn <> nil then
  begin
    Btn.Click;
    Pump;
    Check('pressing it goes through the window, which shows Output',
      F.Dock.PaneVisible('output'));
    Check('and notes the active file, so the project is found',
      F.Debugger.Project.ConfigCount > 0);
  end;
  F.Debugger.Stop;
  Pump;

  { And now actually debug it. }
  Check('the session starts', F.Debugger.Start);
  Waited := 0;
  while (not F.Debugger.Stopped) and (Waited < 20000) do
  begin
    Pump;
    Sleep(20);
    Inc(Waited, 20);
  end;

  Check('the program stops', F.Debugger.Stopped);
  if F.Debugger.Stopped then
  begin
    CheckEqInt('on the line the breakpoint is on', 6, F.Debugger.CurrentLine);
    Check('in the file it was set in',
      Pos('main.c', F.Debugger.CurrentFile) > 0);
    Check('the editor marks where execution is', V.DebugLine = 6);
    Check('stepping is offered now', F.Debugger.CanStep);

    { Locals and the stack are asked for when the stop arrives and answered a
      few exchanges later, so they are waited for rather than read at once --
      the first version of this checked immediately and found both empty. }
    Waited := 0;
    while (F.DebugPane.Locals.Items.Count = 0) and (Waited < 8000) do
    begin
      Pump;
      Sleep(20);
      Inc(Waited, 20);
    end;
    CheckGt('the locals pane filled', 0, F.DebugPane.Locals.Items.Count);
    CheckGt('and the call stack', 1, F.DebugPane.Stack.Items.Count);
    if F.DebugPane.Stack.Items.Count > 0 then
      CheckEq('whose innermost frame is the function stopped in', 'twice',
        F.DebugPane.Stack.Items[0].SubItems[0]);
  end;

  { --- run to cursor --- }
  if F.Debugger.Stopped then
  begin
    { Stopped on line 6; the caret goes to 7 and the program runs there.
      gdb calls this reason "location-reached". }
    F.Debugger.RunToCursor(Src, 7);
    Waited := 0;
    while (F.Debugger.CurrentLine <> 7) and (Waited < 10000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;
    CheckEqInt('run to cursor arrives at the line', 7,
      F.Debugger.CurrentLine);
    Check('and the editor marks it', V.DebugLine = 7);
  end;

  { --- drilling into a struct --- }
  if F.Debugger.Stopped then
  begin
    { Run to cursor moved execution, so the tree has been cleared and is
      being refilled -- reading it now finds it empty.  The first version of
      this check did exactly that. }
    Waited := 0;
    while (F.DebugPane.Locals.Items.Count = 0) and (Waited < 8000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;

    { The struct row is the one shown as "name: type" -- an aggregate has no
      value of its own under --simple-values, which is what tells it from a
      scalar without LED parsing C types. }
    Row := nil;
    for x := 0 to F.DebugPane.Locals.Items.Count - 1 do
      if Copy(F.DebugPane.Locals.Items[x].Text, 1, 3) = 'p: ' then
        Row := F.DebugPane.Locals.Items[x];
    Check('the struct is listed as an aggregate', Row <> nil);

    if Row <> nil then
    begin
      { One placeholder child, so the tree draws something to click. }
      CheckEqInt('with a placeholder to make it openable', 1, Row.Count);
      Check('and nothing real in it yet', Row.Items[0].Text = '...');

      { Opening it is what asks gdb -- two round trips the first time, since
        the row has no variable object yet. }
      Row.Expand(False);
      Waited := 0;
      while (Row.Count < 2) and (Waited < 10000) do
      begin
        Pump; Sleep(20); Inc(Waited, 20);
      end;
      CheckEqInt('opening it fetches all three fields', 3, Row.Count);
      { p = { n, n + 1, "ab" } with n = 21. }
      CheckEq('the first with its value', 'x = 21', Row.Items[0].Text);
      CheckEq('and the second', 'y = 22', Row.Items[1].Text);
      Check('leaves are not openable', Row.Items[0].Count = 0);

      { A char array is an array to gdb: --simple-values gives it no value of
        its own, so it is listed as an aggregate that opens into its elements
        rather than shown as a string.  Where the padding does show is
        wherever the array is *evaluated* -- a watch, or a hover -- and both
        of those are checked below. }
      CheckEq('a char array opens like any other', 'tag: char [8]',
        Row.Items[2].Text);
    end;
  end;

  { --- hovering over one --- }
  if F.Debugger.Stopped then
  begin
    { The fixture stops in twice(), whose only locals are scalars, so switch
      to main's frame where the struct is. }
    F.Debugger.Session.RequestFrames;
    Waited := 0;
    while (Length(F.Debugger.Session.Frames) < 2) and (Waited < 6000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;

    { Hover: the editor decides what the pointer is over, the debugger says
      what it is worth.  Driven through the same two calls the mouse makes. }
    { Line 6 is "    int r = n * 2;" -- the parameter n is at column 13,
      and r is not assigned until this line runs. }
    CheckEq('the editor reads an expression off the line', 'n',
      LedExpressionAt(V.Lines[5], 13));
    CheckEq('and refuses the type keyword beside it', '',
      LedExpressionAt(V.Lines[5], 6));
    { Exactly what MouseMove does when the pointer comes to rest -- the
      handler is already on the view, put there by the tab. }
    Check('the view has a hover handler', Assigned(V.OnHoverExpression));
    V.RequestHover('n');
    Waited := 0;
    { Until the placeholder is replaced.  Waiting for '=' finds the
      placeholder itself, which RequestHover puts there at once. }
    while (Pos(' = ...', V.Hint) > 0) and (Waited < 8000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;
    Check('hovering a local shows its value', Pos('n = 21', V.Hint) > 0);

    { And a second hover over the same thing is answered from the cache,
      which is what stops a round trip per pixel of mouse movement. }
    V.RequestHover('');
    V.RequestHover('n');
    Check('and a repeat is answered at once', Pos('n = 21', V.Hint) > 0);

    { A watch on the char array, which is the path that shows gdb's padding:
      a watch evaluates the expression rather than listing its children. }
    F.DebugPane.TypeWatch('p.tag');
    Waited := 0;
    while (F.DebugPane.Watches.Items.Count = 0) and (Waited < 4000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;
    CheckEqInt('the watch is listed', 1, F.DebugPane.Watches.Items.Count);
    Waited := 0;
    while (F.DebugPane.Watches.Items[0].SubItems[0] = '') and
          (Waited < 6000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;
    CheckEq('and shows the string without its padding', '"ab"',
      F.DebugPane.Watches.Items[0].SubItems[0]);

    { Hovering a struct.  It used to arrive as one line, which is what "it
      does not show the subfields" means in practice -- they are all there,
      in a paragraph. }
    V.RequestHover('');
    V.RequestHover('p');
    Waited := 0;
    while (Pos(' = ...', V.Hint) > 0) and (Waited < 8000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;
    Check('hovering a struct answers: ' + V.Hint, Pos('x = 21', V.Hint) > 0);
    Check('with one field to a line', Pos(LineEnding, V.Hint) > 0);
    Check('and its char array unpadded', Pos('"ab"', V.Hint) > 0);
    Check('nothing of the padding survives', Pos('\000', V.Hint) = 0);

    { Hovering the *type* is not a question gdb can answer: it says "Attempt
      to use a type name as an expression", and that used to be shown as
      though it were the value. }
    V.RequestHover('');
    V.RequestHover('struct P');
    Waited := 0;
    while (Pos(' = ...', V.Hint) > 0) and (Waited < 8000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;
    CheckEq('a type name produces no tooltip at all', '', V.Hint);
    Check('and the hint is switched off with it', not V.ShowHint);
  end;

  { --- watchpoints --- }
  if F.Debugger.Stopped then
  begin
    { gdb has numbered the breakpoint by now, and has been counting hits. }
    Check('the list shows the number gdb gave it',
      F.BreakPane.RowText(0, 0) <> '--');
    CheckGt('and that it has been hit', 0,
      StrToIntDef(F.BreakPane.RowText(0, 5), 0));

    { The pane's own Breakpoint button, which was wired to ldcStop and so
      ended the session instead of setting anything.  Checked while a session
      is live, because that is the only state in which the two are told
      apart. }
    V.CaretY := 11;
    F.Debugger.Command(ldcToggleBreakpoint);
    Pump;
    CheckEqInt('the Breakpoint button sets one at the caret', 2,
      F.Debugger.BreakpointCount);
    Check('and leaves the session alone', F.Debugger.Session.Alive);
    Check('which is still stopped', F.Debugger.Stopped);
    { Both numbered by gdb, which is the state in which removing one used to
      remove the next one with it: -break-delete reports the removal back
      through OnBreakRemoved, which dropped the row -- and then it was
      dropped a second time by an index that had already shifted. }
    Waited := 0;
    while ((F.BreakPane.RowText(0, 0) = '--') or
           (F.BreakPane.RowText(1, 0) = '--')) and (Waited < 6000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;
    Check('gdb numbered both of them',
      (F.BreakPane.RowText(0, 0) <> '--') and (F.BreakPane.RowText(1, 0) <> '--'));
    F.Debugger.RemoveBreakpoint(0);
    Pump;
    CheckEqInt('removing the first removes exactly one', 1,
      F.Debugger.BreakpointCount);
    CheckEq('and the one left is the other', 'main.c:11',
      F.BreakPane.RowText(0, 3));

    { Back to the one breakpoint on line 6 that the rest of this expects. }
    F.Debugger.RemoveBreakpoint(0);
    Pump;
    F.Debugger.ToggleBreakpoint(Src, 6);
    Pump;
    CheckEqInt('and takes it away again', 1, F.Debugger.BreakpointCount);

    { Typed into the pane's own box, so what is exercised is the widget and
      not the event it happens to raise. }
    F.BreakPane.TypeWatchpoint('hits', lgbWatch);
    Waited := 0;
    while (F.BreakPane.RowCount < 2) and (Waited < 4000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;
    CheckEqInt('the watchpoint joins the list', 2, F.BreakPane.RowCount);
    CheckEq('as a watchpoint', 'Write watch', F.BreakPane.RowText(1, 2));
    CheckEq('on the expression typed', 'hits', F.BreakPane.RowText(1, 3));

    Waited := 0;
    while (F.BreakPane.RowText(1, 0) = '--') and (Waited < 6000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;
    Check('and gdb numbered it too', F.BreakPane.RowText(1, 0) <> '--');

    { hits is written in main, after twice() returns -- so continuing from
      line 7 with the breakpoint behind us can only stop on the watchpoint. }
    F.Debugger.SetBreakpointEnabled(0, False);
    Pump;
    F.Debugger.Command(ldcContinue);
    { Waits for the line it should stop on rather than for the line to
      change.  Waiting for a change and then reading raced gdb: a stop
      reported before the caret had settled satisfied the loop, the check read
      whatever was there at that instant, and this failed perhaps three runs
      in eight -- on code nobody had touched.  Waiting for the value itself
      loses nothing, because a run that never reaches line 13 still falls out
      at the timeout and still fails on what it did reach. }
    Waited := 0;
    while (F.Debugger.CurrentLine <> 13) and (Waited < 15000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;
    CheckEqInt('the watchpoint stops on the line after the write', 13,
      F.Debugger.CurrentLine);
    Waited := 0;
    while (StrToIntDef(F.BreakPane.RowText(1, 5), 0) = 0) and (Waited < 4000) do
    begin
      Pump; Sleep(20); Inc(Waited, 20);
    end;
    CheckEqInt('and the list counts the hit', 1,
      StrToIntDef(F.BreakPane.RowText(1, 5), 0));

    { Removing it through the list is what the Remove button does.  The pane
      is shown first: a list view with no window handle behind it keeps no
      selection, so the check would be testing the wrong thing. }
    F.Dock.EdgeVisible[ledBottom] := True;
    F.Dock.ShowPane('breaks');
    Pump;
    F.BreakPane.Select(1);
    CheckEqInt('the row can be selected', 1, F.BreakPane.Selected);
    F.Debugger.RemoveBreakpoint(1);
    Pump;
    CheckEqInt('removing it leaves only the breakpoint', 1,
      F.BreakPane.RowCount);
  end;

  F.Debugger.Stop;
  Pump;
  Check('stopping clears the execution mark', V.DebugLine = 0);

  { Forgetting everything empties the list and the gutter with it. }
  F.Debugger.RemoveAllBreakpoints;
  Pump;
  CheckEqInt('remove-all empties the list', 0, F.BreakPane.RowCount);
  Check('and the gutter mark goes with it', not V.HasBreakpoint(6));
  CheckEqInt('with nothing left painted', 0, GutterRed(V));
  F.Debugger.ToggleBreakpoint(Src, 6);
  Pump;

  { --- building.  The launch.json above names no build command, so add one
    and check the project compiles through the ordinary tool runner. --- }
  L := TStringList.Create;
  try
    L.Add('{ "configurations": [');
    L.Add('  { "name": "Debug", "program": "${workspaceFolder}/main",');
    L.Add('    "preLaunchTask": "build" }');
    L.Add('] }');
    L.SaveToFile(IncludeTrailingPathDelimiter(LaunchDir) + 'launch.json');
    L.Clear;
    L.Add('{ "tasks": [');
    L.Add('  { "label": "build", "command": "gcc",');
    L.Add('    "args": ["-g", "-O0", "main.c", "-o", "main"] }');
    L.Add('] }');
    L.SaveToFile(IncludeTrailingPathDelimiter(LaunchDir) + 'tasks.json');
  finally
    L.Free;
  end;

  { Force a fresh read of the project, then check the label resolved. }
  F.Debugger.Project.LoadFrom(Src);
  CheckEq('the build command comes from tasks.json',
    'gcc -g -O0 main.c -o main',
    F.Debugger.Project.BuildCommandFor(F.Debugger.Project[0]));

  DeleteFile(Bin);
  Check('a missing binary is stale',
    LedBinaryIsStale(F.Debugger.Project.Root, Bin));

  Check('the build starts', F.BuildProjectNow(False));
  Waited := 0;
  while F.ToolRunning and (Waited < 20000) do
  begin
    Pump;
    Sleep(20);
    Inc(Waited, 20);
  end;
  Check('and it produced the binary', FileExists(Bin));
  Check('which is no longer stale',
    not LedBinaryIsStale(F.Debugger.Project.Root, Bin));

  Tab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  if DirectoryExists(Dir) then DeleteDirectory(Dir, False);
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
  Before, After: Integer;
  Outer: Integer;
  Span: Integer;

  { The column ACol if the line carries a guide there, otherwise 0. }
  function GuideCol(const ACols: array of Integer; ACol: Integer): Integer;
  var
    k: Integer;
  begin
    Result := 0;
    for k := 0 to High(ACols) do
      if ACols[k] = ACol then Exit(ACol);
  end;
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

  { Asked by column rather than by count.  A line carries one guide per block
    that encloses it, so the inner block's opener and closer still carry the
    *outer* block's guide -- what they must not carry is a guide for the
    block they themselves begin or end. }
  Opener := 0; Body := 0; Closer := 0; BodyCol := 0; Outer := 0;
  for i := 0 to High(Runs) do
  begin
    if Runs[i].TextIdx = 3 then Opener := GuideCol(Runs[i].Cols, 5);
    if Runs[i].TextIdx = 5 then Closer := GuideCol(Runs[i].Cols, 5);
    if Runs[i].TextIdx = 4 then
    begin
      Body := GuideCol(Runs[i].Cols, 5);
      BodyCol := GuideCol(Runs[i].Cols, 1);
    end;
    if Runs[i].TextIdx = 2 then Outer := GuideCol(Runs[i].Cols, 1);
  end;

  { The inner block runs from line 3 to line 5, so only line 4 is inside it. }
  CheckEqInt('the body of a block carries its guide', 5, Body);
  CheckEqInt('the line that opens it does not', 0, Opener);
  CheckEqInt('nor the line that closes it', 0, Closer);

  { The outer brace sits at column 1.  Those used to be skipped, on the
    grounds that the rule would run down the edge of the text -- but a
    function body flush against the margin is the commonest block there is,
    and leaving it unmarked looked like the guides stopped working. }
  CheckEqInt('a block flush to the left edge is guided too', 1, Outer);
  CheckEqInt('and a nested line carries both', 1, BodyCol);
  { Folding must not take the guides with it.  The guide for a line below a
    collapsed block still has to be drawn, and at the same column -- the
    complaint was that the rules broke up and then vanished after a fold. }
  Before := Length(V.ComputeBlockGuides(0, V.Lines.Count - 1));
  V.CaretY := 1;
  LedFoldAll(V);
  Pump;
  Check('folding everything changes what is on screen', V.FoldState <> '');
  After := Length(V.ComputeBlockGuides(0, V.Lines.Count - 1));
  CheckEqInt('the guides survive a fold', Before, After);
  LedUnfoldAll(V);
  Pump;
  CheckEqInt('and are unchanged after unfolding again', Before,
    Length(V.ComputeBlockGuides(0, V.Lines.Count - 1)));

  { The gutter draws chevrons and nothing else now.  A marker beside a line
    where no block starts was the other half of the complaint, and it came
    from reading SynEdit's block-selection classifications -- so selecting
    lines must not create one. }
  V.BlockBegin := Point(1, 2);
  V.BlockEnd := Point(1, 4);
  V.SelectionMode := smNormal;
  Pump;
  CheckEqInt('selecting lines adds no fold markers', Before,
    Length(V.ComputeBlockGuides(0, V.Lines.Count - 1)));
  V.SelText := V.SelText;      { leave the document as it was }

  { How big the chevron actually comes out.

    It is drawn at a fraction of its column, and the column is scaled with
    the display -- so at 3.125x the old figure gave a chevron forty-nine
    pixels across, which is a button, not a hint.  Measured off the painted
    view rather than computed, because what matters is the ink: nothing else
    is drawn in that column, so the widest row of it is the chevron.

    Asserted as a proportion of the column, so it holds at every scale. }
  Span := ChevronSpan(V);
  Say(Format('  (fold column %d px, chevron %d px)',
    [V.Gutter.CodeFoldPart.Width, Span]));
  CheckGt('a chevron is painted at all', 0, Span);
  Check('and it no longer fills its column',
    Span <= (V.Gutter.CodeFoldPart.Width * 4) div 5);
  Check('while staying wide enough to read',
    Span >= (V.Gutter.CodeFoldPart.Width * 2) div 5);
end;

{ Three ways a row is drawn, all reported as too loud or too loose.

  The caret's row is marked with a rule above and below rather than a filled
  band; a click past the last character lands on the last character; and a
  selection stops where the text does instead of running out to the right
  edge of the view.

  Measured off the painted view, because every one of them is about ink. }
procedure TestRowStyling(F: TLedMainForm);
var
  Dir, Src: string;
  L: TStringList;
  Tab: TLedTab;
  V: TLedEdit;
  Ymid, Wide, Past: Integer;
begin
  Say('row styling');

  Dir := TempName('rowstyle');
  ForceDirectories(Dir);
  Src := IncludeTrailingPathDelimiter(Dir) + 'rows.txt';
  L := TStringList.Create;
  try
    L.Add('short');
    L.Add('a somewhat longer line of text to select across');
    L.Add('tiny');
    L.Add('another line so the caret has somewhere to be');
    L.SaveToFile(Src);
  finally
    L.Free;
  end;

  Tab := F.AddTab(F.Documents.OpenFile(Src));
  Pump;
  if Tab = nil then Exit;
  V := Tab.ActiveView;
  V.TopLine := 1;
  V.SelectionMode := smNormal;
  V.BlockBegin := Point(1, 1);
  V.BlockEnd := Point(1, 1);
  V.CaretXY := Point(1, 3);
  Pump;

  { --- the caret's row: two rules, not a band --- }
  Check('the row colour survived the move off SynEdit''s own fill',
    V.CurrentLineColour <> clNone);
  Check('and differs from the page, or there would be nothing to see',
    V.CurrentLineColour <> V.Color);

  { Which row the painter marked, rather than the ink it put down.  PaintTo
    into a bitmap reproduces LED's gutter drawing and not its text-area
    drawing -- a full-width fill in the text area comes back with two pixels
    of it -- so the rules themselves were checked on a real X server and what
    is asserted here is the decision behind them. }
  V.Repaint;
  Pump;
  CheckEqInt('the rules are drawn on the caret''s row', 2, V.CurrentLineRow);
  CheckEqInt('and SynEdit no longer fills it', clNone,
    V.LineHighlightColor.Background);

  { A selection is the thing to look at, so the row markers stand down. }
  V.BlockBegin := Point(1, 2);
  V.BlockEnd := Point(4, 2);
  V.Repaint;
  Pump;
  CheckEqInt('and stand down while something is selected', -1,
    V.CurrentLineRow);
  V.BlockBegin := Point(1, 1);
  V.BlockEnd := Point(1, 1);
  V.CaretXY := Point(1, 3);
  V.Repaint;
  Pump;
  CheckEqInt('coming back when it is cleared', 2, V.CurrentLineRow);

  { --- a click past the end of a line --- }
  V.CaretXY := Point(1, 1);
  Pump;
  TLedMousePoke.Press(V, [],
    V.Gutter.Width + 2 + 40 * V.CharWidth, V.LineHeight div 2);
  TLedMousePoke.Release(V, [],
    V.Gutter.Width + 2 + 40 * V.CharWidth, V.LineHeight div 2);
  Pump;
  CheckEqInt('clicking past the end of a line lands on its end',
    Length(V.Lines[0]) + 1, V.CaretX);
  { The same click as a real mouse makes it: a press, a pixel or two of
    movement, a release.  That is a drag as far as SynEdit is concerned, and
    with eoScrollPastEol it reaches out into the space past the line -- where
    it selects virtual spaces that are not in the buffer.  Nothing is drawn
    for them, since LED stopped shading past the line end, so what the user
    saw was a click that moved the caret and took the current-line rules away
    with it, replacing them with nothing. }
  TLedMousePoke.Press(V, [],
    V.Gutter.Width + 2 + 40 * V.CharWidth, V.LineHeight div 2);
  TLedMousePoke.Move(V, [ssLeft],
    V.Gutter.Width + 2 + 44 * V.CharWidth, V.LineHeight div 2);
  TLedMousePoke.Release(V, [],
    V.Gutter.Width + 2 + 44 * V.CharWidth, V.LineHeight div 2);
  Pump;
  V.Repaint;
  Pump;
  CheckEqInt('a drag past the end of a line ends at the line end',
    Length(V.Lines[0]) + 1, V.CaretX);
  Check('and selects nothing, rather than a run of virtual spaces',
    not V.SelAvail);
  CheckEqInt('so the row keeps its rules', 0, V.CurrentLineRow);

  { And if a selection out there is arrived at some other way -- the caret
    put past the line end by code, with eoScrollPastEol -- the rules are
    still drawn, because a selection of nothing is not a selection. }
  V.BlockBegin := Point(Length(V.Lines[0]) + 1, 1);
  V.BlockEnd := Point(Length(V.Lines[0]) + 20, 1);
  V.CaretXY := Point(Length(V.Lines[0]) + 20, 1);
  V.Repaint;
  Pump;
  CheckEqInt('a selection with no text in it leaves the rules alone', 0,
    V.CurrentLineRow);
  V.BlockBegin := Point(1, 1);
  V.BlockEnd := Point(1, 1);
  V.CaretXY := Point(1, 1);
  Pump;

  { A rectangle still reaches past it, which is what eoScrollPastEol is on
    for -- clamping every click would have taken that with it. }
  V.SelectionMode := smColumn;
  V.BlockBegin := Point(1, 1);
  V.BlockEnd := Point(30, 3);
  Pump;
  CheckEqInt('a column selection still reaches past a short line', 30,
    V.BlockEnd.X);
  V.SelectionMode := smNormal;
  V.BlockBegin := Point(1, 1);
  V.BlockEnd := Point(1, 1);
  Pump;

  { --- a selection stops where the text does --- }
  V.CaretXY := Point(1, 1);
  V.BlockBegin := Point(1, 1);
  V.BlockEnd := Point(5, 3);
  Pump;
  Ymid := V.LineHeight div 2;          { line 1, "short" }
  Wide := ScanlineCount(V, Ymid, V.SelectedColor.Background);
  Say(Format('  (selection on a 5-char line: %d px shaded, char %d px)',
    [Wide, V.CharWidth]));
  CheckGt('the selected text is shaded', 0, Wide);
  { Five characters and the newline after them; anything much past that is
    empty space the selection has no business colouring. }
  Past := (Length(V.Lines[0]) + 2) * V.CharWidth;
  Check('but the empty space beyond the line is not', Wide <= Past);

  V.BlockBegin := Point(1, 1);
  V.BlockEnd := Point(1, 1);
  Tab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  if DirectoryExists(Dir) then DeleteDirectory(Dir, False);
end;

{ An attribute by its stored name, or nil. }
function AttrNamed(AHighlighter: TSynCustomHighlighter;
  const AName: string): TSynHighlighterAttributes;
var
  i: Integer;
begin
  Result := nil;
  if AHighlighter = nil then Exit;
  for i := 0 to AHighlighter.AttrCount - 1 do
    if SameText(AHighlighter.Attribute[i].StoredName, AName) then
      Exit(AHighlighter.Attribute[i]);
end;

{ A folded block is tinted, and clicking a word lights up the others.

  Two markups that SynEdit provides and LED turns on: the first through
  OnSpecialLineMarkup, the second by giving the highlight-all-at-caret markup
  a colour, which is what wakes it. }
type
  { MouseDown and MouseUp are protected, and clicking is the thing to check. }
  TMapPoke = class(TLedMiniMap);

{ The mean brightness of one pixel column of a control. }
function ColumnLuma(AControl: TWinControl; AX: Integer): Integer;
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  y, Total, Rows: Integer;
  C: TFPColor;
begin
  Result := -1;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(AControl.Width, AControl.Height);
    AControl.PaintTo(Bmp.Canvas, 0, 0);
    Img := Bmp.CreateIntfImage;
    try
      if (AX < 0) or (AX >= Img.Width) or (Img.Height = 0) then Exit;
      Total := 0;
      Rows := 0;
      for y := 0 to Img.Height - 1 do
      begin
        C := Img.Colors[AX, y];
        Inc(Total, (C.Red div 257) * 299 div 1000 +
                   (C.Green div 257) * 587 div 1000 +
                   (C.Blue div 257) * 114 div 1000);
        Inc(Rows);
      end;
      if Rows > 0 then Result := Total div Rows;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

{ The minimap: the whole file too small to read, down the right of the view.

  What is checked is that it draws the file rather than a blank strip, that
  the strip follows the text down a file too long to fit in it, and that
  clicking in it scrolls the text.  Ink is counted rather than described: a
  minimap that paints its background and nothing else would satisfy every
  property assertion about it, and looks exactly like a broken one. }
procedure TestMiniMap(F: TLedMainForm);
var
  Dir, Src: string;
  L: TStringList;
  Tab: TLedTab;
  V: TLedEdit;
  Map: TLedMiniMap;
  i, Ink, Blank, Top0, Top1, MapTop0, MapTop1: Integer;
  ClickY, Wanted, ViewBefore: Integer;
  Shade0, ShadeN: Integer;
  T0: QWord;

  { Pixels in the strip that are neither its background nor the box wash --
    that is, bars drawn for the text. }
  function InkPixels: Integer;
  var
    Bmp: TBitmap;
    Img: TLazIntfImage;
    x, y: Integer;
    Bg: TFPColor;
  begin
    Result := 0;
    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(Map.Width, Map.Height);
      Map.PaintTo(Bmp.Canvas, 0, 0);
      Img := Bmp.CreateIntfImage;
      try
        if (Img.Width = 0) or (Img.Height = 0) then Exit;
        Bg := TColorToFPColor(ColorToRGB(Map.Color));
        for y := 0 to Img.Height - 1 do
          for x := 0 to Img.Width - 1 do
            if Img.Colors[x, y] <> Bg then Inc(Result);
      finally
        Img.Free;
      end;
    finally
      Bmp.Free;
    end;
  end;

begin
  Say('minimap');

  Dir := TempName('minimap');
  ForceDirectories(Dir);
  Src := IncludeTrailingPathDelimiter(Dir) + 'long.c';
  L := TStringList.Create;
  try
    { Long enough that it cannot fit in the strip, so the scrolling half of
      this is exercised rather than skipped, and in blocks, so the folding
      half is too. }
    for i := 1 to 60 do
    begin
      L.Add('int function_' + IntToStr(i) + '(int x)');
      L.Add('{');
      L.Add('    int variable_' + IntToStr(i) + ' = ' + IntToStr(i) + ';');
      L.Add('    int another_' + IntToStr(i) + ' = x;');
      L.Add('    if (x > 0) {');
      L.Add('        variable_' + IntToStr(i) + ' += another_' + IntToStr(i) + ';');
      L.Add('    }');
      L.Add('    return variable_' + IntToStr(i) + ';');
      L.Add('}');
      L.Add('');
    end;
    L.SaveToFile(Src);
  finally
    L.Free;
  end;

  Tab := F.AddTab(F.Documents.OpenFile(Src));
  Pump;
  if Tab = nil then Exit;
  V := Tab.ActiveView;
  Map := Tab.MiniMap;
  Check('a tab has a minimap', Map <> nil);
  if Map = nil then Exit;

  Check('and it is off until it is asked for', not Map.Visible);
  Blank := InkPixels;

  F.actToggleMiniMap.Execute;
  Pump; Pump;
  Check('the View menu turns it on', Map.Visible);
  Check('and it maps the view it is beside', Map.Editor = V);
  CheckGt('and it is a strip, not the whole pane', Map.Width, V.Width);
  CheckGt('and wide enough to show the shape of a line', 40, Map.Width);

  { How long a repaint of the strip takes.  It is repainted on every caret
    move, so a slow one would be felt as sluggish typing. }
  T0 := GetTickCount64;
  for i := 1 to 50 do
  begin
    Map.Invalidate;
    Map.Repaint;
  end;
  Say(Format('  (%d repaints of a %d-line strip in %d ms)',
    [50, Map.LinesShown, Integer(GetTickCount64 - T0)]));

  Ink := InkPixels;
  CheckGt('it draws the file rather than a blank strip: ' + IntToStr(Ink),
    Blank + 200, Ink);

  { Down a file too long for the strip, the strip travels with the text --
    otherwise the box would walk off the bottom of it and the map would be of
    a part of the file nobody is looking at. }
  CheckGt('the file is longer than the strip can hold', Map.LinesShown,
    V.Lines.Count);
  V.TopLine := 1;
  Pump;
  Top0 := V.TopLine;
  MapTop0 := Map.TopLine;
  V.TopLine := V.Lines.Count - V.LinesInWindow;
  Pump;
  Top1 := V.TopLine;
  MapTop1 := Map.TopLine;
  CheckGt('the text really moved', Top0, Top1);
  CheckGt('and the strip followed it down the file', MapTop0, MapTop1);
  CheckEqInt('from the very top when the text is at the top', 1, MapTop0);

  { And the other direction: a click in the strip scrolls the text to it.
    Through the control's own mouse handlers, which are protected -- the
    point is that a click does this, not that a method exists. }
  V.TopLine := 1;
  Pump;
  { The line aimed at, read before the click: the strip moves with the text,
    so afterwards the same pixel row is a different line -- which is how the
    first version of this check managed to fail while the code was right. }
  ClickY := (Map.Height * 3) div 4;
  Wanted := Map.LineAtY(ClickY);
  TMapPoke(Map).MouseDown(mbLeft, [], Map.Width div 2, ClickY);
  TMapPoke(Map).MouseUp(mbLeft, [], Map.Width div 2, ClickY);
  Pump;
  CheckGt('clicking low in the strip scrolls the text down', 1, V.TopLine);
  { Centred on what was clicked, not pinned to the top of the view: a click
    in a minimap means "show me this", and what is wanted is that line with
    its surroundings. }
  Check('and the line clicked is in the middle of the view: ' +
    IntToStr(Wanted) + ' vs ' + IntToStr(V.TopLine + V.LinesInWindow div 2),
    Abs(V.TopLine + V.LinesInWindow div 2 - Wanted) <= 2);

  { The shadow down the left edge: a gradient, not a rule.  Measured as the
    mean brightness of each of the first few columns -- it has to fall away
    from the strip's own colour as it approaches the page, and the column
    against the page has to differ from the strip at all. }
  Shade0 := ColumnLuma(Map, 0);
  ShadeN := ColumnLuma(Map, LedScale96(6) - 1);
  Say(Format('  (edge shadow: column 0 = %d, column %d = %d, strip = %d)',
    [Shade0, LedScale96(6) - 1, ShadeN, LedColourLuma(Map.Color)]));
  CheckGt('the edge shadow is darkest against the page',
    Abs(ShadeN - LedColourLuma(Map.Color)),
    Abs(Shade0 - LedColourLuma(Map.Color)));
  CheckGt('and fades out before the bars start', 0,
    Abs(Shade0 - LedColourLuma(Map.Color)));

  { A folded block is one line on screen, and the map has to agree.  SynEdit's
    TopLine counts screen lines, so a map that counted buffer lines scrolled
    to the wrong place the moment anything was folded -- and further wrong the
    more was folded, which is why dragging in it went nowhere near where it
    was pointed. }
  V.CaretXY := Point(1, 1);
  ViewBefore := Map.LinesShown;
  LedFoldAll(V);
  Pump;
  V.Repaint;
  Pump;
  CheckGt('folding hides lines from the view', V.ViewLineCount,
    V.Lines.Count);
  Check('and the map is of the view, not the buffer: ' +
    IntToStr(Map.LinesShown) + ' of ' + IntToStr(V.ViewLineCount),
    Map.LinesShown <= V.ViewLineCount);
  CheckGt('so the map got shorter too', Map.LinesShown, ViewBefore);

  ClickY := Map.Height div 2;
  Wanted := Map.LineAtY(ClickY);
  TMapPoke(Map).MouseDown(mbLeft, [], Map.Width div 2, ClickY);
  TMapPoke(Map).MouseUp(mbLeft, [], Map.Width div 2, ClickY);
  Pump;
  Check('and a drag still lands where it is pointed with a block folded: ' +
    IntToStr(Wanted) + ' vs ' + IntToStr(V.TopLine + V.LinesInWindow div 2),
    Abs(V.TopLine + V.LinesInWindow div 2 - Wanted) <= 2);

  F.actToggleMiniMap.Execute;
  Pump;
  Check('and the View menu turns it off again', not Map.Visible);

  Tab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  if DirectoryExists(Dir) then DeleteDirectory(Dir, False);
end;

procedure TestWordAndFoldMarkup(F: TLedMainForm);
var
  Dir, Src: string;
  L: TStringList;
  Tab: TLedTab;
  V: TLedEdit;
  MarginGap: Integer;
  DiagI, DiagJ: Integer;
  StrAttr, Attr: TSynHighlighterAttributes;
  KateString, Behind: TColor;
  Ratio, Worst: Double;
  WorstName: string;

  { Puts the caret where a click would and returns how many appearances the
    markup found.  The search is SynEdit's, driven by a timer that does not
    fire under ProcessMessages -- but calling its handler does the search,
    and a repaint afterwards establishes the range it searches over. }
  function MatchesAt(AX, AY: Integer): Integer;
  begin
    V.CaretXY := Point(AX, AY);
    Pump;
    TLedMarkupPeek.SearchNow(V.HighlightWord);
    V.Repaint;
    Pump;
    Result := TLedMarkupPeek.Count(V.HighlightWord);
  end;

begin
  Say('word and fold markup');

  Dir := TempName('markup');
  ForceDirectories(Dir);
  Src := IncludeTrailingPathDelimiter(Dir) + 'demo.c';
  L := TStringList.Create;
  try
    L.Add('int count = 0;');             { 1 }
    L.Add('int twice(int n)');           { 2 }
    L.Add('{');                          { 3 }
    L.Add('    int count = n;');         { 4 }
    L.Add('    count = count * 2;');     { 5 }
    L.Add('    return count;');          { 6 }
    L.Add('}');                          { 7 }
    L.Add('/* count in a comment */');   { 8 }
    L.Add('char *s = "count here";');    { 9 }
    L.Add('int snake_case_2 = 0;');      { 10 }
    L.Add('int b = snake_case_2;');      { 11 }
    L.SaveToFile(Src);
  finally
    L.Free;
  end;

  Tab := F.AddTab(F.Documents.OpenFile(Src));
  Pump;
  if Tab = nil then Exit;
  V := Tab.ActiveView;
  V.TopLine := 1;
  Pump;

  { --- every appearance of the word at the caret --- }
  { On the markup that follows the caret, not on TSynEdit.HighlightAllColor.
    That published property is the *search* markup's, so the first version of
    this asserted a colour on an object the feature never consults -- and
    passed, while clicking a word did nothing.  Read it back off the markup
    LED actually configures. }
  { --- and it stands down for a selection of several rows --- }

  { With a selection, SynEdit's markup searches for the selected text rather
    than for the word at the caret.  Over one line that is what a
    double-click is for.  Over several the selection matches itself, so the
    search-match colour was painted over every selected row -- oblivion's
    green filling the page behind the selection. }
  V.BlockBegin := Point(1, 4);
  V.BlockEnd := Point(5, 6);
  Pump;
  Check('a selection of several rows silences the appearance highlight',
    not TLedMarkupPeek.Live(V.HighlightWord));

  V.BlockBegin := Point(5, 5);
  V.BlockEnd := Point(10, 5);
  Pump;
  Check('but a selection on one line still lights up its other appearances',
    TLedMarkupPeek.Live(V.HighlightWord));

  V.BlockBegin := Point(1, 1);
  V.BlockEnd := Point(1, 1);
  Pump;
  Check('and it comes back when the selection goes',
    TLedMarkupPeek.Live(V.HighlightWord));

  { --- switching themes has to undo the last one --- }

  { Applying a scheme colours the scopes that scheme mentions and leaves the
    rest alone, so what one scheme colours and the next does not stays as the
    first one left it.  Switching from kate to classic left strings red:
    kate colours def:string, classic says nothing about it, and nothing put
    it back.  SynEdit keeps each attribute's defaults privately and offers no
    way to read them, so LED keeps its own copy and restores from it first. }
  StrAttr := AttrNamed(V.Highlighter, 'def.string');
  Check('the C highlighter has a string attribute', StrAttr <> nil);
  if StrAttr <> nil then
  begin
    LedSetCurrentTheme('kate');
    LedRetheme(LedCurrentTheme);
    LedApplyThemeToEditor(LedCurrentTheme, V);
    KateString := StrAttr.Foreground;

    LedSetCurrentTheme('classic');
    LedRetheme(LedCurrentTheme);
    LedApplyThemeToEditor(LedCurrentTheme, V);
    Check('switching schemes does not leave the last one'#39's string colour: ' +
      Format('%.6x then %.6x', [ColorToRGB(KateString),
        ColorToRGB(StrAttr.Foreground)]),
      StrAttr.Foreground <> KateString);

    { And back again, to the same answer as the first time: restoring must be
      repeatable, not a one-way trip through the defaults. }
    LedSetCurrentTheme('kate');
    LedRetheme(LedCurrentTheme);
    LedApplyThemeToEditor(LedCurrentTheme, V);
    CheckEqInt('and going back gives the same colour again',
      KateString, StrAttr.Foreground);
  end;

  { --- every theme readable on its own page --- }

  { A grammar's colours were chosen for whatever page its author had in mind,
    and a scheme colours only the scopes it thinks about; what is left over
    is a colour nobody picked for this background.  Measured before the floor
    went in, on white: tango's strings at 1.5 to one, its keywords at 2.1,
    solarized-light's strings at 1.4 -- a mustard yellow on white. }
  Worst := 100;
  WorstName := '';
  for DiagI := 0 to LedThemes.Count - 1 do
  begin
    LedSetCurrentTheme(LedThemes[DiagI].Id);
    LedRetheme(LedCurrentTheme);
    LedApplyThemeToEditor(LedCurrentTheme, V);
    for DiagJ := 0 to V.Highlighter.AttrCount - 1 do
    begin
      Attr := V.Highlighter.Attribute[DiagJ];
      if (Attr = nil) or (Attr.Foreground = clNone) then Continue;
      Behind := Attr.Background;
      if Behind = clNone then Behind := V.Color;
      Ratio := LedContrastRatio(Attr.Foreground, Behind);
      if Ratio < Worst then
      begin
        Worst := Ratio;
        WorstName := LedThemes[DiagI].Id + '/' + Attr.StoredName;
      end;
    end;

    { The rules on the caret's row, which are drawn from the theme's
      current-line colour -- a tint meant to fill a whole row, and invisible
      in a one-pixel rule until it is pushed off the page. }
    CheckGt('the current-line rule can be seen in ' + LedThemes[DiagI].Id,
      25, Abs(LedColourLuma(LedThemeCurrentLineColour(LedCurrentTheme,
        V.Font.Color, V.Color)) - LedColourLuma(V.Color)));

    { And the word-appearance highlight has to be readable on its own
      background, whatever the scheme did or did not say about it: kate's
      search match is yellow with no foreground, so the word kept the
      selection's white and was drawn white on yellow. }
    if V.HighlightWord.MarkupInfo.Background <> clNone then
      CheckGt('the appearance highlight is readable in ' + LedThemes[DiagI].Id,
        40, Round(10 * LedContrastRatio(V.HighlightWord.MarkupInfo.Foreground,
          V.HighlightWord.MarkupInfo.Background)));
  end;
  Check(Format('no syntax colour is unreadable on its own page ' +
    '(worst: %s at %.1f to one)', [WorstName, Worst]), Worst >= 3.9);

  LedSetCurrentTheme('medit');
  LedRetheme(LedCurrentTheme);
  LedApplyThemeToEditor(LedCurrentTheme, V);

  Check('the caret markup has a colour, which is what wakes it',
    (V.HighlightWord <> nil) and
    (V.HighlightWord.MarkupInfo.Background <> clNone));
  Check('and it is not merely the search markup that was coloured',
    V.HighlightWord.MarkupInfo.Background <> clNone);
  Check('and LED configured it to whole words',
    (V.HighlightWord <> nil) and V.HighlightWord.FullWord);

  { What the suite can reach, and what it cannot.

    LED's part is turning the markup on: giving it a colour, which is what
    wakes it, and telling it to match whole words.  Both are asserted above.

    The search itself is SynEdit's, driven by a TTimer over the visible
    range.  A TTimer does not fire under Application.ProcessMessages, which
    is what drives this suite, and calling the handler by hand still finds
    nothing because the range is established by painting.  So the shading is
    confirmed by using the editor, not from here -- asserting a match count
    would mean asserting zero, which would pass whether it worked or not. }
  { Every appearance, wherever it is.  Seven of "count": five in code, one in
    a comment and one inside a string literal. }
  CheckEqInt('clicking a word finds every appearance of it', 7,
    MatchesAt(6, 5));
  Check('and they are shaded', TLedMarkupPeek.Paints(V.HighlightWord));

  { The caret at either end of a word, not only in the middle of one -- a
    click lands where the pointer was, and that is often the first character
    or the space after the last. }
  CheckEqInt('the caret at the start of a word counts as being in it', 6,
    MatchesAt(1, 2));
  CheckEqInt('and so does the caret just past its end', 6, MatchesAt(4, 2));

  { Whole words, so clicking "count" leaves "counter" alone.  Nothing here is
    called counter; what this asserts is that the option survived, since
    without it the count above would be the same. }
  Check('whole words only', V.HighlightWord.FullWord);

  { Underscores and digits are part of an identifier, not breaks in it.  A
    word-boundary rule that disagreed would report the two halves of
    snake_case_2 separately and shade the wrong span. }
  CheckEqInt('an identifier with underscores and digits is one word', 2,
    MatchesAt(9, 10));

  { A word that appears once is shaded too.  SynEdit hides a lone match by
    default, which from the outside is a click that answers for some words
    and not others -- and that is what it looked like: clicking count lit up
    the file and clicking twice, three lines above it, did nothing at all. }
  CheckEqInt('a word that appears once is still found', 1, MatchesAt(6, 2));
  Check('and it is still shaded, so the click is never ignored',
    TLedMarkupPeek.Paints(V.HighlightWord));

  V.CaretXY := Point(6, 5);
  Pump;
  TLedMarkupPeek.SearchNow(V.HighlightWord);
  { Hovering with no debugger running says nothing at all.  It used to answer
    every word in an ordinary editing session with

      count = (not stopped)

    which reads as a complaint about the word rather than as the debugger
    declining to answer. }
  Check('no debug session is running here', not F.Debugger.Session.Alive);
  V.RequestHover('');
  V.RequestHover('count');
  Pump;
  CheckEq('so hovering a word leaves no tooltip', '', V.Hint);
  Check('and the hint is switched off', not V.ShowHint);

  { --- a folded block is tinted --- }
  { The right margin is a note about a limit, not a rule through the page.
    Drawn in the style's own colour it was the brightest thing in the window
    on oblivion, whose right-margin foreground is very nearly white. }
  Check('the right margin has a colour', V.RightEdgeColor <> clNone);
  { Visible, but a note rather than a rule: far enough from the page to be
    seen and not so far as to compete with the code.  Both halves matter --
    the first mix had none at all on a scheme whose margin colour is close to
    its page, and the margin vanished. }
  MarginGap := Abs(LedColourLuma(V.RightEdgeColor) - LedColourLuma(V.Color));
  CheckGt('the margin can be seen against the page', 10, MarginGap);
  Check('but is softer than the text on it: ' + IntToStr(MarginGap),
    MarginGap < Abs(LedColourLuma(V.Font.Color) - LedColourLuma(V.Color)));

  { The preview sets code in the editor's own face rather than IPro's
    'Courier New', which no Linux desktop has. }
  if F.Preview <> nil then
    CheckEq('the preview sets code in the editor''s font',
      V.Font.Name, F.Preview.FixedFace);

  Check('the theme gave a fold tint', V.FoldedLineColour <> clNone);
  Check('and it differs from the page', V.FoldedLineColour <> V.Color);

  Check('nothing is folded to begin with', not V.LineIsFolded(3));
  LedFoldAll(V);
  Pump;
  Check('folding the block marks the line that carries it',
    V.LineIsFolded(3));
  Check('and not a line that carries nothing', not V.LineIsFolded(1));
  LedUnfoldAll(V);
  Pump;
  Check('unfolding takes the tint away again', not V.LineIsFolded(3));

  Tab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  if DirectoryExists(Dir) then DeleteDirectory(Dir, False);
end;

{ A byte is two cells: one in the hex half, one in the text half.

  Putting the caret on either lights both -- the side being typed into
  strongly, its counterpart faintly -- so the eye can cross the row without
  counting.  The same for a selection.  Asked of the markup rather than read
  off the screen, because what is being checked is the pairing: which cells
  light, and which of the pair is the brighter. }
procedure TestHexPairing(F: TLedMainForm);
var
  Dir, Bin: string;
  St: TFileStream;
  B: array[0..31] of Byte;
  i: Integer;
  Tab: TLedTab;
  V: TLedEdit;
  M: TLedHexMarkup;
  HexCol, TxtCol, Active, Mirror: Integer;
begin
  Say('hex pairing');

  Dir := TempName('hexpair');
  ForceDirectories(Dir);
  Bin := IncludeTrailingPathDelimiter(Dir) + 'data.bin';
  for i := 0 to High(B) do B[i] := i;
  B[3] := 0;                      { a NUL, so LED reads it as binary }
  St := TFileStream.Create(Bin, fmCreate);
  try
    St.WriteBuffer(B, SizeOf(B));
  finally
    St.Free;
  end;

  Tab := F.AddTab(F.Documents.OpenFile(Bin));
  Pump;
  if Tab = nil then Exit;
  V := Tab.ActiveView;
  Check('it opened as a dump', V.HexMode);
  M := V.HexMarkup;
  Check('and the dump has its markup', M <> nil);
  if M = nil then Exit;

  { Byte 5 of row 1, from the hex side. }
  HexCol := LedHexByteColumn(5);
  TxtCol := LedHexTextColumn(5);
  V.CaretXY := Point(HexCol, 1);
  Pump;

  { --- and the two things a dump has no use for --- }

  { The appearance highlight follows the caret and lights up every other
    place the same word appears.  A dump has no words: clicking one byte pair
    lit up every other place those two glyphs happened to fall, which in a
    wall of hexadecimal is most of the screen and means nothing -- 3A in one
    row and 3A in another are two different bytes at two different offsets. }
  Check('a dump does not light up repeated byte pairs',
    not TLedMarkupPeek.Live(V.HighlightWord));

  { And the minimap is a picture of a file's shape, which a dump does not
    have: every row is an address, sixteen cells and sixteen characters, so
    the map of one is a solid rectangle down the side of the window. }
  F.SetMiniMaps(True);
  Pump;
  Check('the minimap is asked for', LedPrefs.GetBool(LedPrefMiniMap, False));
  Check('and still not shown over a dump',
    (Tab.MiniMap = nil) or (not Tab.MiniMap.Visible));

  { It comes back for text, which is what says the rule is about dumps and
    not about the map having been switched off. }
  Tab.Document.OpenAsText;
  Tab.RefreshMiniMap;
  Pump;
  Check('the same document as text gets one',
    (Tab.MiniMap <> nil) and Tab.MiniMap.Visible);
  Check('and its words light up again',
    TLedMarkupPeek.Live(V.HighlightWord));
  F.SetMiniMaps(False);
  Pump;

  { Back to the dump for the pairing checks below. }
  Tab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  Tab := F.AddTab(F.Documents.OpenFile(Bin));
  Pump;
  if Tab = nil then Exit;
  V := Tab.ActiveView;
  M := V.HexMarkup;
  if M = nil then Exit;
  V.CaretXY := Point(HexCol, 1);
  Pump;

  Active := ColorToRGB(M.BackgroundAt(1, HexCol));
  Mirror := ColorToRGB(M.BackgroundAt(1, TxtCol));
  Check('the byte under the caret is shaded', M.BackgroundAt(1, HexCol) <> clNone);
  Check('and so is the same byte in the text column',
    M.BackgroundAt(1, TxtCol) <> clNone);
  Check('the two differ, so which side has the caret is visible',
    Active <> Mirror);
  Check('a byte the caret is not on stays unshaded',
    M.BackgroundAt(1, LedHexByteColumn(9)) = clNone);

  { Now from the text side: the same pair, the strengths swapped. }
  V.CaretXY := Point(TxtCol, 1);
  Pump;
  CheckEqInt('crossing to the text side makes that cell the bright one',
    Active, ColorToRGB(M.BackgroundAt(1, TxtCol)));
  CheckEqInt('and the hex cell the faint one',
    Mirror, ColorToRGB(M.BackgroundAt(1, HexCol)));

  { A selection lights every byte in it, on both sides. }
  V.CaretXY := Point(LedHexByteColumn(2), 1);
  V.BlockBegin := Point(LedHexByteColumn(2), 1);
  V.BlockEnd := Point(LedHexByteColumn(6), 1);
  Pump;
  Check('a selected byte is shaded in the hex half',
    M.BackgroundAt(1, LedHexByteColumn(4)) <> clNone);
  Check('and in the text half',
    M.BackgroundAt(1, LedHexTextColumn(4)) <> clNone);
  Check('while a byte outside it is not',
    M.BackgroundAt(1, LedHexByteColumn(12)) = clNone);

  V.BlockBegin := Point(1, 1);
  V.BlockEnd := Point(1, 1);
  Tab.Document.Master.Modified := False;
  F.CloseActiveTab(False);
  Pump;
  if DirectoryExists(Dir) then DeleteDirectory(Dir, False);
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
  part LED owns -- that a dropped path opens, through the same route as the
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
  exist.  Found by taking a screenshot of LED under Xvfb, which is a poor
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

  { A file named on the command line has to be configured like any other.
    Photographing a 6000-character line with max_line_len=60 showed it
    untruncated, which the bench -- which opens through OpenFiles after
    startup -- did not reproduce, so the suspicion was this path. }
  if F.ActiveTab <> nil then
    CheckEqInt('and the long-line limit was applied to it',
      LedPrefs.GetInt('Editor/max_line_len', -1),
      F.ActiveTab.ActiveView.LongLines.Limit);

  DeleteFile(Path);
end;

{ Turns an unhandled exception into a failed check and stops, rather than
  letting the LCL put up a dialog no one is there to close.

  An instance method, because Application.OnException is "of object". }
type
  TSelfTestExceptionSink = class
    procedure Handle(Sender: TObject; E: Exception);
  end;

var
  ExceptionSink: TSelfTestExceptionSink = nil;

procedure TSelfTestExceptionSink.Handle(Sender: TObject; E: Exception);
begin
  WriteLn;
  WriteLn('  FAIL  unhandled ' + E.ClassName + ': ' + E.Message);
  WriteLn;
  WriteLn(Format('%d checks, %d failures', [Checks, Failures + 1]));
  Flush(Output);
  Halt(1);
end;

procedure LedPrepareSelfTestSandbox;
var
  Sandbox: string;
begin
  FSandboxDir := GetEnvironmentVariable(LedConfigDirEnv);
  if FSandboxDir <> '' then
    FSandboxDir := IncludeTrailingPathDelimiter(FSandboxDir);
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
    FSandboxDir := IncludeTrailingPathDelimiter(Sandbox);
  end;
end;

function LedRunSelfTest: Integer;
var
  F: TLedMainForm;
  Sandbox: string;
begin
  { The sandbox is set up by LedPrepareSelfTestSandbox before the main form
    exists.  Doing it here was too late and silently useless: constructing
    the form reads a preference, TLedPrefs resolves its file name once in
    its constructor, and so the singleton stayed bound to the real
    prefs.ini.  Every run then wrote its scratch filter rule into the
    developer's own configuration -- one machine had accumulated a hundred
    copies of globs:*.selftest, which showed up as a filters page full of
    repeated rows. }
  Check('the self-test is not writing to your own configuration',
    (FSandboxDir <> '') and (Pos(FSandboxDir, LedPrefs.FileName) = 1));

  { An unhandled exception must fail the run, not stop it.

    Removing one nil check and re-running proved why: the suite reached the
    line that dereferenced it and hung there, because the LCL default handler
    puts up a modal dialog and under xvfb nobody dismisses it.  A hung run
    burns its whole CI timeout and reports nothing; a failed one names the
    check it died in. }
  if ExceptionSink = nil then ExceptionSink := TSelfTestExceptionSink.Create;
  Application.OnException := @ExceptionSink.Handle;

  Say('LED self-test');
  WriteLn;

  F := LedMainForm;
  { No modal dialog may ever appear during a scripted run: it would block the
    harness and, worse, land on the screen of whoever happens to be logged in. }
  F.Silent := True;
  F.Show;
  Pump;

  { First, before anything else has had a chance to open a tab or move a
    caret: this section is about the state LED actually starts in. }
  TestStartupDocument(F);
  TestBinaryFiles(F);
  TestBJDataFiles(F);
  TestBJDataFolding(F);
  TestBJDataEditing(F);
  TestNotebookEditing(F);
  TestNotebookColouring(F);
  TestNotebookRunning(F);
  TestNotebookBounds(F);
  TestNotebookPane(F);
  TestBJDataGuides(F);
  TestBJDataSearch(F);
  WriteLn;

  TestLineEndDetection;
  WriteLn;
  TestSharedBufferSplitView(F);
  WriteLn;
  TestIconsAndFocus(F);
  TestXErrorSurvival(F);
  TestTerminalPaneAndSession(F);
  TestBrowserNavigation(F);
  TestTabReordering(F);
  TestSaveTheRightDocument(F);
  TestRememberedState(F);
  TestBookmarkList(F);
  TestSharedDocuments(F);
  TestProjectList(F);
  TestSpelling(F);
  TestMeditTrim(F);
  TestBundledFont(F);
  TestUntitledNumbering(F);
  TestBinarySurvivesFailedDecode(F);
  TestShowPaneShowsThatPane(F);
  TestDockEdges(F);
  TestPaneSizes(F);
  TestPaneSizeMemory(F);
  WriteLn;
  TestTabsAndFileRoundTrip(F);
  WriteLn;
  TestDocumentBehaviour(F);
  WriteLn;
  TestRecentFiles(F);
  WriteLn;
  TestClipboardUnderGrab(F);
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
  TestRowStyling(F);
  TestWordAndFoldMarkup(F);
  TestMiniMap(F);
  TestHexPairing(F);
  TestLongLines(F);
  TestWikiMarkup(F);
  TestPreviewLineMapping(F);
  TestPreviewClickKeepsPage(F);
  TestColumnPasteWithHighlighter(F);
  TestColumnPasteAcrossTabs(F);
  TestRecoveryJournalPass(F);
  TestDebugger(F);
  TestReportedPolish(F);
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
  TestSpeedButtonHover(F);
  WriteLn;
  TestFileBrowser(F);
  WriteLn;
  TestTerminal(F);
  WriteLn;
  TestCompletionAndSymbols(F);
  TestSymbolsFollowTheDocument(F);
  WriteLn;
  TestFolding(F);
  WriteLn;
  TestWindowPlacement(F);
  TestWordWrapToggling(F);
  TestMenusAndDetection(F);
  WriteLn;

  WriteLn(Format('%d checks, %d failures', [Checks, Failures]));
  if Failures = 0 then
    Result := 0
  else
    Result := 1;
end;

end.
