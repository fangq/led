{ LED - a lightweight editor.  The visual editor: Markdown, HTML and Word
  files edited as the pages they print as.

  The pages are Parade's -- a text layout engine in C with a Lazarus control
  of its own, TParadeEdit, which lays out, rasterizes and edits a document
  model that imports and exports Markdown, HTML and DOCX.  This unit is the
  frame around that control: the fonts it is given, a strip of formatting
  buttons, and the conversion between the document LED holds -- a text
  buffer, or the bytes of a .docx -- and Parade's.

  A visual edit is a translation, and the translation is not the identity:
  Markdown written as `*this*` comes back as `_this_`, HTML loses what the
  importer does not model.  So nothing is written back until something was
  changed here, and then all of it at once, as one undo step in the text.

  Parade is optional.  Built without it -- `make PARADE=` or no Parade tree
  next to LED -- led.parade.inc is the empty stub, every query here answers
  "not available", and the rest of LED needs no IFDEF of its own. }
unit Led.UI.Visual;

{$mode objfpc}{$H+}
{$I led.parade.inc}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, StdCtrls, Buttons, Graphics, Forms,
  Dialogs, LCLType
  {$IFDEF LED_PARADE}, parade, paradeedit{$ENDIF};

type
  TLedVisualKind = (lvkNone, lvkMarkdown, lvkHtml, lvkDocx);

  { The page view, a strip of buttons above it.  One per tab, made when the
    tab is first switched to it. }
  TLedVisualPane = class(TPanel)
  private
    FKind: TLedVisualKind;
    FBar: TPanel;
    FStyle: TComboBox;
    FMarkup: TComboBox;
    FTrack: TSpeedButton;
    FOnChange: TNotifyEvent;
    {$IFDEF LED_PARADE}
    FEdit: TParadeEdit;
    {$ENDIF}
    function AddButton(const ACaption, AHint: string; AStyle: TFontStyles;
      AOnClick: TNotifyEvent): TSpeedButton;
    procedure StyleChosen(Sender: TObject);
    procedure BoldClicked(Sender: TObject);
    procedure ItalicClicked(Sender: TObject);
    procedure UnderlineClicked(Sender: TObject);
    procedure TrackClicked(Sender: TObject);
    procedure PrevClicked(Sender: TObject);
    procedure NextClicked(Sender: TObject);
    procedure AcceptClicked(Sender: TObject);
    procedure RejectClicked(Sender: TObject);
    procedure CommentClicked(Sender: TObject);
    procedure MarkupChosen(Sender: TObject);
    procedure BackToPage;
    procedure EditChanged(Sender: TObject);
    function GetModified: Boolean;
    function GetEditor: TWinControl;
  public
    constructor Create(AOwner: TComponent); override;

    { The document in a format, the whole of it.  False with the reason when
      it would not import -- or when LED was built without Parade. }
    function Load(const AData: string; AKind: TLedVisualKind;
      const AFileName: string; out AWhy: string): Boolean;
    { And back out, in the format it came in -- or in another one. }
    function Export(AKind: TLedVisualKind = lvkNone): string;
    { The words on the pages, without their formatting. }
    function PlainText: string;
    { Typed at the caret, over the selection.  For scripting the page. }
    procedure InsertText(const AText: string);

    function CanUndo: Boolean;
    function CanRedo: Boolean;
    function SelAvail: Boolean;
    procedure Undo;
    procedure Redo;
    procedure CutToClipboard;
    procedure CopyToClipboard;
    procedure PasteFromClipboard;
    procedure SelectAll;
    procedure ToggleBold;
    procedure ToggleItalic;
    procedure ToggleUnderline;

    property Kind: TLedVisualKind read FKind;
    { Changed here since the last Load or MarkSaved. }
    property Modified: Boolean read GetModified;
    procedure MarkSaved;
    { The control that takes the focus and the keys.  nil without Parade. }
    property Editor: TWinControl read GetEditor;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

{ Whether this LED has the visual editor at all. }
function LedVisualAvailable: Boolean;

{ What the visual editor would open this file as, by its name. }
function LedVisualKindOf(const AFileName: string): TLedVisualKind;

