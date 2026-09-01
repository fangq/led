{ led - a light editor.  Customisable keyboard shortcuts.

  Bindings live in keys.ini as action-id to shortcut pairs, and only where
  they differ from the built-in default -- so the file stays small and a new
  default reaches existing users instead of being masked by a stale copy of
  the old one.

  LCL has no reusable key-capture control (TShortCutGrabBox is inside the
  IDE), so there is a small one here. }
unit Led.UI.Shortcuts;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls, ActnList,
  Menus, LCLType, LCLProc, IniFiles,
  Led.Core.Paths;

type
  { An edit box that shows the keystroke you press instead of typing it. }
  TLedKeyGrab = class(TEdit)
  private
    FShortCut: TShortCut;
    procedure SetShortCut(AValue: TShortCut);
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    property ShortCut: TShortCut read FShortCut write SetShortCut;
  end;

  TLedShortcuts = class
  private
    FActions: TActionList;
    FDefaults: TStringList;   // action id -> default shortcut, as text
    FFileName: string;
  public
    constructor Create(AActions: TActionList);
    destructor Destroy; override;

    { Records what each action came with, so a customisation can be told from
      a default and reset means something. }
    procedure CaptureDefaults;
    procedure Load;
    procedure Save;
    procedure Reset(const AActionId: string);
    procedure SetShortcut(const AActionId: string; AShortCut: TShortCut);
    function DefaultOf(const AActionId: string): TShortCut;
    function ConflictWith(AShortCut: TShortCut;
      const AExceptId: string): string;
    property Actions: TActionList read FActions;
  end;

  TLedShortcutsForm = class(TForm)
  private
    FShortcuts: TLedShortcuts;
    FList: TListView;
    FGrab: TLedKeyGrab;
    FConflict: TLabel;
    procedure Populate;
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure GrabChanged(Sender: TObject);
    procedure DoAssign(Sender: TObject);
    procedure DoReset(Sender: TObject);
    procedure DoClose(Sender: TObject);
  public
    constructor CreateFor(AOwner: TComponent; AShortcuts: TLedShortcuts);
  end;

implementation

{ TLedKeyGrab }

constructor TLedKeyGrab.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ReadOnly := True;
  Text := '';
end;

procedure TLedKeyGrab.SetShortCut(AValue: TShortCut);
begin
  FShortCut := AValue;
  if AValue = 0 then
    Text := '(none)'
  else
    Text := ShortCutToText(AValue);
  if Assigned(OnChange) then OnChange(Self);
end;

procedure TLedKeyGrab.KeyDown(var Key: Word; Shift: TShiftState);
begin
  { A bare modifier is not a shortcut; wait for the real key. }
  if Key in [VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN] then
  begin
    Key := 0;
    Exit;
  end;
  if Key = VK_BACK then
    SetShortCut(0)
  else
    SetShortCut(KeyToShortCut(Key, Shift));
  Key := 0;
end;

{ TLedShortcuts }

constructor TLedShortcuts.Create(AActions: TActionList);
begin
  inherited Create;
  FActions := AActions;
  FDefaults := TStringList.Create;
  FDefaults.CaseSensitive := False;
  FFileName := LedConfigFile('keys.ini');
end;

destructor TLedShortcuts.Destroy;
begin
  FDefaults.Free;
  inherited Destroy;
end;

procedure TLedShortcuts.CaptureDefaults;
var
  i: Integer;
  A: TContainedAction;
begin
  FDefaults.Clear;
  for i := 0 to FActions.ActionCount - 1 do
  begin
    A := FActions.Actions[i];
    FDefaults.Values[A.Name] := ShortCutToTextRaw(TAction(A).ShortCut);
  end;
end;

function TLedShortcuts.DefaultOf(const AActionId: string): TShortCut;
begin
  Result := TextToShortCutRaw(FDefaults.Values[AActionId]);
end;

procedure TLedShortcuts.Load;
var
  Ini: TIniFile;
  Names: TStringList;
  i: Integer;
  A: TContainedAction;
begin
  if not FileExists(FFileName) then Exit;
  Ini := TIniFile.Create(FFileName);
  Names := TStringList.Create;
  try
    Ini.ReadSection('Shortcuts', Names);
    for i := 0 to Names.Count - 1 do
    begin
      A := FActions.ActionByName(Names[i]);
      if A = nil then Continue;      { an action that no longer exists }
      TAction(A).ShortCut := TextToShortCutRaw(
        Ini.ReadString('Shortcuts', Names[i], ''));
    end;
  finally
    Names.Free;
    Ini.Free;
  end;
end;

procedure TLedShortcuts.Save;
var
  Ini: TMemIniFile;
  i: Integer;
  A: TContainedAction;
  L: TStringList;
begin
  Ini := TMemIniFile.Create('');
  L := TStringList.Create;
  try
    for i := 0 to FActions.ActionCount - 1 do
    begin
      A := FActions.Actions[i];
      { Only differences are written.  A binding that matches the default is
        left out, so changing a default later actually reaches the user. }
      if TAction(A).ShortCut <> DefaultOf(A.Name) then
        { The raw spelling, not the localised one: a shortcut written on a
          German desktop must still read back on an English one. }
        Ini.WriteString('Shortcuts', A.Name,
          ShortCutToTextRaw(TAction(A).ShortCut));
    end;
    Ini.GetStrings(L);
    LedWriteFileAtomic(FFileName, L.Text);
  finally
    L.Free;
    Ini.Free;
  end;
end;

procedure TLedShortcuts.Reset(const AActionId: string);
var
  A: TContainedAction;
