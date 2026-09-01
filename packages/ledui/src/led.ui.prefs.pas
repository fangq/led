{ led - a light editor.  The preferences dialog.

  medit authored nine preference pages as Glade files compiled to C. Here the
  whole dialog is driven by one table: each row names a category, a
  preference key, a caption and a kind, and the dialog builds the controls,
  loads them and writes them back.

  Adding a setting is one line in that table. That is the entire reason for
  the design -- a preferences dialog is the part of an editor most likely to
  rot, and the cheapest way to keep it honest is to make the cost of a new
  setting nearly zero. }
unit Led.UI.Prefs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Spin,
  Dialogs, Graphics,
  Led.Core.Prefs, Led.Syn.Theme;

type
  TLedPrefKind = (pkBool, pkInt, pkString, pkChoice, pkFont, pkHeading);

  TLedPrefItem = record
    Category: string;
    Kind: TLedPrefKind;
    Key: string;
    Caption: string;
    DefStr: string;
    DefInt: Integer;
    MinInt: Integer;
    MaxInt: Integer;
    Choices: string;     // comma-separated; '@themes' means "the theme list"
  end;

  TLedPrefsDialog = class(TForm)
  private
    FTree: TTreeView;
    FPages: TPanel;
    FCategories: TStringList;   // name -> TPanel
    FControls: TStringList;     // pref key -> control
    FKinds: TStringList;        // pref key -> Ord(kind)
    FFontLabels: TStringList;   // pref key -> the label showing the font
    procedure Build;
    function PageFor(const ACategory: string): TPanel;
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure PickFont(Sender: TObject);
    procedure DoOK(Sender: TObject);
    procedure DoApply(Sender: TObject);
    procedure DoCancel(Sender: TObject);
  public
    { Raised after Apply or OK so the window can re-read anything that
      changed. }
    OnApplied: TNotifyEvent;
    constructor CreateDialog(AOwner: TComponent);
    destructor Destroy; override;
    procedure LoadFromPrefs;
    procedure ApplyToPrefs;
  end;

implementation

const
  { The whole preferences surface.  Keys are medit's, so the vocabulary
    carries over even though the storage format does not.  Every field is
    spelled out because FPC requires typed-constant records to be complete
    and in order. }
  PrefItems: array[0..21] of TLedPrefItem = (
    (Category: 'General'; Kind: pkHeading; Key: '';
     Caption: 'Indentation'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkInt; Key: 'Editor/tab_width';
     Caption: 'Tab width'; DefStr: '';
     DefInt: 8; MinInt: 1; MaxInt: 32; Choices: ''),
    (Category: 'General'; Kind: pkInt; Key: 'Editor/indent_width';
     Caption: 'Indent width'; DefStr: '';
     DefInt: 4; MinInt: 1; MaxInt: 32; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/spaces_instead_of_tabs';
     Caption: 'Insert spaces instead of tabs'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/auto_indent';
     Caption: 'Indent a new line like the one above'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkHeading; Key: '';
     Caption: 'Session'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/save_session';
     Caption: 'Reopen the last session at startup'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkHeading; Key: '';
     Caption: 'Appearance'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkFont; Key: 'Editor/font';
     Caption: 'Editor font'; DefStr: 'Monospace 10';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkChoice; Key: 'Editor/color_scheme';
     Caption: 'Colour scheme'; DefStr: 'medit';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: '@themes'),
    (Category: 'View'; Kind: pkHeading; Key: '';
     Caption: 'The text area'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/show_line_numbers';
     Caption: 'Show line numbers'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/highlight_current_line';
     Caption: 'Highlight the current line'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/draw_right_margin';
     Caption: 'Show a right margin'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkInt; Key: 'Editor/right_margin_offset';
     Caption: 'Right margin at column'; DefStr: '';
     DefInt: 80; MinInt: 20; MaxInt: 250; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/wrapping_enable';
     Caption: 'Wrap long lines'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkHeading; Key: '';
     Caption: 'Saving'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkBool; Key: 'Editor/make_backups';
     Caption: 'Keep a backup copy (name~) when saving'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkBool; Key: 'Editor/strip';
     Caption: 'Strip trailing whitespace on save'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkBool; Key: 'Editor/add_newline';
     Caption: 'End the file with a newline'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkHeading; Key: '';
     Caption: 'Opening'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkString; Key: 'Editor/encodings';
     Caption: 'Encodings to try, in order'; DefStr: 'utf8,LOCALE,iso885915,iso88591';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: '')
  );

