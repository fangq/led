{ LED - a lightweight editor.  The Outline pane.

  Two kinds of document, two shapes of answer.

  For source, a tree of what ctags found, grouped by kind: functions
  together, types together.  That is how a programmer looks for a symbol --
  by what it is, not by where in the file it happens to be.  ctags is an
  external program and may not be installed; the pane says so plainly rather
  than sitting empty and looking broken.

  For a document -- Markdown, a wiki page, a notebook -- the table of
  contents: the headings, nested by level, in the order they appear.  Order
  matters there in a way it does not for source, because a document is read
  from the top and its sections are its structure.

  Double-clicking anything goes to its line. }
unit Led.UI.Outline;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ComCtrls, ExtCtrls, StdCtrls,
  Led.Core.Ctags, Led.Core.Outline;

type
  { The line ctags reported, and the symbol's name.  The name is passed
    because the line drifts: ctags reads the file on disk, so anything typed
    since moves every symbol below the edit.  What the name is for is settled
    by whoever handles the jump. }
  TLedOutlineJump = procedure(ALine: Integer; const AName: string) of object;

  TLedOutlinePane = class(TPanel)
  private
    FTree: TTreeView;
    FNote: TLabel;
    FTags: TLedTags;
    FFileName: string;
    FOnJump: TLedOutlineJump;
    procedure TreeDblClick(Sender: TObject);
    procedure Clear(const AFileName: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Re-reads AFileName with ctags.  Cheap enough to call whenever the
      active document changes: ctags over one file takes a few
      milliseconds. }
    procedure Reload(const AFileName: string);

    { Shows a document's headings instead: nested by level, in the order they
      appear.  AFileName is only what the pane reports it is showing.

      The nesting is by level and not by counting: a document that starts at
      "##" and never uses "#" nests from there, and one that jumps from "#"
      to "###" does not grow an empty level in between.  Which is to say the
      tree follows the reader's document rather than correcting it. }
    procedure ShowOutline(const AFileName: string;
      const AItems: TLedOutline);
    property OnJump: TLedOutlineJump read FOnJump write FOnJump;
    property Tags: TLedTags read FTags;
    { What the pane is showing, and which file it was built from.  For the
      check that switching documents rebuilds it: the tree is what the reader
      acts on, and it has been out of step with the active document before. }
    property Tree: TTreeView read FTree;
    property FileName: string read FFileName;
  end;

implementation

constructor TLedOutlinePane.Create(AOwner: TComponent);
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

destructor TLedOutlinePane.Destroy;
begin
  FTags.Free;
  inherited Destroy;
end;

procedure TLedOutlinePane.Clear(const AFileName: string);
begin
  FFileName := AFileName;
  FTree.Items.Clear;
  FNote.Visible := False;
end;

procedure TLedOutlinePane.ShowOutline(const AFileName: string;
  const AItems: TLedOutline);
var
  i, d, k: Integer;
  Node: TTreeNode;
  { The heading each level is currently under, so a heading finds its parent
    without the list being walked backwards for it. }
  Open: array[0..7] of TTreeNode;
begin
  Clear(AFileName);
  if Length(AItems) = 0 then
  begin
    FNote.Caption := 'This document has no headings.';
    FNote.Visible := True;
    Exit;
  end;

  FTree.Items.BeginUpdate;
  try
    for d := Low(Open) to High(Open) do Open[d] := nil;
    for i := 0 to High(AItems) do
    begin
      d := AItems[i].Level;
      if d < 1 then d := 1;
      if d > High(Open) then d := High(Open);

      { The nearest heading above it that is shallower.  Nil means the top
        of the tree, which is what a document starting at "##" gets. }
      Node := nil;
      while (d > 1) and (Node = nil) do
      begin
        Dec(d);
        Node := Open[d];
      end;
      d := AItems[i].Level;
      if d > High(Open) then d := High(Open);

      if Node = nil then
        Node := FTree.Items.Add(nil, AItems[i].Title)
      else
        Node := FTree.Items.AddChild(Node, AItems[i].Title);
      Node.Data := Pointer(PtrInt(AItems[i].Line));

      Open[d] := Node;
      { Anything deeper belongs to this heading now, not to the last one at
        that depth. }
      for k := d + 1 to High(Open) do Open[k] := nil;
    end;
    FTree.FullExpand;
  finally
    FTree.Items.EndUpdate;
  end;
end;

procedure TLedOutlinePane.Reload(const AFileName: string);
var
  i, k: Integer;
  Kinds: TStringList;
  Group, Node: TTreeNode;
  KindLabel, Label_: string;
begin
  Clear(AFileName);

  if not LedCtagsAvailable then
  begin
    FNote.Caption := 'Install ctags to see the symbols in a file.';
    FNote.Visible := True;
    Exit;
  end;

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

procedure TLedOutlinePane.TreeDblClick(Sender: TObject);
var
  Line: Integer;
begin
  if (FTree.Selected = nil) or (FTree.Selected.Data = nil) then Exit;
  Line := PtrInt(FTree.Selected.Data);
  if (Line > 0) and Assigned(FOnJump) then
    FOnJump(Line, FTree.Selected.Text);
end;

end.
