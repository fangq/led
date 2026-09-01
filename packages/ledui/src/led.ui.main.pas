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
  ExtCtrls, Math, Graphics, ImgList, Clipbrd, LCLIntf, ToolWin,
  PairSplitter, SynEdit, SynEditTypes,
  SynEditKeyCmds, LConvEncoding,
  Led.Core.Types, Led.Core.CLI, Led.Core.Instance, Led.Core.FileIO, Led.Core.Prefs, Led.Core.Session,
  Led.Core.Config, Led.Core.Encodings, Led.Core.Paths,
  Led.Syn.Languages, Led.Syn.Theme, Led.Syn.Factory,
  Led.UI.Dock, Led.UI.Document, Led.UI.Tab, Led.UI.Edit, Led.UI.Commands,
  Led.UI.Find, Led.UI.Prefs, Led.UI.Shortcuts, Led.UI.Output,
  Led.UI.ToolRunner, Led.Core.Tools, Led.UI.Grep, Led.UI.FileBrowser,
  Led.Term.View, Led.Term.Pty, Led.Term.Pane, Led.UI.Symbols, Led.UI.Preview,
  Led.UI.Print, Led.UI.Icons, Led.UI.Focus, Led.Core.Recovery, Led.UI.Dpi,
  Led.UI.Splitter, LCLProc;

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
    actNewWindow: TAction;
    actCloseAll: TAction;
    actReopenEncoding: TAction;
    actPageSetup: TAction;
    actPrintPdf: TAction;
    actExportHtml: TAction;
    actDelete: TAction;
    actFindCurrent: TAction;
    actFindCurrentBack: TAction;
    actPrevTab: TAction;
    actNextTab: TAction;
    actFocusDoc: TAction;
    actMoveToSplit: TAction;
    actShowToolbar: TAction;
    actResetLayout: TAction;
    actSplitNotebook: TAction;
    actFocusOtherNotebook: TAction;
    actMoveToNotebook: TAction;
    miHeaderStyle: TMenuItem;
    actStripTrailing: TAction;
    actToggleBrowser: TAction;
    actSplitTermH: TAction;
    actSplitTermV: TAction;
    actHelp: TAction;
    actReportBug: TAction;
    actAbout: TAction;
    MainMenu1: TMainMenu;
    mnuFile: TMenuItem;
    mi_New: TMenuItem;
    mi_NewWindow: TMenuItem;
    miSep1: TMenuItem;
    mi_Open: TMenuItem;
    miOpenRecent: TMenuItem;
    miReopenEncoding: TMenuItem;
    mi_Reload: TMenuItem;
    miSep2: TMenuItem;
    mi_Save: TMenuItem;
    mi_SaveAs: TMenuItem;
    miSep3: TMenuItem;
    mi_PageSetup: TMenuItem;
    mi_Print: TMenuItem;
    mi_PrintPdf: TMenuItem;
    mi_ExportHtml: TMenuItem;
    miSep4: TMenuItem;
    mi_CloseTab: TMenuItem;
    mi_CloseAll: TMenuItem;
    miSep5: TMenuItem;
    mi_Quit: TMenuItem;
    mnuEdit: TMenuItem;
    mi_Undo: TMenuItem;
    mi_Redo: TMenuItem;
    miSep6: TMenuItem;
    mi_Cut: TMenuItem;
    mi_Copy: TMenuItem;
    mi_Paste: TMenuItem;
    mi_Delete: TMenuItem;
    miSep7: TMenuItem;
    mi_SelectAll: TMenuItem;
    mi_PasteColumn: TMenuItem;
    mi_ClearSelection: TMenuItem;
    miSep8: TMenuItem;
    mi_Indent: TMenuItem;
    mi_Unindent: TMenuItem;
    mi_IndentSpace: TMenuItem;
    mi_UnindentSpace: TMenuItem;
    miSep9: TMenuItem;
    mi_Comment: TMenuItem;
    mi_Uncomment: TMenuItem;
    mi_StripTrailing: TMenuItem;
    mi_Complete: TMenuItem;
    miSep10: TMenuItem;
    mi_Shortcuts: TMenuItem;
    mi_Preferences: TMenuItem;
    mnuSearch: TMenuItem;
    mi_Find: TMenuItem;
    mi_Replace: TMenuItem;
    mi_FindNext: TMenuItem;
    mi_FindPrev: TMenuItem;
    mi_QuickFind: TMenuItem;
    mi_FindInFiles: TMenuItem;
    miSep11: TMenuItem;
    mi_FindCurrent: TMenuItem;
    mi_FindCurrentBack: TMenuItem;
    miSep12: TMenuItem;
    mi_GotoLine: TMenuItem;
    miSep13: TMenuItem;
    mi_ToggleBracket: TMenuItem;
    mi_SelectToBracket: TMenuItem;
    mnuDocument: TMenuItem;
    miLanguage: TMenuItem;
    miEncoding: TMenuItem;
    miLineEnd: TMenuItem;
    miSep14: TMenuItem;
    mi_ToggleBookmark: TMenuItem;
    mi_NextBookmark: TMenuItem;
    mi_PrevBookmark: TMenuItem;
    mnuTools: TMenuItem;
    miToolList: TMenuItem;
    miSep15: TMenuItem;
    mi_SplitTermH: TMenuItem;
    mi_SplitTermV: TMenuItem;
    miSep16: TMenuItem;
    mi_StopTool: TMenuItem;
    mnuView: TMenuItem;
    mi_ShowToolbar: TMenuItem;
    miSep17: TMenuItem;
    mi_WrapText: TMenuItem;
    mi_LineNumbers: TMenuItem;
    miSep18: TMenuItem;
    mi_FocusDoc: TMenuItem;
    mi_MoveToSplit: TMenuItem;
    miSep19: TMenuItem;
    mi_ToggleFold: TMenuItem;
    mi_FoldAll: TMenuItem;
    mi_UnfoldAll: TMenuItem;
    miSep20: TMenuItem;
    mi_SplitSideBySide: TMenuItem;
    mi_SplitStacked: TMenuItem;
    mi_Unsplit: TMenuItem;
    mi_CycleViews: TMenuItem;
    miSep21: TMenuItem;
    miTheme: TMenuItem;
    miSep22: TMenuItem;
    mi_ToggleLeftPane: TMenuItem;
    mi_ToggleBottomPane: TMenuItem;
    mi_ToggleBrowser: TMenuItem;
    mi_ToggleOutput: TMenuItem;
    mi_ToggleTerminal: TMenuItem;
    mi_ToggleSymbols: TMenuItem;
    mi_TogglePreview: TMenuItem;
    mnuWindow: TMenuItem;
    mi_PrevTab: TMenuItem;
    mi_NextTab: TMenuItem;
    miSep23: TMenuItem;
    miDocList: TMenuItem;
    mnuHelp: TMenuItem;
    mi_Help: TMenuItem;
    mi_ReportBug: TMenuItem;
    miSep24: TMenuItem;
    mi_About: TMenuItem;
    ImageList1: TImageList;
    ToolBar1: TToolBar;
    tbNew: TToolButton;
    tbSep1: TToolButton;
    tbOpen: TToolButton;
    tbSave: TToolButton;
    tbSaveAs: TToolButton;
    tbSep2: TToolButton;
    tbUndo: TToolButton;
    tbRedo: TToolButton;
    tbSep3: TToolButton;
    tbCut: TToolButton;
    tbCopy: TToolButton;
    tbPaste: TToolButton;
    tbSep4: TToolButton;
    tbFind: TToolButton;
    tbReplace: TToolButton;
    tbSep5: TToolButton;
    tbStopTool: TToolButton;
    PopupEditor: TPopupMenu;
    mcUndo: TMenuItem;
    mcRedo: TMenuItem;
    mcSep1: TMenuItem;
    mcCut: TMenuItem;
    mcCopy: TMenuItem;
    mcPaste: TMenuItem;
    mcDelete: TMenuItem;
    mcSep2: TMenuItem;
    mcSelectAll: TMenuItem;
    mcSep3: TMenuItem;
    mcComment: TMenuItem;
    mcUncomment: TMenuItem;
    mcIndent: TMenuItem;
    mcUnindent: TMenuItem;
    mcSep4: TMenuItem;
    mcToggleBookmark: TMenuItem;
    mcToggleFold: TMenuItem;
    mcSep5: TMenuItem;
    miCtxTools: TMenuItem;
    mcSep6: TMenuItem;
    mcGotoLine: TMenuItem;
    mcFindCurrent: TMenuItem;
    PopupTab: TPopupMenu;
    mtSave: TMenuItem;
    mtSaveAs: TMenuItem;
    mtReload: TMenuItem;
    mtSep1: TMenuItem;
    mtCloseTab: TMenuItem;
    mtCloseAll: TMenuItem;
    mtSep2: TMenuItem;
    miTabCloseOthers: TMenuItem;
    miTabCopyPath: TMenuItem;
    miTabOpenFolder: TMenuItem;
    mtSepNotebook: TMenuItem;
    mtMoveToNotebook: TMenuItem;
    mtSplitNotebook: TMenuItem;
    mtFocusOtherNotebook: TMenuItem;
    mtSep3: TMenuItem;
    mtSplitSideBySide: TMenuItem;
    mtSplitStacked: TMenuItem;
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    StatusBar1: TStatusBar;
    procedure actAboutExecute(Sender: TObject);
    procedure actCloseAllExecute(Sender: TObject);
    procedure actDeleteExecute(Sender: TObject);
    procedure actExportHtmlExecute(Sender: TObject);
    procedure actFindCurrentBackExecute(Sender: TObject);
    procedure actFindCurrentExecute(Sender: TObject);
    procedure actFocusDocExecute(Sender: TObject);
    procedure actHelpExecute(Sender: TObject);
    procedure actMoveToSplitExecute(Sender: TObject);
    procedure actNewWindowExecute(Sender: TObject);
    procedure actNextTabExecute(Sender: TObject);
    procedure actPageSetupExecute(Sender: TObject);
    procedure actPrevTabExecute(Sender: TObject);
    procedure actPrintPdfExecute(Sender: TObject);
    procedure actReopenEncodingExecute(Sender: TObject);
    procedure actReportBugExecute(Sender: TObject);
    procedure actShowToolbarExecute(Sender: TObject);
    procedure actResetLayoutExecute(Sender: TObject);
    procedure actSplitNotebookExecute(Sender: TObject);
    procedure actFocusOtherNotebookExecute(Sender: TObject);
    procedure actMoveToNotebookExecute(Sender: TObject);
    procedure miHeaderStyleClick(Sender: TObject);
    procedure HeaderStylePicked(Sender: TObject);
    procedure actSplitTermHExecute(Sender: TObject);
    procedure actSplitTermVExecute(Sender: TObject);
    procedure actStripTrailingExecute(Sender: TObject);
    procedure actToggleBrowserExecute(Sender: TObject);
    procedure miReopenEncodingClick(Sender: TObject);
    procedure miDocListClick(Sender: TObject);
    procedure miTabCloseOthersClick(Sender: TObject);
    procedure miTabCopyPathClick(Sender: TObject);
    procedure miTabOpenFolderClick(Sender: TObject);
    procedure PopupEditorPopup(Sender: TObject);
    procedure PopupTabPopup(Sender: TObject);
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
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
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
    FFocusedOnce: Boolean;
    FRecovery: TLedRecovery;
    FRecoveryTimer: TTimer;
    FRecoveryOffered: Boolean;
    FDocs: TLedDocuments;
    FDock: TLedDockHost;
    FBook: TPageControl;
    { The second tab group.  nil until the window is split, which is what
      "split notebook" means: two independent sets of tabs side by side in one
      window, as medit's get_notebook(window, 0/1) offered.  The pair splitter
      exists only while it does. }
    FBook2: TPageControl;
    FBookSplit: TLedPairSplitter;
    FActiveBookIdx: Integer;
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
    FTerminal: TLedTerminalPane;
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
    procedure PaneShown(const AId: string);
    procedure StartTerminalDeferred(Data: PtrInt);
    procedure StartTerminal;
    { Tells the editor which keys the menus have claimed, so it stops
      handling them itself.  Called after the shortcuts are set up and again
      whenever the user changes them. }
    procedure ReserveActionShortcuts;
    procedure PopulateHeaderStyleMenu;
    { The tab group new tabs go to and ActiveTab reads from. }
    function ActiveBook: TPageControl;
    function BookByIndex(AIndex: Integer): TPageControl;
    function IndexOfBook(ABook: TPageControl): Integer;
    { Every tab in the window, both groups, in group order.  Five copies of
      the same nested loop over pages and their controls were doing this
      before, and every one of them would have had to learn about the second
      group. }
    procedure CollectTabs(AInto: TFPList);
    function TabOnPage(APage: TCustomPage): TLedTab;
    procedure SetActiveBook(AIndex: Integer);
    procedure BookEnter(Sender: TObject);
    procedure MoveTabToBook(ATab: TLedTab; ABook: TPageControl);

    procedure SaveSession;

    { Empties a dynamic submenu without destroying its items mid-event.  See
      the implementation for why TMenuItem.Clear cannot be used here. }
    procedure ClearMenu(AItem: TMenuItem);

    { Crash recovery.  The journal is reconciled wholesale on a timer rather
      than hooked into every save and close path, because there are several of
      each and missing one leaves a stale entry that offers the user work they
      already saved. }
    procedure RecoveryTick(Sender: TObject);
    procedure ReconcileRecovery;
    procedure OfferRecovery;
    function RecoveryIdFor(ADoc: TLedDocument): string;
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
    procedure CloseActiveTab(AReplace: Boolean);
    procedure PopulateReopenMenu;
    procedure ReopenEncodingItemClick(Sender: TObject);
    procedure PopulateDocMenu;
    procedure DocItemClick(Sender: TObject);
    function TabOnPage(AIndex: Integer): TLedTab;
    procedure FindWordAtCursor(ABackwards: Boolean);
    procedure PopulateContextTools;
    procedure BuildIcons;
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
    { The second tab group, nil unless the window is split. }
    property Notebook2: TPageControl read FBook2;
    function TabCount: Integer;
    function NotebookSplit: Boolean;
    { Splits the window into two independent tab groups, or puts them back
      together.  Idempotent. }
    procedure SetNotebookSplit(AEnable: Boolean; AVertical: Boolean = False);
    procedure FocusOtherNotebook;
    procedure MoveTabToOtherNotebook;
    { For the self-test: the shortcut New Tab actually carries, so a check can
      prove the accelerator survived rather than only that the editor let go
      of the key. }
    function NewDocShortCut: TShortCut;
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

