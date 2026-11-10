{ LED - a lightweight editor.  "Save these documents?" for a batch close.

  Closing a window with six modified documents in it asked six separate
  questions, one after another, with no way to see how many were coming or to
  answer them together.  medit showed one list; this is that list.

  The dialog is deliberately small: the names, a checkbox each, and three
  answers -- save the ticked ones, discard everything, or go back. }
unit Led.UI.SaveAll;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, StdCtrls, ExtCtrls, CheckLst, Graphics;

type
  TLedSaveManyResult = (lsmSave, lsmDiscard, lsmCancel);

{ Asks about ANames, which are display names in the caller's own order.
  On lsmSave, AChecked is filled with the indices the user left ticked.
  Everything starts ticked, because that is what someone who hits Save
  without reading the list almost always means. }
function LedAskSaveMany(AOwner: TComponent; ANames: TStrings;
  AChecked: TList): TLedSaveManyResult;

{ The dialog itself, not shown, for the self-test to look at its layout. }
function LedSaveManyDialog(AOwner: TComponent; ANames: TStrings): TForm;

implementation

type
  TSaveManyForm = class(TForm)
  private
    FList: TCheckListBox;
    FButtons: array[0..4] of TButton;     { All, None, Save, Discard, Cancel }
    procedure FitButtons;
    procedure DoSave(Sender: TObject);
    procedure DoDiscard(Sender: TObject);
    procedure DoCancel(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure DoSelectNone(Sender: TObject);
  protected
    procedure DoShow; override;
    procedure Activate; override;
  public
    constructor CreateFor(AOwner: TComponent; ANames: TStrings);
    property List: TCheckListBox read FList;
  end;

constructor TSaveManyForm.CreateFor(AOwner: TComponent; ANames: TStrings);
var
  i: Integer;
  Lbl: TLabel;
  Bottom: TPanel;

  { As wide as its caption needs, never narrower than AWidth: the widths
    were pixels once, and a larger interface font ran each caption into the
    button beside it. }
  function AddButton(const ACaption: string; AHandler: TNotifyEvent;
    AResult: TModalResult; AWidth: Integer): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Bottom;
    Result.Caption := ACaption;
    Result.AutoSize := True;
    Result.Constraints.MinWidth := AWidth;
    Result.Constraints.MinHeight := 28;
    Result.Top := 8;
    Result.OnClick := AHandler;
    Result.ModalResult := AResult;
  end;

  { Each button anchored to its neighbour, so none can be laid over another
    whatever the captions come to. }
  procedure Chain(AButton: TButton; ASide: TAnchorKind; ATo: TControl;
    AToSide: TAnchorSideReference; AGap: Integer);
  begin
    AButton.Anchors := [akTop, ASide];
    AButton.AnchorSide[ASide].Control := ATo;
    AButton.AnchorSide[ASide].Side := AToSide;
    if ASide = akLeft then
      AButton.BorderSpacing.Left := AGap
    else
      AButton.BorderSpacing.Right := AGap;
  end;

begin
  inherited CreateNew(AOwner);
  Caption := 'Unsaved changes';
  Position := poOwnerFormCenter;
  BorderStyle := bsDialog;
  Width := 460;
  Height := 320;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Left := 12;
  Lbl.Top := 12;
  Lbl.Width := Width - 24;
  Lbl.WordWrap := True;
  Lbl.Caption := Format(
    'These %d documents have unsaved changes.'#10 +
    'Selected documents will be saved; the rest will be closed as they are.',
    [ANames.Count]);

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 44;
  Bottom.BevelOuter := bvNone;
  Bottom.Caption := '';

  { Right to left, so the default answer sits where the eye lands. }
  FButtons[4] := AddButton('Cancel', @DoCancel, mrCancel, 90);
  Chain(FButtons[4], akRight, Bottom, asrRight, 12);
  FButtons[4].Cancel := True;

  FButtons[3] := AddButton('Close Without Saving', @DoDiscard, mrNo, 150);
  Chain(FButtons[3], akRight, FButtons[4], asrLeft, 8);

  FButtons[2] := AddButton('Save Selected', @DoSave, mrYes, 110);
  Chain(FButtons[2], akRight, FButtons[3], asrLeft, 8);
  FButtons[2].Default := True;

  FButtons[0] := AddButton('All', @DoSelectAll, mrNone, 50);
  Chain(FButtons[0], akLeft, Bottom, asrLeft, 12);
  FButtons[1] := AddButton('None', @DoSelectNone, mrNone, 50);
  Chain(FButtons[1], akLeft, FButtons[0], asrRight, 6);

  FList := TCheckListBox.Create(Self);
  FList.Parent := Self;
  FList.Left := 12;
  FList.Top := 56;
  FList.Width := Width - 24;
  FList.Height := Height - 56 - Bottom.Height - 12;
  FList.Anchors := [akLeft, akTop, akRight, akBottom];
  for i := 0 to ANames.Count - 1 do
    FList.Items.Add(ANames[i]);
  for i := 0 to FList.Items.Count - 1 do
    FList.Checked[i] := True;
end;

{ The dialog is widened to hold its buttons, once they know how wide they
  are: that is after the form scaler has run and the widgetset has measured
  the captions, which is why it is done on showing and again on the first
  activation rather than in the constructor. }
procedure TSaveManyForm.FitButtons;
var
  i, Need, Grow: Integer;
begin
  Need := 0;
  for i := 0 to High(FButtons) do
    Inc(Need, FButtons[i].Width);
  { the margins and gaps, and room between the two groups }
  Inc(Need, Scale96ToForm(12 + 6 + 24 + 8 + 8 + 12));
  Grow := Need - ClientWidth;
  if Grow <= 0 then Exit;
  ClientWidth := Need;
  Left := Left - Grow div 2;
end;

procedure TSaveManyForm.DoShow;
begin
  inherited DoShow;
  FitButtons;
end;

procedure TSaveManyForm.Activate;
begin
  inherited Activate;
  FitButtons;
end;

procedure TSaveManyForm.DoSave(Sender: TObject);
begin
  ModalResult := mrYes;
end;

procedure TSaveManyForm.DoDiscard(Sender: TObject);
begin
  ModalResult := mrNo;
end;

procedure TSaveManyForm.DoCancel(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TSaveManyForm.DoSelectAll(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to FList.Items.Count - 1 do FList.Checked[i] := True;
end;

procedure TSaveManyForm.DoSelectNone(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to FList.Items.Count - 1 do FList.Checked[i] := False;
end;

function LedSaveManyDialog(AOwner: TComponent; ANames: TStrings): TForm;
begin
  Result := TSaveManyForm.CreateFor(AOwner, ANames);
end;

function LedAskSaveMany(AOwner: TComponent; ANames: TStrings;
  AChecked: TList): TLedSaveManyResult;
var
  Dlg: TSaveManyForm;
  i: Integer;
begin
  if AChecked <> nil then AChecked.Clear;
  Dlg := TSaveManyForm.CreateFor(AOwner, ANames);
  try
    case Dlg.ShowModal of
      mrYes:
        begin
          Result := lsmSave;
          if AChecked <> nil then
            for i := 0 to Dlg.List.Items.Count - 1 do
              if Dlg.List.Checked[i] then AChecked.Add(Pointer(PtrInt(i)));
        end;
      mrNo: Result := lsmDiscard;
    else
      Result := lsmCancel;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
