{ led - a light editor.  The editor view control.

  One TLedEdit is one *view*.  A document may own several of them, all sharing
  a single text buffer, which is how split view works. }
unit Led.UI.Edit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Graphics, Menus, SynEdit, SynEditTypes,
  SynEditMouseCmds, SynEditWrappedView, SynCompletion, SynEditFoldedView,
  SynEditMarkupFoldColoring, SynEditMarkup, SynEditMiscClasses,
  Led.UI.Dpi, Led.UI.FoldGutter;

{ Shortcuts the menus own, which the editor must therefore not consume.

  SynEdit ships a keymap of its own and handles a key before the form's
  accelerators get a look, so any overlap silently goes to the editor.  Two of
  them were doing visible damage -- syneditkeycmds.pp binds Ctrl+M to
  ecLineBreak and Ctrl+N to ecInsertLine, so File > New Tab and its Ctrl+N
  never fired and typing it inserted a newline instead.

  Rather than name the offenders, the main form registers every shortcut its
  action list uses and each editor drops the matching keystrokes as it is
  built.  That way a shortcut added to a menu later cannot quietly be eaten
  by the editor, which is how this one got in. }
procedure LedReserveShortcut(AShortCut: TShortCut);
procedure LedStripReservedKeystrokes(AEdit: TSynEdit);