{ The image list ships empty and is drawn here, once, against the current
  theme's menu-text colour, so the icons stay legible under a dark theme
  instead of being black-on-black. }
procedure TLedMainForm.BuildIcons;
var
  Size: Integer;
begin
  { The icons are drawn by code rather than loaded, so they can be generated
    at whatever size the display calls for instead of being scaled up from
    sixteen pixels and going soft.  Sixteen is the size they were designed
    at, which is what LedScale96 takes. }
  Size := LedScale96(16);
  ImageList1.Width := Size;
  ImageList1.Height := Size;
  LedBuildIconList(ImageList1, LedIconNames, clBtnText);
end;

procedure TLedMainForm.FormCreate(Sender: TObject);
begin
  BuildIcons;
  FDocs := TLedDocuments.Create(Self);

  { The journal is created before anything can be edited, but the directory
    itself is only made on the first write, so an installation that never
    crashes never grows one. }
  FRecovery := TLedRecovery.Create;
  FRecoveryTimer := TTimer.Create(Self);
  FRecoveryTimer.Interval :=
    Max(5, LedPrefs.GetInt(LedPrefRecoveryInterval, 20)) * 1000;
  FRecoveryTimer.OnTimer := @RecoveryTick;
  FRecoveryTimer.Enabled := LedPrefs.GetBool(LedPrefRecoveryEnabled, True);
  FRecent := TLedRecentFiles.Create;
  FRecent.Load;
  FSearch := TLedSearchState.Create;
  { Defaults are captured before keys.ini is read, so a customisation can be
    told from a default and Reset has something to go back to. }
  FShortcuts := TLedShortcuts.Create(ActionList1);
  FShortcuts.CaptureDefaults;
  { Before the first document, so the first editor is built already knowing
    which keys are not its to handle. }
  ReserveActionShortcuts;
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
  { The edge rails draw the same icons the toolbar and menus use. }
  FDock.Images := ImageList1;
  FDock.ShowRails := LedPrefs.GetBool(LedPrefShowPaneButtons, True);
  { Unlocked by default: dragging panes around is worth having, and the
    instability it can provoke lives in AnchorDocking's gtk2 handling rather
    than here.  The lock is in Preferences for anyone who would rather not,
    and View > Reset Pane Layout is the way back from a bad drop. }
  FDock.DraggingAllowed := not LedPrefs.GetBool(LedPrefLockPanes, False);
  FDock.HeaderStyle := LedPrefs.GetStr(LedPrefHeaderStyle, 'Points');
  FDock.OnPaneShown := @PaneShown;

  { Dropping files on the window opens them.  Set here rather than in the
    designer because the handler has to exist first, and because this is
    where the rest of the window's wiring lives. }
  AllowDropFiles := True;
  OnDropFiles := @FormDropFiles;

  FBook := TPageControl.Create(Self);
  FBook.Parent := FDock.Center;
  FBook.Align := alClient;
  FBook.OnChange := @BookChange;
  FBook.OnEnter := @BookEnter;
  FBook.Images := ImageList1;
  FBook.PopupMenu := PopupTab;

  { Phase 0 placeholders so the dock edges can be exercised; real panes arrive
    in phases 3 and 5. }
  FOutput := TLedOutputPane.Create(Self);
  FOutput.OnJump := @OutputJump;
  { The output pane is a TSynEdit like the editor, and was the one pane
    nothing ever themed -- so it sat there as a white rectangle in the middle
    of a dark window.  It takes the same theme the documents do. }
  LedApplyThemeToEditor(LedCurrentTheme, FOutput);

  FBrowser := TLedFileBrowser.Create(Self);
  FBrowser.OnOpenFile := @BrowserOpenFile;

  FDock.AddPane(ledLeft, 'files', 'Files', FBrowser, 'browser');

  FSymbols := TLedSymbolPane.Create(Self);
  FSymbols.OnJump := @SymbolJump;
  FDock.AddPane(ledRight, 'symbols', 'Symbols', FSymbols, 'symbols');
  FDock.EdgeVisible[ledRight] := False;
  FDock.AddPane(ledBottom, 'output', 'Output', FOutput, 'run');

  { The preview and the terminal used to be registered the first time their
    action ran, which meant a saved layout naming them was restored before
    they existed:

      TAnchorDockMaster.DoCreateControl WARNING: control not found: "Pane_terminal"
      CreateControlsForNode Pane_terminal failed to create

    and the pane the user had left open came back missing.  Registering a
    pane is cheap -- it creates the control, not the work behind it: the
    terminal starts no pseudo-terminal until it is first shown, and the
    preview renders nothing until asked -- so they are registered here with
    the rest, and LoadLayout finds everything it names. }
  FPreview := TLedPreviewPane.Create(Self);
  FDock.AddPane(ledRight, 'preview', 'Preview', FPreview, 'doc');

  { Except where there is no pseudo-terminal to be had.  Registering it there
    would put a button on the rail for a pane that can only apologise. }
  if LedPtyAvailable then
  begin
    FTerminal := TLedTerminalPane.Create(Self);
    FDock.AddPane(ledBottom, 'terminal', 'Terminal', FTerminal, 'terminal');
  end;

  FDock.EdgeVisible[ledLeft] := False;
  FDock.EdgeVisible[ledBottom] := False;

  { Restore where the user last put the panes.  A layout from an older build
    is discarded rather than fought with, leaving the defaults. }
  FDock.LoadLayout(LedConfigFile('layout.xml'));

  ToolBar1.Visible := LedPrefs.GetBool('Editor/show_toolbar', True);
  actShowToolbar.Checked := ToolBar1.Visible;

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
  PopulateReopenMenu;
  PopulateDocMenu;
  { Every other dynamic submenu is filled here as well as on its own click,
    which is why they have contents the first time the menu is opened.  This
    one was only filled on click, so it came up empty until it had been
    clicked once. }
  PopulateHeaderStyleMenu;
end;

procedure TLedMainForm.FormDestroy(Sender: TObject);
begin
  FRecovery.Free;
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
  ClearMenu(miToolList);
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
  { Registered in FormCreate, before the layout was restored. }
  if FPreview = nil then Exit;
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
begin
  if not LedPtyAvailable then
  begin
    ReportError('A terminal needs a pseudo-terminal, which is not available '
      + 'on this platform yet.');
    Exit;
  end;

  { Registered in FormCreate when a pseudo-terminal is available, which the
    check above has already established. }
  if FTerminal = nil then Exit;
  FDock.ShowPane('terminal');
  FDock.EdgeVisible[ledBottom] := True;

  { ShowPane raises OnPaneShown, which starts it. }
  LedTryFocus(FTerminal.Active);
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
  LedTryFocus(Tab.ActiveView);
end;

{ --- preferences and shortcuts --------------------------------------------- }

procedure TLedMainForm.PrefsApplied(Sender: TObject);
var
  i: Integer;
  Tabs: TFPList;
begin
  { Preferences feed the user layer of every document's config, and the theme
    may have changed too, so both are rebuilt and pushed to every view. }
  LedReloadUserConfig;
  LedSetCurrentTheme(LedPrefs.GetStr(LedPrefColorScheme, 'medit'));
  FDock.ShowRails := LedPrefs.GetBool(LedPrefShowPaneButtons, True);
  FDock.DraggingAllowed := not LedPrefs.GetBool(LedPrefLockPanes, False);
  FDock.HeaderStyle := LedPrefs.GetStr(LedPrefHeaderStyle, 'Points');
  { The output pane is not a document, so the loop below never reaches it. }
  LedApplyThemeToEditor(LedCurrentTheme, FOutput);
  Tabs := TFPList.Create;
  try
    CollectTabs(Tabs);
    for i := 0 to Tabs.Count - 1 do
      TLedTab(Tabs[i]).Document.ApplyConfigToViews;
  finally
    Tabs.Free;
  end;
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
  { A shortcut just added to an action has to be taken away from the editor,
    or the editor keeps handling it and the new binding appears not to work. }
  ReserveActionShortcuts;
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
  i: Integer;
  Tabs: TFPList;
begin
  Tabs := TFPList.Create;
  try
    CollectTabs(Tabs);
    for i := 0 to Tabs.Count - 1 do
      if TLedTab(Tabs[i]).Document = ADoc then
        Exit(TLedTab(Tabs[i]));
  finally
    Tabs.Free;
  end;
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
  ClearMenu(miOpenRecent);
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
  LedTryFocus(ActiveView);
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
  i, k: Integer;
  Tab: TLedTab;
  Tabs: TFPList;
begin
  if not (ssCtrl in Shift) then Exit;
  Handled := True;
  Tabs := TFPList.Create;
  try
    CollectTabs(Tabs);
    for i := 0 to Tabs.Count - 1 do
    begin
      Tab := TLedTab(Tabs[i]);
      for k := 0 to Tab.ViewCount - 1 do
        if WheelDelta > 0 then
          LedZoomFont(Tab.Views[k], 1)
        else
          LedZoomFont(Tab.Views[k], -1);
    end;
  finally
    Tabs.Free;
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
  ClearMenu(miEncoding);
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
  ClearMenu(miLineEnd);
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
  ClearMenu(miLanguage);
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
  ClearMenu(miTheme);
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
  i: Integer;
  Tabs: TFPList;
begin
  LedSetCurrentTheme(TMenuItem(Sender).Hint);
  PopulateThemeMenu;         { move the tick }
  { Every open view has to be repainted with the new chrome colours. }
  Tabs := TFPList.Create;
  try
    CollectTabs(Tabs);
    for i := 0 to Tabs.Count - 1 do
      TLedTab(Tabs[i]).Document.ApplyConfigToViews;
  finally
    Tabs.Free;
  end;
end;

{ --- session -------------------------------------------------------------- }

{ ---- crash recovery ---------------------------------------------------- }

function TLedMainForm.RecoveryIdFor(ADoc: TLedDocument): string;
begin
  if ADoc = nil then Exit('');
  Result := LedRecoveryId(ADoc.FileName, ADoc.UntitledNo);
end;

{ Bring the journal into line with what is actually open and dirty.  Every
  document is considered on every tick, so a save, a Save As or a close needs
  no hook of its own: the next pass simply stops finding it dirty.  Entries
  for documents that are gone are swept the same way. }
procedure TLedMainForm.ReconcileRecovery;
var
  i: Integer;
  Doc: TLedDocument;
  E: TLedRecoveryEntry;
  Live: TStringList;
  Pending: TLedRecoveryEntries;
begin
  if FRecovery = nil then Exit;

  Live := TStringList.Create;
  try
    Live.Sorted := True;
    Live.Duplicates := dupIgnore;

    for i := 0 to FDocs.Count - 1 do
    begin
      Doc := FDocs[i];
      if Doc = nil then Continue;
      if not Doc.Modified then Continue;

      E := Default(TLedRecoveryEntry);
      E.Id          := RecoveryIdFor(Doc);
      E.FileName    := Doc.FileName;
      E.DisplayName := Doc.DisplayName;
      E.Encoding    := Doc.Info.Encoding;
      E.Language    := Doc.LangInfo.Id;
      E.Line        := Doc.Master.CaretY;
      E.Column      := Doc.Master.CaretX;
      E.SavedAt     := Now;
      Live.Add(E.Id);
      try
        FRecovery.Store(E, Doc.Master.Lines.Text);
      except
        { A journal that cannot be written must not stop the editor.  The
          alternative -- an exception every few seconds from a timer -- is
          worse than no journal. }
      end;
    end;

    { Anything journalled that is no longer a dirty open document has been
      saved or closed, so it is no longer work at risk. }
    Pending := FRecovery.Scan;
    for i := 0 to High(Pending) do
      if Live.IndexOf(Pending[i].Id) < 0 then
        FRecovery.Discard(Pending[i].Id);
  finally
    Live.Free;
  end;
end;

procedure TLedMainForm.RecoveryTick(Sender: TObject);
begin
  { Not during a scripted run.  Pump calls ProcessMessages, so this timer
    would fire at arbitrary points between a test's steps, reading every
    document's text and writing files while the test is mid-way through
    changing them.  A harness that races a background task is a harness that
    fails for reasons nobody can reproduce. }
  if Silent then Exit;
  ReconcileRecovery;
end;

{ Anything left in the journal at startup is work from a run that never
  reached its close handler.  A clean exit empties the directory, so its
  contents are the whole signal -- there is no separate "was I running" flag
  to fall out of step with reality. }
procedure TLedMainForm.OfferRecovery;
var
  Pending: TLedRecoveryEntries;
  i, Shown: Integer;
  Names, Msg: string;
  Doc: TLedDocument;
  Tab: TLedTab;
  Restored: Integer;
begin
  if FRecovery = nil then Exit;
  if FRecoveryOffered then Exit;
  FRecoveryOffered := True;
  { Silent is the scripted-run flag: no modal dialog may appear, because it
    would block the harness and land on the screen of whoever is logged in.
    The journal is left alone rather than cleared -- a self-test must not
    destroy the user's pending recovery as a side effect of running. }
  if Silent then Exit;

  Pending := FRecovery.Scan;
  if Length(Pending) = 0 then Exit;

  Names := '';
  Shown := 0;
  for i := 0 to High(Pending) do
  begin
    if Shown >= 10 then
    begin
      Names := Names + LineEnding + Format('  ... and %d more',
        [Length(Pending) - Shown]);
      Break;
    end;
    if Pending[i].DisplayName <> '' then
      Names := Names + LineEnding + '  ' + Pending[i].DisplayName
    else if Pending[i].FileName <> '' then
      Names := Names + LineEnding + '  ' + ExtractFileName(Pending[i].FileName)
    else
      Names := Names + LineEnding + '  ' + Pending[i].Id;
    Inc(Shown);
  end;

  if Length(Pending) = 1 then
    Msg := 'led did not shut down cleanly, and one document had unsaved ' +
      'changes:' + LineEnding + Names + LineEnding + LineEnding +
      'Recover it?'
  else
    Msg := Format('led did not shut down cleanly, and %d documents had ' +
      'unsaved changes:', [Length(Pending)]) + LineEnding + Names +
      LineEnding + LineEnding + 'Recover them?';

  if MessageDlg('Recover unsaved work', Msg, mtWarning, [mbYes, mbNo], 0)
     <> mrYes then
  begin
    FRecovery.Clear;
    Exit;
  end;

  Restored := 0;
  for i := 0 to High(Pending) do
  begin
    Doc := nil;
    try
      { A recovered file opens from disk first, so its encoding, line ending
        and language are the real ones, and only the text is replaced.  The
        document is left modified on purpose: recovery hands back the work,
        it does not decide to write it over the file. }
      if (Pending[i].FileName <> '') and FileExists(Pending[i].FileName) then
        Doc := FDocs.OpenFile(Pending[i].FileName)
      else
        Doc := FDocs.NewDocument;

      if Doc = nil then Continue;

      Doc.Master.BeginUpdate;
      try
        Doc.Master.Lines.Text := FRecovery.LoadText(Pending[i]);
      finally
        Doc.Master.EndUpdate;
      end;
      Doc.Master.Modified := True;

      Tab := AddTab(Doc);
      if Tab <> nil then
      begin
        if Pending[i].Line > 0 then
          Tab.ActiveView.CaretY := Pending[i].Line;
        if Pending[i].Column > 0 then
          Tab.ActiveView.CaretX := Pending[i].Column;
      end;
      Inc(Restored);
    except
      { One unrecoverable entry must not abandon the rest. }
    end;
  end;

  { The journal is rebuilt from the restored documents on the next tick, so
    clearing here cannot lose anything -- and leaving the old entries would
    make a second crash offer the same work twice. }
  FRecovery.Clear;
  if Restored > 0 then
    ReconcileRecovery;
end;

{ Every dynamic submenu -- recent files, languages, encodings, themes, the
  document list, the tool lists -- is rebuilt from its own parent item's
  OnClick, which is the only moment it can be current.  Emptying it with
  TMenuItem.Clear frees the child items right there, while the LCL is still
  dispatching that event on that menu, and the LCL says so:

    WARNING: TMenuItem.Destroy with LCLRefCount>0.
    Hint: Maybe the component is processing an event?

  Application.ReleaseComponent exists for exactly this: it detaches the item
  now and frees it once the reference count has dropped, after the event has
  finished with it.  Detaching first matters too -- the item must be out of
  the menu before the new contents go in, or the old entries are still drawn.
}
procedure TLedMainForm.ClearMenu(AItem: TMenuItem);
var
  i: Integer;
  Child: TMenuItem;
begin
  if AItem = nil then Exit;
  for i := AItem.Count - 1 downto 0 do
  begin
    Child := AItem.Items[i];
    AItem.Delete(i);
    Application.ReleaseComponent(Child);
  end;
end;

{ The pane header's look is a matter of taste and the right answer is not
  obvious -- a hairline grip reads as structure to one person and as clutter
  to the next -- so the choice is offered instead of decided.  The list comes
  from AnchorDocking's own registry, so a style added upstream appears here
  without led being told, and led's own LedPlain sits among them. }
{ Starting the shell is the pane's own business, not one menu item's.  It used
  to happen only inside actToggleTerminalExecute, so a terminal opened from an
  edge button or restored with the layout came up as an empty black rectangle
  with no prompt in it. }
procedure TLedMainForm.StartTerminal;
var
  Dir: string;
begin
  if FTerminal = nil then Exit;
  if FTerminal.Running then Exit;
  { In the folder of the document in front of you, which is nearly always
    where you wanted to be. }
  Dir := GetCurrentDir;
  if (ActiveTab <> nil) and not ActiveTab.Document.IsUntitled then
    Dir := ExtractFileDir(ActiveTab.Document.FileName);
  FTerminal.Start(Dir);
end;

procedure TLedMainForm.StartTerminalDeferred(Data: PtrInt);
begin
  StartTerminal;
  if FTerminal <> nil then
    LedTryFocus(FTerminal.Active);
end;

procedure TLedMainForm.PaneShown(const AId: string);
begin
  if SameText(AId, 'terminal') then
    { Queued, not called.  OnPaneShown fires from inside ShowPane, while
      AnchorDocking is still docking the pane, so the view has no size yet --
      and TLedTermView.Start measures Width div FCharW to decide how many
      columns to ask the shell for.  Started there it came up against a
      control of no size and, often enough to be the first thing anyone
      noticed, showed nothing at all until it was toggled again.  A queued
      call runs once the layout has settled. }
    Application.QueueAsyncCall(@StartTerminalDeferred, 0)
  else if SameText(AId, 'preview') then
    { The preview renders the document in front of you; shown from an edge
      button it would otherwise sit blank until something else refreshed it. }
    RefreshPreview;
end;


function TLedMainForm.NewDocShortCut: TShortCut;
begin
  Result := actNew.ShortCut;
end;

procedure TLedMainForm.ReserveActionShortcuts;
var
  i, j: Integer;
  Act: TContainedAction;
begin
  for i := 0 to ActionList1.ActionCount - 1 do
  begin
    Act := ActionList1.Actions[i];
    if not (Act is TCustomAction) then Continue;
    LedReserveShortcut(TCustomAction(Act).ShortCut);
    { Secondary shortcuts count too: a menu that offers two ways in should not
      have one of them swallowed. }
    for j := 0 to TCustomAction(Act).SecondaryShortCuts.Count - 1 do
      LedReserveShortcut(
        TextToShortCut(TCustomAction(Act).SecondaryShortCuts[j]));
  end;

  { Existing views were built before this ran, or before the user last
    changed a shortcut, so they are brought into line too. }
  for i := 0 to FDocs.Count - 1 do
    for j := 0 to FDocs[i].ViewCount - 1 do
      LedStripReservedKeystrokes(FDocs[i].Views[j]);
end;

procedure TLedMainForm.PopulateHeaderStyleMenu;
var
  Names: TStringArray;
  i: Integer;
  Item: TMenuItem;
  Current: string;
begin
  ClearMenu(miHeaderStyle);
  Current := FDock.HeaderStyle;
  Names := FDock.HeaderStyleNames;
  for i := 0 to High(Names) do
  begin
    Item := TMenuItem.Create(miHeaderStyle);
    Item.Caption := LedHeaderStyleCaption(Names[i]);
    { The real name travels in Hint, because the caption is now a label and
      no longer something the dock would recognise. }
    Item.Hint := Names[i];
    Item.Checked := SameText(Names[i], Current);
    Item.OnClick := @HeaderStylePicked;
    miHeaderStyle.Add(Item);
  end;
end;

{ Split Notebook toggles: the same item puts the window back together, which
  is what the checked state in the menu says. }
procedure TLedMainForm.actSplitNotebookExecute(Sender: TObject);
begin
  SetNotebookSplit(not NotebookSplit);
end;

procedure TLedMainForm.actFocusOtherNotebookExecute(Sender: TObject);
begin
  FocusOtherNotebook;
end;

procedure TLedMainForm.actMoveToNotebookExecute(Sender: TObject);
begin
  MoveTabToOtherNotebook;
end;

procedure TLedMainForm.miHeaderStyleClick(Sender: TObject);
begin
  PopulateHeaderStyleMenu;
end;

procedure TLedMainForm.HeaderStylePicked(Sender: TObject);
begin
  if not (Sender is TMenuItem) then Exit;
  FDock.HeaderStyle := TMenuItem(Sender).Hint;
  LedPrefs.SetStr(LedPrefHeaderStyle, FDock.HeaderStyle);
end;

{ --- the two tab groups ---------------------------------------------------- }

function TLedMainForm.BookByIndex(AIndex: Integer): TPageControl;
begin
  if AIndex = 1 then Result := FBook2 else Result := FBook;
end;

function TLedMainForm.IndexOfBook(ABook: TPageControl): Integer;
begin
  if (ABook <> nil) and (ABook = FBook2) then Result := 1 else Result := 0;
end;

function TLedMainForm.ActiveBook: TPageControl;
begin
  Result := BookByIndex(FActiveBookIdx);
  if Result = nil then Result := FBook;
end;

function TLedMainForm.TabOnPage(APage: TCustomPage): TLedTab;
var
  i: Integer;
begin
  Result := nil;
  if APage = nil then Exit;
  for i := 0 to APage.ControlCount - 1 do
    if APage.Controls[i] is TLedTab then
      Exit(TLedTab(APage.Controls[i]));
end;

procedure TLedMainForm.CollectTabs(AInto: TFPList);
var
  b, i: Integer;
  Book: TPageControl;
  Tab: TLedTab;
begin
  AInto.Clear;
  for b := 0 to 1 do
  begin
    Book := BookByIndex(b);
    if Book = nil then Continue;
    for i := 0 to Book.PageCount - 1 do
    begin
      Tab := TabOnPage(Book.Pages[i]);
      if Tab <> nil then AInto.Add(Tab);
    end;
  end;
end;

procedure TLedMainForm.SetActiveBook(AIndex: Integer);
begin
  if BookByIndex(AIndex) = nil then AIndex := 0;
  if FActiveBookIdx = AIndex then Exit;
  FActiveBookIdx := AIndex;
  UpdateStatusBar;
end;

{ Clicking anywhere in a group makes it the active one, which is what decides
  where a new tab lands and which tab the menus act on. }
procedure TLedMainForm.BookEnter(Sender: TObject);
begin
  if Sender is TPageControl then
    SetActiveBook(IndexOfBook(TPageControl(Sender)));
end;

{ Across both groups, which is what "is there more than one tab open" has to
  mean once there can be two of them. }
function TLedMainForm.TabCount: Integer;
begin
  Result := FBook.PageCount;
  if FBook2 <> nil then Inc(Result, FBook2.PageCount);
end;

function TLedMainForm.NotebookSplit: Boolean;
begin
  Result := FBook2 <> nil;
end;

{ Moving a tab between groups is a reparent and nothing more.  That is the
  whole payoff of TLedDocument owning the buffer rather than any view: the
  document, its undo history and its marks are untouched, and the views keep
  pointing at the same shared TSynEditStringList.  Nothing is saved, reloaded
  or re-highlighted. }
procedure TLedMainForm.MoveTabToBook(ATab: TLedTab; ABook: TPageControl);
var
  Sheet, Old: TTabSheet;
begin
  if (ATab = nil) or (ABook = nil) then Exit;
  Old := ATab.Sheet;
  if (Old <> nil) and (Old.PageControl = ABook) then Exit;

  Sheet := ABook.AddTabSheet;
  ATab.Parent := Sheet;
  ATab.Sheet := Sheet;
  RefreshTabCaption(ATab);
  ABook.ActivePage := Sheet;
  Old.Free;
end;

procedure TLedMainForm.SetNotebookSplit(AEnable: Boolean; AVertical: Boolean);
var
  Tabs: TFPList;
  i: Integer;
begin
  if AEnable = NotebookSplit then Exit;

  if AEnable then
  begin
    { A pair splitter holding the two groups, in place of the single one. }
    FBookSplit := TLedPairSplitter.Create(Self);
    FBookSplit.Parent := FDock.Center;
    FBookSplit.Align := alClient;
    if AVertical then
      FBookSplit.SplitterType := pstVertical
    else
      FBookSplit.SplitterType := pstHorizontal;

    FBook.Parent := FBookSplit.Sides[0];
    FBook.Align := alClient;

    FBook2 := TPageControl.Create(Self);
    FBook2.Parent := FBookSplit.Sides[1];
    FBook2.Align := alClient;
    FBook2.OnChange := @BookChange;
    FBook2.OnEnter := @BookEnter;
    FBook2.Images := ImageList1;
    FBook2.PopupMenu := PopupTab;

    { Divide the space evenly.  TPairSplitter leaves the divider wherever its
      default falls, which is not the middle -- the same thing that made a
      fresh split view come out lopsided in c79f95a. }
    if AVertical then
      FBookSplit.Position := FBookSplit.Height div 2
    else
      FBookSplit.Position := FBookSplit.Width div 2;

    { A split with nothing in the second group is a puzzle rather than a
      feature, so the tab in front moves across to start it off -- as long as
      that does not empty the first. }
    if FBook.PageCount > 1 then
      MoveTabToBook(ActiveTab, FBook2);
    SetActiveBook(1);
  end
  else
  begin
    { Everything comes back to the first group, in order, before anything is
      freed. }
    Tabs := TFPList.Create;
    try
      CollectTabs(Tabs);
      for i := 0 to Tabs.Count - 1 do
        if TLedTab(Tabs[i]).Sheet.PageControl = FBook2 then
          MoveTabToBook(TLedTab(Tabs[i]), FBook);
    finally
      Tabs.Free;
    end;

    FBook2.Free;
    FBook2 := nil;
    FBook.Parent := FDock.Center;
    FBook.Align := alClient;
    FreeAndNil(FBookSplit);
    SetActiveBook(0);
  end;

  UpdateStatusBar;
end;

procedure TLedMainForm.FocusOtherNotebook;
var
  Other: TPageControl;
  Tab: TLedTab;
begin
  if not NotebookSplit then Exit;
  if FActiveBookIdx = 0 then Other := FBook2 else Other := FBook;
  { Not into an empty group.  Moving the last tab out of one leaves a half
    with nothing in it, and focusing that would put the caret nowhere and
    leave every document-shaped menu item greyed out with no way back except
    to guess.  The group is left in place -- the user split the window and
    can unsplit it -- but focus stays where there is something to edit. }
  if (Other = nil) or (Other.PageCount = 0) then Exit;
  SetActiveBook(IndexOfBook(Other));
  Tab := ActiveTab;
  if Tab <> nil then
    LedTryFocus(Tab.ActiveView);
end;

procedure TLedMainForm.MoveTabToOtherNotebook;
var
  Tab: TLedTab;
  Target: TPageControl;
begin
  Tab := ActiveTab;
  if Tab = nil then Exit;

  { Asking to move a tab when there is nowhere to move it to is a reasonable
    way to ask for a split, and is what medit's Move to Split Notebook does. }
  if not NotebookSplit then
  begin
    SetNotebookSplit(True);
    Exit;
  end;

  if Tab.Sheet.PageControl = FBook then Target := FBook2 else Target := FBook;
  MoveTabToBook(Tab, Target);
  SetActiveBook(IndexOfBook(Target));
  LedTryFocus(Tab.ActiveView);
end;

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

{ Files dropped on the window.

  A directory is not opened as a document -- it points the file browser at
  itself instead, which is what dropping a folder on an editor is asking for
  and what medit's browser did with one.

  Everything else goes through OpenFiles, the same path the Open dialog and
  the command line use, so a dropped file gets the encoding try-list, the
  prompt on a failed decode and the recent-files entry rather than a second,
  thinner way in. }
procedure TLedMainForm.FormDropFiles(Sender: TObject;
  const FileNames: array of string);
var
  i: Integer;
  Files: TStringList;
  Dir: string;
begin
  Files := TStringList.Create;
  try
    Dir := '';
    for i := 0 to High(FileNames) do
    begin
      if FileNames[i] = '' then Continue;
      if DirectoryExists(FileNames[i]) then
      begin
        if Dir = '' then Dir := FileNames[i];
        Continue;
      end;
      Files.Add(FileNames[i]);
    end;

    if Files.Count > 0 then
      OpenFiles(Files);

    if Dir <> '' then
    begin
      FDock.ShowPane('files');
      if FBrowser <> nil then
        FBrowser.SetRoot(Dir);
    end;
  finally
    Files.Free;
  end;

  { The drop came from another window, so this one is not in front. }
  if WindowState = wsMinimized then WindowState := wsNormal;
  BringToFront;
  LedTryFocus(ActiveView);
end;

procedure TLedMainForm.FormActivate(Sender: TObject);
begin
  { The editor could not be focused while the window was still being built,
    so the first activation is where it actually happens. }
  if not FFocusedOnce then
  begin
    FFocusedOnce := True;
    LedTryFocus(ActiveView);
    { Asked once the window is actually up, so the dialog has a parent and
      the user can see what it is talking about. }
    OfferRecovery;
  end;
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
  if (ActiveBook = nil) or (ActiveBook.ActivePage = nil) then Exit;
  Result := TabOnPage(ActiveBook.ActivePage);
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
  Sheet := ActiveBook.AddTabSheet;
  Result := TLedTab.CreateForDocument(Self, ADoc);
  Result.Parent := Sheet;
  Result.Sheet := Sheet;
  ADoc.OnChanged := @DocChanged;
  Result.ActiveView.OnStatusChange := @ViewStatusChange;
  Result.ActiveView.OnMouseWheel := @ViewMouseWheel;
  Result.ViewPopupMenu := PopupEditor;
  RefreshTabCaption(Result);
  ActiveBook.ActivePage := Sheet;
  { During FormCreate the window is not visible yet, so this cannot succeed
    and must not be allowed to raise; FormShow focuses the editor once the
    window is up. }
  LedTryFocus(Result.ActiveView);
  UpdateStatusBar;
end;

procedure TLedMainForm.RefreshTabCaption(ATab: TLedTab);
var
  S: string;
begin
  if (ATab = nil) or (ATab.Sheet = nil) then Exit;
  S := ATab.Document.DisplayName;
  if ATab.Document.Modified then
  begin
    S := '*' + S;
    ATab.Sheet.ImageIndex := LedIconIndex('docmodified');
  end
  else
    ATab.Sheet.ImageIndex := LedIconIndex('doc');
  ATab.Sheet.Caption := S;
end;

procedure TLedMainForm.DocChanged(ADoc: TLedDocument);
var
  i: Integer;
  Tab: TLedTab;
  Tabs: TFPList;
begin
  Tabs := TFPList.Create;
  try
    CollectTabs(Tabs);
    for i := 0 to Tabs.Count - 1 do
    begin
      Tab := TLedTab(Tabs[i]);
      if Tab.Document = ADoc then
        RefreshTabCaption(Tab);
    end;
  finally
    Tabs.Free;
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
  { A pane closed with the header's own close button never comes through
    TogglePane, so the rail is reconciled here rather than trusted to be
    told. }
  FDock.RefreshRails;

  { medit enables these only when there is more than one tab, because
    splitting a window to move its only document into the empty half is not a
    thing anyone means to do.  Putting the halves back together stays
    available whenever they are apart. }
  actSplitNotebook.Enabled := NotebookSplit or (TabCount > 1);
  actSplitNotebook.Checked := NotebookSplit;
  actFocusOtherNotebook.Enabled := NotebookSplit;
  actMoveToNotebook.Enabled := NotebookSplit or (TabCount > 1);

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
begin
  if ActiveTab = nil then Exit;
  if not ConfirmClose(ActiveTab.Document) then Exit;
  CloseActiveTab(True);
end;

{ Closes the current tab, having already agreed with the user that it may go.
  AReplace opens a fresh untitled document when the last tab is closed, which
  is right for File / Close but wrong in the middle of a Close All run. }
procedure TLedMainForm.CloseActiveTab(AReplace: Boolean);
var
  Tab: TLedTab;
  Sheet: TTabSheet;
  Doc: TLedDocument;
begin
  Tab := ActiveTab;
  if Tab = nil then Exit;
  Doc := Tab.Document;

  Sheet := Tab.Sheet;
  Tab.Free;          // detaches its views from the document
  Sheet.Free;
  if Doc.ViewCount = 0 then
    FDocs.CloseDocument(Doc);

  if AReplace and (FBook.PageCount = 0) then
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
  { Reaching here is what "clean exit" means, so the journal goes: whatever
    was unsaved has now been either saved or knowingly discarded by the user
    through the close-confirmation above.  This is also what makes a
    non-empty recovery directory at the next startup unambiguous. }
  if FRecovery <> nil then
    FRecovery.Clear;
  if FRecoveryTimer <> nil then
    FRecoveryTimer.Enabled := False;

  { The pane layout is saved whatever the session setting says: where the
    panes sit is part of the window, not part of the documents in it. }
  FDock.SaveLayout(LedConfigFile('layout.xml'));
  FRecent.Save;
  if LedPrefs.Dirty then
    LedPrefs.Save;
end;


{ ---- File ------------------------------------------------------------- }

procedure TLedMainForm.actNewWindowExecute(Sender: TObject);
var
  W: TLedMainForm;
begin
  { Each window owns its own documents.  Sharing them across windows is what
    medit did and it is the reason its document manager is a singleton; here
    a second window is simply a second editor, which is easier to reason
    about and covers what the menu item is actually used for. }
  if Silent then Exit;
  W := TLedMainForm.Create(Application);
  W.Show;
end;

procedure TLedMainForm.actCloseAllExecute(Sender: TObject);
begin
  while FBook.PageCount > 0 do
  begin
    FBook.ActivePageIndex := FBook.PageCount - 1;
    if ActiveTab = nil then Break;
    { A cancelled save prompt stops the whole run, as it does in medit. }
    if not ConfirmClose(ActiveTab.Document) then Exit;
    CloseActiveTab(False);
  end;
  if FBook.PageCount = 0 then actNewExecute(nil);
end;

procedure TLedMainForm.miReopenEncodingClick(Sender: TObject);
begin
  PopulateReopenMenu;
end;

procedure TLedMainForm.PopulateReopenMenu;
var
  i: Integer;
  Item: TMenuItem;
  Names: TStringList;
begin
  ClearMenu(miReopenEncoding);
  Names := TStringList.Create;
  try
    GetSupportedEncodings(Names);
    for i := 0 to Names.Count - 1 do
    begin
      Item := TMenuItem.Create(miReopenEncoding);
      Item.Caption := Names[i];
      Item.Hint := Names[i];
      Item.OnClick := @ReopenEncodingItemClick;
      miReopenEncoding.Add(Item);
    end;
  finally
    Names.Free;
  end;
  miReopenEncoding.Enabled := (ActiveTab <> nil) and
    (ActiveTab.Document.FileName <> '');
end;

procedure TLedMainForm.ReopenEncodingItemClick(Sender: TObject);
var
  Doc: TLedDocument;
  Enc: string;
begin
  if ActiveTab = nil then Exit;
  Doc := ActiveTab.Document;
  if Doc.FileName = '' then Exit;
  if Doc.Modified and
     not Confirm('Reopening discards unsaved changes.  Continue?', False) then
    Exit;
  Enc := LedNormaliseEncoding(TMenuItem(Sender).Hint);
  try
    Doc.Reload(Enc);
  except
    on E: Exception do ReportError('Could not reopen: ' + E.Message);
  end;
  UpdateStatusBar;
end;

procedure TLedMainForm.actReopenEncodingExecute(Sender: TObject);
begin
  { The action exists so the id matches medit's; the work is in the submenu. }
  PopulateReopenMenu;
end;

procedure TLedMainForm.actPageSetupExecute(Sender: TObject);
begin
  if Silent then Exit;
  LedPageSetup(Self);
end;

procedure TLedMainForm.actPrintPdfExecute(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  if (Silent) or (ActiveTab = nil) then Exit;
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := 'Export as PDF';
    Dlg.Filter := 'PDF files|*.pdf|All files|*';
    Dlg.DefaultExt := '.pdf';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    Dlg.FileName := ChangeFileExt(ExtractFileName(
      ActiveTab.Document.DisplayName), '.pdf');
    if not Dlg.Execute then Exit;
    try
      LedExportPdf(ActiveView, ActiveTab.Document.DisplayName, Dlg.FileName);
    except
      on E: Exception do ReportError('Could not write the PDF: ' + E.Message);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TLedMainForm.actExportHtmlExecute(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  if (Silent) or (ActiveTab = nil) then Exit;
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := 'Export as HTML';
    Dlg.Filter := 'HTML files|*.html;*.htm|All files|*';
    Dlg.DefaultExt := '.html';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    Dlg.FileName := ChangeFileExt(ExtractFileName(
      ActiveTab.Document.DisplayName), '.html');
    if not Dlg.Execute then Exit;
    try
      LedExportHtml(ActiveView, ActiveTab.Document.DisplayName, Dlg.FileName);
    except
      on E: Exception do ReportError('Could not write the HTML: ' + E.Message);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ---- Edit ------------------------------------------------------------- }

procedure TLedMainForm.actDeleteExecute(Sender: TObject);
begin
  if CurrentView = nil then Exit;
  if CurrentView.SelAvail then
    CurrentView.ClearSelection
  else
    CurrentView.CommandProcessor(ecDeleteChar, #0, nil);
end;

procedure TLedMainForm.actStripTrailingExecute(Sender: TObject);
begin
  if CurrentView <> nil then LedStripTrailingSpace(CurrentView);
end;

{ ---- Search ----------------------------------------------------------- }

procedure TLedMainForm.FindWordAtCursor(ABackwards: Boolean);
var
  V: TLedEdit;
  Word: string;
  Saved: Boolean;
begin
  V := SearchView;
  if V = nil then Exit;
  if V.SelAvail then
    Word := V.SelText
  else
    Word := V.GetWordAtRowCol(V.LogicalCaretXY);
  if Word = '' then Exit;

  FSearch.SearchText := Word;
  FSearch.RememberSearch(Word);
  Saved := FSearch.Backwards;
  FSearch.Backwards := ABackwards;
  try
    LedFindNext(V, FSearch, False);
  finally
    FSearch.Backwards := Saved;
  end;
  UpdateStatusBar;
end;

procedure TLedMainForm.actFindCurrentExecute(Sender: TObject);
begin
  FindWordAtCursor(False);
end;

procedure TLedMainForm.actFindCurrentBackExecute(Sender: TObject);
begin
  FindWordAtCursor(True);
end;

{ ---- Window ----------------------------------------------------------- }

procedure TLedMainForm.actPrevTabExecute(Sender: TObject);
begin
  if FBook.PageCount < 2 then Exit;
  if FBook.ActivePageIndex = 0 then
    FBook.ActivePageIndex := FBook.PageCount - 1
  else
    FBook.ActivePageIndex := FBook.ActivePageIndex - 1;
  BookChange(nil);
end;

procedure TLedMainForm.actNextTabExecute(Sender: TObject);
begin
  if FBook.PageCount < 2 then Exit;
  if FBook.ActivePageIndex = FBook.PageCount - 1 then
    FBook.ActivePageIndex := 0
  else
    FBook.ActivePageIndex := FBook.ActivePageIndex + 1;
  BookChange(nil);
end;

procedure TLedMainForm.miDocListClick(Sender: TObject);
begin
  PopulateDocMenu;
end;

procedure TLedMainForm.PopulateDocMenu;
var
  i: Integer;
  Item: TMenuItem;
  Tab: TLedTab;
begin
  ClearMenu(miDocList);
  for i := 0 to FBook.PageCount - 1 do
  begin
    Tab := TabOnPage(i);
    if Tab = nil then Continue;
    Item := TMenuItem.Create(miDocList);
    Item.Caption := Tab.Document.DisplayName;
    if Tab.Document.Modified then Item.Caption := Item.Caption + ' *';
    Item.Tag := i;
    Item.RadioItem := True;
    Item.Checked := i = FBook.ActivePageIndex;
    Item.OnClick := @DocItemClick;
    miDocList.Add(Item);
  end;
  miDocList.Enabled := miDocList.Count > 0;
  if miDocList.Count = 0 then miDocList.Caption := '(no documents)';
end;

procedure TLedMainForm.DocItemClick(Sender: TObject);
begin
  FBook.ActivePageIndex := TMenuItem(Sender).Tag;
  BookChange(nil);
end;

function TLedMainForm.TabOnPage(AIndex: Integer): TLedTab;
var
  j: Integer;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex >= FBook.PageCount) then Exit;
  for j := 0 to FBook.Pages[AIndex].ControlCount - 1 do
    if FBook.Pages[AIndex].Controls[j] is TLedTab then
      Exit(TLedTab(FBook.Pages[AIndex].Controls[j]));
end;

{ ---- View ------------------------------------------------------------- }

procedure TLedMainForm.actFocusDocExecute(Sender: TObject);
begin
  LedTryFocus(ActiveView);
end;

procedure TLedMainForm.actMoveToSplitExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  { With one notebook there is no other notebook to move to, so this does
    what the name promises within the tab: move the caret to the next view,
    splitting first if there is only one. }
  Tab := ActiveTab;
  if Tab = nil then Exit;
  if Tab.ViewCount < 2 then
    Tab.SplitView(False);
  Tab.CycleViews;
end;

{ The way back from a layout that dragging has made unusable.  AnchorDocking
  will happily leave a pane somewhere unreachable and offers no route back,
  so this closes every pane, redocks the editor and throws the saved layout
  away -- the state of a first run. }
procedure TLedMainForm.actResetLayoutExecute(Sender: TObject);
begin
  if Silent then Exit;
  if not Confirm('Close every pane and return to the default layout?', False)
    then Exit;
  FDock.ResetLayout(LedConfigFile('layout.xml'));
  UpdateStatusBar;
end;

procedure TLedMainForm.actShowToolbarExecute(Sender: TObject);
begin
  ToolBar1.Visible := not ToolBar1.Visible;
  actShowToolbar.Checked := ToolBar1.Visible;
  LedPrefs.SetBool('Editor/show_toolbar', ToolBar1.Visible);
end;

procedure TLedMainForm.actToggleBrowserExecute(Sender: TObject);
begin
  FDock.ShowPane('files');
  FDock.EdgeVisible[ledLeft] := True;
end;

{ ---- Tools ------------------------------------------------------------ }

procedure TLedMainForm.actSplitTermHExecute(Sender: TObject);
begin
  actToggleTerminalExecute(nil);
  if FTerminal = nil then Exit;
  FTerminal.Split(False);
  LedTryFocus(FTerminal.Active);
end;

procedure TLedMainForm.actSplitTermVExecute(Sender: TObject);
begin
  actToggleTerminalExecute(nil);
  if FTerminal = nil then Exit;
  FTerminal.Split(True);
  LedTryFocus(FTerminal.Active);
end;

{ ---- Help ------------------------------------------------------------- }

procedure TLedMainForm.actHelpExecute(Sender: TObject);
begin
  if Silent then Exit;
  ShowMessage(
    'led ' + LedVersion + ' -- a light editor.' + LineEnding + LineEnding +
    'Keyboard shortcuts are listed under Edit / Configure Shortcuts,' +
    LineEnding +
    'and every one of them can be changed there.' + LineEnding + LineEnding +
    'Documentation lives in README.md next to the program.');
end;

procedure TLedMainForm.actReportBugExecute(Sender: TObject);
begin
  if Silent then Exit;
  ShowMessage(
    'Please report bugs with:' + LineEnding + LineEnding +
    '  led version:  ' + LedVersion + LineEnding +
    '  platform:     ' + {$I %FPCTARGETOS%} + '-' + {$I %FPCTARGETCPU%} +
      LineEnding +
    '  widgetset:    ' + LedWidgetSetName + LineEnding + LineEnding +
    'and the steps that reproduce it.');
end;

procedure TLedMainForm.actAboutExecute(Sender: TObject);
begin
  if Silent then Exit;
  ShowMessage(
    'led ' + LedVersion + LineEnding + LineEnding +
    'A light editor, in the shape of medit.' + LineEnding +
    'Free Pascal ' + {$I %FPCVERSION%} + ', Lazarus LCL, SynEdit.' +
    LineEnding + LineEnding +
    'Widgetset: ' + LedWidgetSetName);
end;

{ ---- The context menus ------------------------------------------------ }

procedure TLedMainForm.PopupEditorPopup(Sender: TObject);
var
  V: TLedEdit;
  HasSel: Boolean;
begin
  V := CurrentView;
  HasSel := (V <> nil) and V.SelAvail;
  mcUndo.Enabled := (V <> nil) and V.CanUndo;
  mcRedo.Enabled := (V <> nil) and V.CanRedo;
  mcCut.Enabled := HasSel;
  mcCopy.Enabled := HasSel;
  mcDelete.Enabled := HasSel;
  mcPaste.Enabled := V <> nil;
  mcSelectAll.Enabled := (V <> nil) and (V.Lines.Count > 0);
  { Comment markers come from the grammar, so a language without them should
    not offer the item at all. }
  mcComment.Enabled := actComment.Enabled;
  mcUncomment.Enabled := actUncomment.Enabled;
  mcToggleFold.Enabled := actToggleFold.Enabled;
  PopulateContextTools;
end;

procedure TLedMainForm.PopulateContextTools;
var
  i, Shown: Integer;
  Item: TMenuItem;
  Tool: TLedTool;
  Doc: TLedDocument;
  LangId, FileName: string;
begin
  ClearMenu(miCtxTools);
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
    { Only the tools that asked to be here, and only where they apply. }
    if Tool.Place <> ltpContext then Continue;
    if not Tool.AppliesTo(LangId, FileName) then Continue;
    Item := TMenuItem.Create(miCtxTools);
    Item.Caption := Tool.Name;
    Item.Hint := Tool.Id;
    Item.Enabled := LedToolCanRun(Tool, Doc) and not FRunner.Running;
    Item.OnClick := @ToolItemClick;
    miCtxTools.Add(Item);
    Inc(Shown);
  end;

  miCtxTools.Caption := 'Tools';
  miCtxTools.Enabled := Shown > 0;
  if Shown = 0 then miCtxTools.Caption := 'Tools  (none apply here)';
end;

procedure TLedMainForm.PopupTabPopup(Sender: TObject);
var
  Doc: TLedDocument;
begin
  if ActiveTab = nil then Exit;
  Doc := ActiveTab.Document;
  miTabCloseOthers.Enabled := FBook.PageCount > 1;
  miTabCopyPath.Enabled := Doc.FileName <> '';
  miTabOpenFolder.Enabled := Doc.FileName <> '';
  mtReload.Enabled := Doc.FileName <> '';
end;

procedure TLedMainForm.miTabCloseOthersClick(Sender: TObject);
var
  Keep: TLedTab;
begin
  Keep := ActiveTab;
  if Keep = nil then Exit;
  while FBook.PageCount > 1 do
  begin
    if TabOnPage(0) = Keep then
      FBook.ActivePageIndex := 1
    else
      FBook.ActivePageIndex := 0;
    if ActiveTab = nil then Break;
    if not ConfirmClose(ActiveTab.Document) then Exit;
    CloseActiveTab(False);
  end;
end;

procedure TLedMainForm.miTabCopyPathClick(Sender: TObject);
begin
  if (ActiveTab <> nil) and (ActiveTab.Document.FileName <> '') then
    Clipboard.AsText := ActiveTab.Document.FileName;
end;

procedure TLedMainForm.miTabOpenFolderClick(Sender: TObject);
begin
  if (ActiveTab <> nil) and (ActiveTab.Document.FileName <> '') then
    OpenDocument(ExtractFilePath(ActiveTab.Document.FileName));
end;

end.
