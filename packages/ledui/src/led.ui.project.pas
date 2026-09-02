{ led - a light editor.  The project file list.

  medit's File List plugin: a tree of user-made groups holding files, kept
  across sessions, so the dozen files a piece of work actually touches are
  one click away without hunting through a folder tree.  It is not a project
  model -- there is no build system, no notion of a root -- which is the
  point.  It is a list you curate by hand.

  Stored as filelist.json beside the other state.  Files are held as paths,
  not as open documents: a list whose entries vanish when you close a tab
  would be a tab bar with extra steps. }
unit Led.UI.Project;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ComCtrls, ExtCtrls, StdCtrls, Menus, Dialogs,
  fpjson, jsonparser;

type
  TLedProjectOpen = procedure(const AFileName: string) of object;

  TLedProjectPane = class(TPanel)
  private
    FTree: TTreeView;
    FMenu: TPopupMenu;
    FOnOpen: TLedProjectOpen;
    FFileName: string;
    FDirty: Boolean;
    procedure TreeDblClick(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure DoOpen(Sender: TObject);
    procedure DoAddGroup(Sender: TObject);
    procedure DoRename(Sender: TObject);
    procedure DoRemove(Sender: TObject);
    function GroupFor(ANode: TTreeNode): TTreeNode;
  public
    constructor Create(AOwner: TComponent); override;

    { Adds AFileName to the selected group, or to the first group, making one
      if the list is empty.  Returns the node, or nil if it was already
      there. }
    function AddFile(const AFileName: string): TTreeNode;
    function AddGroup(const AName: string): TTreeNode;

    { A group node has no Data; a file node carries its path in Text and its
      full path in the node's Data-owned string list slot. }
    function IsGroup(ANode: TTreeNode): Boolean;
    function PathOf(ANode: TTreeNode): string;

    function GroupCount: Integer;
    function FileCount: Integer;

    procedure LoadFrom(const AFileName: string);
    procedure SaveTo(const AFileName: string);
    { Writes only if something changed since the last save. }
    procedure SaveIfDirty;

    property Tree: TTreeView read FTree;
    property OnOpen: TLedProjectOpen read FOnOpen write FOnOpen;
  end;

implementation

uses
  LazFileUtils, Led.Core.Paths;

type
  { The full path lives here rather than in the node's Text, so the tree can
    show a base name while the list still knows where the file is. }
  TPathHolder = class
    Path: string;
    constructor Create(const APath: string);
  end;

constructor TPathHolder.Create(const APath: string);
begin
  inherited Create;
  Path := APath;
end;

constructor TLedProjectPane.Create(AOwner: TComponent);

  procedure AddMenu(const ACaption: string; AHandler: TNotifyEvent);
  var
    Item: TMenuItem;
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

  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := @MenuPopup;
  AddMenu('Open', @DoOpen);
  AddMenu('-', nil);
  AddMenu('Add Group', @DoAddGroup);
  AddMenu('Rename', @DoRename);
  AddMenu('Remove', @DoRemove);

  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.PopupMenu := FMenu;
  FTree.OnDblClick := @TreeDblClick;
end;

function TLedProjectPane.IsGroup(ANode: TTreeNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Parent = nil);
end;

function TLedProjectPane.PathOf(ANode: TTreeNode): string;
begin
  Result := '';
  if (ANode = nil) or IsGroup(ANode) then Exit;
  if ANode.Data <> nil then Result := TPathHolder(ANode.Data).Path;
end;

function TLedProjectPane.GroupFor(ANode: TTreeNode): TTreeNode;
begin
  Result := ANode;
  if Result = nil then Exit;
  while Result.Parent <> nil do Result := Result.Parent;
end;

function TLedProjectPane.GroupCount: Integer;
var
  N: TTreeNode;
begin
  Result := 0;
  N := FTree.Items.GetFirstNode;
  while N <> nil do
  begin
    Inc(Result);
    N := N.GetNextSibling;
  end;
end;

function TLedProjectPane.FileCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FTree.Items.Count - 1 do
    if not IsGroup(FTree.Items[i]) then Inc(Result);
end;

function TLedProjectPane.AddGroup(const AName: string): TTreeNode;
begin
  Result := FTree.Items.AddChild(nil, AName);
  FDirty := True;
end;

function TLedProjectPane.AddFile(const AFileName: string): TTreeNode;
var
  Group, N: TTreeNode;
  Full: string;
  i: Integer;
begin
  Result := nil;
  if AFileName = '' then Exit;
  Full := ExpandFileName(AFileName);

  { Already listed anywhere?  Then adding it again would be two entries for
    one file, and removing one would leave the other. }
  for i := 0 to FTree.Items.Count - 1 do
    if SameFileName(PathOf(FTree.Items[i]), Full) then Exit;

  Group := GroupFor(FTree.Selected);
  if Group = nil then Group := FTree.Items.GetFirstNode;
  if Group = nil then Group := AddGroup('Files');

  N := FTree.Items.AddChildObject(Group, ExtractFileName(Full),
    TPathHolder.Create(Full));
  Group.Expanded := True;
  FDirty := True;
  Result := N;
end;

procedure TLedProjectPane.TreeDblClick(Sender: TObject);
begin
  DoOpen(Sender);
end;

procedure TLedProjectPane.MenuPopup(Sender: TObject);
var
  Sel: TTreeNode;
begin
  Sel := FTree.Selected;
  FMenu.Items[0].Enabled := (Sel <> nil) and not IsGroup(Sel);
  FMenu.Items[3].Enabled := (Sel <> nil) and IsGroup(Sel);   // Rename
  FMenu.Items[4].Enabled := Sel <> nil;                      // Remove
end;

procedure TLedProjectPane.DoOpen(Sender: TObject);
var
  Path: string;
begin
  Path := PathOf(FTree.Selected);
  if (Path <> '') and Assigned(FOnOpen) then FOnOpen(Path);
end;

procedure TLedProjectPane.DoAddGroup(Sender: TObject);
var
  GroupName: string;
begin
  GroupName := 'New Group';
  if not InputQuery('Add Group', 'Group name:', GroupName) then Exit;
  if Trim(GroupName) = '' then Exit;
  FTree.Selected := AddGroup(Trim(GroupName));
end;

procedure TLedProjectPane.DoRename(Sender: TObject);
var
  GroupName: string;
begin
  if not IsGroup(FTree.Selected) then Exit;
  GroupName := FTree.Selected.Text;
  if not InputQuery('Rename Group', 'Group name:', GroupName) then Exit;
  if Trim(GroupName) = '' then Exit;
  FTree.Selected.Text := Trim(GroupName);
  FDirty := True;
end;

procedure TLedProjectPane.DoRemove(Sender: TObject);
var
  N: TTreeNode;
begin
  N := FTree.Selected;
  if N = nil then Exit;
  { Removing a group takes its files with it, so that one is worth asking
    about; removing a single file is trivially redone by adding it again. }
  if IsGroup(N) and (N.Count > 0) then
    if MessageDlg('Remove group',
         Format('Remove "%s" and the %d files listed in it?', [N.Text, N.Count]),
         mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  N.Delete;
  FDirty := True;
end;

procedure TLedProjectPane.LoadFrom(const AFileName: string);
var
  Json: string;
  L: TStringList;
  Data: TJSONData;
  Root: TJSONObject;
  Groups, Files: TJSONArray;
  GObj: TJSONObject;
  g, f: Integer;
  Group: TTreeNode;
begin
  FFileName := AFileName;
  FTree.Items.Clear;
  FDirty := False;
  if not FileExists(AFileName) then Exit;

  L := TStringList.Create;
  try
    try
      L.LoadFromFile(AFileName);
      Json := L.Text;
    except
      Exit;
    end;
  finally
    L.Free;
  end;

  Data := nil;
  try
    try
      Data := GetJSON(Json);
    except
      { A corrupt list is not worth refusing to start over. }
      Exit;
    end;
    if not (Data is TJSONObject) then Exit;
    Root := TJSONObject(Data);
    Groups := Root.Get('groups', TJSONArray(nil));
    if Groups = nil then Exit;

    for g := 0 to Groups.Count - 1 do
    begin
      if not (Groups.Items[g] is TJSONObject) then Continue;
      GObj := TJSONObject(Groups.Items[g]);
      Group := FTree.Items.AddChild(nil, GObj.Get('name', 'Files'));
      Files := GObj.Get('files', TJSONArray(nil));
      if Files <> nil then
        for f := 0 to Files.Count - 1 do
          FTree.Items.AddChildObject(Group,
            ExtractFileName(Files.Strings[f]),
            TPathHolder.Create(Files.Strings[f]));
      Group.Expanded := GObj.Get('expanded', True);
    end;
  finally
    Data.Free;
  end;
end;

procedure TLedProjectPane.SaveTo(const AFileName: string);
var
  Root: TJSONObject;
  Groups, Files: TJSONArray;
  GObj: TJSONObject;
  N, C: TTreeNode;
begin
  FFileName := AFileName;
  Root := TJSONObject.Create;
  try
    Groups := TJSONArray.Create;
    Root.Add('groups', Groups);

    N := FTree.Items.GetFirstNode;
    while N <> nil do
    begin
      GObj := TJSONObject.Create;
      Groups.Add(GObj);
      GObj.Add('name', N.Text);
      GObj.Add('expanded', N.Expanded);
      Files := TJSONArray.Create;
      GObj.Add('files', Files);
      C := N.GetFirstChild;
      while C <> nil do
      begin
        if PathOf(C) <> '' then Files.Add(PathOf(C));
        C := C.GetNextSibling;
      end;
      N := N.GetNextSibling;
    end;

    LedWriteFileAtomic(AFileName, Root.FormatJSON);
    FDirty := False;
  finally
    Root.Free;
  end;
end;

procedure TLedProjectPane.SaveIfDirty;
begin
  if FDirty and (FFileName <> '') then SaveTo(FFileName);
end;

end.