{ The keys the visual editor takes before the window's shortcuts do: Ctrl+B
  is bold in a page and Toggle Bookmark everywhere else, and the window would
  otherwise always win -- see Led.UI.EditKeys. }
function LedVisualClaimKey(AKey: Word; AShift: TShiftState;
  AControl: TWinControl): Boolean;

implementation

uses
  Led.UI.EditKeys, Led.UI.Dpi;

const
  { The paragraph styles every Parade document is made with, in the order a
    reader looks for them. }
  StyleNames: array[0..9] of string = ('Normal', 'Title', 'Heading 1',
    'Heading 2', 'Heading 3', 'Heading 4', 'Heading 5', 'Heading 6',
    'Quote', 'Code');

function LedVisualAvailable: Boolean;
begin
  Result := {$IFDEF LED_PARADE}True{$ELSE}False{$ENDIF};
end;

function LedVisualKindOf(const AFileName: string): TLedVisualKind;
var
  E: string;
begin
  E := LowerCase(ExtractFileExt(AFileName));
  if (E = '.md') or (E = '.markdown') then Exit(lvkMarkdown);
  if (E = '.html') or (E = '.htm') or (E = '.xhtml') then Exit(lvkHtml);
  if E = '.docx' then Exit(lvkDocx);
  Result := lvkNone;
end;

{$IFDEF LED_PARADE}
function ParadeFormat(AKind: TLedVisualKind): Int32;
begin
  case AKind of
    lvkMarkdown: Result := PD_CONV_MARKDOWN;
    lvkHtml: Result := PD_CONV_HTML;
    lvkDocx: Result := PD_CONV_DOCX;
  else
    Result := -1;
  end;
end;

{ A serif and a sans for the text, a monospace for code, a math font for
  equations -- wherever this system keeps them.  Parade reads TrueType and
  OpenType files itself rather than asking the desktop, so it has to be told
  where they are.

  The serif comes first: it is what a document that names no font is set
  in.  A document that names a font this does not have -- Arial, Times New
  Roman -- gets a registered face of the same kind (pd_font_family_class),
  and the Liberation faces are the metric twins of those two, so the lines
  break where Word broke them.  Calibri and Cambria, the Office defaults,
  have twins of their own, Carlito and Caladea, registered under the names
  documents ask for. }
procedure AddFonts(AEdit: TParadeEdit);
type
  TFace = record
    Group, Family, Dir, Regular, Bold, Italic, BoldItalic: string;
  end;
const
  Groups: array[0..3] of string = ('serif', 'sans', 'calibri', 'cambria');
var
  Faces: array of TFace;
  Monos, Maths: array of string;
  g, i: Integer;

  procedure Face(const AGroup, AFamily, ADir, AR, AB, AI, ABI: string);
  begin
    SetLength(Faces, Length(Faces) + 1);
    with Faces[High(Faces)] do
    begin
      Group := AGroup;
      Family := AFamily;
      Dir := IncludeTrailingPathDelimiter(ADir);
      Regular := AR;
      Bold := AB;
      Italic := AI;
      BoldItalic := ABI;
    end;
  end;

  procedure Add(const AFamily, AFile: string; AWeight: Integer; AItalic: Boolean);
  begin
    if FileExists(AFile) then
      AEdit.AddFont(AFamily, AFile, AWeight, AItalic);
  end;

var
  Win: string;
