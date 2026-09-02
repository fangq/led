{ led - a light editor.  The terminal pane.

  Holds one or more terminals in a tree of splitters, Terminator-style: any
  terminal can be split horizontally or vertically, and closing one collapses
  its splitter so the sibling takes the space back.

  The context menu is where the per-terminal commands live -- split, close,
  paste, clear, colour scheme, font size -- because a terminal has no menu bar
  of its own and these should not clutter the editor's. }
unit Led.Term.Pane;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, Menus, Clipbrd, PairSplitter, Forms,
  { LCL-only, and carries no led dependency of its own, so using it here does
    not compromise ledterm being buildable on its own. }
  Led.UI.Splitter,
  Led.Term.View, Led.Term.Pty;

const
  LedMaxTerminals = 8;

type
  TLedTerminalPane = class(TPanel)
  private
    FTerminals: TFPList;         // of TLedTermView
    FActive: TLedTermView;
    FMenu: TPopupMenu;
    FSchemeMenu: TMenuItem;
    FWorkDir: string;
    function AddTerminal(AParent: TWinControl): TLedTermView;
    procedure TermEnter(Sender: TObject);
    procedure TermExited(Sender: TObject);
    procedure BuildMenu;
    procedure MenuPopup(Sender: TObject);
    procedure DoSplitH(Sender: TObject);
    procedure DoSplitV(Sender: TObject);
    procedure DoClose(Sender: TObject);
    procedure DoPaste(Sender: TObject);
    procedure DoCopyScreen(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure DoClear(Sender: TObject);
    procedure DoBigger(Sender: TObject);
    procedure DoSmaller(Sender: TObject);
    procedure DoScheme(Sender: TObject);
    function GetCount: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Starts the first terminal.  Later ones are started by splitting. }
    function Start(const AWorkDir: string): Boolean;
    procedure Split(AVertical: Boolean);
    procedure CloseActive;
    function Running: Boolean;
    procedure FocusActive;

    property Active: TLedTermView read FActive;
    property Count: Integer read GetCount;
  end;

implementation

{ A TPairSplitter leaves its divider wherever the default position puts it,
  which is not the middle, so a fresh split looks lopsided.  The size is only
  known once the layout has run, hence the InitialSize fallback for a splitter
  that is not on screen yet. }
procedure CentreSplitter(ASplitter: TPairSplitter);
var
  Extent: Integer;
begin
  ASplitter.HandleNeeded;
  if ASplitter.SplitterType = pstHorizontal then
    Extent := ASplitter.Width
  else
    Extent := ASplitter.Height;
  if Extent < 40 then
  begin
    if ASplitter.SplitterType = pstHorizontal then
      Extent := ASplitter.Parent.ClientWidth
    else
      Extent := ASplitter.Parent.ClientHeight;
  end;
  if Extent >= 40 then
    ASplitter.Position := Extent div 2;
end;


constructor TLedTerminalPane.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  FTerminals := TFPList.Create;
  BuildMenu;
end;

destructor TLedTerminalPane.Destroy;
begin
  FTerminals.Free;
  inherited Destroy;
end;

function TLedTerminalPane.GetCount: Integer;
begin
  Result := FTerminals.Count;
end;

procedure TLedTerminalPane.BuildMenu;
var
  Item: TMenuItem;
  i: Integer;

  function Add(const ACaption: string; AHandler: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(FMenu);
    if ACaption = '-' then
      Result.Caption := '-'
    else
    begin
      Result.Caption := ACaption;
      Result.OnClick := AHandler;
    end;
    FMenu.Items.Add(Result);
  end;

begin
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := @MenuPopup;

  Add('Copy', @DoCopyScreen);
  Add('Paste', @DoPaste);
  Add('Select All', @DoSelectAll);
  Add('-', nil);
  Add('Split Side by Side', @DoSplitH);
  Add('Split Stacked', @DoSplitV);
  Add('Close This Terminal', @DoClose);
  Add('-', nil);
  Add('Clear', @DoClear);
  Add('Larger Text', @DoBigger);
  Add('Smaller Text', @DoSmaller);
  Add('-', nil);

  FSchemeMenu := Add('Colour Scheme', nil);
  { The scheme list is fixed, so it is built once.  A submenu filled from its
    own parent's OnClick never opens -- a childless item is a leaf. }
  for i := 0 to LedTermSchemeCount - 1 do
  begin
    Item := TMenuItem.Create(FSchemeMenu);
    Item.Caption := LedTermSchemeName(i);
    Item.Tag := i;
    Item.RadioItem := True;
    Item.OnClick := @DoScheme;
    FSchemeMenu.Add(Item);
  end;
end;

procedure TLedTerminalPane.MenuPopup(Sender: TObject);

  procedure EnableItem(const ACaption: string; AEnabled: Boolean);
  var
    i: Integer;
  begin
    for i := 0 to FMenu.Items.Count - 1 do
      if FMenu.Items[i].Caption = ACaption then
      begin
        FMenu.Items[i].Enabled := AEnabled;
        Exit;
      end;
  end;

begin
  { Only offer to split while there is room, and only offer to close when
    closing leaves something behind. }
  { Found by name rather than by index: the indices moved when Select All
    was added, and a menu that greys the wrong item is worse than one that
    greys nothing. }
  EnableItem('Split Side by Side', FTerminals.Count < LedMaxTerminals);
  EnableItem('Split Stacked', FTerminals.Count < LedMaxTerminals);
  EnableItem('Close This Terminal', FTerminals.Count > 1);
  EnableItem('Copy', True);
end;

function TLedTerminalPane.AddTerminal(AParent: TWinControl): TLedTermView;
begin
  Result := TLedTermView.Create(Self);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.PopupMenu := FMenu;
  Result.OnEnter := @TermEnter;
  Result.OnExited := @TermExited;
  FTerminals.Add(Result);
  if FActive = nil then FActive := Result;
end;

procedure TLedTerminalPane.TermEnter(Sender: TObject);
begin
  FActive := TLedTermView(Sender);
end;

procedure TLedTerminalPane.TermExited(Sender: TObject);
begin
  { A shell that exits closes its pane, which is what a terminal emulator
    does.  The last one is left in place rather than leaving an empty pane. }
  if FTerminals.Count > 1 then
  begin
    FActive := TLedTermView(Sender);
    CloseActive;
  end;
end;

function TLedTerminalPane.Start(const AWorkDir: string): Boolean;
var
  T: TLedTermView;
begin
  Result := False;
  if not LedPtyAvailable then Exit;
  FWorkDir := AWorkDir;
  if FTerminals.Count = 0 then
    T := AddTerminal(Self)
  else
    T := FActive;
  if T.Running then Exit(True);
  Result := T.Start('', AWorkDir);
end;

procedure TLedTerminalPane.Split(AVertical: Boolean);
var
  Old: TLedTermView;
  Host: TWinControl;
  Splitter: TPairSplitter;
  NewTerm: TLedTermView;
begin
  if FTerminals.Count >= LedMaxTerminals then Exit;
  Old := FActive;
  if Old = nil then Exit;

  Host := Old.Parent;
  Splitter := TLedPairSplitter.Create(Self);
  Splitter.Parent := Host;
  Splitter.Align := alClient;
  if AVertical then
    Splitter.SplitterType := pstVertical
  else
    Splitter.SplitterType := pstHorizontal;

  Old.Parent := Splitter.Sides[0];
  Old.Align := alClient;

  NewTerm := AddTerminal(Splitter.Sides[1]);
  CentreSplitter(Splitter);
  NewTerm.Start('', FWorkDir);
  FActive := NewTerm;
end;

procedure TLedTerminalPane.CloseActive;
var
  Doomed: TLedTermView;
  Side: TWinControl;
  Splitter: TPairSplitter;
  Keeper: TControl;
  Host: TWinControl;
begin
  if FTerminals.Count < 2 then Exit;
  Doomed := FActive;
  if (Doomed = nil) or not (Doomed.Parent is TPairSplitterSide) then Exit;

  Side := Doomed.Parent;
  Splitter := TPairSplitter(Side.Parent);
  Host := Splitter.Parent;

  if Splitter.Sides[0] = Side then
    Side := Splitter.Sides[1]
  else
    Side := Splitter.Sides[0];
  if Side.ControlCount = 0 then Exit;
  Keeper := Side.Controls[0];

  FTerminals.Remove(Doomed);
  FActive := nil;
  Doomed.Stop;

  Keeper.Parent := Host;
  Keeper.Align := alClient;

  { Released rather than freed.  The usual way here is a shell that has just
    exited, which is noticed inside the view's own poll timer -- so this runs
    with that view's event still on the stack, and freeing it there is a
    use-after-free.  ReleaseComponent hands both to the LCL to destroy once
    the reference count has dropped.  Same reasoning as ClearMenu in
    Led.UI.Main. }
  Application.ReleaseComponent(Doomed);
  Application.ReleaseComponent(Splitter);

  if FTerminals.Count > 0 then
    FActive := TLedTermView(FTerminals[0]);
end;

function TLedTerminalPane.Running: Boolean;
var
  i: Integer;
begin
  for i := 0 to FTerminals.Count - 1 do
    if TLedTermView(FTerminals[i]).Running then Exit(True);
  Result := False;
end;

procedure TLedTerminalPane.FocusActive;
begin
  { Deliberately empty of any SetFocus.  Whether a control can be focused
    depends on the state of the window that owns it, which this pane cannot
    see; Led.UI.Focus answers that question and the caller asks it. }
end;

procedure TLedTerminalPane.DoSplitH(Sender: TObject);
begin
  Split(False);
end;

procedure TLedTerminalPane.DoSplitV(Sender: TObject);
begin
  Split(True);
end;

procedure TLedTerminalPane.DoClose(Sender: TObject);
begin
  CloseActive;
end;

procedure TLedTerminalPane.DoPaste(Sender: TObject);
begin
  if FActive <> nil then FActive.Paste(Clipboard.AsText);
end;

procedure TLedTerminalPane.DoCopyScreen(Sender: TObject);
var
  i: Integer;
  S: string;
begin
  if FActive = nil then Exit;
  { What was selected with the mouse, if anything; otherwise the whole
    visible screen, which is what the item used to be able to offer. }
  if FActive.HasSelection then
  begin
    Clipboard.AsText := FActive.SelectedText;
    Exit;
  end;
  S := '';
  for i := 0 to FActive.Screen.Rows - 1 do
    S := S + FActive.Screen.RowText(i) + LineEnding;
  Clipboard.AsText := TrimRight(S) + LineEnding;
end;

procedure TLedTerminalPane.DoSelectAll(Sender: TObject);
begin
  if FActive <> nil then FActive.SelectAll;
end;

procedure TLedTerminalPane.DoClear(Sender: TObject);
begin
  { Asking the shell to clear keeps its idea of the screen and ours in step,
    which resetting the model behind its back would not. }
  if FActive <> nil then FActive.Paste('clear' + LineEnding);
end;

procedure TLedTerminalPane.DoBigger(Sender: TObject);
begin
  if (FActive <> nil) and (FActive.Font.Size < 32) then
    FActive.Font.Size := FActive.Font.Size + 1;
end;

procedure TLedTerminalPane.DoSmaller(Sender: TObject);
begin
  if (FActive <> nil) and (FActive.Font.Size > 5) then
    FActive.Font.Size := FActive.Font.Size - 1;
end;

procedure TLedTerminalPane.DoScheme(Sender: TObject);
var
  i: Integer;
begin
  { The scheme is a property of the pane, not of one split, so all of them
    change together. }
  for i := 0 to FTerminals.Count - 1 do
    TLedTermView(FTerminals[i]).SetScheme(TMenuItem(Sender).Tag);
  TMenuItem(Sender).Checked := True;
end;

end.
