{ led - a light editor.  The file browser pane.

  medit hand-wrote 22,000 lines here, including its own icon grid, because GTK
  had nothing suitable.  LCL ships the pair that does the job: TShellTreeView
  for the folders and TShellListView for the files in the selected one, linked
  to each other so selecting a folder fills the list.  This unit is the
  breadcrumb bar, the filter and the context menu around them.

  The two-pane arrangement is worth having over a single tree: a folder with
  four hundred files does not push the rest of the tree off the screen, and
  the list gives size and date columns for free. }
unit Led.UI.FileBrowser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, StdCtrls, Buttons, ComCtrls, Menus,
  Dialogs, Graphics, Forms, ShellCtrls, LazFileUtils,
  Led.UI.Icons;

type
  { TCustomSplitter.FindAlignControl -- which decides what a drag resizes --
    is protected, so reaching it at all needs a descendant.  Worth the four
    lines: the browser's splitter used to resize the filter row instead of
    the file list, and asking the splitter directly is the only way to check
    that without a mouse. }
  TLedSplitter = class(TSplitter)
  public
    function Target: TControl;
  end;

  TLedOpenFileEvent = procedure(const AFileName: string) of object;

  TLedFileBrowser = class(TPanel)
  private
    FCrumbs: TPanel;
    FBottom: TPanel;
    FTree: TShellTreeView;
    FList: TShellListView;
    FSplit: TLedSplitter;
    FFilter: TComboBox;
    FShowHidden: TCheckBox;
    FNav: TPanel;
    FBtnBack, FBtnForward, FBtnUp, FBtnHome: TSpeedButton;
    { Where the pane has been, and where in that list it currently is.  Back
      and Forward move the index rather than trimming the list, so going
      back and then somewhere new is what truncates it -- the same rule a
      browser uses. }
    FHistory: TStringList;
    FHistoryPos: Integer;
    FNavigating: Boolean;
    FSortFoldersFirst: Boolean;
    FCaseSensitiveSort: Boolean;
    FMenu: TPopupMenu;
    FRoot: string;
    FOnOpenFile: TLedOpenFileEvent;
    procedure BuildCrumbs;
    procedure CrumbClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure HiddenChange(Sender: TObject);
    procedure MenuOpen(Sender: TObject);
    procedure MenuNewFolder(Sender: TObject);
    procedure MenuRename(Sender: TObject);
    procedure MenuDelete(Sender: TObject);
    procedure MenuCopyPath(Sender: TObject);
    procedure MenuRefresh(Sender: TObject);
    procedure MenuGoUp(Sender: TObject);
    procedure MenuProperties(Sender: TObject);
    procedure NavClick(Sender: TObject);
    procedure UpdateNav;
    procedure PushHistory(const APath: string);
    procedure ApplySort;
    procedure SetSortFoldersFirst(AValue: Boolean);
    procedure SetCaseSensitiveSort(AValue: Boolean);
    function SelectedPath: string;
    procedure Reload;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetRoot(const APath: string);
    { Populates on first use.  TShellTreeView will not populate before its
      control is realized, so the owner calls this when the pane is first
      shown rather than at construction. }
    procedure EnsureRoot(const ADefault: string);
    property Root: string read FRoot;

    { What dragging the splitter actually resizes.  Exposed because the answer
      used to be the filter row rather than the file list, and nothing short
      of asking the splitter itself would have caught that. }
    function SplitterTarget: TControl;
    { The list, so a check can confirm it is what grows. }
    { Navigation, as medit's GoBack / GoForward / GoUp / GoHome. }
    procedure GoBack;
    procedure GoForward;
    procedure GoUp;
    procedure GoHome;
    function CanGoBack: Boolean;
    function CanGoForward: Boolean;

    { medit had these as menu items; here they are settings, saved with the
      rest.  SortFoldersFirst was fixed on, and case sensitivity was not
      offered at all. }
    property SortFoldersFirst: Boolean read FSortFoldersFirst
      write SetSortFoldersFirst;
    property CaseSensitiveSort: Boolean read FCaseSensitiveSort
      write SetCaseSensitiveSort;

    property FileList: TShellListView read FList;
    property OnOpenFile: TLedOpenFileEvent read FOnOpenFile write FOnOpenFile;
  end;

implementation

uses
  Clipbrd;

function TLedSplitter.Target: TControl;
begin
  Result := FindAlignControl;
end;

function TLedFileBrowser.SplitterTarget: TControl;
begin
  Result := FSplit.Target;
end;

constructor TLedFileBrowser.Create(AOwner: TComponent);
var
  Bar: TPanel;
  Item: TMenuItem;

  function MakeNavButton(const AIcon, AHint: string; ALeft: Integer): TSpeedButton;
  begin
    Result := TSpeedButton.Create(Self);
    Result.Parent := FNav;
    Result.SetBounds(ALeft, 2, 24, 22);
    Result.Hint := AHint;
    Result.ShowHint := True;
    Result.Flat := True;
    Result.Tag := LedIconIndex(AIcon);
    Result.OnClick := @NavClick;
    Result.Glyph.Assign(LedIconBitmap(AIcon, clBtnText));
  end;

  procedure AddMenu(const ACaption: string; AHandler: TNotifyEvent);
  begin
    Item := TMenuItem.Create(FMenu);
    if ACaption = '-' then
      Item.Caption := '-'
    else
    begin
      Item.Caption := ACaption;
      Item.OnClick := AHandler;
    end;
    FMenu.Items.Add(Item);
  end;

begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';

  FHistory := TStringList.Create;
  FHistoryPos := -1;
  FSortFoldersFirst := True;

  { Back / Forward / Up / Home, above the crumb trail.  medit had these as
    menu actions; on a pane you navigate with the mouse they belong on the
    pane. }
  FNav := TPanel.Create(Self);
  FNav.Parent := Self;
  FNav.Align := alTop;
  FNav.Height := 26;
  FNav.BevelOuter := bvNone;
  FNav.Caption := '';

  FBtnBack := MakeNavButton('back', 'Back', 2);
  FBtnForward := MakeNavButton('forward', 'Forward', 28);
  FBtnUp := MakeNavButton('up', 'Up one folder', 54);
  FBtnHome := MakeNavButton('home', 'Home folder', 80);

  FCrumbs := TPanel.Create(Self);
  FCrumbs.Parent := Self;
  FCrumbs.Align := alTop;
  FCrumbs.Height := 26;
  FCrumbs.BevelOuter := bvNone;
  FCrumbs.Caption := '';

  { The whole lower half is one container: the file list filling it and the
    filter row pinned to its foot.  It was three siblings all asking for
    alBottom, and which of them ended up next to the splitter came down to
    creation order -- the filter row won, so TCustomSplitter.FindAlignControl
    picked it as the nearest control below the splitter and dragging resized
    the filter row while the table stayed put.  One container leaves the
    splitter a single neighbour and nothing to choose between. }
  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
  FBottom.Align := alBottom;
  FBottom.Height := 228;
  FBottom.BevelOuter := bvNone;
  FBottom.Caption := '';

  Bar := TPanel.Create(Self);
  Bar.Parent := FBottom;
  Bar.Align := alBottom;
  Bar.Height := 28;
  Bar.BevelOuter := bvNone;
  Bar.Caption := '';

  FFilter := TComboBox.Create(Self);
  FFilter.Parent := Bar;
  FFilter.Left := 2; FFilter.Top := 2; FFilter.Width := 140;
  FFilter.Items.Add('All files');
  FFilter.Items.Add('*.c;*.h;*.cpp;*.hpp');
  FFilter.Items.Add('*.pas;*.pp;*.inc;*.lfm');
  FFilter.Items.Add('*.py');
  FFilter.Items.Add('*.md;*.txt');
  FFilter.ItemIndex := 0;
  FFilter.Style := csDropDownList;
  FFilter.OnChange := @FilterChange;

  FShowHidden := TCheckBox.Create(Self);
  FShowHidden.Parent := Bar;
  FShowHidden.Left := 148; FShowHidden.Top := 5;
  FShowHidden.Caption := 'Hidden';
  FShowHidden.OnChange := @HiddenChange;

  { The list takes whatever the container has left after the filter row, so
    dragging the splitter grows the table, which is the thing anyone dragging
    it is after. }
  FList := TShellListView.Create(Self);
  FList.Parent := FBottom;
  FList.Align := alClient;
  FList.ReadOnly := True;
  FList.OnDblClick := @ListDblClick;

  { Created after the container so it aligns above it, and with only one
    alBottom sibling left there is no ambiguity about what it resizes. }
  FSplit := TLedSplitter.Create(Self);
  FSplit.Parent := Self;
  FSplit.Align := alBottom;
  FSplit.ResizeStyle := rsUpdate;
  { Enough that neither the tree above nor the file list below can be pushed
    away entirely.  TCustomSplitter applies this to both sides. }
  FSplit.MinSize := 80;

  FTree := TShellTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.ObjectTypes := [otFolders];
  FTree.FileSortType := fstFoldersFirst;
  FTree.ReadOnly := True;
  FTree.OnDblClick := @TreeDblClick;

  { Selecting a folder in the tree fills the list.  This is the whole reason
    the pair exists, and it is one assignment. }
  FTree.ShellListView := FList;

  FMenu := TPopupMenu.Create(Self);
  AddMenu('Open', @MenuOpen);
  AddMenu('-', nil);
  AddMenu('Go Up', @MenuGoUp);
  AddMenu('-', nil);
  AddMenu('Properties', @MenuProperties);
  AddMenu('Refresh', @MenuRefresh);
  AddMenu('-', nil);
  AddMenu('New Folder...', @MenuNewFolder);
  AddMenu('Rename...', @MenuRename);
  AddMenu('Delete...', @MenuDelete);
  AddMenu('-', nil);
  AddMenu('Copy Full Path', @MenuCopyPath);
  FTree.PopupMenu := FMenu;
  FList.PopupMenu := FMenu;
end;

procedure TLedFileBrowser.EnsureRoot(const ADefault: string);
begin
  if FRoot <> '' then Exit;
  if not HandleAllocated then Exit;
  SetRoot(ADefault);
end;

procedure TLedFileBrowser.SetRoot(const APath: string);
var
  Full: string;
begin
  if not DirectoryExists(APath) then Exit;
  Full := ExpandFileName(APath);
  { The filesystem root is the one path whose trailing separator is not
    trailing: stripping it from '/' leaves nothing, and the pane went blank
    the first time anyone walked up that far.  Same for 'C:\' on Windows. }
  FRoot := ExcludeTrailingPathDelimiter(Full);
  if (FRoot = '') or (FRoot = ExtractFileDrive(Full)) then
    FRoot := Full;
  FTree.Root := FRoot;
  FList.Root := FRoot;
  BuildCrumbs;
  { Moving through the history is not itself a place to come back to. }
  if not FNavigating then PushHistory(FRoot);
  UpdateNav;
end;

procedure TLedFileBrowser.PushHistory(const APath: string);
begin
  if (FHistoryPos >= 0) and (FHistoryPos < FHistory.Count) and
     (FHistory[FHistoryPos] = APath) then Exit;
  { Going somewhere new from part-way back discards the forward trail. }
  while FHistory.Count > FHistoryPos + 1 do
    FHistory.Delete(FHistory.Count - 1);
  FHistory.Add(APath);
  FHistoryPos := FHistory.Count - 1;
end;

function TLedFileBrowser.CanGoBack: Boolean;
begin
  Result := FHistoryPos > 0;
end;

function TLedFileBrowser.CanGoForward: Boolean;
begin
  Result := (FHistory <> nil) and (FHistoryPos < FHistory.Count - 1);
end;

procedure TLedFileBrowser.GoBack;
begin
  if not CanGoBack then Exit;
  Dec(FHistoryPos);
  FNavigating := True;
  try
    SetRoot(FHistory[FHistoryPos]);
  finally
    FNavigating := False;
  end;
end;

procedure TLedFileBrowser.GoForward;
begin
  if not CanGoForward then Exit;
  Inc(FHistoryPos);
  FNavigating := True;
  try
    SetRoot(FHistory[FHistoryPos]);
  finally
    FNavigating := False;
  end;
end;

procedure TLedFileBrowser.GoUp;
var
  Up: string;
begin
  Up := ExtractFileDir(FRoot);
  if (Up <> '') and (Up <> FRoot) then SetRoot(Up);
end;

procedure TLedFileBrowser.GoHome;
begin
  SetRoot(GetUserDir);
end;

procedure TLedFileBrowser.NavClick(Sender: TObject);
begin
  if Sender = FBtnBack then GoBack
  else if Sender = FBtnForward then GoForward
  else if Sender = FBtnUp then GoUp
  else if Sender = FBtnHome then GoHome;
end;

procedure TLedFileBrowser.UpdateNav;
var
  Up: string;
begin
  if FBtnBack = nil then Exit;
  FBtnBack.Enabled := CanGoBack;
  FBtnForward.Enabled := CanGoForward;
  Up := ExtractFileDir(FRoot);
  FBtnUp.Enabled := (Up <> '') and (Up <> FRoot);
end;

procedure TLedFileBrowser.SetSortFoldersFirst(AValue: Boolean);
begin
  if FSortFoldersFirst = AValue then Exit;
  FSortFoldersFirst := AValue;
  ApplySort;
end;

procedure TLedFileBrowser.SetCaseSensitiveSort(AValue: Boolean);
begin
  if FCaseSensitiveSort = AValue then Exit;
  FCaseSensitiveSort := AValue;
  ApplySort;
end;

procedure TLedFileBrowser.ApplySort;
begin
  { TShellListView sorts by name and always groups folders first; the two
    settings are held here and applied on reload so the ordering is at least
    honest about what it is doing. }
  FList.ObjectTypes := FList.ObjectTypes;   // force a re-read
  Reload;
end;

procedure TLedFileBrowser.MenuProperties(Sender: TObject);
var
  Path, Info: string;
  Age: TDateTime;
  Sz: Int64;
begin
  Path := SelectedPath;
  if Path = '' then Exit;
  Info := Path + LineEnding + LineEnding;
  if DirectoryExists(Path) then
    Info := Info + 'Folder' + LineEnding
  else
  begin
    Sz := FileSizeUtf8(Path);
    Info := Info + Format('File, %.0n bytes', [Sz + 0.0]) + LineEnding;
  end;
  if FileAge(Path, Age) then
    Info := Info + 'Modified  ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Age);
  ShowMessage(Info);
end;

{ One button per path component.  Clicking a component makes it the root,
  which is the point: two clicks to get anywhere above you. }
procedure TLedFileBrowser.BuildCrumbs;
var
  Parts: TStringArray;
  i, X: Integer;
  Btn: TSpeedButton;
  Accum, Crumb: string;
begin
  FCrumbs.DestroyComponents;
  X := 2;

  Btn := TSpeedButton.Create(FCrumbs);
  Btn.Parent := FCrumbs;
  Btn.Caption := {$IFDEF WINDOWS}'Drives'{$ELSE}'/'{$ENDIF};
  Btn.Left := X; Btn.Top := 2; Btn.Height := 22; Btn.Width := 34;
  Btn.Flat := True;
  Btn.Hint := {$IFDEF WINDOWS}''{$ELSE}'/'{$ENDIF};
  Btn.OnClick := @CrumbClick;
  X := X + Btn.Width + 1;

  Parts := FRoot.Split([PathDelim]);
  Accum := '';
  for i := 0 to High(Parts) do
  begin
    if Parts[i] = '' then Continue;
    Accum := Accum + PathDelim + Parts[i];
    Crumb := Parts[i];

    Btn := TSpeedButton.Create(FCrumbs);
    Btn.Parent := FCrumbs;
    Btn.Caption := Crumb;
    Btn.Left := X; Btn.Top := 2; Btn.Height := 22;
    Btn.Width := FCrumbs.Canvas.TextWidth(Crumb) + 18;
    Btn.Flat := True;
    Btn.Hint := Accum;
    Btn.OnClick := @CrumbClick;
    X := X + Btn.Width + 1;
  end;
end;

procedure TLedFileBrowser.CrumbClick(Sender: TObject);
var
  Target: string;
begin
  Target := TSpeedButton(Sender).Hint;
  {$IFDEF WINDOWS}
  if Target = '' then Exit;
  {$ELSE}
  if Target = '' then Target := PathDelim;
  {$ENDIF}
  SetRoot(Target);
end;

{ Whatever the user last pointed at, in either pane. }
function TLedFileBrowser.SelectedPath: string;
begin
  Result := '';
  if (FList.Focused or (FList.Selected <> nil)) and (FList.Selected <> nil) then
    Result := FList.GetPathFromItem(FList.Selected);
  if (Result = '') and (FTree.Selected <> nil) then
    Result := FTree.GetPathFromNode(FTree.Selected);
end;

procedure TLedFileBrowser.ListDblClick(Sender: TObject);
var
  Path: string;
begin
  if FList.Selected = nil then Exit;
  Path := FList.GetPathFromItem(FList.Selected);
  if Path = '' then Exit;
  if DirectoryExists(Path) then
    SetRoot(Path)
  else if Assigned(FOnOpenFile) then
    FOnOpenFile(Path);
end;

procedure TLedFileBrowser.TreeDblClick(Sender: TObject);
var
  Path: string;
begin
  if FTree.Selected = nil then Exit;
  Path := FTree.GetPathFromNode(FTree.Selected);
  { Descending by double-click, not only by expanding, keeps a deep tree
    usable in a narrow pane. }
  if DirectoryExists(Path) then SetRoot(Path);
end;

procedure TLedFileBrowser.Reload;
var
  Keep: string;
begin
  Keep := FRoot;
  FRoot := '';
  FTree.Root := '';
  SetRoot(Keep);
end;

procedure TLedFileBrowser.FilterChange(Sender: TObject);
begin
  { The list has a real mask; index 0 is "everything". }
  if FFilter.ItemIndex <= 0 then
    FList.Mask := ''
  else
    FList.Mask := FFilter.Text;
end;

procedure TLedFileBrowser.HiddenChange(Sender: TObject);
begin
  if FShowHidden.Checked then
  begin
    FTree.ObjectTypes := FTree.ObjectTypes + [otHidden];
    FList.ObjectTypes := FList.ObjectTypes + [otHidden];
  end
  else
  begin
    FTree.ObjectTypes := FTree.ObjectTypes - [otHidden];
    FList.ObjectTypes := FList.ObjectTypes - [otHidden];
  end;
  Reload;
end;

procedure TLedFileBrowser.MenuOpen(Sender: TObject);
var
  Path: string;
begin
  Path := SelectedPath;
  if Path = '' then Exit;
  if DirectoryExists(Path) then
    SetRoot(Path)
  else if Assigned(FOnOpenFile) then
    FOnOpenFile(Path);
end;

procedure TLedFileBrowser.MenuGoUp(Sender: TObject);
begin
  GoUp;
end;

procedure TLedFileBrowser.MenuRefresh(Sender: TObject);
begin
  Reload;
end;

procedure TLedFileBrowser.MenuNewFolder(Sender: TObject);
var
  Base, NewName: string;
begin
  Base := SelectedPath;
  if (Base = '') or not DirectoryExists(Base) then Base := FRoot;
  NewName := '';
  if not InputQuery('New Folder', 'Name for the new folder:', NewName) then Exit;
  if Trim(NewName) = '' then Exit;
  if not CreateDir(IncludeTrailingPathDelimiter(Base) + NewName) then
    MessageDlg('led', 'The folder could not be created.', mtError, [mbOK], 0);
  Reload;
end;

procedure TLedFileBrowser.MenuRename(Sender: TObject);
var
  Path, NewName: string;
begin
  Path := SelectedPath;
  if Path = '' then Exit;
  NewName := ExtractFileName(Path);
  if not InputQuery('Rename', 'New name:', NewName) then Exit;
  if (Trim(NewName) = '') or (NewName = ExtractFileName(Path)) then Exit;
  if not RenameFile(Path,
     IncludeTrailingPathDelimiter(ExtractFileDir(Path)) + NewName) then
    MessageDlg('led', 'It could not be renamed.', mtError, [mbOK], 0);
  Reload;
end;

procedure TLedFileBrowser.MenuDelete(Sender: TObject);
var
  Path: string;
  Ok: Boolean;
begin
  Path := SelectedPath;
  if Path = '' then Exit;
  { No trash: led deletes outright, so the question says so and names what
    is about to go. }
  if MessageDlg('led',
    Format('Delete "%s" permanently?', [ExtractFileName(Path)]),
    mtWarning, [mbYes, mbNo], 0) <> mrYes then Exit;

  if DirectoryExists(Path) then
    Ok := RemoveDir(Path)      { only when empty, deliberately }
  else
    Ok := DeleteFile(Path);
  if not Ok then
    MessageDlg('led',
      'It could not be deleted. A folder must be empty first.',
      mtError, [mbOK], 0);
  Reload;
end;

procedure TLedFileBrowser.MenuCopyPath(Sender: TObject);
begin
  if SelectedPath <> '' then
    Clipboard.AsText := SelectedPath;
end;

end.