begin
  Faces := nil;
  {$IFDEF WINDOWS}
  Win := GetEnvironmentVariable('WINDIR');
  if Win = '' then Win := 'C:\Windows';
  Win := Win + '\Fonts';
  Face('serif', 'Times New Roman', Win, 'times.ttf', 'timesbd.ttf', 'timesi.ttf', 'timesbi.ttf');
  Face('sans', 'Arial', Win, 'arial.ttf', 'arialbd.ttf', 'ariali.ttf', 'arialbi.ttf');
  Face('calibri', 'Calibri', Win, 'calibri.ttf', 'calibrib.ttf', 'calibrii.ttf', 'calibriz.ttf');
  Monos := [Win + '\consola.ttf', Win + '\cour.ttf'];
  Maths := [];
  {$ELSE}
  {$IFDEF DARWIN}
  Win := '/System/Library/Fonts/Supplemental';
  Face('serif', 'Times New Roman', Win, 'Times New Roman.ttf', 'Times New Roman Bold.ttf',
    'Times New Roman Italic.ttf', 'Times New Roman Bold Italic.ttf');
  Face('sans', 'Arial', Win, 'Arial.ttf', 'Arial Bold.ttf', 'Arial Italic.ttf',
    'Arial Bold Italic.ttf');
  Monos := [Win + '/Courier New.ttf'];
  Maths := [];
  {$ELSE}
  Win := '/usr/share/fonts/';
  Face('serif', 'Liberation Serif', Win + 'truetype/liberation', 'LiberationSerif-Regular.ttf',
    'LiberationSerif-Bold.ttf', 'LiberationSerif-Italic.ttf', 'LiberationSerif-BoldItalic.ttf');
  Face('serif', 'Liberation Serif', Win + 'liberation-serif', 'LiberationSerif-Regular.ttf',
    'LiberationSerif-Bold.ttf', 'LiberationSerif-Italic.ttf', 'LiberationSerif-BoldItalic.ttf');
  Face('serif', 'DejaVu Serif', Win + 'truetype/dejavu', 'DejaVuSerif.ttf',
    'DejaVuSerif-Bold.ttf', 'DejaVuSerif-Italic.ttf', 'DejaVuSerif-BoldItalic.ttf');
  Face('serif', 'DejaVu Serif', Win + 'dejavu-serif-fonts', 'DejaVuSerif.ttf',
    'DejaVuSerif-Bold.ttf', 'DejaVuSerif-Italic.ttf', 'DejaVuSerif-BoldItalic.ttf');
  Face('sans', 'Liberation Sans', Win + 'truetype/liberation', 'LiberationSans-Regular.ttf',
    'LiberationSans-Bold.ttf', 'LiberationSans-Italic.ttf', 'LiberationSans-BoldItalic.ttf');
  Face('sans', 'Liberation Sans', Win + 'liberation-sans', 'LiberationSans-Regular.ttf',
    'LiberationSans-Bold.ttf', 'LiberationSans-Italic.ttf', 'LiberationSans-BoldItalic.ttf');
  Face('sans', 'DejaVu Sans', Win + 'truetype/dejavu', 'DejaVuSans.ttf',
    'DejaVuSans-Bold.ttf', 'DejaVuSans-Oblique.ttf', 'DejaVuSans-BoldOblique.ttf');
  Face('calibri', 'Calibri', Win + 'truetype/crosextra', 'Carlito-Regular.ttf',
    'Carlito-Bold.ttf', 'Carlito-Italic.ttf', 'Carlito-BoldItalic.ttf');
  Face('cambria', 'Cambria', Win + 'truetype/crosextra', 'Caladea-Regular.ttf',
    'Caladea-Bold.ttf', 'Caladea-Italic.ttf', 'Caladea-BoldItalic.ttf');
  Monos := [Win + 'truetype/dejavu/DejaVuSansMono.ttf',
    Win + 'dejavu-sans-mono-fonts/DejaVuSansMono.ttf',
    Win + 'truetype/liberation/LiberationMono-Regular.ttf'];
  Maths := ['/usr/share/texmf/fonts/opentype/public/lm-math/latinmodern-math.otf',
    '/usr/share/fonts/opentype/lmodern/latinmodern-math.otf',
    '/usr/share/texlive/texmf-dist/fonts/opentype/public/lm-math/latinmodern-math.otf'];
  {$ENDIF}
  {$ENDIF}

  { One family per group: the first one that is there, serif first. }
  for g := Low(Groups) to High(Groups) do
    for i := 0 to High(Faces) do
      with Faces[i] do
        if (Group = Groups[g]) and FileExists(Dir + Regular) then
        begin
          Add(Family, Dir + Regular, 400, False);
          Add(Family, Dir + Bold, 700, False);
          Add(Family, Dir + Italic, 400, True);
          Add(Family, Dir + BoldItalic, 700, True);
          Break;
        end;
  for i := 0 to High(Monos) do
    if FileExists(Monos[i]) then
    begin
      AEdit.AddFont('monospace', Monos[i]);
      Break;
    end;
  for i := 0 to High(Maths) do
    if FileExists(Maths[i]) then
    begin
      AEdit.SetMathFont(Maths[i]);
      Break;
    end;