type
  TLedEdit = class(TSynEdit)
  private
    FDocument: TObject;   // the owning TLedDocument; typed loosely to avoid
                          // a circular unit reference
    FWrapPlugin: TLazSynEditLineWrapPlugin;
    FCompletion: TSynCompletion;
    FFoldGuides: TSynEditMarkupFoldColors;
    function GetWrapEnabled: Boolean;
    procedure SetWrapEnabled(AValue: Boolean);
    procedure CompletionSearch(var APosition: Integer);
    procedure CollectWords(const APrefix: string; AInto: TStrings);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Document: TObject read FDocument write FDocument;
    { The vertical block guides, so the theme can colour them. }
    property FoldGuides: TSynEditMarkupFoldColors read FFoldGuides;
    { SynEdit implements wrapping as a view plugin rather than a property;
      attaching and detaching it is how the View menu toggles wrap. }
    property WrapEnabled: Boolean read GetWrapEnabled write SetWrapEnabled;
    { Created on first use.  TSynCompletion builds a popup form, and building
      a form inside another form's constructor hangs. }
    function Completion: TSynCompletion;
    { Lines actually on display.  Folding hides lines in the view, never in
      the buffer, so Lines.Count does not move when something is folded and
      is the wrong thing to look at.  TextView is protected on TSynEdit, so
      a descendant is the only place this can be reached. }
    function VisibleLineCount: Integer;
    { The folded view, which SynEdit keeps private but exposes to descendants
      through GetFoldedTextBuffer.  Its API is indexed by text line, unlike
      CodeFoldAction, which works from screen rows and therefore does nothing
      unless the display happens to be in the state it expects. }
    function FoldedView: TSynEditFoldedView;
  end;

implementation

constructor TLedEdit.Create(AOwner: TComponent);
var
  i: Integer;
begin
  inherited Create(AOwner);

  Options := Options
    + [eoBracketHighlight,     // matching-bracket markup
       eoGroupUndo,            // coalesce typing into one undo step
       eoTabIndent,            // Tab indents a selected block
       eoEnhanceHomeKey,       // smart Home
       eoScrollPastEol,        // needed for column selection past line end
       eoKeepCaretX]
    - [eoSmartTabs];

  Options2 := Options2 + [eoEnhanceEndKey];   // smart End

  { medit selected a rectangle with Ctrl+drag; SynEdit ships Alt+drag.  Both
    are bound, since Alt+drag is grabbed by the window manager on several
    Linux desktops and would otherwise be unreachable.

    emUseMouseActions makes SynEdit take every mouse gesture from these
    lists instead of its built-in handling, and the lists start EMPTY.  So
    they have to be filled with the defaults first, or the only gesture the
    editor understands is the one added below -- no caret placement, no
    drag-select, no wheel, no context menu, and no clicking the fold boxes
    in the gutter. }
  MouseOptions := MouseOptions + [emUseMouseActions];
  ResetMouseActions;
  MouseActions.AddCommand(emcStartColumnSelections, True, mbXLeft, ccSingle,
    cdDown, [ssCtrl], [ssCtrl, ssAlt, ssShift]);
  DefaultSelectionMode := smNormal;

  Gutter.Visible := True;
  Gutter.LineNumberPart.Visible := True;
  Gutter.CodeFoldPart.Visible := True;
  Gutter.ChangesPart.Visible := True;
  { The gutter parts keep their own action lists, and they are empty for the
    same reason. }
  for i := 0 to Gutter.Parts.Count - 1 do
    Gutter.Parts[i].ResetMouseActions;

  { medit sizes the line-number column to the digits actually needed.
    AutoSize does that, but SynEdit's floor of 22 pixels of padding makes a
    three-digit file look like a five-digit one. }
  Gutter.LineNumberPart.AutoSize := True;
  Gutter.LineNumberPart.DigitCount := 2;
  Gutter.LineNumberPart.LeadingZeros := False;
  Gutter.MarksPart.AutoSize := False;
  Gutter.MarksPart.Width := LedScale96(12);
  Gutter.SeparatorPart.Width := LedScale96(2);
  Gutter.ChangesPart.Width := LedScale96(3);

  { The fold column must be sized explicitly, and this is not cosmetic
    fiddling.  TSynGutterCodeFolding derives its box from
      HalfBoxSize := Min(Width, LineHeight - 2) div 2
    and its pen from
      Pen.Width := Min(..., FPpiPenWidth)
    where FPpiPenWidth is only ever recomputed inside SetWidth -- and SetWidth
    returns immediately while AutoSize is on.  Left on AutoSize the markers
    therefore stay small *and* keep a one-pixel pen at any DPI, which is why
    the fold boxes and the vertical rule joining a block to its end looked
    faint.  Sizing the column to the line height gives both room to grow. }
  { Replace the stock fold column with one that draws medit's chevrons
    instead of boxed [-] and [+].  TSynGutter.CodeFoldPart resolves through
    "is", so the descendant is what every later reference finds -- the two
    lines below, and the theme applier's contrast handling.

    ResetMouseActions on the new part is not optional, and getting it wrong
    is why the first attempt at this drew correctly and ignored every click:
    a gutter part's mouse-action list starts EMPTY and is filled with the
    defaults by ResetMouseActions.  The loop above does that for the parts
    that exist at the time, and this one is created after it, so it has to
    ask for its own. }
  Gutter.CodeFoldPart.Free;
  TLedGutterCodeFolding.Create(Gutter.Parts).Name := 'LedGutterCodeFolding1';
  Gutter.CodeFoldPart.ResetMouseActions;

  Gutter.CodeFoldPart.AutoSize := False;
  { Wider than the stock column, both because the chevron wants the room and
    because HalfBoxSize and the pen width are derived from it. }
  Gutter.CodeFoldPart.Width := LedScale96(18);

  { Vertical guides down the body of each open block, drawn in the text area
    rather than the gutter -- medit draws them there too, in
    _moo_text_view_draw_fold_guides, and a guide in the gutter cannot line up
    with the code it belongs to.

    This is SynEdit's own TSynEditMarkupFoldColors, which the Lazarus IDE
    uses for the same purpose: it anchors the line at the block's first
    non-whitespace column -- the same idea as medit's owner-line scan -- and
    draws it as a left frame edge on the marked column, so it spans the rows
    between the opening and closing lines and nothing else.

    ColorCount matters: RealEnabled is false while it is zero, which is the
    default, so the markup does nothing until asked.  One colour rather than
    the IDE's per-nesting-level palette, because medit drew one quiet guide
    and a rainbow in a text editor is a choice nobody asked for.  The colour
    itself comes from the theme; see LedApplyThemeToEditor. }
  FFoldGuides := TSynEditMarkupFoldColors.Create(Self);
  FFoldGuides.ColorCount := 1;
  FFoldGuides.LineColor[0].Style := slsSolid;
  TSynEditMarkupManager(MarkupMgr).AddMarkUp(FFoldGuides);

  Font.Name := LedDefaultFontName;
  Font.Size := LedDefaultFontSize;

  { Anything the menus claim is dropped from the editor's own keymap, so the
    accelerator reaches the action instead of being spent here. }
  LedStripReservedKeystrokes(Self);

  BorderStyle := bsNone;
  ScrollBars := ssAutoBoth;

end;

var
  GReserved: array of TShortCut;

procedure LedReserveShortcut(AShortCut: TShortCut);
var
  i: Integer;
begin
  if AShortCut = 0 then Exit;
  for i := 0 to High(GReserved) do
    if GReserved[i] = AShortCut then Exit;
  SetLength(GReserved, Length(GReserved) + 1);
  GReserved[High(GReserved)] := AShortCut;
end;

procedure LedStripReservedKeystrokes(AEdit: TSynEdit);
var
  i, j: Integer;
  SC: TShortCut;
begin
  if AEdit = nil then Exit;
  for i := AEdit.Keystrokes.Count - 1 downto 0 do
  begin
    SC := AEdit.Keystrokes[i].ShortCut;
    for j := 0 to High(GReserved) do
      if GReserved[j] = SC then
      begin
        AEdit.Keystrokes.Delete(i);
        Break;
      end;
  end;
end;

{ Word completion drawn from the document itself.  medit had none at all, and
  it is the absence people notice within a minute. }
function TLedEdit.Completion: TSynCompletion;
begin
  if FCompletion = nil then
  begin
    { Owned by nothing: making the editor its owner deadlocks, because
      TSynCompletion also attaches itself to that editor as a plugin. }
    FCompletion := TSynCompletion.Create(nil);
    FCompletion.Editor := Self;
    FCompletion.ShortCut := 16416;      { Ctrl+Space }
    FCompletion.CaseSensitive := False;
    FCompletion.OnSearchPosition := @CompletionSearch;
  end;
  Result := FCompletion;
end;

{ Every distinct word in the buffer that begins with what has been typed.
  Scanning the whole document each time is affordable -- it is a pass over a
  few hundred kilobytes of text -- and it means the list is never stale. }
procedure TLedEdit.CollectWords(const APrefix: string; AInto: TStrings);
var
  i, j, k, n: Integer;
  Line, Word, Lower: string;
begin
  Lower := LowerCase(APrefix);
  for i := 0 to Lines.Count - 1 do
  begin
    Line := Lines[i];
    n := Length(Line);
    j := 1;
    while j <= n do
    begin
      if Line[j] in ['A'..'Z', 'a'..'z', '_'] then
      begin
        k := j;
        while (k <= n) and (Line[k] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
          Inc(k);
        Word := Copy(Line, j, k - j);
        { Too short to be worth offering, and never the word being typed. }
        if (Length(Word) > 2) and
           ((Lower = '') or (Pos(Lower, LowerCase(Word)) = 1)) and
           (not SameText(Word, APrefix)) then
          AInto.Add(Word);
        j := k;
      end
      else
        Inc(j);
    end;
  end;
end;

procedure TLedEdit.CompletionSearch(var APosition: Integer);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Sorted := True;
    L.Duplicates := dupIgnore;
    CollectWords(FCompletion.CurrentString, L);
    FCompletion.ItemList.Assign(L);
  finally
    L.Free;
  end;
  APosition := 0;
end;

destructor TLedEdit.Destroy;
begin
  FreeAndNil(FCompletion);
  inherited Destroy;
end;

function TLedEdit.VisibleLineCount: Integer;
begin
  Result := TextView.Count;
end;

function TLedEdit.FoldedView: TSynEditFoldedView;
begin
  Result := TSynEditFoldedView(GetFoldedTextBuffer);
end;

function TLedEdit.GetWrapEnabled: Boolean;
begin
  Result := FWrapPlugin <> nil;
end;

procedure TLedEdit.SetWrapEnabled(AValue: Boolean);
begin
  if AValue = GetWrapEnabled then Exit;
  if AValue then
    FWrapPlugin := TLazSynEditLineWrapPlugin.Create(Self)
  else
    FreeAndNil(FWrapPlugin);
end;

end.
