{ led - a light editor.  "Save these documents?" for a batch close.

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

implementation

type
  TSaveManyForm = class(TForm)
  private
    FList: TCheckListBox;
    procedure DoSave(Sender: TObject);
    procedure DoDiscard(Sender: TObject);
    procedure DoCancel(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure DoSelectNone(Sender: TObject);
  public
    constructor CreateFor(AOwner: TComponent; ANames: TStrings);
    property List: TCheckListBox read FList;
  end;

constructor TSaveManyForm.CreateFor(AOwner: TComponent; ANames: TStrings);
var
  i: Integer;
  Lbl: TLabel;
  Bottom: TPanel;
  Btn: TButton;
  X: Integer;

  function AddButton(const ACaption: string; AHandler: TNotifyEvent;
    AResult: TModalResult; AWidth: Integer): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Bottom;
    Result.Caption := ACaption;
    Result.Width := AWidth;
    Result.Height := 28;
    Result.Top := 8;
    Result.OnClick := AHandler;
    Result.ModalResult := AResult;
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
    'Ticked documents will be saved; the rest will be closed as they are.',
    [ANames.Count]);

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 44;
  Bottom.BevelOuter := bvNone;
  Bottom.Caption := '';

  { Right to left, so the default answer sits where the eye lands. }
  X := Width - 12;
  Btn := AddButton('Cancel', @DoCancel, mrCancel, 90);
  Dec(X, Btn.Width); Btn.Left := X;
  Btn.Cancel := True;

  Dec(X, 8);
  Btn := AddButton('Close Without Saving', @DoDiscard, mrNo, 150);
  Dec(X, Btn.Width); Btn.Left := X;

  Dec(X, 8);
  Btn := AddButton('Save Ticked', @DoSave, mrYes, 110);
  Dec(X, Btn.Width); Btn.Left := X;
  Btn.Default := True;

  Btn := AddButton('All', @DoSelectAll, mrNone, 50);
  Btn.Left := 12;
  Btn := AddButton('None', @DoSelectNone, mrNone, 50);
  Btn.Left := 66;

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
