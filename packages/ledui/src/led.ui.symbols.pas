{ led - a light editor.  The symbol browser pane.

  A tree of what ctags found in the active document, grouped by kind.
  Double-clicking a symbol goes to its line.

  ctags is an external program and may not be installed; the pane says so
  plainly rather than sitting empty and looking broken. }
unit Led.UI.Symbols;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ComCtrls, ExtCtrls, StdCtrls,
  Led.Core.Ctags;

type
  TLedSymbolJump = procedure(ALine: Integer) of object;

  TLedSymbolPane = class(TPanel)
  private
    FTree: TTreeView;
    FNote: TLabel;
    FTags: TLedTags;
    FFileName: string;
    FOnJump: TLedSymbolJump;
    procedure TreeDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Re-reads AFileName.  Cheap enough to call whenever the active document
      changes: ctags over one file takes a few milliseconds. }
    procedure Reload(const AFileName: string);
    property OnJump: TLedSymbolJump read FOnJump write FOnJump;
    property Tags: TLedTags read FTags;
  end;

implementation

constructor TLedSymbolPane.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  FTags := TLedTags.Create;

  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.Align := alTop;
  FNote.Caption := '';
  FNote.WordWrap := True;
  FNote.Visible := False;

  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.ShowRoot := False;
  FTree.OnDblClick := @TreeDblClick;
end;

destructor TLedSymbolPane.Destroy;
begin
  FTags.Free;
  inherited Destroy;
end;

procedure TLedSymbolPane.Reload(const AFileName: string);
var
  i, k: Integer;
  Kinds: TStringList;
  Group, Node: TTreeNode;
  KindLabel, Label_: string;
begin
  FFileName := AFileName;
  FTree.Items.Clear;

  if not LedCtagsAvailable then
  begin
    FNote.Caption := 'Install ctags to see the symbols in a file.';
    FNote.Visible := True;
    Exit;
  end;
  FNote.Visible := False;

  if (AFileName = '') or not FileExists(AFileName) then Exit;
  if not FTags.RunOn(AFileName) then Exit;

  Kinds := TStringList.Create;
  try
    Kinds.Sorted := True;
    Kinds.Duplicates := dupIgnore;
    FTree.Items.BeginUpdate;
    try
      { A group is created on first use, so empty groups never appear. }
      for i := 0 to FTags.Count - 1 do
      begin
        KindLabel := FTags.KindName(FTags[i].Kind);
        k := Kinds.IndexOf(KindLabel);
        if k < 0 then
        begin
          Group := FTree.Items.Add(nil, KindLabel);
          Kinds.AddObject(KindLabel, Group);
        end
        else
          Group := TTreeNode(Kinds.Objects[k]);

        Label_ := FTags[i].Name;
        if FTags[i].Scope <> '' then
          Label_ := FTags[i].Scope + '::' + Label_;
        Node := FTree.Items.AddChild(Group, Label_);
        Node.Data := Pointer(PtrInt(FTags[i].Line));
      end;
      FTree.FullExpand;
    finally
      FTree.Items.EndUpdate;
    end;
  finally
    Kinds.Free;
  end;
end;

procedure TLedSymbolPane.TreeDblClick(Sender: TObject);
var
  Line: Integer;
begin
  if (FTree.Selected = nil) or (FTree.Selected.Data = nil) then Exit;
  Line := PtrInt(FTree.Selected.Data);
  if (Line > 0) and Assigned(FOnJump) then
    FOnJump(Line);
end;

end.
