{ led - a lightweight editor.  The file browser pane.

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
    FCrumbWidth: Integer;
    FOnOpenFile: TLedOpenFileEvent;
    procedure BuildCrumbs;
    procedure CrumbClick(Sender: TObject);
    procedure TreeExpanded(Sender: TObject; ANode: TTreeNode);
    procedure NavResize(Sender: TObject);
    procedure SortTree;
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
    { And the tree, so a check can select its root -- which used to raise. }
    property FileTree: TShellTreeView read FTree;

    { The crumb trail, by the numbers: how many buttons it has, and how far
      the last of them reaches.  Exposed because "the breadcrumb bar
      disappeared" has two quite different causes -- no buttons at all, or
      buttons that run off the right-hand edge -- and they need different
      fixes. }
    function CrumbCount: Integer;
    function CrumbsWidth: Integer;
    function CrumbBarWidth: Integer;
    { The glyph on a navigation button, and the button under it.  Exposed
      because the two came apart: the buttons scaled with the pane and the
      glyph stayed at the sixteen pixels the icons are drawn at, which is
      what "huge buttons with tiny icons" was. }
    function NavGlyphSize: Integer;
    function NavButtonSize: Integer;
    property OnOpenFile: TLedOpenFileEvent read FOnOpenFile write FOnOpenFile;
  end;

implementation

uses
  Clipbrd, Led.UI.Dpi;

function TLedSplitter.Target: TControl;
begin
  Result := FindAlignControl;
end;

{ Divides the navigation row between the buttons and the trail, and refits the
  trail when its share of the width changes -- otherwise dragging the pane
  wider leaves components hidden that would now fit, and narrower pushes the
  current folder back off the edge.

  Hung off the row's own OnResize rather than the browser's Resize, which is
  the mistake worth recording: the browser's Resize runs before the alignment
  pass has given FNav its new width, so it divided up the old one and nothing
  came along afterwards to correct it -- the trail simply never appeared. }
procedure TLedFileBrowser.NavResize(Sender: TObject);
var
  Edge: Integer;
begin
  if (FNav = nil) or (FCrumbs = nil) or
     (FBtnHome = nil) or (FBtnBack = nil) then Exit;

  { Measured off the buttons rather than computed, so it stays right whatever
    the sweep scaled them to: past the last one, plus the margin the first one
    was given. }
  Edge := FBtnHome.Left + FBtnHome.Width + FBtnBack.Left;
  if FNav.ClientWidth - Edge < 1 then Exit;
  FCrumbs.SetBounds(Edge, 0, FNav.ClientWidth - Edge, FNav.ClientHeight);

  { The pane roots itself the first time it has real geometry, instead of
    waiting to be told.  Only the two pane toggles told it, so a session that
    restored with the Files pane already open left FRoot empty for the whole
    session: the tree still filled -- the constructor roots that separately --
    but the crumb trail is built from FRoot, so it came up with nothing in it
    every time.  That is what "the breadcrumb bar disappeared" actually was.

    Here rather than in Resize because this runs when the row has been given
    its real width, which is also when the tree's control is realized enough
    for TShellTreeView to populate. }
  if (FRoot = '') and HandleAllocated then
    EnsureRoot(GetCurrentDir)
  else if (FRoot <> '') and (FCrumbs.ClientWidth <> FCrumbWidth) then
    BuildCrumbs;
end;

function TLedFileBrowser.CrumbCount: Integer;
begin
  Result := FCrumbs.ControlCount;
end;

function TLedFileBrowser.CrumbsWidth: Integer;
var
  i: Integer;
  C: TControl;
begin
  Result := 0;
  for i := 0 to FCrumbs.ControlCount - 1 do
  begin
    C := FCrumbs.Controls[i];
    if C.Left + C.Width > Result then Result := C.Left + C.Width;
  end;
end;

function TLedFileBrowser.NavGlyphSize: Integer;
begin
  Result := 0;
  if (FBtnBack <> nil) and (FBtnBack.Glyph <> nil) then
    Result := FBtnBack.Glyph.Height;
end;

function TLedFileBrowser.NavButtonSize: Integer;
begin
  Result := 0;
  if FBtnBack <> nil then Result := FBtnBack.Height;
end;

function TLedFileBrowser.CrumbBarWidth: Integer;
begin
  Result := FCrumbs.ClientWidth;
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
    { Plain numbers, not LedScale96.  The browser is built in FormCreate, so
      the startup sweep still has AutoAdjustLayout to run over it and scales
      these itself -- handing it sizes that were already scaled put the four
      buttons 253 pixels apart where 81 was meant.  Only what is built after
      the sweep, further down, scales its own. }
    Result.SetBounds(ALeft, 2, 20, 20);
    Result.Hint := AHint;
    Result.ShowHint := True;
    Result.Flat := True;
    Result.Tag := LedIconIndex(AIcon);
    Result.OnClick := @NavClick;
    { At the size the button actually is, not the sixteen pixels the icons are
      designed at -- same as the toolbar's image list. }
    Result.Glyph.Assign(LedIconBitmap(AIcon, clBtnText, LedScale96(14)));
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
  FNav.Height := 24;
  FNav.BevelOuter := bvNone;
  FNav.Caption := '';

  FBtnBack := MakeNavButton('back', 'Back', 2);
  FBtnForward := MakeNavButton('forward', 'Forward', 24);
  FBtnUp := MakeNavButton('up', 'Up one folder', 46);
  FBtnHome := MakeNavButton('home', 'Home folder', 68);

  { On the same row as the buttons, to the right of them.  Two rows left an
    empty strip as tall as the buttons sitting between the trail and the
    tree, and the trail wants horizontal room, not vertical.  Its bounds are
    set in Resize, once the row has a width to divide up. }
  FCrumbs := TPanel.Create(Self);
  FCrumbs.Parent := FNav;
  FCrumbs.BevelOuter := bvNone;
  FCrumbs.Caption := '';
  FNav.OnResize := @NavResize;

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
  { Deliberately not scaled, unlike every other size here.  This is not a
    piece of chrome that has to match the display -- it is where the splitter
    starts, before the user drags it somewhere else.  Scaled to 712 on a
    300-PPI target it was taller than a short pane, which left the tree above
    it no height and the splitter no neighbour to resize: SplitterTarget went
    from the file list to nothing at all. }
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
  { Rooted at a real directory before anything else touches it.  With Root
    left empty the LCL populates from GetBasePath, which is '/' on Unix but
    '' on Windows -- and the empty case there enumerates every logical drive
    (shellctrls.pas, PopulateWithBaseFiles), which stalls for as long as the
    slowest of them takes to answer.  A disconnected network mapping is the
    usual culprit.
    First, too, because ObjectTypes and FileSortType each repopulate the
    tree: setting the root last would run those over the drive list. }
  { Before the root, because SetRoot expands the root node as it builds it and
    that expand is the one nothing else will repeat. }
  FTree.OnExpanded := @TreeExpanded;
  if DirectoryExists(GetCurrentDir) then FTree.Root := GetCurrentDir;
  FTree.ObjectTypes := [otFolders];
  FTree.ReadOnly := True;
  FTree.OnDblClick := @TreeDblClick;
  { Sorted by led rather than by the LCL, and not as a matter of taste.
    Assigning FileSortType runs TCustomShellTreeView.SetFileSortType, which
    rebuilds the tree -- but not the way SetRoot does.  SetRoot gives the root
    node the file info that makes it a directory:

      TShellTreeNode(RootNode).FFileInfo.Attr := FileGetAttr(FRoot);

    SetFileSortType's rebuild does only

      RootNode := Items.AddChild(nil, FRoot);

    and leaves FFileInfo zeroed, so IsDirectory came back False for the top
    row.  Clicking it then took DoSelectionChanged's branch for files, which
    raises when the file is not on disk -- and a folder never is:

      The selected item does not exist on disk: "/home/..."

    Unhandled, so it arrives as the LCL's ignore-or-abort dialog.  It only
    showed when the pane's first root was the one the constructor had already
    set, because SetRoot early-exits on an unchanged path and any other path
    rebuilt the node correctly: that is, when the editor was run from the
    folder it was browsing.

    FFileInfo is private, so the node cannot be repaired from here, and
    setting the sort before the root would send the LCL enumerating every
    logical drive.  So the LCL is not asked to sort.  Nothing is lost: with
    otFolders the tree holds only folders, so fstFoldersFirst was doing no
    more than ordering them by name, which is what AlphaSort does. }

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
  { A new root's children arrive in readdir order; see the constructor for why
    the LCL is not the one sorting them. }
  SortTree;
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

{ One button per path component, laid out from the right so that the folder
  you are actually in is the one you can always see.

  Left to right was the obvious way round and the wrong one.  A path a few
  folders deep is wider than the pane: /home/fangq/space/git/Temp/led measures
  982 pixels of buttons in a 937-pixel bar, and that was a wide pane.  What
  ran off the edge was the tail -- which is the only part anyone needs -- so
  the trail looked like it had been replaced by "/ home fangq" and nothing
  else.  Now the leading components are the ones that go, and a button in
  their place still reaches them. }
procedure TLedFileBrowser.BuildCrumbs;
var
  Parts: TStringArray;
  Caps, Hints: array of string;
  Wide: array of Integer;
  i, n, First, Avail, Total, X, EllipsisWide: Integer;
  Accum: string;

  function AddCrumb(const ACaption, AHint: string;
    AWidth: Integer): TSpeedButton;
  begin
    Result := TSpeedButton.Create(FCrumbs);
    Result.Parent := FCrumbs;
    Result.Caption := ACaption;
    Result.Left := X;
    Result.Top := LedScale96(2);
    Result.Height := LedScale96(22);
    Result.Width := AWidth;
    Result.Flat := True;
    { The hint carries the path this crumb goes to, which CrumbClick reads
      back -- and which is worth showing, now that a truncated trail means
      the caption alone may not say where you would land. }
    Result.Hint := AHint;
    Result.ShowHint := True;
    Result.OnClick := @CrumbClick;
    X := X + AWidth + LedScale96(1);
  end;

begin
  FCrumbs.DestroyComponents;

  { Measured in the font the buttons will actually draw in.  A TPanel's canvas
    carries whatever font it was last prepared with, which outside a paint is
    not necessarily its own -- and every crumb's width comes from this. }
  FCrumbs.Canvas.Font.Assign(FCrumbs.Font);

  { The root, then one entry per component. }
  Parts := FRoot.Split([PathDelim]);
  n := 1;
  for i := 0 to High(Parts) do
    if Parts[i] <> '' then Inc(n);
  SetLength(Caps, n);
  SetLength(Hints, n);
  SetLength(Wide, n);

  Caps[0] := {$IFDEF WINDOWS}'Drives'{$ELSE}'/'{$ENDIF};
  Hints[0] := {$IFDEF WINDOWS}''{$ELSE}'/'{$ENDIF};
  n := 1;
  Accum := '';
  for i := 0 to High(Parts) do
  begin
    if Parts[i] = '' then Continue;
    Accum := Accum + PathDelim + Parts[i];
    Caps[n] := Parts[i];
    Hints[n] := Accum;
    Inc(n);
  end;

  for i := 0 to n - 1 do
    Wide[i] := FCrumbs.Canvas.TextWidth(Caps[i]) + LedScale96(20);
  EllipsisWide := FCrumbs.Canvas.TextWidth('<<') + LedScale96(20);

  { Drop leading components until the rest fit.  A bar with no width yet --
    BuildCrumbs runs from SetRoot, which can be long before the pane is laid
    out -- keeps all of them; Resize builds the trail again once there is a
    width to fit it to. }
  Avail := FCrumbs.ClientWidth - LedScale96(4);
  First := 0;
  if Avail > 0 then
    repeat
      Total := 0;
      for i := First to n - 1 do
        Total := Total + Wide[i] + LedScale96(1);
      if First > 0 then
        Total := Total + EllipsisWide + LedScale96(1);
      if (Total <= Avail) or (First >= n - 1) then Break;
      Inc(First);
    until False;

  X := LedScale96(2);
  { Whatever was dropped is still one click away: this goes to the deepest of
    the components that did not fit. }
  if First > 0 then
    AddCrumb('<<', Hints[First - 1], EllipsisWide);
  for i := First to n - 1 do
    AddCrumb(Caps[i], Hints[i], Wide[i]);

  FCrumbWidth := FCrumbs.ClientWidth;
end;

{ TCustomTreeView.AlphaSort sorts the top level, and the top level here is the
  single node standing for the root folder -- every name the user actually
  reads is one of its children.  So sort those, and let OnExpanded take the
  deeper levels as they open. }
procedure TLedFileBrowser.SortTree;
var
  N: TTreeNode;
begin
  N := FTree.Items.GetFirstNode;
  while N <> nil do
  begin
    N.AlphaSort;
    N := N.GetNextSibling;
  end;
end;

{ Children are populated when a folder is first opened, so this is where they
  need ordering.  See the constructor for why it is not the LCL doing it. }
procedure TLedFileBrowser.TreeExpanded(Sender: TObject; ANode: TTreeNode);
begin
  if ANode <> nil then ANode.AlphaSort;
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
