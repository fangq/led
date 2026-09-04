{ led - a light editor.  The editor view control.

  One TLedEdit is one *view*.  A document may own several of them, all sharing
  a single text buffer, which is how split view works. }
unit Led.UI.Edit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Graphics, Menus, SynEdit, SynEditTypes,
  SynEditMouseCmds, SynEditWrappedView, SynCompletion, SynEditFoldedView,
  SynEditKeyCmds, LCLType,
  SynEditHighlighterFoldBase, SynEditHighlighter, LazVersion,
  Led.UI.Dpi, Led.UI.FoldGutter, Led.UI.SpellMarkup, Led.UI.LongLine,
  Led.Core.Spell, Led.Core.Gdb;

{$I led.lazversion.inc}

type
  { A click in the gutter's mark column, which is how a breakpoint is set in
    every debugger anyone has used.  medit's plugin could not do this -- its
    own notes call it a known limitation -- because GtkTextView gives no
    usable per-line gutter hit.  SynEdit does. }
  TLedBreakpointClick = procedure(Sender: TObject; ALine: Integer) of object;
  { The pointer came to rest on something worth evaluating.  Answered later,
    through ShowHoverValue, because gdb is asked and gdb takes its time. }
  TLedHoverExpression = procedure(Sender: TObject; const AExpr: string) of object;

  { A breakpoint as the gutter needs to know it.  Conditional ones are drawn
    hollow, because one that looks identical to an unconditional breakpoint
    and then does not stop is the sort of thing that costs an afternoon. }
  TLedGutterBreak = record
    Line: Integer;
    Conditional: Boolean;
  end;
  TLedGutterBreaks = array of TLedGutterBreak;

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
    FSpell: TLedSpellMarkup;
    FLongLines: TLedLongLineView;
    FGuideColour: TColor;
    { The debugger's two marks.  Painted here rather than made into
      TSynEditMarks because SynEdit only draws marks when
      BookMarkOptions.BookmarkImages is set, and setting it would also
      replace the numbered glyphs led's ten bookmarks draw themselves with. }
    FBreaks: TLedGutterBreaks;
    FDebugLine: Integer;
    FOnBreakpointClick: TLedBreakpointClick;
    FOnHoverExpression: TLedHoverExpression;
    FHoverExpr: string;
    procedure SetDebugLine(AValue: Integer);
    function MarksColumn(out ALeft, AWidth: Integer): Boolean;
    procedure DrawDebugMarks;
    procedure ApplyDebugGutterWidth;
    procedure ColumnCommand(Sender: TObject;
      var Command: TSynEditorCommand; var AChar: TUTF8Char; Data: Pointer);
    function GetWrapEnabled: Boolean;
    procedure SetWrapEnabled(AValue: Boolean);
    function LineIndentColumn(ATextIdx: Integer): Integer;
    procedure DrawBlockGuides;
    procedure DrawLongLineMarkers;
    procedure CompletionSearch(var APosition: Integer);
    procedure CollectWords(const APrefix: string; AInto: TStrings);
  protected
    procedure Paint; override;
    { Keeps the long-line view's live range on the caret and the selection.
      Every caret or selection movement passes through here, which is what
      makes the "a line being edited is never truncated" invariant hold
      without every edit path having to remember it. }
    procedure StatusChanged(AChanges: TSynStatusChanges); override;
    { Clicking the marker reveals the next chunk, which is medit's gesture. }
    procedure MouseDown(AButton: TMouseButton; AShift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(AShift: TShiftState; X, Y: Integer); override;
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

    { The lines this document has breakpoints on, and the line execution is
      stopped at (0 for none).  Set by the debugger; drawn in the gutter. }
    procedure SetBreakpointLines(const ABreaks: TLedGutterBreaks);
    function HasBreakpoint(ALine: Integer): Boolean;
    function BreakpointIsConditional(ALine: Integer): Boolean;
    property DebugLine: Integer read FDebugLine write SetDebugLine;
    property OnBreakpointClick: TLedBreakpointClick
      read FOnBreakpointClick write FOnBreakpointClick;

    { Hover-to-inspect.  The editor says what the pointer is over; the
      debugger says what it is worth, whenever it finds out. }
    property OnHoverExpression: TLedHoverExpression
      read FOnHoverExpression write FOnHoverExpression;
    { Asks about AExpr and remembers that it did, which is what lets a late
      answer be told from one about a place the pointer has since left.
      MouseMove calls this; so does anything driving the editor without a
      mouse. }
    procedure RequestHover(const AExpr: string);
    procedure ShowHoverValue(const AExpr, AValue: string);
    { What the pointer is over now, or ''.  Public so a check can ask
      without a mouse. }
    function ExpressionAtPixels(X, Y: Integer): string;
    property HoverExpression: string read FHoverExpr;

    { Display-only truncation of very long lines; see Led.UI.LongLine for why
      the buffer is never touched.  Always present, because the view has to be
      in the chain before any text arrives -- the limit is what turns it on
      and off. }
    property LongLines: TLedLongLineView read FLongLines;
    { The character offset the marker sits at on a truncated line, or 0.
      Public so the self-test can ask which lines are truncated and how far,
      which is the decision behind the pixels. }
    function LongLineMarkerCol(ATextIdx: Integer): Integer;

    { The spell markup, created on first use.  Off until a preference turns
      it on, so a document that is never checked costs nothing. }
    function SpellMarkup: TLedSpellMarkup;
    procedure SetSpellScope(AScope: TLedSpellScope);
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

  { Adds Ctrl+Shift+<key> for a column command, leaving whatever SynEdit
    already bound in place. }
  procedure AddColumnKey(ACmd: TSynEditorCommand; AKey: Word);
  var
    K: TSynEditKeyStroke;
  begin
    K := Keystrokes.Add;
    K.Command := ACmd;
    { One assignment, not Key then Shift.  Setting Key alone leaves the
      keystroke momentarily bound to the bare arrow, which SynEdit already
      uses -- and its duplicate check raises on that intermediate state, so
      the binding never happened and the arrow keys took the blame. }
    try
      K.ShortCut := Menus.ShortCut(AKey, [ssCtrl, ssShift]);
    except
      on ESynKeyError do
        { Something else already owns it; leave that alone and rely on
          SynEdit's own Alt+Shift binding. }
        K.Free;
    end;
  end;

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

    emUseMouseActions makes SynEdit take every gesture from the *user* lists
    rather than its internal ones -- GetActionsForOptions returns FUserActions
    when that option is set -- and ResetMouseActions copies the internal
    defaults into them.  So the defaults have to be there, or the editor
    understands nothing but what is added here: no caret placement, no
    drag-select, no wheel, no context menu, no fold boxes.

    Which list matters, and this is where the first attempt went wrong.
    SynEdit keeps three, and MouseDown asks them in order: MouseSelActions
    when the click landed inside a selection, then MouseTextActions, and
    MouseActions only if neither claimed it.  A Ctrl+drag was registered on
    MouseActions -- the last one -- while MouseTextActions holds the stock

      emcStartSelections, mbXLeft, ccSingle, cdDown, [], [ssShift, ssAlt]

    whose mask names only Shift and Alt.  Ctrl is unmasked, so that entry
    matches a Ctrl+left-press, starts an ordinary selection and returns
    handled, and the column command three lines below never got a look.
    Alt+drag worked because emAltSetsColumnMode puts its entries in the same
    list as the default it has to beat.

    So the Ctrl entries go in MouseTextActions too, and the stock selection
    entries get ssCtrl added to their masks so they stand down when it is
    held.  emAltSetsColumnMode stays on, which is what keeps Alt+drag. }
  MouseOptions := MouseOptions + [emUseMouseActions, emAltSetsColumnMode];
  ResetMouseActions;

  for i := MouseTextActions.Count - 1 downto 0 do
    if MouseTextActions[i].Command = emcStartSelections then
      MouseTextActions[i].ShiftMask :=
        MouseTextActions[i].ShiftMask + [ssCtrl];

  { Ctrl+drag starts a rectangle; Ctrl+Shift+drag extends the one already
    there, which is the pair SynEdit registers for Alt. }
  MouseTextActions.AddCommand(emcStartColumnSelections, True, mbXLeft,
    ccSingle, cdDown, [ssCtrl], [ssShift, ssAlt, ssCtrl],
    emcoSelectionStart);
  MouseTextActions.AddCommand(emcStartColumnSelections, True, mbXLeft,
    ccSingle, cdDown, [ssShift, ssCtrl], [ssShift, ssAlt, ssCtrl],
    emcoSelectionContinue);

  { And inside an existing selection the sel list answers first, so a
    Ctrl+drag that begins on selected text would start a drag-move instead. }
  for i := MouseSelActions.Count - 1 downto 0 do
    if MouseSelActions[i].Command = emcStartDragMove then
      MouseSelActions[i].ShiftMask :=
        MouseSelActions[i].ShiftMask + [ssCtrl];

  DefaultSelectionMode := smNormal;
  OnProcessCommand := @ColumnCommand;

  { SynEdit binds keyboard rectangle selection to Alt+Shift+arrows, and on
    several Linux desktops Alt+Shift is taken by the window manager -- the
    same reason Ctrl+drag is bound alongside Alt+drag above.  Ctrl+Shift+
    arrows are added as a second way in; SynEdit leaves them unbound. }
  AddColumnKey(ecColSelUp,    VK_UP);
  AddColumnKey(ecColSelDown,  VK_DOWN);
  AddColumnKey(ecColSelLeft,  VK_LEFT);
  AddColumnKey(ecColSelRight, VK_RIGHT);
  AddColumnKey(ecColSelLineStart, VK_HOME);
  AddColumnKey(ecColSelLineEnd,   VK_END);

  { AsFirst, so this sits at the bottom of the view chain, immediately above
    the text buffer.  Added on top instead it caps the caret and the painter
    but nothing else, and the views below -- the trimmer and above all the
    tab expander, which rescans a changed line end to end -- keep walking the
    full 5 MB on every keystroke.  From the bottom, everything above it sees
    the short line.

    TCustomSynEdit.Lines is built straight on FLines and does not pass
    through the chain at all, so load and save still see the whole line. }
  FLongLines := TLedLongLineView.Create;
  GetTextViewsManager.AddTextView(FLongLines, True);

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
  { The marks column only ever holds a bookmark glyph, and at twelve pixels
    it read as a broad empty band between the numbers and the code.  Six is
    enough for the glyph and stops the gutter looking like two gutters. }
  Gutter.MarksPart.AutoSize := False;
  Gutter.MarksPart.Width := LedScale96(6);
  Gutter.SeparatorPart.Width := LedScale96(1);
  Gutter.ChangesPart.Width := LedScale96(3);

  { The line the caret is on, called out in the gutter the way every editor
    that has line numbers does.

    MarkupInfoCurrentLine arrived on TSynGutterLineNumber after Lazarus 2.2,
    where the column has one MarkupInfo for every row and the paint routine
    reads it once.  There is no hook to single out a row short of
    reimplementing the part's Paint against two different base classes, so on
    2.2 the current line simply is not emphasised.  Cosmetic, and the caret
    and the status bar both still say where you are. }
  {$IFDEF LED_LAZ3_UP}
  Gutter.LineNumberPart.MarkupInfoCurrentLine.Foreground := clWhite;
  Gutter.LineNumberPart.MarkupInfoCurrentLine.Style := [fsBold];
  {$ENDIF}

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
      { Every enclosing block gets a guide, including one that starts at
        column 1.  Those were skipped, on the grounds that the rule would run
        down the very edge of the text -- but a function body flush against
        the margin is the commonest block there is, and leaving it unmarked
        made the guides look like they stopped working at the top level. }
      for i := 0 to Depth - 1 do
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

{ medit's " ..." at the truncation point, so hidden text reads as hidden
  rather than as absent.  Drawn rather than inserted: putting the marker in
  the text would make it selectable, searchable and saveable, which is three
  kinds of wrong for something that is not in the file. }
{ --- the debugger's gutter marks ------------------------------------------ }

{ Where the mark column is, in client pixels.  Asked of the gutter rather
  than assumed: the parts are ordered by whatever is switched on, so summing
  widths by hand goes wrong the moment someone hides the line numbers. }
function TLedEdit.MarksColumn(out ALeft, AWidth: Integer): Boolean;
begin
  ALeft := 0;
  AWidth := 0;
  Result := Gutter.Visible and (Gutter.MarksPart <> nil) and
            Gutter.MarksPart.Visible;
  if not Result then Exit;
  ALeft := Gutter.MarksPart.Left;
  AWidth := Gutter.MarksPart.Width;
  Result := AWidth > 0;
end;

{ The column is six scaled pixels when nothing is being debugged, which is
  right for the bookmark glyph it was sized for and far too narrow both to
  show a breakpoint and to click one.  Widened only while there is something
  to show, so a session that never debugs looks exactly as it did. }
procedure TLedEdit.ApplyDebugGutterWidth;
var
  Want: Integer;
begin
  if (Length(FBreaks) > 0) or (FDebugLine > 0) then
    Want := LedScale96(14)
  else
    Want := LedScale96(6);
  if Gutter.MarksPart.Width <> Want then
    Gutter.MarksPart.Width := Want;
end;

procedure TLedEdit.SetBreakpointLines(const ABreaks: TLedGutterBreaks);
var
  i: Integer;
begin
  SetLength(FBreaks, Length(ABreaks));
  for i := 0 to High(ABreaks) do FBreaks[i] := ABreaks[i];
  ApplyDebugGutterWidth;
  Invalidate;
end;

function TLedEdit.HasBreakpoint(ALine: Integer): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(FBreaks) do
    if FBreaks[i].Line = ALine then Exit(True);
  Result := False;
end;

function TLedEdit.BreakpointIsConditional(ALine: Integer): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(FBreaks) do
    if FBreaks[i].Line = ALine then Exit(FBreaks[i].Conditional);
  Result := False;
end;

procedure TLedEdit.SetDebugLine(AValue: Integer);
begin
  if FDebugLine = AValue then Exit;
  FDebugLine := AValue;
  ApplyDebugGutterWidth;
  Invalidate;
end;

procedure TLedEdit.DrawDebugMarks;
var
  FV: TSynEditFoldedView;
  Row, TextIdx, MLeft, MWidth, Cx, Cy, R: Integer;
  IsBreak, IsHere: Boolean;
begin
  if (Length(FBreaks) = 0) and (FDebugLine <= 0) then Exit;
  if not MarksColumn(MLeft, MWidth) then Exit;
  if not (FoldedTextBuffer is TSynEditFoldedView) then Exit;
  FV := TSynEditFoldedView(FoldedTextBuffer);

  R := MWidth;
  if LineHeight - 4 < R then R := LineHeight - 4;
  if R < 4 then Exit;

  for Row := 0 to LinesInWindow do
  begin
    TextIdx := FV.ScreenLineToTextIndex(Row);
    if (TextIdx < 0) or (TextIdx >= Lines.Count) then Continue;

    IsBreak := HasBreakpoint(TextIdx + 1);
    IsHere := (FDebugLine > 0) and (TextIdx + 1 = FDebugLine);
    if not (IsBreak or IsHere) then Continue;

    Cx := MLeft + (MWidth - R) div 2;
    Cy := Row * LineHeight + (LineHeight - R) div 2;

    if IsBreak then
    begin
      if BreakpointIsConditional(TextIdx + 1) then
      begin
        { Hollow, and in the same red: it is still a breakpoint, it just will
          not necessarily stop.  Drawn in maroon it read as a shadow rather
          than as a breakpoint at all. }
        Canvas.Brush.Style := bsClear;
        Canvas.Pen.Color := clRed;
        Canvas.Pen.Width := 2;
        Canvas.Ellipse(Cx, Cy, Cx + R, Cy + R);
        Canvas.Pen.Width := 1;
      end
      else
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := clRed;
        Canvas.Pen.Color := clMaroon;
        Canvas.Ellipse(Cx, Cy, Cx + R, Cy + R);
      end;
    end;

    if IsHere then
    begin
      { Drawn over the dot when both are on the line, because where
        execution is matters more than that it can stop there. }
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := clYellow;
      Canvas.Pen.Color := clOlive;
      Canvas.Polygon([Point(Cx, Cy), Point(Cx + R, Cy + R div 2),
                      Point(Cx, Cy + R)]);
    end;
  end;
  Canvas.Brush.Style := bsSolid;
end;

procedure TLedEdit.DrawLongLineMarkers;
var
  FV: TSynEditFoldedView;
  Row, TextIdx, TextLeft, X, Col: Integer;
  Saved: TColor;
begin
  if FLongLines = nil then Exit;
  if FLongLines.Limit <= 0 then Exit;
  if not (FoldedTextBuffer is TSynEditFoldedView) then Exit;
  FV := TSynEditFoldedView(FoldedTextBuffer);

  if Gutter.Visible then
    TextLeft := Gutter.Width + 2
  else
    TextLeft := 1;

  Saved := Canvas.Font.Color;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := clRed;
  try
    for Row := 0 to LinesInWindow do
    begin
      TextIdx := FV.ScreenLineToTextIndex(Row);
      if (TextIdx < 0) or (TextIdx >= Lines.Count) then Continue;
      Col := LongLineMarkerCol(TextIdx);
      if Col = 0 then Continue;
      X := TextLeft + (Col - LeftChar) * CharWidth;
      if X < TextLeft then Continue;
      if X > ClientWidth then Continue;
      Canvas.TextOut(X, Row * LineHeight, LedLongLineMarker);
    end;
  finally
    Canvas.Font.Color := Saved;
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TLedEdit.DrawBlockGuides;
var
  Runs: TLedGuideRuns;
  FV: TSynEditFoldedView;
  FirstText, LastText, i, j, Row, TextLeft, LastRow: Integer;
  RunTop, RunCol: array of Integer;

  function HasCol(const ACols: array of Integer; ACol: Integer): Boolean;
  var
    k: Integer;
  begin
    for k := 0 to High(ACols) do
      if ACols[k] = ACol then Exit(True);
    Result := False;
  end;

  function IndexOfRun(ACol: Integer): Integer;
  var
    k: Integer;
  begin
    for k := 0 to High(RunCol) do
      if RunCol[k] = ACol then Exit(k);
    Result := -1;
  end;

  { One line from the top of ATop's row to the top of ABelow's row. }
  procedure StrokeRun(ACol, ATop, ABelow: Integer);
  var
    X: Integer;
  begin
    if ABelow <= ATop then Exit;
    X := TextLeft + (ACol - LeftChar) * CharWidth;
    if X < TextLeft then Exit;
    Canvas.MoveTo(X, ATop * LineHeight);
    Canvas.LineTo(X, ABelow * LineHeight);
  end;

  procedure OpenRun(ACol, ARow: Integer);
  var
    k: Integer;
  begin
    for k := 0 to High(RunCol) do
      if RunCol[k] < 0 then
      begin
        RunCol[k] := ACol;
        RunTop[k] := ARow;
        Exit;
      end;
    SetLength(RunCol, Length(RunCol) + 1);
    SetLength(RunTop, Length(RunTop) + 1);
    RunCol[High(RunCol)] := ACol;
    RunTop[High(RunTop)] := ARow;
  end;

  procedure FlushRuns(ABelow: Integer);
  var
    k: Integer;
  begin
    for k := 0 to High(RunCol) do
      if RunCol[k] >= 0 then
      begin
        if ABelow >= 0 then StrokeRun(RunCol[k], RunTop[k], ABelow);
        RunCol[k] := -1;
      end;
  end;

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
  LastRow := -1;

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

  { One stroke per unbroken vertical run, not one per line.  Drawing each row
    separately left the rule looking dotted: a per-row LineTo stops a pixel
    short on some backends, and a row the fold view has no screen line for
    punched a hole that never closed up. }
  SetLength(RunTop, 0);
  SetLength(RunCol, 0);

  for i := 0 to High(Runs) do
  begin
    { Folded-away lines have no row of their own; TextIndexToScreenLine gives
      the row the fold collapsed onto, so they would stack guides on one
      line.  Such a row ends every run rather than continuing it. }
    Row := FV.TextIndexToScreenLine(Runs[i].TextIdx);
    if (Row < 0) or (Row >= LinesInWindow) or
       (FV.ScreenLineToTextIndex(Row) <> Runs[i].TextIdx) then
    begin
      FlushRuns(-1);
      Continue;
    end;

    { Close any run whose column is not on this line, then open or extend
      the ones that are. }
    for j := 0 to High(RunCol) do
      if (RunCol[j] >= 0) and not HasCol(Runs[i].Cols, RunCol[j]) then
      begin
        StrokeRun(RunCol[j], RunTop[j], Row);
        RunCol[j] := -1;
      end;

    for j := 0 to High(Runs[i].Cols) do
      if IndexOfRun(Runs[i].Cols[j]) < 0 then
        OpenRun(Runs[i].Cols[j], Row);

    LastRow := Row;
  end;

  FlushRuns(LastRow + 1);
end;

procedure TLedEdit.Paint;
begin
  inherited Paint;
  DrawBlockGuides;
  DrawLongLineMarkers;
  DrawDebugMarks;
end;

{ Word completion drawn from the document itself.  medit had none at all, and
  it is the absence people notice within a minute. }
{ Typing, backspacing and deleting with a rectangle selected act on every
  line of it, which is the whole point of a rectangle.  SynEdit does not do
  that on its own: it clears the block and then applies the keystroke once,
  at the caret, so "type X over three lines" left X on one line and nothing
  on the other two.

  Handled here rather than in Led.UI.Commands because it has to intercept the
  command before SynEdit runs it. }
procedure TLedEdit.ColumnCommand(Sender: TObject;
  var Command: TSynEditorCommand; var AChar: TUTF8Char; Data: Pointer);
var
  FirstY, LastY, Col, y, Len: Integer;
  Line: string;
begin
  { SelAvail is False for a rectangle with no width, but a zero-width block
    spanning several lines is still a block -- it is exactly what Backspace
    and Delete are aimed at, and what a multi-line caret looks like. }
  if SelectionMode <> smColumn then Exit;
  if not (SelAvail or (BlockBegin.Y <> BlockEnd.Y)) then Exit;
  { Explicit comparisons, not a set: these commands are 501, 502 and 511, and
    a Pascal set only spans 0..255, so "Command in [...]" cannot mean what it
    looks like. }
  if (Command <> ecChar) and (Command <> ecDeleteChar) and
     (Command <> ecDeleteLastChar) then Exit;
  if ReadOnly then Exit;

  FirstY := BlockBegin.Y;
  LastY := BlockEnd.Y;
  Col := BlockBegin.X;
  if BlockEnd.X < Col then Col := BlockEnd.X;

  BeginUndoBlock;
  try
    { Clear the rectangle first; SelText on a column selection removes it
      line by line, which is what is wanted here. }
    if (BlockBegin.X <> BlockEnd.X) then
      SelText := '';

    if Command = ecChar then
    begin
      for y := FirstY to LastY do
      begin
        if (y < 1) or (y > Lines.Count) then Continue;
        Line := Lines[y - 1];
        Len := Length(Line);
        { A line too short to reach the column is padded, so the inserted
          text still lines up.  Without this the block loses its shape on
          ragged text. }
        if Len < Col - 1 then
          TextBetweenPoints[Point(Len + 1, y), Point(Len + 1, y)] :=
            StringOfChar(' ', Col - 1 - Len);
        TextBetweenPoints[Point(Col, y), Point(Col, y)] := AChar;
      end;
      CaretXY := Point(Col + Length(AChar), FirstY);
    end
    else
    begin
      { Backspace and Delete over a zero-width rectangle: take one character
        from each line, on the side the key names. }
      for y := FirstY to LastY do
      begin
        if (y < 1) or (y > Lines.Count) then Continue;
        Line := Lines[y - 1];
        if Command = ecDeleteLastChar then
        begin
          if Col > 1 then
            TextBetweenPoints[Point(Col - 1, y), Point(Col, y)] := '';
        end
        else
          if Col <= Length(Line) then
            TextBetweenPoints[Point(Col, y), Point(Col + 1, y)] := '';
      end;
      if (Command = ecDeleteLastChar) and (Col > 1) then Dec(Col);
      CaretXY := Point(Col, FirstY);
    end;
  finally
    EndUndoBlock;
  end;

  { Handled here; SynEdit must not run it again. }
  Command := ecNone;
end;

function TLedEdit.SpellMarkup: TLedSpellMarkup;
begin
  if FSpell = nil then
  begin
    { Owned by the markup manager once added, as the other markups are. }
    FSpell := TLedSpellMarkup.Create(Self);
    MarkupManager.AddMarkUp(FSpell);
  end;
  Result := FSpell;
end;

procedure TLedEdit.SetSpellScope(AScope: TLedSpellScope);
begin
  { Nothing is created while spell checking is off, so the dictionary is
    never loaded for someone who does not use it. }
  if (FSpell = nil) and (AScope = lssOff) then Exit;
  SpellMarkup.Scope := AScope;
  SpellMarkup.Invalidate;
  Invalidate;
end;

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

{ Where the "..." goes: one past the last visible character, so it reads as
  a continuation of the text rather than as part of it.  0 when the line is
  not truncated. }
function TLedEdit.LongLineMarkerCol(ATextIdx: Integer): Integer;
begin
  Result := 0;
  if FLongLines = nil then Exit;
  if (ATextIdx < 0) or (ATextIdx >= Lines.Count) then Exit;
  if not FLongLines.IsTruncated(ATextIdx) then Exit;
  Result := FLongLines.VisibleLength(ATextIdx) + 1;
end;

{ A click at or past the marker reveals one more limit's worth of the line.

  Deliberately not "anywhere on a truncated line": the marker is the only
  part of the row that means "there is more", and a bare click that both
  moved the caret and changed what the line shows would make the text jump
  under the pointer. }
{ What the pointer is over, in the document's own terms. }
function TLedEdit.ExpressionAtPixels(X, Y: Integer): string;
var
  P: TPoint;
begin
  Result := '';
  if Gutter.Visible and (X < Gutter.Width) then Exit;
  P := PixelsToRowColumn(Point(X, Y));
  if (P.Y < 1) or (P.Y > Lines.Count) then Exit;
  Result := LedExpressionAt(Lines[P.Y - 1], P.X);
end;

{ Only asks when the answer could differ from the one already showing, so
  moving along a single identifier costs nothing. }
procedure TLedEdit.MouseMove(AShift: TShiftState; X, Y: Integer);
var
  Expr: string;
begin
  inherited MouseMove(AShift, X, Y);
  if not Assigned(FOnHoverExpression) then Exit;
  Expr := ExpressionAtPixels(X, Y);
  if Expr = FHoverExpr then Exit;
  RequestHover(Expr);
end;

procedure TLedEdit.RequestHover(const AExpr: string);
begin
  FHoverExpr := AExpr;
  if AExpr = '' then
  begin
    Hint := '';
    Exit;
  end;
  { Something is shown at once, so the pointer does not sit over a value
    with no sign that anything was asked. }
  Hint := AExpr + ' = ...';
  ShowHint := True;
  if Assigned(FOnHoverExpression) then FOnHoverExpression(Self, AExpr);
end;

procedure TLedEdit.ShowHoverValue(const AExpr, AValue: string);
begin
  { Ignored when the pointer has moved on: the answer is for a place it is
    no longer over, and putting it in the hint would show the wrong value
    for whatever is there now. }
  if AExpr <> FHoverExpr then Exit;
  Hint := AExpr + ' = ' + AValue;
  ShowHint := True;
end;

procedure TLedEdit.MouseDown(AButton: TMouseButton; AShift: TShiftState;
  X, Y: Integer);
var
  P: TPoint;
  TextIdx, Col, MLeft, MWidth, Row: Integer;
  FV: TSynEditFoldedView;
begin
  { A click in the gutter's mark column sets or clears a breakpoint, which is
    how every debugger does it and which medit's own plugin lists as a thing
    it could not manage.  Taken before inherited, because the gutter's own
    mouse actions would otherwise consume it. }
  if (AButton = mbLeft) and Assigned(FOnBreakpointClick) and
     MarksColumn(MLeft, MWidth) and
     (X >= MLeft) and (X < MLeft + MWidth) and
     (FoldedTextBuffer is TSynEditFoldedView) then
  begin
    FV := TSynEditFoldedView(FoldedTextBuffer);
    Row := Y div LineHeight;
    TextIdx := FV.ScreenLineToTextIndex(Row);
    if (TextIdx >= 0) and (TextIdx < Lines.Count) then
    begin
      FOnBreakpointClick(Self, TextIdx + 1);
      Exit;
    end;
  end;

  if (AButton = mbLeft) and (FLongLines <> nil) and (FLongLines.Limit > 0) then
  begin
    P := PixelsToRowColumn(Point(X, Y));
    TextIdx := P.Y - 1;
    Col := LongLineMarkerCol(TextIdx);
    if (Col > 0) and (P.X >= Col) then
    begin
      FLongLines.RevealMore(TextIdx);
      Invalidate;
      Exit;
    end;
  end;
  inherited MouseDown(AButton, AShift, X, Y);
end;

procedure TLedEdit.StatusChanged(AChanges: TSynStatusChanges);
var
  A, B: Integer;
begin
  inherited StatusChanged(AChanges);
  if FLongLines = nil then Exit;
  if AChanges * [scCaretX, scCaretY, scSelection] = [] then Exit;

  A := CaretY - 1;
  B := A;
  if SelAvail then
  begin
    A := BlockBegin.Y - 1;
    B := BlockEnd.Y - 1;
    if B < A then begin A := BlockEnd.Y - 1; B := BlockBegin.Y - 1; end;
  end;
  FLongLines.SetLiveRange(A, B);
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
