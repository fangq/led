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
  Dialogs, LCLType, Menus
  {$IFDEF LED_PARADE}, parade, paradeedit{$ENDIF}
  {$IFDEF LED_PARADE_SYNC}, paradesync, paraderelay{$ENDIF};

type
  TLedVisualKind = (lvkNone, lvkMarkdown, lvkHtml, lvkDocx);

  { The page view, a strip of buttons above it.  One per tab, made when the
    tab is first switched to it. }
  TLedVisualPane = class(TPanel)
  private
    FKind: TLedVisualKind;
    FTabStrip: TPanel;          { the tabs' names, one button each, and the sharing status }
    FBars: array of TFlowPanel; { a row of controls per tab; one shown }
    FBar: TFlowPanel;           { the one being filled while the constructor builds them }
    FStyle: TComboBox;
    FMarkup: TComboBox;
    FTrack: TSpeedButton;
    FOnChange: TNotifyEvent;
    {$IFDEF LED_PARADE}
    FEdit: TParadeEdit;
    {$ENDIF}
    {$IFDEF LED_PARADE_SYNC}
    FSync: TParadeSync;
    FRelay: TParadeRelay;       { the relay this LED runs when it hosts the document }
    FHostDoc, FHostAddress, FFileName: string;
    FShareBtn, FJoinBtn, FHostBtn: TSpeedButton;
    FSyncStatus: TLabel;
    procedure ShareClicked(Sender: TObject);
    procedure JoinClicked(Sender: TObject);
    procedure HostClicked(Sender: TObject);
    procedure ShowInvite;
    procedure InviteCopyClicked(Sender: TObject);
    procedure StopSharing;
    procedure SyncChanged(Sender: TObject);
    function AskConnection(const ACaption: string; var AServer, ADoc, AToken, AName: string): Boolean;
    {$ENDIF}
  private
    {$IFDEF LED_PARADE}
    { the Home tab }
    FFont, FSize: TComboBox;
    FBoldBtn, FItalicBtn, FUnderBtn, FStrikeBtn, FSupBtn, FSubBtn: TSpeedButton;
    FBulletBtn, FNumberBtn: TSpeedButton;
    FAlignBtns: array[0..3] of TSpeedButton;
    FColorMenu, FHighlightMenu, FSpacingMenu: TPopupMenu;
    FTextColor, FHighlightColor: Integer;   { $RRGGBB the colour buttons put on; -1: automatic / none }
    FStylesShown: Integer;      { the document's style count when the list was last filled }
    procedure BuildHome;
    procedure RefreshStyles;
    procedure SelectionChanged(Sender: TObject);
    procedure FontChosen(Sender: TObject);
    procedure SizeChosen(Sender: TObject);
    procedure ComboKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure GrowClicked(Sender: TObject);
    procedure ShrinkClicked(Sender: TObject);
    procedure StrikeClicked(Sender: TObject);
    procedure SupClicked(Sender: TObject);
    procedure SubClicked(Sender: TObject);
    procedure ColorClicked(Sender: TObject);
    procedure HighlightClicked(Sender: TObject);
    procedure ColorItemClicked(Sender: TObject);
    procedure HighlightItemClicked(Sender: TObject);
    procedure MenuDropClicked(Sender: TObject);
    procedure ClearClicked(Sender: TObject);
    procedure BulletsClicked(Sender: TObject);
    procedure NumberingClicked(Sender: TObject);
    procedure IndentLessClicked(Sender: TObject);
    procedure IndentMoreClicked(Sender: TObject);
    procedure AlignClicked(Sender: TObject);
    procedure LineSpacingItemClicked(Sender: TObject);
    procedure ParaSpaceItemClicked(Sender: TObject);
    {$ENDIF}
    function AddTab(const ACaption: string): TFlowPanel;
    procedure TabClicked(Sender: TObject);
    procedure AddSeparator;
    function AddIconButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TSpeedButton;
    function AddToggle(const ACaption, AHint: string; AStyle: TFontStyles; AOnClick: TNotifyEvent): TSpeedButton;
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
    { Asks for a relay, a document and a token, and puts the shared document
      in place of this one -- Join without the toolbar.  False when it was
      cancelled or could not join (the reason has been shown). }
    function JoinShared: Boolean;

    property Kind: TLedVisualKind read FKind;
    { Changed here since the last Load or MarkSaved. }
    property Modified: Boolean read GetModified;
    procedure MarkSaved;
    { The control that takes the focus and the keys.  nil without Parade. }
    property Editor: TWinControl read GetEditor;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    {$IFDEF LED_PARADE}
    { the page itself, for scripting and tests }
    property Page: TParadeEdit read FEdit;
    {$ENDIF}
    { the tab shown in the toolbar: 0 Home, 1 Review, 2 Share }
    procedure ShowTab(AIndex: Integer);
  end;

{ Whether this LED has the visual editor at all. }
function LedVisualAvailable: Boolean;

{ Whether this LED can share documents (Parade built with its yrs library). }
function LedVisualCanShare: Boolean;

{ An empty Word file, as Parade writes one: what a document joined starts as. }
function LedVisualEmptyDocx: string;

{ What the visual editor would open this file as, by its name. }
function LedVisualKindOf(const AFileName: string): TLedVisualKind;

{ The keys the visual editor takes before the window's shortcuts do: Ctrl+B
  is bold in a page and Toggle Bookmark everywhere else, and the window would
  otherwise always win -- see Led.UI.EditKeys. }
function LedVisualClaimKey(AKey: Word; AShift: TShiftState;
  AControl: TWinControl): Boolean;

implementation

uses
  Led.UI.EditKeys, Led.UI.Dpi, Led.UI.Icons
  {$IFDEF LED_PARADE_SYNC}, IniFiles, Clipbrd, Led.Core.Paths{$IFDEF UNIX}, BaseUnix, Unix{$ENDIF}{$ENDIF};

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

function LedVisualCanShare: Boolean;
begin
  Result := {$IFDEF LED_PARADE_SYNC}True{$ELSE}False{$ENDIF};
end;

function LedVisualEmptyDocx: string;
var
  P: TLedVisualPane;
begin
  P := TLedVisualPane.Create(nil);
  try
    Result := P.Export(lvkDocx);
  finally
    P.Free;
  end;
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

  { The toolbar: tabs, as a word processor's -- Home for the font and the
    paragraph, Review for tracked changes and comments, Share for editing
    together -- each a row of controls that wraps when the pane is narrow. }
  FTabStrip := TPanel.Create(Self);
  FTabStrip.Parent := Self;
  FTabStrip.Align := alTop;
  FTabStrip.BevelOuter := bvNone;
  FTabStrip.Caption := '';
  FTabStrip.AutoSize := True;
  FTabStrip.ChildSizing.LeftRightSpacing := LedScale96(4);
  FTabStrip.ChildSizing.TopBottomSpacing := LedScale96(1);
  FTabStrip.ChildSizing.HorizontalSpacing := LedScale96(2);
  FTabStrip.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  FTabStrip.ChildSizing.ControlsPerLine := 100;

  {$IFDEF LED_PARADE}
  FEdit := TParadeEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Align := alClient;
  AddFonts(FEdit);
  FEdit.OnChange := @EditChanged;
  FEdit.OnSelectionChange := @SelectionChanged;
  {$ENDIF}

  AddTab('Home');
  FStyle := TComboBox.Create(Self);
  FStyle.Style := csDropDownList;
  FStyle.Width := LedScale96(130);
  FStyle.Hint := 'Paragraph style';
  FStyle.ShowHint := True;
  for i := Low(StyleNames) to High(StyleNames) do
    FStyle.Items.Add(StyleNames[i]);
  FStyle.ItemIndex := 0;
  FStyle.OnSelect := @StyleChosen;
  {$IFDEF LED_PARADE}
  BuildHome;
  {$ELSE}
  FStyle.Parent := FBar;
  AddToggle('B', 'Bold (Ctrl+B)', [fsBold], @BoldClicked);
  AddToggle('I', 'Italic (Ctrl+I)', [fsItalic], @ItalicClicked);
  AddToggle('U', 'Underline (Ctrl+U)', [fsUnderline], @UnderlineClicked);
  {$ENDIF}

  { review: tracked changes and comments }
  AddTab('Review');
  FTrack := AddButton('Track changes', 'Record edits as tracked changes', [], @TrackClicked);
  FTrack.AllowAllUp := True;
  FTrack.GroupIndex := 1;
  AddSeparator;
  AddButton('< Previous', 'Previous change or comment', [], @PrevClicked);
  AddButton('Next >', 'Next change or comment', [], @NextClicked);
  AddButton('Accept', 'Accept the change (the selection''s changes)', [], @AcceptClicked);
  AddButton('Reject', 'Reject the change (the selection''s changes)', [], @RejectClicked);
  AddSeparator;
  AddIconButton('comment', 'Comment on the selection, or reply to the comment at the caret', @CommentClicked);
  AddSeparator;
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

  {$IFDEF LED_PARADE_SYNC}
  { a shared document: everyone editing it at once, through a relay }
  AddTab('Share');
  FShareBtn := AddButton('Share', 'Share this document through a relay, for others to edit with you', [], @ShareClicked);
  FJoinBtn := AddButton('Join', 'Open a shared document from a relay in place of this one', [], @JoinClicked);
  FHostBtn := AddButton('Host', 'Share this document through a relay LED runs itself, and invite others', [],
    @HostClicked);
  FSyncStatus := TLabel.Create(Self);
  FSyncStatus.Parent := FTabStrip;    { on the tabs' row: seen whichever tab is open }
  FSyncStatus.Caption := '';
  FSyncStatus.Layout := tlCenter;
  FSyncStatus.BorderSpacing.Left := LedScale96(12);
  FSync := TParadeSync.Create(Self, FEdit);
  FSync.OnStateChange := @SyncChanged;
  FSync.OutboxDir := IncludeTrailingPathDelimiter(LedConfigDir) + 'outbox';   { edits made offline outlive a quit }
  FRelay := TParadeRelay.Create(Self);
  {$ENDIF}
  ShowTab(0);
end;

function TLedVisualPane.AddTab(const ACaption: string): TFlowPanel;
var
  B: TSpeedButton;
begin
  B := TSpeedButton.Create(Self);
  B.Parent := FTabStrip;
  B.Caption := ACaption;
  B.Flat := True;
  B.GroupIndex := 50;           { one down at a time: the open tab }
  B.AllowAllUp := False;
  B.Tag := Length(FBars);
  B.Constraints.MinWidth := LedScale96(64);
  B.Height := LedScale96(22);
  B.OnClick := @TabClicked;
  Result := TFlowPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.Top := 1000 + Length(FBars);     { under the tabs, above the page }
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.AutoSize := True;
  Result.AutoWrap := True;
  Result.BorderSpacing.Left := LedScale96(4);
  Result.BorderSpacing.Bottom := LedScale96(2);
  Result.Visible := False;
  SetLength(FBars, Length(FBars) + 1);
  FBars[High(FBars)] := Result;
  FBar := Result;
end;

procedure TLedVisualPane.ShowTab(AIndex: Integer);
var
  i: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FBars)) then Exit;
  for i := 0 to High(FBars) do
    FBars[i].Visible := i = AIndex;
  for i := 0 to FTabStrip.ControlCount - 1 do
    if (FTabStrip.Controls[i] is TSpeedButton) and (FTabStrip.Controls[i].Tag = AIndex) then
      TSpeedButton(FTabStrip.Controls[i]).Down := True;
end;

procedure TLedVisualPane.TabClicked(Sender: TObject);
begin
  ShowTab(TSpeedButton(Sender).Tag);
  BackToPage;
end;

procedure TLedVisualPane.AddSeparator;
var
  B: TBevel;
begin
  B := TBevel.Create(Self);
  B.Parent := FBar;
  B.Shape := bsLeftLine;
  B.Width := LedScale96(6);
  B.Height := LedScale96(24);
  B.BorderSpacing.Left := LedScale96(4);
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
  { as wide as its caption needs, never narrower than an icon button }
  Result.AutoSize := ACaption <> '';
  Result.Constraints.MinWidth := LedScale96(26);
  Result.Width := LedScale96(26);
  Result.Height := LedScale96(26);
  Result.BorderSpacing.Around := LedScale96(1);
  Result.OnClick := AOnClick;
end;

function TLedVisualPane.AddIconButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TSpeedButton;
begin
  Result := AddButton('', AHint, [], AOnClick);
  Result.Width := LedScale96(26);
  Result.Glyph := LedIconBitmap(AIcon, clBtnText, LedScale96(16));
end;

var
  ToggleGroups: Integer = 100;

function TLedVisualPane.AddToggle(const ACaption, AHint: string; AStyle: TFontStyles;
  AOnClick: TNotifyEvent): TSpeedButton;
begin
  Result := AddButton(ACaption, AHint, AStyle, AOnClick);
  { a group of its own: down and up again on its own, showing the state at the caret }
  Inc(ToggleGroups);
  Result.GroupIndex := ToggleGroups;
  Result.AllowAllUp := True;
end;

{$IFDEF LED_PARADE}
{ $RRGGBB, as Parade has colours, from an LCL colour }
function ToRGB(C: TColor): Integer;
begin
  C := ColorToRGB(C);
  Result := (Red(C) shl 16) or (Green(C) shl 8) or Blue(C);
end;

function FromRGB(V: Integer): TColor;
begin
  Result := RGBToColor((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
end;

{ a colour's swatch, for a menu item }
procedure Swatch(AItem: TMenuItem; AColour: TColor; ANone: Boolean);
var
  S: Integer;
begin
  S := LedScale96(14);
  AItem.Bitmap.SetSize(S, S);
  with AItem.Bitmap.Canvas do
  begin
    Brush.Color := clWhite;
    FillRect(0, 0, S, S);
    if not ANone then
    begin
      Brush.Color := AColour;
      FillRect(1, 1, S - 1, S - 1);
    end
    else
    begin
      Pen.Color := clRed;
      Line(1, S - 1, S - 1, 1);
    end;
    Brush.Style := bsClear;
    Pen.Color := clGray;
    Rectangle(0, 0, S, S);
  end;
end;

procedure TLedVisualPane.BuildHome;
const
  TextColours: array[0..9] of Integer = ($000000, $7F7F7F, $C00000, $FF0000, $FFC000, $FFFF00, $00B050,
    $00B0F0, $0070C0, $7030A0);
  TextColourNames: array[0..9] of string = ('Black', 'Grey', 'Dark red', 'Red', 'Orange', 'Yellow', 'Green',
    'Light blue', 'Blue', 'Purple');
  Highlights: array[0..6] of Integer = ($FFFF00, $00FF00, $00FFFF, $FF00FF, $C0C0C0, $FFC000, $9DC3E6);
  HighlightNames: array[0..6] of string = ('Yellow', 'Bright green', 'Turquoise', 'Pink', 'Grey', 'Orange',
    'Light blue');
  Spacings: array[0..5] of Integer = (1000, 1150, 1500, 2000, 2500, 3000);
  AlignIcons: array[0..3] of string = ('alignleft', 'aligncenter', 'alignright', 'alignjustify');
  AlignHints: array[0..3] of string = ('Align left', 'Centre', 'Align right', 'Justify');
  AlignValues: array[0..3] of Integer = (PD_ALIGN_LEFT, PD_ALIGN_CENTER, PD_ALIGN_RIGHT, PD_ALIGN_JUSTIFY);
  Sizes: array[0..15] of string = ('8', '9', '10', '10.5', '11', '12', '14', '16', '18', '20', '24', '28', '36',
    '48', '72', '96');
var
  i: Integer;
  M: TMenuItem;
  B: TSpeedButton;

  function Item(AMenu: TPopupMenu; const ACaption: string; ATag: Integer; AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(AMenu);
    Result.Caption := ACaption;
    Result.Tag := ATag;
    Result.OnClick := AClick;
    AMenu.Items.Add(Result);
  end;

  procedure Line(AMenu: TPopupMenu);
  begin
    Item(AMenu, '-', 0, nil);
  end;

  { the narrow arrow beside a button that opens its menu }
  procedure Drop(AMenu: TPopupMenu; const AHint: string);
  begin
    B := AddButton(#$E2#$96#$BE, AHint, [], @MenuDropClicked);    { a small down triangle }
    B.Width := LedScale96(14);
    B.Tag := PtrInt(AMenu);
    B.BorderSpacing.Left := 0;
  end;

begin
  FTextColor := $C00000;
  FHighlightColor := $FFFF00;

  { the font }
  FFont := TComboBox.Create(Self);
  FFont.Parent := FBar;
  FFont.Style := csDropDown;      { a family the list does not have can still be typed }
  FFont.Width := LedScale96(170);
  FFont.Hint := 'Font';
  FFont.ShowHint := True;
  FFont.DropDownCount := 20;
  FEdit.GetFontFamilies(FFont.Items);
  FFont.OnSelect := @FontChosen;
  FFont.OnKeyDown := @ComboKeyDown;
  FFont.BorderSpacing.Around := LedScale96(1);
  FSize := TComboBox.Create(Self);
  FSize.Parent := FBar;
  FSize.Style := csDropDown;
  FSize.Width := LedScale96(58);
  FSize.Hint := 'Font size';
  FSize.ShowHint := True;
  FSize.DropDownCount := 16;
  for i := 0 to High(Sizes) do
    FSize.Items.Add(Sizes[i]);
  FSize.OnSelect := @SizeChosen;
  FSize.OnKeyDown := @ComboKeyDown;
  FSize.BorderSpacing.Around := LedScale96(1);
  AddIconButton('fontgrow', 'Bigger (Ctrl+])', @GrowClicked);
  AddIconButton('fontshrink', 'Smaller (Ctrl+[)', @ShrinkClicked);
  AddSeparator;
  FBoldBtn := AddToggle('B', 'Bold (Ctrl+B)', [fsBold], @BoldClicked);
  FItalicBtn := AddToggle('I', 'Italic (Ctrl+I)', [fsItalic], @ItalicClicked);
  FUnderBtn := AddToggle('U', 'Underline (Ctrl+U)', [fsUnderline], @UnderlineClicked);
  FStrikeBtn := AddToggle('S', 'Strikethrough', [fsStrikeOut], @StrikeClicked);
  FSupBtn := AddToggle('x' + #$C2#$B2, 'Superscript', [], @SupClicked);
  FSubBtn := AddToggle('x' + #$E2#$82#$82, 'Subscript', [], @SubClicked);
  AddSeparator;

  { colours: the button puts on the last one chosen, the arrow chooses another }
  FColorMenu := TPopupMenu.Create(Self);
  M := Item(FColorMenu, 'Automatic', -1, @ColorItemClicked);
  Swatch(M, clBlack, False);
  Line(FColorMenu);
  for i := 0 to High(TextColours) do
    Swatch(Item(FColorMenu, TextColourNames[i], TextColours[i], @ColorItemClicked), FromRGB(TextColours[i]), False);
  Line(FColorMenu);
  Item(FColorMenu, 'More colours...', -2, @ColorItemClicked);
  AddIconButton('textcolor', 'Font colour', @ColorClicked);
  Drop(FColorMenu, 'Choose the font colour');
  FHighlightMenu := TPopupMenu.Create(Self);
  for i := 0 to High(Highlights) do
    Swatch(Item(FHighlightMenu, HighlightNames[i], Highlights[i], @HighlightItemClicked), FromRGB(Highlights[i]),
      False);
  Line(FHighlightMenu);
  Swatch(Item(FHighlightMenu, 'No highlight', -1, @HighlightItemClicked), clWhite, True);
  AddIconButton('highlight', 'Highlight', @HighlightClicked);
  Drop(FHighlightMenu, 'Choose the highlight colour');
  AddIconButton('clearformat', 'Clear formatting (the selection''s own; its style stays)', @ClearClicked);
  AddSeparator;

  { the paragraph }
  FBulletBtn := AddIconButton('bullets', 'Bullets', @BulletsClicked);
  FBulletBtn.GroupIndex := 60;
  FBulletBtn.AllowAllUp := True;
  FNumberBtn := AddIconButton('numbering', 'Numbering', @NumberingClicked);
  FNumberBtn.GroupIndex := 61;
  FNumberBtn.AllowAllUp := True;
  AddIconButton('unindent', 'Decrease indent (in a list: a level up)', @IndentLessClicked);
  AddIconButton('indent', 'Increase indent (in a list: a level down)', @IndentMoreClicked);
  AddSeparator;
  for i := 0 to 3 do
  begin
    FAlignBtns[i] := AddIconButton(AlignIcons[i], AlignHints[i], @AlignClicked);
    FAlignBtns[i].GroupIndex := 62;     { one of the four }
    FAlignBtns[i].Tag := AlignValues[i];
  end;
  FSpacingMenu := TPopupMenu.Create(Self);
  for i := 0 to High(Spacings) do
    Item(FSpacingMenu, FormatFloat('0.0#', Spacings[i] / 1000), Spacings[i], @LineSpacingItemClicked)
      .RadioItem := True;
  Line(FSpacingMenu);
  Item(FSpacingMenu, 'No space before', 0, @ParaSpaceItemClicked);
  Item(FSpacingMenu, '6 pt before', 6, @ParaSpaceItemClicked);
  Item(FSpacingMenu, '12 pt before', 12, @ParaSpaceItemClicked);
  Line(FSpacingMenu);
  Item(FSpacingMenu, 'No space after', 1000, @ParaSpaceItemClicked);
  Item(FSpacingMenu, '6 pt after', 1006, @ParaSpaceItemClicked);
  Item(FSpacingMenu, '12 pt after', 1012, @ParaSpaceItemClicked);
  B := AddIconButton('linespacing', 'Line and paragraph spacing', @MenuDropClicked);
  B.Tag := PtrInt(FSpacingMenu);
  AddSeparator;

  { the paragraph's style }
  FStyle.Parent := FBar;
  FStyle.BorderSpacing.Around := LedScale96(1);
end;

procedure TLedVisualPane.RefreshStyles;
var
  L: TStringList;
  i, k: Integer;
begin
  L := TStringList.Create;
  try
    FEdit.GetParagraphStyles(L);
    if L.Count = FStylesShown then Exit;
    FStylesShown := L.Count;
    FStyle.Items.BeginUpdate;
    try
      FStyle.Items.Clear;
      { the usual ones first, in the order a reader looks for them, then the document's own }
      for i := Low(StyleNames) to High(StyleNames) do
      begin
        k := L.IndexOf(StyleNames[i]);
        if k >= 0 then
        begin
          FStyle.Items.Add(StyleNames[i]);
          L.Delete(k);
        end;
      end;
      L.Sort;
      FStyle.Items.AddStrings(L);
    finally
      FStyle.Items.EndUpdate;
    end;
  finally
    L.Free;
  end;
end;

{ the controls show what is at the caret: its font, its paragraph's alignment and list, its style }
procedure TLedVisualPane.SelectionChanged(Sender: TObject);
var
  P: pd_char_props;
  Pp: pd_para_props;
  i, L: Integer;
begin
  if FFont = nil then Exit;
  P := FEdit.CurrentCharProps;
  if not FFont.Focused then
    FFont.Text := P.family;
  if not FSize.Focused then
    FSize.Text := FormatFloat('0.#', P.size / PD_SP_PER_PT);
  FBoldBtn.Down := P.weight >= 600;
  FItalicBtn.Down := P.italic <> 0;
  FUnderBtn.Down := P.underline <> 0;
  FStrikeBtn.Down := P.strike <> 0;
  FSupBtn.Down := P.shift = PD_SHIFT_SUPER;
  FSubBtn.Down := P.shift = PD_SHIFT_SUB;
  Pp := FEdit.CurrentParaProps;
  for i := 0 to 3 do
    if FAlignBtns[i].Tag = Pp.align then
      FAlignBtns[i].Down := True;
  for i := 0 to FSpacingMenu.Items.Count - 1 do
    if FSpacingMenu.Items[i].RadioItem then
      FSpacingMenu.Items[i].Checked := FSpacingMenu.Items[i].Tag = Pp.line_spacing;
  L := FEdit.CurrentListFormat;
  FBulletBtn.Down := L = PD_NUM_BULLET;
  FNumberBtn.Down := (L >= 0) and (L <> PD_NUM_BULLET);
  RefreshStyles;
  if not FStyle.DroppedDown then
    FStyle.ItemIndex := FStyle.Items.IndexOf(FEdit.CurrentStyleName);
end;

procedure TLedVisualPane.FontChosen(Sender: TObject);
begin
  if FFont.ItemIndex >= 0 then
    FEdit.SetFontFamily(FFont.Items[FFont.ItemIndex])
  else
    FEdit.SetFontFamily(Trim(FFont.Text));
  BackToPage;
end;

procedure TLedVisualPane.SizeChosen(Sender: TObject);
var
  S: string;
  V: Double;
begin
  if FSize.ItemIndex >= 0 then
    S := FSize.Items[FSize.ItemIndex]
  else
    S := Trim(FSize.Text);
  if TryStrToFloat(StringReplace(S, ',', '.', []), V, DefaultFormatSettings) or TryStrToFloat(S, V) then
    FEdit.SetFontSize(V);
  BackToPage;
end;

{ Enter in the font or size box puts it on; Escape goes back to the page as it was }
procedure TLedVisualPane.ComboKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    TComboBox(Sender).ItemIndex := TComboBox(Sender).Items.IndexOf(TComboBox(Sender).Text);
    if Sender = FFont then FontChosen(Sender) else SizeChosen(Sender);
  end
  else if Key = VK_ESCAPE then
  begin
    Key := 0;
    BackToPage;
    SelectionChanged(nil);
  end;
end;

procedure TLedVisualPane.GrowClicked(Sender: TObject);
begin
  FEdit.StepFontSize(True);
  BackToPage;
end;

procedure TLedVisualPane.ShrinkClicked(Sender: TObject);
begin
  FEdit.StepFontSize(False);
  BackToPage;
end;

procedure TLedVisualPane.StrikeClicked(Sender: TObject);
begin
  FEdit.ToggleStrike;
  BackToPage;
end;

procedure TLedVisualPane.SupClicked(Sender: TObject);
begin
  FEdit.ToggleSuperscript;
  BackToPage;
end;

procedure TLedVisualPane.SubClicked(Sender: TObject);
begin
  FEdit.ToggleSubscript;
  BackToPage;
end;

procedure TLedVisualPane.ColorClicked(Sender: TObject);
begin
  FEdit.SetTextColor(FTextColor);
  BackToPage;
end;

procedure TLedVisualPane.HighlightClicked(Sender: TObject);
begin
  FEdit.SetHighlight(FHighlightColor);
  BackToPage;
end;

procedure TLedVisualPane.ColorItemClicked(Sender: TObject);
var
  D: TColorDialog;
begin
  if TMenuItem(Sender).Tag = -2 then
  begin   { more colours }
    D := TColorDialog.Create(nil);
    try
      if FTextColor >= 0 then
        D.Color := FromRGB(FTextColor);
      if not D.Execute then
      begin
        BackToPage;
        Exit;
      end;
      FTextColor := ToRGB(D.Color);
    finally
      D.Free;
    end;
  end
  else
    FTextColor := TMenuItem(Sender).Tag;
  ColorClicked(Sender);
end;

procedure TLedVisualPane.HighlightItemClicked(Sender: TObject);
begin
  FHighlightColor := TMenuItem(Sender).Tag;
  HighlightClicked(Sender);
end;

procedure TLedVisualPane.MenuDropClicked(Sender: TObject);
var
  P: TPoint;
begin
  P := TControl(Sender).ClientToScreen(Point(0, TControl(Sender).Height));
  TPopupMenu(TComponent(TControl(Sender).Tag)).PopUp(P.X, P.Y);
end;

procedure TLedVisualPane.ClearClicked(Sender: TObject);
begin
  FEdit.ClearFormatting;
  BackToPage;
end;

procedure TLedVisualPane.BulletsClicked(Sender: TObject);
begin
  FEdit.ToggleList(PD_NUM_BULLET);
  BackToPage;
end;

procedure TLedVisualPane.NumberingClicked(Sender: TObject);
begin
  FEdit.ToggleList(PD_NUM_DECIMAL);
  BackToPage;
end;

procedure TLedVisualPane.IndentLessClicked(Sender: TObject);
begin
  FEdit.ChangeIndent(False);
  BackToPage;
end;

procedure TLedVisualPane.IndentMoreClicked(Sender: TObject);
begin
  FEdit.ChangeIndent(True);
  BackToPage;
end;

procedure TLedVisualPane.AlignClicked(Sender: TObject);
begin
  FEdit.SetAlignment(TSpeedButton(Sender).Tag);
  BackToPage;
end;

procedure TLedVisualPane.LineSpacingItemClicked(Sender: TObject);
begin
  FEdit.SetLineSpacing(TMenuItem(Sender).Tag);
  BackToPage;
end;

procedure TLedVisualPane.ParaSpaceItemClicked(Sender: TObject);
var
  T: Integer;
begin
  T := TMenuItem(Sender).Tag;
  if T >= 1000 then
    FEdit.SetParaSpacing(-1, T - 1000)
  else
    FEdit.SetParaSpacing(T, -1);
  BackToPage;
end;
{$ENDIF}


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
      {$IFDEF LED_PARADE_SYNC}
      FFileName := AFileName;   { a name to host it under }
      {$ENDIF}
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

{$IFDEF LED_PARADE_SYNC}
function CollabIni: TIniFile;
begin
  ForceDirectories(LedConfigDir);
  Result := TIniFile.Create(IncludeTrailingPathDelimiter(LedConfigDir) + 'collab.ini');
end;

function TLedVisualPane.AskConnection(const ACaption: string; var AServer, ADoc, AToken, AName: string): Boolean;
var
  V: array of string;
  Ini: TIniFile;
begin
  Ini := CollabIni;
  try
    SetLength(V, 4);
    V[0] := Ini.ReadString('relay', 'server', 'http://127.0.0.1:8765');
    V[1] := ADoc;
    V[2] := Ini.ReadString('relay', 'token', '');
    V[3] := Ini.ReadString('relay', 'name', GetEnvironmentVariable('USER'));
    Result := InputQuery(ACaption, ['Relay address', 'Document', 'Token (from the host''s Invite, or parade_relay token)', 'Your name'], V) and
      (Trim(V[0]) <> '') and (Trim(V[1]) <> '');
    if not Result then
      Exit;
    AServer := Trim(V[0]);
    ADoc := Trim(V[1]);
    AToken := Trim(V[2]);
    AName := Trim(V[3]);
    Ini.WriteString('relay', 'server', AServer);
    Ini.WriteString('relay', 'token', AToken);
    Ini.WriteString('relay', 'name', AName);
  finally
    Ini.Free;
  end;
end;

procedure TLedVisualPane.StopSharing;
begin
  FSync.Stop;
  if FRelay.Active then
    FRelay.Stop;    { hosting ends with it: the others are told they are offline }
  FHostDoc := '';
  SyncChanged(nil);
end;

procedure TLedVisualPane.ShareClicked(Sender: TObject);
var
  Server, Doc, Token, Who: string;
begin
  if FSync.State <> pssOff then
  begin   { Share is Leave while shared }
    StopSharing;
    BackToPage;
    Exit;
  end;
  Doc := '';
  if not AskConnection('Share this document', Server, Doc, Token, Who) then
    Exit;
  if not FSync.Start(Server, Doc, Token, Who, True) then
    MessageDlg('Share', 'Could not share: ' + FSync.LastError, mtError, [mbOK], 0);
  BackToPage;
end;

procedure TLedVisualPane.JoinClicked(Sender: TObject);
begin
  if (FEdit.Modified or (Trim(FEdit.DocumentText) <> '')) and
     (MessageDlg('Join', 'The shared document replaces what this tab shows. Go on?', mtConfirmation,
      [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  JoinShared;
end;
{$ENDIF}

function TLedVisualPane.JoinShared: Boolean;
{$IFDEF LED_PARADE_SYNC}
var
  Server, Doc, Token, Who: string;
  V: array of string;
  Ini: TIniFile;
begin
  Result := False;
  { the invitation link the host sent (Host > Invite): relay, document and token in one }
  Ini := CollabIni;
  try
    SetLength(V, 2);
    V[0] := '';
    V[1] := Ini.ReadString('relay', 'name', GetEnvironmentVariable('USER'));
    if not InputQuery('Join a shared document', ['Invitation link (blank: enter the relay, document and token)',
      'Your name'], V) then
      Exit;
    Who := Trim(V[1]);
    Ini.WriteString('relay', 'name', Who);
  finally
    Ini.Free;
  end;
  if Trim(V[0]) = '' then
  begin
    Doc := '';
    if not AskConnection('Join a shared document', Server, Doc, Token, Who) then
      Exit;
  end
  else if not ParadeParseInvite(V[0], Server, Doc, Token) then
  begin
    MessageDlg('Join', 'That is not an invitation link: it looks like http://host:8765/d/document#t=... ' +
      '(ask the host for Host > Invite).', mtError, [mbOK], 0);
    Exit;
  end;
  Result := FSync.Start(Server, Doc, Token, Who, False);
  if not Result then
    MessageDlg('Join', 'Could not join: ' + FSync.LastError, mtError, [mbOK], 0);
  BackToPage;
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

{$IFDEF LED_PARADE_SYNC}

{ the key this LED's relay signs its tokens with, made on first use and kept with the settings }
function RelaySecret: RawByteString;
var
  F: string;
begin
  F := IncludeTrailingPathDelimiter(LedConfigDir) + 'relay.secret';
  if not FileExists(F) then
  begin
    ForceDirectories(LedConfigDir);
    with TStringList.Create do
    try
      Text := ParadeNewSecret;
      SaveToFile(F);
    finally
      Free;
    end;
    {$IFDEF UNIX}
    FpChmod(F, &600);
    {$ENDIF}
  end;
  Result := ParadeReadSecret(F);
end;

function ThisHostName: string;
begin
  {$IFDEF UNIX}
  Result := GetHostName;
  {$ELSE}
  Result := GetEnvironmentVariable('COMPUTERNAME');
  {$ENDIF}
  if Result = '' then
    Result := 'localhost';
end;

procedure TLedVisualPane.HostClicked(Sender: TObject);
var
  V: array of string;
  Ini: TIniFile;
  Doc, Who: string;
  Port: Integer;
  Everyone: Boolean;
begin
  if FRelay.Active then
  begin   { Host is Invite while hosting }
    ShowInvite;
    Exit;
  end;
  if FSync.State <> pssOff then
  begin
    MessageDlg('Host', 'This document is shared already: Leave first.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Ini := CollabIni;
  try
    SetLength(V, 4);
    V[0] := ChangeFileExt(ExtractFileName(FFileName), '');
    if V[0] = '' then
      V[0] := Ini.ReadString('host', 'document', 'document');
    V[1] := Ini.ReadString('relay', 'name', GetEnvironmentVariable('USER'));
    V[2] := IntToStr(Ini.ReadInteger('host', 'port', 8765));
    V[3] := Ini.ReadString('host', 'network', 'yes');
    if not InputQuery('Host this document',
      ['Document name', 'Your name', 'Port', 'Let other machines in (yes / no: this machine only)'], V) or
      (Trim(V[0]) = '') then
      Exit;
    Doc := Trim(V[0]);
    Who := Trim(V[1]);
    Port := StrToIntDef(Trim(V[2]), 8765);
    Everyone := not SameText(Trim(V[3]), 'no');
    Ini.WriteString('host', 'document', Doc);
    Ini.WriteString('relay', 'name', Who);
    Ini.WriteInteger('host', 'port', Port);
    Ini.WriteString('host', 'network', BoolToStr(Everyone, 'yes', 'no'));
  finally
    Ini.Free;
  end;
  try
    FRelay.Secret := RelaySecret;
  except
    on E: Exception do
    begin
      MessageDlg('Host', 'No signing key: ' + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  FRelay.DbFile := IncludeTrailingPathDelimiter(LedConfigDir) + 'relay.sqlite';
  FRelay.Port := Port;
  if Everyone then
    FRelay.Host := '0.0.0.0'
  else
    FRelay.Host := '127.0.0.1';
  if not FRelay.Start then
  begin
    MessageDlg('Host', 'The relay did not start: ' + FRelay.LastError, mtError, [mbOK], 0);
    Exit;
  end;
  if not FSync.Start(Format('http://127.0.0.1:%d', [Port]), Doc, ParadeMakeToken(FRelay.Secret, Who, Doc, 'editor', 3650),
    Who, True) then
  begin
    { hosted here before: its log is still here, and it is what the others have }
    if (FRelay.Store.Last(Doc) > 0) and (MessageDlg('Host', Format('"%s" was hosted here before. Open it as the others ' +
      'left it, in place of this tab''s text?', [Doc]), mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
    begin
      if not FSync.Start(Format('http://127.0.0.1:%d', [Port]), Doc,
        ParadeMakeToken(FRelay.Secret, Who, Doc, 'editor', 3650), Who, False) then
      begin
        MessageDlg('Host', 'Could not open it: ' + FSync.LastError, mtError, [mbOK], 0);
        FRelay.Stop;
        Exit;
      end;
    end
    else
    begin
      if FRelay.Store.Last(Doc) = 0 then
        MessageDlg('Host', 'Could not share: ' + FSync.LastError, mtError, [mbOK], 0);
      FRelay.Stop;
      Exit;
    end;
  end;
  FHostDoc := Doc;
  if Everyone then
    FHostAddress := Format('http://%s:%d', [ThisHostName, Port])
  else
    FHostAddress := Format('http://127.0.0.1:%d', [Port]);
  SyncChanged(nil);
  ShowInvite;
  BackToPage;
end;

{ what the others need to join: a link for each role, which carries the relay, the document and a token }
procedure TLedVisualPane.ShowInvite;
var
  F: TForm;
  M: TMemo;
  B: TButton;
  Edit, Read: string;

  procedure CopyButton(const ACaption, AText: string);
  var
    C: TButton;
  begin
    C := TButton.Create(F);
    C.Parent := F;
    C.Align := alBottom;
    C.Caption := ACaption;
    C.Hint := AText;
    C.OnClick := @InviteCopyClicked;
  end;

begin
  Edit := ParadeInviteLink(FHostAddress, FHostDoc, ParadeMakeToken(FRelay.Secret, 'guest', FHostDoc, 'editor', 30));
  Read := ParadeInviteLink(FHostAddress, FHostDoc, ParadeMakeToken(FRelay.Secret, 'reader', FHostDoc, 'viewer', 30));
  F := TForm.CreateNew(nil);
  try
    F.Caption := 'Invite to "' + FHostDoc + '"';
    F.Position := poMainFormCenter;
    F.SetBounds(0, 0, 720, 360);
    M := TMemo.Create(F);
    M.Parent := F;
    M.Align := alClient;
    M.ReadOnly := True;
    M.WordWrap := True;
    M.ScrollBars := ssAutoVertical;
    M.Lines.Add('Send a link to whoever is to join: in their LED, File > Join Shared Document, and paste it. ' +
      'Each is good for 30 days; whoever has one can get in, so send it privately.');
    M.Lines.Add('');
    M.Lines.Add('To edit:');
    M.Lines.Add(Edit);
    M.Lines.Add('');
    M.Lines.Add('To read only:');
    M.Lines.Add(Read);
    M.Lines.Add('');
    M.Lines.Add('The document stays reachable while this LED shares it (until Leave).');
    CopyButton('Copy the link to read', Read);
    CopyButton('Copy the link to edit', Edit);
    B := TButton.Create(F);
    B.Parent := F;
    B.Align := alBottom;
    B.Caption := 'OK';
    B.ModalResult := mrOK;
    B.Default := True;
    F.ShowModal;
  finally
    F.Free;
  end;
end;

procedure TLedVisualPane.InviteCopyClicked(Sender: TObject);
begin
  Clipboard.AsText := TButton(Sender).Hint;
  TButton(Sender).Caption := 'Copied';
end;

procedure TLedVisualPane.SyncChanged(Sender: TObject);
var
  S: string;
begin
  if FSync.State = pssOff then
  begin
    if FRelay.Active then
      FRelay.Stop;    { the shared document went (another one opened in the tab): hosting ends }
    FSyncStatus.Caption := '';
    FShareBtn.Caption := 'Share';
    FHostBtn.Caption := 'Host';
    FJoinBtn.Enabled := True;
    FHostBtn.Enabled := True;
    Exit;
  end;
  if FRelay.Active then
  begin
    FHostBtn.Caption := 'Invite';
    FHostBtn.Enabled := True;
  end
  else
    FHostBtn.Enabled := False;
  S := 'shared: ' + ParadeSyncStateName(FSync.State);
  if FRelay.Active then
    S := 'hosting ' + FHostAddress + ', ' + ParadeSyncStateName(FSync.State);
  if FSync.PeerCount > 0 then
    S := S + Format(', %d other(s) here', [FSync.PeerCount]);
  if FEdit.ReadOnly then
    S := S + ' (read only)';
  FSyncStatus.Caption := S;
  FShareBtn.Caption := 'Leave';
  FJoinBtn.Enabled := False;
end;
{$ENDIF}

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
    {$IFDEF LED_PARADE}
    VK_OEM_6: Pane.Page.StepFontSize(True);     { Ctrl+] and Ctrl+[, as word processors have them }
    VK_OEM_4: Pane.Page.StepFontSize(False);
    {$ENDIF}
  else
    Result := False;
  end;
end;

initialization
  LedEditKeyClaim := @LedVisualClaimKey;

end.
