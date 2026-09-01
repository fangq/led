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
  Led.Core.Types, Led.Core.FileIO, Led.Core.Prefs, Led.Core.Session,
  Led.Core.Config, Led.Core.Encodings,
  Led.Syn.Languages, Led.Syn.Theme, Led.Syn.Factory,
  Led.UI.Dock, Led.UI.Document, Led.UI.Tab, Led.UI.Edit, Led.UI.Commands,
  Led.UI.Find;

type
  TLedMainForm = class(TForm)
    ActionList1: TActionList;
    actNew: TAction;
    actOpen: TAction;
    actSave: TAction;
    actSaveAs: TAction;
    actReload: TAction;
    actCloseTab: TAction;
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
    actWrapText: TAction;
    actLineNumbers: TAction;
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
    mi_CloseTab: TMenuItem;
    mi_Quit: TMenuItem;
    mnuEdit: TMenuItem;
    mi_Undo: TMenuItem;
    mi_Redo: TMenuItem;
    miSep3: TMenuItem;
    mi_Cut: TMenuItem;
    mi_Copy: TMenuItem;
    mi_Paste: TMenuItem;
    miSep4: TMenuItem;
    mi_SelectAll: TMenuItem;
    mi_PasteColumn: TMenuItem;
    mi_ClearSelection: TMenuItem;
    miSep5: TMenuItem;
    mi_Indent: TMenuItem;
    mi_Unindent: TMenuItem;
    mi_IndentSpace: TMenuItem;
    mi_UnindentSpace: TMenuItem;
    miSep6: TMenuItem;
    mi_Comment: TMenuItem;
    mi_Uncomment: TMenuItem;
    mnuSearch: TMenuItem;
    mi_Find: TMenuItem;
    mi_Replace: TMenuItem;
    mi_FindNext: TMenuItem;
    mi_FindPrev: TMenuItem;
    mi_QuickFind: TMenuItem;
    miSep7: TMenuItem;
    mi_GotoLine: TMenuItem;
    miSep8: TMenuItem;
    mi_ToggleBracket: TMenuItem;
    mi_SelectToBracket: TMenuItem;
    mnuDocument: TMenuItem;
    miLanguage: TMenuItem;
    miEncoding: TMenuItem;
    miLineEnd: TMenuItem;
    miSep9: TMenuItem;
    mi_ToggleBookmark: TMenuItem;
    mi_NextBookmark: TMenuItem;
    mi_PrevBookmark: TMenuItem;
    mnuView: TMenuItem;
    mi_WrapText: TMenuItem;
    mi_LineNumbers: TMenuItem;
    miSep10: TMenuItem;
    mi_SplitSideBySide: TMenuItem;
    mi_SplitStacked: TMenuItem;
    mi_Unsplit: TMenuItem;
    mi_CycleViews: TMenuItem;
    miSep11: TMenuItem;
    miTheme: TMenuItem;
    miSep12: TMenuItem;
    mi_ToggleLeftPane: TMenuItem;
    mi_ToggleBottomPane: TMenuItem;
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
  private
    FDocs: TLedDocuments;
    FDock: TLedDockHost;
    FBook: TPageControl;
    FRecent: TLedRecentFiles;
    FSearch: TLedSearchState;
    FFindForm: TLedFindForm;
    FFindBar: TLedFindBar;
    FCheckingDisk: Boolean;
    function SearchView: TLedEdit;
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

  FDock := TLedDockHost.Create(Self);
  FDock.Parent := Self;
  FDock.Align := alClient;

  FBook := TPageControl.Create(Self);
  FBook.Parent := FDock.Center;
  FBook.Align := alClient;
  FBook.OnChange := @BookChange;

  { Phase 0 placeholders so the dock edges can be exercised; real panes arrive
    in phases 3 and 5. }
  FDock.AddPane(ledLeft, 'files', 'Files', nil);
  FDock.AddPane(ledBottom, 'output', 'Output', nil);
  FDock.EdgeVisible[ledLeft] := False;
  FDock.EdgeVisible[ledBottom] := False;

  if not RestoreSession then
    actNewExecute(nil);
end;

procedure TLedMainForm.FormDestroy(Sender: TObject);
begin
  FRecent.Free;
  FSearch.Free;
end;

{ --- find and replace ------------------------------------------------------ }

function TLedMainForm.SearchView: TLedEdit;
begin
  Result := ActiveView;
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
  actFind.Enabled := HasDoc;
  actReplace.Enabled := HasDoc;
  actFindNext.Enabled := HasDoc;
  actFindPrev.Enabled := HasDoc;
  actQuickFind.Enabled := HasDoc;
  actToggleBracket.Enabled := HasDoc;
  actSelectToBracket.Enabled := HasDoc;
  actToggleBookmark.Enabled := HasDoc;
  actNextBookmark.Enabled := HasDoc;
  actPrevBookmark.Enabled := HasDoc;
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
