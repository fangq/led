{ led - a light editor.  The bookmark list.

  SynEdit gives ten numbered bookmark slots and the means to jump between
  them, which covers Toggle / Next / Previous.  What it has no notion of is
  seeing them all at once, and that is the thing medit's Edit Bookmarks
  dialog was for: with ten slots spread over a long file, "which ones did I
  set, and where?" is not answerable from the gutter alone. }
unit Led.UI.Bookmarks;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, StdCtrls, ExtCtrls, ComCtrls,
  Led.UI.Edit;

type
  TLedBookmark = record
    Slot: Integer;
    Line: Integer;
    Text: string;
  end;
  TLedBookmarkArray = array of TLedBookmark;

{ Every bookmark in AView, in line order rather than slot order -- which is
  the order a reader thinks in. }
function LedCollectBookmarks(AView: TLedEdit): TLedBookmarkArray;

{ The dialog.  Returns the line to jump to, or 0 if the user did not pick
  one; removals are applied to AView before returning either way. }
function LedEditBookmarks(AOwner: TComponent; AView: TLedEdit): Integer;

implementation

function LedCollectBookmarks(AView: TLedEdit): TLedBookmarkArray;
var
  i, X, Y, n, j: Integer;
  Tmp: TLedBookmark;
begin
  SetLength(Result, 0);
  if AView = nil then Exit;
  n := 0;
  SetLength(Result, 10);
  for i := 0 to 9 do
    if AView.GetBookMark(i, X, Y) then
    begin
      Result[n].Slot := i;
      Result[n].Line := Y;
      if (Y >= 1) and (Y <= AView.Lines.Count) then
        Result[n].Text := Trim(AView.Lines[Y - 1])
      else
        Result[n].Text := '';
      Inc(n);
    end;
  SetLength(Result, n);

  { Ten items at most, so the simplest sort that is obviously right. }
  for i := 0 to High(Result) do
    for j := i + 1 to High(Result) do
      if Result[j].Line < Result[i].Line then
      begin
        Tmp := Result[i]; Result[i] := Result[j]; Result[j] := Tmp;
      end;
end;

type
  TBookmarkForm = class(TForm)
  private
    FView: TLedEdit;
    FList: TListView;
    FGoLine: Integer;
    procedure Fill;
    procedure DoGoTo(Sender: TObject);
    procedure DoRemove(Sender: TObject);
    procedure DoRemoveAll(Sender: TObject);
    procedure DoDblClick(Sender: TObject);
  public
    constructor CreateFor(AOwner: TComponent; AView: TLedEdit);
    property GoLine: Integer read FGoLine;
  end;

constructor TBookmarkForm.CreateFor(AOwner: TComponent; AView: TLedEdit);
var
  Bottom: TPanel;
  Btn: TButton;
  X: Integer;

  function AddButton(const ACaption: string; AHandler: TNotifyEvent;
    AWidth: Integer): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Bottom;
    Result.Caption := ACaption;
    Result.Width := AWidth;
    Result.Height := 28;
    Result.Top := 8;
    Result.OnClick := AHandler;
  end;

begin
  inherited CreateNew(AOwner);
  FView := AView;
  FGoLine := 0;
  Caption := 'Bookmarks';
  Position := poOwnerFormCenter;
  BorderStyle := bsSizeable;
  Width := 520;
  Height := 300;

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 44;
  Bottom.BevelOuter := bvNone;
  Bottom.Caption := '';

  X := Width - 12;
  Btn := AddButton('Close', nil, 90);
  Dec(X, Btn.Width); Btn.Left := X;
  Btn.ModalResult := mrCancel;
  Btn.Cancel := True;

  Dec(X, 8);
  Btn := AddButton('Go To', @DoGoTo, 90);
  Dec(X, Btn.Width); Btn.Left := X;
  Btn.Default := True;

  Btn := AddButton('Remove', @DoRemove, 90);
  Btn.Left := 12;
  Btn := AddButton('Remove All', @DoRemoveAll, 100);
  Btn.Left := 106;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.BorderSpacing.Around := 8;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnDblClick := @DoDblClick;
  FList.Columns.Add.Caption := 'Slot';
  FList.Columns[0].Width := 50;
  FList.Columns.Add.Caption := 'Line';
  FList.Columns[1].Width := 70;
  FList.Columns.Add.Caption := 'Text';
  FList.Columns[2].Width := 360;

  Fill;
end;

procedure TBookmarkForm.Fill;
var
  Marks: TLedBookmarkArray;
  i: Integer;
  It: TListItem;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    Marks := LedCollectBookmarks(FView);
    for i := 0 to High(Marks) do
    begin
      It := FList.Items.Add;
      It.Caption := IntToStr(Marks[i].Slot);
      It.SubItems.Add(IntToStr(Marks[i].Line));
      It.SubItems.Add(Marks[i].Text);
      { The slot is what removal needs; the line is what Go To needs. }
      It.Data := Pointer(PtrInt(Marks[i].Slot));
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count > 0 then FList.Items[0].Selected := True;
end;

procedure TBookmarkForm.DoGoTo(Sender: TObject);
begin
  if FList.Selected = nil then Exit;
  FGoLine := StrToIntDef(FList.Selected.SubItems[0], 0);
  ModalResult := mrOK;
end;

procedure TBookmarkForm.DoDblClick(Sender: TObject);
begin
  DoGoTo(Sender);
end;

procedure TBookmarkForm.DoRemove(Sender: TObject);
begin
  if FList.Selected = nil then Exit;
  FView.ClearBookMark(PtrInt(FList.Selected.Data));
  Fill;
end;

procedure TBookmarkForm.DoRemoveAll(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to 9 do FView.ClearBookMark(i);
  Fill;
end;

function LedEditBookmarks(AOwner: TComponent; AView: TLedEdit): Integer;
var
  Dlg: TBookmarkForm;
begin
  Result := 0;
  if AView = nil then Exit;
  Dlg := TBookmarkForm.CreateFor(AOwner, AView);
  try
    if Dlg.ShowModal = mrOK then Result := Dlg.GoLine;
  finally
    Dlg.Free;
  end;
end;

end.
