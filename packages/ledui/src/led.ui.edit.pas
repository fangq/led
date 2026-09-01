{ led - a light editor.  The editor view control.

  One TLedEdit is one *view*.  A document may own several of them, all sharing
  a single text buffer, which is how split view works. }
unit Led.UI.Edit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Graphics, Menus, SynEdit, SynEditTypes,
  SynEditMouseCmds, SynEditWrappedView, SynCompletion, SynEditFoldedView,
  SynEditHighlighterFoldBase, SynEditHighlighter,
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
  { One text line and the columns a guide should be drawn at on it. }
  TLedGuideRun = record
    TextIdx: Integer;
    Cols: array of Integer;
  end;
  TLedGuideRuns = array of TLedGuideRun;

  TLedEdit = class(TSynEdit)
  private
    FDocument: TObject;   // the owning TLedDocument; typed loosely to avoid
                          // a circular unit reference
    FWrapPlugin: TLazSynEditLineWrapPlugin;
    FCompletion: TSynCompletion;
    FGuideColour: TColor;
    function GetWrapEnabled: Boolean;
    procedure SetWrapEnabled(AValue: Boolean);
    function LineIndentColumn(ATextIdx: Integer): Integer;
    procedure DrawBlockGuides;
    procedure CompletionSearch(var APosition: Integer);
    procedure CollectWords(const APrefix: string; AInto: TStrings);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Document: TObject read FDocument write FDocument;
    { The colour the vertical block guides are drawn in; the theme sets it. }
    property GuideColour: TColor read FGuideColour write FGuideColour;

    { The columns a guide belongs at, for every text line in the range.
      Public because it is what the self-test can check: the drawing itself
      is pixels, but which columns are guided is the decision, and it is the
      same routine Paint uses. }
    function ComputeBlockGuides(AFirstText, ALastText: Integer): TLedGuideRuns;
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

  FGuideColour := clNone;

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

{ --- vertical block guides ------------------------------------------------- }

{ The column of the first non-blank character, 1-based, tabs expanded.  This
  is where the guide for a block opened on this line belongs -- medit anchors
  its guides the same way. }
function TLedEdit.LineIndentColumn(ATextIdx: Integer): Integer;
var
  Txt: string;
  i, Col: Integer;
begin
  Result := 0;
  if (ATextIdx < 0) or (ATextIdx >= Lines.Count) then Exit;
  Txt := Lines[ATextIdx];
  Col := 1;
  for i := 1 to Length(Txt) do
  begin
    if Txt[i] = #9 then
      Col := Col + TabWidth - ((Col - 1) mod TabWidth)
    else if Txt[i] = ' ' then
      Inc(Col)
    else
      Exit(Col);
  end;
  { All blank: no guide belongs to a line with nothing on it. }
  Result := 0;
end;

{ Which columns carry a guide, for each line in the range.

  A stack of open blocks, walked forwards.  On each line the blocks that end
  there are popped, the remaining stack is what the line is inside, and the
  blocks that start there are pushed afterwards.  That ordering is what makes
  the guide span the body only: the opening line draws before its own block is
  pushed, and the closing line draws after its block is popped -- from the
  second line of the block to the one before the last, which is what was
  asked for and what medit does.

  The walk starts a bounded distance above the range so that blocks opened
  off-screen still produce their guides; without that, scrolling into the
  middle of a function would show nothing. }
function TLedEdit.ComputeBlockGuides(AFirstText,
  ALastText: Integer): TLedGuideRuns;
const
  ScanBack = 800;
var
  HL: TSynCustomFoldHighlighter;
  Stack: array of Integer;
  Depth, Start, L, i, Opens, Closes, EndLvl, MinLvl, PrevEnd, Col, N: Integer;
