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
  Dialogs, LCLType, Menus, Spin
  {$IFDEF LED_PARADE}, parade, paradeedit{$ENDIF}
  {$IFDEF LED_PARADE_SYNC}, paradesync, paraderelay, Led.UI.Collab{$ENDIF};

type
  { lvkPdoc: Parade's own document, BJData (binary); lvkJdoc: the same as JSON text }
  TLedVisualKind = (lvkNone, lvkMarkdown, lvkHtml, lvkDocx, lvkPdoc, lvkJdoc);

  { The page view, a strip of buttons above it.  One per tab, made when the
    tab is first switched to it. }
  TLedVisualPane = class(TPanel)
  private
    FKind: TLedVisualKind;
    FTabStrip: TPanel;          { the tabs' names, one button each, and the sharing status }
    FBars: array of TFlowPanel; { a row of controls per tab; one shown }
    FBarHost: TPanel;           { holds the bars: as tall as the tallest one, so a tab switch moves nothing }
    FBarWidth: Integer;         { the width the host's height was found at }
    FBar: TWinControl;          { what the constructor is filling: a tab's bar, or a row of a group in it }
    FBarSave: TWinControl;      { the bar a two-row group is in }
    FGroup: TPanel;             { the two-row group being filled }
    FTabBtns: array of TSpeedButton;
    FTableTab: Integer;         { the Table tab's index, shown only while the caret is in a table (-1: none) }
    FShapeTab: Integer;         { the Insert tab's, which has the shapes' section (-1: none) }
    FShapeFmt: array of TControl;   { that section's controls for a selected shape: enabled while there is one }
    FShapeSel: Boolean;         { a drawing or a shape of it selected, when the selection last changed }
    FShapePop: TForm;           { the shapes' palette, made when first opened }
    FStyle: TComboBox;
    FMarkup: TComboBox;
    FTrack: TSpeedButton;
    FOnChange: TNotifyEvent;
    FOnStatus: TNotifyEvent;
    {$IFDEF LED_PARADE}
    FEdit: TParadeEdit;
    {$ENDIF}
    {$IFDEF LED_PARADE_SYNC}
    FSync: TParadeSync;
    FCollab: TLedCollab;        { sharing, hosting, inviting: the same for a page as for a text }
    FFileName: string;
    FSyncStatus: TLabel;
    procedure SyncChanged(Sender: TObject);
    function DocName: string;
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
    FGallery: TCustomControl;   { the style panel: the styles drawn as they look, to click }
    FPainterBtn: TSpeedButton;
    procedure PainterClicked(Sender: TObject);
    procedure PainterDblClicked(Sender: TObject);
    procedure GalleryPicked(Sender: TObject);
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
    { the Insert tab }
    procedure BuildInsert;
    procedure TableItemClicked(Sender: TObject);
    procedure PictureClicked(Sender: TObject);
    procedure LinkClicked(Sender: TObject);
    procedure BreakItemClicked(Sender: TObject);
    procedure EquationItemClicked(Sender: TObject);
    procedure NoteItemClicked(Sender: TObject);
    procedure FieldItemClicked(Sender: TObject);
    procedure FormItemClicked(Sender: TObject);
    procedure SymbolItemClicked(Sender: TObject);
    {$ENDIF}
  private
    {$IFDEF LED_PARADE}
    { the Layout and Table tabs }
    FPortraitItem, FLandscapeItem: TMenuItem;
    FIndentLeft, FIndentRight, FSpaceBefore, FSpaceAfter: TFloatSpinEdit;
    FHeaderRowBtn: TSpeedButton;
    FUpdating: Boolean;
    function MenuItem(AMenu: TPopupMenu; const ACaption: string; ATag: Integer; AClick: TNotifyEvent): TMenuItem;
    { a button opening AMenu: big (a picture over its name) or small (one beside it, for a two-row group) }
    function MenuButton(const AIcon, ACaption, AHint: string; AMenu: TPopupMenu; ABig: Boolean = True): TSpeedButton;
    function NumberBox(const ACaption, AHint: string; AMax, AStep: Double; ADecimals: Integer): TFloatSpinEdit;
    procedure BuildLayout;
    procedure MarginsItemClicked(Sender: TObject);
    procedure OrientationItemClicked(Sender: TObject);
    procedure SizeItemClicked(Sender: TObject);
    procedure ColumnsItemClicked(Sender: TObject);
    procedure LayoutBreakItemClicked(Sender: TObject);
    procedure EditHeaderFooter(AFooter: Boolean);
    procedure HeaderClicked(Sender: TObject);
    procedure FooterClicked(Sender: TObject);
    procedure PageNumberItemClicked(Sender: TObject);
    procedure LineNumberItemClicked(Sender: TObject);
    procedure ParaBoxChanged(Sender: TObject);
    procedure BuildTable;
    procedure BuildShape;
    procedure ShapesDropClicked(Sender: TObject);
    procedure PaletteItemClicked(Sender: TObject);
    procedure PaletteDeactivate(Sender: TObject);
    procedure CanvasClicked(Sender: TObject);
    procedure ShapeFillItemClicked(Sender: TObject);
    procedure ShapeRotateItemClicked(Sender: TObject);
    procedure ShapeThemeItemClicked(Sender: TObject);
    procedure EditPointsClicked(Sender: TObject);
    procedure AddTextClicked(Sender: TObject);
    procedure ShapeAlignItemClicked(Sender: TObject);
    procedure ShapeLineStyleItemClicked(Sender: TObject);
    function PickColour(var AColour: TColor): Boolean;
    procedure ShapeLineItemClicked(Sender: TObject);
    procedure ShapeOrderItemClicked(Sender: TObject);
    procedure GroupClicked(Sender: TObject);
    procedure UngroupClicked(Sender: TObject);
    procedure TableInsertItemClicked(Sender: TObject);
    procedure TableDeleteItemClicked(Sender: TObject);
    procedure TableMergeItemClicked(Sender: TObject);
    procedure ShadingItemClicked(Sender: TObject);
    procedure BordersItemClicked(Sender: TObject);
    procedure HeaderRowClicked(Sender: TObject);
    procedure DistributeClicked(Sender: TObject);
    {$ENDIF}
  private
    {$IFDEF LED_PARADE}
    { the References and View tabs }
    FZoomBox: TComboBox;
    FMarksBtn, FNavBtn: TSpeedButton;
    FNavPanel: TPanel;
    FNavList: TListBox;
    FNavSplitter: TSplitter;
    FNavTimer: TTimer;
    FFitWidth: Boolean;         { the zoom follows the width of the view (Page width), until another is chosen }
    FFitZoom: Double;           { the zoom it last set: another one found means Ctrl+wheel chose it }
    procedure FitWidth;
    procedure EditResized(Sender: TObject);
    procedure BuildReferences;
    procedure TocItemClicked(Sender: TObject);
    procedure CaptionItemClicked(Sender: TObject);
    procedure CrossRefClicked(Sender: TObject);
    procedure BookmarkClicked(Sender: TObject);
    procedure BuildView;
    procedure ShowZoom;
    procedure ZoomChosen(Sender: TObject);
    procedure ZoomKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ZoomInClicked(Sender: TObject);
    procedure ZoomOutClicked(Sender: TObject);
    procedure MarksClicked(Sender: TObject);
    procedure NavClicked(Sender: TObject);
    procedure NavListClicked(Sender: TObject);
    procedure NavTimerFired(Sender: TObject);
    {$ENDIF}
    procedure FitBarHost;
    procedure BarResized(Sender: TObject);
    procedure BeginRows;
    procedure NextRow;
    procedure EndRows;
    function AddTab(const ACaption: string): TFlowPanel;
    procedure TabClicked(Sender: TObject);
    procedure AddSeparator;
    function AddIconButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TSpeedButton;
    function AddToggle(const ACaption, AHint: string; AStyle: TFontStyles; AOnClick: TNotifyEvent): TSpeedButton;
    function AddIconToggle(const AIcon, AHint: string; AOnClick: TNotifyEvent): TSpeedButton;
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
    { the Delete key, as the page has it: a character, the selection, a selected drawing or shape of one }
    procedure DeleteKey;
    { Asks for a relay, a document and a token, and puts the shared document
      in place of this one -- Join without the toolbar.  False when it was
      cancelled or could not join (the reason has been shown). }
    function JoinShared: Boolean;
    {$IFDEF LED_PARADE_SYNC}
    { joined to a shared document the caller asked for (File > Join), in place of this page }
    function JoinWith(const Server, Doc, Token, Who: string): Boolean;
    { the page's session, for the main window's Share / Host / Invite / Leave }
    property Collab: TLedCollab read FCollab;
    {$ENDIF}

    property Kind: TLedVisualKind read FKind;
    { Changed here since the last Load or MarkSaved. }
    property Modified: Boolean read GetModified;
    procedure MarkSaved;
    { The control that takes the focus and the keys.  nil without Parade. }
    property Editor: TWinControl read GetEditor;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { The caret or the selection moved: what the status bar says of the page has changed }
    property OnStatus: TNotifyEvent read FOnStatus write FOnStatus;
    { For the status bar: the caret's page of how many, and the selection's words and characters when there is one }
    function StatusText: string;
    {$IFDEF LED_PARADE}
    { the page itself, for scripting and tests }
    property Page: TParadeEdit read FEdit;
    { the Shape tab, there while a shape is selected; for tests }
    function ShapeTabShown: Boolean;
    { the gallery of shapes the Insert tab's Shapes button opens (nil until it first is) }
    property ShapePalette: TForm read FShapePop;
    {$ENDIF}
    { the tab shown in the toolbar: 0 Home, 1 Insert, 2 Layout, 3 References, 4 Review, 5 View, 6 Share, then
      Table (shown in a table); without Parade: 0 Home, 1 Review }
    procedure ShowTab(AIndex: Integer);
    { the preferences that reach the page: line breaking as one types (for a
      .pdoc or .jdoc, only what it opens next: it carries its own) }
    procedure ApplyPrefs;
  end;

{ Whether this LED has the visual editor at all. }
function LedVisualAvailable: Boolean;

{ Whether this LED can share documents (Parade built with its yrs library). }
function LedVisualCanShare: Boolean;

{ An empty Word file, as Parade writes one: what a document joined starts as. }
function LedVisualEmptyDocx: string;
{ An empty document of a kind the pages are kept as (lvkDocx, lvkPdoc). }
function LedVisualEmpty(AKind: TLedVisualKind): string;

{ What the visual editor would open this file as, by its name. }
function LedVisualKindOf(const AFileName: string): TLedVisualKind;
{ a file of the kind is bytes (Word, .pdoc), not text }
function LedVisualKindIsBinary(AKind: TLedVisualKind): Boolean;

{ The keys the visual editor takes before the window's shortcuts do: Ctrl+B
  is bold in a page and Toggle Bookmark everywhere else, and the window would
  otherwise always win -- see Led.UI.EditKeys. }
function LedVisualClaimKey(AKey: Word; AShift: TShiftState;
  AControl: TWinControl): Boolean;

{ The words and characters of UTF-8 text, added to Words and Chars, as a word processor counts them: a word is a run
  of anything but white space, and each Chinese, Japanese or Korean character is a word of its own; the characters
  are every one but the line breaks.  InWord carries a word across calls, for text that comes in pieces. }
procedure LedCountText(const S: string; var Words, Chars: Integer; var InWord: Boolean);
{ ", 12 words, 68 characters" for a selection, '' for none }
function LedSelectionCounts(Words, Chars: Integer): string;

implementation

uses
  Led.UI.EditKeys, Led.UI.Dpi, Led.UI.Icons, Led.Core.Prefs, Math, StrUtils, IntfGraphics, GraphType, FPImage
  {$IFDEF LED_PARADE}, fpjson, jsonparser, ctypes{$ENDIF}
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
begin
  Result := LedVisualEmpty(lvkDocx);
end;

function LedVisualEmpty(AKind: TLedVisualKind): string;
var
  P: TLedVisualPane;
begin
  P := TLedVisualPane.Create(nil);
  try
    Result := P.Export(AKind);
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
  if E = '.pdoc' then Exit(lvkPdoc);
  if E = '.jdoc' then Exit(lvkJdoc);
  Result := lvkNone;
end;

function LedVisualKindIsBinary(AKind: TLedVisualKind): Boolean;
begin
  Result := AKind in [lvkDocx, lvkPdoc];
end;

{$IFDEF LED_PARADE}
function ParadeFormat(AKind: TLedVisualKind): Int32;
begin
  case AKind of
    lvkMarkdown: Result := PD_CONV_MARKDOWN;
    lvkHtml: Result := PD_CONV_HTML;
    lvkDocx: Result := PD_CONV_DOCX;
    lvkPdoc, lvkJdoc: Result := PD_CONV_JDATA;
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
  { and every other font installed, for the font list: loaded when text first uses one }
  AEdit.AddSystemFonts;
end;
{$ENDIF}

{ the toolbar's height: two rows of small buttons, or one row of big ones (a picture over a name) }
function BarHeight: Integer;
begin
  Result := 2 * LedScale96(30) + LedScale96(2);
end;

{$IFDEF LED_PARADE}
type
  { The style panel: the paragraph styles drawn as they look -- their font, size, weight, slant and colour,
    the size kept to what fits -- in two rows of tiles, the caret's style marked; a click gives the paragraph
    the style, the wheel or the arrows at the right go through the rest. }
  TLedStyleGallery = class(TCustomControl)
  private
    FNames: TStringList;
    FFamily: array of string;
    FPoints: array of Double;
    FBold, FItalic: array of Boolean;
    FColor: array of TColor;
    FFirst, FHot: Integer;
    FCurrent, FPicked: string;
    FOnPick: TNotifyEvent;
    procedure SetCurrent(const AValue: string);
    function TileW: Integer;
    function TileH: Integer;
    function Cols: Integer;
    function TileAt(X, Y: Integer): Integer;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { the styles named in ANames, as the document defines them }
    procedure Fill(AEdit: TParadeEdit; ANames: TStrings);
    property Current: string read FCurrent write SetCurrent;
    property Picked: string read FPicked;
    property OnPick: TNotifyEvent read FOnPick write FOnPick;
  end;

constructor TLedStyleGallery.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNames := TStringList.Create;
  FHot := -1;
  TabStop := False;     { a click leaves the caret in the page }
  ControlStyle := ControlStyle + [csOpaque];
end;

destructor TLedStyleGallery.Destroy;
begin
  FNames.Free;
  inherited Destroy;
end;

procedure TLedStyleGallery.Fill(AEdit: TParadeEdit; ANames: TStrings);
var
  i: Integer;
  St: pd_style_id;
  Cp: pd_char_props;
begin
  FNames.Assign(ANames);
  SetLength(FFamily, FNames.Count);
  SetLength(FPoints, FNames.Count);
  SetLength(FBold, FNames.Count);
  SetLength(FItalic, FNames.Count);
  SetLength(FColor, FNames.Count);
  for i := 0 to FNames.Count - 1 do
  begin
    FillChar(Cp, SizeOf(Cp), 0);
    St := pd_doc_style_find(AEdit.Doc, PAnsiChar(FNames[i]));
    if St <> 0 then
      pd_doc_style_resolve(AEdit.Doc, St, nil, @Cp);
    FFamily[i] := Cp.family;
    FPoints[i] := Cp.size / PD_SP_PER_PT;
    FBold[i] := Cp.weight >= 600;
    FItalic[i] := Cp.italic <> 0;
    if Cp.color and $FFFFFF <> 0 then
      FColor[i] := RGBToColor((Cp.color shr 16) and $FF, (Cp.color shr 8) and $FF, Cp.color and $FF)
    else
      FColor[i] := clBlack;
  end;
  if FFirst >= FNames.Count then
    FFirst := 0;
  Invalidate;
end;

procedure TLedStyleGallery.SetCurrent(const AValue: string);
var
  K: Integer;
begin
  if AValue = FCurrent then Exit;
  FCurrent := AValue;
  { the caret's style in view }
  K := FNames.IndexOf(AValue);
  if (K >= 0) and (Cols > 0) and ((K < FFirst) or (K >= FFirst + 2 * Cols)) then
    { its row, or the row above it when it is in the last: both rows full as far as the styles go }
    FFirst := Max(0, Min((K div Cols) * Cols, ((FNames.Count - 1) div Cols) * Cols - Cols));
  Invalidate;
end;

function TLedStyleGallery.TileW: Integer;
begin
  Result := LedScale96(86);
end;

function TLedStyleGallery.TileH: Integer;
begin
  Result := (ClientHeight - LedScale96(2)) div 2;
end;

function TLedStyleGallery.Cols: Integer;
begin
  Result := Max(1, (ClientWidth - LedScale96(18)) div TileW);
end;

function TLedStyleGallery.TileAt(X, Y: Integer): Integer;
var
  C, R: Integer;
begin
  Result := -1;
  if X >= Cols * TileW then
    Exit;
  C := X div TileW;
  R := Y div (TileH + LedScale96(2));
  if (R < 0) or (R > 1) then
    Exit;
  Result := FFirst + R * Cols + C;
  if Result >= FNames.Count then
    Result := -1;
end;

procedure TLedStyleGallery.Paint;
var
  i, K, X, Y, AX: Integer;
  R: TRect;
  Pt: Double;
begin
  Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(ClientRect);
  for i := 0 to 2 * Cols - 1 do
  begin
    K := FFirst + i;
    if K >= FNames.Count then
      Break;
    X := (i mod Cols) * TileW;
    Y := (i div Cols) * (TileH + LedScale96(2));
    R := Rect(X + 1, Y, X + TileW - 2, Y + TileH);
    if FNames[K] = FCurrent then
      Canvas.Brush.Color := RGBToColor(214, 228, 252)
    else if K = FHot then
      Canvas.Brush.Color := RGBToColor(236, 242, 252)
    else
      Canvas.Brush.Color := clWhite;    { the page's own white, in a dark theme too: the styles look as on it }
    Canvas.Pen.Color := IfThen(FNames[K] = FCurrent, RGBToColor(80, 120, 230), RGBToColor(200, 204, 214));
    Canvas.Rectangle(R);
    { the name in the style's own look, at a size that fits the tile }
    Canvas.Font.Name := IfThen(FFamily[K] <> '', FFamily[K], 'default');
    Pt := FPoints[K];
    if Pt <= 0 then Pt := 11;
    Canvas.Font.Size := Max(7, Min(Round(Pt), 13));
    Canvas.Font.Style := [];
    if FBold[K] then Canvas.Font.Style := Canvas.Font.Style + [fsBold];
    if FItalic[K] then Canvas.Font.Style := Canvas.Font.Style + [fsItalic];
    Canvas.Font.Color := FColor[K];
    Canvas.Brush.Style := bsClear;
    Canvas.TextRect(Rect(R.Left + 3, R.Top + 1, R.Right - 3, R.Bottom - 1), R.Left + LedScale96(5),
      R.Top + (TileH - Canvas.TextHeight(FNames[K])) div 2, FNames[K]);
    Canvas.Brush.Style := bsSolid;
  end;
  { the arrows to go through the rest: up a row, down a row }
  AX := Cols * TileW + LedScale96(2);
  Canvas.Font.Name := 'default';
  Canvas.Font.Size := 8;
  Canvas.Font.Style := [];
  Canvas.Font.Color := IfThen(FFirst > 0, clBtnText, clGrayText);
  Canvas.TextOut(AX + 2, LedScale96(6), #$E2#$96#$B2);
  Canvas.Font.Color := IfThen(FFirst + 2 * Cols < FNames.Count, clBtnText, clGrayText);
  Canvas.TextOut(AX + 2, ClientHeight - LedScale96(20), #$E2#$96#$BC);
end;

procedure TLedStyleGallery.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  K: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  K := TileAt(X, Y);
  if K <> FHot then
  begin
    FHot := K;
    Invalidate;
  end;
end;

procedure TLedStyleGallery.MouseLeave;
begin
  inherited MouseLeave;
  if FHot >= 0 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

procedure TLedStyleGallery.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  K: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  if X >= Cols * TileW then
  begin   { the arrows }
    if Y < ClientHeight div 2 then
      FFirst := Max(0, FFirst - Cols)
    else if FFirst + 2 * Cols < FNames.Count then
      Inc(FFirst, Cols);
    Invalidate;
    Exit;
  end;
  K := TileAt(X, Y);
  if K < 0 then Exit;
  FPicked := FNames[K];
  if Assigned(FOnPick) then
    FOnPick(Self);
end;

function TLedStyleGallery.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then
    FFirst := Max(0, FFirst - Cols)
  else if FFirst + 2 * Cols < FNames.Count then
    Inc(FFirst, Cols);
  Invalidate;
  Result := True;
end;
{$ENDIF}

procedure SetIcon(AButton: TSpeedButton; const AIcon: string); forward;
procedure SetSmallIcon(AButton: TSpeedButton; const AIcon: string); forward;

{ TLedVisualPane }

constructor TLedVisualPane.Create(AOwner: TComponent);
var
  i: Integer;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';

  { The toolbar: tabs, as a word processor's -- Home for the font and the
    paragraph, Insert for tables, pictures, links and the like, Layout for
    the pages, References for contents, captions and cross-references,
    Review for tracked changes and comments, View for zoom, marks and the
    headings, Share for editing together, and Table while the caret is in
    one -- each a row of controls that wraps when the pane is narrow. }
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
  FEdit.OnResize := @EditResized;
  FFitWidth := True;      { a page as wide as the view, as a reader expects on opening one }
  {$ENDIF}
  ApplyPrefs;

  AddTab('Home');
  FStyle := TComboBox.Create(Self);
  FStyle.Style := csDropDownList;
  FStyle.Width := LedScale96(130);
  FStyle.Constraints.MinWidth := LedScale96(130);
  FStyle.Constraints.MaxWidth := LedScale96(130);
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

  FTableTab := -1;
  FShapeTab := -1;
  {$IFDEF LED_PARADE}
  AddTab('Insert');
  FShapeTab := High(FBars);
  BuildInsert;
  AddTab('Layout');
  BuildLayout;
  AddTab('References');
  BuildReferences;
  {$ENDIF}

  { review: tracked changes and comments }
  AddTab('Review');
  FTrack := AddButton('Track changes', 'Record edits as tracked changes', [], @TrackClicked);
  SetIcon(FTrack, 'trackchanges');
  FTrack.AllowAllUp := True;
  FTrack.GroupIndex := 1;
  AddSeparator;
  BeginRows;
  SetSmallIcon(AddButton('Previous', 'Previous change or comment', [], @PrevClicked), 'prevchange');
  SetSmallIcon(AddButton('Accept', 'Accept the change (the selection''s changes)', [], @AcceptClicked), 'accept');
  NextRow;
  SetSmallIcon(AddButton('Next', 'Next change or comment', [], @NextClicked), 'nextchange');
  SetSmallIcon(AddButton('Reject', 'Reject the change (the selection''s changes)', [], @RejectClicked), 'reject');
  EndRows;
  AddSeparator;
  SetIcon(AddButton('Comment', 'Comment on the selection, or reply to the comment at the caret', [], @CommentClicked),
    'addcomment');
  AddSeparator;
  BeginRows;
  with TLabel.Create(Self) do
  begin
    Parent := FBar;
    Caption := 'Show changes as';
  end;
  NextRow;
  FMarkup := TComboBox.Create(Self);
  FMarkup.Parent := FBar;
  FMarkup.Style := csDropDownList;
  FMarkup.Width := LedScale96(110);
  FMarkup.Constraints.MinWidth := LedScale96(110);
  FMarkup.Constraints.MaxWidth := LedScale96(110);
  FMarkup.Hint := 'How tracked changes show';
  FMarkup.ShowHint := True;
  FMarkup.Items.Add('Balloons');
  FMarkup.Items.Add('Inline');
  FMarkup.Items.Add('Final');
  FMarkup.Items.Add('Original');
  FMarkup.ItemIndex := 0;
  FMarkup.OnSelect := @MarkupChosen;
  EndRows;

  {$IFDEF LED_PARADE}
  AddTab('View');
  BuildView;
  {$ENDIF}

  {$IFDEF LED_PARADE_SYNC}
  { a shared document: everyone editing it at once, through a relay (Share and Join are on LED's own toolbar,
    for every kind of document); how the session is doing, on the tabs' row }
  FSyncStatus := TLabel.Create(Self);
  FSyncStatus.Parent := FTabStrip;    { on the tabs' row: seen whichever tab is open }
  FSyncStatus.Caption := '';
  FSyncStatus.Layout := tlCenter;
  FSyncStatus.BorderSpacing.Left := LedScale96(12);
  FSync := TParadeSync.Create(Self, FEdit);
  FSync.OutboxDir := IncludeTrailingPathDelimiter(LedConfigDir) + 'outbox';   { edits made offline outlive a quit }
  FCollab := TLedCollab.Create(Self, FSync, lckRich);
  FCollab.OnChange := @SyncChanged;
  {$ENDIF}
  {$IFDEF LED_PARADE}
  { a tab of its own while the caret is in a table, as word processors have it }
  AddTab('Table');
  BuildTable;
  FTableTab := High(FBars);
  FTabBtns[FTableTab].Visible := False;
  {$ENDIF}
  {$IFDEF LED_PARADE_SYNC}
  { the sharing status after the last tab }
  FSyncStatus.Parent := nil;
  FSyncStatus.Parent := FTabStrip;
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
  SetLength(FTabBtns, Length(FTabBtns) + 1);
  FTabBtns[High(FTabBtns)] := B;
  if FBarHost = nil then
  begin
    FBarHost := TPanel.Create(Self);
    FBarHost.Parent := Self;
    FBarHost.Align := alTop;
    FBarHost.Top := 1000;     { under the tabs, above the page }
    FBarHost.BevelOuter := bvNone;
    FBarHost.Caption := '';
    FBarHost.Height := BarHeight + LedScale96(6);
  end;
  Result := TFlowPanel.Create(Self);
  Result.Parent := FBarHost;
  Result.Align := alTop;
  Result.OnResize := @BarResized;     { its rows wrapped again: the holder may need to grow }
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
  FBarHost.DisableAlign;
  try
    for i := 0 to High(FBars) do
      FBars[i].Visible := i = AIndex;
  finally
    FBarHost.EnableAlign;
  end;
  FitBarHost;
  for i := 0 to FTabStrip.ControlCount - 1 do
    if (FTabStrip.Controls[i] is TSpeedButton) and (FTabStrip.Controls[i].Tag = AIndex) then
      TSpeedButton(FTabStrip.Controls[i]).Down := True;
end;

procedure TLedVisualPane.BarResized(Sender: TObject);
begin
  if TControl(Sender).Visible then
    FitBarHost;
end;

{ The bars' holder only grows, to the tallest bar seen at this width: were it as tall as the bar shown, a tab
  whose row wraps (Home) and one whose row does not would move the page up and down on every switch, and the
  page is drawn again whole each time it is resized -- slow over a remote display. A new width starts again. }
procedure TLedVisualPane.FitBarHost;
var
  i, H: Integer;
begin
  if FBarHost = nil then Exit;
  if FBarHost.Width <> FBarWidth then
  begin
    FBarWidth := FBarHost.Width;
    H := 0;
  end
  else
    H := FBarHost.Height;
  H := Max(H, BarHeight + LedScale96(6));    { two rows of small buttons, or one of big ones }
  for i := 0 to High(FBars) do
    if FBars[i].Visible then
      H := Max(H, FBars[i].Height + FBars[i].BorderSpacing.Bottom);
  if H <> FBarHost.Height then
    FBarHost.Height := H;
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
  B.Height := BarHeight;
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
  Result.Constraints.MinWidth := LedScale96(30);
  Result.Width := LedScale96(30);
  Result.Height := LedScale96(30);
  Result.BorderSpacing.Around := LedScale96(1);
  Result.OnClick := AOnClick;
end;

function TLedVisualPane.AddIconButton(const AIcon, AHint: string; AOnClick: TNotifyEvent): TSpeedButton;
begin
  Result := AddButton('', AHint, [], AOnClick);
  Result.Width := LedScale96(30);
  Result.Glyph := LedIconBitmap(AIcon, clBtnText, LedScale96(20));
end;

var
  ToggleGroups: Integer = 100;

{ a picture on a button made with a caption: the two side by side }
{ a button with a name made a big one: its picture over its name, as tall as the two rows }
procedure SetIcon(AButton: TSpeedButton; const AIcon: string);
begin
  AButton.Glyph := LedIconBitmap(AIcon, clBtnText, LedScale96(32));
  AButton.Layout := blGlyphTop;
  AButton.Spacing := LedScale96(2);
  AButton.Margin := LedScale96(3);
  AButton.Constraints.MinWidth := LedScale96(52);
  AButton.Constraints.MinHeight := BarHeight;
  AButton.Height := BarHeight;
end;

{ a button with a name kept small, for a two-row group: a small picture beside its name }
procedure SetSmallIcon(AButton: TSpeedButton; const AIcon: string);
begin
  AButton.Glyph := LedIconBitmap(AIcon, clBtnText, LedScale96(20));
  AButton.Layout := blGlyphLeft;
  AButton.Spacing := LedScale96(4);
  AButton.Margin := LedScale96(3);
end;

{ two rows of small controls side by side in a bar, the second under the first: Home's font and paragraph
  groups, the Layout tab's boxes }
procedure TLedVisualPane.BeginRows;
var
  R: TPanel;
begin
  FBarSave := FBar;
  FGroup := TPanel.Create(Self);
  FGroup.Parent := FBar;
  FGroup.BevelOuter := bvNone;
  FGroup.Caption := '';
  FGroup.AutoSize := True;
  FGroup.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  FGroup.ChildSizing.ControlsPerLine := 1;
  FGroup.ChildSizing.VerticalSpacing := LedScale96(2);
  FGroup.BorderSpacing.Around := LedScale96(1);
  R := TPanel.Create(Self);
  R.Parent := FGroup;
  R.BevelOuter := bvNone;
  R.Caption := '';
  R.AutoSize := True;
  R.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  R.ChildSizing.ControlsPerLine := 100;
  R.ChildSizing.HorizontalSpacing := LedScale96(1);
  FBar := R;
end;

procedure TLedVisualPane.NextRow;
var
  R: TPanel;
begin
  R := TPanel.Create(Self);
  R.Parent := FGroup;
  R.BevelOuter := bvNone;
  R.Caption := '';
  R.AutoSize := True;
  R.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  R.ChildSizing.ControlsPerLine := 100;
  R.ChildSizing.HorizontalSpacing := LedScale96(1);
  FBar := R;
end;

procedure TLedVisualPane.EndRows;
begin
  FBar := FBarSave;
end;

function TLedVisualPane.AddIconToggle(const AIcon, AHint: string; AOnClick: TNotifyEvent): TSpeedButton;
begin
  Result := AddToggle('', AHint, [], AOnClick);
  Result.AutoSize := False;
  Result.Width := LedScale96(30);
  Result.Glyph := LedIconBitmap(AIcon, clBtnText, LedScale96(20));
end;

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

  { the font: its name and size, then how it looks }
  BeginRows;
  FFont := TComboBox.Create(Self);
  FFont.Parent := FBar;
  FFont.Style := csDropDown;      { a family the list does not have can still be typed }
  FFont.Width := LedScale96(150);
  FFont.Constraints.MinWidth := LedScale96(150);
  FFont.Constraints.MaxWidth := LedScale96(150);
  FFont.Hint := 'Font';
  FFont.ShowHint := True;
  FFont.DropDownCount := 20;
  FEdit.GetFontFamilies(FFont.Items);
  FFont.OnSelect := @FontChosen;
  FFont.OnKeyDown := @ComboKeyDown;
  FSize := TComboBox.Create(Self);
  FSize.Parent := FBar;
  FSize.Style := csDropDown;
  FSize.Width := LedScale96(58);
  FSize.Constraints.MinWidth := LedScale96(58);
  FSize.Constraints.MaxWidth := LedScale96(58);
  FSize.Hint := 'Font size';
  FSize.ShowHint := True;
  FSize.DropDownCount := 16;
  for i := 0 to High(Sizes) do
    FSize.Items.Add(Sizes[i]);
  FSize.OnSelect := @SizeChosen;
  FSize.OnKeyDown := @ComboKeyDown;
  AddIconButton('fontgrow', 'Bigger (Ctrl+])', @GrowClicked);
  AddIconButton('fontshrink', 'Smaller (Ctrl+[)', @ShrinkClicked);
  AddIconButton('clearformat', 'Clear formatting (the selection''s own; its style stays)', @ClearClicked);
  FPainterBtn := AddIconToggle('formatpainter', 'Format painter: the look at the caret onto the next selection ' +
    '(double-click: onto every one, until Escape)', @PainterClicked);
  FPainterBtn.OnDblClick := @PainterDblClicked;
  NextRow;
  FBoldBtn := AddIconToggle('fmtbold', 'Bold (Ctrl+B)', @BoldClicked);
  FItalicBtn := AddIconToggle('fmtitalic', 'Italic (Ctrl+I)', @ItalicClicked);
  FUnderBtn := AddIconToggle('fmtunderline', 'Underline (Ctrl+U)', @UnderlineClicked);
  FStrikeBtn := AddIconToggle('fmtstrike', 'Strikethrough', @StrikeClicked);
  FSubBtn := AddIconToggle('fmtsub', 'Subscript', @SubClicked);
  FSupBtn := AddIconToggle('fmtsuper', 'Superscript', @SupClicked);
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
  EndRows;
  AddSeparator;

  { the paragraph: lists, indents and spacing, then alignment }
  BeginRows;
  FBulletBtn := AddIconButton('bullets', 'Bullets', @BulletsClicked);
  FBulletBtn.GroupIndex := 60;
  FBulletBtn.AllowAllUp := True;
  FNumberBtn := AddIconButton('numbering', 'Numbering', @NumberingClicked);
  FNumberBtn.GroupIndex := 61;
  FNumberBtn.AllowAllUp := True;
  AddIconButton('unindent', 'Decrease indent (in a list: a level up)', @IndentLessClicked);
  AddIconButton('indent', 'Increase indent (in a list: a level down)', @IndentMoreClicked);
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
  NextRow;
  for i := 0 to 3 do
  begin
    FAlignBtns[i] := AddIconButton(AlignIcons[i], AlignHints[i], @AlignClicked);
    FAlignBtns[i].GroupIndex := 62;     { one of the four }
    FAlignBtns[i].Tag := AlignValues[i];
  end;
  EndRows;
  AddSeparator;

  { the styles: the panel shows them as they look, the box lists them all }
  BeginRows;
  FStyle.Parent := FBar;
  NextRow;
  with TLabel.Create(Self) do
  begin
    Parent := FBar;
    Caption := 'Styles';
    BorderSpacing.Left := LedScale96(4);
  end;
  EndRows;
  FGallery := TLedStyleGallery.Create(Self);
  FGallery.Parent := FBar;
  FGallery.Width := LedScale96(3 * 86 + 18);
  FGallery.Height := BarHeight;
  FGallery.Hint := 'Paragraph styles: click one to give the paragraph it';
  FGallery.ShowHint := True;
  TLedStyleGallery(FGallery).OnPick := @GalleryPicked;
  FGallery.BorderSpacing.Around := LedScale96(1);
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
    if FGallery <> nil then
      TLedStyleGallery(FGallery).Fill(FEdit, FStyle.Items);
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
  ShapeAt: pd_pos;
  ShapeSid: Integer;
  Sel: Boolean;
begin
  if Assigned(FOnStatus) then
    FOnStatus(Self);
  if FFont = nil then Exit;
  P := FEdit.CurrentCharProps;
  if not FFont.Focused then
    FFont.Text := P.family;
  if not FSize.Focused then
    FSize.Text := FormatFloat('0.#', P.size / PD_SP_PER_PT);
  FBoldBtn.Down := P.weight >= 600;
  FPainterBtn.Down := FEdit.FormatPainterOn;
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
  if FGallery <> nil then
    TLedStyleGallery(FGallery).Current := FEdit.CurrentStyleName;
  FitWidth;     { the paper may have changed (landscape, another size) }
  ShowZoom;
  { the Layout tab's boxes and menus }
  FUpdating := True;
  try
    if not FIndentLeft.Focused then FIndentLeft.Value := Pp.indent_left / PD_SP_PER_PT / 72;
    if not FIndentRight.Focused then FIndentRight.Value := Pp.indent_right / PD_SP_PER_PT / 72;
    if not FSpaceBefore.Focused then FSpaceBefore.Value := Pp.space_before / PD_SP_PER_PT;
    if not FSpaceAfter.Focused then FSpaceAfter.Value := Pp.space_after / PD_SP_PER_PT;
  finally
    FUpdating := False;
  end;
  with FEdit.CurrentSectionProps do
  begin
    FLandscapeItem.Checked := page_width > page_height;
    FPortraitItem.Checked := page_width <= page_height;
  end;
  { the Table tab: there while the caret is in a table; Home again when it leaves with the tab open }
  if FTableTab >= 0 then
  begin
    if FEdit.InTable then
    begin
      FTabBtns[FTableTab].Visible := True;
      FHeaderRowBtn.Down := FEdit.CurrentTableProps.header_rows > 0;
    end
    else if FTabBtns[FTableTab].Visible then
    begin
      if FBars[FTableTab].Visible then
        ShowTab(0);
      FTabBtns[FTableTab].Visible := False;
    end;
  end;
  { the Insert tab's shapes: its controls for a shape there while one is selected, and the tab opened when one first
    is }
  if FShapeTab >= 0 then
  begin
    Sel := FEdit.SelectedShape(ShapeAt, ShapeSid);
    if Sel <> FShapeSel then
      for i := 0 to High(FShapeFmt) do
        FShapeFmt[i].Enabled := Sel;
    if Sel and not FShapeSel then
      ShowTab(FShapeTab);
    FShapeSel := Sel;
  end;
end;

{ the painter: on for one selection, off again when clicked while on }
procedure TLedVisualPane.PainterClicked(Sender: TObject);
begin
  if FEdit.FormatPainterOn then
    FEdit.StopFormatPainter
  else
    FEdit.StartFormatPainter(False);
  FPainterBtn.Down := FEdit.FormatPainterOn;
  BackToPage;
end;

{ double-clicked: on for every selection, until Escape or another click }
procedure TLedVisualPane.PainterDblClicked(Sender: TObject);
begin
  FEdit.StartFormatPainter(True);
  FPainterBtn.Down := True;
  BackToPage;
end;

procedure TLedVisualPane.GalleryPicked(Sender: TObject);
begin
  FEdit.SetParagraphStyle(TLedStyleGallery(FGallery).Picked);
  BackToPage;
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

{ the Insert tab: objects at the caret }
const
  { Word's shapes, as its gallery has them: a group's name (#), then its shapes -- Office's presets by their names,
    and the lines and the shapes drawn by hand by this editor's }
  ShapeGallery: array[0..167] of string = (
    '#Lines', 'line', 'arrow', 'doubleArrow', 'elbow', 'elbowArrow', 'elbowDoubleArrow', 'curvedConnector',
    'curvedArrow', 'curvedDoubleArrow', 'curve', 'freeform', 'scribble',
    '#Rectangles', 'rect', 'roundRect', 'snip1Rect', 'snip2SameRect', 'snip2DiagRect', 'snipRoundRect', 'round1Rect',
    'round2SameRect', 'round2DiagRect',
    '#Basic Shapes', 'textbox', 'ellipse', 'triangle', 'rtTriangle', 'parallelogram', 'trapezoid', 'diamond',
    'pentagon', 'hexagon', 'heptagon', 'octagon', 'decagon', 'dodecagon', 'pie', 'chord', 'teardrop', 'frame',
    'halfFrame', 'corner', 'diagStripe', 'plus', 'plaque', 'can', 'cube', 'bevel', 'donut', 'noSmoking', 'blockArc',
    'foldedCorner', 'smileyFace', 'heart', 'lightningBolt', 'sun', 'moon', 'cloud', 'arc', 'bracketPair', 'bracePair',
    'leftBracket', 'rightBracket', 'leftBrace', 'rightBrace',
    '#Block Arrows', 'rightArrow', 'leftArrow', 'upArrow', 'downArrow', 'leftRightArrow', 'upDownArrow', 'quadArrow',
    'leftRightUpArrow', 'bentArrow', 'uturnArrow', 'leftUpArrow', 'bentUpArrow', 'curvedRightArrow',
    'curvedLeftArrow', 'curvedUpArrow', 'curvedDownArrow', 'stripedRightArrow', 'notchedRightArrow', 'homePlate',
    'chevron', 'rightArrowCallout', 'downArrowCallout', 'leftArrowCallout', 'upArrowCallout',
    'leftRightArrowCallout', 'quadArrowCallout', 'circularArrow',
    '#Equation Shapes', 'mathPlus', 'mathMinus', 'mathMultiply', 'mathDivide', 'mathEqual', 'mathNotEqual',
    '#Flowchart', 'flowChartProcess', 'flowChartAlternateProcess', 'flowChartDecision', 'flowChartInputOutput',
    'flowChartPredefinedProcess', 'flowChartInternalStorage', 'flowChartDocument', 'flowChartMultidocument',
    'flowChartTerminator', 'flowChartPreparation', 'flowChartManualInput', 'flowChartManualOperation',
    'flowChartConnector', 'flowChartOffpageConnector', 'flowChartPunchedCard', 'flowChartPunchedTape',
    'flowChartSummingJunction', 'flowChartOr', 'flowChartCollate', 'flowChartSort', 'flowChartExtract',
    'flowChartMerge', 'flowChartOnlineStorage', 'flowChartDelay', 'flowChartMagneticTape', 'flowChartMagneticDisk',
    'flowChartMagneticDrum', 'flowChartDisplay',
    '#Stars and Banners', 'irregularSeal1', 'irregularSeal2', 'star4', 'star5', 'star6', 'star7', 'star8', 'star10',
    'star12', 'star16', 'star24', 'star32', 'ribbon2', 'ribbon', 'ellipseRibbon2', 'ellipseRibbon', 'verticalScroll',
    'horizontalScroll', 'wave', 'doubleWave',
    '#Callouts', 'wedgeRectCallout', 'wedgeRoundRectCallout', 'wedgeEllipseCallout', 'cloudCallout',
    'borderCallout1', 'borderCallout2', 'borderCallout3', 'accentCallout1', 'accentCallout2', 'accentCallout3',
    'callout1', 'callout2', 'callout3', 'accentBorderCallout1', 'accentBorderCallout2', 'accentBorderCallout3');

{ a shape's name as a reader says it: rightArrow "Right arrow", star5 "Star 5" }
function ShapeTitle(const Kind: string): string;
var
  i: Integer;
begin
  case Kind of
    'rect': Exit('Rectangle');
    'roundRect': Exit('Rounded rectangle');
    'ellipse': Exit('Oval');
    'line': Exit('Line');
    'arrow': Exit('Line arrow');
    'doubleArrow': Exit('Line arrow: double');
    'elbow': Exit('Connector: elbow');
    'elbowArrow': Exit('Connector: elbow arrow');
    'elbowDoubleArrow': Exit('Connector: elbow double arrow');
    'curvedConnector': Exit('Connector: curved');
    'curvedArrow': Exit('Connector: curved arrow');
    'curvedDoubleArrow': Exit('Connector: curved double arrow');
    'curve': Exit('Curve (click its points; double-click to end)');
    'freeform': Exit('Freeform (click its corners; on the first again to close it, or double-click to end)');
    'scribble': Exit('Scribble (drag to draw)');
    'textbox': Exit('Text box');
  end;
  Result := '';
  for i := 1 to Length(Kind) do
    if (i > 1) and ((Kind[i] in ['A'..'Z']) or ((Kind[i] in ['0'..'9']) and not (Kind[i - 1] in ['0'..'9']))) then
      Result := Result + ' ' + LowerCase(Kind[i])
    else
      Result := Result + Kind[i];
  if Copy(Result, 1, 10) = 'flow chart' then
    Result := 'Flowchart:' + Copy(Result, 11, MaxInt);
  Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
end;

{$IFDEF LED_PARADE}
{ A shape as its gallery button shows it: its outline, drawn four times over and averaged (smooth at any size), in
  AColour with the rest transparent. Office's presets from their definitions; the lines and the hand-drawn kinds
  by hand }
function ShapeIcon(const Kind: string; ASize: Integer; AColour: TColor): TBitmap;
const
  K = 4;
var
  Big: TBitmap;
  Img: TLazIntfImage;
  Src: TLazIntfImage;
  X, Y, I, J, S, M, Sum: Integer;
  W, H, BW, BH, OX, OY, Sc: Double;
  Js: RawByteString;
  Adj: string;
  N: csize_t;
  Data: TJSONData;
  Paths, Cmds, C: TJSONArray;
  Pa: TJSONObject;
  AnyStroke: Boolean;
  Pts: array of TPoint;
  NP: Integer;
  CX, CY, SX, SY: Double;
  Col: TFPColor;

  function P(U, V: Double): TPoint;     { a point of the box (0..1) }
  begin
    Result := Point(Round(M + U * (S - 2 * M)), Round(M + V * (S - 2 * M)));
  end;

  procedure Head(X0, Y0, X1, Y1: Double);    { an arrowhead at X1, Y1, coming from X0, Y0 }
  var
    A, L: Double;
  begin
    A := ArcTan2(Y1 - Y0, X1 - X0);
    L := 0.22;
    Big.Canvas.Brush.Style := bsSolid;
    Big.Canvas.Brush.Color := clBlack;
    Big.Canvas.Polygon([P(X1, Y1), P(X1 - L * Cos(A - 0.45), Y1 - L * Sin(A - 0.45)),
      P(X1 - L * Cos(A + 0.45), Y1 - L * Sin(A + 0.45))]);
    Big.Canvas.Brush.Style := bsClear;
  end;

  procedure Bez(const Q: array of Double);   { a cubic through four points of the box }
  var
    T: Integer;
    U, V: Double;
    B: array[0..24] of TPoint;
  begin
    for T := 0 to 24 do
    begin
      U := T / 24;
      V := 1 - U;
      B[T] := P(V * V * V * Q[0] + 3 * V * V * U * Q[2] + 3 * V * U * U * Q[4] + U * U * U * Q[6],
        V * V * V * Q[1] + 3 * V * V * U * Q[3] + 3 * V * U * U * Q[5] + U * U * U * Q[7]);
    end;
    Big.Canvas.Polyline(B);
  end;

  procedure Put(PX, PY: Double);
  begin
    if NP > High(Pts) then
      SetLength(Pts, NP * 2 + 16);
    Pts[NP] := Point(Round(OX + PX * Sc), Round(OY + PY * Sc));
    Inc(NP);
  end;

begin
  S := ASize * K;
  M := 2 * K;
  Big := TBitmap.Create;
  try
    Big.SetSize(S, S);
    Big.Canvas.Brush.Color := clWhite;
    Big.Canvas.FillRect(0, 0, S, S);
    Big.Canvas.Pen.Color := clBlack;
    Big.Canvas.Pen.Width := Round(K * 1.1);
    Big.Canvas.Brush.Style := bsClear;
    case Kind of
      'line', 'arrow', 'doubleArrow':
        begin
          Big.Canvas.Line(P(0.08, 0.92), P(0.92, 0.08));
          if Kind <> 'line' then Head(0.08, 0.92, 0.92, 0.08);
          if Kind = 'doubleArrow' then Head(0.92, 0.08, 0.08, 0.92);
        end;
      'elbow', 'elbowArrow', 'elbowDoubleArrow':
        begin
          Big.Canvas.Polyline([P(0.08, 0.2), P(0.5, 0.2), P(0.5, 0.8), P(0.92, 0.8)]);
          if Kind <> 'elbow' then Head(0.5, 0.8, 0.92, 0.8);
          if Kind = 'elbowDoubleArrow' then Head(0.5, 0.2, 0.08, 0.2);
        end;
      'curvedConnector', 'curvedArrow', 'curvedDoubleArrow':
        begin
          Bez([0.08, 0.2, 0.6, 0.2, 0.4, 0.8, 0.92, 0.8]);
          if Kind <> 'curvedConnector' then Head(0.6, 0.8, 0.92, 0.8);
          if Kind = 'curvedDoubleArrow' then Head(0.4, 0.2, 0.08, 0.2);
        end;
      'curve': Bez([0.08, 0.85, 0.3, -0.25, 0.65, 1.25, 0.92, 0.15]);
      'freeform': Big.Canvas.Polyline([P(0.1, 0.9), P(0.25, 0.25), P(0.5, 0.6), P(0.75, 0.1), P(0.9, 0.75),
          P(0.55, 0.92)]);
      'scribble':
        begin
          SetLength(Pts, 40);
          for I := 0 to 39 do
            Pts[I] := P(0.08 + 0.84 * I / 39, 0.5 + 0.3 * Sin(I / 39 * 11) * (0.5 + 0.5 * Cos(I / 39 * 3)));
          Big.Canvas.Polyline(Pts);
        end;
      'textbox':
        begin
          Big.Canvas.Rectangle(Rect(P(0.08, 0.15).X, P(0.08, 0.15).Y, P(0.92, 0.85).X, P(0.92, 0.85).Y));
          Big.Canvas.Line(P(0.25, 0.35), P(0.75, 0.35));
          Big.Canvas.Line(P(0.25, 0.5), P(0.75, 0.5));
          Big.Canvas.Line(P(0.25, 0.65), P(0.6, 0.65));
        end;
    else
      begin   { an Office preset: its paths as its definition draws them }
        W := 1000;
        H := 1000;
        if (Pos('flowChart', Kind) = 1) or (Pos('Rect', Kind) > 0) or (Kind = 'rect') or (Pos('Ribbon', Kind) > 0) or
           (Kind = 'ribbon') or (Kind = 'ribbon2') or (Pos('wave', LowerCase(Kind)) > 0) or (Kind = 'horizontalScroll') or
           (Kind = 'leftRightArrow') or (Kind = 'stripedRightArrow') or (Kind = 'notchedRightArrow') or
           (Kind = 'homePlate') or (Pos('Callout', Kind) > 0) or (Pos('callout', Kind) = 1) then
          H := 680
        else if (Kind = 'verticalScroll') or (Kind = 'upDownArrow') or (Kind = 'can') then
          W := 680;
        { the corners of the rectangles' kinds cut or rounded more than they are by default, as Word's gallery
          shows them: at its size they would all look alike }
        if Pos('Rect', Kind) > 0 then
          Adj := 'adj=30000 adj1=30000 adj2=30000'
        else
          Adj := '';
        N := pd_preset_json(PAnsiChar(Kind), W, H, PAnsiChar(Adj), nil, 0);
        if N > 0 then
        begin
          SetLength(Js, N + 1);
          pd_preset_json(PAnsiChar(Kind), W, H, PAnsiChar(Adj), PAnsiChar(Js), N + 1);
          SetLength(Js, N);
          Data := nil;
          try
            Data := GetJSON(Js);
            Paths := TJSONObject(Data).Find('paths') as TJSONArray;
            BW := S - 2 * M;
            BH := BW;
            Sc := Min(BW / W, BH / H) * 0.94;
            OX := M + (BW - W * Sc) / 2;
            OY := M + (BH - H * Sc) / 2;
            AnyStroke := False;
            for I := 0 to Paths.Count - 1 do
              AnyStroke := AnyStroke or (TJSONObject(Paths[I]).Get('stroke', 1) = 1);
            for I := 0 to Paths.Count - 1 do
            begin
              Pa := TJSONObject(Paths[I]);
              if AnyStroke and (Pa.Get('stroke', 1) <> 1) then
                Continue;
              Cmds := Pa.Find('cmds') as TJSONArray;
              NP := 0;
              CX := 0; CY := 0; SX := 0; SY := 0;
              for J := 0 to Cmds.Count - 1 do
              begin
                C := TJSONArray(Cmds[J]);
                case C[0].AsString of
                  'm':
                    begin
                      if NP > 1 then Big.Canvas.Polyline(Pts, 0, NP);
                      NP := 0;
                      CX := C[1].AsFloat; CY := C[2].AsFloat; SX := CX; SY := CY;
                      Put(CX, CY);
                    end;
                  'l':
                    begin
                      CX := C[1].AsFloat; CY := C[2].AsFloat;
                      Put(CX, CY);
                    end;
                  'c':
                    begin
                      for X := 1 to 10 do
                      begin
                        BW := X / 10;
                        BH := 1 - BW;
                        Put(BH * BH * BH * CX + 3 * BH * BH * BW * C[1].AsFloat + 3 * BH * BW * BW * C[3].AsFloat +
                          BW * BW * BW * C[5].AsFloat, BH * BH * BH * CY + 3 * BH * BH * BW * C[2].AsFloat +
                          3 * BH * BW * BW * C[4].AsFloat + BW * BW * BW * C[6].AsFloat);
                      end;
                      CX := C[5].AsFloat; CY := C[6].AsFloat;
                    end;
                  'z':
                    begin
                      Put(SX, SY);
                      CX := SX; CY := SY;
                    end;
                end;
              end;
              if NP > 1 then Big.Canvas.Polyline(Pts, 0, NP);
            end;
          except
          end;
          Data.Free;
        end;
      end;
    end;
    { four by four pixels a pixel: how much of it is ink, its alpha }
    Src := Big.CreateIntfImage;
    Img := TLazIntfImage.Create(ASize, ASize, [riqfRGB, riqfAlpha]);
    try
      Img.CreateData;
      for Y := 0 to ASize - 1 do
        for X := 0 to ASize - 1 do
        begin
          Sum := 0;
          for J := 0 to K - 1 do
            for I := 0 to K - 1 do
              Inc(Sum, 65535 - Src.Colors[X * K + I, Y * K + J].green);
          Col := TColorToFPColor(AColour);
          Col.alpha := Sum div (K * K);
          Img.Colors[X, Y] := Col;
        end;
      Result := TBitmap.Create;
      Result.LoadFromIntfImage(Img);
    finally
      Img.Free;
      Src.Free;
    end;
  finally
    Big.Free;
  end;
end;
{$ENDIF}

{ the gallery of shapes, under the button that opens it: a click on one puts it in (drawn with the mouse in the
  canvas selected) }
procedure TLedVisualPane.ShapesDropClicked(Sender: TObject);
var
  Box: TScrollBox;
  Flow: TFlowPanel;
  L: TLabel;
  B: TSpeedButton;
  i, Sz: Integer;
  P: TPoint;
begin
  if FShapePop = nil then
  begin
    FShapePop := TForm.CreateNew(Self);
    FShapePop.BorderStyle := bsNone;
    FShapePop.FormStyle := fsStayOnTop;
    FShapePop.ShowInTaskBar := stNever;
    FShapePop.OnDeactivate := @PaletteDeactivate;
    FShapePop.Width := LedScale96(12 * 30 + 28);
    FShapePop.Height := LedScale96(460);
    Box := TScrollBox.Create(FShapePop);
    Box.Parent := FShapePop;
    Box.Align := alClient;
    Box.HorzScrollBar.Visible := False;
    Box.VertScrollBar.Increment := LedScale96(30);
    Box.Color := clWindow;
    Flow := nil;
    Sz := LedScale96(22);
    { the groups: a heading, then its shapes in rows }
    Box.DisableAutoSizing;
    try
      for i := 0 to High(ShapeGallery) do
        if ShapeGallery[i][1] = '#' then
        begin
          L := TLabel.Create(FShapePop);
          L.Caption := Copy(ShapeGallery[i], 2, MaxInt);
          L.Font.Style := [fsBold];
          L.BorderSpacing.Left := LedScale96(6);
          L.BorderSpacing.Top := LedScale96(4);
          L.Top := 100000 + i * 10;
          L.Align := alTop;
          L.Parent := Box;
          Flow := TFlowPanel.Create(FShapePop);
          Flow.BevelOuter := bvNone;
          Flow.AutoSize := True;
          Flow.AutoWrap := True;
          Flow.Top := 100000 + i * 10 + 5;
          Flow.Align := alTop;
          Flow.BorderSpacing.Left := LedScale96(4);
          Flow.Color := clWindow;
          Flow.Parent := Box;
        end
        else if Flow <> nil then
        begin
          B := TSpeedButton.Create(FShapePop);
          B.Flat := True;
          B.Width := Sz + LedScale96(8);
          B.Height := Sz + LedScale96(8);
          B.Hint := ShapeTitle(ShapeGallery[i]);
          B.ShowHint := True;
          B.Tag := i;
          {$IFDEF LED_PARADE}
          B.Glyph := ShapeIcon(ShapeGallery[i], Sz, clBtnText);
          {$ENDIF}
          B.OnClick := @PaletteItemClicked;
          B.Parent := Flow;
        end;
    finally
      Box.EnableAutoSizing;
    end;
  end;
  P := TControl(Sender).ClientToScreen(Point(0, TControl(Sender).Height));
  FShapePop.Left := P.X;
  FShapePop.Top := P.Y;
  FShapePop.Show;
end;

procedure TLedVisualPane.PaletteDeactivate(Sender: TObject);
begin
  FShapePop.Hide;
end;

procedure TLedVisualPane.PaletteItemClicked(Sender: TObject);
begin
  FShapePop.Hide;
  FEdit.InsertShape(ShapeGallery[TControl(Sender).Tag]);
  BackToPage;
end;

procedure TLedVisualPane.CanvasClicked(Sender: TObject);
begin
  FEdit.InsertCanvas;
  BackToPage;
end;

procedure TLedVisualPane.BuildInsert;
const
  TableSizes: array[0..5] of string = ('2 x 2', '2 x 3', '3 x 3', '3 x 4', '4 x 4', '5 x 5');
  Symbols: array[0..29] of string = (
    #$C2#$A9, #$C2#$AE, #$E2#$84#$A2, #$C2#$A7, #$C2#$B6, #$C2#$B0, #$C2#$B1, #$C3#$97, #$C3#$B7, #$E2#$80#$94,
    #$E2#$80#$93, #$E2#$80#$A6, #$E2#$82#$AC, #$C2#$A3, #$C2#$A5, #$CE#$B1, #$CE#$B2, #$CE#$B3, #$CE#$B4, #$CE#$BC,
    #$CF#$80, #$CE#$A3, #$CE#$A9, #$E2#$88#$9E, #$E2#$89#$A4, #$E2#$89#$A5, #$E2#$89#$A0, #$E2#$89#$88,
    #$E2#$86#$92, #$E2#$80#$A2);
var
  i: Integer;
  M: TPopupMenu;

  function Item(AMenu: TPopupMenu; const ACaption: string; ATag: Integer; AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(AMenu);
    Result.Caption := ACaption;
    Result.Tag := ATag;
    Result.OnClick := AClick;
    AMenu.Items.Add(Result);
  end;

  { a button with a picture and a name, opening AMenu when it has one }
  function Big(const AIcon, ACaption, AHint: string; AClick: TNotifyEvent; AMenu: TPopupMenu = nil;
    ABig: Boolean = True): TSpeedButton;
  begin
    if AMenu <> nil then
    begin
      Result := AddButton(ACaption + ' ' + #$E2#$96#$BE, AHint, [], @MenuDropClicked);
      Result.Tag := PtrInt(AMenu);
    end
    else
      Result := AddButton(ACaption, AHint, [], AClick);
    if ABig then
      SetIcon(Result, AIcon)
    else
      SetSmallIcon(Result, AIcon);
  end;

begin
  { the big ones: what is put in most; the others two by two beside them }
  M := TPopupMenu.Create(Self);
  for i := 0 to High(TableSizes) do
    Item(M, TableSizes[i], i, @TableItemClicked);
  Item(M, '-', 0, nil);
  Item(M, 'Other size...', -1, @TableItemClicked);
  Big('inserttable', 'Table', 'Insert a table at the caret', nil, M);
  Big('insertpicture', 'Picture', 'Insert a picture from a file (PNG, JPEG, GIF)', @PictureClicked);
  { the shapes: what there is to put in, and what a selected one looks like -- Word's Shape Format, here }
  AddSeparator;
  BuildShape;
  AddSeparator;
  M := TPopupMenu.Create(Self);
  Item(M, 'In the line...', 0, @EquationItemClicked);
  Item(M, 'On a line of its own...', 1, @EquationItemClicked);
  Big('insertequation', 'Equation', 'An equation, written in LaTeX', nil, M);
  AddSeparator;
  BeginRows;
  Big('insertlink', 'Link', 'Make the selection a link, or insert one', @LinkClicked, nil, False);
  M := TPopupMenu.Create(Self);
  Item(M, 'Page number', PD_FIELD_PAGE, @FieldItemClicked);
  Item(M, 'Number of pages', PD_FIELD_PAGES, @FieldItemClicked);
  Item(M, 'Date', PD_FIELD_DATE, @FieldItemClicked);
  Big('insertfield', 'Field', 'A page number, the number of pages or the date, kept up to date', nil, M, False);
  NextRow;
  M := TPopupMenu.Create(Self);
  Item(M, 'Page break', PD_BREAK_PAGE, @BreakItemClicked);
  Item(M, 'Column break', PD_BREAK_COLUMN, @BreakItemClicked);
  Item(M, 'Horizontal line', PD_BREAK_RULE, @BreakItemClicked);
  Big('insertbreak', 'Break', 'A page or column break, or a horizontal line', nil, M, False);
  M := TPopupMenu.Create(Self);
  for i := 0 to High(Symbols) do
    Item(M, Symbols[i], i, @SymbolItemClicked);
  Big('insertsymbol', 'Symbol', 'A symbol the keyboard does not have', nil, M, False);
  EndRows;
  AddSeparator;
  M := TPopupMenu.Create(Self);
  Item(M, 'Check box', 0, @FormItemClicked);
  Item(M, 'Drop-down list...', 1, @FormItemClicked);
  Item(M, 'Date', 2, @FormItemClicked);
  Item(M, 'Text box', 3, @FormItemClicked);
  Big('insertform', 'Form', 'A form field Word fills in: a check box, a list to choose from, a date, a text box; ' +
    'click it on the page to tick, choose or pick', nil, M);
end;

procedure TLedVisualPane.FormItemClicked(Sender: TObject);
var
  S: string;
  L: TStringList;
  A: array of string;
  i: Integer;
begin
  case TMenuItem(Sender).Tag of
    0: FEdit.InsertControl('checkbox', []);
    1:
      begin
        S := 'Yes, No, Maybe';
        if InputQuery('Drop-down list', 'The choices, separated by commas:', S) and (Trim(S) <> '') then
        begin
          L := TStringList.Create;
          try
            L.StrictDelimiter := True;
            L.Delimiter := ',';
            L.DelimitedText := S;
            SetLength(A, 0);
            for i := 0 to L.Count - 1 do
              if Trim(L[i]) <> '' then
              begin
                SetLength(A, Length(A) + 1);
                A[High(A)] := Trim(L[i]);
              end;
            if Length(A) > 0 then
              FEdit.InsertControl('dropdown', A);
          finally
            L.Free;
          end;
        end;
      end;
    2: FEdit.InsertControl('date', []);
    3: FEdit.InsertControl('text', []);
  end;
  BackToPage;
end;

procedure TLedVisualPane.TableItemClicked(Sender: TObject);
var
  V: array of string;
  R, C: Integer;
  S: string;
begin
  if TMenuItem(Sender).Tag >= 0 then
  begin
    S := TMenuItem(Sender).Caption;      { "rows x columns" }
    R := StrToIntDef(Trim(Copy(S, 1, Pos('x', S) - 1)), 2);
    C := StrToIntDef(Trim(Copy(S, Pos('x', S) + 1, 9)), 2);
  end
  else
  begin
    SetLength(V, 2);
    V[0] := '3';
    V[1] := '3';
    if not InputQuery('Insert table', ['Rows', 'Columns'], V) then
    begin
      BackToPage;
      Exit;
    end;
    R := StrToIntDef(Trim(V[0]), 0);
    C := StrToIntDef(Trim(V[1]), 0);
    if (R < 1) or (C < 1) or (R > 500) or (C > 32) then
    begin
      MessageDlg('Insert table', 'Rows from 1 to 500, columns from 1 to 32.', mtError, [mbOK], 0);
      Exit;
    end;
  end;
  FEdit.InsertTable(R, C);
  BackToPage;
end;

procedure TLedVisualPane.PictureClicked(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(nil);
  try
    D.Title := 'Insert picture';
    D.Filter := 'Pictures (*.png;*.jpg;*.jpeg;*.gif)|*.png;*.jpg;*.jpeg;*.gif|All files|*';
    if D.Execute and not FEdit.InsertPicture(D.FileName) then
      MessageDlg('Insert picture', 'Could not read ' + D.FileName + ' as a PNG, JPEG or GIF picture.', mtError,
        [mbOK], 0);
  finally
    D.Free;
  end;
  BackToPage;
end;

procedure TLedVisualPane.LinkClicked(Sender: TObject);
var
  V: array of string;
begin
  if SelAvail then
  begin   { the selection becomes the link's text }
    SetLength(V, 1);
    V[0] := 'https://';
    if InputQuery('Link', ['Address'], V) and (Trim(V[0]) <> '') and (Trim(V[0]) <> 'https://') then
      FEdit.InsertLink(Trim(V[0]), '');
  end
  else
  begin
    SetLength(V, 2);
    V[0] := 'https://';
    V[1] := '';
    if InputQuery('Insert link', ['Address', 'Text to show (blank: the address)'], V) and (Trim(V[0]) <> '') and
       (Trim(V[0]) <> 'https://') then
      FEdit.InsertLink(Trim(V[0]), V[1]);
  end;
  BackToPage;
end;

procedure TLedVisualPane.BreakItemClicked(Sender: TObject);
begin
  FEdit.InsertBreak(TMenuItem(Sender).Tag);
  BackToPage;
end;

procedure TLedVisualPane.EquationItemClicked(Sender: TObject);
var
  S: string;
begin
  S := '';
  if InputQuery('Equation', 'The equation in LaTeX (e.g. E = mc^2, \frac{a}{b}, \sum_{i=1}^n x_i):', S) and
     (Trim(S) <> '') then
    FEdit.InsertEquation(Trim(S), TMenuItem(Sender).Tag = 1);
  BackToPage;
end;

procedure TLedVisualPane.NoteItemClicked(Sender: TObject);
var
  S: string;
begin
  S := '';
  if InputQuery(TMenuItem(Sender).Caption, 'The note''s text:', S) then
    FEdit.InsertNote(S, TMenuItem(Sender).Tag = 1);
  BackToPage;
end;

procedure TLedVisualPane.FieldItemClicked(Sender: TObject);
begin
  FEdit.InsertField(TMenuItem(Sender).Tag);
  BackToPage;
end;

procedure TLedVisualPane.SymbolItemClicked(Sender: TObject);
begin
  FEdit.InsertText(TMenuItem(Sender).Caption);
  BackToPage;
end;

{ ---- the Layout tab: the caret's section's pages, and the paragraph's exact indents and spacing ---- }

function TLedVisualPane.MenuItem(AMenu: TPopupMenu; const ACaption: string; ATag: Integer;
  AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := AClick;
  AMenu.Items.Add(Result);
end;

function TLedVisualPane.MenuButton(const AIcon, ACaption, AHint: string; AMenu: TPopupMenu;
  ABig: Boolean): TSpeedButton;
begin
  Result := AddButton(ACaption + ' ' + #$E2#$96#$BE, AHint, [], @MenuDropClicked);
  Result.Tag := PtrInt(AMenu);
  if AIcon = '' then
  else if ABig then
    SetIcon(Result, AIcon)
  else
    SetSmallIcon(Result, AIcon);
end;

function TLedVisualPane.NumberBox(const ACaption, AHint: string; AMax, AStep: Double;
  ADecimals: Integer): TFloatSpinEdit;
var
  L: TLabel;
  Box: TPanel;
begin
  { the label and its box in a panel of their own: they wrap to the next line together }
  Box := TPanel.Create(Self);
  Box.Parent := FBar;
  Box.BevelOuter := bvNone;
  Box.Caption := '';
  Box.AutoSize := True;
  Box.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  Box.ChildSizing.ControlsPerLine := 2;
  Box.ChildSizing.HorizontalSpacing := LedScale96(3);
  Box.BorderSpacing.Left := LedScale96(6);
  L := TLabel.Create(Self);
  L.Parent := Box;
  L.Caption := ACaption;
  L.Layout := tlCenter;
  L.AutoSize := False;      { the same width for all: the boxes line up in their two rows }
  L.Width := LedScale96(84);
  L.Height := LedScale96(26);
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := Box;
  Result.Width := LedScale96(64);
  Result.Constraints.MinWidth := LedScale96(64);
  Result.MinValue := 0;
  Result.MaxValue := AMax;
  Result.Increment := AStep;
  Result.DecimalPlaces := ADecimals;
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.BorderSpacing.Around := LedScale96(1);
  Result.OnEditingDone := @ParaBoxChanged;
end;

procedure TLedVisualPane.BuildLayout;
var
  M, LnMenu: TPopupMenu;
begin
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Normal (1" all round)', 0, @MarginsItemClicked);
  MenuItem(M, 'Narrow (0.5")', 1, @MarginsItemClicked);
  MenuItem(M, 'Moderate (1" top and bottom, 0.75" sides)', 2, @MarginsItemClicked);
  MenuItem(M, 'Wide (1" top and bottom, 2" sides)', 3, @MarginsItemClicked);
  MenuItem(M, '-', 0, nil);
  MenuItem(M, 'Custom margins...', -1, @MarginsItemClicked);
  MenuButton('margins', 'Margins', 'The page''s margins (this section)', M);
  M := TPopupMenu.Create(Self);
  FPortraitItem := MenuItem(M, 'Portrait', 0, @OrientationItemClicked);
  FLandscapeItem := MenuItem(M, 'Landscape', 1, @OrientationItemClicked);
  FPortraitItem.RadioItem := True;
  FLandscapeItem.RadioItem := True;
  MenuButton('orientation', 'Orientation', 'Portrait or landscape (this section)', M);
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Letter (8.5" x 11")', 0, @SizeItemClicked);
  MenuItem(M, 'Legal (8.5" x 14")', 1, @SizeItemClicked);
  MenuItem(M, 'Tabloid (11" x 17")', 2, @SizeItemClicked);
  MenuItem(M, 'Executive (7.25" x 10.5")', 3, @SizeItemClicked);
  MenuItem(M, 'A3 (297 x 420 mm)', 4, @SizeItemClicked);
  MenuItem(M, 'A4 (210 x 297 mm)', 5, @SizeItemClicked);
  MenuItem(M, 'A5 (148 x 210 mm)', 6, @SizeItemClicked);
  MenuButton('pagesize', 'Size', 'The paper (this section)', M);
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'One', 1, @ColumnsItemClicked);
  MenuItem(M, 'Two', 2, @ColumnsItemClicked);
  MenuItem(M, 'Three', 3, @ColumnsItemClicked);
  MenuButton('columns', 'Columns', 'Text in columns (this section)', M);
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Page break', 0, @LayoutBreakItemClicked);
  MenuItem(M, 'Column break', 1, @LayoutBreakItemClicked);
  MenuItem(M, '-', 0, nil);
  MenuItem(M, 'Section break, next page', 2, @LayoutBreakItemClicked);
  MenuItem(M, 'Section break, continuous', 3, @LayoutBreakItemClicked);
  AddSeparator;
  BeginRows;
  MenuButton('insertbreak', 'Breaks', 'A page or column break, or a new section with page settings of its own', M, False);
  NextRow;
  LnMenu := TPopupMenu.Create(Self);
  MenuItem(LnMenu, 'None', 0, @LineNumberItemClicked);
  MenuItem(LnMenu, 'Every line', 1, @LineNumberItemClicked);
  MenuItem(LnMenu, 'Every 5 lines', 5, @LineNumberItemClicked);
  MenuButton('linenumbers', 'Line numbers', 'Lines numbered in the margin', LnMenu, False);
  EndRows;
  AddSeparator;
  BeginRows;
  SetSmallIcon(AddButton('Header...', 'The text at the top of every page; {page}, {pages} and {date} are kept up to date',
    [], @HeaderClicked), 'header');
  NextRow;
  SetSmallIcon(AddButton('Footer...', 'The text at the bottom of every page; {page}, {pages} and {date} are kept up to date',
    [], @FooterClicked), 'footer');
  EndRows;
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Bottom of the page, centred', 0, @PageNumberItemClicked);
  MenuItem(M, '"Page N of M" at the bottom', 1, @PageNumberItemClicked);
  MenuItem(M, 'Top of the page, right', 2, @PageNumberItemClicked);
  MenuItem(M, '-', 0, nil);
  MenuItem(M, 'Start at...', 3, @PageNumberItemClicked);
  MenuItem(M, 'Remove', 4, @PageNumberItemClicked);
  MenuButton('pagenumbers', 'Page numbers', 'Page numbers in the header or footer', M);
  AddSeparator;
  BeginRows;
  FIndentLeft := NumberBox('Indent left', 'The paragraph''s left indent, in inches', 10, 0.25, 2);
  FSpaceBefore := NumberBox('Space before', 'Space before the paragraph, in points', 500, 6, 0);
  NextRow;
  FIndentRight := NumberBox('Indent right', 'The paragraph''s right indent, in inches', 10, 0.25, 2);
  FSpaceAfter := NumberBox('Space after', 'Space after the paragraph, in points', 500, 6, 0);
  EndRows;
end;

procedure TLedVisualPane.MarginsItemClicked(Sender: TObject);
const
  Sets: array[0..3, 0..3] of Double = ((72, 72, 72, 72), (36, 36, 36, 36), (72, 72, 54, 54), (72, 72, 144, 144));
var
  V: array of string;
  P: pd_section_props;
  i: Integer;
  T: array[0..3] of Double;
begin
  i := TMenuItem(Sender).Tag;
  if i >= 0 then
    FEdit.SetMargins(Sets[i, 0], Sets[i, 1], Sets[i, 2], Sets[i, 3])
  else
  begin
    P := FEdit.CurrentSectionProps;
    SetLength(V, 4);
    V[0] := FormatFloat('0.##', P.margin_top / PD_SP_PER_PT / 72);
    V[1] := FormatFloat('0.##', P.margin_bottom / PD_SP_PER_PT / 72);
    V[2] := FormatFloat('0.##', P.margin_left / PD_SP_PER_PT / 72);
    V[3] := FormatFloat('0.##', P.margin_right / PD_SP_PER_PT / 72);
    if InputQuery('Margins', ['Top (inches)', 'Bottom', 'Left', 'Right'], V) then
    begin
      for i := 0 to 3 do
        if not TryStrToFloat(Trim(V[i]), T[i]) or (T[i] < 0) or (T[i] > 10) then
        begin
          MessageDlg('Margins', 'Margins are inches from 0 to 10.', mtError, [mbOK], 0);
          Exit;
        end;
      FEdit.SetMargins(T[0] * 72, T[1] * 72, T[2] * 72, T[3] * 72);
    end;
  end;
  BackToPage;
end;

procedure TLedVisualPane.OrientationItemClicked(Sender: TObject);
begin
  FEdit.SetOrientation(TMenuItem(Sender).Tag = 1);
  BackToPage;
end;

procedure TLedVisualPane.SizeItemClicked(Sender: TObject);
const
  MM = 72 / 25.4;
  Sizes: array[0..6, 0..1] of Double = ((612, 792), (612, 1008), (792, 1224), (522, 756), (297 * MM, 420 * MM),
    (210 * MM, 297 * MM), (148 * MM, 210 * MM));
begin
  FEdit.SetPageSize(Sizes[TMenuItem(Sender).Tag, 0], Sizes[TMenuItem(Sender).Tag, 1]);
  BackToPage;
end;

procedure TLedVisualPane.ColumnsItemClicked(Sender: TObject);
begin
  FEdit.SetColumns(TMenuItem(Sender).Tag);
  BackToPage;
end;

procedure TLedVisualPane.LayoutBreakItemClicked(Sender: TObject);
begin
  case TMenuItem(Sender).Tag of
    0: FEdit.InsertBreak(PD_BREAK_PAGE);
    1: FEdit.InsertBreak(PD_BREAK_COLUMN);
    2: FEdit.InsertSectionBreak(False);
    3: FEdit.InsertSectionBreak(True);
  end;
  BackToPage;
end;

procedure TLedVisualPane.EditHeaderFooter(AFooter: Boolean);
var
  V: array of string;
  A: Integer;
  S: string;
begin
  SetLength(V, 2);
  V[0] := FEdit.HeaderFooterText(AFooter);
  if AFooter then V[1] := 'centre' else V[1] := 'left';
  if AFooter then S := 'Footer' else S := 'Header';
  if not InputQuery(S, [S + ' text ({page}, {pages} and {date} are filled in; blank: none)',
    'Alignment (left, centre, right)'], V) then
  begin
    BackToPage;
    Exit;
  end;
  S := LowerCase(Trim(V[1]));
  if (S = 'right') or (S = 'r') then A := PD_ALIGN_RIGHT
  else if (S = 'left') or (S = 'l') then A := PD_ALIGN_LEFT
  else A := PD_ALIGN_CENTER;
  FEdit.SetHeaderFooter(AFooter, V[0], A);
  BackToPage;
end;

procedure TLedVisualPane.HeaderClicked(Sender: TObject);
begin
  EditHeaderFooter(False);
end;

procedure TLedVisualPane.FooterClicked(Sender: TObject);
begin
  EditHeaderFooter(True);
end;

procedure TLedVisualPane.PageNumberItemClicked(Sender: TObject);
var
  S: string;
  N: Integer;
begin
  case TMenuItem(Sender).Tag of
    0: FEdit.SetHeaderFooter(True, '{page}', PD_ALIGN_CENTER);
    1: FEdit.SetHeaderFooter(True, 'Page {page} of {pages}', PD_ALIGN_CENTER);
    2: FEdit.SetHeaderFooter(False, '{page}', PD_ALIGN_RIGHT);
    3:
      begin
        S := IntToStr(Max(1, FEdit.CurrentSectionProps.first_page_number));
        if InputQuery('Page numbers', 'The first page of this section is number:', S) then
        begin
          N := StrToIntDef(Trim(S), -1);
          if N >= 1 then
            FEdit.SetFirstPageNumber(N);
        end;
      end;
    4:
      begin   { only a header or footer that is just the page number goes }
        if Pos('{page}', FEdit.HeaderFooterText(True)) > 0 then
          FEdit.SetHeaderFooter(True, '');
        if FEdit.HeaderFooterText(False) = '{page}' then
          FEdit.SetHeaderFooter(False, '');
      end;
  end;
  BackToPage;
end;

procedure TLedVisualPane.LineNumberItemClicked(Sender: TObject);
begin
  FEdit.SetLineNumbers(TMenuItem(Sender).Tag);
  BackToPage;
end;

procedure TLedVisualPane.ParaBoxChanged(Sender: TObject);
var
  P: pd_para_props;
begin
  if FUpdating then Exit;
  FillChar(P, SizeOf(P), 0);
  if Sender = FIndentLeft then
  begin
    P.mask := PD_PP_INDENT_LEFT;
    P.indent_left := Round(FIndentLeft.Value * 72 * PD_SP_PER_PT);
  end
  else if Sender = FIndentRight then
  begin
    P.mask := PD_PP_INDENT_RIGHT;
    P.indent_right := Round(FIndentRight.Value * 72 * PD_SP_PER_PT);
  end
  else if Sender = FSpaceBefore then
  begin
    P.mask := PD_PP_SPACE_BEFORE;
    P.space_before := Round(FSpaceBefore.Value * PD_SP_PER_PT);
  end
  else if Sender = FSpaceAfter then
  begin
    P.mask := PD_PP_SPACE_AFTER;
    P.space_after := Round(FSpaceAfter.Value * PD_SP_PER_PT);
  end;
  { only when it differs: leaving the box unchanged is not an edit }
  with FEdit.CurrentParaProps do
    if ((P.mask = PD_PP_INDENT_LEFT) and (indent_left = P.indent_left)) or
       ((P.mask = PD_PP_INDENT_RIGHT) and (indent_right = P.indent_right)) or
       ((P.mask = PD_PP_SPACE_BEFORE) and (space_before = P.space_before)) or
       ((P.mask = PD_PP_SPACE_AFTER) and (space_after = P.space_after)) then
      Exit;
  FEdit.ApplyParaProps(P);
end;

{ ---- the Table tab: shown while the caret is in a table ---- }

procedure TLedVisualPane.BuildTable;
const
  Shades: array[0..6] of Integer = ($D9E2F3, $E2EFD9, $FFF2CC, $FBE4D5, $EDEDED, $BDD7EE, $C5E0B3);
  ShadeNames: array[0..6] of string = ('Light blue', 'Light green', 'Light yellow', 'Light orange', 'Light grey',
    'Blue', 'Green');
var
  M: TPopupMenu;
  i: Integer;
begin
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Row above', 0, @TableInsertItemClicked);
  MenuItem(M, 'Row below', 1, @TableInsertItemClicked);
  MenuItem(M, 'Column left', 2, @TableInsertItemClicked);
  MenuItem(M, 'Column right', 3, @TableInsertItemClicked);
  MenuButton('tblinsert', 'Insert', 'A row or column next to the caret''s cell', M);
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Row', 0, @TableDeleteItemClicked);
  MenuItem(M, 'Column', 1, @TableDeleteItemClicked);
  MenuItem(M, 'Table', 2, @TableDeleteItemClicked);
  MenuButton('tbldelete', 'Delete', 'The caret''s row or column, or the whole table', M);
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'With the cell to the right', 0, @TableMergeItemClicked);
  MenuItem(M, 'With the cell below', 1, @TableMergeItemClicked);
  MenuItem(M, '-', 0, nil);
  MenuItem(M, 'Split the merged cell', 2, @TableMergeItemClicked);
  BeginRows;
  MenuButton('tblmerge', 'Merge', 'Join cells into one, or split one back', M, False);
  NextRow;
  FHeaderRowBtn := AddToggle('Header row', 'Repeat the first row at the top of every page the table runs onto', [],
    @HeaderRowClicked);
  SetSmallIcon(FHeaderRowBtn, 'headerrow');
  EndRows;
  AddSeparator;
  BeginRows;
  M := TPopupMenu.Create(Self);
  for i := 0 to High(Shades) do
    Swatch(MenuItem(M, ShadeNames[i], Shades[i], @ShadingItemClicked), FromRGB(Shades[i]), False);
  MenuItem(M, '-', 0, nil);
  Swatch(MenuItem(M, 'No shading', -1, @ShadingItemClicked), clWhite, True);
  MenuButton('shading', 'Shading', 'A colour behind the selected cells', M, False);
  NextRow;
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'None', 0, @BordersItemClicked);
  MenuItem(M, 'Thin (0.5 pt)', 5, @BordersItemClicked);
  MenuItem(M, 'Medium (1 pt)', 10, @BordersItemClicked);
  MenuItem(M, 'Thick (1.5 pt)', 15, @BordersItemClicked);
  MenuButton('borders', 'Borders', 'The table''s rules', M, False);
  EndRows;
  SetIcon(AddButton('Distribute columns', 'Every column as wide as the others', [], @DistributeClicked), 'distribute');
end;

function TLedVisualPane.ShapeTabShown: Boolean;
begin
  Result := (FShapeTab >= 0) and FBars[FShapeTab].Visible and FShapeSel;
end;

const
  { a new shape's fill and outline: Office's accents, each outlined a shade darker }
  Themes: array[0..8, 0..1] of Integer = (($4472C4, $2F528F), ($ED7D31, $AE5A21), ($A5A5A5, $787878),
    ($FFC000, $BC8C00), ($5B9BD5, $41719C), ($70AD47, $507E32), ($C00000, $8C0000), ($7030A0, $4E2270),
    ($FFFFFF, $000000));
  { the Outline menu's dashes and arrowheads: caption, dash, head, tail ('' as it is) }
  LineStyles: array[0..12, 0..3] of string = (
    ('Solid', 'solid', '', ''), ('Dashed', 'dash', '', ''), ('Dotted', 'sysDot', '', ''),
    ('Dash-dot', 'dashDot', '', ''), ('Long dashes', 'lgDash', '', ''), ('-', '', '', ''),
    ('No arrowheads', '', 'none', 'none'), ('Arrow at the end', '', 'none', 'triangle'),
    ('Arrow at the start', '', 'triangle', 'none'), ('Arrows at both ends', '', 'triangle', 'triangle'),
    ('Open arrow at the end', '', 'none', 'arrow'), ('Dot at the start, arrow at the end', '', 'oval', 'triangle'),
    ('Diamond at the end', '', 'none', 'diamond'));
  ThemeNames: array[0..8] of string = ('Blue', 'Orange', 'Grey', 'Gold', 'Light blue', 'Green', 'Dark red', 'Purple',
    'White, outlined black');

{ the Insert tab's shapes: what is drawn in a canvas, and a shape's fill and outline, its turn, its points, its place
  in the order, groups -- what Word's Shape Format has first }
procedure TLedVisualPane.BuildShape;
const
  Colours: array[0..9] of Integer = ($FFFFFF, $000000, $4472C4, $ED7D31, $A5A5A5, $FFC000, $5B9BD5, $70AD47,
    $C00000, $7030A0);
  ColourNames: array[0..9] of string = ('White', 'Black', 'Blue', 'Orange', 'Grey', 'Gold', 'Light blue', 'Green',
    'Dark red', 'Purple');
var
  M: TPopupMenu;
  i, First: Integer;
begin
  SetIcon(AddButton('Shapes ' + #$E2#$96#$BE, 'A shape: in a new canvas, or drawn with the mouse in the canvas ' +
    'selected', [], @ShapesDropClicked), 'insertshape');
  SetIcon(AddButton('Canvas', 'A drawing canvas: shapes, lines, arrows and text boxes drawn in it make a diagram',
    [], @CanvasClicked), 'insertcanvas');
  First := FBar.ControlCount;
  M := TPopupMenu.Create(Self);
  for i := 0 to High(Colours) do
    Swatch(MenuItem(M, ColourNames[i], Colours[i], @ShapeFillItemClicked), FromRGB(Colours[i]), False);
  MenuItem(M, 'More colours...', -2, @ShapeFillItemClicked);
  MenuItem(M, '-', 0, nil);
  Swatch(MenuItem(M, 'No fill', -1, @ShapeFillItemClicked), clWhite, True);
  MenuButton('shading', 'Fill', 'The colour inside the selected shape', M);
  M := TPopupMenu.Create(Self);
  for i := 0 to High(Colours) do
    Swatch(MenuItem(M, ColourNames[i], Colours[i], @ShapeLineItemClicked), FromRGB(Colours[i]), False);
  MenuItem(M, 'More colours...', -2, @ShapeLineItemClicked);
  MenuItem(M, '-', 0, nil);
  MenuItem(M, 'Thin (0.75 pt)', -75, @ShapeLineItemClicked);
  MenuItem(M, 'Medium (1.5 pt)', -150, @ShapeLineItemClicked);
  MenuItem(M, 'Thick (3 pt)', -300, @ShapeLineItemClicked);
  MenuItem(M, '-', 0, nil);
  for i := 0 to High(LineStyles) do
    if LineStyles[i, 0] = '-' then
      MenuItem(M, '-', 0, nil)
    else
      MenuItem(M, LineStyles[i, 0], i, @ShapeLineStyleItemClicked);
  MenuItem(M, '-', 0, nil);
  Swatch(MenuItem(M, 'No outline', -1, @ShapeLineItemClicked), clWhite, True);
  MenuButton('borders', 'Outline', 'The selected shape''s line: its colour, width, dashes and arrowheads', M);
  M := TPopupMenu.Create(Self);
  for i := 0 to High(Themes) do
    Swatch(MenuItem(M, ThemeNames[i], i, @ShapeThemeItemClicked), FromRGB(Themes[i, 0]), False);
  MenuButton('shapetheme', 'Colours', 'The colours new shapes are drawn in (and the selected shape, recoloured)', M);
  AddSeparator;
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Rotate right 90' + #$C2#$B0, 0, @ShapeRotateItemClicked);
  MenuItem(M, 'Rotate left 90' + #$C2#$B0, 1, @ShapeRotateItemClicked);
  MenuItem(M, '-', 0, nil);
  MenuItem(M, 'Flip horizontal', 2, @ShapeRotateItemClicked);
  MenuItem(M, 'Flip vertical', 3, @ShapeRotateItemClicked);
  MenuItem(M, '-', 0, nil);
  MenuItem(M, 'No rotation', 4, @ShapeRotateItemClicked);
  MenuButton('rotate', 'Rotate', 'Turn or flip the selected shape (or drag its round handle; Shift: by 15' +
    #$C2#$B0 + ')', M);
  SetIcon(AddButton('Edit Points', 'The selected shape''s outline as points to drag (or double-click the shape)', [],
    @EditPointsClicked), 'editpoints');
  SetIcon(AddButton('Add Text', 'Text typed in the selected shape (or just start typing with it selected)', [],
    @AddTextClicked), 'shapetext');
  AddSeparator;
  BeginRows;
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Bring forward', 0, @ShapeOrderItemClicked);
  MenuItem(M, 'Bring to front', 2, @ShapeOrderItemClicked);
  MenuItem(M, '-', 0, nil);
  MenuItem(M, 'Send backward', 1, @ShapeOrderItemClicked);
  MenuItem(M, 'Send to back', 3, @ShapeOrderItemClicked);
  MenuButton('arrange', 'Arrange', 'Which shapes the selected one is drawn over', M, False);
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Align left', 0, @ShapeAlignItemClicked);
  MenuItem(M, 'Align centre', 1, @ShapeAlignItemClicked);
  MenuItem(M, 'Align right', 2, @ShapeAlignItemClicked);
  MenuItem(M, '-', 0, nil);
  MenuItem(M, 'Align top', 3, @ShapeAlignItemClicked);
  MenuItem(M, 'Align middle', 4, @ShapeAlignItemClicked);
  MenuItem(M, 'Align bottom', 5, @ShapeAlignItemClicked);
  MenuItem(M, '-', 0, nil);
  MenuItem(M, 'Distribute horizontally', 6, @ShapeAlignItemClicked);
  MenuItem(M, 'Distribute vertically', 7, @ShapeAlignItemClicked);
  MenuButton('alignshapes', 'Align', 'The selected shapes lined up or spread out evenly (one shape: along its ' +
    'canvas; a rubber band or Shift+click selects more)', M, False);
  NextRow;
  SetSmallIcon(AddButton('Group', 'The selected shapes (Shift+click for more) made one', [], @GroupClicked), 'group');
  AddButton('Ungroup', 'The group the selected shape is in taken apart', [], @UngroupClicked);
  EndRows;
  { what is for a selected shape: off until there is one (Colours is for new shapes too) }
  for i := First to FBar.ControlCount - 1 do
    if not ((FBar.Controls[i] is TSpeedButton) and (Pos('Colours', TSpeedButton(FBar.Controls[i]).Caption) = 1)) then
    begin
      SetLength(FShapeFmt, Length(FShapeFmt) + 1);
      FShapeFmt[High(FShapeFmt)] := FBar.Controls[i];
      FBar.Controls[i].Enabled := False;
    end;
end;

{ a colour from the system's dialog, starting at AColour; False when it was closed without one }
function TLedVisualPane.PickColour(var AColour: TColor): Boolean;
var
  D: TColorDialog;
begin
  D := TColorDialog.Create(nil);
  try
    D.Color := AColour;
    Result := D.Execute;
    if Result then
      AColour := D.Color;
  finally
    D.Free;
  end;
end;

procedure TLedVisualPane.ShapeFillItemClicked(Sender: TObject);
var
  C: TColor;
begin
  if TMenuItem(Sender).Tag = -2 then
  begin
    C := FEdit.ShapeFillColor;
    if PickColour(C) then
      FEdit.SetShapeFill(C, False);
  end
  else
    FEdit.SetShapeFill(FromRGB(Max(0, TMenuItem(Sender).Tag)), TMenuItem(Sender).Tag = -1);
  BackToPage;
end;

procedure TLedVisualPane.ShapeRotateItemClicked(Sender: TObject);
var
  G: TParadeShapeGeom;
begin
  case TMenuItem(Sender).Tag of
    0, 1:
      if FEdit.SelectedShapeGeom(G) then
        FEdit.RotateShape(G.Rot + IfThen(TMenuItem(Sender).Tag = 0, 90, -90));
    2: FEdit.FlipShape(True);
    3: FEdit.FlipShape(False);
    4: FEdit.RotateShape(0);
  end;
  BackToPage;
end;

{ the colours new shapes are drawn in, remembered; the selected shape recoloured with them }
procedure TLedVisualPane.ShapeThemeItemClicked(Sender: TObject);
var
  T: Integer;
  At: pd_pos;
  Sid: Integer;
begin
  T := TMenuItem(Sender).Tag;
  FEdit.ShapeFillColor := FromRGB(Themes[T, 0]);
  FEdit.ShapeLineColor := FromRGB(Themes[T, 1]);
  LedPrefs.SetInt(LedPrefShapeTheme, T);
  if FEdit.SelectedShape(At, Sid) then
    FEdit.SetShapeStyle(FEdit.ShapeFillColor, FEdit.ShapeLineColor);
  BackToPage;
end;

procedure TLedVisualPane.AddTextClicked(Sender: TObject);
begin
  FEdit.AddShapeText;
  BackToPage;
end;

procedure TLedVisualPane.ShapeAlignItemClicked(Sender: TObject);
begin
  case TMenuItem(Sender).Tag of
    6: FEdit.DistributeShapes(True);
    7: FEdit.DistributeShapes(False);
  else
    FEdit.AlignShapes(TMenuItem(Sender).Tag);
  end;
  BackToPage;
end;

procedure TLedVisualPane.ShapeLineStyleItemClicked(Sender: TObject);
var
  i: Integer;
begin
  i := TMenuItem(Sender).Tag;
  FEdit.SetShapeLineStyle(LineStyles[i, 1], LineStyles[i, 2], LineStyles[i, 3]);
  BackToPage;
end;

procedure TLedVisualPane.EditPointsClicked(Sender: TObject);
begin
  FEdit.EditShapePoints;
  BackToPage;
end;

{ a colour (the tag, an RGB), a width (minus hundredths of a point), or none (-1) }
procedure TLedVisualPane.ShapeLineItemClicked(Sender: TObject);
var
  T: Integer;
  C: TColor;
begin
  T := TMenuItem(Sender).Tag;
  if T = -2 then
  begin
    C := FEdit.ShapeLineColor;
    if PickColour(C) then
      FEdit.SetShapeLine(C, 0, False);
  end
  else if T = -1 then
    FEdit.SetShapeLine(clBlack, 0, True)
  else if T < 0 then
    FEdit.SetShapeLine(clNone, -T / 100, False)
  else
    FEdit.SetShapeLine(FromRGB(T), 0, False);
  BackToPage;
end;

procedure TLedVisualPane.ShapeOrderItemClicked(Sender: TObject);
begin
  FEdit.ShapeOrder(TMenuItem(Sender).Tag);
  BackToPage;
end;

procedure TLedVisualPane.GroupClicked(Sender: TObject);
begin
  FEdit.GroupShapes;
  BackToPage;
end;

procedure TLedVisualPane.UngroupClicked(Sender: TObject);
begin
  FEdit.UngroupShape;
  BackToPage;
end;

procedure TLedVisualPane.TableInsertItemClicked(Sender: TObject);
begin
  case TMenuItem(Sender).Tag of
    0: FEdit.TableInsertRow(False);
    1: FEdit.TableInsertRow(True);
    2: FEdit.TableInsertColumn(False);
    3: FEdit.TableInsertColumn(True);
  end;
  BackToPage;
end;

procedure TLedVisualPane.TableDeleteItemClicked(Sender: TObject);
begin
  case TMenuItem(Sender).Tag of
    0: FEdit.TableDeleteRow;
    1: FEdit.TableDeleteColumn;
    2: FEdit.TableDelete;
  end;
  BackToPage;
end;

procedure TLedVisualPane.TableMergeItemClicked(Sender: TObject);
begin
  case TMenuItem(Sender).Tag of
    0: FEdit.TableMergeRight;
    1: FEdit.TableMergeDown;
    2: FEdit.TableSplitCell;
  end;
  BackToPage;
end;

procedure TLedVisualPane.ShadingItemClicked(Sender: TObject);
begin
  FEdit.SetCellShading(TMenuItem(Sender).Tag);
  BackToPage;
end;

procedure TLedVisualPane.BordersItemClicked(Sender: TObject);
begin
  FEdit.SetTableBorders(TMenuItem(Sender).Tag / 10);
  BackToPage;
end;

procedure TLedVisualPane.HeaderRowClicked(Sender: TObject);
begin
  FEdit.SetHeaderRow(FEdit.CurrentTableProps.header_rows = 0);
  FHeaderRowBtn.Down := FEdit.CurrentTableProps.header_rows > 0;
  BackToPage;
end;

procedure TLedVisualPane.DistributeClicked(Sender: TObject);
begin
  FEdit.DistributeColumns;
  BackToPage;
end;

{ ---- the References tab ---- }

procedure TLedVisualPane.BuildReferences;
var
  M: TPopupMenu;
begin
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Insert (headings 1-3)', 3, @TocItemClicked);
  MenuItem(M, 'Insert (headings 1-2)', 2, @TocItemClicked);
  MenuItem(M, '-', 0, nil);
  MenuItem(M, 'Update table', 0, @TocItemClicked);
  MenuButton('toc', 'Table of contents', 'A table of contents of the headings, with their pages', M);
  AddSeparator;
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Footnote...', 0, @NoteItemClicked);
  MenuItem(M, 'Endnote...', 1, @NoteItemClicked);
  MenuButton('insertnote', 'Note', 'A footnote or an endnote at the caret', M);
  M := TPopupMenu.Create(Self);
  MenuItem(M, 'Figure...', 0, @CaptionItemClicked);
  MenuItem(M, 'Table...', 1, @CaptionItemClicked);
  MenuItem(M, 'Equation...', 2, @CaptionItemClicked);
  MenuButton('caption', 'Caption', 'A numbered caption under the caret''s paragraph: Figure 1, Table 1, ...', M);
  BeginRows;
  SetSmallIcon(AddButton('Cross-reference...', 'A reference to a caption or heading: its number, page or text, kept up to date',
    [], @CrossRefClicked), 'crossref');
  NextRow;
  SetSmallIcon(AddButton('Bookmark...', 'A named place, for links to #name', [], @BookmarkClicked), 'bookmark');
  EndRows;
end;

procedure TLedVisualPane.TocItemClicked(Sender: TObject);
begin
  if TMenuItem(Sender).Tag = 0 then
  begin
    if not FEdit.UpdateTableOfContents then
      MessageDlg('Table of contents', 'This document has no table of contents yet.', mtInformation, [mbOK], 0);
  end
  else
    FEdit.InsertTableOfContents(TMenuItem(Sender).Tag);
  BackToPage;
end;

procedure TLedVisualPane.CaptionItemClicked(Sender: TObject);
const
  Seqs: array[0..2] of string = ('Figure', 'Table', 'Equation');
var
  S: string;
begin
  S := '';
  if InputQuery(Seqs[TMenuItem(Sender).Tag] + ' caption',
    'The caption''s text, after "' + Seqs[TMenuItem(Sender).Tag] + ' N: " (blank: the number alone):', S) then
    FEdit.InsertCaption(Seqs[TMenuItem(Sender).Tag], Trim(S));
  BackToPage;
end;

procedure TLedVisualPane.CrossRefClicked(Sender: TObject);
var
  F: TForm;
  L: TListBox;
  R: TRadioGroup;
  P: TPanel;
  B: TButton;
  T: TParadeRefTargets;
  i: Integer;
begin
  T := FEdit.ReferenceTargets;
  if T = nil then
  begin
    MessageDlg('Cross-reference', 'There is nothing to refer to yet: add captions (References > Caption) or ' +
      'headings first.', mtInformation, [mbOK], 0);
    Exit;
  end;
  F := TForm.CreateNew(nil);
  try
    F.Caption := 'Cross-reference';
    F.Position := poMainFormCenter;
    F.SetBounds(0, 0, LedScale96(520), LedScale96(400));
    R := TRadioGroup.Create(F);
    R.Parent := F;
    R.Align := alTop;
    R.Caption := 'Insert';
    R.Columns := 2;
    R.Items.Add('Its label and number ("Figure 2")');
    R.Items.Add('Its number alone');
    R.Items.Add('Its page number');
    R.Items.Add('Its text');
    R.ItemIndex := 0;
    R.AutoSize := True;
    P := TPanel.Create(F);
    P.Parent := F;
    P.Align := alBottom;
    P.BevelOuter := bvNone;
    P.AutoSize := True;
    B := TButton.Create(F);
    B.Parent := P;
    B.Align := alRight;
    B.Caption := 'Cancel';
    B.ModalResult := mrCancel;
    B.Cancel := True;
    B := TButton.Create(F);
    B.Parent := P;
    B.Align := alRight;
    B.Caption := 'Insert';
    B.ModalResult := mrOK;
    B.Default := True;
    L := TListBox.Create(F);
    L.Parent := F;
    L.Align := alClient;
    for i := 0 to High(T) do
      if T[i].IsCaption then
        L.Items.Add(T[i].Text)
      else
        L.Items.Add(StringOfChar(' ', 3 * Max(0, T[i].Level - 1)) + T[i].Text + '   (heading)');
    L.ItemIndex := 0;
    if (F.ShowModal = mrOK) and (L.ItemIndex >= 0) then
      FEdit.InsertCrossReference(T[L.ItemIndex], TParadeRefWhat(R.ItemIndex));
  finally
    F.Free;
  end;
  BackToPage;
end;

procedure TLedVisualPane.BookmarkClicked(Sender: TObject);
var
  S: string;
  i: Integer;
begin
  S := '';
  if InputQuery('Bookmark', 'The place''s name (letters, digits, _ and -; a link to it is #name):', S) then
  begin
    S := Trim(S);
    for i := 1 to Length(S) do
      if not (S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
        S[i] := '_';
    if S <> '' then
      FEdit.InsertBookmark(Copy(S, 1, 31));
  end;
  BackToPage;
end;

{ ---- the View tab ---- }

procedure TLedVisualPane.BuildView;
const
  Zooms: array[0..7] of string = ('50%', '75%', '100%', '125%', '150%', '200%', 'Page width', 'Whole page');
var
  i: Integer;
begin
  BeginRows;
  FZoomBox := TComboBox.Create(Self);
  FZoomBox.Parent := FBar;
  FZoomBox.Style := csDropDown;
  FZoomBox.Width := LedScale96(100);
  FZoomBox.Constraints.MinWidth := LedScale96(100);
  FZoomBox.Constraints.MaxWidth := LedScale96(100);
  FZoomBox.Hint := 'Zoom (also Ctrl+wheel)';
  FZoomBox.ShowHint := True;
  for i := 0 to High(Zooms) do
    FZoomBox.Items.Add(Zooms[i]);
  FZoomBox.Text := '100%';
  FZoomBox.OnSelect := @ZoomChosen;
  FZoomBox.OnKeyDown := @ZoomKeyDown;
  FZoomBox.BorderSpacing.Around := LedScale96(1);
  NextRow;
  AddIconButton('zoomout', 'Zoom out', @ZoomOutClicked);
  AddIconButton('zoomin', 'Zoom in', @ZoomInClicked);
  EndRows;
  AddSeparator;
  BeginRows;
  FMarksBtn := AddToggle('Marks', 'Show formatting marks: where each paragraph ends', [], @MarksClicked);
  SetSmallIcon(FMarksBtn, 'formatmarks');
  NextRow;
  FNavBtn := AddToggle('Navigation', 'A list of the headings beside the page: click one to go there', [],
    @NavClicked);
  SetSmallIcon(FNavBtn, 'navigation');
  EndRows;

  { the navigation list, hidden until asked for }
  FNavPanel := TPanel.Create(Self);
  FNavPanel.Parent := Self;
  FNavPanel.Align := alLeft;
  FNavPanel.Width := LedScale96(200);
  FNavPanel.BevelOuter := bvNone;
  FNavPanel.Caption := '';
  FNavPanel.Visible := False;
  FNavList := TListBox.Create(Self);
  FNavList.Parent := FNavPanel;
  FNavList.Align := alClient;
  FNavList.OnClick := @NavListClicked;
  FNavSplitter := TSplitter.Create(Self);
  FNavSplitter.Parent := Self;
  FNavSplitter.Align := alLeft;
  FNavSplitter.Left := FNavPanel.Width + 1;
  FNavSplitter.Visible := False;
  FNavTimer := TTimer.Create(Self);
  FNavTimer.Enabled := False;
  FNavTimer.Interval := 400;      { the list made again a little after the typing stops }
  FNavTimer.OnTimer := @NavTimerFired;
end;

{ the page as wide as the view, while that is the zoom the reader has; a zoom chosen another way ends it }
procedure TLedVisualPane.FitWidth;
var
  Z: Double;
begin
  if not FFitWidth or (FEdit = nil) or (FEdit.PageCount = 0) or (FEdit.ClientWidth < 50) then Exit;
  if (FFitZoom <> 0) and (Abs(FEdit.Zoom - FFitZoom) > 1e-6) then
  begin   { Ctrl+wheel moved it }
    FFitWidth := False;
    Exit;
  end;
  Z := FEdit.PageWidthZoom;
  if Z <= 0 then Exit;
  FEdit.Zoom := Z;
  FFitZoom := FEdit.Zoom;     { as the editor kept it, within its limits }
  if FZoomBox <> nil then
    ShowZoom;
end;

procedure TLedVisualPane.EditResized(Sender: TObject);
begin
  FitWidth;
end;

procedure TLedVisualPane.ShowZoom;
begin
  if not FZoomBox.Focused then
    FZoomBox.Text := IntToStr(Round(FEdit.Zoom * 100)) + '%';
end;

procedure TLedVisualPane.ZoomChosen(Sender: TObject);
var
  S: string;
  V: Double;
begin
  if FZoomBox.ItemIndex >= 0 then
    S := FZoomBox.Items[FZoomBox.ItemIndex]
  else
    S := Trim(FZoomBox.Text);
  FFitWidth := S = 'Page width';
  FFitZoom := 0;
  if FFitWidth then
    FitWidth
  else if S = 'Whole page' then
    FEdit.Zoom := FEdit.WholePageZoom
  else if TryStrToFloat(Trim(StringReplace(S, '%', '', [])), V) and (V >= 10) and (V <= 600) then
    FEdit.Zoom := V / 100;
  FZoomBox.ItemIndex := -1;
  BackToPage;
  ShowZoom;
end;

procedure TLedVisualPane.ZoomKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    FZoomBox.ItemIndex := FZoomBox.Items.IndexOf(FZoomBox.Text);
    ZoomChosen(Sender);
  end
  else if Key = VK_ESCAPE then
  begin
    Key := 0;
    BackToPage;
    ShowZoom;
  end;
end;

procedure TLedVisualPane.ZoomInClicked(Sender: TObject);
begin
  FFitWidth := False;
  FEdit.Zoom := FEdit.Zoom * 1.25;
  ShowZoom;
  BackToPage;
end;

procedure TLedVisualPane.ZoomOutClicked(Sender: TObject);
begin
  FFitWidth := False;
  FEdit.Zoom := FEdit.Zoom / 1.25;
  ShowZoom;
  BackToPage;
end;

{ the toggles flip what they show and then show it: a button clicked from code is not pressed down first }
procedure TLedVisualPane.MarksClicked(Sender: TObject);
begin
  FEdit.ShowMarks := not FEdit.ShowMarks;
  FMarksBtn.Down := FEdit.ShowMarks;
  BackToPage;
end;

procedure TLedVisualPane.NavClicked(Sender: TObject);
begin
  FNavPanel.Visible := not FNavPanel.Visible;
  FNavSplitter.Visible := FNavPanel.Visible;
  FNavBtn.Down := FNavPanel.Visible;
  if FNavPanel.Visible then
    FEdit.GetHeadings(FNavList.Items);
  BackToPage;
end;

procedure TLedVisualPane.NavListClicked(Sender: TObject);
begin
  if FNavList.ItemIndex < 0 then Exit;
  FEdit.GoToPos(PdPos(pd_block_id(PtrUInt(FNavList.Items.Objects[FNavList.ItemIndex])), 0));
  BackToPage;
end;

procedure TLedVisualPane.NavTimerFired(Sender: TObject);
var
  Keep: Integer;
begin
  FNavTimer.Enabled := False;
  if not FNavPanel.Visible then Exit;
  Keep := FNavList.TopIndex;
  FEdit.GetHeadings(FNavList.Items);
  if Keep < FNavList.Items.Count then
    FNavList.TopIndex := Keep;
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

procedure TLedVisualPane.DeleteKey;
begin
  {$IFDEF LED_PARADE}
  FEdit.ProcessKey(VK_DELETE, []);
  {$ENDIF}
end;

procedure TLedVisualPane.ApplyPrefs;
{$IFDEF LED_PARADE}
var
  T: Integer;
{$ENDIF}
begin
  {$IFDEF LED_PARADE}
  { what a document opened or joined from now on gets, and the one shown: the
    formats LED opens here carry no setting of their own }
  FEdit.HybridDefault := LowerCase(LedPrefs.GetStr(LedPrefLineBreaking, 'hybrid')) <> 'optimal';
  T := EnsureRange(LedPrefs.GetInt(LedPrefShapeTheme, 0), 0, High(Themes));   { the colours new shapes take }
  FEdit.ShapeFillColor := FromRGB(Themes[T, 0]);
  FEdit.ShapeLineColor := FromRGB(Themes[T, 1]);
  if not (FKind in [lvkPdoc, lvkJdoc]) then     { a Parade document keeps the one saved with it }
    FEdit.HybridBreaking := FEdit.HybridDefault;
  {$ENDIF}
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
    AWhy := 'the visual editor opens Markdown, HTML, Word (.docx) and Parade (.pdoc, .jdoc) files';
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
  {$IFDEF LED_PARADE}
  FitWidth;
  {$ENDIF}
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
    FEdit.SaveToStream(S, ParadeFormat(AKind), AKind = lvkPdoc);
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
  FEdit.TrackChanges := not FEdit.TrackChanges;
  FTrack.Down := FEdit.TrackChanges;
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

function TLedVisualPane.JoinShared: Boolean;
{$IFDEF LED_PARADE_SYNC}
var
  Server, Doc, Token, Who: string;
  What: TLedCollabKind;
begin
  Result := False;
  if not LedAskJoin(Server, Doc, Token, Who, What) then
    Exit;
  if What = lckText then
  begin
    MessageDlg('Join', '"' + Doc + '" is a shared text, not a page: File > Join Shared Document opens it in a ' +
      'text tab.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Result := JoinWith(Server, Doc, Token, Who);
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

{$IFDEF LED_PARADE_SYNC}
function TLedVisualPane.DocName: string;
begin
  Result := ChangeFileExt(ExtractFileName(FFileName), '');
end;

function TLedVisualPane.JoinWith(const Server, Doc, Token, Who: string): Boolean;
begin
  Result := FCollab.JoinWith(Server, Doc, Token, Who);
  BackToPage;
end;

procedure TLedVisualPane.SyncChanged(Sender: TObject);
var
  S: string;
begin
  if not FCollab.Active then
  begin
    FSyncStatus.Caption := '';
    Exit;
  end;
  S := FCollab.StatusText;
  if FEdit.ReadOnly then
    S := S + ' (read only)';
  FSyncStatus.Caption := S;
end;
{$ENDIF}

procedure TLedVisualPane.EditChanged(Sender: TObject);
begin
  {$IFDEF LED_PARADE}
  if (FNavPanel <> nil) and FNavPanel.Visible then
  begin   { the headings list made again once the typing pauses }
    FNavTimer.Enabled := False;
    FNavTimer.Enabled := True;
  end;
  {$ENDIF}
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure LedCountText(const S: string; var Words, Chars: Integer; var InWord: Boolean);
var
  i, n, k: Integer;
  c: Cardinal;
begin
  i := 1;
  n := Length(S);
  while i <= n do
  begin
    c := Ord(S[i]);
    k := 1;
    if c >= $F0 then begin c := c and $07; k := 4; end
    else if c >= $E0 then begin c := c and $0F; k := 3; end
    else if c >= $C0 then begin c := c and $1F; k := 2; end;
    while (k > 1) and (i + 1 <= n) and (Ord(S[i + 1]) and $C0 = $80) do
    begin
      Inc(i);
      c := (c shl 6) or (Ord(S[i]) and $3F);
      Dec(k);
    end;
    Inc(i);
    if (c = 10) or (c = 13) or (c = $FFFC) then     { line breaks, and the objects the text stands in for }
    begin
      InWord := InWord and (c = $FFFC);
      Continue;
    end;
    Inc(Chars);
    if (c = 32) or (c = 9) or (c = $A0) or (c = $3000) or ((c >= $2000) and (c <= $200A)) or (c = $2028) or
       (c = $2029) then
      InWord := False
    else if ((c >= $2E80) and (c <= $9FFF)) or ((c >= $AC00) and (c <= $D7AF)) or ((c >= $F900) and (c <= $FAFF)) or
       ((c >= $FF66) and (c <= $FF9F)) or ((c >= $20000) and (c <= $3FFFF)) then
    begin   { CJK: each a word, ending the one before it }
      Inc(Words);
      InWord := False;
    end
    else if not InWord then
    begin
      Inc(Words);
      InWord := True;
    end;
  end;
end;

function LedSelectionCounts(Words, Chars: Integer): string;
const
  Plural: array[Boolean] of string = ('s', '');
begin
  if Chars = 0 then
    Result := ''
  else
    Result := Format(', %.0n word%s, %.0n character%s selected', [Words * 1.0, Plural[Words = 1], Chars * 1.0,
      Plural[Chars = 1]]);
end;

function TLedVisualPane.StatusText: string;
{$IFDEF LED_PARADE}
var
  PageNo: Int32;
  X, Base, Asc, Desc: pd_sp;
  A, B: pd_pos;
  Blk: pd_block_id;
  S: string;
  Lo, Hi, Words, Chars: Integer;
  InWord: Boolean;
{$ENDIF}
begin
  Result := '';
  {$IFDEF LED_PARADE}
  if (FEdit = nil) or (FEdit.Layout = nil) then
    Exit;
  if (FEdit.PageCount > 0) and (pd_layout_caret(FEdit.Layout, FEdit.CaretPos, PageNo, X, Base, Asc, Desc) = PD_OK) then
    Result := Format('Page %d of %d', [PageNo + 1, FEdit.PageCount])
  else if FEdit.PageCount > 0 then
    Result := Format('%d pages', [FEdit.PageCount]);
  if FEdit.SelectionRange(A, B) then
  begin   { paragraph by paragraph, as the selection's text is made, without making it }
    Words := 0;
    Chars := 0;
    InWord := False;
    Blk := A.block;
    while Blk <> 0 do
    begin
      S := FEdit.ParaText(Blk);
      if Blk = A.block then Lo := A.offset else Lo := 0;
      if Blk = B.block then Hi := B.offset else Hi := Length(S);
      if Hi > Lo then
        LedCountText(Copy(S, Lo + 1, Hi - Lo), Words, Chars, InWord);
      if Blk = B.block then
        Break;
      InWord := False;
      Blk := pd_doc_next_paragraph(FEdit.Doc, Blk);
    end;
    Result := Result + LedSelectionCounts(Words, Chars);
  end;
  {$ENDIF}
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