end;
{$ENDIF}

{ TLedVisualPane }

constructor TLedVisualPane.Create(AOwner: TComponent);
var
  i: Integer;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';

  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.BevelOuter := bvNone;
  FBar.Caption := '';
  FBar.AutoSize := True;
  FBar.ChildSizing.LeftRightSpacing := LedScale96(4);
  FBar.ChildSizing.TopBottomSpacing := LedScale96(2);
  FBar.ChildSizing.HorizontalSpacing := LedScale96(2);
  FBar.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  FBar.ChildSizing.ControlsPerLine := 100;

  FStyle := TComboBox.Create(Self);
  FStyle.Parent := FBar;
  FStyle.Style := csDropDownList;
  FStyle.Width := LedScale96(120);
  FStyle.Hint := 'Paragraph style';
  FStyle.ShowHint := True;
  for i := Low(StyleNames) to High(StyleNames) do
    FStyle.Items.Add(StyleNames[i]);
  FStyle.ItemIndex := 0;
  FStyle.OnSelect := @StyleChosen;

  AddButton('B', 'Bold (Ctrl+B)', [fsBold], @BoldClicked);
  AddButton('I', 'Italic (Ctrl+I)', [fsItalic], @ItalicClicked);
  AddButton('U', 'Underline (Ctrl+U)', [fsUnderline], @UnderlineClicked);

  { review: tracked changes and comments }
  FTrack := AddButton('Track', 'Record edits as tracked changes', [], @TrackClicked);
  FTrack.AllowAllUp := True;
  FTrack.GroupIndex := 1;
  AddButton('<', 'Previous change or comment', [], @PrevClicked);
  AddButton('>', 'Next change or comment', [], @NextClicked);
  AddButton('Accept', 'Accept the change (the selection''s changes)', [], @AcceptClicked);
  AddButton('Reject', 'Reject the change (the selection''s changes)', [], @RejectClicked);
  AddButton('Comment', 'Comment on the selection, or reply to the comment at the caret', [], @CommentClicked);
  FMarkup := TComboBox.Create(Self);
  FMarkup.Parent := FBar;
  FMarkup.Style := csDropDownList;
  FMarkup.Width := LedScale96(110);
  FMarkup.Hint := 'How tracked changes show';
  FMarkup.ShowHint := True;
  FMarkup.Items.Add('Balloons');
  FMarkup.Items.Add('Inline');
  FMarkup.Items.Add('Final');
  FMarkup.Items.Add('Original');
  FMarkup.ItemIndex := 0;
  FMarkup.OnSelect := @MarkupChosen;

  {$IFDEF LED_PARADE}
  FEdit := TParadeEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Align := alClient;
  AddFonts(FEdit);
  FEdit.OnChange := @EditChanged;
  {$ENDIF}
end;

function TLedVisualPane.AddButton(const ACaption, AHint: string;
  AStyle: TFontStyles; AOnClick: TNotifyEvent): TSpeedButton;
