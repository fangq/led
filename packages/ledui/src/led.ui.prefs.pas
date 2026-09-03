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
  Grids, Dialogs, Graphics, LCLType, LConvEncoding,
  Led.Core.Prefs, Led.Core.Tools, Led.Core.Filters, Led.Core.Paths,
  Led.Syn.Theme, Led.Syn.Languages;

type
  TLedPrefKind = (pkBool, pkInt, pkString, pkChoice, pkFont, pkHeading,
                  { A page the table cannot describe: a list of things
                    rather than a set of scalars.  Key names the builder. }
                  pkCustom);

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

    { Languages page }
    FLangList: TComboBox;
    FLangGlobs, FLangMimes, FLangOptions: TEdit;
    FLangLoading: Boolean;

    { File filters page }
    FFilterGrid: TStringGrid;

    { Tools page }
    FToolList: TListBox;
    FToolName, FToolFiles, FToolLangs, FToolAccel: TEdit;
    FToolKind, FToolPlace, FToolInput, FToolOutput, FToolFilter: TComboBox;
    FToolEnabled: TCheckBox;
    FToolCode: TMemo;
    FTools: TLedTools;
    FToolLoading: Boolean;
    procedure Build;
    function PageFor(const ACategory: string): TPanel;

    { The three pages whose content is a list rather than a set of scalars.
      Each owns its own controls and its own load/apply, because a table
      that could describe them would be harder to read than the code. }
    procedure BuildLanguagesPage(APage: TPanel);
    procedure BuildFiltersPage(APage: TPanel);
    procedure BuildToolsPage(APage: TPanel);
    procedure LangSelected(Sender: TObject);
    procedure FilterRowChanged(Sender: TObject);
    procedure FilterAdd(Sender: TObject);
    procedure FilterDelete(Sender: TObject);
    procedure FilterMove(Sender: TObject);
    procedure ToolSelected(Sender: TObject);
    procedure ToolFieldChanged(Sender: TObject);
    procedure LoadLanguages;
    procedure LoadFilters;
    procedure LoadTools;
    procedure ApplyLanguages;
    procedure ApplyFilters;
    procedure ApplyTools;
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

    { For the self-test: how many pages the dialog built, whether the three
      list pages produced their controls, and a way to add a filter row
      without driving the grid by hand. }
    function PageCount: Integer;
    function ListPagesReady: Boolean;
    procedure AddFilterRow(const AFilter, AConfig: string);
  end;

implementation