begin
  A := FActions.ActionByName(AActionId);
  if A <> nil then
    TAction(A).ShortCut := DefaultOf(AActionId);
end;

procedure TLedShortcuts.SetShortcut(const AActionId: string;
  AShortCut: TShortCut);
var
  A: TContainedAction;
begin
  A := FActions.ActionByName(AActionId);
  if A <> nil then
    TAction(A).ShortCut := AShortCut;
end;

function TLedShortcuts.ConflictWith(AShortCut: TShortCut;
  const AExceptId: string): string;
var
  i: Integer;
  A: TContainedAction;
begin
  Result := '';
  if AShortCut = 0 then Exit;
  for i := 0 to FActions.ActionCount - 1 do
  begin
    A := FActions.Actions[i];
    if SameText(A.Name, AExceptId) then Continue;
    if TAction(A).ShortCut = AShortCut then
      Exit(TAction(A).Caption);
  end;
end;

{ TLedShortcutsForm }

constructor TLedShortcutsForm.CreateFor(AOwner: TComponent;
  AShortcuts: TLedShortcuts);
var
  Bottom: TPanel;
  Btn: TButton;
  Lbl: TLabel;
begin
  inherited CreateNew(AOwner);
  FShortcuts := AShortcuts;

  Caption := 'Keyboard Shortcuts';
  Position := poMainFormCenter;
  Width := 560;
  Height := 520;

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self; Bottom.Align := alBottom; Bottom.Height := 84;
  Bottom.BevelOuter := bvNone; Bottom.Caption := '';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Bottom; Lbl.Caption := 'Press the keys you want:';
  Lbl.Left := 12; Lbl.Top := 12;

  FGrab := TLedKeyGrab.Create(Self);
  FGrab.Parent := Bottom; FGrab.Left := 180; FGrab.Top := 8; FGrab.Width := 160;
  FGrab.OnChange := @GrabChanged;

  Btn := TButton.Create(Self);
  Btn.Parent := Bottom; Btn.Caption := 'Assign'; Btn.Left := 350; Btn.Top := 7;
  Btn.Width := 80; Btn.OnClick := @DoAssign;

  Btn := TButton.Create(Self);
  Btn.Parent := Bottom; Btn.Caption := 'Reset'; Btn.Left := 438; Btn.Top := 7;
  Btn.Width := 80; Btn.OnClick := @DoReset;

  FConflict := TLabel.Create(Self);
  FConflict.Parent := Bottom; FConflict.Left := 12; FConflict.Top := 40;
  FConflict.Width := 520;

  Btn := TButton.Create(Self);
  Btn.Parent := Bottom; Btn.Caption := 'Close'; Btn.Left := 438; Btn.Top := 54;
  Btn.Width := 80; Btn.OnClick := @DoClose;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.Columns.Add.Caption := 'Command';
  FList.Columns[0].Width := 320;
  FList.Columns.Add.Caption := 'Shortcut';
  FList.Columns[1].Width := 200;
  FList.OnSelectItem := @ListSelect;

  Populate;
end;

procedure TLedShortcutsForm.Populate;
var
  i, Sel: Integer;
  A: TContainedAction;
  Item: TListItem;
begin
  Sel := -1;
  if FList.Selected <> nil then Sel := FList.Selected.Index;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for i := 0 to FShortcuts.Actions.ActionCount - 1 do
    begin
      A := FShortcuts.Actions.Actions[i];
      Item := FList.Items.Add;
      Item.Caption := StringReplace(TAction(A).Caption, '&', '', [rfReplaceAll]);
      Item.SubItems.Add(ShortCutToText(TAction(A).ShortCut));
      Item.Data := A;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if (Sel >= 0) and (Sel < FList.Items.Count) then
    FList.Items[Sel].Selected := True;
end;

procedure TLedShortcutsForm.ListSelect(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  if Selected and (Item <> nil) and (Item.Data <> nil) then
    FGrab.ShortCut := TAction(Item.Data).ShortCut;
end;

procedure TLedShortcutsForm.GrabChanged(Sender: TObject);
var
  Other: string;
begin
  FConflict.Caption := '';
  if FList.Selected = nil then Exit;
  Other := FShortcuts.ConflictWith(FGrab.ShortCut,
    TAction(FList.Selected.Data).Name);
  if Other <> '' then
    FConflict.Caption := Format('Already used by "%s". Assigning will take it away.',
      [StringReplace(Other, '&', '', [rfReplaceAll])]);
end;

procedure TLedShortcutsForm.DoAssign(Sender: TObject);
var
  A: TAction;
  OtherName: string;
  i: Integer;
begin
  if FList.Selected = nil then Exit;
  A := TAction(FList.Selected.Data);

  { A shortcut can only mean one thing, so assigning takes it from whoever
    had it rather than leaving two actions fighting over it. }
  OtherName := FShortcuts.ConflictWith(FGrab.ShortCut, A.Name);
  if OtherName <> '' then
    for i := 0 to FShortcuts.Actions.ActionCount - 1 do
      if TAction(FShortcuts.Actions.Actions[i]).ShortCut = FGrab.ShortCut then
        TAction(FShortcuts.Actions.Actions[i]).ShortCut := 0;

  A.ShortCut := FGrab.ShortCut;
  FShortcuts.Save;
  Populate;
end;

procedure TLedShortcutsForm.DoReset(Sender: TObject);
begin
  if FList.Selected = nil then Exit;
  FShortcuts.Reset(TAction(FList.Selected.Data).Name);
  FShortcuts.Save;
  Populate;
end;

procedure TLedShortcutsForm.DoClose(Sender: TObject);
begin
  Close;
end;

end.
