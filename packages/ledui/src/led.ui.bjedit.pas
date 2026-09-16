// led - a lightweight editor.  The panel that edits one value of a BJData
// file.
//
// A value in a structure view is two things at once: what it says, and the
// type it is stored as.  A text box on its own can only ask about the first,
// and the second then has to be guessed from what was typed -- which is
// right often enough to be the default and wrong often enough to be worth
// showing.  So the panel shows both: the types this text could be written
// as, with the file's own selected, and the text itself.
//
// The type list is not a fixed menu of everything BJData has.  It is the
// types the text in the box could actually be stored as, rebuilt at every
// keystroke: type 0.1 and float32 leaves the list, type 300 and uint8 does.
// That comes from Led.Core.BJDEdit, which answers it by writing the value
// and reading it back rather than from a table.
//
// It is a small window under the row rather than a dialog in the middle of
// the screen, because it belongs to the row it is editing.  It does not
// close when it loses the focus: losing what you have typed because a window
// manager moved the focus somewhere is worse than a panel that waits.

unit Led.UI.BJEdit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, LCLType,
  Led.Core.BJDEdit, Led.UI.Dpi;

type
  { Called when the panel is done with; AAccepted is False for Escape and for
    Cancel, and then nothing about the file has been touched. }
  TLedBJValueDone = procedure(Sender: TObject; AAccepted: Boolean) of object;

  TLedBJValuePopup = class(TForm)
  private
    FFrame: TPanel;
    FKeyLabel: TLabel;
    FTypes: TComboBox;
    FValue: TEdit;
    FOk: TButton;
    FCancel: TButton;
    { One marker per item in FTypes, in the same order: the list shows names
      and the file stores markers, and this is the one mapping between. }
    FMarkers: string;
    FCurrent: AnsiChar;
    { Whether the type in the list is the reader's choice or the panel's.
      A chosen type survives further typing; one the panel picked follows
      what is typed, so fixing a typo does not leave the value stored as
      whatever the half-typed text happened to allow. }
    FChosen: Boolean;
    FSetting: Boolean;   // the panel is moving the list, not the reader
    FOnDone: TLedBJValueDone;
    function PickType(AMarker: AnsiChar): Boolean;
    procedure SyncOk;
    procedure TypeChanged(Sender: TObject);
    procedure ValueChanged(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    function GetValueText: string;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;

    { Opens the panel at a screen position with AText in the box and ACurrent
      selected in the type list.  AKey names the record, or is empty for an
      array element. }
    procedure ShowFor(AScreenX, AScreenY: Integer; const AKey, AText: string;
      ACurrent: AnsiChar);
    { Closes it, telling the caller whether the reader accepted.  Called by
      the buttons, by Return and Escape, and by the window when the document
      goes away underneath it. }
    procedure Finish(AAccepted: Boolean);

    { Selects a type by marker.  False when this text cannot be written as
      that type, in which case nothing is selected that was not before. }
    function SelectType(AMarker: AnsiChar): Boolean;
    { The marker of the selected type, or #0 when the text is not a value at
      all and the list is therefore empty. }
    function ChosenMarker: AnsiChar;

    property ValueText: string read GetValueText;
    property OnDone: TLedBJValueDone read FOnDone write FOnDone;

    { The controls, for the self-test: a check drives the panel the way a
      reader does rather than calling the window's handler directly. }
    property ValueBox: TEdit read FValue;
    property TypeList: TComboBox read FTypes;
    property OkButton: TButton read FOk;
    property CancelButton: TButton read FCancel;
  end;

implementation

constructor TLedBJValuePopup.Create(AOwner: TComponent);
var
  Pad, Row, Line2, BtnW, BtnH: Integer;
begin
  { CreateNew rather than Create: there is no form resource for this, it is
    built here. }
  CreateNew(AOwner);
  BorderStyle := bsNone;
  KeyPreview := True;
  ShowInTaskBar := stNever;
  Position := poDesigned;

  Pad := LedScale96(8);
  BtnW := LedScale96(72);
  BtnH := LedScale96(25);
  Row := Pad + LedScale96(18);
  Line2 := Row + LedScale96(30);

  ClientWidth := LedScale96(368);
  ClientHeight := Line2 + BtnH + Pad;

  { A raised frame, because the window has no border of its own: without it
    the panel has no edge and reads as part of the page behind it. }
  FFrame := TPanel.Create(Self);
  FFrame.Parent := Self;
  FFrame.Align := alClient;
  FFrame.BevelOuter := bvRaised;
  FFrame.Caption := '';

  FKeyLabel := TLabel.Create(Self);
  FKeyLabel.Parent := FFrame;
  FKeyLabel.SetBounds(Pad, Pad, ClientWidth - Pad * 2, LedScale96(16));

  FTypes := TComboBox.Create(Self);
  FTypes.Parent := FFrame;
  FTypes.Style := csDropDownList;
  FTypes.SetBounds(Pad, Row, LedScale96(120), LedScale96(24));
  FTypes.OnChange := @TypeChanged;

  FValue := TEdit.Create(Self);
  FValue.Parent := FFrame;
  FValue.SetBounds(Pad + LedScale96(128), Row,
    ClientWidth - Pad * 2 - LedScale96(128), LedScale96(24));
  FValue.OnChange := @ValueChanged;

  FOk := TButton.Create(Self);
  FOk.Parent := FFrame;
  FOk.Caption := 'OK';
  FOk.SetBounds(ClientWidth - Pad - BtnW * 2 - LedScale96(6), Line2,
    BtnW, BtnH);
  FOk.OnClick := @OkClick;

  FCancel := TButton.Create(Self);
  FCancel.Parent := FFrame;
  FCancel.Caption := 'Cancel';
  FCancel.SetBounds(ClientWidth - Pad - BtnW, Line2, BtnW, BtnH);
  FCancel.OnClick := @CancelClick;
end;

function TLedBJValuePopup.GetValueText: string;
begin
  Result := FValue.Text;
end;

function TLedBJValuePopup.ChosenMarker: AnsiChar;
begin
  Result := #0;
  if (FTypes.ItemIndex >= 0) and (FTypes.ItemIndex < Length(FMarkers)) then
    Result := FMarkers[FTypes.ItemIndex + 1];
end;

{ There is something to accept exactly when a type is selected.  Kept in one
  place because three things move the selection: typing, choosing, and the
  panel opening. }
procedure TLedBJValuePopup.SyncOk;
begin
  FOk.Enabled := FTypes.ItemIndex >= 0;
end;

function TLedBJValuePopup.PickType(AMarker: AnsiChar): Boolean;
var
  At: Integer;
begin
  At := Pos(AMarker, FMarkers);
  { The two boolean markers are one entry in the list: a file holding F and
    a file holding T offer the same choice, and which byte is written is what
    the text says. }
  if (At = 0) and (AMarker in ['T', 'F']) then At := Pos('T', FMarkers);
  Result := At > 0;
  if Result then
  begin
    FSetting := True;
    try
      FTypes.ItemIndex := At - 1;
    finally
      FSetting := False;
    end;
  end;
  SyncOk;
end;

function TLedBJValuePopup.SelectType(AMarker: AnsiChar): Boolean;
begin
  Result := PickType(AMarker);
  { Coming from outside the panel means somebody chose it. }
  if Result then FChosen := True;
end;

procedure TLedBJValuePopup.TypeChanged(Sender: TObject);
begin
  if not FSetting then FChosen := True;
  SyncOk;
end;

{ The list, rebuilt for what is in the box now.  The selection survives where
  the type it named is still possible -- a reader who chose float64 and then
  fixed a typo should not find themselves back on int32 -- and otherwise
  falls to what the file would get if nobody chose at all. }
procedure TLedBJValuePopup.ValueChanged(Sender: TObject);
var
  Was: AnsiChar;
  i: Integer;
  Kept: Boolean;
begin
  Was := ChosenMarker;
  FMarkers := LedBJTypesFor(FValue.Text, FCurrent);

  FSetting := True;
  try
    FTypes.Items.BeginUpdate;
    try
      FTypes.Items.Clear;
      for i := 1 to Length(FMarkers) do
        FTypes.Items.Add(LedBJTypeName(FMarkers[i]));
      FTypes.ItemIndex := -1;
    finally
      FTypes.Items.EndUpdate;
    end;
  finally
    FSetting := False;
  end;

  Kept := FChosen and (Was <> #0) and PickType(Was);
  if not Kept then
  begin
    { What the file would get if nobody chose -- and nothing at all when
      that is nothing, which is how a word typed into a number field looks.
      The list still offers a string for it: turning a number into text is a
      real thing to want, and one the reader has to ask for by name rather
      than fall into by pressing Return. }
    PickType(LedBJMarkerFor(FValue.Text, FCurrent));
    FChosen := False;
  end;

  FTypes.Enabled := FMarkers <> '';
  SyncOk;
end;

procedure TLedBJValuePopup.ShowFor(AScreenX, AScreenY: Integer;
  const AKey, AText: string; ACurrent: AnsiChar);
begin
  FCurrent := ACurrent;
  if AKey <> '' then
    FKeyLabel.Caption := Format('Value of "%s"', [AKey])
  else
    FKeyLabel.Caption := 'Value';

  FChosen := False;
  FValue.Text := AText;
  { Assigning the text fires ValueChanged, so the list is already built; this
    puts the file's own type back on top of whatever that chose, without
    counting as a choice -- retyping the value should still land on the type
    the value calls for. }
  PickType(ACurrent);
  FChosen := False;

  { On the screen, not off the bottom of it: a row near the foot of the
    window would otherwise open the panel where it cannot be read. }
  if AScreenY + Height > Screen.Height then AScreenY := AScreenY - Height;
  if AScreenX + Width > Screen.Width then AScreenX := Screen.Width - Width;
  if AScreenX < 0 then AScreenX := 0;
  if AScreenY < 0 then AScreenY := 0;
  SetBounds(AScreenX, AScreenY, Width, Height);

  Show;
  FValue.SetFocus;
  FValue.SelectAll;
end;

procedure TLedBJValuePopup.Finish(AAccepted: Boolean);
begin
  if not Visible then Exit;
  Hide;
  if Assigned(FOnDone) then FOnDone(Self, AAccepted);
end;

procedure TLedBJValuePopup.OkClick(Sender: TObject);
begin
  Finish(True);
end;

procedure TLedBJValuePopup.CancelClick(Sender: TObject);
begin
  Finish(False);
end;

{ Return accepts and Escape abandons, wherever the focus is inside the panel.
  KeyPreview is what brings them here from the box and the list. }
procedure TLedBJValuePopup.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    if FOk.Enabled then Finish(True);
    Exit;
  end;
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    Key := 0;
    Finish(False);
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

end.
