{ led - a light editor.  Main window.

  Menus, the toolbar and the action list live in led.ui.main.lfm and are meant
  to be edited in the Lazarus form designer.  This unit holds only behaviour:
  action handlers, action enabling, and the wiring between the document model,
  the centre notebook and the dock host. }
unit Led.UI.Main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Dialogs, Menus, ActnList, ComCtrls,
  ExtCtrls, Math, SynEdit, SynEditTypes,
  SynEditKeyCmds, LConvEncoding,
  Led.Core.Types, Led.Core.CLI, Led.Core.Instance, Led.Core.FileIO, Led.Core.Prefs, Led.Core.Session,
  Led.Core.Config, Led.Core.Encodings, Led.Core.Paths,
  Led.Syn.Languages, Led.Syn.Theme, Led.Syn.Factory,
  Led.UI.Dock, Led.UI.Document, Led.UI.Tab, Led.UI.Edit, Led.UI.Commands,
  Led.UI.Find, Led.UI.Prefs, Led.UI.Shortcuts, Led.UI.Output,
  Led.UI.ToolRunner, Led.Core.Tools, Led.UI.Grep, Led.UI.FileBrowser,
  Led.Term.View, Led.Term.Pty, Led.UI.Symbols, Led.UI.Preview,
  Led.UI.Print;

