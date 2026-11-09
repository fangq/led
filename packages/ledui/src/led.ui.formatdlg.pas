{ LED - a lightweight editor.  The formatting dialogs of the visual editor.

  The ribbon holds the settings a writer reaches for every minute; these hold
  the rest of them, the way a word processor's Font, Paragraph and Bullets and
  Numbering dialogs do, and the styles the paragraphs are made of.

  Each dialog is given the properties as they are and hands back only what
  the writer changed (the mask says which), so a selection of mixed fonts set
  to bold stays mixed fonts.  The Modify style dialog opens the Font and
  Paragraph dialogs on the style rather than on the text.

  Every control has a name, and each form goes through LedVisualDialogHook
  before it is shown, so the self-test fills them in as a writer would. }

unit Led.UI.FormatDlg;

{$mode objfpc}{$H+}
{$I led.parade.inc}

interface

{$IFDEF LED_PARADE}
uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Graphics, Forms, Dialogs, ComCtrls, Spin,
  parade, paradeedit;

{ Format > Font: the properties are the text's as they are; on OK they are what changed (mask), True if any did }
function LedFontDialog(AEdit: TParadeEdit; var Props: pd_char_props; const ACaption: string = 'Font'): Boolean;
{ Format > Paragraph, the same way }
function LedParagraphDialog(AEdit: TParadeEdit; var Props: pd_para_props;
  const ACaption: string = 'Paragraph'): Boolean;
{ Format > Bullets and numbering, on the selected paragraphs: True when the list changed (or was taken off) }
function LedListDialog(AEdit: TParadeEdit): Boolean;
{ a paragraph style defined from its dialog: StyleName's, or a new one's when IsNew; True when it was }
function LedStyleDialog(AEdit: TParadeEdit; const StyleName: string; IsNew: Boolean): Boolean;
{ every paragraph style, to apply, change or add to; True when one was applied }
function LedStylesDialog(AEdit: TParadeEdit): Boolean;

{ a line describing a style's look: "Calibri, 11 pt, bold; left, after 8 pt" }
function LedStyleSummary(const Pp: pd_para_props; const Cp: pd_char_props): string;
{ a list label as Parade draws it, for a preview: Levels' template at Level, with each level's count }
function LedListLabel(const Levels: TParadeListLevels; Level: Integer; const Counts: array of Integer): string;
{$ENDIF}

implementation

{$IFDEF LED_PARADE}
uses
  Math, LazUTF8, Led.UI.Dpi, Led.UI.Visual;

const
  Pt = PD_SP_PER_PT;
  Sizes = '8|9|10|10.5|11|12|14|16|18|20|22|24|26|28|36|48|72';
  UnderNames = '(none)|Single|Double|Thick|Dotted|Dashed|Wavy|Words only';
  Langs = '|en-US|en-GB|de-DE|fr-FR|es-ES|it-IT|pt-BR|nl-NL|ru-RU|zh-Hans|zh-Hant|ja-JP|ko-KR|ar-SA|he-IL';
  AlignNames = 'Left|Centred|Right|Justified';
  AlignValues: array[0..3] of Integer = (PD_ALIGN_LEFT, PD_ALIGN_CENTER, PD_ALIGN_RIGHT, PD_ALIGN_JUSTIFY);
  LineNames = 'Single|1.5 lines|Double|At least|Exactly|Multiple';
  { the number styles a list level can have, in the order the dialog lists them }
  NumFormats: array[0..14] of Integer = (PD_NUM_BULLET, PD_NUM_DECIMAL, PD_NUM_DECIMAL_ZERO, PD_NUM_LOWER_ALPHA,
    PD_NUM_UPPER_ALPHA, PD_NUM_LOWER_ROMAN, PD_NUM_UPPER_ROMAN, PD_NUM_ORDINAL, PD_NUM_CARDINAL_TEXT,
    PD_NUM_ORDINAL_TEXT, PD_NUM_CIRCLED, PD_NUM_FULLWIDTH, PD_NUM_CJK_COUNTING, PD_NUM_CJK_TRADITIONAL, PD_NUM_NONE);
  NumNames = 'Bullet|1, 2, 3|01, 02, 03|a, b, c|A, B, C|i, ii, iii|I, II, III|1st, 2nd, 3rd|One, Two, Three|' +
    'First, Second, Third|' + #$E2#$91#$A0 + ', ' + #$E2#$91#$A1 + ', ' + #$E2#$91#$A2 + '|' +
    #$EF#$BC#$91 + ', ' + #$EF#$BC#$92 + ', ' + #$EF#$BC#$93 + '|' + #$E4#$B8#$80 + ', ' + #$E4#$BA#$8C + ', ' +
    #$E4#$B8#$89 + '|' + #$E7#$94#$B2 + ', ' + #$E4#$B9#$99 + ', ' + #$E4#$B8#$99 + '|(no number)';
  Bullets = #$E2#$80#$A2'|'#$E2#$97#$A6'|'#$E2#$96#$AA'|'#$E2#$96#$A0'|'#$E2#$80#$A3'|'#$E2#$9E#$A2'|'#$E2#$9C#$93 +
    '|'#$E2#$80#$93'|'#$E2#$98#$85'|'#$E2#$97#$86'|'#$E2#$97#$8B'|'#$E2#$9D#$96'|-|*';
  Presets = '(as the levels are)|Bullets ' + #$E2#$80#$A2 + ' ' + #$E2#$97#$A6 + ' ' + #$E2#$96#$AA +
    '|1. a. i.|1) a) i)|(1) (a) (i)|1. 1.1. 1.1.1.|A. B. C.|I. A. 1.|Checks ' + #$E2#$9C#$93 +
    '|Arrows ' + #$E2#$9E#$A2;

var
  Dot: TFormatSettings;

function S(V: Integer): Integer;
begin
  Result := LedScale96(V);
end;

function RGBOf(C: TColor): UInt32;
begin
  C := ColorToRGB(C);
  Result := (UInt32(Red(C)) shl 16) or (UInt32(Green(C)) shl 8) or UInt32(Blue(C));
end;

function ColorOf(V: UInt32): TColor;
begin
  Result := RGBToColor((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
end;

function PtStr(V: pd_sp): string;
begin
  Result := FormatFloat('0.##', V / Pt, Dot);
end;

function NumOf(const AText: string; ADefault: Double): Double;
begin
  Result := StrToFloatDef(StringReplace(Trim(AText), ',', '.', []), ADefault, Dot);
end;

function Fam(const A: array of AnsiChar): string;
begin
  Result := string(PAnsiChar(@A[0]));
end;

procedure SetFam(var A: array of AnsiChar; const V: string);
begin
  FillChar(A[0], Length(A), 0);
  StrPLCopy(@A[0], V, High(A));
end;

{ ---- a list's labels ---- }

function Roman(N: Integer): string;
const
  V: array[0..12] of Integer = (1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1);
  R: array[0..12] of string = ('m', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i');
var
  I: Integer;
begin
  Result := '';
  if (N <= 0) or (N > 3999) then
    Exit(IntToStr(N));
  for I := 0 to 12 do
    while N >= V[I] do
    begin
      Result := Result + R[I];
      Dec(N, V[I]);
    end;
end;

function NumText(Fmt, N: Integer): string;
const
  CardWords: array[1..10] of string = ('One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten');
  OrdWords: array[1..10] of string = ('First', 'Second', 'Third', 'Fourth', 'Fifth', 'Sixth', 'Seventh', 'Eighth',
    'Ninth', 'Tenth');
  Counting: array[1..10] of Cardinal = ($4E00, $4E8C, $4E09, $56DB, $4E94, $516D, $4E03, $516B, $4E5D, $5341);
  Stems: array[1..10] of Cardinal = ($7532, $4E59, $4E19, $4E01, $620A, $5DF1, $5E9A, $8F9B, $58EC, $7678);
  Symbols: array[0..3] of string = ('*', #$E2#$80#$A0, #$E2#$80#$A1, #$C2#$A7);
var
  I: Integer;
  D: string;
begin
  case Fmt of
    PD_NUM_DECIMAL: Result := IntToStr(N);
    PD_NUM_DECIMAL_ZERO: Result := Format('%.2d', [N]);
    PD_NUM_LOWER_ALPHA, PD_NUM_UPPER_ALPHA:
      begin
        Result := StringOfChar(Chr(Ord('a') + (Max(N, 1) - 1) mod 26), (Max(N, 1) - 1) div 26 + 1);
        if Fmt = PD_NUM_UPPER_ALPHA then
          Result := UpperCase(Result);
      end;
    PD_NUM_LOWER_ROMAN: Result := Roman(N);
    PD_NUM_UPPER_ROMAN: Result := UpperCase(Roman(N));
    PD_NUM_ORDINAL:
      if (N mod 100 >= 11) and (N mod 100 <= 13) then
        Result := IntToStr(N) + 'th'
      else
        case N mod 10 of
          1: Result := IntToStr(N) + 'st';
          2: Result := IntToStr(N) + 'nd';
          3: Result := IntToStr(N) + 'rd';
        else
          Result := IntToStr(N) + 'th';
        end;
    PD_NUM_CARDINAL_TEXT: if (N >= 1) and (N <= 10) then Result := CardWords[N] else Result := IntToStr(N);
    PD_NUM_ORDINAL_TEXT: if (N >= 1) and (N <= 10) then Result := OrdWords[N] else Result := IntToStr(N);
    PD_NUM_CIRCLED: if (N >= 1) and (N <= 20) then Result := UnicodeToUTF8($2460 + N - 1) else Result := IntToStr(N);
    PD_NUM_FULLWIDTH:
      begin
        D := IntToStr(N);
        Result := '';
        for I := 1 to Length(D) do
          Result := Result + UnicodeToUTF8($FF10 + Ord(D[I]) - Ord('0'));
      end;
    PD_NUM_CJK_COUNTING: if (N >= 1) and (N <= 10) then Result := UnicodeToUTF8(Counting[N]) else Result := IntToStr(N);
    PD_NUM_CJK_TRADITIONAL: if (N >= 1) and (N <= 10) then Result := UnicodeToUTF8(Stems[N]) else Result := IntToStr(N);
    PD_NUM_SYMBOL: Result := Symbols[(Max(N, 1) - 1) mod 4];
    PD_NUM_NONE: Result := '';
  else
    Result := IntToStr(N);
  end;
end;

function LedListLabel(const Levels: TParadeListLevels; Level: Integer; const Counts: array of Integer): string;
var
  K: Integer;
begin
  Result := Fam(Levels[Level].text);
  if Levels[Level].format = PD_NUM_BULLET then
    Exit;
  for K := Min(8, High(Counts)) downto 0 do
    Result := StringReplace(Result, '%' + IntToStr(K + 1), NumText(Levels[K].format, Counts[K]), [rfReplaceAll]);
end;

function LedStyleSummary(const Pp: pd_para_props; const Cp: pd_char_props): string;
begin
  Result := Fam(Cp.family);
  if Result = '' then
    Result := '(the default font)';
  Result := Result + ', ' + PtStr(Cp.size) + ' pt';
  if Cp.weight >= 600 then
    Result := Result + ', bold';
  if Cp.italic <> 0 then
    Result := Result + ', italic';
  if Cp.underline <> 0 then
    Result := Result + ', underlined';
  if Cp.caps <> 0 then
    Result := Result + ', all caps'
  else if Cp.small_caps <> 0 then
    Result := Result + ', small caps';
  case Pp.align of
    PD_ALIGN_CENTER: Result := Result + '; centred';
    PD_ALIGN_RIGHT: Result := Result + '; right';
    PD_ALIGN_JUSTIFY: Result := Result + '; justified';
  else
    Result := Result + '; left';
  end;
  if Pp.indent_left <> 0 then
    Result := Result + ', indented ' + PtStr(Pp.indent_left) + ' pt';
  if Pp.indent_first > 0 then
    Result := Result + ', first line ' + PtStr(Pp.indent_first) + ' pt'
  else if Pp.indent_first < 0 then
    Result := Result + ', hanging ' + PtStr(-Pp.indent_first) + ' pt';
  if Pp.space_before <> 0 then
    Result := Result + ', before ' + PtStr(Pp.space_before) + ' pt';
  if Pp.space_after <> 0 then
    Result := Result + ', after ' + PtStr(Pp.space_after) + ' pt';
  case Pp.line_rule of
    PD_LINE_AT_LEAST: Result := Result + ', lines at least ' + PtStr(Pp.line_height) + ' pt';
    PD_LINE_EXACT: Result := Result + ', lines exactly ' + PtStr(Pp.line_height) + ' pt';
  else
    if (Pp.line_spacing <> 0) and (Pp.line_spacing <> 1000) then
      Result := Result + ', line spacing ' + FormatFloat('0.##', Pp.line_spacing / 1000, Dot);
  end;
  if Pp.keep_with_next <> 0 then
    Result := Result + ', kept with the next';
  if Pp.page_break_before <> 0 then
    Result := Result + ', on a new page';
end;

{ ---- what every dialog is made of ---- }

type
  TLedFmtDlg = class(TForm)
  protected
    FEdit: TParadeEdit;
    FLoading: Boolean;
    FButtons: TPanel;
    function Lbl(AParent: TWinControl; const ACaption: string; X, Y: Integer): TLabel;
    function Combo(AParent: TWinControl; const AName: string; X, Y, W: Integer; const AItems: string;
      AList: Boolean): TComboBox;
    function Spin(AParent: TWinControl; const AName: string; X, Y, W: Integer; AMin, AMax, AValue: Double;
      ADecimals: Integer = 1): TFloatSpinEdit;
    function Box(AParent: TWinControl; const AName, ACaption: string; X, Y: Integer; AChecked: Boolean): TCheckBox;
    function ColorBtn(AParent: TWinControl; const AName: string; X, Y: Integer; AColor: TColor): TColorButton;
    function Group(AParent: TWinControl; const ACaption: string; X, Y, W, H: Integer): TGroupBox;
    function Btn(AParent: TWinControl; const AName, ACaption: string; X, W: Integer; AResult: TModalResult;
      AClick: TNotifyEvent): TButton;
    function Preview(AParent: TWinControl; const AName: string; X, Y, W, H: Integer): TPaintBox;
    procedure Changed(Sender: TObject); virtual;
  public
    constructor Make(AEdit: TParadeEdit; const ACaption: string; W, H: Integer);
    { through the self-test's hook, then shown: True on OK }
    function Run: Boolean;
    function RunResult: TModalResult;
  end;

constructor TLedFmtDlg.Make(AEdit: TParadeEdit; const ACaption: string; W, H: Integer);
begin
  inherited CreateNew(nil);
  FEdit := AEdit;
  Caption := ACaption;
  BorderStyle := bsDialog;
  Position := poOwnerFormCenter;
  ClientWidth := S(W);
  ClientHeight := S(H) + S(44);
  FButtons := TPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alBottom;
  FButtons.Height := S(44);
  FButtons.BevelOuter := bvNone;
  Btn(FButtons, 'BtnCancel', 'Cancel', W - 92, 80, mrCancel, nil).Cancel := True;
  Btn(FButtons, 'BtnOK', 'OK', W - 180, 80, mrOK, nil).Default := True;
end;

function TLedFmtDlg.RunResult: TModalResult;
begin
  if Assigned(LedVisualDialogHook) then
    LedVisualDialogHook(Self);
  Result := ShowModal;
end;

function TLedFmtDlg.Run: Boolean;
begin
  Result := RunResult = mrOK;
end;

procedure TLedFmtDlg.Changed(Sender: TObject);
begin
end;

function TLedFmtDlg.Lbl(AParent: TWinControl; const ACaption: string; X, Y: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := S(X);
  Result.Top := S(Y) + S(4);
end;

function TLedFmtDlg.Combo(AParent: TWinControl; const AName: string; X, Y, W: Integer; const AItems: string;
  AList: Boolean): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.Name := AName;
  Result.Left := S(X);
  Result.Top := S(Y);
  Result.Width := S(W);
  Result.DropDownCount := 16;
  if AList then
    Result.Style := csDropDownList;
  if AItems <> '' then
  begin
    Result.Items.Delimiter := '|';
    Result.Items.StrictDelimiter := True;
    Result.Items.DelimitedText := AItems;
  end;
  Result.Text := '';
  Result.OnChange := @Changed;
end;

function TLedFmtDlg.Spin(AParent: TWinControl; const AName: string; X, Y, W: Integer; AMin, AMax, AValue: Double;
  ADecimals: Integer): TFloatSpinEdit;
begin
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.Name := AName;
  Result.Left := S(X);
  Result.Top := S(Y);
  Result.Width := S(W);
  Result.DecimalPlaces := ADecimals;
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Value := AValue;
  Result.OnChange := @Changed;
end;

function TLedFmtDlg.Box(AParent: TWinControl; const AName, ACaption: string; X, Y: Integer;
  AChecked: Boolean): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.Name := AName;
  Result.Caption := ACaption;
  Result.Left := S(X);
  Result.Top := S(Y);
  Result.Checked := AChecked;
  Result.OnChange := @Changed;
end;

function TLedFmtDlg.ColorBtn(AParent: TWinControl; const AName: string; X, Y: Integer; AColor: TColor): TColorButton;
begin
  Result := TColorButton.Create(Self);
  Result.Parent := AParent;
  Result.Name := AName;
  Result.Left := S(X);
  Result.Top := S(Y);
  Result.Width := S(70);
  Result.Height := S(25);
  Result.ButtonColor := AColor;
  Result.OnColorChanged := @Changed;
end;

function TLedFmtDlg.Group(AParent: TWinControl; const ACaption: string; X, Y, W, H: Integer): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.SetBounds(S(X), S(Y), S(W), S(H));
end;

function TLedFmtDlg.Btn(AParent: TWinControl; const AName, ACaption: string; X, W: Integer;
  AResult: TModalResult; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Name := AName;
  Result.Caption := ACaption;
  Result.SetBounds(S(X), S(9), S(W), S(27));
  Result.ModalResult := AResult;
  Result.OnClick := AClick;
end;

function TLedFmtDlg.Preview(AParent: TWinControl; const AName: string; X, Y, W, H: Integer): TPaintBox;
begin
  Result := TPaintBox.Create(Self);
  Result.Parent := AParent;
  Result.Name := AName;
  Result.SetBounds(S(X), S(Y), S(W), S(H));
end;

{ ---- Font ---- }

type
  TLedFontDlg = class(TLedFmtDlg)
  private
    FIn: pd_char_props;
    FFam, FStyle, FSize, FUnder, FLang, FFamEA, FFamCS: TComboBox;
    FCol, FHil: TColorButton;
    FHilOn, FStrike, FSup, FSub, FSmall, FCaps, FHidden, FKern: TCheckBox;
    FScale, FSpacing, FPosition: TFloatSpinEdit;
    FBox: TPaintBox;
    FSample: string;
    procedure PaintPreview(Sender: TObject);
  protected
    procedure Changed(Sender: TObject); override;
  public
    constructor Build(AEdit: TParadeEdit; const ACaption: string; const AIn: pd_char_props);
    function Delta: pd_char_props;
  end;

constructor TLedFontDlg.Build(AEdit: TParadeEdit; const ACaption: string; const AIn: pd_char_props);
var
  PC: TPageControl;
  Tab: TTabSheet;
  G: TGroupBox;
  I: Integer;
begin
  Make(AEdit, ACaption, 470, 430);
  FIn := AIn;
  FLoading := True;
  FSample := 'AaBbYyZz';
  if AEdit <> nil then
  begin
    FSample := Trim(Copy(AEdit.SelectedText, 1, 40));
    if (FSample = '') or (Pos(#10, FSample) > 0) then
      FSample := 'AaBbYyZz';
  end;
  PC := TPageControl.Create(Self);
  PC.Parent := Self;
  PC.Name := 'FontPages';
  PC.Align := alClient;
  Tab := PC.AddTabSheet;
  Tab.Caption := 'Font';
  Lbl(Tab, 'Font:', 10, 4);
  FFam := Combo(Tab, 'FontFamily', 10, 26, 200, '', False);
  if AEdit <> nil then
    AEdit.GetFontFamilies(FFam.Items);
  FFam.Text := Fam(FIn.family);
  Lbl(Tab, 'Style:', 220, 4);
  FStyle := Combo(Tab, 'FontStyle', 220, 26, 120, 'Regular|Italic|Bold|Bold italic', True);
  FStyle.ItemIndex := Ord(FIn.italic <> 0) + 2 * Ord(FIn.weight >= 600);
  Lbl(Tab, 'Size:', 350, 4);
  FSize := Combo(Tab, 'FontSize', 350, 26, 90, Sizes, False);
  FSize.Text := PtStr(FIn.size);
  Lbl(Tab, 'Font colour:', 10, 62);
  FCol := ColorBtn(Tab, 'FontColor', 10, 84, ColorOf(FIn.color));
  Lbl(Tab, 'Underline:', 120, 62);
  FUnder := Combo(Tab, 'FontUnderline', 120, 84, 120, UnderNames, True);
  FUnder.ItemIndex := EnsureRange(FIn.underline, 0, 7);
  FHilOn := Box(Tab, 'FontHighlightOn', 'Highlight:', 260, 64, FIn.background <> 0);
  if FIn.background <> 0 then
    FHil := ColorBtn(Tab, 'FontHighlight', 260, 84, ColorOf(FIn.background))
  else
    FHil := ColorBtn(Tab, 'FontHighlight', 260, 84, clYellow);
  G := Group(Tab, 'Effects', 10, 120, 440, 90);
  FStrike := Box(G, 'FontStrike', 'Strikethrough', 10, 4, FIn.strike <> 0);
  FSup := Box(G, 'FontSuper', 'Superscript', 10, 26, FIn.shift = PD_SHIFT_SUPER);
  FSub := Box(G, 'FontSub', 'Subscript', 10, 48, FIn.shift = PD_SHIFT_SUB);
  FSmall := Box(G, 'FontSmallCaps', 'Small caps', 160, 4, FIn.small_caps <> 0);
  FCaps := Box(G, 'FontAllCaps', 'All caps', 160, 26, FIn.caps <> 0);
  FHidden := Box(G, 'FontHidden', 'Hidden', 160, 48, FIn.hidden <> 0);
  Lbl(Tab, 'Preview', 10, 216);
  FBox := Preview(Tab, 'FontPreview', 10, 238, 440, 80);
  FBox.OnPaint := @PaintPreview;
  Tab := PC.AddTabSheet;
  Tab.Caption := 'Advanced';
  G := Group(Tab, 'Character spacing', 10, 4, 440, 130);
  Lbl(G, 'Scale (%):', 10, 4);
  I := FIn.hscale;
  if I = 0 then
    I := 1000;
  FScale := Spin(G, 'FontScale', 200, 4, 90, 1, 600, I / 10, 0);
  Lbl(G, 'Spacing (pt, below 0: condensed):', 10, 36);
  FSpacing := Spin(G, 'FontSpacing', 200, 36, 90, -100, 100, FIn.letter_space / Pt, 1);
  Lbl(G, 'Position (pt, below 0: lowered):', 10, 68);
  FPosition := Spin(G, 'FontPosition', 200, 68, 90, -500, 500, FIn.position / Pt, 1);
  FKern := Box(Tab, 'FontKerning', 'Kerning: the font''s own spacing between pairs of letters', 14, 142,
    FIn.kerning <> 0);
  G := Group(Tab, 'Other scripts and language', 10, 172, 440, 130);
  Lbl(G, 'East Asian text''s font:', 10, 4);
  FFamEA := Combo(G, 'FontFamilyEA', 200, 4, 220, '', False);
  Lbl(G, 'Complex scripts'' font:', 10, 36);
  FFamCS := Combo(G, 'FontFamilyCS', 200, 36, 220, '', False);
  if AEdit <> nil then
  begin
    AEdit.GetFontFamilies(FFamEA.Items);
    FFamCS.Items.Assign(FFamEA.Items);
  end;
  FFamEA.Items.Insert(0, '');
  FFamCS.Items.Insert(0, '');
  FFamEA.Text := Fam(FIn.family_ea);
  FFamCS.Text := Fam(FIn.family_cs);
  Lbl(G, 'Language (hyphenation, breaks):', 10, 68);
  FLang := Combo(G, 'FontLanguage', 200, 68, 120, Langs, False);
  FLang.Text := Fam(FIn.lang);
  PC.ActivePageIndex := 0;
  FLoading := False;
end;

procedure TLedFontDlg.Changed(Sender: TObject);
begin
  if FLoading then
    Exit;
  FLoading := True;
  try   { superscript and subscript are one or the other }
    if (Sender = FSup) and FSup.Checked then
      FSub.Checked := False
    else if (Sender = FSub) and FSub.Checked then
      FSup.Checked := False
    else if Sender = FHil then
      FHilOn.Checked := True;
  finally
    FLoading := False;
  end;
  if FBox <> nil then
    FBox.Invalidate;
end;

procedure TLedFontDlg.PaintPreview(Sender: TObject);
var
  C: TCanvas;
  T: string;
  Sz, X, Y, W, H: Integer;
begin
  C := FBox.Canvas;
  C.Brush.Color := clWhite;
  C.Pen.Color := clGray;
  C.Rectangle(0, 0, FBox.Width, FBox.Height);
  T := FSample;
  if FCaps.Checked then
    T := UTF8UpperCase(T);
  if Trim(FFam.Text) <> '' then
    C.Font.Name := Trim(FFam.Text);
  Sz := Round(NumOf(FSize.Text, 11));
  if FSup.Checked or FSub.Checked then
    Sz := Sz * 2 div 3;
  C.Font.Size := EnsureRange(Sz, 4, 40);
  C.Font.Style := [];
  if FStyle.ItemIndex in [2, 3] then
    C.Font.Style := C.Font.Style + [fsBold];
  if FStyle.ItemIndex in [1, 3] then
    C.Font.Style := C.Font.Style + [fsItalic];
  if FUnder.ItemIndex > 0 then
    C.Font.Style := C.Font.Style + [fsUnderline];
  if FStrike.Checked then
    C.Font.Style := C.Font.Style + [fsStrikeOut];
  C.Font.Color := FCol.ButtonColor;
  W := C.TextWidth(T);
  H := C.TextHeight(T);
  X := Max(4, (FBox.Width - W) div 2);
  Y := (FBox.Height - H) div 2;
  if FSup.Checked then
    Dec(Y, H div 2)
  else if FSub.Checked then
    Inc(Y, H div 3);
  if FHilOn.Checked then
  begin
    C.Brush.Color := FHil.ButtonColor;
    C.FillRect(X, Y, X + W, Y + H);
  end;
  C.Brush.Style := bsClear;
  if FHidden.Checked then
    C.Font.Color := clSilver;
  C.TextOut(X, Y, T);
  C.Brush.Style := bsSolid;
end;

function TLedFontDlg.Delta: pd_char_props;
var
  V: Double;
  Bold, Ital: Boolean;
  Sh, I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  if (Trim(FFam.Text) <> '') and (Trim(FFam.Text) <> Fam(FIn.family)) then
  begin
    Result.mask := Result.mask or PD_CP_FAMILY;
    SetFam(Result.family, Trim(FFam.Text));
    Result.font_theme := FIn.font_theme and not 3;    { a family of its own, not the theme's }
  end;
  Bold := FStyle.ItemIndex in [2, 3];
  Ital := FStyle.ItemIndex in [1, 3];
  if Bold <> (FIn.weight >= 600) then
  begin
    Result.mask := Result.mask or PD_CP_WEIGHT;
    if Bold then Result.weight := 700 else Result.weight := 400;
  end;
  if Ital <> (FIn.italic <> 0) then
  begin
    Result.mask := Result.mask or PD_CP_ITALIC;
    Result.italic := Ord(Ital);
  end;
  V := NumOf(FSize.Text, -1);
  if (V >= 1) and (V <= 1600) and (Round(V * Pt) <> FIn.size) then
  begin
    Result.mask := Result.mask or PD_CP_SIZE;
    Result.size := Round(V * Pt);
  end;
  if RGBOf(FCol.ButtonColor) <> (FIn.color and $FFFFFF) then
  begin
    Result.mask := Result.mask or PD_CP_COLOR;
    Result.color := $FF000000 or RGBOf(FCol.ButtonColor);
  end;
  if (FHilOn.Checked <> (FIn.background <> 0)) or
    (FHilOn.Checked and (RGBOf(FHil.ButtonColor) <> (FIn.background and $FFFFFF))) then
  begin
    Result.mask := Result.mask or PD_CP_BACKGROUND;
    if FHilOn.Checked then
      Result.background := $FF000000 or RGBOf(FHil.ButtonColor);
  end;
  if FUnder.ItemIndex <> FIn.underline then
  begin
    Result.mask := Result.mask or PD_CP_UNDERLINE;
    Result.underline := Max(0, FUnder.ItemIndex);
  end;
  if FStrike.Checked <> (FIn.strike <> 0) then
  begin
    Result.mask := Result.mask or PD_CP_STRIKE;
    Result.strike := Ord(FStrike.Checked);
  end;
  Sh := PD_SHIFT_NONE;
  if FSup.Checked then
    Sh := PD_SHIFT_SUPER
  else if FSub.Checked then
    Sh := PD_SHIFT_SUB;
  if Sh <> FIn.shift then
  begin
    Result.mask := Result.mask or PD_CP_SHIFT;
    Result.shift := Sh;
  end;
  if FSmall.Checked <> (FIn.small_caps <> 0) then
  begin
    Result.mask := Result.mask or PD_CP_SMALLCAPS;
    Result.small_caps := Ord(FSmall.Checked);
  end;
  if FCaps.Checked <> (FIn.caps <> 0) then
  begin
    Result.mask := Result.mask or PD_CP_CAPS;
    Result.caps := Ord(FCaps.Checked);
  end;
  if FHidden.Checked <> (FIn.hidden <> 0) then
  begin
    Result.mask := Result.mask or PD_CP_HIDDEN;
    Result.hidden := Ord(FHidden.Checked);
  end;
  I := FIn.hscale;
  if I = 0 then
    I := 1000;
  if Round(FScale.Value * 10) <> I then
  begin
    Result.mask := Result.mask or PD_CP_HSCALE;
    Result.hscale := Round(FScale.Value * 10);
  end;
  if Round(FSpacing.Value * Pt) <> FIn.letter_space then
  begin
    Result.mask := Result.mask or PD_CP_LETTERSPACE;
    Result.letter_space := Round(FSpacing.Value * Pt);
  end;
  if Round(FPosition.Value * Pt) <> FIn.position then
  begin
    Result.mask := Result.mask or PD_CP_POSITION;
    Result.position := Round(FPosition.Value * Pt);
  end;
  if FKern.Checked <> (FIn.kerning <> 0) then
  begin
    Result.mask := Result.mask or PD_CP_KERNING;
    Result.kerning := Ord(FKern.Checked);
  end;
  if Trim(FFamEA.Text) <> Fam(FIn.family_ea) then
  begin
    Result.mask := Result.mask or PD_CP_FAMILY_EA;
    SetFam(Result.family_ea, Trim(FFamEA.Text));
    Result.font_theme := Result.font_theme or (FIn.font_theme and not 12);
  end;
  if Trim(FFamCS.Text) <> Fam(FIn.family_cs) then
  begin
    Result.mask := Result.mask or PD_CP_FAMILY_CS;
    SetFam(Result.family_cs, Trim(FFamCS.Text));
    Result.font_theme := Result.font_theme or (FIn.font_theme and not 48);
  end;
  if Trim(FLang.Text) <> Fam(FIn.lang) then
  begin
    Result.mask := Result.mask or PD_CP_LANG;
    SetFam(Result.lang, Trim(FLang.Text));
  end;
end;

function LedFontDialog(AEdit: TParadeEdit; var Props: pd_char_props; const ACaption: string): Boolean;
var
  D: TLedFontDlg;
begin
  D := TLedFontDlg.Build(AEdit, ACaption, Props);
  try
    Result := D.Run;
    if Result then
    begin
      Props := D.Delta;
      Result := Props.mask <> 0;
    end;
  finally
    D.Free;
  end;
end;

{ ---- Paragraph ---- }

type
  TLedParaDlg = class(TLedFmtDlg)
  private
    FIn: pd_para_props;
    FAlign, FDir, FSpecial, FLine: TComboBox;
    FLeft, FRight, FBy, FBefore, FAfter, FAt, FTabs: TFloatSpinEdit;
    FContextual, FWidows, FKeepNext, FKeepLines, FBreak, FHyph, FShadeOn: TCheckBox;
    FShade: TColorButton;
    FBox: TPaintBox;
    procedure PaintPreview(Sender: TObject);
    procedure LineChanged(Sender: TObject);
    function LineIndex: Integer;
  protected
    procedure Changed(Sender: TObject); override;
  public
    constructor Build(AEdit: TParadeEdit; const ACaption: string; const AIn: pd_para_props);
    function Delta: pd_para_props;
  end;

function TLedParaDlg.LineIndex: Integer;
begin
  case FIn.line_rule of
    PD_LINE_AT_LEAST: Result := 3;
    PD_LINE_EXACT: Result := 4;
  else
    case FIn.line_spacing of
      0, 1000: Result := 0;
      1500: Result := 1;
      2000: Result := 2;
    else
      Result := 5;
    end;
  end;
end;

constructor TLedParaDlg.Build(AEdit: TParadeEdit; const ACaption: string; const AIn: pd_para_props);
var
  PC: TPageControl;
  Tab: TTabSheet;
  G: TGroupBox;
  I: Integer;
begin
  Make(AEdit, ACaption, 470, 500);
  FIn := AIn;
  if FIn.line_spacing = 0 then
    FIn.line_spacing := 1000;
  FLoading := True;
  PC := TPageControl.Create(Self);
  PC.Parent := Self;
  PC.Name := 'ParaPages';
  PC.Align := alClient;
  Tab := PC.AddTabSheet;
  Tab.Caption := 'Indents and spacing';
  G := Group(Tab, 'General', 8, 2, 446, 60);
  Lbl(G, 'Alignment:', 10, 4);
  FAlign := Combo(G, 'ParaAlign', 90, 4, 120, AlignNames, True);
  FAlign.ItemIndex := 0;
  for I := 0 to 3 do
    if AlignValues[I] = FIn.align then
      FAlign.ItemIndex := I;
  Lbl(G, 'Direction:', 224, 4);
  FDir := Combo(G, 'ParaDirection', 320, 4, 116, 'As the text|Left to right|Right to left', True);
  FDir.ItemIndex := EnsureRange(FIn.direction, 0, 2);
  G := Group(Tab, 'Indentation', 8, 66, 446, 92);
  Lbl(G, 'Left (pt):', 10, 4);
  FLeft := Spin(G, 'ParaIndentLeft', 90, 4, 80, -500, 1000, FIn.indent_left / Pt);
  Lbl(G, 'Right (pt):', 10, 36);
  FRight := Spin(G, 'ParaIndentRight', 90, 36, 80, -500, 1000, FIn.indent_right / Pt);
  Lbl(G, 'Special:', 224, 4);
  FSpecial := Combo(G, 'ParaSpecial', 320, 4, 116, '(none)|First line|Hanging', True);
  if FIn.indent_first > 0 then
    FSpecial.ItemIndex := 1
  else if FIn.indent_first < 0 then
    FSpecial.ItemIndex := 2
  else
    FSpecial.ItemIndex := 0;
  Lbl(G, 'By (pt):', 224, 36);
  FBy := Spin(G, 'ParaSpecialBy', 320, 36, 80, 0, 1000, Abs(FIn.indent_first) / Pt);
  G := Group(Tab, 'Spacing', 8, 162, 446, 118);
  Lbl(G, 'Before (pt):', 10, 4);
  FBefore := Spin(G, 'ParaBefore', 90, 4, 80, 0, 1600, FIn.space_before / Pt);
  Lbl(G, 'After (pt):', 10, 36);
  FAfter := Spin(G, 'ParaAfter', 90, 36, 80, 0, 1600, FIn.space_after / Pt);
  Lbl(G, 'Line spacing:', 224, 4);
  FLine := Combo(G, 'ParaLineRule', 320, 4, 116, LineNames, True);
  FLine.ItemIndex := LineIndex;
  Lbl(G, 'At:', 224, 36);
  FAt := Spin(G, 'ParaLineAt', 320, 36, 80, 0, 1600, 1, 2);
  case FLine.ItemIndex of
    3, 4: FAt.Value := FIn.line_height / Pt;
    5: FAt.Value := FIn.line_spacing / 1000;
  end;
  FAt.Enabled := FLine.ItemIndex >= 3;
  FLine.OnChange := @LineChanged;
  FContextual := Box(G, 'ParaContextual', 'No space between paragraphs of the same style', 10, 68,
    FIn.contextual <> 0);
  Lbl(Tab, 'Preview', 10, 284);
  FBox := Preview(Tab, 'ParaPreview', 10, 304, 444, 130);
  FBox.OnPaint := @PaintPreview;
  Tab := PC.AddTabSheet;
  Tab.Caption := 'Line and page breaks';
  G := Group(Tab, 'Pagination', 8, 2, 446, 116);
  FWidows := Box(G, 'ParaWidows', 'Widow and orphan control (no line alone at a page''s top or bottom)', 10, 4,
    (FIn.widows > 1) or (FIn.orphans > 1));
  FKeepNext := Box(G, 'ParaKeepNext', 'Keep with next', 10, 26, FIn.keep_with_next <> 0);
  FKeepLines := Box(G, 'ParaKeepLines', 'Keep lines together', 10, 48, FIn.keep_lines <> 0);
  FBreak := Box(G, 'ParaBreakBefore', 'Page break before', 10, 70, FIn.page_break_before <> 0);
  G := Group(Tab, 'Formatting', 8, 122, 446, 120);
  FHyph := Box(G, 'ParaHyphenate', 'Hyphenate', 10, 4, FIn.hyphenate <> 0);
  Lbl(G, 'Default tab stops (pt):', 10, 30);
  I := FIn.tab_interval;
  if I = 0 then
    I := 36 * Pt;
  FTabs := Spin(G, 'ParaTabInterval', 170, 30, 80, 1, 500, I / Pt);
  FShadeOn := Box(G, 'ParaShadingOn', 'Shading:', 10, 64, FIn.shading <> 0);
  if FIn.shading <> 0 then
    FShade := ColorBtn(G, 'ParaShading', 170, 60, ColorOf(FIn.shading))
  else
    FShade := ColorBtn(G, 'ParaShading', 170, 60, RGBToColor($F2, $F2, $F2));
  PC.ActivePageIndex := 0;
  FLoading := False;
end;

procedure TLedParaDlg.LineChanged(Sender: TObject);
begin
  if FLoading then
    Exit;
  FLoading := True;
  try
    case FLine.ItemIndex of
      3, 4: if FAt.Value < 4 then FAt.Value := 12;
      5: FAt.Value := 1.15;
    end;
    FAt.Enabled := FLine.ItemIndex >= 3;
  finally
    FLoading := False;
  end;
  Changed(Sender);
end;

procedure TLedParaDlg.Changed(Sender: TObject);
begin
  if FLoading then
    Exit;
  if Sender = FShade then
    FShadeOn.Checked := True;
  if FBox <> nil then
    FBox.Invalidate;
end;

procedure TLedParaDlg.PaintPreview(Sender: TObject);
var
  C: TCanvas;
  K, Pitch, Y, L, R, First, X0, X1: Double;

  procedure Bars(Count: Integer; AColor: TColor; ALeft, ARight, AFirst: Double; AAlign: Integer);
  var
    J: Integer;
    A, B, Len: Double;
  begin
    C.Brush.Color := AColor;
    for J := 0 to Count - 1 do
    begin
      A := X0 + ALeft;
      if J = 0 then
        A := A + AFirst;
      B := X1 - ARight;
      if J = Count - 1 then
        Len := (B - A) * 0.55
      else if AAlign = PD_ALIGN_JUSTIFY then
        Len := B - A
      else
        Len := (B - A) * (0.82 + 0.06 * (J mod 3));
      case AAlign of
        PD_ALIGN_CENTER: A := A + (B - A - Len) / 2;
        PD_ALIGN_RIGHT: A := B - Len;
      end;
      C.FillRect(Round(A), Round(Y), Round(A + Len), Round(Y + Max(2, Pitch * 0.45)));
      Y := Y + Pitch;
    end;
  end;

begin
  C := FBox.Canvas;
  C.Brush.Color := clWhite;
  C.Pen.Color := clGray;
  C.Rectangle(0, 0, FBox.Width, FBox.Height);
  X0 := S(8);
  X1 := FBox.Width - S(8);
  K := (X1 - X0) / 468;     { a 6.5 inch line }
  Y := S(6);
  Pitch := 12 * K;
  Bars(2, RGBToColor($D0, $D0, $D0), 0, 0, 0, PD_ALIGN_LEFT);
  case FLine.ItemIndex of
    1: Pitch := 18 * K;
    2: Pitch := 24 * K;
    3: Pitch := Max(12, FAt.Value) * K;
    4: Pitch := FAt.Value * K;
    5: Pitch := 12 * FAt.Value * K;
  else
    Pitch := 12 * K;
  end;
  Pitch := EnsureRange(Pitch, 2, 30);
  Y := Y + Min(FBefore.Value * K, 30);
  L := FLeft.Value * K;
  R := FRight.Value * K;
  First := 0;
  case FSpecial.ItemIndex of
    1: First := FBy.Value * K;
    2: First := -FBy.Value * K;
  end;
  Bars(4, RGBToColor($40, $40, $40), L, R, First, AlignValues[Max(0, FAlign.ItemIndex)]);
  Y := Y + Min(FAfter.Value * K, 30);
  Pitch := 12 * K;
  Bars(2, RGBToColor($D0, $D0, $D0), 0, 0, 0, PD_ALIGN_LEFT);
end;

function TLedParaDlg.Delta: pd_para_props;
var
  V: pd_sp;
  I, Ls, Rule: Integer;
  H: pd_sp;
begin
  FillChar(Result, SizeOf(Result), 0);
  I := AlignValues[Max(0, FAlign.ItemIndex)];
  if I <> FIn.align then
  begin
    Result.mask := Result.mask or PD_PP_ALIGN;
    Result.align := I;
  end;
  if FDir.ItemIndex <> FIn.direction then
  begin
    Result.mask := Result.mask or PD_PP_DIRECTION;
    Result.direction := Max(0, FDir.ItemIndex);
  end;
  V := Round(FLeft.Value * Pt);
  if V <> FIn.indent_left then
  begin
    Result.mask := Result.mask or PD_PP_INDENT_LEFT;
    Result.indent_left := V;
  end;
  V := Round(FRight.Value * Pt);
  if V <> FIn.indent_right then
  begin
    Result.mask := Result.mask or PD_PP_INDENT_RIGHT;
    Result.indent_right := V;
  end;
  case FSpecial.ItemIndex of
    1: V := Round(FBy.Value * Pt);
    2: V := -Round(FBy.Value * Pt);
  else
    V := 0;
  end;
  if V <> FIn.indent_first then
  begin
    Result.mask := Result.mask or PD_PP_INDENT_FIRST;
    Result.indent_first := V;
  end;
  V := Round(FBefore.Value * Pt);
  if V <> FIn.space_before then
  begin
    Result.mask := Result.mask or PD_PP_SPACE_BEFORE;
    Result.space_before := V;
  end;
  V := Round(FAfter.Value * Pt);
  if V <> FIn.space_after then
  begin
    Result.mask := Result.mask or PD_PP_SPACE_AFTER;
    Result.space_after := V;
  end;
  Rule := PD_LINE_MULTIPLE;
  Ls := 1000;
  H := 0;
  case FLine.ItemIndex of
    1: Ls := 1500;
    2: Ls := 2000;
    3: begin Rule := PD_LINE_AT_LEAST; H := Round(FAt.Value * Pt); end;
    4: begin Rule := PD_LINE_EXACT; H := Round(FAt.Value * Pt); end;
    5: Ls := Round(FAt.Value * 1000);
  end;
  if (Rule <> FIn.line_rule) or (Ls <> FIn.line_spacing) and (Rule = PD_LINE_MULTIPLE) or
    (H <> FIn.line_height) and (Rule <> PD_LINE_MULTIPLE) then
  begin
    Result.mask := Result.mask or PD_PP_LINE_SPACING;
    Result.line_rule := Rule;
    Result.line_spacing := Ls;
    Result.line_height := H;
  end;
  if FContextual.Checked <> (FIn.contextual <> 0) then
  begin
    Result.mask := Result.mask or PD_PP_CONTEXTUAL;
    Result.contextual := Ord(FContextual.Checked);
  end;
  if FWidows.Checked <> ((FIn.widows > 1) or (FIn.orphans > 1)) then
  begin
    Result.mask := Result.mask or PD_PP_WIDOWS or PD_PP_ORPHANS;
    Result.widows := 1 + Ord(FWidows.Checked);
    Result.orphans := Result.widows;
  end;
  if FKeepNext.Checked <> (FIn.keep_with_next <> 0) then
  begin
    Result.mask := Result.mask or PD_PP_KEEP_NEXT;
    Result.keep_with_next := Ord(FKeepNext.Checked);
  end;
  if FKeepLines.Checked <> (FIn.keep_lines <> 0) then
  begin
    Result.mask := Result.mask or PD_PP_KEEP_LINES;
    Result.keep_lines := Ord(FKeepLines.Checked);
  end;
  if FBreak.Checked <> (FIn.page_break_before <> 0) then
  begin
    Result.mask := Result.mask or PD_PP_BREAK_BEFORE;
    Result.page_break_before := Ord(FBreak.Checked);
  end;
  if FHyph.Checked <> (FIn.hyphenate <> 0) then
  begin
    Result.mask := Result.mask or PD_PP_HYPHENATE;
    Result.hyphenate := Ord(FHyph.Checked);
  end;
  V := FIn.tab_interval;
  if V = 0 then
    V := 36 * Pt;
  if Round(FTabs.Value * Pt) <> V then
  begin   { the set stops go with the interval: kept as they were }
    Result.mask := Result.mask or PD_PP_TABS;
    Result.ntabs := FIn.ntabs;
    Result.tabs := FIn.tabs;
    Result.tab_interval := Round(FTabs.Value * Pt);
  end;
  if (FShadeOn.Checked <> (FIn.shading <> 0)) or
    (FShadeOn.Checked and (RGBOf(FShade.ButtonColor) <> (FIn.shading and $FFFFFF))) then
  begin
    Result.mask := Result.mask or PD_PP_SHADING;
    if FShadeOn.Checked then
      Result.shading := $FF000000 or RGBOf(FShade.ButtonColor);
  end;
end;

function LedParagraphDialog(AEdit: TParadeEdit; var Props: pd_para_props; const ACaption: string): Boolean;
var
  D: TLedParaDlg;
begin
  D := TLedParaDlg.Build(AEdit, ACaption, Props);
  try
    Result := D.Run;
    if Result then
    begin
      Props := D.Delta;
      Result := Props.mask <> 0;
    end;
  finally
    D.Free;
  end;
end;

{ ---- Bullets and numbering ---- }

type
  TLedListDlg = class(TLedFmtDlg)
  private
    FLevels: TParadeListLevels;
    FCur: Integer;
    FLevelList: TListBox;
    FPreset, FFormat, FText, FFont: TComboBox;
    FStart: TSpinEdit;
    FIndent, FHanging: TFloatSpinEdit;
    FBold, FWhole: TCheckBox;
    FBox: TPaintBox;
    procedure LevelClicked(Sender: TObject);
    procedure PresetChosen(Sender: TObject);
    procedure LoadLevel;
    procedure StoreLevel;
    procedure FillTexts;
    procedure PaintPreview(Sender: TObject);
  protected
    procedure Changed(Sender: TObject); override;
  public
    InList: Boolean;
    constructor Build(AEdit: TParadeEdit);
    property Levels: TParadeListLevels read FLevels;
  end;

constructor TLedListDlg.Build(AEdit: TParadeEdit);
var
  I, Lvl: Integer;
begin
  Make(AEdit, 'Bullets and numbering', 520, 420);
  FLoading := True;
  InList := AEdit.CurrentListLevels(FLevels, Lvl);
  Lbl(Self, 'Start from:', 10, 8);
  FPreset := Combo(Self, 'ListPreset', 110, 8, 200, Presets, True);
  FPreset.ItemIndex := 0;
  if not InList then
    FPreset.ItemIndex := 1;
  FPreset.OnChange := @PresetChosen;
  Lbl(Self, 'Level:', 10, 42);
  FLevelList := TListBox.Create(Self);
  FLevelList.Parent := Self;
  FLevelList.Name := 'ListLevel';
  FLevelList.SetBounds(S(10), S(64), S(50), S(230));
  for I := 1 to 9 do
    FLevelList.Items.Add(IntToStr(I));
  FLevelList.OnClick := @LevelClicked;
  Lbl(Self, 'Number style:', 80, 42);
  FFormat := Combo(Self, 'ListFormat', 200, 42, 160, NumNames, True);
  Lbl(Self, 'Bullet or format:', 80, 74);
  FText := Combo(Self, 'ListText', 200, 74, 100, '', False);
  FText.Hint := '%1 is the first level''s number, %2 the second''s, and so on';
  FText.ShowHint := True;
  Lbl(Self, 'Start at:', 310, 74);
  FStart := TSpinEdit.Create(Self);
  FStart.Parent := Self;
  FStart.Name := 'ListStart';
  FStart.SetBounds(S(410), S(74), S(70), S(25));
  FStart.MinValue := 0;
  FStart.MaxValue := 32767;
  FStart.OnChange := @Changed;
  Lbl(Self, 'Text indent (pt):', 80, 106);
  FIndent := Spin(Self, 'ListIndent', 200, 106, 80, 0, 1000, 0);
  Lbl(Self, 'Hanging (pt):', 310, 106);
  FHanging := Spin(Self, 'ListHanging', 410, 106, 70, -500, 500, 0);
  Lbl(Self, 'Label font:', 80, 138);
  FFont := Combo(Self, 'ListFont', 200, 138, 160, '', False);
  AEdit.GetFontFamilies(FFont.Items);
  FFont.Items.Insert(0, '');
  FBold := Box(Self, 'ListBold', 'Bold label', 410, 140, False);
  FWhole := Box(Self, 'ListWhole', 'The whole list, not only the selected paragraphs', 80, 172, InList);
  FWhole.Enabled := InList;
  Lbl(Self, 'Preview', 80, 200);
  FBox := Preview(Self, 'ListPreview', 80, 222, 430, 190);
  FBox.OnPaint := @PaintPreview;
  Btn(FButtons, 'ListRemove', 'Remove the list', 10, 120, mrNo, nil).Enabled := InList;
  FCur := EnsureRange(Lvl, 0, 8);
  FLevelList.ItemIndex := FCur;
  FLoading := False;
  if not InList then
    PresetChosen(nil)
  else
    LoadLevel;
end;

procedure TLedListDlg.FillTexts;
var
  N: string;
begin
  FText.Items.Clear;
  if FLevels[FCur].format = PD_NUM_BULLET then
  begin
    FText.Items.Delimiter := '|';
    FText.Items.StrictDelimiter := True;
    FText.Items.DelimitedText := Bullets;
  end
  else
  begin
    N := '%' + IntToStr(FCur + 1);
    FText.Items.Add(N + '.');
    FText.Items.Add(N + ')');
    FText.Items.Add('(' + N + ')');
    FText.Items.Add(N);
    if FCur > 0 then
      FText.Items.Add('%1.' + N + '.');
  end;
end;

procedure TLedListDlg.LoadLevel;
var
  I: Integer;
begin
  FLoading := True;
  try
    FFormat.ItemIndex := High(NumFormats);
    for I := 0 to High(NumFormats) do
      if NumFormats[I] = FLevels[FCur].format then
        FFormat.ItemIndex := I;
    FillTexts;
    FText.Text := Fam(FLevels[FCur].text);
    FStart.Value := FLevels[FCur].start;
    FStart.Enabled := FLevels[FCur].format <> PD_NUM_BULLET;
    FIndent.Value := FLevels[FCur].indent / Pt;
    FHanging.Value := FLevels[FCur].hanging / Pt;
    FFont.Text := Fam(FLevels[FCur].label_family);
    FBold.Checked := FLevels[FCur].label_weight >= 600;
  finally
    FLoading := False;
  end;
  FBox.Invalidate;
end;

procedure TLedListDlg.StoreLevel;
var
  Was: Integer;
begin
  Was := FLevels[FCur].format;
  FLevels[FCur].format := NumFormats[Max(0, FFormat.ItemIndex)];
  if (FLevels[FCur].format = PD_NUM_BULLET) <> (Was = PD_NUM_BULLET) then
  begin   { from a bullet to a number or back: a label of the new kind }
    if FLevels[FCur].format = PD_NUM_BULLET then
      FText.Text := #$E2#$80#$A2
    else
      FText.Text := '%' + IntToStr(FCur + 1) + '.';
  end;
  SetFam(FLevels[FCur].text, FText.Text);
  FLevels[FCur].start := FStart.Value;
  FLevels[FCur].indent := Round(FIndent.Value * Pt);
  FLevels[FCur].hanging := Round(FHanging.Value * Pt);
  SetFam(FLevels[FCur].label_family, Trim(FFont.Text));
  if FBold.Checked then
    FLevels[FCur].label_weight := 700
  else if FLevels[FCur].label_weight >= 600 then
    FLevels[FCur].label_weight := 0;
  if (FLevels[FCur].format = PD_NUM_BULLET) <> (Was = PD_NUM_BULLET) then
    LoadLevel;
end;

procedure TLedListDlg.Changed(Sender: TObject);
begin
  if FLoading then
    Exit;
  StoreLevel;
  FStart.Enabled := FLevels[FCur].format <> PD_NUM_BULLET;
  FLoading := True;
  try
    FPreset.ItemIndex := 0;    { the levels as they now are }
  finally
    FLoading := False;
  end;
  FBox.Invalidate;
end;

procedure TLedListDlg.LevelClicked(Sender: TObject);
begin
  if FLevelList.ItemIndex < 0 then
    Exit;
  FCur := FLevelList.ItemIndex;
  LoadLevel;
end;

procedure TLedListDlg.PresetChosen(Sender: TObject);
const
  Chk = #$E2#$9C#$93;
  Arr = #$E2#$9E#$A2;
var
  I: Integer;
begin
  if FLoading then
    Exit;
  case FPreset.ItemIndex of
    1: FLevels := TParadeEdit.DefaultListLevels(PD_NUM_BULLET);
    2: FLevels := TParadeEdit.DefaultListLevels(PD_NUM_DECIMAL);
    3, 4:
      begin
        FLevels := TParadeEdit.DefaultListLevels(PD_NUM_DECIMAL);
        for I := 0 to 8 do
          if FPreset.ItemIndex = 3 then
            SetFam(FLevels[I].text, '%' + IntToStr(I + 1) + ')')
          else
            SetFam(FLevels[I].text, '(%' + IntToStr(I + 1) + ')');
      end;
    5:
      begin   { legal: each level its parents' numbers too }
        FLevels := TParadeEdit.DefaultListLevels(PD_NUM_DECIMAL);
        for I := 0 to 8 do
        begin
          FLevels[I].format := PD_NUM_DECIMAL;
          SetFam(FLevels[I].text, '');
          FLevels[I].text[0] := #0;
        end;
        for I := 0 to 8 do
        begin
          if I = 0 then
            SetFam(FLevels[I].text, '%1.')
          else
            SetFam(FLevels[I].text, Fam(FLevels[I - 1].text) + '%' + IntToStr(I + 1) + '.');
          FLevels[I].hanging := (18 + 8 * Min(I, 4)) * Pt;
        end;
      end;
    6:
      begin
        FLevels := TParadeEdit.DefaultListLevels(PD_NUM_DECIMAL);
        for I := 0 to 8 do
          if I mod 3 = 0 then
            FLevels[I].format := PD_NUM_UPPER_ALPHA;
      end;
    7:
      begin   { an outline: I. A. 1. a. i. }
        FLevels := TParadeEdit.DefaultListLevels(PD_NUM_DECIMAL);
        for I := 0 to 8 do
          case I mod 5 of
            0: FLevels[I].format := PD_NUM_UPPER_ROMAN;
            1: FLevels[I].format := PD_NUM_UPPER_ALPHA;
            2: FLevels[I].format := PD_NUM_DECIMAL;
            3: FLevels[I].format := PD_NUM_LOWER_ALPHA;
            4: FLevels[I].format := PD_NUM_LOWER_ROMAN;
          end;
      end;
    8, 9:
      begin
        FLevels := TParadeEdit.DefaultListLevels(PD_NUM_BULLET);
        for I := 0 to 8 do
          if FPreset.ItemIndex = 8 then
            SetFam(FLevels[I].text, Chk)
          else
            SetFam(FLevels[I].text, Arr);
      end;
  else
    Exit;
  end;
  LoadLevel;
end;

procedure TLedListDlg.PaintPreview(Sender: TObject);
const
  Items: array[0..5] of Integer = (0, 1, 1, 2, 0, 0);
  Words: array[0..5] of string = ('The first item', 'A point under it', 'Another point', 'A detail of that one',
    'The second item', 'The third item');
var
  C: TCanvas;
  Counts: array[0..8] of Integer;
  I, J, L, Y, H: Integer;
  K: Double;
  T: string;
  XL, XT: Integer;
begin
  C := FBox.Canvas;
  C.Brush.Color := clWhite;
  C.Pen.Color := clGray;
  C.Rectangle(0, 0, FBox.Width, FBox.Height);
  C.Font.Size := 9;
  H := C.TextHeight('Ag') + S(6);
  K := (FBox.Width - S(150)) / 216;     { three inches of indent in the room there is }
  for J := 0 to 8 do
    Counts[J] := FLevels[J].start - 1;
  Y := S(6);
  for I := 0 to High(Items) do
  begin
    L := Items[I];
    Inc(Counts[L]);
    for J := L + 1 to 8 do
      Counts[J] := FLevels[J].start - 1;
    T := LedListLabel(FLevels, L, Counts);
    XT := S(6) + Round(FLevels[L].indent * K / Pt);
    XL := XT - Round(FLevels[L].hanging * K / Pt);
    C.Font.Style := [];
    if (L = FCur) then
      C.Font.Color := clBlack
    else
      C.Font.Color := clGray;
    if Fam(FLevels[L].label_family) <> '' then
      C.Font.Name := Fam(FLevels[L].label_family)
    else
      C.Font.Name := 'default';
    if FLevels[L].label_weight >= 600 then
      C.Font.Style := [fsBold];
    C.TextOut(XL, Y, T);
    C.Font.Name := 'default';
    C.Font.Style := [];
    C.TextOut(Max(XT, XL + C.TextWidth(T) + S(4)), Y, Words[I]);
    Inc(Y, H);
  end;
end;

function LedListDialog(AEdit: TParadeEdit): Boolean;
var
  D: TLedListDlg;
  R: TModalResult;
begin
  Result := False;
  D := TLedListDlg.Build(AEdit);
  try
    R := D.RunResult;
    if R = mrNo then
    begin
      AEdit.RemoveList;
      Result := True;
    end
    else if R = mrOK then
    begin
      AEdit.ApplyListLevels(D.Levels, D.FWhole.Checked and D.InList);
      Result := True;
    end;
  finally
    D.Free;
  end;
end;

{ ---- a paragraph style ---- }

type
  TLedStyleDlg = class(TLedFmtDlg)
  private
    FIsNew: Boolean;
    FStyleName: string;
    FWorkC, FChgC: pd_char_props;
    FWorkP, FChgP: pd_para_props;
    FName: TEdit;
    FBasedOn, FNext, FFont, FAlign: TComboBox;
    FSize, FBefore, FAfter: TFloatSpinEdit;
    FBold, FItalic: TCheckBox;
    FCol: TColorButton;
    FDesc: TLabel;
    FBox: TPaintBox;
    procedure LoadQuick;
    procedure Harvest;
    procedure FontClicked(Sender: TObject);
    procedure ParaClicked(Sender: TObject);
    procedure PaintPreview(Sender: TObject);
  protected
    procedure Changed(Sender: TObject); override;
  public
    OwnC: pd_char_props;
    OwnP: pd_para_props;
    constructor Build(AEdit: TParadeEdit; const AStyle: string; AIsNew: Boolean);
    function Commit: Boolean;
  end;

constructor TLedStyleDlg.Build(AEdit: TParadeEdit; const AStyle: string; AIsNew: Boolean);
var
  St, Par: pd_style_id;
  Kind: Int32;
  Names: TStringList;
  I: Integer;
  ParentName, NextName: string;
  G: TGroupBox;
begin
  if AIsNew then
    Make(AEdit, 'New style', 500, 420)
  else
    Make(AEdit, 'Modify style: ' + AStyle, 500, 420);
  FIsNew := AIsNew;
  FStyleName := AStyle;
  FLoading := True;
  FillChar(FChgC, SizeOf(FChgC), 0);
  FillChar(FChgP, SizeOf(FChgP), 0);
  FillChar(OwnC, SizeOf(OwnC), 0);
  FillChar(OwnP, SizeOf(OwnP), 0);
  ParentName := 'Normal';
  NextName := '';
  if AIsNew then
  begin   { the caret paragraph's look }
    FWorkC := AEdit.CurrentCharProps;
    FWorkP := AEdit.CurrentParaProps;
    OwnC := FWorkC;
    OwnC.mask := PD_CP_FAMILY or PD_CP_SIZE or PD_CP_WEIGHT or PD_CP_ITALIC or PD_CP_COLOR;
    OwnP := FWorkP;
    OwnP.mask := PD_PP_ALIGN or PD_PP_SPACE_BEFORE or PD_PP_SPACE_AFTER or PD_PP_LINE_SPACING or
      PD_PP_INDENT_LEFT or PD_PP_INDENT_FIRST;
  end
  else
  begin
    St := pd_doc_style_find(AEdit.Doc, PAnsiChar(AStyle));
    Kind := 0;
    Par := 0;
    pd_doc_style_info(AEdit.Doc, St, @Kind, @Par, @OwnP, @OwnC);
    ParentName := '';
    if Par <> 0 then
      ParentName := pd_doc_style_name(AEdit.Doc, Par);
    pd_doc_style_resolve(AEdit.Doc, St, @FWorkP, @FWorkC);
    if (OwnP.mask and PD_PP_NEXT_STYLE <> 0) and (OwnP.next_style <> 0) then
      NextName := pd_doc_style_name(AEdit.Doc, OwnP.next_style);
  end;
  Names := TStringList.Create;
  try
    AEdit.GetParagraphStyles(Names);
    Lbl(Self, 'Name:', 10, 10);
    FName := TEdit.Create(Self);
    FName.Parent := Self;
    FName.Name := 'StyleName';
    FName.SetBounds(S(160), S(10), S(220), S(25));
    FName.Text := AStyle;
    FName.ReadOnly := not AIsNew;
    if not AIsNew then
      FName.Color := clBtnFace;
    Lbl(Self, 'Based on:', 10, 42);
    FBasedOn := Combo(Self, 'StyleBasedOn', 160, 42, 220, '', True);
    FBasedOn.Items.Add('(none)');
    for I := 0 to Names.Count - 1 do
      if Names[I] <> AStyle then
        FBasedOn.Items.Add(Names[I]);
    FBasedOn.ItemIndex := Max(0, FBasedOn.Items.IndexOf(ParentName));
    Lbl(Self, 'Following paragraph:', 10, 74);
    FNext := Combo(Self, 'StyleNext', 160, 74, 220, '', True);
    FNext.Items.Add('(this style)');
    for I := 0 to Names.Count - 1 do
      if Names[I] <> AStyle then
        FNext.Items.Add(Names[I]);
    FNext.ItemIndex := Max(0, FNext.Items.IndexOf(NextName));
  finally
    Names.Free;
  end;
  G := Group(Self, 'Formatting', 8, 104, 484, 96);
  FFont := Combo(G, 'StyleFont', 10, 2, 170, '', False);
  AEdit.GetFontFamilies(FFont.Items);
  FSize := Spin(G, 'StyleSize', 188, 2, 70, 1, 400, 11);
  FBold := Box(G, 'StyleBold', 'Bold', 268, 4, False);
  FItalic := Box(G, 'StyleItalic', 'Italic', 328, 4, False);
  FCol := ColorBtn(G, 'StyleColor', 392, 0, clBlack);
  FAlign := Combo(G, 'StyleAlign', 10, 38, 110, AlignNames, True);
  Lbl(G, 'Before:', 132, 38);
  FBefore := Spin(G, 'StyleBefore', 184, 38, 64, 0, 400, 0);
  Lbl(G, 'After:', 258, 38);
  FAfter := Spin(G, 'StyleAfter', 302, 38, 64, 0, 400, 0);
  Lbl(G, 'pt', 372, 38);
  FBox := Preview(Self, 'StylePreview', 10, 210, 480, 120);
  FBox.OnPaint := @PaintPreview;
  FDesc := Lbl(Self, '', 10, 336);
  FDesc.Name := 'StyleDesc';
  FDesc.Caption := '';
  FDesc.AutoSize := False;
  FDesc.WordWrap := True;
  FDesc.SetBounds(S(10), S(338), S(480), S(70));
  Btn(FButtons, 'StyleFontBtn', 'Font...', 10, 90, mrNone, @FontClicked);
  Btn(FButtons, 'StyleParaBtn', 'Paragraph...', 106, 100, mrNone, @ParaClicked);
  LoadQuick;
  FLoading := False;
end;

procedure TLedStyleDlg.LoadQuick;
var
  I: Integer;
begin
  FLoading := True;
  try
    FFont.Text := Fam(FWorkC.family);
    FSize.Value := FWorkC.size / Pt;
    FBold.Checked := FWorkC.weight >= 600;
    FItalic.Checked := FWorkC.italic <> 0;
    FCol.ButtonColor := ColorOf(FWorkC.color);
    FAlign.ItemIndex := 0;
    for I := 0 to 3 do
      if AlignValues[I] = FWorkP.align then
        FAlign.ItemIndex := I;
    FBefore.Value := FWorkP.space_before / Pt;
    FAfter.Value := FWorkP.space_after / Pt;
  finally
    FLoading := False;
  end;
  FDesc.Caption := LedStyleSummary(FWorkP, FWorkC);
  FBox.Invalidate;
end;

{ the quick controls' changes, into the style's look and what changed }
procedure TLedStyleDlg.Harvest;
var
  C: pd_char_props;
  P: pd_para_props;
begin
  FillChar(C, SizeOf(C), 0);
  FillChar(P, SizeOf(P), 0);
  if (Trim(FFont.Text) <> '') and (Trim(FFont.Text) <> Fam(FWorkC.family)) then
  begin
    C.mask := C.mask or PD_CP_FAMILY;
    SetFam(C.family, Trim(FFont.Text));
    C.font_theme := FWorkC.font_theme and not 3;
  end;
  if Round(FSize.Value * Pt) <> FWorkC.size then
  begin
    C.mask := C.mask or PD_CP_SIZE;
    C.size := Round(FSize.Value * Pt);
  end;
  if FBold.Checked <> (FWorkC.weight >= 600) then
  begin
    C.mask := C.mask or PD_CP_WEIGHT;
    if FBold.Checked then C.weight := 700 else C.weight := 400;
  end;
  if FItalic.Checked <> (FWorkC.italic <> 0) then
  begin
    C.mask := C.mask or PD_CP_ITALIC;
    C.italic := Ord(FItalic.Checked);
  end;
  if RGBOf(FCol.ButtonColor) <> (FWorkC.color and $FFFFFF) then
  begin
    C.mask := C.mask or PD_CP_COLOR;
    C.color := $FF000000 or RGBOf(FCol.ButtonColor);
  end;
  if AlignValues[Max(0, FAlign.ItemIndex)] <> FWorkP.align then
  begin
    P.mask := P.mask or PD_PP_ALIGN;
    P.align := AlignValues[Max(0, FAlign.ItemIndex)];
  end;
  if Round(FBefore.Value * Pt) <> FWorkP.space_before then
  begin
    P.mask := P.mask or PD_PP_SPACE_BEFORE;
    P.space_before := Round(FBefore.Value * Pt);
  end;
  if Round(FAfter.Value * Pt) <> FWorkP.space_after then
  begin
    P.mask := P.mask or PD_PP_SPACE_AFTER;
    P.space_after := Round(FAfter.Value * Pt);
  end;
  MergeCharProps(FWorkC, C);
  MergeCharProps(FChgC, C);
  MergeParaProps(FWorkP, P);
  MergeParaProps(FChgP, P);
end;

procedure TLedStyleDlg.Changed(Sender: TObject);
begin
  if FLoading then
    Exit;
  Harvest;
  FDesc.Caption := LedStyleSummary(FWorkP, FWorkC);
  FBox.Invalidate;
end;

procedure TLedStyleDlg.FontClicked(Sender: TObject);
var
  C: pd_char_props;
begin
  Harvest;
  C := FWorkC;
  if LedFontDialog(FEdit, C, 'Font of ' + FName.Text) then
  begin
    MergeCharProps(FWorkC, C);
    MergeCharProps(FChgC, C);
    LoadQuick;
  end;
end;

procedure TLedStyleDlg.ParaClicked(Sender: TObject);
var
  P: pd_para_props;
begin
  Harvest;
  P := FWorkP;
  if LedParagraphDialog(FEdit, P, 'Paragraph of ' + FName.Text) then
  begin
    MergeParaProps(FWorkP, P);
    MergeParaProps(FChgP, P);
    LoadQuick;
  end;
end;

procedure TLedStyleDlg.PaintPreview(Sender: TObject);
var
  C: TCanvas;
  T: string;
  X, Y, W: Integer;
begin
  C := FBox.Canvas;
  C.Brush.Color := clWhite;
  C.Pen.Color := clGray;
  C.Rectangle(0, 0, FBox.Width, FBox.Height);
  if FWorkP.shading <> 0 then
  begin
    C.Brush.Color := ColorOf(FWorkP.shading);
    C.FillRect(S(4), S(4), FBox.Width - S(4), FBox.Height - S(4));
  end;
  if Fam(FWorkC.family) <> '' then
    C.Font.Name := Fam(FWorkC.family);
  C.Font.Size := EnsureRange(Round(FWorkC.size / Pt), 4, 36);
  C.Font.Style := [];
  if FWorkC.weight >= 600 then
    C.Font.Style := C.Font.Style + [fsBold];
  if FWorkC.italic <> 0 then
    C.Font.Style := C.Font.Style + [fsItalic];
  if FWorkC.underline <> 0 then
    C.Font.Style := C.Font.Style + [fsUnderline];
  C.Font.Color := ColorOf(FWorkC.color);
  T := FName.Text;
  if T = '' then
    T := 'A paragraph in this style';
  if FWorkC.caps <> 0 then
    T := UTF8UpperCase(T);
  W := C.TextWidth(T);
  case FWorkP.align of
    PD_ALIGN_CENTER: X := (FBox.Width - W) div 2;
    PD_ALIGN_RIGHT: X := FBox.Width - W - S(10);
  else
    X := S(10) + Min(FBox.Width div 2, Round(FWorkP.indent_left / Pt));
  end;
  Y := (FBox.Height - C.TextHeight(T)) div 2;
  C.Brush.Style := bsClear;
  C.TextOut(Max(S(4), X), Y, T);
  C.Brush.Style := bsSolid;
end;

function TLedStyleDlg.Commit: Boolean;
var
  NewName, BasedOn: string;
  Nx: pd_style_id;
begin
  Result := False;
  Harvest;
  NewName := Trim(FName.Text);
  if NewName = '' then
    Exit;
  if FIsNew and (pd_doc_style_find(FEdit.Doc, PAnsiChar(NewName)) <> 0) then
  begin
    MessageDlg('New style', 'There is a style called ' + NewName + ' already: Modify style changes it.',
      mtWarning, [mbOK], 0);
    Exit;
  end;
  MergeCharProps(OwnC, FChgC);
  MergeParaProps(OwnP, FChgP);
  BasedOn := '';
  if FBasedOn.ItemIndex > 0 then
    BasedOn := FBasedOn.Items[FBasedOn.ItemIndex];
  Nx := 0;
  if FNext.ItemIndex > 0 then
    Nx := pd_doc_style_find(FEdit.Doc, PAnsiChar(FNext.Items[FNext.ItemIndex]));
  if (Nx <> 0) or (OwnP.mask and PD_PP_NEXT_STYLE <> 0) then
  begin
    OwnP.mask := OwnP.mask or PD_PP_NEXT_STYLE;
    OwnP.next_style := Nx;
  end;
  Result := FEdit.DefineParagraphStyle(NewName, OwnP, OwnC, BasedOn);
  if Result and FIsNew then
    FEdit.SetParagraphStyle(NewName);
end;

function LedStyleDialog(AEdit: TParadeEdit; const StyleName: string; IsNew: Boolean): Boolean;
var
  D: TLedStyleDlg;
begin
  Result := False;
  if not IsNew and (pd_doc_style_find(AEdit.Doc, PAnsiChar(StyleName)) = 0) then
    Exit;
  D := TLedStyleDlg.Build(AEdit, StyleName, IsNew);
  try
    if D.Run then
      Result := D.Commit;
  finally
    D.Free;
  end;
end;

{ ---- the styles, all of them ---- }

type
  TLedStylesDlg = class(TLedFmtDlg)
  private
    FList: TListBox;
    FDesc: TLabel;
    FBox: TPaintBox;
    procedure Fill(const ASelect: string);
    procedure Picked(Sender: TObject);
    procedure ModifyClicked(Sender: TObject);
    procedure NewClicked(Sender: TObject);
    procedure PaintPreview(Sender: TObject);
    procedure Resolve(out Pp: pd_para_props; out Cp: pd_char_props);
  public
    constructor Build(AEdit: TParadeEdit);
    function Chosen: string;
  end;

constructor TLedStylesDlg.Build(AEdit: TParadeEdit);
begin
  Make(AEdit, 'Styles', 520, 360);
  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Name := 'StylesList';
  FList.SetBounds(S(10), S(10), S(180), S(340));
  FList.OnClick := @Picked;
  FList.OnDblClick := @ModifyClicked;
  FBox := Preview(Self, 'StylesPreview', 200, 10, 310, 120);
  FBox.OnPaint := @PaintPreview;
  FDesc := Lbl(Self, '', 200, 136);
  FDesc.Name := 'StylesDesc';
  FDesc.Caption := '';
  FDesc.AutoSize := False;
  FDesc.WordWrap := True;
  FDesc.SetBounds(S(200), S(138), S(310), S(120));
  with TButton.Create(Self) do
  begin
    Parent := Self;
    Name := 'StylesModify';
    Caption := 'Modify...';
    SetBounds(S(200), S(270), S(100), S(27));
    OnClick := @ModifyClicked;
  end;
  with TButton.Create(Self) do
  begin
    Parent := Self;
    Name := 'StylesNew';
    Caption := 'New...';
    SetBounds(S(310), S(270), S(100), S(27));
    OnClick := @NewClicked;
  end;
  TButton(FindComponent('BtnOK')).Caption := 'Apply';
  TButton(FindComponent('BtnCancel')).Caption := 'Close';
  Fill(AEdit.CurrentStyleName);
end;

procedure TLedStylesDlg.Fill(const ASelect: string);
begin
  FList.Items.Clear;
  FEdit.GetParagraphStyles(FList.Items);
  FList.ItemIndex := FList.Items.IndexOf(ASelect);
  if (FList.ItemIndex < 0) and (FList.Count > 0) then
    FList.ItemIndex := Max(0, FList.Items.IndexOf('Normal'));
  Picked(nil);
end;

function TLedStylesDlg.Chosen: string;
begin
  Result := '';
  if FList.ItemIndex >= 0 then
    Result := FList.Items[FList.ItemIndex];
end;

procedure TLedStylesDlg.Resolve(out Pp: pd_para_props; out Cp: pd_char_props);
begin
  FillChar(Pp, SizeOf(Pp), 0);
  FillChar(Cp, SizeOf(Cp), 0);
  if Chosen <> '' then
    pd_doc_style_resolve(FEdit.Doc, pd_doc_style_find(FEdit.Doc, PAnsiChar(Chosen)), @Pp, @Cp);
end;

procedure TLedStylesDlg.Picked(Sender: TObject);
var
  Pp: pd_para_props;
  Cp: pd_char_props;
begin
  Resolve(Pp, Cp);
  if Chosen <> '' then
    FDesc.Caption := LedStyleSummary(Pp, Cp)
  else
    FDesc.Caption := '';
  FBox.Invalidate;
end;

procedure TLedStylesDlg.ModifyClicked(Sender: TObject);
var
  N: string;
begin
  N := Chosen;
  if (N <> '') and LedStyleDialog(FEdit, N, False) then
    Fill(N);
end;

procedure TLedStylesDlg.NewClicked(Sender: TObject);
var
  Before: Integer;
begin
  Before := FList.Count;
  if LedStyleDialog(FEdit, '', True) then
  begin
    Fill(FEdit.CurrentStyleName);
    if FList.Count = Before then
      Picked(nil);
  end;
end;

procedure TLedStylesDlg.PaintPreview(Sender: TObject);
var
  Pp: pd_para_props;
  Cp: pd_char_props;
  C: TCanvas;
  T: string;
begin
  C := FBox.Canvas;
  C.Brush.Color := clWhite;
  C.Pen.Color := clGray;
  C.Rectangle(0, 0, FBox.Width, FBox.Height);
  T := Chosen;
  if T = '' then
    Exit;
  Resolve(Pp, Cp);
  if Fam(Cp.family) <> '' then
    C.Font.Name := Fam(Cp.family);
  C.Font.Size := EnsureRange(Round(Cp.size / Pt), 4, 32);
  C.Font.Style := [];
  if Cp.weight >= 600 then
    C.Font.Style := C.Font.Style + [fsBold];
  if Cp.italic <> 0 then
    C.Font.Style := C.Font.Style + [fsItalic];
  C.Font.Color := ColorOf(Cp.color);
  C.Brush.Style := bsClear;
  C.TextOut(S(10), (FBox.Height - C.TextHeight(T)) div 2, T);
  C.Brush.Style := bsSolid;
end;

function LedStylesDialog(AEdit: TParadeEdit): Boolean;
var
  D: TLedStylesDlg;
begin
  Result := False;
  D := TLedStylesDlg.Build(AEdit);
  try
    if D.Run and (D.Chosen <> '') then
    begin
      AEdit.SetParagraphStyle(D.Chosen);
      Result := True;
    end;
  finally
    D.Free;
  end;
end;

initialization
  Dot := DefaultFormatSettings;
  Dot.DecimalSeparator := '.';
{$ENDIF}
end.