constructor TLedPrefsDialog.CreateDialog(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  FCategories := TStringList.Create;
  FControls := TStringList.Create;
  FKinds := TStringList.Create;
  FFontLabels := TStringList.Create;
  Build;
end;

destructor TLedPrefsDialog.Destroy;
begin
  FCategories.Free;
  FControls.Free;
  FKinds.Free;
  FFontLabels.Free;
  inherited Destroy;
end;

function TLedPrefsDialog.PageFor(const ACategory: string): TPanel;
var
  i: Integer;
  P: TPanel;
  Node: TTreeNode;
begin
  i := FCategories.IndexOf(ACategory);
  if i >= 0 then Exit(TPanel(FCategories.Objects[i]));

  P := TPanel.Create(Self);
  P.Parent := FPages;
  P.Align := alClient;
  P.BevelOuter := bvNone;
  P.Caption := '';
  P.Visible := FCategories.Count = 0;
  FCategories.AddObject(ACategory, P);

  Node := FTree.Items.Add(nil, ACategory);
  Node.Data := P;
  if FCategories.Count = 1 then
    FTree.Selected := Node;
  Result := P;
end;

procedure TLedPrefsDialog.Build;
var
  i, Y: Integer;
  Page: TPanel;
  Item: TLedPrefItem;
  Lbl: TLabel;
  Chk: TCheckBox;
  Spn: TSpinEdit;
  Edt: TEdit;
  Cbo: TComboBox;
  Btn: TButton;
  Bottom: TPanel;
  Tops: TStringList;
  j: Integer;

  function NextY(const ACat: string; ADelta: Integer): Integer;
  var
    k: Integer;
  begin
    k := Tops.IndexOf(ACat);
    if k < 0 then k := Tops.Add(ACat);
    Result := PtrInt(Tops.Objects[k]) + 12;
    Tops.Objects[k] := TObject(PtrInt(Result + ADelta));
  end;

begin
  Caption := 'Preferences';
  Position := poMainFormCenter;
  Width := 640;
  Height := 480;
  BorderStyle := bsSizeable;

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 44;
  Bottom.BevelOuter := bvNone;
  Bottom.Caption := '';

  Btn := TButton.Create(Self);
  Btn.Parent := Bottom; Btn.Caption := 'OK'; Btn.Width := 90;
  Btn.Anchors := [akRight, akTop]; Btn.Left := 340; Btn.Top := 8;
  Btn.OnClick := @DoOK; Btn.Default := True;

  Btn := TButton.Create(Self);
  Btn.Parent := Bottom; Btn.Caption := 'Cancel'; Btn.Width := 90;
  Btn.Anchors := [akRight, akTop]; Btn.Left := 438; Btn.Top := 8;
  Btn.OnClick := @DoCancel; Btn.Cancel := True;

  Btn := TButton.Create(Self);
  Btn.Parent := Bottom; Btn.Caption := 'Apply'; Btn.Width := 90;
  Btn.Anchors := [akRight, akTop]; Btn.Left := 536; Btn.Top := 8;
  Btn.OnClick := @DoApply;

  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alLeft;
  FTree.Width := 150;
  FTree.ReadOnly := True;
  FTree.ShowRoot := False;
  FTree.ShowLines := False;
  FTree.OnChange := @TreeChange;

  FPages := TPanel.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.BevelOuter := bvNone;
  FPages.Caption := '';

  Tops := TStringList.Create;
  try
    for i := Low(PrefItems) to High(PrefItems) do
    begin
      Item := PrefItems[i];
      Page := PageFor(Item.Category);

      case Item.Kind of
        pkHeading:
          begin
            Y := NextY(Item.Category, 20);
            Lbl := TLabel.Create(Self);
            Lbl.Parent := Page;
            Lbl.Caption := Item.Caption;
            Lbl.Font.Style := [fsBold];
            Lbl.Left := 12;
            Lbl.Top := Y;
          end;
        pkBool:
          begin
            Y := NextY(Item.Category, 22);
            Chk := TCheckBox.Create(Self);
            Chk.Parent := Page;
            Chk.Caption := Item.Caption;
            Chk.Left := 24;
            Chk.Top := Y;
            Chk.Width := 420;
            FControls.AddObject(Item.Key, Chk);
            FKinds.AddObject(Item.Key, TObject(PtrInt(Ord(Item.Kind))));
          end;
        pkInt:
          begin
            Y := NextY(Item.Category, 26);
            Lbl := TLabel.Create(Self);
            Lbl.Parent := Page; Lbl.Caption := Item.Caption;
            Lbl.Left := 24; Lbl.Top := Y + 4;
            Spn := TSpinEdit.Create(Self);
            Spn.Parent := Page;
            Spn.Left := 300; Spn.Top := Y; Spn.Width := 80;
            Spn.MinValue := Item.MinInt; Spn.MaxValue := Item.MaxInt;
            FControls.AddObject(Item.Key, Spn);
            FKinds.AddObject(Item.Key, TObject(PtrInt(Ord(Item.Kind))));
          end;
        pkString:
          begin
            Y := NextY(Item.Category, 26);
            Lbl := TLabel.Create(Self);
            Lbl.Parent := Page; Lbl.Caption := Item.Caption;
            Lbl.Left := 24; Lbl.Top := Y + 4;
            Edt := TEdit.Create(Self);
            Edt.Parent := Page;
            Edt.Left := 300; Edt.Top := Y; Edt.Width := 300;
            Edt.Anchors := [akLeft, akTop, akRight];
            FControls.AddObject(Item.Key, Edt);
            FKinds.AddObject(Item.Key, TObject(PtrInt(Ord(Item.Kind))));
          end;
        pkChoice:
          begin
            Y := NextY(Item.Category, 26);
            Lbl := TLabel.Create(Self);
            Lbl.Parent := Page; Lbl.Caption := Item.Caption;
            Lbl.Left := 24; Lbl.Top := Y + 4;
            Cbo := TComboBox.Create(Self);
            Cbo.Parent := Page;
            Cbo.Left := 300; Cbo.Top := Y; Cbo.Width := 200;
            Cbo.Style := csDropDownList;
            if Item.Choices = '@themes' then
              for j := 0 to LedThemes.Count - 1 do
                Cbo.Items.AddObject(LedThemes[j].Name,
                  TObject(PtrInt(j)))
            else
              Cbo.Items.CommaText := Item.Choices;
            FControls.AddObject(Item.Key, Cbo);
            FKinds.AddObject(Item.Key, TObject(PtrInt(Ord(Item.Kind))));
          end;
        pkFont:
          begin
            Y := NextY(Item.Category, 28);
            Lbl := TLabel.Create(Self);
            Lbl.Parent := Page; Lbl.Caption := Item.Caption;
            Lbl.Left := 24; Lbl.Top := Y + 4;
            Lbl := TLabel.Create(Self);
            Lbl.Parent := Page; Lbl.Left := 300; Lbl.Top := Y + 4;
            Lbl.Width := 200;
            FFontLabels.AddObject(Item.Key, Lbl);
            Btn := TButton.Create(Self);
            Btn.Parent := Page; Btn.Caption := 'Choose...';
            Btn.Left := 510; Btn.Top := Y; Btn.Width := 90;
            Btn.Hint := Item.Key;
            Btn.OnClick := @PickFont;
            FControls.AddObject(Item.Key, Lbl);
            FKinds.AddObject(Item.Key, TObject(PtrInt(Ord(Item.Kind))));
          end;
      end;
    end;
  finally
    Tops.Free;
  end;
end;

procedure TLedPrefsDialog.TreeChange(Sender: TObject; Node: TTreeNode);
var
  i: Integer;
begin
  for i := 0 to FCategories.Count - 1 do
    TPanel(FCategories.Objects[i]).Visible :=
      (Node <> nil) and (FCategories.Objects[i] = TObject(Node.Data));
end;

procedure TLedPrefsDialog.PickFont(Sender: TObject);
var
  Dlg: TFontDialog;
  Key: string;
  i: Integer;
  Lbl: TLabel;
begin
  Key := TButton(Sender).Hint;
  i := FFontLabels.IndexOf(Key);
  if i < 0 then Exit;
  Lbl := TLabel(FFontLabels.Objects[i]);

  Dlg := TFontDialog.Create(Self);
  try
    { The stored form is "Family Size", as medit wrote it. }
    Dlg.Font.Name := Copy(Lbl.Caption, 1, LastDelimiter(' ', Lbl.Caption) - 1);
    Dlg.Font.Size := StrToIntDef(
      Copy(Lbl.Caption, LastDelimiter(' ', Lbl.Caption) + 1, MaxInt), 10);
    if Dlg.Execute then
      Lbl.Caption := Format('%s %d', [Dlg.Font.Name, Dlg.Font.Size]);
  finally
    Dlg.Free;
  end;
end;

procedure TLedPrefsDialog.LoadFromPrefs;
var
  i, j: Integer;
  Key: string;
  Kind: TLedPrefKind;
  Ctl: TObject;
  Item: TLedPrefItem;

  function ItemFor(const AKey: string): TLedPrefItem;
  var
    k: Integer;
  begin
    for k := Low(PrefItems) to High(PrefItems) do
      if PrefItems[k].Key = AKey then Exit(PrefItems[k]);
    Result := Default(TLedPrefItem);
  end;

begin
  for i := 0 to FControls.Count - 1 do
  begin
    Key := FControls[i];
    Ctl := FControls.Objects[i];
    Kind := TLedPrefKind(PtrInt(FKinds.Objects[FKinds.IndexOf(Key)]));
    Item := ItemFor(Key);
    case Kind of
      pkBool:   TCheckBox(Ctl).Checked := LedPrefs.GetBool(Key, Item.DefInt <> 0);
      pkInt:    TSpinEdit(Ctl).Value := LedPrefs.GetInt(Key, Item.DefInt);
      pkString: TEdit(Ctl).Text := LedPrefs.GetStr(Key, Item.DefStr);
      pkFont:   TLabel(Ctl).Caption := LedPrefs.GetStr(Key, Item.DefStr);
      pkChoice:
        begin
          if Item.Choices = '@themes' then
          begin
            TComboBox(Ctl).ItemIndex := 0;
            for j := 0 to LedThemes.Count - 1 do
              if SameText(LedThemes[j].Id, LedPrefs.GetStr(Key, Item.DefStr)) then
                TComboBox(Ctl).ItemIndex := j;
          end
          else
            TComboBox(Ctl).ItemIndex :=
              TComboBox(Ctl).Items.IndexOf(LedPrefs.GetStr(Key, Item.DefStr));
        end;
    end;
  end;
end;

procedure TLedPrefsDialog.ApplyToPrefs;
var
  i, Idx: Integer;
  Key: string;
  Kind: TLedPrefKind;
  Ctl: TObject;
begin
  for i := 0 to FControls.Count - 1 do
  begin
    Key := FControls[i];
    Ctl := FControls.Objects[i];
    Kind := TLedPrefKind(PtrInt(FKinds.Objects[FKinds.IndexOf(Key)]));
    case Kind of
      pkBool:   LedPrefs.SetBool(Key, TCheckBox(Ctl).Checked);
      pkInt:    LedPrefs.SetInt(Key, TSpinEdit(Ctl).Value);
      pkString: LedPrefs.SetStr(Key, TEdit(Ctl).Text);
      pkFont:   LedPrefs.SetStr(Key, TLabel(Ctl).Caption);
      pkChoice:
        begin
          Idx := TComboBox(Ctl).ItemIndex;
          if Idx < 0 then Continue;
          { The theme list stores ids, not the display names shown. }
          if (Key = 'Editor/color_scheme') and (Idx < LedThemes.Count) then
            LedPrefs.SetStr(Key, LedThemes[Idx].Id)
          else
            LedPrefs.SetStr(Key, TComboBox(Ctl).Items[Idx]);
        end;
    end;
  end;
  LedPrefs.Save;
end;

procedure TLedPrefsDialog.DoApply(Sender: TObject);
begin
  ApplyToPrefs;
  if Assigned(OnApplied) then OnApplied(Self);
end;

procedure TLedPrefsDialog.DoOK(Sender: TObject);
begin
  DoApply(Sender);
  ModalResult := mrOK;
end;

procedure TLedPrefsDialog.DoCancel(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

end.
