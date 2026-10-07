{ LED - a lightweight editor.  The file browser pane.

  medit hand-wrote 22,000 lines here, including its own icon grid, because GTK
  had nothing suitable.  LCL ships TShellTreeView, which enumerates a
  directory into tree nodes; this unit is the breadcrumb bar, the filter, the
  icons and the context menu around it.

  One tree, showing folders and files together, as VS Code and Sublime show
  them.  It replaced a folder tree over a file list, and the trade is worth
  naming: a folder with four hundred files in it now pushes the rest of the
  tree down, and the size and date columns the list gave for free are gone.
  What is bought is that the shape of a project is visible in one place --
  which is what the pane is for -- without a click into each folder and
  without half the pane's height spent on a list of one directory. }
unit Led.UI.FileBrowser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, StdCtrls, Buttons, ComCtrls, Menus,
  Dialogs, Graphics, Forms, ShellCtrls, LazFileUtils, LazUTF8, LCLType, Masks,
  Led.UI.Icons, Led.Core.Prefs;

const
  { the paths typed or chosen in the path box, newest first: its list }
  LedPrefRecentPaths = 'FileBrowser/recent_paths';
  LedRecentPathsMax = 20;

const
  { The preset that means "do not filter".  Named because the filter box is
    read by what its entry says rather than by where the entry sits, and a
    fork supplying presets of its own has to be able to include this one. }
  LedFilterAll = 'All files';

  { The tree's own small image list, in the order it is built.  A position in
    here is what a node's ImageIndex is, so the order is load-bearing --
    'folder' first because a directory takes it without consulting the
    extension table, and the plain page last because it is the fallback. }
  { The tree's own list, in its own order: IconForPath answers an index
    into this and the plain page is last, which is what an unrecognised
    name falls back to.  MATLAB and python are here because the shipped
    set has a logo for each and a file list in this program is mostly .m
    files -- without them both fell through to the plain page. }
  TreeIconNames: array[0..9] of string =
    ('folder', 'filesource', 'filetext', 'filemarkdown', 'filepdf',
     'fileimage', 'filebinary', 'matlab', 'python', 'doc');

{ A byte count as a person reads one: 1.4 MB rather than 1468006.  Binary
  multiples, since that is what a file system reports. }
function LedFormatSize(ABytes: Int64): string;

type
  { TCustomTreeView keeps the hook that draws an expander protected, and
    TShellTreeView does not publish it. }
  TLedTreeAccess = class(TCustomTreeView);

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
    { The trail as text: a double click on the bar swaps it for this, to
      type or paste a path into. }
    FPathRow: TPanel;            { the path being typed, and its browse button }
    FPathEdit: TComboBox;
    FPathBrowse: TSpeedButton;
    FBtnRefresh: TSpeedButton;
    FWatch: TTimer;
    FWatchSig: string;           { what the folders held when last looked at }
    FTree: TShellTreeView;
    FIcons: TImageList;
    FFilter: TComboBox;
    FShowHidden: TCheckBox;
    FNav: TPanel;
    FBtnBack, FBtnForward, FBtnUp, FBtnHome: TSpeedButton;
    FBtnNewFolder, FBtnNewFile: TSpeedButton;
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
    FMask: string;
    FHintNode: TTreeNode;
    FCrumbWidth: Integer;
    FOnOpenFile: TLedOpenFileEvent;
    FOnRootChanged: TLedOpenFileEvent;
    { Type-to-select: the letters typed so far, and when the last came.
      Letters a second apart are one name; a longer pause starts another.
      While FTyped is set, Up and Down move between the rows it matches. }
    FTyped: string;
    FTypedAt: QWord;
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeUTF8KeyPress(Sender: TObject; var UTF8Key: TUTF8Char);
    procedure TreeMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure TreeExit(Sender: TObject);
    function TypedMatches(ANode: TTreeNode): Boolean;
    function NextTypedMatch(AFrom: TTreeNode; AForward, AIncludeFrom: Boolean): TTreeNode;
    procedure SelectNode(ANode: TTreeNode);
    procedure BuildCrumbs;
    procedure CrumbClick(Sender: TObject);
    procedure TreeExpanded(Sender: TObject; ANode: TTreeNode);
    procedure TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure TreeDrawArrow(Sender: TCustomTreeView; const ARect: TRect;
      ACollapsed: Boolean);
    procedure IconiseNodes;
    procedure IconiseChildren(ANode: TTreeNode);
    procedure PathBackOnRootRow;
    function IconForPath(const APath: string; AIsDir: Boolean): Integer;
    function PassesFilter(const AName: string): Boolean;
    procedure NavResize(Sender: TObject);
    procedure CrumbsDblClick(Sender: TObject);
    procedure PathEditKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure PathEditExit(Sender: TObject);
    procedure EndPathEdit;
    procedure PathSelect(Sender: TObject);
    procedure PathBrowseClick(Sender: TObject);
    procedure RememberPath(const APath: string);
    procedure WatchTick(Sender: TObject);
    function FolderSignature: string;
    procedure SortTree;
    procedure ListDblClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure HiddenChange(Sender: TObject);
    procedure MenuOpen(Sender: TObject);
    procedure MenuNewFolder(Sender: TObject);
    procedure MenuNewFile(Sender: TObject);
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
    function CompareNodes(ANode1, ANode2: TTreeNode): Integer;
    procedure SortChildren(ANode: TTreeNode);
    procedure SetSortFoldersFirst(AValue: Boolean);
    procedure SetCaseSensitiveSort(AValue: Boolean);
    function SelectedPath: string;
    procedure Reload;
  public
    { The file a drag out of this pane is carrying, or '' when the drag
      started on a folder or on nothing.

      A drag out of the list is how a file is opened *as a file* -- the
      editor's reading of it -- whatever else the program would otherwise
      do with that name.  The pane does not know what that means; it only
      says what is being carried, and the window decides.  See
      TLedMainForm.EditorDragDrop.

      Read from the selection rather than from a pointer-position hit test,
      because a tree selects on the press and the drag begins after it. }
    function DraggedFile: string;

    { The tree itself, so a drop target can ask "is this drag mine?".
      Answered with the control rather than with a flag, because that is
      what the LCL hands a drop handler as the source. }
    function DragSource: TControl;
    constructor Create(AOwner: TComponent); override;
    { FHistory is a list of this pane's own making rather than a child
      component, so it is freed here; everything else is Create(Self). }
    destructor Destroy; override;
    { What the filter box offers, and which of them is picked to begin
      with -- the first.

      Settable because the presets are a statement about what this program
      is for: LED's are the languages it was written to edit, and a
      language environment's are the files a session makes.  A fork
      supplying its own here is one call; editing the list in place would
      put its vocabulary in an upstream file. }
    procedure SetFilterPresets(const AItems: array of string);

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

    { The two controls on the bar below the tree, driven as a click drives
      them.  Public because both went wrong in ways that only show when the
      control is used rather than read: the Hidden box re-rooted the tree
      from the label on its top row, and the filter wrote a field that
      nothing went on to act on. }
    procedure ShowHidden(AOn: Boolean);
    procedure FilterBy(const AMask: string);
    { Which names the tree is currently letting through; '' is everything. }
    property Mask: string read FMask;

    { The one tree.  Public so a check can read what is in it. }
    property Tree: TShellTreeView read FTree;

    { Type-to-select, as the tree's key handlers drive it; public so a check
      can type without a keyboard.  TypeAhead adds what was typed to the
      name being looked for -- or starts a new one after a pause -- and
      selects the first visible row whose name begins with it, from the
      selected row on.  CycleTyped moves to the next (ADelta > 0) or the
      previous matching row, wrapping, and is False when no name is being
      typed, so Up and Down then move as they always do.  EndTyping forgets
      the name. }
    procedure TypeAhead(const AText: string);
    function CycleTyped(ADelta: Integer): Boolean;
    procedure EndTyping;
    { What is being typed; '' when nothing is. }
    property Typed: string read FTyped;
    { Which picture a path would get.  Public so the mapping can be checked
      without going through the tree's own enumeration. }
    function IconFor(const APath: string): Integer;
    { Paints the tree in the editor's colours.  The pane used the desktop's
      instead, so a dark scheme in the editor sat beside a file list in
      whatever the widget theme happened to be. }
    procedure ApplyColours(AFore, ABack: TColor);
    { True when LED is drawing the expander rather than the LCL.  A function
      because the hook is protected on TCustomTreeView, and Pascal's
      protected reaches only within the unit that declares the descendant. }
    function DrawsOwnChevron: Boolean;
    { And the tree, so a check can select its root -- which used to raise. }
    property FileTree: TShellTreeView read FTree;

    { The crumb trail, by the numbers: how many buttons it has, and how far
      the last of them reaches.  Exposed because "the breadcrumb bar
      disappeared" has two quite different causes -- no buttons at all, or
      buttons that run off the right-hand edge -- and they need different
      fixes. }
    function CrumbCount: Integer;
    { The trail as an edit box, as a double click on the bar makes it.
      Enter goes to what was typed -- a full path, one relative to where
      the pane is, or one starting with ~ -- and Escape or leaving the box
      goes back to the trail.  A path that is not a folder keeps the box
      open, marked, for the reader to correct.  EnterPath is that Enter,
      for a check to make without a keyboard. }
    procedure BeginPathEdit;
    function EnterPath(const APath: string): Boolean;
    function PathEditing: Boolean;
    property PathEdit: TComboBox read FPathEdit;
    function CrumbsWidth: Integer;
    function CrumbBarWidth: Integer;
    { The glyph on a navigation button, and the button under it.  Exposed
      because the two came apart: the buttons scaled with the pane and the
      glyph stayed at the sixteen pixels the icons are drawn at, which is
      what "huge buttons with tiny icons" was. }
    function NavGlyphSize: Integer;
    function NavButtonSize: Integer;
    { How many buttons sit on the navigation row.  The breadcrumb trail is
      made of speed buttons too, so counting them by class finds both. }
    function NavButtonCount: Integer;
    { The nav buttons themselves, for the check that they shade under the
      pointer.  There is no drawing to look at from outside otherwise: a
      speed button has no handle of its own to paint. }
    function NavButton(AIndex: Integer): TSpeedButton;
    property OnOpenFile: TLedOpenFileEvent read FOnOpenFile write FOnOpenFile;

    { The pane moved to another folder -- by a crumb, by Up, Home, Back or
      Forward, by a double click on a directory, or by anything else, because
      all of them go through SetRoot and nothing else sets FRoot.

      Nothing in the editor listens: where a file list is pointed is not the
      editor's business.  It is the MATLAB IDE's, where this pane *is* the
      current folder -- `pwd` answers from it, `cd` moves it, and a script
      beside it is on the path -- and one event is cheaper than the fork
      watching a private field on a timer. }
    property OnRootChanged: TLedOpenFileEvent
      read FOnRootChanged write FOnRootChanged;
  end;

implementation

uses
  Clipbrd, Led.UI.Dpi;

const
  { The editor's own presets: the languages LED was written to edit, with
    everything first because an editor opens whatever it is pointed at. }
  LedDefaultFilters: array[0..4] of string = (
    LedFilterAll,
    '*.c;*.h;*.cpp;*.hpp',
    '*.pas;*.pp;*.inc;*.lfm',
    '*.py',
    '*.md;*.txt');

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
begin
  if (FNav = nil) or (FCrumbs = nil) or
     (FBtnHome = nil) or (FBtnBack = nil) then Exit;

  { The trail has a row of its own now and is aligned to it, so its bounds
    are the layout's business and not this procedure's.

    Setting them here is what crashed LED on startup: an alTop control given
    SetBounds is realigned, realignment raises OnResize, and OnResize set the
    bounds again -- unbounded recursion, which arrives as an access violation
    rather than as anything that names itself.  It only bit where the pane
    was open when LED started, which is why a scripted run never saw it. }

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

{ There is no splitter any more: the pane is one tree.  Kept as nil rather
  than removed, so a caller that still asks gets an answer instead of a
  compile error. }

{ Which picture a row gets.

  The extension table lives in Led.UI.Icons, with the tab headers, so a file
  cannot end up with one picture in the tree and another on its tab.  This
  turns the name that rule returns into a position in the small list built
  for the tree. }
function TLedFileBrowser.IconForPath(const APath: string;
  AIsDir: Boolean): Integer;
var
  i: Integer;
  Want: string;
begin
  if AIsDir then Exit(0);           { 'folder', first in TreeIconNames }
  Want := LedIconForFile(APath);
  for i := 0 to High(TreeIconNames) do
    if TreeIconNames[i] = Want then Exit(i);
  Result := High(TreeIconNames);    { the plain page, which is last }
end;

{ True when AName is one the filter lets through.  Folders always pass: a
  filter is about which files to look at, not which folders exist. }
function TLedFileBrowser.PassesFilter(const AName: string): Boolean;
begin
  Result := (FMask = '') or MatchesMaskList(AName, FMask, ';');
end;

{ Put a picture on every child of ANode, and drop the files the filter
  excludes.

  Done here rather than by the LCL because TShellTreeView makes its nodes as
  it enumerates and has no hook for either -- it knows the path of a node and
  nothing about what LED wants to do with it. }
procedure TLedFileBrowser.IconiseChildren(ANode: TTreeNode);
var
  Node, Next: TTreeNode;
  Path: string;
  IsDir: Boolean;
begin
  if ANode = nil then Exit;
  Node := ANode.GetFirstChild;
  while Node <> nil do
  begin
    Next := Node.GetNextSibling;
    Path := FTree.GetPathFromNode(Node);
    IsDir := DirectoryExists(Path);
    if (not IsDir) and (not PassesFilter(ExtractFileName(Path))) then
      Node.Delete
    else
    begin
      Node.ImageIndex := IconForPath(Path, IsDir);
      Node.SelectedIndex := Node.ImageIndex;
    end;
    Node := Next;
  end;
end;

{ The whole tree as it stands, root included.  Cheap: only the nodes that
  have actually been created are walked, and a folder is not enumerated until
  it is opened. }
procedure TLedFileBrowser.IconiseNodes;
var
  Node: TTreeNode;
  Path, Leaf: string;
  IsDir: Boolean;
begin
  if FTree = nil then Exit;
  FTree.BeginUpdate;
  try
    { The root row shows the folder's name rather than its whole path.  The
      path is on the crumb bar directly above, where it can be read and
      clicked; repeating it here only pushed the first few folders off the
      right-hand edge of a narrow pane.

      Reading a path back out of the tree is safe: TCustomShellTreeView
      builds one from each node's own record, not from the text shown in it.
      Refreshing is not.  TCustomShellTreeView.Refresh re-roots the whole
      tree from the top row's *text* -- `FRoot := #0; SetRoot(ANode.Text)`
      -- so once that text is a bare name it is resolved against the working
      directory.  Anything that can reach Refresh has to put the path back
      first; see PathBackOnRootRow. }
    Node := FTree.Items.GetFirstNode;
    if Node <> nil then
    begin
      Leaf := ExtractFileName(ExcludeTrailingPathDelimiter(FTree.Root));
      { Except at the top of the filesystem, where there is no name to show
        and the path is the only thing there is. }
      if Leaf = '' then Leaf := FTree.Root;
      if (Leaf <> '') and (Node.Text <> Leaf) then Node.Text := Leaf;
    end;

    Node := FTree.Items.GetFirstNode;
    while Node <> nil do
    begin
      Path := FTree.GetPathFromNode(Node);
      IsDir := (Path = '') or DirectoryExists(Path);
      Node.ImageIndex := IconForPath(Path, IsDir);
      Node.SelectedIndex := Node.ImageIndex;
      Node := Node.GetNext;
    end;
  finally
    FTree.EndUpdate;
  end;
end;

{ Puts the real path back on the top row, undoing the short label above.

  Reported as: ticking Hidden raises

      Invalid pathname: "/home/users/fangq/fangq"

  Assigning ObjectTypes runs TCustomShellTreeView.SetObjectTypes, which calls
  Refresh(nil), which rebuilds the tree by reading the top row's text and
  passing it to SetRoot.  The row said 'fangq' rather than
  /home/users/fangq, so SetRoot expanded it against the process's working
  directory -- the reader's home -- and raised on a folder that was never
  there.  SetObjectTypes guards its SetPath but not its Refresh, so the
  exception came all the way out.

  The label comes back by itself: whatever reloads next ends in
  IconiseNodes. }
procedure TLedFileBrowser.PathBackOnRootRow;
var
  Node: TTreeNode;
begin
  if (FTree = nil) or (FRoot = '') then Exit;
  Node := FTree.Items.GetFirstNode;
  if (Node <> nil) and (Node.Text <> FRoot) then Node.Text := FRoot;
end;

function TLedFileBrowser.DrawsOwnChevron: Boolean;
begin
  Result := (FTree <> nil) and
            Assigned(TLedTreeAccess(FTree).OnCustomDrawArrow);
end;

procedure TLedFileBrowser.ApplyColours(AFore, ABack: TColor);
begin
  if (FTree = nil) or (AFore = clNone) or (ABack = clNone) then Exit;
  FTree.Color := ABack;
  FTree.Font.Color := AFore;

  { The icons are drawn, not loaded, so they can be drawn again in the
    colours the tree has just been given.  Only the ones with no colour of
    their own change -- a source file stays blue -- but those are the ones
    that were disappearing into a dark page. }
  if FIcons <> nil then
  begin
    LedBuildIconList(FIcons, TreeIconNames, AFore);
    FTree.Invalidate;
  end;
  { The crumb trail and the filter row stay in the desktop's colours: they
    are chrome, not content, and LED does not theme its other chrome either. }
end;

function LedFormatSize(ABytes: Int64): string;
const
  Units: array[0..4] of string = ('bytes', 'KB', 'MB', 'GB', 'TB');
var
  i: Integer;
  V: Double;
begin
  if ABytes < 1024 then
    Exit(Format('%d bytes', [ABytes]));
  V := ABytes;
  i := 0;
  while (V >= 1024) and (i < High(Units)) do
  begin
    V := V / 1024;
    Inc(i);
  end;
  Result := Format('%.1f %s', [V, Units[i]]);
end;

function TLedFileBrowser.IconFor(const APath: string): Integer;
begin
  Result := IconForPath(APath, DirectoryExists(APath));
end;

function TLedFileBrowser.NavButtonCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  if FNav = nil then Exit;
  for i := 0 to FNav.ControlCount - 1 do
    if FNav.Controls[i] is TSpeedButton then Inc(Result);
end;

function TLedFileBrowser.NavButton(AIndex: Integer): TSpeedButton;
var
  i, n: Integer;
begin
  Result := nil;
  if FNav = nil then Exit;
  n := 0;
  for i := 0 to FNav.ControlCount - 1 do
    if FNav.Controls[i] is TSpeedButton then
    begin
      if n = AIndex then Exit(TSpeedButton(FNav.Controls[i]));
      Inc(n);
    end;
end;

function TLedFileBrowser.SplitterTarget: TControl;
begin
  Result := nil;
end;

{ ---- type-to-select --------------------------------------------------- }

const
  { Letters closer together than this are one name. }
  TypeAheadPause = 1000;

function TLedFileBrowser.TypedMatches(ANode: TTreeNode): Boolean;
begin
  Result := (ANode <> nil) and (FTyped <> '') and
    (Pos(UTF8LowerCase(FTyped), UTF8LowerCase(ANode.Text)) = 1);
end;

{ The next visible row that matches, after AFrom (or at it), going one way
  and wrapping round; nil when none does.  Visible rows only: a name inside a
  folder that is shut is not one the user can see to be choosing. }
function TLedFileBrowser.NextTypedMatch(AFrom: TTreeNode; AForward,
  AIncludeFrom: Boolean): TTreeNode;
var
  Node, Start: TTreeNode;
begin
  Result := nil;
  if (FTree = nil) or (FTree.Items.Count = 0) then Exit;
  Start := AFrom;
  if Start = nil then
  begin
    Start := FTree.Items.GetFirstVisibleNode;
    AIncludeFrom := True;
  end;
  if Start = nil then Exit;
  if AIncludeFrom and TypedMatches(Start) then Exit(Start);
  Node := Start;
  repeat
    if AForward then
    begin
      Node := Node.GetNextVisible;
      if Node = nil then Node := FTree.Items.GetFirstVisibleNode;
    end
    else
    begin
      Node := Node.GetPrevVisible;
      if Node = nil then Node := FTree.Items.GetLastExpandedSubNode;
    end;
    if Node = nil then Exit;
    if TypedMatches(Node) then Exit(Node);
  until Node = Start;
end;

procedure TLedFileBrowser.SelectNode(ANode: TTreeNode);
begin
  if ANode = nil then Exit;
  FTree.Selected := ANode;
  ANode.MakeVisible;
end;

procedure TLedFileBrowser.TypeAhead(const AText: string);
var
  Found: TTreeNode;
begin
  if (FTree = nil) or (AText = '') then Exit;
  if (FTyped <> '') and (GetTickCount64 - FTypedAt > TypeAheadPause) then
    FTyped := '';
  FTyped := FTyped + AText;
  FTypedAt := GetTickCount64;
  { The selected row stays if it still matches -- "ap" then "p" keeps
    apple -- and otherwise the search runs on from it. }
  Found := NextTypedMatch(FTree.Selected, True, True);
  if Found <> nil then
    SelectNode(Found)
  else if UTF8Length(FTyped) > 1 then
  begin
    { Nothing starts with what has been typed: the last letter alone, as a
      repeated first letter steps through the rows that begin with it. }
    FTyped := AText;
    Found := NextTypedMatch(FTree.Selected, True, False);
    if Found <> nil then
      SelectNode(Found);
  end;
end;

function TLedFileBrowser.CycleTyped(ADelta: Integer): Boolean;
var
  Found: TTreeNode;
begin
  Result := FTyped <> '';
  if not Result then Exit;
  FTypedAt := GetTickCount64;
  Found := NextTypedMatch(FTree.Selected, ADelta > 0, False);
  if Found <> nil then
    SelectNode(Found);
end;

procedure TLedFileBrowser.EndTyping;
begin
  FTyped := '';
end;

procedure TLedFileBrowser.TreeUTF8KeyPress(Sender: TObject;
  var UTF8Key: TUTF8Char);
begin
  { Printable characters only: Enter, Tab, Escape and the control keys keep
    the meanings the tree and the window give them. }
  if (UTF8Key = '') or ((Length(UTF8Key) = 1) and (UTF8Key[1] < ' ')) then
    Exit;
  { A space continues a name being typed, and is the tree's own otherwise. }
  if (UTF8Key = ' ') and (FTyped = '') then Exit;
  TypeAhead(UTF8Key);
  UTF8Key := '';
end;

procedure TLedFileBrowser.TreeKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if FTyped = '' then Exit;
  if Shift * [ssCtrl, ssAlt, ssMeta] <> [] then
  begin
    EndTyping;
    Exit;
  end;
  case Key of
    VK_UP:
      begin
        CycleTyped(-1);
        Key := 0;
      end;
    VK_DOWN:
      begin
        CycleTyped(1);
        Key := 0;
      end;
    VK_BACK:
      begin
        UTF8Delete(FTyped, UTF8Length(FTyped), 1);
        FTypedAt := GetTickCount64;
        if FTyped <> '' then
          SelectNode(NextTypedMatch(FTree.Selected, True, True));
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        EndTyping;
        Key := 0;
      end;
    VK_RETURN, VK_TAB, VK_LEFT, VK_RIGHT, VK_HOME, VK_END, VK_PRIOR,
    VK_NEXT, VK_DELETE, VK_INSERT:
      { the name is done, and the key does what it always does }
      EndTyping;
  else
    { Anything else -- a letter, a digit, Shift on its way to a capital --
      arrives here first, as a key, and then as the character it types.
      Ending the name here, as the first version did for every key it did
      not list, emptied it before each letter was added to it. }
  end;
end;

procedure TLedFileBrowser.TreeMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  EndTyping;
end;

procedure TLedFileBrowser.TreeExit(Sender: TObject);
begin
  EndTyping;
end;

constructor TLedFileBrowser.Create(AOwner: TComponent);
var
  Bar: TPanel;
  Item: TMenuItem;

  function MakeNavButton(const AIcon, AHint: string; ALeft: Integer): TSpeedButton;
  begin
    Result := TLedSpeedButton.Create(Self);
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
    { Sixteen, not fourteen: the glyphs are painted artwork now and a
      gradient needs a pixel or two more than a line drawing before it
      reads as a shape rather than a smudge. }
    Result.Glyph.Assign(LedIconBitmap(AIcon, clBtnText, LedScale96(16)));
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
  { Making things, rather than only going places.  Both were on the context
    menu and nowhere else, which is a poor place for the two actions someone
    working in a tree reaches for most. }
  FBtnNewFolder := MakeNavButton('newfolder', 'New folder...', 94);
  FBtnNewFolder.OnClick := @MenuNewFolder;
  FBtnNewFile := MakeNavButton('newfile', 'New file...', 116);
  FBtnNewFile.OnClick := @MenuNewFile;
  { the folders read again: what another program -- or the engine -- wrote
    shows without waiting for the watch below }
  FBtnRefresh := MakeNavButton('reload', 'Refresh', 142);
  FBtnRefresh.OnClick := @MenuRefresh;

  { A row of its own, under the buttons.  It shared the button row once,
    which kept the chrome to one line but left the trail a few dozen pixels
    of what a path needs -- and with six buttons there now rather than four
    there is no room to share at all. }
  FCrumbs := TPanel.Create(Self);
  FCrumbs.Parent := Self;
  { Below the buttons, not above them.  Two alTop siblings stack in order of
    their Top, and a control that has just been made has Top 0 -- the same as
    the row already there -- so the trail came out on the first line and the
    buttons on the second.  Given a Top past the nav row it settles under it,
    and the alignment keeps it there. }
  FCrumbs.Top := FNav.Height + 1;
  FCrumbs.Align := alTop;
  FCrumbs.Height := 24;
  FCrumbs.BevelOuter := bvNone;
  FCrumbs.Caption := '';
  FCrumbs.OnResize := @NavResize;
  FCrumbs.OnDblClick := @CrumbsDblClick;
  FCrumbs.Hint := 'Double-click to type a path';
  FCrumbs.ShowHint := True;

  { Owned by the pane, not the bar: BuildCrumbs frees everything the bar
    owns, and counts what it holds. }
  { The path typed in place of the trail: a box that remembers the paths
    entered before, and a button that chooses a folder instead. }
  FPathRow := TPanel.Create(Self);
  FPathRow.Visible := False;
  FPathRow.Parent := Self;
  FPathRow.Top := FCrumbs.Top;
  FPathRow.Align := alTop;
  FPathRow.AutoSize := True;
  FPathRow.BevelOuter := bvNone;
  FPathRow.Caption := '';
  FPathBrowse := TLedSpeedButton.Create(Self);
  FPathBrowse.Parent := FPathRow;
  FPathBrowse.Align := alRight;
  FPathBrowse.Width := 24;
  FPathBrowse.Flat := True;
  FPathBrowse.Hint := 'Choose a folder...';
  FPathBrowse.ShowHint := True;
  FPathBrowse.Glyph.Assign(LedIconBitmap('open', clBtnText, LedScale96(14)));
  FPathBrowse.OnClick := @PathBrowseClick;
  FPathEdit := TComboBox.Create(Self);
  FPathEdit.Parent := FPathRow;
  FPathEdit.Align := alClient;
  FPathEdit.Style := csDropDown;
  FPathEdit.DropDownCount := LedRecentPathsMax;
  FPathEdit.Items.CommaText := LedPrefs.GetStr(LedPrefRecentPaths, '');
  FPathEdit.OnKeyDown := @PathEditKeyDown;
  FPathEdit.OnExit := @PathEditExit;
  FPathEdit.OnSelect := @PathSelect;

  { Looked at a little at a time, while the pane is in view: a folder that
    gained or lost an entry -- a file saved, made by a program, deleted -- is
    read again, its open folders open and its selection kept. }
  FWatch := TTimer.Create(Self);
  FWatch.Interval := 1500;
  FWatch.OnTimer := @WatchTick;

  { Just the filter row, at the foot.  It used to sit inside a container 228
    pixels tall -- the height the file list wanted before the pane became one
    tree.  With the list gone that container was a filter row with two
    hundred pixels of nothing under it, which is what "a large empty space
    below the filters" was. }
  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alBottom;
  Bar.Height := 28;
  Bar.BevelOuter := bvNone;
  Bar.Caption := '';

  FFilter := TComboBox.Create(Self);
  FFilter.Parent := Bar;
  FFilter.Left := 2; FFilter.Top := 2; FFilter.Width := 140;
  SetFilterPresets(LedDefaultFilters);
  FFilter.Style := csDropDownList;
  FFilter.OnChange := @FilterChange;

  FShowHidden := TCheckBox.Create(Self);
  FShowHidden.Parent := Bar;
  FShowHidden.Left := 148; FShowHidden.Top := 5;
  FShowHidden.Caption := 'Hidden';
  FShowHidden.OnChange := @HiddenChange;

  { The tree's own pictures, drawn by LED rather than taken from the desktop
    theme -- which is how every other icon in the application is made, and
    the only way they look the same on all three platforms. }
  FIcons := TImageList.Create(Self);
  { The same twenty the toolbar uses; see TLedMainForm.BuildIcons. }
  FIcons.Width := LedScale96(20);
  FIcons.Height := LedScale96(20);
  { clBtnText, not clDefault: clDefault resolves to black, and the tree is
    painted in the *editor's* colours, so on a dark scheme every icon without
    a colour of its own was black on near-black.  Rebuilt with the tree's own
    foreground whenever those colours change -- see ApplyColours. }
  LedBuildIconList(FIcons, TreeIconNames, clBtnText);

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
  { Files as well as folders: one tree rather than a tree over a list. }
  FTree.ObjectTypes := [otFolders, otNonFolders];
  FTree.ReadOnly := True;
  FTree.OnDblClick := @TreeDblClick;
  { Draggable out of the pane.  Automatic rather than begun by hand: the
    LCL starts the drag after its own threshold, so a click still selects
    and an expander arrow still expands.  Through the accessor because the
    shell tree does not publish it. }
  TLedTreeAccess(FTree).DragMode := dmAutomatic;
  { The row under the pointer says where it is and how big it is.  A tree in
    a narrow pane truncates names, and the size is the other thing anyone
    asks of a file list -- it was the one thing lost when the pane stopped
    being a list with columns. }
  FTree.ShowHint := True;
  FTree.OnMouseMove := @TreeMouseMove;
  { Typing a name selects it, as in any file manager; see TypeAhead. }
  FTree.OnUTF8KeyPress := @TreeUTF8KeyPress;
  FTree.OnKeyDown := @TreeKeyDown;
  FTree.OnMouseDown := @TreeMouseDown;
  FTree.OnExit := @TreeExit;
  { LED draws the expander.  The LCL offers a themed box, a plus-minus and an
    outlined triangle, and none of them is the chevron a file tree has used
    since VS Code made it the convention.  OnCustomDrawArrow hands over that
    rectangle and nothing else -- the indent, the hit testing and the click
    that toggles a node all stay the LCL's. }
  { Protected on TCustomTreeView and published only by TTreeView, which
    TShellTreeView is not -- so it is reached the way this project reaches
    any other protected member, through a descendant declared for the
    purpose. }
  TLedTreeAccess(FTree).OnCustomDrawArrow := @TreeDrawArrow;
  { The selection is the whole row, as it is in every file tree worth using;
    a name-width highlight in a pane this narrow is hard to see and harder to
    aim at. }
  FTree.RowSelect := True;
  FTree.HideSelection := False;
  FTree.ShowButtons := True;
  FTree.ShowLines := False;
  FTree.ShowRoot := True;
  { An icon per row, by what the file is.  The nodes are made by the LCL as
    it enumerates, so the pictures are put on afterwards -- see IconiseNodes. }
  FTree.Images := FIcons;
  FTree.OnExpanded := @TreeExpanded;
  { Sorted by LED rather than by the LCL, and not as a matter of taste.
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

  FMenu := TPopupMenu.Create(Self);
  AddMenu('Open', @MenuOpen);
  AddMenu('-', nil);
  AddMenu('Go Up', @MenuGoUp);
  AddMenu('-', nil);
  AddMenu('Properties', @MenuProperties);
  AddMenu('Refresh', @MenuRefresh);
  AddMenu('-', nil);
  AddMenu('New Folder...', @MenuNewFolder);
  AddMenu('New File...', @MenuNewFile);
  AddMenu('Rename...', @MenuRename);
  AddMenu('Delete...', @MenuDelete);
  AddMenu('-', nil);
  AddMenu('Copy Full Path', @MenuCopyPath);
  FTree.PopupMenu := FMenu;
  IconiseNodes;
end;

destructor TLedFileBrowser.Destroy;
begin
  FHistory.Free;
  inherited Destroy;
end;

procedure TLedFileBrowser.EnsureRoot(const ADefault: string);
begin
  if FRoot <> '' then Exit;
  if not HandleAllocated then Exit;
  SetRoot(ADefault);
end;

procedure TLedFileBrowser.SetFilterPresets(const AItems: array of string);
var
  i: Integer;
begin
  if Length(AItems) = 0 then
    Exit;
  FFilter.Items.BeginUpdate;
  try
    FFilter.Items.Clear;
    for i := Low(AItems) to High(AItems) do
      FFilter.Items.Add(AItems[i]);
  finally
    FFilter.Items.EndUpdate;
  end;
  { Everything, whatever order the presets came in.

    The caller decides what the list leads with -- a language environment
    leads with its own files -- but not what the pane opens showing: a file
    browser that starts with most of the folder hidden looks broken, and
    the reader has no way of knowing that the thing they cannot find is
    merely filtered out. }
  FFilter.ItemIndex := FFilter.Items.IndexOf(LedFilterAll);
  if FFilter.ItemIndex < 0 then
    FFilter.ItemIndex := 0;
  FilterChange(FFilter);
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
  { Setting Root rebuilds the tree from nothing, so every picture put on the
    old nodes went with them. }
  IconiseNodes;
  BuildCrumbs;
  { Moving through the history is not itself a place to come back to. }
  if not FNavigating then PushHistory(FRoot);
  UpdateNav;
  { what the folders hold as they were just read: a file made from now on
    is a change to it.  Taken on the first look instead, a file made
    before that look was in it, and was never seen. }
  FWatchSig := FolderSignature;

  { Last, so a listener that asks the pane where it is gets the answer it
    has just finished arriving at rather than the one it is leaving. }
  if Assigned(FOnRootChanged) then FOnRootChanged(FRoot);
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
  { There used to be a `FTree.ObjectTypes := FTree.ObjectTypes` here, meant
    to force a re-read.  SetObjectTypes returns at once when the value has
    not changed, so it never did anything -- and had it done, it would have
    taken the refresh path that PathBackOnRootRow exists to survive.
    Reload is what re-reads. }
  IconiseNodes;
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
    Result := TLedSpeedButton.Create(FCrumbs);
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
{ Folders first, then files, each group by name.

  AlphaSort is what this used, and it sorts on the node's text and nothing
  else -- so a folder called `docs` landed between `build.sh` and
  `install.sh` and the reader had to pick the directories out of the middle
  of the file list.  Every file manager, and medit's own browser, groups
  them; SortFoldersFirst was here to say so and was read by nothing, which
  is why the setting existed and the order did not follow it.

  CaseSensitiveSort is the other half of the same omission: it was stored,
  offered as a property, and never reached the comparison either. }
function TLedFileBrowser.CompareNodes(ANode1, ANode2: TTreeNode): Integer;
var
  Dir1, Dir2: Boolean;
begin
  if FSortFoldersFirst then
  begin
    Dir1 := (ANode1 is TShellTreeNode) and TShellTreeNode(ANode1).IsDirectory;
    Dir2 := (ANode2 is TShellTreeNode) and TShellTreeNode(ANode2).IsDirectory;
    if Dir1 <> Dir2 then
    begin
      if Dir1 then Result := -1 else Result := 1;
      Exit;
    end;
  end;

  if FCaseSensitiveSort then
    Result := CompareStr(ANode1.Text, ANode2.Text)
  else
    Result := CompareText(ANode1.Text, ANode2.Text);
end;

procedure TLedFileBrowser.SortChildren(ANode: TTreeNode);
begin
  if ANode <> nil then
    ANode.CustomSort(@CompareNodes);
end;

procedure TLedFileBrowser.SortTree;
var
  N: TTreeNode;
begin
  N := FTree.Items.GetFirstNode;
  while N <> nil do
  begin
    SortChildren(N);
    N := N.GetNextSibling;
  end;
end;

{ Children are populated when a folder is first opened, so this is where they
  need ordering.  See the constructor for why it is not the LCL doing it. }
{ A folder that has just been opened has had its children made by the LCL,
  which knows nothing about LED's pictures or its filter -- so both are
  applied here, where the nodes first exist. }
procedure TLedFileBrowser.TreeExpanded(Sender: TObject; ANode: TTreeNode);
begin
  if ANode = nil then Exit;
  IconiseChildren(ANode);
  SortChildren(ANode);
  { a folder opened is watched from now on, as it was just read -- not a
    change to read again }
  FWatchSig := FolderSignature;
end;

procedure TLedFileBrowser.CrumbsDblClick(Sender: TObject);
begin
  BeginPathEdit;
end;

procedure TLedFileBrowser.BeginPathEdit;
begin
  if FPathRow.Visible then Exit;
  FPathEdit.Text := FRoot;
  FPathEdit.ParentColor := False;
  FPathEdit.Color := clDefault;
  FPathRow.Top := FCrumbs.Top;
  FCrumbs.Visible := False;
  FPathRow.Visible := True;
  if FPathEdit.CanFocus then
    FPathEdit.SetFocus;
  FPathEdit.SelectAll;
end;

procedure TLedFileBrowser.EndPathEdit;
begin
  if not FPathRow.Visible then Exit;
  FCrumbs.Top := FPathRow.Top;
  FCrumbs.Visible := True;
  FPathRow.Visible := False;
  { the trail was built at whatever width it had when it was hidden }
  BuildCrumbs;
end;

function TLedFileBrowser.PathEditing: Boolean;
begin
  Result := FPathRow.Visible;
end;

{ a path gone to from the box: first in its list, and kept for next time }
procedure TLedFileBrowser.RememberPath(const APath: string);
var
  I: Integer;
begin
  I := FPathEdit.Items.IndexOf(APath);
  if I >= 0 then
    FPathEdit.Items.Delete(I);
  FPathEdit.Items.Insert(0, APath);
  while FPathEdit.Items.Count > LedRecentPathsMax do
    FPathEdit.Items.Delete(FPathEdit.Items.Count - 1);
  LedPrefs.SetStr(LedPrefRecentPaths, FPathEdit.Items.CommaText);
end;

procedure TLedFileBrowser.PathSelect(Sender: TObject);
begin
  if FPathEdit.ItemIndex >= 0 then
    EnterPath(FPathEdit.Items[FPathEdit.ItemIndex]);
end;

procedure TLedFileBrowser.PathBrowseClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(Self);
  try
    D.Title := 'Choose a folder';
    D.InitialDir := FRoot;
    if D.Execute then
      EnterPath(D.FileName);
  finally
    D.Free;
  end;
end;

function TLedFileBrowser.EnterPath(const APath: string): Boolean;
var
  Target: string;
begin
  Target := Trim(APath);
  if (Target = '~') or (Copy(Target, 1, 2) = '~' + PathDelim) then
    Target := ExcludeTrailingPathDelimiter(GetUserDir) + Copy(Target, 2, MaxInt);
  if Target <> '' then
    Target := CreateAbsolutePath(Target, FRoot);
  Result := (Target <> '') and DirectoryExists(Target);
  if not Result then
  begin
    { left open and marked, so a typo is fixed rather than retyped }
    if FPathRow.Visible then
      FPathEdit.Color := $C0C0FF;
    Exit;
  end;
  RememberPath(ExcludeTrailingPathDelimiter(ExpandFileName(Target)));
  EndPathEdit;
  SetRoot(Target);
end;

procedure TLedFileBrowser.PathEditKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    EnterPath(FPathEdit.Text);
  end
  else if Key = VK_ESCAPE then
  begin
    Key := 0;
    EndPathEdit;
  end;
end;

procedure TLedFileBrowser.PathEditExit(Sender: TObject);
begin
  { the list dropped down takes the focus for a moment: still typing }
  if FPathEdit.DroppedDown then
    Exit;
  EndPathEdit;
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
function TLedFileBrowser.DraggedFile: string;
var
  Path: string;
begin
  Result := '';
  Path := SelectedPath;
  if (Path <> '') and FileExists(Path) and not DirectoryExists(Path) then
    Result := Path;
end;

function TLedFileBrowser.DragSource: TControl;
begin
  Result := FTree;
end;

function TLedFileBrowser.SelectedPath: string;
begin
  Result := '';
  if FTree.Selected <> nil then
    Result := FTree.GetPathFromNode(FTree.Selected);
  if (Result = '') and (FTree.Selected <> nil) then
    Result := FTree.GetPathFromNode(FTree.Selected);
end;

procedure TLedFileBrowser.ListDblClick(Sender: TObject);
var
  Path: string;
begin
  if FTree.Selected = nil then Exit;
  Path := FTree.GetPathFromNode(FTree.Selected);
  if Path = '' then Exit;
  if DirectoryExists(Path) then
    SetRoot(Path)
  else if Assigned(FOnOpenFile) then
    FOnOpenFile(Path);
end;

{ What the row under the pointer is.  Rebuilt only when the row changes, so
  moving along a row costs one comparison. }
procedure TLedFileBrowser.TreeMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  Node: TTreeNode;
  Path, Tip: string;
  Size: Int64;
  Rec: TSearchRec;
begin
  Node := FTree.GetNodeAt(X, Y);
  if Node = FHintNode then Exit;
  FHintNode := Node;
  if Node = nil then
  begin
    FTree.Hint := '';
    Exit;
  end;

  Path := ExcludeTrailingPathDelimiter(FTree.GetPathFromNode(Node));
  Tip := Path;
  if FileExists(Path) then
  begin
    Size := -1;
    if FindFirst(Path, faAnyFile, Rec) = 0 then
    begin
      Size := Rec.Size;
      FindClose(Rec);
    end;
    if Size >= 0 then
      Tip := Path + LineEnding + LedFormatSize(Size);
  end;
  FTree.Hint := Tip;
end;

{ A right-angle chevron: two arms meeting at ninety degrees, pointing right
  when the folder is shut and down when it is open.

  Square rather than the flatter proportions LED's fold gutter uses.  That
  one sits in a narrow column beside code and is drawn wide so it reads at a
  glance; this one sits in a row of text where a wide chevron would look like
  a mistake, and ninety degrees is what the eye expects beside a folder. }
procedure TLedFileBrowser.TreeDrawArrow(Sender: TCustomTreeView;
  const ARect: TRect; ACollapsed: Boolean);
var
  C: TCanvas;
  Cx, Cy, Arm: Integer;
begin
  C := Sender.Canvas;
  Cx := (ARect.Left + ARect.Right) div 2;
  Cy := (ARect.Top + ARect.Bottom) div 2;

  { Half the shorter side, less a pixel, so the arms stay inside the cell the
    LCL measured for them. }
  Arm := (ARect.Right - ARect.Left) div 2;
  if (ARect.Bottom - ARect.Top) div 2 < Arm then
    Arm := (ARect.Bottom - ARect.Top) div 2;
  Dec(Arm);
  if Arm < 2 then Arm := 2;

  C.Pen.Color := Sender.ExpandSignColor;
  if C.Pen.Color = clNone then C.Pen.Color := Sender.Font.Color;
  C.Pen.Width := 1;
  if Arm >= 5 then C.Pen.Width := 2;
  C.Pen.Style := psSolid;
  C.Pen.EndCap := pecRound;
  C.Pen.JoinStyle := pjsRound;

  if ACollapsed then
  begin
    { Pointing right: the apex on the right, arms back at ninety degrees. }
    C.MoveTo(Cx - Arm div 2, Cy - Arm);
    C.LineTo(Cx + Arm div 2, Cy);
    C.LineTo(Cx - Arm div 2, Cy + Arm);
  end
  else
  begin
    { Pointing down. }
    C.MoveTo(Cx - Arm, Cy - Arm div 2);
    C.LineTo(Cx, Cy + Arm div 2);
    C.LineTo(Cx + Arm, Cy - Arm div 2);
  end;
end;

procedure TLedFileBrowser.TreeDblClick(Sender: TObject);
var
  Path: string;
begin
  if FTree.Selected = nil then Exit;
  Path := FTree.GetPathFromNode(FTree.Selected);
  { A folder descends, a file opens.  Opening was the file list's job before
    the pane became one tree, and went with it -- leaving double-click doing
    nothing on the rows most people double-click. }
  if DirectoryExists(Path) then
    SetRoot(Path)
  else if FileExists(Path) and Assigned(FOnOpenFile) then
    FOnOpenFile(Path);
end;

{ The folders read again, as they are on disk now; the folders that were
  open opened again, shallowest first, and what was selected selected }
procedure TLedFileBrowser.Reload;
var
  Keep, Sel: string;
  Open: TStringList;
  I, J: Integer;
  N: TTreeNode;
begin
  Keep := FRoot;
  Sel := SelectedPath;
  Open := TStringList.Create;
  try
    for I := 0 to FTree.Items.Count - 1 do
      if FTree.Items[I].Expanded and (FTree.Items[I].Level > 0) then
        Open.Add(FTree.GetPathFromNode(FTree.Items[I]));
    FRoot := '';
    FTree.Root := '';
    SetRoot(Keep);
    for J := 0 to Open.Count - 1 do
      for I := 0 to FTree.Items.Count - 1 do
      begin
        N := FTree.Items[I];
        if (N.Level > 0) and (FTree.GetPathFromNode(N) = Open[J]) then
        begin
          N.Expand(False);
          Break;
        end;
      end;
    if Sel <> '' then
      for I := 0 to FTree.Items.Count - 1 do
        if FTree.GetPathFromNode(FTree.Items[I]) = Sel then
        begin
          FTree.Selected := FTree.Items[I];
          Break;
        end;
  finally
    Open.Free;
  end;
  FWatchSig := FolderSignature;
end;

{ what the root and its open folders hold, as their names: a change of it is
  an entry made, deleted or renamed }
function TLedFileBrowser.FolderSignature: string;
var
  Dirs: TStringList;
  I, Count: Integer;
  R: TSearchRec;
begin
  Result := '';
  if FRoot = '' then
    Exit;
  Dirs := TStringList.Create;
  try
    Dirs.Add(FRoot);
    for I := 0 to FTree.Items.Count - 1 do
      if FTree.Items[I].Expanded and (FTree.Items[I].Level > 0) and (Dirs.Count < 50) then
        Dirs.Add(FTree.GetPathFromNode(FTree.Items[I]));
    for I := 0 to Dirs.Count - 1 do
    begin
      Result := Result + '|' + Dirs[I] + ':';
      Count := 0;
      if FindFirst(IncludeTrailingPathDelimiter(Dirs[I]) + '*', faAnyFile, R) = 0 then
      try
        repeat
          if (R.Name <> '.') and (R.Name <> '..') then
          begin
            Result := Result + R.Name + '/';
            Inc(Count);
          end;
        until (FindNext(R) <> 0) or (Count > 5000);
      finally
        FindClose(R);
      end;
    end;
  finally
    Dirs.Free;
  end;
end;

procedure TLedFileBrowser.WatchTick(Sender: TObject);
var
  Sig: string;
begin
  if not IsVisible or PathEditing or (FRoot = '') then
    Exit;
  Sig := FolderSignature;
  if (FWatchSig <> '') and (Sig <> FWatchSig) then
    Reload
  else
    FWatchSig := Sig;
end;

procedure TLedFileBrowser.FilterChange(Sender: TObject);
begin
  { By what the entry says, not by where it sits.  "Everything" was index 0
    by construction, which held for exactly as long as one program supplied
    the presets: the MATLAB fork puts its own first, and a first entry that
    was a real mask was read as no mask at all and filtered nothing. }
  if (FFilter.ItemIndex < 0) or (FFilter.Text = LedFilterAll) then
    FilterBy('')
  else
    FilterBy(FFilter.Text);
end;

{ Reported as: the filter does not seem to work.

  It did not.  Picking from the list set the mask and stopped there, and the
  mask is only ever read while a folder's children are being made -- in
  IconiseChildren, from OnExpanded.  The rows on screen had been made
  already, so nothing about them changed, and a filter chosen before opening
  a folder was the only one that appeared to do anything.

  Reloading is what re-enumerates: the root is built and expanded again, and
  every row that appears passes through the filter on its way in. }
procedure TLedFileBrowser.FilterBy(const AMask: string);
begin
  if FMask = AMask then Exit;
  FMask := AMask;
  if FRoot <> '' then Reload;
end;

procedure TLedFileBrowser.HiddenChange(Sender: TObject);
begin
  ShowHidden(FShowHidden.Checked);
end;

procedure TLedFileBrowser.ShowHidden(AOn: Boolean);
var
  Want: TObjectTypes;
begin
  if FTree = nil then Exit;
  Want := FTree.ObjectTypes;
  if AOn then
    Include(Want, otHidden)
  else
    Exclude(Want, otHidden);
  { Keep the box and the tree saying the same thing when this is called from
    somewhere other than the box itself.  Without unhooking, assigning
    Checked comes straight back round through HiddenChange. }
  if FShowHidden.Checked <> AOn then
  begin
    FShowHidden.OnChange := nil;
    try
      FShowHidden.Checked := AOn;
    finally
      FShowHidden.OnChange := @HiddenChange;
    end;
  end;
  if Want = FTree.ObjectTypes then Exit;
  { Assigning this refreshes the tree, and the refresh reads the top row's
    text as a path.  See PathBackOnRootRow for what that cost. }
  PathBackOnRootRow;
  FTree.ObjectTypes := Want;
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

{ A new, empty file in the folder the selection is in, opened once it is
  made -- making one and then having to find it again is a step nobody wants.

  Beside MenuNewFolder because the two belong together, and both are on the
  toolbar now as well as the context menu. }
procedure TLedFileBrowser.MenuNewFile(Sender: TObject);
var
  Base, NewName, Full: string;
  L: TStringList;
begin
  Base := SelectedPath;
  if (Base = '') or (not DirectoryExists(Base)) then
    Base := ExtractFileDir(Base);
  if (Base = '') or (not DirectoryExists(Base)) then Base := FRoot;
  if not DirectoryExists(Base) then Exit;

  NewName := 'untitled.txt';
  if not InputQuery('New File', 'Name for the new file:', NewName) then Exit;
  NewName := Trim(NewName);
  if NewName = '' then Exit;

  Full := IncludeTrailingPathDelimiter(Base) + NewName;
  if FileExists(Full) or DirectoryExists(Full) then
  begin
    ShowMessage('There is already something called ' + NewName + ' there.');
    Exit;
  end;

  L := TStringList.Create;
  try
    try
      L.SaveToFile(Full);
    except
      on E: Exception do
      begin
        ShowMessage('Could not create ' + NewName + ': ' + E.Message);
        Exit;
      end;
    end;
  finally
    L.Free;
  end;

  Reload;
  if Assigned(FOnOpenFile) then FOnOpenFile(Full);
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
  { No trash: LED deletes outright, so the question says so and names what
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
