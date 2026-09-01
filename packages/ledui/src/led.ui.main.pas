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
  LConvEncoding,
  Led.Core.Types, Led.Core.FileIO, Led.Core.Prefs, Led.Core.Session,
  Led.Core.Config, Led.Core.Encodings,
  Led.Syn.Languages, Led.Syn.Theme, Led.Syn.Factory,
  Led.UI.Dock, Led.UI.Document, Led.UI.Tab, Led.UI.Edit;

type
  TLedMainForm = class(TForm)
    ActionList1: TActionList;
    actNew: TAction;
    actOpen: TAction;
    actSave: TAction;
    actSaveAs: TAction;
    actCloseTab: TAction;
    actQuit: TAction;
    actSplitSideBySide: TAction;
    actSplitStacked: TAction;
    actUnsplit: TAction;
    actCycleViews: TAction;
    actToggleLeftPane: TAction;
    actToggleBottomPane: TAction;
    actReload: TAction;
    MainMenu1: TMainMenu;
    mnuFile: TMenuItem;
    miNew: TMenuItem;
    miOpen: TMenuItem;
    miSep1: TMenuItem;
    miSave: TMenuItem;
    miSaveAs: TMenuItem;
    miOpenRecent: TMenuItem;
    miReload: TMenuItem;
    miSep2: TMenuItem;
    miCloseTab: TMenuItem;
    miQuit: TMenuItem;
    mnuDocument: TMenuItem;
    miLanguage: TMenuItem;
    miTheme: TMenuItem;
    mnuView: TMenuItem;
    miSplitSideBySide: TMenuItem;
    miSplitStacked: TMenuItem;
    miUnsplit: TMenuItem;
    miCycleViews: TMenuItem;
    miSep3: TMenuItem;
    miToggleLeftPane: TMenuItem;
    miToggleBottomPane: TMenuItem;
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
  private
    FDocs: TLedDocuments;
    FDock: TLedDockHost;
    FBook: TPageControl;
    FRecent: TLedRecentFiles;
    FCheckingDisk: Boolean;
    procedure PopulateRecentMenu;
    procedure RecentItemClick(Sender: TObject);
    procedure PopulateLanguageMenu;
    procedure LanguageItemClick(Sender: TObject);
    procedure PopulateThemeMenu;
    procedure ThemeItemClick(Sender: TObject);
    procedure SaveSession;
    function RestoreSession: Boolean;
    procedure CheckExternalChanges;
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