begin
  { Speed buttons, so that a click leaves the caret where it was: a button
    that took the focus would take the selection's highlight with it. }
  Result := TSpeedButton.Create(Self);
  Result.Parent := FBar;
  Result.Caption := ACaption;
  Result.Font.Style := AStyle;
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.Flat := True;
  { A minimum rather than a width: the bar lays its children out itself and
    would shrink a button to its one-letter caption. }
  Result.Constraints.MinWidth := LedScale96(26);
  Result.Height := FStyle.Height;
  Result.OnClick := AOnClick;
end;

function TLedVisualPane.GetEditor: TWinControl;
begin
  Result := {$IFDEF LED_PARADE}FEdit{$ELSE}nil{$ENDIF};
end;

function TLedVisualPane.Load(const AData: string; AKind: TLedVisualKind;
  const AFileName: string; out AWhy: string): Boolean;
{$IFDEF LED_PARADE}
var
  S: TStringStream;
{$ENDIF}
begin
  Result := False;
  AWhy := '';
  {$IFDEF LED_PARADE}
  if AKind = lvkNone then
  begin
    AWhy := 'the visual editor opens Markdown, HTML and Word (.docx) files';
    Exit;
  end;
  S := TStringStream.Create(AData);
  try
    try
      FEdit.LoadFromStream(S, ParadeFormat(AKind), AFileName);
    except
      on E: Exception do
      begin
        AWhy := E.Message;
        Exit;
      end;
    end;
  finally
    S.Free;
  end;
  FKind := AKind;
  Result := True;
  {$ELSE}
  AWhy := 'this LED was built without Parade, the visual editor';
  {$ENDIF}
end;

function TLedVisualPane.Export(AKind: TLedVisualKind): string;
{$IFDEF LED_PARADE}
var
  S: TStringStream;
{$ENDIF}
begin
  Result := '';
  if AKind = lvkNone then AKind := FKind;
  if AKind = lvkNone then Exit;
  {$IFDEF LED_PARADE}
  S := TStringStream.Create('');
  try
    FEdit.SaveToStream(S, ParadeFormat(AKind));
    Result := S.DataString;
  finally
    S.Free;
  end;
  {$ENDIF}
end;

function TLedVisualPane.PlainText: string;
begin
  Result := {$IFDEF LED_PARADE}FEdit.DocumentText{$ELSE}''{$ENDIF};
end;

procedure TLedVisualPane.InsertText(const AText: string);
begin
  {$IFDEF LED_PARADE}FEdit.InsertText(AText);{$ENDIF}
end;

function TLedVisualPane.GetModified: Boolean;
begin
  Result := {$IFDEF LED_PARADE}FEdit.Modified{$ELSE}False{$ENDIF};
end;

procedure TLedVisualPane.MarkSaved;
begin
  {$IFDEF LED_PARADE}FEdit.Modified := False;{$ENDIF}
end;

function TLedVisualPane.CanUndo: Boolean;
begin
  Result := {$IFDEF LED_PARADE}pd_doc_can_undo(FEdit.Doc) <> 0{$ELSE}False{$ENDIF};
end;

function TLedVisualPane.CanRedo: Boolean;
begin
  Result := {$IFDEF LED_PARADE}pd_doc_can_redo(FEdit.Doc) <> 0{$ELSE}False{$ENDIF};
end;

function TLedVisualPane.SelAvail: Boolean;
begin
  {$IFDEF LED_PARADE}
  Result := (FEdit.CaretPos.block <> FEdit.AnchorPos.block) or
    (FEdit.CaretPos.offset <> FEdit.AnchorPos.offset);
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure TLedVisualPane.Undo;
begin
  {$IFDEF LED_PARADE}FEdit.Undo;{$ENDIF}
end;

procedure TLedVisualPane.Redo;
begin
  {$IFDEF LED_PARADE}FEdit.Redo;{$ENDIF}
end;

procedure TLedVisualPane.CutToClipboard;
begin
  {$IFDEF LED_PARADE}FEdit.CutToClipboard;{$ENDIF}
end;

procedure TLedVisualPane.CopyToClipboard;
begin
  {$IFDEF LED_PARADE}FEdit.CopyToClipboard;{$ENDIF}
end;

procedure TLedVisualPane.PasteFromClipboard;
begin
  {$IFDEF LED_PARADE}FEdit.PasteFromClipboard;{$ENDIF}
end;

procedure TLedVisualPane.SelectAll;
begin
  {$IFDEF LED_PARADE}FEdit.SelectAll;{$ENDIF}
end;

procedure TLedVisualPane.ToggleBold;
begin
  {$IFDEF LED_PARADE}FEdit.ToggleBold;{$ENDIF}
end;

procedure TLedVisualPane.ToggleItalic;
begin
  {$IFDEF LED_PARADE}FEdit.ToggleItalic;{$ENDIF}
end;

procedure TLedVisualPane.ToggleUnderline;
begin
  {$IFDEF LED_PARADE}FEdit.ToggleUnderline;{$ENDIF}
end;

procedure TLedVisualPane.StyleChosen(Sender: TObject);
begin
  {$IFDEF LED_PARADE}
  if FStyle.ItemIndex >= 0 then
    FEdit.SetParagraphStyle(FStyle.Items[FStyle.ItemIndex]);
  { Back to the page: the next key is meant for the text, not the list. }
  if FEdit.CanFocus then FEdit.SetFocus;
  {$ENDIF}
end;

procedure TLedVisualPane.BoldClicked(Sender: TObject);
begin
  ToggleBold;
end;

procedure TLedVisualPane.ItalicClicked(Sender: TObject);
begin
  ToggleItalic;
end;

procedure TLedVisualPane.UnderlineClicked(Sender: TObject);
begin
  ToggleUnderline;
end;

procedure TLedVisualPane.BackToPage;
begin
  {$IFDEF LED_PARADE}
  if FEdit.CanFocus then FEdit.SetFocus;
  {$ENDIF}
end;

procedure TLedVisualPane.TrackClicked(Sender: TObject);
begin
  {$IFDEF LED_PARADE}
  FEdit.TrackChanges := FTrack.Down;
  {$ENDIF}
  BackToPage;
end;

procedure TLedVisualPane.PrevClicked(Sender: TObject);
begin
  {$IFDEF LED_PARADE}
  FEdit.NextChange(-1);
  {$ENDIF}
  BackToPage;
end;

procedure TLedVisualPane.NextClicked(Sender: TObject);
begin
  {$IFDEF LED_PARADE}
  FEdit.NextChange(1);
  {$ENDIF}
  BackToPage;
end;

procedure TLedVisualPane.AcceptClicked(Sender: TObject);
begin
  {$IFDEF LED_PARADE}
  FEdit.AcceptChange;
  {$ENDIF}
  BackToPage;
end;

procedure TLedVisualPane.RejectClicked(Sender: TObject);
begin
  {$IFDEF LED_PARADE}
  FEdit.RejectChange;
  {$ENDIF}
  BackToPage;
end;

procedure TLedVisualPane.CommentClicked(Sender: TObject);
{$IFDEF LED_PARADE}
var
  S: string;
  Id: pd_comment_id;
{$ENDIF}
begin
  {$IFDEF LED_PARADE}
  S := '';
  if SelAvail then
    Id := 0
  else
    Id := FEdit.CommentAt(FEdit.CaretPos);
  if Id <> 0 then
  begin
    if InputQuery('Reply', 'Reply to the comment:', S) and (S <> '') then
      FEdit.ReplyToComment(Id, S);
  end
  else if InputQuery('Comment', 'Comment on the selection:', S) and (S <> '') then
    FEdit.AddComment(S);
  {$ENDIF}
  BackToPage;
end;

procedure TLedVisualPane.MarkupChosen(Sender: TObject);
begin
  {$IFDEF LED_PARADE}
  if FMarkup.ItemIndex >= 0 then
    FEdit.MarkupMode := FMarkup.ItemIndex;   { PD_MARKUP_* in the list's order }
  {$ENDIF}
  BackToPage;
end;

procedure TLedVisualPane.EditChanged(Sender: TObject);
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

function LedVisualClaimKey(AKey: Word; AShift: TShiftState;
  AControl: TWinControl): Boolean;
var
  Pane: TLedVisualPane;
begin
  Result := False;
  if (AControl = nil) or not (AControl.Parent is TLedVisualPane) then Exit;
  Pane := TLedVisualPane(AControl.Parent);
  if AControl <> Pane.Editor then Exit;
  if AShift * [ssCtrl, ssAlt, ssShift, ssMeta] <> [ssCtrl] then Exit;
  Result := True;
  case AKey of
    VK_B: Pane.ToggleBold;
    VK_I: Pane.ToggleItalic;
    VK_U: Pane.ToggleUnderline;
  else
    Result := False;
  end;
end;

initialization
  LedEditKeyClaim := @LedVisualClaimKey;

end.