type
  TLedMainForm = class(TForm)
    ActionList1: TActionList;
    actNew: TAction;
    actOpen: TAction;
    actSave: TAction;
    actSaveAs: TAction;
    actReload: TAction;
    actCloseTab: TAction;
    actPrint: TAction;
    actPreferences: TAction;
    actShortcuts: TAction;
    actQuit: TAction;
    actUndo: TAction;
    actRedo: TAction;
    actCut: TAction;
    actCopy: TAction;
    actPaste: TAction;
    actSelectAll: TAction;
    actPasteColumn: TAction;
    actClearSelection: TAction;
    actIndent: TAction;
    actUnindent: TAction;
    actIndentSpace: TAction;
    actUnindentSpace: TAction;
    actComment: TAction;
    actUncomment: TAction;
    actFind: TAction;
    actReplace: TAction;
    actFindNext: TAction;
    actFindPrev: TAction;
    actQuickFind: TAction;
    actFindInFiles: TAction;
    actGotoLine: TAction;
    actToggleBracket: TAction;
    actSelectToBracket: TAction;
    actToggleBookmark: TAction;
    actNextBookmark: TAction;
    actPrevBookmark: TAction;
    actSplitSideBySide: TAction;
    actSplitStacked: TAction;
    actUnsplit: TAction;
    actCycleViews: TAction;
    actToggleFold: TAction;
    actFoldAll: TAction;
    actUnfoldAll: TAction;
    actWrapText: TAction;
    actLineNumbers: TAction;
    actStopTool: TAction;
    actToggleOutput: TAction;
    actToggleTerminal: TAction;
    actToggleSymbols: TAction;
    actTogglePreview: TAction;
    actComplete: TAction;
    actToggleLeftPane: TAction;
    actToggleBottomPane: TAction;
    MainMenu1: TMainMenu;
    mnuFile: TMenuItem;
    mi_New: TMenuItem;
    mi_Open: TMenuItem;
    miOpenRecent: TMenuItem;
    mi_Reload: TMenuItem;
    miSep1: TMenuItem;
    mi_Save: TMenuItem;
    mi_SaveAs: TMenuItem;
    miSep2: TMenuItem;
    mi_Print: TMenuItem;
    miSep3: TMenuItem;
    mi_CloseTab: TMenuItem;
    mi_Quit: TMenuItem;
    mnuEdit: TMenuItem;
    mi_Undo: TMenuItem;
    mi_Redo: TMenuItem;
    miSep4: TMenuItem;
    mi_Cut: TMenuItem;
    mi_Copy: TMenuItem;
    mi_Paste: TMenuItem;
    miSep5: TMenuItem;
    mi_SelectAll: TMenuItem;
    mi_PasteColumn: TMenuItem;
    mi_ClearSelection: TMenuItem;
    miSep6: TMenuItem;
    mi_Indent: TMenuItem;
    mi_Unindent: TMenuItem;
    mi_IndentSpace: TMenuItem;
    mi_UnindentSpace: TMenuItem;
    miSep7: TMenuItem;
    mi_Comment: TMenuItem;
    mi_Uncomment: TMenuItem;
    mi_Complete: TMenuItem;
    miSep8: TMenuItem;
    mi_Shortcuts: TMenuItem;
    mi_Preferences: TMenuItem;
    mnuSearch: TMenuItem;
    mi_Find: TMenuItem;
    mi_Replace: TMenuItem;
    mi_FindNext: TMenuItem;
    mi_FindPrev: TMenuItem;
    mi_QuickFind: TMenuItem;
    mi_FindInFiles: TMenuItem;
    miSep9: TMenuItem;
    mi_GotoLine: TMenuItem;
    miSep10: TMenuItem;
    mi_ToggleBracket: TMenuItem;
    mi_SelectToBracket: TMenuItem;
    mnuDocument: TMenuItem;
    miLanguage: TMenuItem;
    miEncoding: TMenuItem;
    miLineEnd: TMenuItem;
    miSep11: TMenuItem;
    mi_ToggleBookmark: TMenuItem;
    mi_NextBookmark: TMenuItem;
    mi_PrevBookmark: TMenuItem;
    mnuTools: TMenuItem;
    miToolList: TMenuItem;
    miSep12: TMenuItem;
    mi_StopTool: TMenuItem;
    mnuView: TMenuItem;
    mi_WrapText: TMenuItem;
    mi_LineNumbers: TMenuItem;
    miSep13: TMenuItem;
    mi_ToggleFold: TMenuItem;
    mi_FoldAll: TMenuItem;
    mi_UnfoldAll: TMenuItem;
    miSep14: TMenuItem;
    mi_SplitSideBySide: TMenuItem;
    mi_SplitStacked: TMenuItem;
    mi_Unsplit: TMenuItem;
    mi_CycleViews: TMenuItem;
    miSep15: TMenuItem;
    miTheme: TMenuItem;
    miSep16: TMenuItem;
    mi_ToggleLeftPane: TMenuItem;
    mi_ToggleBottomPane: TMenuItem;
    mi_ToggleOutput: TMenuItem;
    mi_ToggleTerminal: TMenuItem;
    mi_ToggleSymbols: TMenuItem;
    mi_TogglePreview: TMenuItem;
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    StatusBar1: TStatusBar;
    procedure ActionList1Update(AAction: TBasicAction; var Handled: Boolean);
    procedure actCloseTabExecute(Sender: TObject);
    procedure actCycleViewsExecute(Sender: TObject);
    procedure actNewExecute(Sender: TObject);
    procedure actOpenExecute(Sender: TObject);
    procedure actQuitExecute(Sender: TObject);
    procedure actSaveAsExecute(Sender: TObject);
    procedure actSaveExecute(Sender: TObject);
    procedure actSplitSideBySideExecute(Sender: TObject);
    procedure actSplitStackedExecute(Sender: TObject);
    procedure actToggleBottomPaneExecute(Sender: TObject);
    procedure actToggleLeftPaneExecute(Sender: TObject);
    procedure actUnsplitExecute(Sender: TObject);
    procedure actReloadExecute(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure miOpenRecentClick(Sender: TObject);
    procedure miLanguageClick(Sender: TObject);
    procedure miThemeClick(Sender: TObject);
    procedure actCommentExecute(Sender: TObject);
    procedure actCopyExecute(Sender: TObject);
    procedure actCutExecute(Sender: TObject);
    procedure actGotoLineExecute(Sender: TObject);
    procedure actIndentExecute(Sender: TObject);
    procedure actIndentSpaceExecute(Sender: TObject);
    procedure actLineNumbersExecute(Sender: TObject);
    procedure actNextBookmarkExecute(Sender: TObject);
    procedure actPasteExecute(Sender: TObject);
    procedure actPrevBookmarkExecute(Sender: TObject);
    procedure actRedoExecute(Sender: TObject);
    procedure actSelectAllExecute(Sender: TObject);
    procedure actSelectToBracketExecute(Sender: TObject);
    procedure actToggleBookmarkExecute(Sender: TObject);
    procedure actToggleBracketExecute(Sender: TObject);
    procedure actUncommentExecute(Sender: TObject);
    procedure actUndoExecute(Sender: TObject);
    procedure actUnindentExecute(Sender: TObject);
    procedure actUnindentSpaceExecute(Sender: TObject);
    procedure actWrapTextExecute(Sender: TObject);
    procedure miEncodingClick(Sender: TObject);
    procedure miLineEndClick(Sender: TObject);
    procedure actFindExecute(Sender: TObject);
    procedure actFindNextExecute(Sender: TObject);
    procedure actFindPrevExecute(Sender: TObject);
    procedure actQuickFindExecute(Sender: TObject);
    procedure actReplaceExecute(Sender: TObject);
    procedure actClearSelectionExecute(Sender: TObject);
    procedure actPasteColumnExecute(Sender: TObject);
    procedure actFoldAllExecute(Sender: TObject);
    procedure actToggleFoldExecute(Sender: TObject);
    procedure actUnfoldAllExecute(Sender: TObject);
    procedure actPreferencesExecute(Sender: TObject);
    procedure actShortcutsExecute(Sender: TObject);
    procedure actStopToolExecute(Sender: TObject);
    procedure actToggleOutputExecute(Sender: TObject);
    procedure miToolListClick(Sender: TObject);
    procedure actFindInFilesExecute(Sender: TObject);
    procedure actToggleTerminalExecute(Sender: TObject);
    procedure actCompleteExecute(Sender: TObject);
    procedure actToggleSymbolsExecute(Sender: TObject);
    procedure actPrintExecute(Sender: TObject);
    procedure actTogglePreviewExecute(Sender: TObject);
  private
    FDocs: TLedDocuments;
    FDock: TLedDockHost;
    FBook: TPageControl;
    FRecent: TLedRecentFiles;
    FSearch: TLedSearchState;
    FInstance: TLedInstance;
    FInstanceTimer: TTimer;
    FFindForm: TLedFindForm;
    FFindBar: TLedFindBar;
    FShortcuts: TLedShortcuts;
    FTools: TLedTools;
    FRunner: TLedToolRunner;
    FOutput: TLedOutputPane;
    FGrepDialog: TLedGrepDialog;
    FBrowser: TLedFileBrowser;
    FTerminal: TLedTermView;
    FSymbols: TLedSymbolPane;
    FPreview: TLedPreviewPane;
    FCheckingDisk: Boolean;
    procedure RefreshPreview;
    procedure SymbolJump(ALine: Integer);
    procedure BrowserOpenFile(const AFileName: string);
    procedure GrepStarted;
    procedure PopulateToolMenu;
    procedure ToolItemClick(Sender: TObject);
    procedure OutputJump(const AFileName: string; ALine, AColumn: Integer);
    procedure PrefsApplied(Sender: TObject);
    procedure InstancePoll(Sender: TObject);
    procedure InstanceOpenRequest(const APayload: string);
    function SearchView: TLedEdit;
    function FindTabFor(ADoc: TLedDocument): TLedTab;
    { Every dynamic submenu is filled in advance rather than on the parent's
      OnClick.  A TMenuItem with no children is a leaf: on GTK it never opens
      a submenu, so the handler that was supposed to fill it never ran and
      the menu was permanently empty. }
    procedure PopulateAllMenus;
    procedure PopulateRecentMenu;
    procedure RecentItemClick(Sender: TObject);
    procedure PopulateLanguageMenu;
    procedure LanguageItemClick(Sender: TObject);
    procedure PopulateThemeMenu;
    procedure ThemeItemClick(Sender: TObject);
    procedure PopulateEncodingMenu;
    procedure EncodingItemClick(Sender: TObject);
    procedure PopulateLineEndMenu;
    procedure LineEndItemClick(Sender: TObject);
    procedure ViewMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure SaveSession;
    function RestoreSession: Boolean;
    procedure CheckExternalChanges;
    function CurrentView: TLedEdit;
    procedure GotoAdjacentBookmark(AForward: Boolean);
    procedure ShowFindForm(AReplace: Boolean);
    procedure BookChange(Sender: TObject);
    procedure DocChanged(ADoc: TLedDocument);
    procedure RefreshTabCaption(ATab: TLedTab);
    procedure UpdateStatusBar;
    procedure ViewStatusChange(Sender: TObject; AChanges: TSynStatusChanges);
    function ConfirmClose(ADoc: TLedDocument): Boolean;
  public
    { Every message the window shows goes through these two, so that
      --self-test and --script can run without a modal dialog stopping them
      dead.  In Silent mode a report goes to stdout and a question takes its
      stated default. }
    Silent: Boolean;
    { Answered instead of asking, when Silent; '' means "give up". }
    SilentEncodingChoice: string;
    procedure ReportError(const AMessage: string);
    { Offers the user a list of encodings after a decode has failed.  Returns
      '' when they decline, which means the file is simply not opened. }
    function AskEncoding(const AFileName: string): string;
    function Confirm(const AMessage: string; ADefault: Boolean): Boolean;
    function ConfirmSaveDiscardCancel(const AMessage: string): Integer;

    procedure OpenFiles(AFiles: TStrings);

    { Public so the --self-test harness, and later the scripting API, can
      drive the window the same way a user would. }
    function ActiveTab: TLedTab;
    function ActiveView: TLedEdit;
    function AddTab(ADoc: TLedDocument): TLedTab;
    property Documents: TLedDocuments read FDocs;
    property Dock: TLedDockHost read FDock;
    property Notebook: TPageControl read FBook;
    property Recent: TLedRecentFiles read FRecent;
    property Browser: TLedFileBrowser read FBrowser;

    { Takes ownership of the single-instance server and starts listening for
      hand-offs from later invocations. }
    procedure AdoptInstance(AInstance: TLedInstance);
    procedure ApplyCommandLine(ACmd: TLedCommandLine; const ACwd: string);
  end;

var
  LedMainForm: TLedMainForm;

implementation

{$R *.lfm}

procedure TLedMainForm.ReportError(const AMessage: string);
begin
  if Silent then
    WriteLn(StdErr, 'led: ', AMessage)
  else
    MessageDlg('led', AMessage, mtError, [mbOK], 0);
end;

function TLedMainForm.Confirm(const AMessage: string; ADefault: Boolean): Boolean;
begin
  if Silent then
  begin
    WriteLn(StdErr, 'led: ', AMessage, ' -> ', BoolToStr(ADefault, 'yes', 'no'));
    Exit(ADefault);
  end;
  Result := MessageDlg('led', AMessage, mtConfirmation, [mbYes, mbNo], 0) = mrYes;
end;

function TLedMainForm.ConfirmSaveDiscardCancel(const AMessage: string): Integer;
begin
  if Silent then
  begin
    WriteLn(StdErr, 'led: ', AMessage, ' -> no');
    Exit(mrNo);
  end;
  Result := MessageDlg('led', AMessage, mtConfirmation,
    [mbYes, mbNo, mbCancel], 0);
end;

function TLedMainForm.AskEncoding(const AFileName: string): string;
var
  Names, Ids: TStringList;
  i, Chosen: Integer;
begin
  Result := '';
  if Silent then Exit(SilentEncodingChoice);

  Ids := TStringList.Create;
  Names := TStringList.Create;
  try
    GetSupportedEncodings(Ids);
    for i := 0 to Ids.Count - 1 do
      Names.Add(Ids[i]);
    Chosen := InputCombo('led',
      Format('%s could not be decoded.'#10 +
             'Which character encoding does it use?',
             [ExtractFileName(AFileName)]), Names);
    if Chosen >= 0 then
      Result := LedNormaliseEncoding(Ids[Chosen]);
  finally
    Names.Free;
    Ids.Free;
  end;
end;

procedure TLedMainForm.FormCreate(Sender: TObject);
begin
  FDocs := TLedDocuments.Create(Self);
  FRecent := TLedRecentFiles.Create;
  FRecent.Load;
  FSearch := TLedSearchState.Create;
  { Defaults are captured before keys.ini is read, so a customisation can be
    told from a default and Reset has something to go back to. }
  FShortcuts := TLedShortcuts.Create(ActionList1);
  FShortcuts.CaptureDefaults;
  FShortcuts.Load;

  FTools := TLedTools.Create;
  { Shipped tools first, then the user's, so a user tool with the same id
    replaces rather than duplicates the one that came with led. }
  FTools.LoadDirectory(LedConfigFile('tools'));
  FTools.LoadDirectory(LedDataFile('tools'));
  FRunner := TLedToolRunner.Create(Self);

  FDock := TLedDockHost.Create(Self);
  FDock.Parent := Self;
  FDock.Align := alClient;

  FBook := TPageControl.Create(Self);
  FBook.Parent := FDock.Center;
  FBook.Align := alClient;
  FBook.OnChange := @BookChange;

  { Phase 0 placeholders so the dock edges can be exercised; real panes arrive
    in phases 3 and 5. }
  FOutput := TLedOutputPane.Create(Self);
  FOutput.OnJump := @OutputJump;

  FBrowser := TLedFileBrowser.Create(Self);
  FBrowser.OnOpenFile := @BrowserOpenFile;

  FDock.AddPane(ledLeft, 'files', 'Files', FBrowser);

  FSymbols := TLedSymbolPane.Create(Self);
  FSymbols.OnJump := @SymbolJump;
  FDock.AddPane(ledRight, 'symbols', 'Symbols', FSymbols);
  FDock.EdgeVisible[ledRight] := False;
  FDock.AddPane(ledBottom, 'output', 'Output', FOutput);
  FDock.EdgeVisible[ledLeft] := False;
  FDock.EdgeVisible[ledBottom] := False;

  if not RestoreSession then
    actNewExecute(nil);

  PopulateAllMenus;
end;

procedure TLedMainForm.PopulateAllMenus;
begin
  PopulateRecentMenu;
  PopulateLanguageMenu;
  PopulateEncodingMenu;
  PopulateLineEndMenu;
  PopulateThemeMenu;
  PopulateToolMenu;
end;

procedure TLedMainForm.FormDestroy(Sender: TObject);
begin
  FRecent.Free;
  FSearch.Free;
  FShortcuts.Free;
  FTools.Free;
  FInstance.Free;
end;

{ --- user tools ------------------------------------------------------------ }

procedure TLedMainForm.miToolListClick(Sender: TObject);
begin
  PopulateToolMenu;
end;

procedure TLedMainForm.PopulateToolMenu;
var
  i, Shown: Integer;
  Item: TMenuItem;
  Tool: TLedTool;
  Doc: TLedDocument;
  LangId, FileName: string;
begin
  miToolList.Clear;
  Doc := nil;
  if ActiveTab <> nil then Doc := ActiveTab.Document;
  LangId := '';
  FileName := '';
  if Doc <> nil then
  begin
    LangId := Doc.Config.GetStr(LedSetLang);
    FileName := Doc.FileName;
  end;

  Shown := 0;
  for i := 0 to FTools.Count - 1 do
  begin
    Tool := FTools[i];
    if Tool.Place <> ltpMenu then Continue;
    { A tool that does not apply to this document is left out entirely rather
      than shown greyed: the Tools menu is long enough already. }
    if not Tool.AppliesTo(LangId, FileName) then Continue;

    Item := TMenuItem.Create(miToolList);
    Item.Caption := Tool.Name;
    Item.Hint := Tool.Id;
    Item.Enabled := LedToolCanRun(Tool, Doc) and not FRunner.Running;
    Item.OnClick := @ToolItemClick;
    miToolList.Add(Item);
    Inc(Shown);
  end;

  miToolList.Caption := 'Run';
  miToolList.Enabled := Shown > 0;
  if Shown = 0 then
    miToolList.Caption := 'Run  (no tools apply here)';
end;

procedure TLedMainForm.ToolItemClick(Sender: TObject);
var
  Tool: TLedTool;
  Doc: TLedDocument;
  i: Integer;
begin
  Tool := FTools.FindById(TMenuItem(Sender).Hint);
  if Tool = nil then Exit;
  if FRunner.Running then
  begin
    ReportError('Another tool is still running.');
    Exit;
  end;

  Doc := nil;
  if ActiveTab <> nil then Doc := ActiveTab.Document;

  { Saving first is part of the contract, so a build sees what is on screen. }
  if (ltoNeedSaveAll in Tool.Options) then
  begin
    for i := 0 to FDocs.Count - 1 do
      if FDocs[i].Modified and not FDocs[i].IsUntitled then
        FDocs[i].Save;
  end
  else if (ltoNeedSave in Tool.Options) and (Doc <> nil) and Doc.Modified then
  begin
    if Doc.IsUntitled then
      actSaveAsExecute(nil)
    else
      Doc.Save;
  end;

  if Tool.Kind <> ltkExe then
  begin
    ReportError(Format('"%s" is a %s tool; only shell tools run so far.',
      [Tool.Name, LedToolKindToString(Tool.Kind)]));
    Exit;
  end;

  if Tool.Output = ltoPane then
  begin
    FDock.ShowPane('output');
    FDock.EdgeVisible[ledBottom] := True;
  end;

  FRunner.Run(Tool, Doc, ActiveView, FOutput);
end;

procedure TLedMainForm.actStopToolExecute(Sender: TObject);
begin
  FRunner.Stop;
end;

procedure TLedMainForm.actToggleOutputExecute(Sender: TObject);
begin
  FDock.ShowPane('output');
  FDock.EdgeVisible[ledBottom] := True;
end;

procedure TLedMainForm.RefreshPreview;
var
  Doc: TLedDocument;
begin
  if (FPreview = nil) or not FDock.EdgeVisible[ledRight] then Exit;
  if ActiveTab = nil then Exit;
  Doc := ActiveTab.Document;
  if LedPreviewHandles(Doc.FileName) then
    FPreview.Update(Doc.Master.Lines.Text, Doc.DisplayName,
      ExtractFileDir(Doc.FileName))
  else
    FPreview.ShowMessage_('This is not a Markdown file.');
end;

procedure TLedMainForm.actTogglePreviewExecute(Sender: TObject);
begin
  if FPreview = nil then
  begin
    FPreview := TLedPreviewPane.Create(Self);
    FDock.AddPane(ledRight, 'preview', 'Preview', FPreview);
  end;
  FDock.ShowPane('preview');
  FDock.EdgeVisible[ledRight] := True;
  RefreshPreview;
end;

procedure TLedMainForm.actPrintExecute(Sender: TObject);
begin
  if Silent then Exit;
  if not LedPrinterAvailable then
  begin
    ReportError('No printer is configured.');
    Exit;
  end;
  if ActiveTab = nil then Exit;
  try
    LedPrintDocument(ActiveView, ActiveTab.Document.DisplayName);
  except
    on E: Exception do
      ReportError('Printing failed: ' + E.Message);
  end;
end;

procedure TLedMainForm.actToggleSymbolsExecute(Sender: TObject);
begin
  FDock.ToggleEdge(ledRight);
  if FDock.EdgeVisible[ledRight] and (ActiveTab <> nil) then
    FSymbols.Reload(ActiveTab.Document.FileName);
end;

procedure TLedMainForm.actCompleteExecute(Sender: TObject);
begin
  if ActiveView <> nil then
    ActiveView.Completion.Execute('', ActiveView.ClientToScreen(
      Point(ActiveView.CaretXPix, ActiveView.CaretYPix + ActiveView.LineHeight)));
end;

procedure TLedMainForm.actToggleTerminalExecute(Sender: TObject);
var
  Dir: string;
begin
  if not LedPtyAvailable then
  begin
    ReportError('A terminal needs a pseudo-terminal, which is not available '
      + 'on this platform yet.');
    Exit;
  end;

  if FTerminal = nil then
  begin
    FTerminal := TLedTermView.Create(Self);
    FDock.AddPane(ledBottom, 'terminal', 'Terminal', FTerminal);
  end;
  FDock.ShowPane('terminal');
  FDock.EdgeVisible[ledBottom] := True;

  { Started on first use, in the folder of the document in front of you,
    which is nearly always where you wanted to be. }
  if not FTerminal.Running then
  begin
    Dir := GetCurrentDir;
    if (ActiveTab <> nil) and not ActiveTab.Document.IsUntitled then
      Dir := ExtractFileDir(ActiveTab.Document.FileName);
    FTerminal.Start('', Dir);
  end;
  if FTerminal.CanFocus then FTerminal.SetFocus;
end;

procedure TLedMainForm.OutputJump(const AFileName: string;
  ALine, AColumn: Integer);
var
  L: TStringList;
  Tab: TLedTab;
  Doc: TLedDocument;
begin
  L := TStringList.Create;
  try
    L.Add(AFileName);
    OpenFiles(L);
  finally
    L.Free;
  end;
  Doc := FDocs.FindByFileName(AFileName);
  if Doc = nil then Exit;
  Tab := FindTabFor(Doc);
  if Tab = nil then Exit;
  FBook.ActivePage := Tab.Sheet;
  if ALine > 0 then
    LedGotoLine(Tab.ActiveView, ALine);
  if (AColumn > 0) and (Tab.ActiveView <> nil) then
    Tab.ActiveView.CaretX := AColumn;
  if Tab.ActiveView.CanFocus then Tab.ActiveView.SetFocus;
end;

{ --- preferences and shortcuts --------------------------------------------- }

procedure TLedMainForm.PrefsApplied(Sender: TObject);
var
  i, j: Integer;
begin
  { Preferences feed the user layer of every document's config, and the theme
    may have changed too, so both are rebuilt and pushed to every view. }
  LedReloadUserConfig;
  LedSetCurrentTheme(LedPrefs.GetStr(LedPrefColorScheme, 'medit'));
  for i := 0 to FBook.PageCount - 1 do
    for j := 0 to FBook.Pages[i].ControlCount - 1 do
      if FBook.Pages[i].Controls[j] is TLedTab then
        TLedTab(FBook.Pages[i].Controls[j]).Document.ApplyConfigToViews;
  UpdateStatusBar;
end;

procedure TLedMainForm.actPreferencesExecute(Sender: TObject);
var
  Dlg: TLedPrefsDialog;
begin
  if Silent then Exit;
  Dlg := TLedPrefsDialog.CreateDialog(Self);
  try
    Dlg.OnApplied := @PrefsApplied;
    Dlg.LoadFromPrefs;
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

procedure TLedMainForm.actShortcutsExecute(Sender: TObject);
var
  Dlg: TLedShortcutsForm;
begin
  if Silent then Exit;
  Dlg := TLedShortcutsForm.CreateFor(Self, FShortcuts);
  try
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

{ --- hand-off from a second invocation ------------------------------------- }

procedure TLedMainForm.AdoptInstance(AInstance: TLedInstance);
begin
  FInstance := AInstance;
  if FInstance = nil then Exit;
  FInstance.OnOpenRequest := @InstanceOpenRequest;
  if FInstance.Role = lirClient then Exit;

  { Polled rather than threaded: the payload has to be acted on from the main
    thread anyway, and a quarter-second delay opening a file is not felt. }
  FInstanceTimer := TTimer.Create(Self);
  FInstanceTimer.Interval := 250;
  FInstanceTimer.OnTimer := @InstancePoll;
  FInstanceTimer.Enabled := True;
end;

procedure TLedMainForm.InstancePoll(Sender: TObject);
begin
  if FInstance <> nil then FInstance.Poll;
end;

procedure TLedMainForm.InstanceOpenRequest(const APayload: string);
var
  Cmd: TLedCommandLine;
  Cwd: string;
begin
  Cmd := TLedCommandLine.Create;
  try
    Cmd.FromJSON(APayload, Cwd);
    ApplyCommandLine(Cmd, Cwd);
  finally
    Cmd.Free;
  end;

  { Bring the window forward.  Reliable on Windows and X11; on Wayland a
    client cannot raise itself, so the taskbar entry is all the user gets. }
  if WindowState = wsMinimized then WindowState := wsNormal;
  Show;
  BringToFront;
end;

procedure TLedMainForm.ApplyCommandLine(ACmd: TLedCommandLine;
  const ACwd: string);
var
  i: Integer;
  Arg: TLedFileArg;
  Path: string;
  Doc: TLedDocument;
  Tab: TLedTab;
begin
  for i := 0 to ACmd.FileCount - 1 do
  begin
    Arg := ACmd.Files[i];
    if Arg.Path = '' then Continue;
    { Relative paths belong to the directory the user typed them in, which
      for a hand-off is not this process's directory. }
    if ACwd <> '' then
      Path := ExpandFileName(IncludeTrailingPathDelimiter(ACwd) + Arg.Path)
    else
      Path := ExpandFileName(Arg.Path);

    Doc := FDocs.FindByFileName(Path);
    if (Doc <> nil) and ACmd.Reload then
      Doc.Reload;

    if Doc = nil then
    begin
      try
        Doc := FDocs.OpenFile(Path, Arg.Encoding);
      except
        on E: ELedFileError do
        begin
          ReportError(E.Message);
          Continue;
        end;
      end;
    end;

    if Doc.ViewCount = 0 then
      Tab := AddTab(Doc)
    else
      Tab := FindTabFor(Doc);
    FRecent.Add(Doc.FileName);

    if (Tab <> nil) and (Arg.Line > 0) then
    begin
      FBook.ActivePage := Tab.Sheet;
      LedGotoLine(Tab.ActiveView, Arg.Line);
    end;
  end;
  UpdateStatusBar;
end;

{ --- find and replace ------------------------------------------------------ }

function TLedMainForm.SearchView: TLedEdit;
begin
  Result := ActiveView;
end;

function TLedMainForm.FindTabFor(ADoc: TLedDocument): TLedTab;
var
  i, j: Integer;
begin
  for i := 0 to FBook.PageCount - 1 do
    for j := 0 to FBook.Pages[i].ControlCount - 1 do
      if (FBook.Pages[i].Controls[j] is TLedTab) and
         (TLedTab(FBook.Pages[i].Controls[j]).Document = ADoc) then
        Exit(TLedTab(FBook.Pages[i].Controls[j]));
  Result := nil;
end;

procedure TLedMainForm.ShowFindForm(AReplace: Boolean);
begin
  if Silent then Exit;
  if FFindForm = nil then
    FFindForm := TLedFindForm.CreateFor(Self, FSearch, @SearchView);
  FFindForm.ShowFor(AReplace);
end;

procedure TLedMainForm.actFindExecute(Sender: TObject);
begin
  ShowFindForm(False);
end;

procedure TLedMainForm.actReplaceExecute(Sender: TObject);
begin
  ShowFindForm(True);
end;

procedure TLedMainForm.actFindNextExecute(Sender: TObject);
begin
  { With nothing to search for yet, F3 opens the dialog rather than doing
    nothing at all. }
  if FSearch.SearchText = '' then
    ShowFindForm(False)
  else
    LedFindNext(SearchView, FSearch, False);
end;

procedure TLedMainForm.actFindPrevExecute(Sender: TObject);
begin
  if FSearch.SearchText = '' then
    ShowFindForm(False)
  else
    LedFindNext(SearchView, FSearch, True);
end;

procedure TLedMainForm.actQuickFindExecute(Sender: TObject);
begin
  if Silent then Exit;
  if FFindBar = nil then
  begin
    FFindBar := TLedFindBar.CreateFor(Self, FSearch, @SearchView);
    FFindBar.Parent := FDock.Center;
  end;
  FFindBar.Activate;
end;

{ --- recent files --------------------------------------------------------- }

procedure TLedMainForm.miOpenRecentClick(Sender: TObject);
begin
  PopulateRecentMenu;
end;

procedure TLedMainForm.PopulateRecentMenu;
var
  i: Integer;
  Item: TMenuItem;
begin
  miOpenRecent.Clear;
  for i := 0 to FRecent.Count - 1 do
  begin
    Item := TMenuItem.Create(miOpenRecent);
    { The path is the caption; ampersands in a file name would otherwise
      become accelerators. }
    Item.Caption := StringReplace(FRecent[i], '&', '&&', [rfReplaceAll]);
    Item.Hint := FRecent[i];
    Item.OnClick := @RecentItemClick;
    miOpenRecent.Add(Item);
  end;
  miOpenRecent.Enabled := FRecent.Count > 0;
end;

procedure TLedMainForm.RecentItemClick(Sender: TObject);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add(TMenuItem(Sender).Hint);
    OpenFiles(L);
  finally
    L.Free;
  end;
end;


{ --- editing commands ------------------------------------------------------ }

{ Every command is a no-op without a view, so one guard serves them all. }
function TLedMainForm.CurrentView: TLedEdit;
begin
  Result := ActiveView;
end;

procedure TLedMainForm.actUndoExecute(Sender: TObject);
begin
  if CurrentView <> nil then CurrentView.Undo;
end;

procedure TLedMainForm.actRedoExecute(Sender: TObject);
begin
  if CurrentView <> nil then CurrentView.Redo;
end;

procedure TLedMainForm.actCutExecute(Sender: TObject);
begin
  if CurrentView <> nil then CurrentView.CutToClipboard;
end;

procedure TLedMainForm.actCopyExecute(Sender: TObject);
begin
  if CurrentView <> nil then CurrentView.CopyToClipboard;
end;

procedure TLedMainForm.actPasteExecute(Sender: TObject);
begin
  if CurrentView <> nil then CurrentView.PasteFromClipboard;
end;

procedure TLedMainForm.actSelectAllExecute(Sender: TObject);
begin
  if CurrentView <> nil then CurrentView.SelectAll;
end;

procedure TLedMainForm.actPasteColumnExecute(Sender: TObject);
begin
  LedPasteColumn(CurrentView);
end;

procedure TLedMainForm.actClearSelectionExecute(Sender: TObject);
begin
  LedClearSelection(CurrentView);
end;

procedure TLedMainForm.actIndentExecute(Sender: TObject);
begin
  if CurrentView <> nil then CurrentView.CommandProcessor(ecBlockIndent, #0, nil);
end;

procedure TLedMainForm.actUnindentExecute(Sender: TObject);
begin
  if CurrentView <> nil then CurrentView.CommandProcessor(ecBlockUnindent, #0, nil);
end;

procedure TLedMainForm.actIndentSpaceExecute(Sender: TObject);
begin
  LedShiftLinesBySpace(CurrentView, True);
end;

procedure TLedMainForm.actUnindentSpaceExecute(Sender: TObject);
begin
  LedShiftLinesBySpace(CurrentView, False);
end;

procedure TLedMainForm.actCommentExecute(Sender: TObject);
begin
  if ActiveTab <> nil then
    LedCommentLines(CurrentView, ActiveTab.Document.LangInfo);
end;

procedure TLedMainForm.actUncommentExecute(Sender: TObject);
begin
  if ActiveTab <> nil then
    LedUncommentLines(CurrentView, ActiveTab.Document.LangInfo);
end;

procedure TLedMainForm.SymbolJump(ALine: Integer);
begin
  if ActiveView <> nil then
    LedGotoLine(ActiveView, ALine);
  if (ActiveView <> nil) and ActiveView.CanFocus then ActiveView.SetFocus;
end;

procedure TLedMainForm.BrowserOpenFile(const AFileName: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add(AFileName);
    OpenFiles(L);
  finally
    L.Free;
  end;
end;

procedure TLedMainForm.GrepStarted;
begin
  FDock.ShowPane('output');
  FDock.EdgeVisible[ledBottom] := True;
end;

procedure TLedMainForm.actFindInFilesExecute(Sender: TObject);
var
  Dir, Seed: string;
begin
  if Silent then Exit;
  if FGrepDialog = nil then
  begin
    FGrepDialog := TLedGrepDialog.CreateFor(Self, FOutput);
    FGrepDialog.OnStarted := @GrepStarted;
  end;
  { Default to the folder of the document in front of you, and to whatever is
    selected -- both are almost always what was meant. }
  Dir := GetCurrentDir;
  Seed := '';
  if ActiveTab <> nil then
  begin
    if not ActiveTab.Document.IsUntitled then
      Dir := ExtractFileDir(ActiveTab.Document.FileName);
    if ActiveView.SelAvail and (Pos(#10, ActiveView.SelText) = 0) then
      Seed := ActiveView.SelText;
  end;
  FGrepDialog.ShowFor(Dir, Seed);
end;

procedure TLedMainForm.actGotoLineExecute(Sender: TObject);
var
  S: string;
  N: Integer;
begin
  if CurrentView = nil then Exit;
  S := IntToStr(CurrentView.CaretY);
  if Silent then Exit;
  if not InputQuery('Go to Line',
    Format('Line number (1 - %d):', [CurrentView.Lines.Count]), S) then Exit;
  if TryStrToInt(Trim(S), N) then
    LedGotoLine(CurrentView, N)
  else
    ReportError(Format('"%s" is not a line number.', [S]));
end;

procedure TLedMainForm.actToggleBracketExecute(Sender: TObject);
begin
  LedToggleMatchingBracket(CurrentView);
end;

procedure TLedMainForm.actSelectToBracketExecute(Sender: TObject);
begin
  LedSelectToMatchingBracket(CurrentView);
end;

{ --- bookmarks ------------------------------------------------------------- }

procedure TLedMainForm.actToggleBookmarkExecute(Sender: TObject);
var
  V: TLedEdit;
  i, X, Y: Integer;
begin
  V := CurrentView;
  if V = nil then Exit;
  { Numbered slots 0-9, as medit had.  Toggling means: if this line already
    carries one, clear it; otherwise take the first free slot. }
  for i := 0 to 9 do
    if V.GetBookMark(i, X, Y) and (Y = V.CaretY) then
    begin
      V.ClearBookMark(i);
      Exit;
    end;
  for i := 0 to 9 do
    if not V.GetBookMark(i, X, Y) then
    begin
      V.SetBookMark(i, 1, V.CaretY);
      Exit;
    end;
  ReportError('All ten bookmark slots are in use.');
end;

{ Walks the bookmarks in line order rather than slot order, which is what
  "next" means to the reader. }
procedure TLedMainForm.GotoAdjacentBookmark(AForward: Boolean);
var
  V: TLedEdit;
  i, Best, X, Line: Integer;
begin
  V := CurrentView;
  if V = nil then Exit;
  Best := -1;
  for i := 0 to 9 do
  begin
    if not V.GetBookMark(i, X, Line) then Continue;
    if AForward then
    begin
      if (Line > V.CaretY) and ((Best < 0) or (Line < Best)) then Best := Line;
    end
    else
      if (Line < V.CaretY) and ((Best < 0) or (Line > Best)) then Best := Line;
  end;
  if Best > 0 then
    LedGotoLine(V, Best);
end;

procedure TLedMainForm.actNextBookmarkExecute(Sender: TObject);
begin
  GotoAdjacentBookmark(True);
end;

procedure TLedMainForm.actPrevBookmarkExecute(Sender: TObject);
begin
  GotoAdjacentBookmark(False);
end;

{ --- view toggles ---------------------------------------------------------- }

procedure TLedMainForm.actToggleFoldExecute(Sender: TObject);
begin
  LedToggleFold(CurrentView);
end;

procedure TLedMainForm.actFoldAllExecute(Sender: TObject);
begin
  LedFoldAll(CurrentView);
end;

procedure TLedMainForm.actUnfoldAllExecute(Sender: TObject);
begin
  LedUnfoldAll(CurrentView);
end;

procedure TLedMainForm.actWrapTextExecute(Sender: TObject);
begin
  if ActiveTab = nil then Exit;
  with ActiveTab.Document.Config do
    if LowerCase(GetStr(LedSetWrapMode)) = 'none' then
      SetStr(LedSetWrapMode, 'word', lcsAuto)
    else
      SetStr(LedSetWrapMode, 'none', lcsAuto);
end;

procedure TLedMainForm.actLineNumbersExecute(Sender: TObject);
begin
  if ActiveTab = nil then Exit;
  with ActiveTab.Document.Config do
    SetBool(LedSetShowLineNumbers, not GetBool(LedSetShowLineNumbers), lcsAuto);
end;

{ Ctrl+wheel zooms the whole window's views.  Temporary: never written to
  preferences, matching medit. }
procedure TLedMainForm.ViewMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  i, j, k: Integer;
  Tab: TLedTab;
begin
  if not (ssCtrl in Shift) then Exit;
  Handled := True;
  for i := 0 to FBook.PageCount - 1 do
    for j := 0 to FBook.Pages[i].ControlCount - 1 do
      if FBook.Pages[i].Controls[j] is TLedTab then
      begin
        Tab := TLedTab(FBook.Pages[i].Controls[j]);
        for k := 0 to Tab.ViewCount - 1 do
          if WheelDelta > 0 then
            LedZoomFont(Tab.Views[k], 1)
          else
            LedZoomFont(Tab.Views[k], -1);
      end;
end;

{ --- encoding and line-ending menus ---------------------------------------- }

procedure TLedMainForm.miEncodingClick(Sender: TObject);
begin
  PopulateEncodingMenu;
end;

procedure TLedMainForm.PopulateEncodingMenu;
var
  Ids: TStringList;
  i: Integer;
  Item: TMenuItem;
  Current: string;
begin
  miEncoding.Clear;
  if ActiveTab = nil then Exit;
  Current := ActiveTab.Document.Info.Encoding;

  Ids := TStringList.Create;
  try
    GetSupportedEncodings(Ids);
    for i := 0 to Ids.Count - 1 do
    begin
      Item := TMenuItem.Create(miEncoding);
      Item.Caption := Ids[i];
      Item.Hint := Ids[i];
      Item.RadioItem := True;
      Item.Checked := SameText(LedNormaliseEncoding(Ids[i]), Current);
      Item.OnClick := @EncodingItemClick;
      miEncoding.Add(Item);
    end;
  finally
    Ids.Free;
  end;
end;

procedure TLedMainForm.EncodingItemClick(Sender: TObject);
begin
  if ActiveTab = nil then Exit;
  { Changes what the next save writes; it does not re-read the file.  Use
    Reload for that. }
  ActiveTab.Document.SetEncoding(TMenuItem(Sender).Hint);
  UpdateStatusBar;
  PopulateEncodingMenu;
end;

procedure TLedMainForm.miLineEndClick(Sender: TObject);
begin
  PopulateLineEndMenu;
end;

procedure TLedMainForm.PopulateLineEndMenu;
const
  Choices: array[0..2] of TLedLineEnd = (leUnix, leWindows, leMac);
  Labels: array[0..2] of string =
    ('Unix (LF)', 'Windows (CRLF)', 'Classic Mac (CR)');
var
  i: Integer;
  Item: TMenuItem;
begin
  miLineEnd.Clear;
  if ActiveTab = nil then Exit;
  for i := 0 to High(Choices) do
  begin
    Item := TMenuItem.Create(miLineEnd);
    Item.Caption := Labels[i];
    Item.Tag := Ord(Choices[i]);
    Item.RadioItem := True;
    Item.Checked := ActiveTab.Document.Info.LineEnd = Choices[i];
    Item.OnClick := @LineEndItemClick;
    miLineEnd.Add(Item);
  end;
end;

procedure TLedMainForm.LineEndItemClick(Sender: TObject);
begin
  if ActiveTab = nil then Exit;
  ActiveTab.Document.SetLineEnd(TLedLineEnd(TMenuItem(Sender).Tag));
  UpdateStatusBar;
  PopulateLineEndMenu;
end;

{ --- language and theme menus --------------------------------------------- }

procedure TLedMainForm.miLanguageClick(Sender: TObject);
begin
  PopulateLanguageMenu;
end;

procedure TLedMainForm.PopulateLanguageMenu;
var
  L: TStringList;
  i: Integer;
  Item, Group: TMenuItem;
  Lang: TLedLangInfo;
  Section, Current: string;
begin
  miLanguage.Clear;
  Current := '';
  if ActiveTab <> nil then
    Current := ActiveTab.Document.Config.GetStr(LedSetLang);

  Item := TMenuItem.Create(miLanguage);
  Item.Caption := 'None';
  Item.Hint := '';
  Item.RadioItem := True;
  Item.Checked := Current = '';
  Item.OnClick := @LanguageItemClick;
  miLanguage.Add(Item);

  L := TStringList.Create;
  try
    LedLanguages.ListForMenu(L);
    Group := nil;
    Section := '';
    for i := 0 to L.Count - 1 do
    begin
      Lang := TLedLangInfo(L.Objects[i]);
      { 128 languages in one flat menu is unusable, so they are grouped by
        the section the grammar declares -- Source, Script, Markup and so on. }
      if Lang.Section <> Section then
      begin
        Section := Lang.Section;
        Group := TMenuItem.Create(miLanguage);
        Group.Caption := Section;
        miLanguage.Add(Group);
      end;
      Item := TMenuItem.Create(Group);
      Item.Caption := Lang.Name;
      if not LedHasHighlighter(Lang.Id) then
        { Honest about what is only recognised rather than coloured. }
        Item.Caption := Lang.Name + '  (no highlighting yet)';
      Item.Hint := Lang.Id;
      Item.RadioItem := True;
      Item.Checked := SameText(Lang.Id, Current);
      Item.OnClick := @LanguageItemClick;
      Group.Add(Item);
    end;
  finally
    L.Free;
  end;
end;

procedure TLedMainForm.LanguageItemClick(Sender: TObject);
begin
  if ActiveTab = nil then Exit;
  ActiveTab.Document.SetLanguage(TMenuItem(Sender).Hint);
  UpdateStatusBar;
  PopulateLanguageMenu;      { move the tick }
  PopulateToolMenu;          { language-specific tools may have changed }
end;

procedure TLedMainForm.miThemeClick(Sender: TObject);
begin
  PopulateThemeMenu;
end;

procedure TLedMainForm.PopulateThemeMenu;
var
  i: Integer;
  Item: TMenuItem;
  Current: string;
begin
  miTheme.Clear;
  Current := LedPrefs.GetStr(LedPrefColorScheme, 'medit');
  for i := 0 to LedThemes.Count - 1 do
  begin
    Item := TMenuItem.Create(miTheme);
    Item.Caption := LedThemes[i].Name;
    Item.Hint := LedThemes[i].Id;
    Item.RadioItem := True;
    Item.Checked := SameText(LedThemes[i].Id, Current);
    Item.OnClick := @ThemeItemClick;
    miTheme.Add(Item);
  end;
end;

procedure TLedMainForm.ThemeItemClick(Sender: TObject);
var
  i, j: Integer;
begin
  LedSetCurrentTheme(TMenuItem(Sender).Hint);
  PopulateThemeMenu;         { move the tick }
  { Every open view has to be repainted with the new chrome colours. }
  for i := 0 to FBook.PageCount - 1 do
    for j := 0 to FBook.Pages[i].ControlCount - 1 do
      if FBook.Pages[i].Controls[j] is TLedTab then
        TLedTab(FBook.Pages[i].Controls[j]).Document.ApplyConfigToViews;
end;

{ --- session -------------------------------------------------------------- }

procedure TLedMainForm.SaveSession;
var
  S: TLedSession;
  W: TLedWindowState;
  T: TLedTabState;
  Tab: TLedTab;
  i, j: Integer;
  E: TLedDockEdge;
begin
  S := TLedSession.Create;
  try
    S.AddWindow;
    W := S.Windows[0];
    W.Left := Left; W.Top := Top; W.Width := Width; W.Height := Height;
    W.Maximized := WindowState = wsMaximized;
    W.ActiveTab := FBook.ActivePageIndex;
    for E := Low(TLedDockEdge) to High(TLedDockEdge) do
    begin
      W.Docks[Ord(E)].Visible := FDock.EdgeVisible[E];
      W.Docks[Ord(E)].Size := FDock.EdgeSize[E];
    end;
    S.SetWindow(0, W);

    for i := 0 to FBook.PageCount - 1 do
      for j := 0 to FBook.Pages[i].ControlCount - 1 do
        if FBook.Pages[i].Controls[j] is TLedTab then
        begin
          Tab := TLedTab(FBook.Pages[i].Controls[j]);
          if Tab.Document.IsUntitled then Continue;
          T := Default(TLedTabState);
          T.FileName := Tab.Document.FileName;
          T.Encoding := Tab.Document.Info.Encoding;
          T.Line := Tab.ActiveView.CaretY;
          T.Column := Tab.ActiveView.CaretX;
          T.TopLine := Tab.ActiveView.TopLine;
          S.AddTab(0, T);
        end;

    S.Save;
  finally
    S.Free;
  end;
end;

function TLedMainForm.RestoreSession: Boolean;
var
  S: TLedSession;
  W: TLedWindowState;
  i: Integer;
  Doc: TLedDocument;
  Tab: TLedTab;
  E: TLedDockEdge;
begin
  Result := False;
  if not LedPrefs.GetBool(LedPrefSaveSession, False) then Exit;

  S := TLedSession.Create;
  try
    if not S.Load then Exit;
    if S.WindowCount = 0 then Exit;
    W := S.Windows[0];

    if (W.Width > 100) and (W.Height > 100) then
    begin
      Left := W.Left; Top := W.Top; Width := W.Width; Height := W.Height;
    end;
    if W.Maximized then WindowState := wsMaximized;

    for E := Low(TLedDockEdge) to High(TLedDockEdge) do
    begin
      if W.Docks[Ord(E)].Size > 0 then
        FDock.EdgeSize[E] := W.Docks[Ord(E)].Size;
      FDock.EdgeVisible[E] := W.Docks[Ord(E)].Visible;
    end;

    for i := 0 to High(W.Tabs) do
    begin
      { A file that has since been deleted is skipped rather than reported:
        restoring a session should be quiet. }
      if not FileExists(W.Tabs[i].FileName) then Continue;
      try
        Doc := FDocs.OpenFile(W.Tabs[i].FileName);
      except
        Continue;
      end;
      if Doc.ViewCount = 0 then
      begin
        Tab := AddTab(Doc);
        if W.Tabs[i].Line > 0 then
        begin
          Tab.ActiveView.CaretXY := Point(Max(1, W.Tabs[i].Column),
            Min(Max(1, W.Tabs[i].Line), Doc.Master.Lines.Count));
          Tab.ActiveView.TopLine := Max(1, W.Tabs[i].TopLine);
        end;
        Result := True;
      end;
    end;

    if Result and (W.ActiveTab >= 0) and (W.ActiveTab < FBook.PageCount) then
      FBook.ActivePageIndex := W.ActiveTab;
  finally
    S.Free;
  end;
end;

{ --- external changes ----------------------------------------------------- }

procedure TLedMainForm.FormActivate(Sender: TObject);
begin
  CheckExternalChanges;
end;

procedure TLedMainForm.CheckExternalChanges;
var
  Tab: TLedTab;
  Doc: TLedDocument;
begin
  { Only the visible document is checked, and only on focus: polling every
    open file on a timer costs more than it is worth. }
  if FCheckingDisk then Exit;
  Tab := ActiveTab;
  if Tab = nil then Exit;
  Doc := Tab.Document;
  if not Doc.ChangedOnDisk then Exit;

  FCheckingDisk := True;
  try
    if Doc.Modified then
    begin
      if Confirm(Format(
        '%s changed on disk, and you have unsaved changes.'#10 +
        'Reload and lose your changes?', [Doc.DisplayName]), False) then
        Doc.Reload;
    end
    else
      Doc.Reload;
    UpdateStatusBar;
  finally
    FCheckingDisk := False;
  end;
end;

procedure TLedMainForm.actReloadExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if (Tab = nil) or Tab.Document.IsUntitled then Exit;
  if Tab.Document.Modified then
    if not Confirm(Format('Discard your changes to %s and reload from disk?',
      [Tab.Document.DisplayName]), False) then
      Exit;
  try
    Tab.Document.Reload;
  except
    on E: ELedFileError do
      ReportError(E.Message);
  end;
  UpdateStatusBar;
end;

function TLedMainForm.ActiveTab: TLedTab;
var
  i: Integer;
begin
  Result := nil;
  if (FBook = nil) or (FBook.ActivePage = nil) then Exit;
  for i := 0 to FBook.ActivePage.ControlCount - 1 do
    if FBook.ActivePage.Controls[i] is TLedTab then
      Exit(TLedTab(FBook.ActivePage.Controls[i]));
end;

function TLedMainForm.ActiveView: TLedEdit;
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab = nil then
    Result := nil
  else
    Result := Tab.ActiveView;
end;

function TLedMainForm.AddTab(ADoc: TLedDocument): TLedTab;
var
  Sheet: TTabSheet;
begin
  Sheet := FBook.AddTabSheet;
  Result := TLedTab.CreateForDocument(Self, ADoc);
  Result.Parent := Sheet;
  Result.Sheet := Sheet;
  ADoc.OnChanged := @DocChanged;
  Result.ActiveView.OnStatusChange := @ViewStatusChange;
  Result.ActiveView.OnMouseWheel := @ViewMouseWheel;
  RefreshTabCaption(Result);
  FBook.ActivePage := Sheet;
  if Result.ActiveView.CanFocus then
    Result.ActiveView.SetFocus;
  UpdateStatusBar;
end;

procedure TLedMainForm.RefreshTabCaption(ATab: TLedTab);
var
  S: string;
begin
  if (ATab = nil) or (ATab.Sheet = nil) then Exit;
  S := ATab.Document.DisplayName;
  if ATab.Document.Modified then
    S := '*' + S;
  ATab.Sheet.Caption := S;
end;

procedure TLedMainForm.DocChanged(ADoc: TLedDocument);
var
  i, j: Integer;
  Tab: TLedTab;
begin
  for i := 0 to FBook.PageCount - 1 do
    for j := 0 to FBook.Pages[i].ControlCount - 1 do
      if FBook.Pages[i].Controls[j] is TLedTab then
      begin
        Tab := TLedTab(FBook.Pages[i].Controls[j]);
        if Tab.Document = ADoc then
          RefreshTabCaption(Tab);
      end;
  UpdateStatusBar;
end;

procedure TLedMainForm.BookChange(Sender: TObject);
begin
  UpdateStatusBar;
  { The document-dependent menus -- which language is ticked, which encoding,
    which tools apply -- follow the active document. }
  PopulateLanguageMenu;
  PopulateEncodingMenu;
  PopulateLineEndMenu;
  PopulateToolMenu;
  { Only refreshed when the pane is actually on screen: running ctags for a
    pane nobody is looking at is pure cost. }
  if (FSymbols <> nil) and FDock.EdgeVisible[ledRight] and
     (ActiveTab <> nil) then
    FSymbols.Reload(ActiveTab.Document.FileName);
  RefreshPreview;
end;

procedure TLedMainForm.ViewStatusChange(Sender: TObject;
  AChanges: TSynStatusChanges);
begin
  if AChanges * [scCaretX, scCaretY, scSelection, scModified] <> [] then
    UpdateStatusBar;
end;

procedure TLedMainForm.UpdateStatusBar;
var
  V: TLedEdit;
  D: TLedDocument;
begin
  V := ActiveView;
  if V = nil then
  begin
    StatusBar1.Panels[0].Text := '';
    StatusBar1.Panels[1].Text := '';
    StatusBar1.Panels[2].Text := '';
    StatusBar1.Panels[3].Text := '';
    StatusBar1.Panels[4].Text := '';
    Caption := 'led';
    Exit;
  end;

  D := TLedDocument(V.Document);
  StatusBar1.Panels[0].Text :=
    Format('Line %d  Col %d', [V.CaretY, V.CaretX]);
  StatusBar1.Panels[1].Text := D.Info.Encoding;
  StatusBar1.Panels[2].Text := LedLineEndName(D.Info.LineEnd);
  if D.LangInfo <> nil then
    StatusBar1.Panels[3].Text := D.LangInfo.Name
  else
    StatusBar1.Panels[3].Text := 'Plain text';
  if V.InsertMode then
    StatusBar1.Panels[4].Text := 'INS'
  else
    StatusBar1.Panels[4].Text := 'OVR';

  if D.IsUntitled then
    Caption := Format('led - %s', [D.DisplayName])
  else
    Caption := Format('led - %s', [D.FileName]);
end;

procedure TLedMainForm.ActionList1Update(AAction: TBasicAction;
  var Handled: Boolean);
var
  Tab: TLedTab;
  HasDoc: Boolean;
begin
  Tab := ActiveTab;
  HasDoc := Tab <> nil;

  actSave.Enabled := HasDoc and (Tab.Document.Modified or Tab.Document.IsUntitled);
  actSaveAs.Enabled := HasDoc;
  actCloseTab.Enabled := HasDoc;
  actSplitSideBySide.Enabled := HasDoc and Tab.CanSplit;
  actSplitStacked.Enabled := HasDoc and Tab.CanSplit;
  actUnsplit.Enabled := HasDoc and (Tab.ViewCount > 1);
  actCycleViews.Enabled := HasDoc and (Tab.ViewCount > 1);
  actReload.Enabled := HasDoc and (not Tab.Document.IsUntitled);
  actUndo.Enabled := HasDoc and Tab.ActiveView.CanUndo;
  actRedo.Enabled := HasDoc and Tab.ActiveView.CanRedo;
  actCut.Enabled := HasDoc and Tab.ActiveView.SelAvail;
  actCopy.Enabled := actCut.Enabled;
  actPaste.Enabled := HasDoc and Tab.ActiveView.CanPaste;
  actSelectAll.Enabled := HasDoc;
  actPasteColumn.Enabled := HasDoc and Tab.ActiveView.CanPaste;
  actClearSelection.Enabled := HasDoc and Tab.ActiveView.SelAvail;
  actIndent.Enabled := HasDoc;
  actUnindent.Enabled := HasDoc;
  actIndentSpace.Enabled := HasDoc;
  actUnindentSpace.Enabled := HasDoc;
  { Greyed out rather than silently doing nothing when the language has no
    comment syntax. }
  actComment.Enabled := HasDoc and LedCanComment(Tab.Document.LangInfo);
  actUncomment.Enabled := actComment.Enabled;
  actGotoLine.Enabled := HasDoc;
  actPreferences.Enabled := True;
  actStopTool.Enabled := FRunner.Running;
  actToggleOutput.Checked := FDock.EdgeVisible[ledBottom];
  actToggleTerminal.Enabled := LedPtyAvailable;
  actToggleSymbols.Checked := FDock.EdgeVisible[ledRight];
  actComplete.Enabled := HasDoc;
  actPrint.Enabled := HasDoc and LedPrinterAvailable;
  actTogglePreview.Enabled := True;
  actShortcuts.Enabled := True;
  actFind.Enabled := HasDoc;
  actFindInFiles.Enabled := True;
  actReplace.Enabled := HasDoc;
  actFindNext.Enabled := HasDoc;
  actFindPrev.Enabled := HasDoc;
  actQuickFind.Enabled := HasDoc;
  actToggleBracket.Enabled := HasDoc;
  actSelectToBracket.Enabled := HasDoc;
  actToggleBookmark.Enabled := HasDoc;
  actNextBookmark.Enabled := HasDoc;
  actPrevBookmark.Enabled := HasDoc;
  { Folding comes from the highlighter, so the menu tells the truth about
    whether this language can fold rather than offering a dead command. }
  actToggleFold.Enabled := HasDoc and LedCanFold(Tab.ActiveView);
  actFoldAll.Enabled := actToggleFold.Enabled;
  actUnfoldAll.Enabled := actToggleFold.Enabled;
  actWrapText.Enabled := HasDoc;
  actWrapText.Checked := HasDoc and
    (LowerCase(Tab.Document.Config.GetStr(LedSetWrapMode)) <> 'none');
  actLineNumbers.Enabled := HasDoc;
  actLineNumbers.Checked := HasDoc and
    Tab.Document.Config.GetBool(LedSetShowLineNumbers);
  actToggleLeftPane.Checked := FDock.EdgeVisible[ledLeft];
  actToggleBottomPane.Checked := FDock.EdgeVisible[ledBottom];

  Handled := True;
end;

procedure TLedMainForm.actNewExecute(Sender: TObject);
begin
  AddTab(FDocs.NewDocument);
end;

procedure TLedMainForm.actOpenExecute(Sender: TObject);
begin
  if OpenDialog1.Execute then
    OpenFiles(OpenDialog1.Files);
end;

procedure TLedMainForm.OpenFiles(AFiles: TStrings);
var
  i: Integer;
  Doc: TLedDocument;
  Encoding: string;
  Retried: Boolean;
begin
  for i := 0 to AFiles.Count - 1 do
  begin
    Doc := nil;
    Retried := False;
    repeat
      try
        Doc := FDocs.OpenFile(AFiles[i], Encoding);
      except
        on E: ELedFileError do
        begin
          { Only an encoding failure is worth a second chance; a missing file
            will not become present because the user picks CP1251. }
          if (E.Error = lfeEncodingFailed) and not Retried then
          begin
            Encoding := AskEncoding(AFiles[i]);
            Retried := True;
            if Encoding <> '' then Continue;
          end
          else
            ReportError(E.Message);
          Break;
        end;
        on E: Exception do
        begin
          ReportError(Format('Could not open %s:'#10'%s',
            [AFiles[i], E.Message]));
          Break;
        end;
      end;
      Break;
    until False;

    Encoding := '';
    if Doc = nil then Continue;
    if Doc.ViewCount = 0 then
      AddTab(Doc);
    FRecent.Add(Doc.FileName);
  end;
  PopulateRecentMenu;
  PopulateLanguageMenu;
  PopulateToolMenu;
end;

procedure TLedMainForm.actSaveExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab = nil then Exit;
  if Tab.Document.IsUntitled then
    actSaveAsExecute(Sender)
  else
    Tab.Document.Save;
end;

procedure TLedMainForm.actSaveAsExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab = nil then Exit;
  if not Tab.Document.IsUntitled then
    SaveDialog1.FileName := Tab.Document.FileName;
  if SaveDialog1.Execute then
  begin
    Tab.Document.SaveToFile(SaveDialog1.FileName);
    RefreshTabCaption(Tab);
    UpdateStatusBar;
    { A new name can mean a new language and new filename rules. }
    PopulateLanguageMenu;
    PopulateToolMenu;
  end;
end;

function TLedMainForm.ConfirmClose(ADoc: TLedDocument): Boolean;
var
  Res: Integer;
begin
  if not ADoc.Modified then Exit(True);
  Res := ConfirmSaveDiscardCancel(
    Format('Save changes to %s before closing?', [ADoc.DisplayName]));
  case Res of
    mrYes:
      begin
        actSaveExecute(nil);
        Result := not ADoc.Modified;
      end;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

procedure TLedMainForm.actCloseTabExecute(Sender: TObject);
var
  Tab: TLedTab;
  Sheet: TTabSheet;
  Doc: TLedDocument;
begin
  Tab := ActiveTab;
  if Tab = nil then Exit;
  Doc := Tab.Document;
  if not ConfirmClose(Doc) then Exit;

  Sheet := Tab.Sheet;
  Tab.Free;          // detaches its views from the document
  Sheet.Free;
  if Doc.ViewCount = 0 then
    FDocs.CloseDocument(Doc);

  if FBook.PageCount = 0 then
    actNewExecute(nil)
  else
    UpdateStatusBar;
end;

procedure TLedMainForm.actSplitSideBySideExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab <> nil then Tab.SplitView(False);
end;

procedure TLedMainForm.actSplitStackedExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab <> nil then Tab.SplitView(True);
end;

procedure TLedMainForm.actUnsplitExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab <> nil then Tab.Unsplit;
end;

procedure TLedMainForm.actCycleViewsExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab <> nil then Tab.CycleViews;
end;

procedure TLedMainForm.actToggleLeftPaneExecute(Sender: TObject);
begin
  FDock.ToggleEdge(ledLeft);
  if FDock.EdgeVisible[ledLeft] then
    FBrowser.EnsureRoot(GetCurrentDir);
end;

procedure TLedMainForm.actToggleBottomPaneExecute(Sender: TObject);
begin
  FDock.ToggleEdge(ledBottom);
end;

procedure TLedMainForm.actQuitExecute(Sender: TObject);
begin
  Close;
end;

procedure TLedMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  i: Integer;
begin
  for i := 0 to FDocs.Count - 1 do
    if not ConfirmClose(FDocs[i]) then
    begin
      CanClose := False;
      Exit;
    end;
  CanClose := True;

  { Written before the windows come down, while the state still exists. }
  if LedPrefs.GetBool(LedPrefSaveSession, False) then
    SaveSession;
  FRecent.Save;
  if LedPrefs.Dirty then
    LedPrefs.Save;
end;

end.