const
  { The whole preferences surface.  Keys are medit's, so the vocabulary
    carries over even though the storage format does not.  Every field is
    spelled out because FPC requires typed-constant records to be complete
    and in order. }
  PrefItems: array[0..49] of TLedPrefItem = (
    (Category: 'General'; Kind: pkHeading; Key: '';
     Caption: 'Indentation'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkInt; Key: 'Editor/tab_width';
     Caption: 'Tab width'; DefStr: '';
     DefInt: 8; MinInt: 1; MaxInt: 100; Choices: ''),
    (Category: 'General'; Kind: pkInt; Key: 'Editor/indent_width';
     Caption: 'Indent width'; DefStr: '';
     DefInt: 4; MinInt: 1; MaxInt: 100; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/spaces_instead_of_tabs';
     Caption: 'Insert spaces instead of tabs'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/auto_indent';
     Caption: 'Indent a new line like the one above'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkHeading; Key: '';
     Caption: 'Keys'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/smart_home_end';
     Caption: 'Home and End go to the text, not the margin'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/backspace_indents';
     Caption: 'Backspace unindents'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/tab_indents';
     Caption: 'Tab indents the selection'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkHeading; Key: '';
     Caption: 'Session'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/save_session';
     Caption: 'Reopen the last session at startup'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/show_toolbar';
     Caption: 'Show the toolbar'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/lock_pane_layout';
     Caption: 'Lock the pane layout (no dragging panes by their header)';
     DefStr: ''; DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/show_pane_buttons';
     Caption: 'Show pane buttons on the window edges'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/recovery_enabled';
     Caption: 'Keep unsaved changes for recovery after a crash'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkInt; Key: 'Editor/recovery_interval';
     Caption: 'Recovery snapshot interval (seconds)'; DefStr: '';
     DefInt: 20; MinInt: 5; MaxInt: 600; Choices: ''),
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
     Caption: 'Highlighting'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/enable_highlighting';
     Caption: 'Colour the syntax'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/highlight_matching_brackets';
     Caption: 'Highlight the matching bracket'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/highlight_mismatching_brackets';
     Caption: 'Highlight an unmatched bracket'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/highlight_current_line';
     Caption: 'Highlight the current line'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkHeading; Key: '';
     Caption: 'The text area'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/show_line_numbers';
     Caption: 'Show line numbers'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/show_tabs';
     Caption: 'Show tabs'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/show_spaces';
     Caption: 'Show spaces'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/show_trailing_spaces';
     Caption: 'Show trailing spaces'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/draw_right_margin';
     Caption: 'Show a right margin'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkInt; Key: 'Editor/right_margin_offset';
     Caption: 'Right margin at column'; DefStr: '';
     DefInt: 80; MinInt: 1; MaxInt: 1000; Choices: ''),
    (Category: 'View'; Kind: pkHeading; Key: '';
     Caption: 'Wrapping'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/wrapping_enable';
     Caption: 'Wrap long lines'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'View'; Kind: pkBool; Key: 'Editor/wrapping_dont_split_words';
     Caption: 'Do not split words when wrapping'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkHeading; Key: '';
     Caption: 'Opening'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkString; Key: 'Editor/encodings';
     Caption: 'Encodings to try, in order'; DefStr: 'utf8,LOCALE,iso885915,iso88591';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkBool; Key: 'Editor/auto_sync';
     Caption: 'Reload a file when it changes on disk'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkBool; Key: 'Editor/open_dialog_follows_doc';
     Caption: 'Open and Save As start in the document folder'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkHeading; Key: '';
     Caption: 'Saving'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkChoice; Key: 'Editor/encoding_save';
     Caption: 'Encoding for new files'; DefStr: 'utf8';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: '@encodings'),
    (Category: 'Files'; Kind: pkBool; Key: 'Editor/make_backups';
     Caption: 'Keep a backup copy (name~) when saving'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkBool; Key: 'Editor/strip';
     Caption: 'Strip trailing whitespace on save'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Files'; Kind: pkBool; Key: 'Editor/add_newline';
     Caption: 'End the file with a newline'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkInt; Key: 'Editor/max_line_len';
     Caption: 'Truncate display of lines longer than'; DefStr: '';
     DefInt: 4096; MinInt: 0; MaxInt: 1000000; Choices: ''),
    (Category: 'General'; Kind: pkHeading; Key: '';
     Caption: 'Spelling'; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkBool; Key: 'Editor/spell_enabled';
     Caption: 'Check spelling as you type'; DefStr: '';
     DefInt: 1; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'General'; Kind: pkChoice; Key: 'Editor/spell_scope';
     Caption: 'Check'; DefStr: 'auto';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: 'auto,code,all'),
    (Category: 'Languages'; Kind: pkCustom; Key: '@languages';
     Caption: ''; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'File Filters'; Kind: pkCustom; Key: '@filters';
     Caption: ''; DefStr: '';
     DefInt: 0; MinInt: 0; MaxInt: 0; Choices: ''),
    (Category: 'Tools'; Kind: pkCustom; Key: '@tools';
     Caption: ''; DefStr: '';
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
  FTools.Free;
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
            else if Item.Choices = '@encodings' then
              GetSupportedEncodings(Cbo.Items)
            else
              Cbo.Items.CommaText := Item.Choices;
            FControls.AddObject(Item.Key, Cbo);
            FKinds.AddObject(Item.Key, TObject(PtrInt(Ord(Item.Kind))));
          end;
        pkCustom:
          begin
            { The page owns its whole surface, so no running Y is kept for
              it and its controls anchor to the panel instead. }
            if Item.Key = '@languages' then BuildLanguagesPage(Page)
            else if Item.Key = '@filters' then BuildFiltersPage(Page)
            else if Item.Key = '@tools' then BuildToolsPage(Page);
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

  { The list pages carry their own state. }
  LoadLanguages;
  LoadFilters;
  LoadTools;
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

  ApplyLanguages;
  ApplyFilters;
  ApplyTools;
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


{ ---- Languages ---------------------------------------------------------
  medit let you override a language's file globs, mime types and per-language
  settings.  The globs drive detection, so this is the page people reach for
  when a project uses .inc for C rather than Pascal. }

procedure TLedPrefsDialog.BuildLanguagesPage(APage: TPanel);
var
  Lbl: TLabel;

  function Row(const ACaption: string; ATop: Integer): TEdit;
  begin
    Lbl := TLabel.Create(Self);
    Lbl.Parent := APage; Lbl.Caption := ACaption;
    Lbl.Left := 24; Lbl.Top := ATop + 4;
    Result := TEdit.Create(Self);
    Result.Parent := APage;
    Result.Left := 140; Result.Top := ATop; Result.Width := 420;
    Result.Anchors := [akLeft, akTop, akRight];
    Result.OnChange := @LangSelected;
  end;

begin
  Lbl := TLabel.Create(Self);
  Lbl.Parent := APage;
  Lbl.Caption := 'Language-specific options';
  Lbl.Font.Style := [fsBold];
  Lbl.Left := 12; Lbl.Top := 12;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := APage; Lbl.Caption := 'Language:';
  Lbl.Left := 24; Lbl.Top := 46;

  FLangList := TComboBox.Create(Self);
  FLangList.Parent := APage;
  FLangList.Left := 140; FLangList.Top := 42; FLangList.Width := 420;
  FLangList.Anchors := [akLeft, akTop, akRight];
  FLangList.Style := csDropDownList;
  FLangList.OnChange := @LangSelected;

  FLangGlobs   := Row('Extensions:', 78);
  FLangMimes   := Row('Mime types:', 110);
  FLangOptions := Row('Options:', 142);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := APage;
  Lbl.Caption := 'Extensions are semicolon-separated globs, for example ' +
    '*.c;*.h.  Options use the same' + LineEnding +
    'names as a modeline, for example  indent-width: 2; use-tabs: false';
  Lbl.Left := 24; Lbl.Top := 182;
end;

procedure TLedPrefsDialog.LoadLanguages;
var
  i: Integer;
  Ids: TStringList;
begin
  if FLangList = nil then Exit;
  FLangLoading := True;
  try
    FLangList.Items.BeginUpdate;
    FLangList.Items.Clear;
    Ids := TStringList.Create;
    try
      for i := 0 to LedLanguages.Count - 1 do
        Ids.AddObject(LedLanguages[i].Name, LedLanguages[i]);
      Ids.Sort;
      FLangList.Items.Assign(Ids);
    finally
      Ids.Free;
    end;
    FLangList.Items.EndUpdate;
    if FLangList.Items.Count > 0 then FLangList.ItemIndex := 0;
  finally
    FLangLoading := False;
  end;
  LangSelected(nil);
end;

procedure TLedPrefsDialog.LangSelected(Sender: TObject);
var
  Info: TLedLangInfo;
  Id: string;
begin
  if FLangLoading or (FLangList = nil) or (FLangList.ItemIndex < 0) then Exit;
  Info := TLedLangInfo(FLangList.Items.Objects[FLangList.ItemIndex]);
  if Info = nil then Exit;
  Id := Info.Id;

  { A change to one of the entries is written straight back, so switching
    language in the combo does not silently drop what was just typed. }
  if Sender = FLangGlobs then
    LedPrefs.SetStr('Languages/' + Id + '/globs', FLangGlobs.Text)
  else if Sender = FLangMimes then
    LedPrefs.SetStr('Languages/' + Id + '/mimetypes', FLangMimes.Text)
  else if Sender = FLangOptions then
    LedPrefs.SetStr('Languages/' + Id + '/config', FLangOptions.Text)
  else
  begin
    FLangLoading := True;
    try
      FLangGlobs.Text := LedPrefs.GetStr('Languages/' + Id + '/globs',
        Info.GlobsText);
      FLangMimes.Text := LedPrefs.GetStr('Languages/' + Id + '/mimetypes',
        Info.MimeTypesText);
      FLangOptions.Text := LedPrefs.GetStr('Languages/' + Id + '/config', '');
    finally
      FLangLoading := False;
    end;
  end;
end;

procedure TLedPrefsDialog.ApplyLanguages;
begin
  { Each edit writes through as it changes, so there is nothing left to do
    here beyond making the registry re-read the overrides. }
  if FLangList <> nil then LedLanguages.ApplyOverrides;
end;

{ ---- File filters ------------------------------------------------------
  A filter is a match rule and a settings string, applied to every document
  whose name or language matches.  Two editable columns and four buttons,
  which is what medit had. }

procedure TLedPrefsDialog.BuildFiltersPage(APage: TPanel);
var
  Lbl: TLabel;
  Btn: TButton;
  Bar: TPanel;

  function AddButton(const ACaption: string; AHandler: TNotifyEvent;
    ATag, ALeft: Integer): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Bar;
    Result.Caption := ACaption;
    Result.Left := ALeft; Result.Top := 4;
    Result.Width := 90; Result.Height := 26;
    Result.Tag := ATag;
    Result.OnClick := AHandler;
  end;

begin
  Lbl := TLabel.Create(Self);
  Lbl.Parent := APage;
  Lbl.Caption := 'File filters';
  Lbl.Font.Style := [fsBold];
  Lbl.Left := 12; Lbl.Top := 12;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := APage;
  Lbl.Caption := 'A filter is  globs:*.mk;Makefile*  or  langs:python  or  ' +
    'regex:...' + LineEnding +
    'The settings are written as in a modeline:  indent-use-tabs: true; ' +
    'tab-width: 8';
  Lbl.Left := 12; Lbl.Top := 34;

  Bar := TPanel.Create(Self);
  Bar.Parent := APage;
  Bar.Align := alBottom;
  Bar.Height := 34;
  Bar.BevelOuter := bvNone;
  Bar.Caption := '';

  AddButton('New', @FilterAdd, 0, 8);
  AddButton('Delete', @FilterDelete, 0, 104);
  AddButton('Move Up', @FilterMove, -1, 208);
  AddButton('Move Down', @FilterMove, 1, 304);

  FFilterGrid := TStringGrid.Create(Self);
  FFilterGrid.Parent := APage;
  FFilterGrid.Left := 12; FFilterGrid.Top := 80;
  FFilterGrid.Width := APage.Width - 24;
  FFilterGrid.Height := 260;
  FFilterGrid.Anchors := [akLeft, akTop, akRight, akBottom];
  FFilterGrid.ColCount := 2;
  FFilterGrid.FixedCols := 0;
  FFilterGrid.RowCount := 1;
  FFilterGrid.Options := FFilterGrid.Options +
    [goEditing, goRowSelect, goColSizing, goVertLine, goHorzLine];
  FFilterGrid.Cells[0, 0] := 'Filter';
  FFilterGrid.Cells[1, 0] := 'Settings';
  FFilterGrid.ColWidths[0] := 240;
  FFilterGrid.ColWidths[1] := 320;
  FFilterGrid.OnEditingDone := @FilterRowChanged;
end;

procedure TLedPrefsDialog.LoadFilters;
var
  i: Integer;
begin
  if FFilterGrid = nil then Exit;
  LedFilters.LoadFromPrefs;
  FFilterGrid.RowCount := LedFilters.Count + 1;
  for i := 0 to LedFilters.Count - 1 do
  begin
    FFilterGrid.Cells[0, i + 1] := LedFilters[i].Definition;
    FFilterGrid.Cells[1, i + 1] := LedFilters[i].Config;
  end;
end;

procedure TLedPrefsDialog.FilterRowChanged(Sender: TObject);
begin
  { Nothing to do until Apply; the grid is the model while the page is open. }
end;

procedure TLedPrefsDialog.FilterAdd(Sender: TObject);
begin
  FFilterGrid.RowCount := FFilterGrid.RowCount + 1;
  FFilterGrid.Cells[0, FFilterGrid.RowCount - 1] := 'globs:*.txt';
  FFilterGrid.Cells[1, FFilterGrid.RowCount - 1] := 'indent-width: 4';
  FFilterGrid.Row := FFilterGrid.RowCount - 1;
end;

procedure TLedPrefsDialog.FilterDelete(Sender: TObject);
begin
  if FFilterGrid.Row < 1 then Exit;
  FFilterGrid.DeleteRow(FFilterGrid.Row);
end;

procedure TLedPrefsDialog.FilterMove(Sender: TObject);
var
  Target: Integer;
begin
  Target := FFilterGrid.Row + TButton(Sender).Tag;
  if (FFilterGrid.Row < 1) or (Target < 1) or
     (Target > FFilterGrid.RowCount - 1) then Exit;
  FFilterGrid.ExchangeColRow(False, FFilterGrid.Row, Target);
  FFilterGrid.Row := Target;
end;

procedure TLedPrefsDialog.ApplyFilters;
var
  i: Integer;
begin
  if FFilterGrid = nil then Exit;
  LedFilters.Clear;
  for i := 1 to FFilterGrid.RowCount - 1 do
    if Trim(FFilterGrid.Cells[0, i]) <> '' then
      LedFilters.Add(Trim(FFilterGrid.Cells[0, i]),
                     Trim(FFilterGrid.Cells[1, i]));
  LedFilters.SaveToPrefs;
end;

{ ---- Tools -------------------------------------------------------------
  medit split this into two tabs, one per menu.  Here the menu a tool belongs
  to is just another field, which is one control instead of a duplicated
  page. }

procedure TLedPrefsDialog.BuildToolsPage(APage: TPanel);
var
  Lbl: TLabel;
  Right: TPanel;

  function Row(const ACaption: string; ATop: Integer): TEdit;
  begin
    Lbl := TLabel.Create(Self);
    Lbl.Parent := Right; Lbl.Caption := ACaption;
    Lbl.Left := 0; Lbl.Top := ATop + 4;
    Result := TEdit.Create(Self);
    Result.Parent := Right;
    Result.Left := 90; Result.Top := ATop; Result.Width := 260;
    Result.Anchors := [akLeft, akTop, akRight];
    Result.OnChange := @ToolFieldChanged;
  end;

  function Choice(const ACaption, AItems: string; ATop: Integer): TComboBox;
  begin
    Lbl := TLabel.Create(Self);
    Lbl.Parent := Right; Lbl.Caption := ACaption;
    Lbl.Left := 0; Lbl.Top := ATop + 4;
    Result := TComboBox.Create(Self);
    Result.Parent := Right;
    Result.Left := 90; Result.Top := ATop; Result.Width := 200;
    Result.Style := csDropDownList;
    Result.Items.CommaText := AItems;
    Result.OnChange := @ToolFieldChanged;
  end;

begin
  Lbl := TLabel.Create(Self);
  Lbl.Parent := APage;
  Lbl.Caption := 'User tools';
  Lbl.Font.Style := [fsBold];
  Lbl.Left := 12; Lbl.Top := 12;

  FToolList := TListBox.Create(Self);
  FToolList.Parent := APage;
  FToolList.Left := 12; FToolList.Top := 40;
  FToolList.Width := 180; FToolList.Height := 320;
  FToolList.Anchors := [akLeft, akTop, akBottom];
  FToolList.OnClick := @ToolSelected;

  Right := TPanel.Create(Self);
  Right.Parent := APage;
  Right.Left := 204; Right.Top := 40;
  Right.Width := APage.Width - 216; Right.Height := 320;
  Right.Anchors := [akLeft, akTop, akRight, akBottom];
  Right.BevelOuter := bvNone;
  Right.Caption := '';

  FToolEnabled := TCheckBox.Create(Self);
  FToolEnabled.Parent := Right;
  FToolEnabled.Caption := 'Enabled';
  FToolEnabled.Left := 90; FToolEnabled.Top := 0;
  FToolEnabled.OnChange := @ToolFieldChanged;

  FToolName  := Row('Name:', 26);
  FToolFiles := Row('Files:', 54);
  FToolLangs := Row('Languages:', 82);
  FToolAccel := Row('Shortcut:', 110);

  FToolPlace  := Choice('Menu:', '"Tools menu","Context menu"', 138);
  FToolKind   := Choice('Type:', '"Shell command","Script","Python script"', 166);
  FToolInput  := Choice('Input:',
    '"None","Selected lines","Selection","Whole document","Document copy"', 194);
  FToolOutput := Choice('Output:',
    '"None","None, asynchronous","Output pane","Insert into the document","New document"', 222);
  FToolFilter := Choice('Filter:', '"none","default","make","bison","latex","python"', 250);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Right; Lbl.Caption := 'Command:';
  Lbl.Left := 0; Lbl.Top := 282;

  FToolCode := TMemo.Create(Self);
  FToolCode.Parent := Right;
  FToolCode.Left := 90; FToolCode.Top := 278;
  FToolCode.Width := 260; FToolCode.Height := 42;
  FToolCode.Anchors := [akLeft, akTop, akRight, akBottom];
  FToolCode.ScrollBars := ssAutoBoth;
  FToolCode.WordWrap := False;
  FToolCode.Font.Name := {$IFDEF WINDOWS}'Consolas'{$ELSE}'Monospace'{$ENDIF};
  FToolCode.OnChange := @ToolFieldChanged;
end;

procedure TLedPrefsDialog.LoadTools;
var
  i: Integer;
begin
  if FToolList = nil then Exit;
  if FTools = nil then FTools := TLedTools.Create;
  FTools.Clear;
  FTools.LoadDirectory(LedConfigFile('tools'));
  FTools.LoadDirectory(LedDataFile('tools'));

  FToolLoading := True;
  try
    FToolList.Items.Clear;
    for i := 0 to FTools.Count - 1 do
      FToolList.Items.AddObject(FTools[i].Name, FTools[i]);
    if FToolList.Items.Count > 0 then FToolList.ItemIndex := 0;
  finally
    FToolLoading := False;
  end;
  ToolSelected(nil);
end;

procedure TLedPrefsDialog.ToolSelected(Sender: TObject);
var
  T: TLedTool;
  Have: Boolean;
begin
  if FToolLoading or (FToolList = nil) then Exit;
  T := nil;
  if FToolList.ItemIndex >= 0 then
    T := TLedTool(FToolList.Items.Objects[FToolList.ItemIndex]);
  Have := T <> nil;

  FToolLoading := True;
  try
    FToolEnabled.Enabled := Have;
    FToolName.Enabled := Have;
    FToolFiles.Enabled := Have;
    FToolLangs.Enabled := Have;
    FToolAccel.Enabled := Have;
    FToolPlace.Enabled := Have;
    FToolKind.Enabled := Have;
    FToolInput.Enabled := Have;
    FToolOutput.Enabled := Have;
    FToolFilter.Enabled := Have;
    FToolCode.Enabled := Have;
    if not Have then
    begin
      FToolName.Text := '';
      FToolCode.Lines.Clear;
      Exit;
    end;

    FToolEnabled.Checked := T.Enabled;
    FToolName.Text := T.Name;
    FToolFiles.Text := T.FileFilter;
    FToolLangs.Text := T.Langs;
    FToolAccel.Text := T.Accel;
    FToolPlace.ItemIndex := Ord(T.Place);
    FToolKind.ItemIndex := Ord(T.Kind);
    FToolInput.ItemIndex := Ord(T.Input);
    FToolOutput.ItemIndex := Ord(T.Output);
    FToolFilter.ItemIndex := FToolFilter.Items.IndexOf(T.Filter);
    if FToolFilter.ItemIndex < 0 then FToolFilter.ItemIndex := 0;
    FToolCode.Lines.Text := T.Code;
  finally
    FToolLoading := False;
  end;
end;

procedure TLedPrefsDialog.ToolFieldChanged(Sender: TObject);
var
  T: TLedTool;
begin
  if FToolLoading or (FToolList = nil) or (FToolList.ItemIndex < 0) then Exit;
  T := TLedTool(FToolList.Items.Objects[FToolList.ItemIndex]);
  if T = nil then Exit;

  T.Enabled := FToolEnabled.Checked;
  T.Name := FToolName.Text;
  T.FileFilter := FToolFiles.Text;
  T.Langs := FToolLangs.Text;
  T.Accel := FToolAccel.Text;
  if FToolPlace.ItemIndex >= 0 then T.Place := TLedToolPlace(FToolPlace.ItemIndex);
  if FToolKind.ItemIndex >= 0 then T.Kind := TLedToolKind(FToolKind.ItemIndex);
  if FToolInput.ItemIndex >= 0 then T.Input := TLedToolInput(FToolInput.ItemIndex);
  if FToolOutput.ItemIndex >= 0 then T.Output := TLedToolOutput(FToolOutput.ItemIndex);
  if FToolFilter.ItemIndex >= 0 then T.Filter := FToolFilter.Items[FToolFilter.ItemIndex];
  T.Code := FToolCode.Lines.Text;

  if Sender = FToolName then
    FToolList.Items[FToolList.ItemIndex] := T.Name;
end;

procedure TLedPrefsDialog.ApplyTools;
var
  i: Integer;
  Dir: string;
begin
  if (FToolList = nil) or (FTools = nil) then Exit;
  { Edited tools are written to the user's directory, never back over the
    shipped copies, so a bad edit is undone by deleting one file. }
  Dir := IncludeTrailingPathDelimiter(LedConfigFile('tools'));
  ForceDirectories(Dir);
  for i := 0 to FTools.Count - 1 do
    FTools[i].SaveToFile(Dir + FTools[i].Id + '.ini');
end;

function TLedPrefsDialog.PageCount: Integer;
begin
  Result := FCategories.Count;
end;

function TLedPrefsDialog.ListPagesReady: Boolean;
begin
  Result := (FLangList <> nil) and (FLangList.Items.Count > 0) and
            (FFilterGrid <> nil) and (FFilterGrid.RowCount > 1) and
            (FToolList <> nil);
end;

procedure TLedPrefsDialog.AddFilterRow(const AFilter, AConfig: string);
begin
  if FFilterGrid = nil then Exit;
  FFilterGrid.RowCount := FFilterGrid.RowCount + 1;
  FFilterGrid.Cells[0, FFilterGrid.RowCount - 1] := AFilter;
  FFilterGrid.Cells[1, FFilterGrid.RowCount - 1] := AConfig;
end;

end.