begin
  Result := nil;
  if not (Highlighter is TSynCustomFoldHighlighter) then Exit;
  HL := TSynCustomFoldHighlighter(Highlighter);
  if Lines.Count = 0 then Exit;

  if AFirstText < 0 then AFirstText := 0;
  if ALastText >= Lines.Count then ALastText := Lines.Count - 1;
  if AFirstText > ALastText then Exit;

  Start := AFirstText - ScanBack;
  if Start < 0 then Start := 0;

  SetLength(Stack, 0);
  Depth := 0;
  if Start > 0 then
    PrevEnd := HL.FoldBlockEndLevel(Start - 1)
  else
    PrevEnd := 0;

  SetLength(Result, ALastText - AFirstText + 1);
  N := 0;

  for L := Start to ALastText do
  begin
    EndLvl := HL.FoldBlockEndLevel(L);
    MinLvl := HL.FoldBlockMinLevel(L);

    Closes := PrevEnd - MinLvl;
    if Closes < 0 then Closes := 0;
    Opens := EndLvl - MinLvl;
    if Opens < 0 then Opens := 0;

    { Blocks that end on this line are no longer around it. }
    for i := 1 to Closes do
      if Depth > 0 then Dec(Depth);

    if L >= AFirstText then
    begin
      Result[N].TextIdx := L;
      SetLength(Result[N].Cols, 0);
      for i := 0 to Depth - 1 do
        { Column 1 means a top-level block, whose guide would run down the
          very edge of the text.  medit skips those and so does this. }
        if Stack[i] > 1 then
        begin
          SetLength(Result[N].Cols, Length(Result[N].Cols) + 1);
          Result[N].Cols[High(Result[N].Cols)] := Stack[i];
        end;
      Inc(N);
    end;

    { Blocks that start here enclose the lines below, not this one. }
    if Opens > 0 then
    begin
      Col := LineIndentColumn(L);
      for i := 1 to Opens do
      begin
        if Length(Stack) <= Depth then SetLength(Stack, Depth + 8);
        Stack[Depth] := Col;
        Inc(Depth);
      end;
    end;

    PrevEnd := EndLvl;
  end;

  SetLength(Result, N);
end;

procedure TLedEdit.DrawBlockGuides;
var
  Runs: TLedGuideRuns;
  FV: TSynEditFoldedView;
  FirstText, LastText, i, j, Row, X, Y, TextLeft: Integer;
begin
  if FGuideColour = clNone then Exit;
  if not (Highlighter is TSynCustomFoldHighlighter) then Exit;
  if not (FoldedTextBuffer is TSynEditFoldedView) then Exit;
  FV := TSynEditFoldedView(FoldedTextBuffer);

  FirstText := FV.ScreenLineToTextIndex(0);
  LastText := FV.ScreenLineToTextIndex(LinesInWindow);
  if LastText < FirstText then LastText := FirstText;

  Runs := ComputeBlockGuides(FirstText, LastText);
  if Length(Runs) = 0 then Exit;

  { Where column 1 starts.  TCustomSynEdit.TextLeftPixelOffset computes
    exactly this and is private, so the two lines it amounts to are repeated
    here: the gutter's width plus GutterTextDist, which is the constant 2. }
  if Gutter.Visible then
    TextLeft := Gutter.Width + 2
  else
    TextLeft := 1;

  Canvas.Pen.Color := FGuideColour;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Style := psSolid;

  for i := 0 to High(Runs) do
  begin
    { Folded-away lines have no row of their own; TextIndexToScreenLine gives
      the row the fold collapsed onto, so they would stack guides on one line. }
    Row := FV.TextIndexToScreenLine(Runs[i].TextIdx);
    if (Row < 0) or (Row >= LinesInWindow) then Continue;
    if FV.ScreenLineToTextIndex(Row) <> Runs[i].TextIdx then Continue;

    Y := Row * LineHeight;
    for j := 0 to High(Runs[i].Cols) do
    begin
      X := TextLeft + (Runs[i].Cols[j] - LeftChar) * CharWidth;
      if X < TextLeft then Continue;
      Canvas.MoveTo(X, Y);
      Canvas.LineTo(X, Y + LineHeight);
    end;
  end;
end;

procedure TLedEdit.Paint;
begin
  inherited Paint;
  DrawBlockGuides;
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
