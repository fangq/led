{ led - a light editor.  The red squiggle under a misspelled word.

  A TSynEditMarkup rather than custom painting, because SynEdit already knows
  how to draw a wavy underline -- slsWaved on the bottom frame edge -- and
  already asks, for every token it draws, whether any markup wants a say.
  That is more than medit managed: moospellcheck.cpp settled for a straight
  red line because Pango's error underline rendered flat in MooTextView.

  Words are checked lazily, one visible line at a time, and the answers for
  that line are cached until the line changes.  A document is only ever a
  screenful of lines away from the user, so there is nothing to gain from
  checking the rest. }
unit Led.UI.SpellMarkup;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, SynEdit, SynEditMarkup, SynEditMiscClasses,
  SynEditTypes, SynEditHighlighter, LazSynEditText,
  SynTextMateSyn, TextMateGrammar,
  Led.Core.Spell;

type
  { How much of a document to check.  lssAuto is resolved to one of the
    others by the caller, which knows the document's language -- see
    Led.UI.Document.ApplyConfigToView. }
  TLedSpellScope = (lssAll, lssCode, lssOff);

  TLedSpellMarkup = class(TSynEditMarkup)
  private
    FScope: TLedSpellScope;
    { The row scanned for the paint in progress, and the misspellings found
      on it.  Valid only between PrepareMarkupForRow and EndMarkup; -1 means
      nothing scanned. }
    FCurrentRow: Integer;
    FStarts, FEnds: array of Integer;   // 1-based logical, [start, end)
    FCount: Integer;
    { Column ranges on the current row that are worth checking -- comments
      and strings under lssCode, the whole line under lssAll.  Collected in
      one pass over the highlighter rather than one query per word. }
    FProseFrom, FProseTo: array of Integer;
    FProseCount: Integer;
    procedure ScanRow(ARow: Integer);
    procedure CollectProseRuns(ARow: Integer; const ALine: string);
    function InProse(ACol: Integer): Boolean;
  public
    constructor Create(ASynEdit: TSynEditBase);
    procedure PrepareMarkupForRow(aRow: Integer); override;
    procedure EndMarkup; override;
    function GetMarkupAttributeAtRowCol(const aRow: Integer;
      const aStartCol: TLazSynDisplayTokenBound;
      const AnRtlInfo: TLazSynDisplayRtlInfo): TSynSelectedColor; override;
    procedure GetNextMarkupColAfterRowCol(const aRow: Integer;
      const aStartCol: TLazSynDisplayTokenBound;
      const AnRtlInfo: TLazSynDisplayRtlInfo;
      out ANextPhys, ANextLog: Integer); override;

    { Drops the scan, so the next paint re-checks.  Needed after a word is
      added to the dictionary or ignored; ordinary edits need nothing,
      because every paint rescans the rows it draws. }
    procedure Invalidate;

    { Exposed for the self-test: the misspellings found on ARow. }
    function MarksOnRow(ARow: Integer): Integer;

    property Scope: TLedSpellScope read FScope write FScope;
  end;

{ The word under a logical column, and where it starts.  Shared with the
  context menu, so that what is offered corrections is exactly what was
  underlined. }
function LedWordAt(const ALine: string; ACol: Integer;
  out AStart, ALen: Integer): string;

implementation

function LedWordAt(const ALine: string; ACol: Integer;
  out AStart, ALen: Integer): string;

  function IsWordChar(C: Char): Boolean;
  begin
    Result := C in ['a'..'z', 'A'..'Z', ''''];
  end;

var
  i, j: Integer;
begin
  Result := '';
  AStart := 0;
  ALen := 0;
  if (ACol < 1) or (ACol > Length(ALine)) then Exit;
  if not IsWordChar(ALine[ACol]) then Exit;

  i := ACol;
  while (i > 1) and IsWordChar(ALine[i - 1]) do Dec(i);
  j := ACol;
  while (j < Length(ALine)) and IsWordChar(ALine[j + 1]) do Inc(j);

  { A leading or trailing apostrophe is quoting, not spelling. }
  while (i <= j) and (ALine[i] = '''') do Inc(i);
  while (j >= i) and (ALine[j] = '''') do Dec(j);
  if i > j then Exit;

  AStart := i;
  ALen := j - i + 1;
  Result := Copy(ALine, i, ALen);
end;

constructor TLedSpellMarkup.Create(ASynEdit: TSynEditBase);
begin
  inherited Create(ASynEdit);
  FScope := lssOff;
  FCurrentRow := -1;
  { No foreground or background of its own: only the wavy underline, so the
    syntax colours underneath are untouched. }
  MarkupInfo.Foreground := clNone;
  MarkupInfo.Background := clNone;
  MarkupInfo.FrameColor := clRed;
  MarkupInfo.FrameEdges := sfeBottom;
  MarkupInfo.FrameStyle := slsWaved;
end;

procedure TLedSpellMarkup.Invalidate;
begin
  FCurrentRow := -1;
end;

{ Called once per display row before any token of it is drawn, which is why
  there is no staleness test anywhere else: the scan cannot outlive the paint
  that made it.  The previous version keyed a cache on the row number and
  rescanned only when that changed -- so typing on one line, which repaints
  only that line, reused the scan from the first keystroke and never noticed
  anything typed after it.

  The guard is for word wrap, where one text line covers several display rows
  and Prepare is called for each. }
procedure TLedSpellMarkup.PrepareMarkupForRow(aRow: Integer);
begin
  if FScope = lssOff then Exit;
  if aRow = FCurrentRow then Exit;
  FCurrentRow := aRow;
  ScanRow(aRow);
end;

procedure TLedSpellMarkup.EndMarkup;
begin
  inherited EndMarkup;
  FCurrentRow := -1;
end;

{ For the self-test, which has no paint to hang a Prepare off. }
function TLedSpellMarkup.MarksOnRow(ARow: Integer): Integer;
begin
  FCurrentRow := -1;
  PrepareMarkupForRow(ARow);
  Result := FCount;
end;

{ The stretches of a line worth checking.

  Under lssAll that is the whole line.  Under lssCode it is the comments and
  strings, which is what makes the feature usable over source: without it,
  every identifier is a misspelling.

  Collected in one walk over the highlighter.  The previous version asked
  GetHighlighterAttriAtRowCol per candidate word, and each of those re-runs
  the highlighter from the start of the line -- affordable when the scan
  happened once, not now that it happens on every paint. }
{ Does an attribute or pattern name denote prose?  Comments, strings and doc
  comments -- and deliberately not 'text', because every highlighter calls
  its default attribute "Text", so matching that made all ordinary code count
  as prose.  Files that really are prose never get here: they are lssAll. }
function LedNameIsProse(const AName: string): Boolean;
var
  S: string;
begin
  S := LowerCase(AName);
  Result := (Pos('comment', S) > 0) or (Pos('string', S) > 0) or
            (Pos('doc', S) > 0);
end;

procedure TLedSpellMarkup.CollectProseRuns(ARow: Integer; const ALine: string);
var
  HL: TSynCustomHighlighter;
  Attr: TSynHighlighterAttributes;
  Col, Len: Integer;

  { A TextMate grammar names only the delimiters of a comment or string; the
    body between them carries the default attribute, so the attribute alone
    cannot tell a comment from code, and a comment continued onto a second
    line has no delimiter at all.  The enclosing pattern is still on the
    grammar's state stack, so ask that.

    The catch is that the grammar pushes a pattern as soon as it *finds* the
    upcoming begin-match, before emitting the text in front of it: while
    `char *s = ` is being emitted the string pattern is already on the stack.
    psfMatchBeginDone, set once a begin-match has actually been consumed,
    is what separates "inside it" from "about to enter it". }
  function InsideProsePattern: Boolean;
  var
    St: TTextMatePatternState;
    i, k: Integer;
  begin
    Result := False;
    if not (HL is TSynTextMateSyn) then Exit;
    St := TSynTextMateSyn(HL).TextMateGrammar.CurrentState;
    for k := St.StateIdx downto 0 do
      if (St.StateList[k].Pattern <> nil) and
         LedNameIsProse(St.StateList[k].Pattern.Name) then
      begin
        for i := k downto 0 do
          if psfMatchBeginDone in St.StateList[i].Flags then Exit(True);
        Exit(False);
      end;
  end;

  procedure Add(AFrom, ATo: Integer);
  begin
    if ATo <= AFrom then Exit;
    { Runs arrive in order, so a run touching the previous one extends it
      rather than starting another -- an apostrophe splitting a comment into
      two tokens must not split a word. }
    if (FProseCount > 0) and (FProseTo[FProseCount - 1] >= AFrom) then
    begin
      if ATo > FProseTo[FProseCount - 1] then FProseTo[FProseCount - 1] := ATo;
      Exit;
    end;
    if FProseCount >= Length(FProseFrom) then
    begin
      SetLength(FProseFrom, FProseCount + 16);
      SetLength(FProseTo, FProseCount + 16);
    end;
    FProseFrom[FProseCount] := AFrom;
    FProseTo[FProseCount] := ATo;
    Inc(FProseCount);
  end;

begin
  FProseCount := 0;
  HL := TCustomSynEdit(SynEdit).Highlighter;

  { Everything, when asked for everything or when there is no highlighter to
    ask -- a plain text file is prose end to end. }
  if (FScope = lssAll) or (HL = nil) then
  begin
    Add(1, Length(ALine) + 1);
    Exit;
  end;

  HL.StartAtLineIndex(ARow - 1);
  while not HL.GetEol do
  begin
    Attr := HL.GetTokenAttribute;
    { The attribute covers the native highlighters, which colour a whole
      comment or string in one go; the state stack covers TextMate. }
    if ((Attr <> nil) and LedNameIsProse(Attr.StoredName)) or
       InsideProsePattern then
    begin
      Col := HL.GetTokenPos + 1;              { GetTokenPos is 0-based }
      Len := Length(HL.GetToken);
      Add(Col, Col + Len);
    end;
    HL.Next;
  end;
end;

function TLedSpellMarkup.InProse(ACol: Integer): Boolean;
var
  i: Integer;
begin
  for i := 0 to FProseCount - 1 do
    if (ACol >= FProseFrom[i]) and (ACol < FProseTo[i]) then Exit(True);
  Result := False;
end;

procedure TLedSpellMarkup.ScanRow(ARow: Integer);
var
  Line, W: string;
  i, S, L: Integer;
begin
  FCount := 0;
  FProseCount := 0;
  if FScope = lssOff then Exit;
  if (ARow < 1) or (ARow > TCustomSynEdit(SynEdit).Lines.Count) then Exit;

  Line := TCustomSynEdit(SynEdit).Lines[ARow - 1];
  if Line = '' then Exit;

  CollectProseRuns(ARow, Line);
  if FProseCount = 0 then Exit;

  i := 1;
  while i <= Length(Line) do
  begin
    W := LedWordAt(Line, i, S, L);
    if W = '' then
    begin
      Inc(i);
      Continue;
    end;
    if InProse(S) and (not LedSpell.Check(W)) then
    begin
      if FCount >= Length(FStarts) then
      begin
        SetLength(FStarts, FCount + 16);
        SetLength(FEnds, FCount + 16);
      end;
      FStarts[FCount] := S;
      FEnds[FCount] := S + L;
      Inc(FCount);
    end;
    i := S + L;
  end;
end;

function TLedSpellMarkup.GetMarkupAttributeAtRowCol(const aRow: Integer;
  const aStartCol: TLazSynDisplayTokenBound;
  const AnRtlInfo: TLazSynDisplayRtlInfo): TSynSelectedColor;
var
  i: Integer;
begin
  Result := nil;
  if (FScope = lssOff) or (aRow <> FCurrentRow) then Exit;

  for i := 0 to FCount - 1 do
    if (aStartCol.Logical >= FStarts[i]) and (aStartCol.Logical < FEnds[i]) then
    begin
      Result := MarkupInfo;
      MarkupInfo.SetFrameBoundsLog(FStarts[i], FEnds[i]);
      Exit;
    end;
end;

procedure TLedSpellMarkup.GetNextMarkupColAfterRowCol(const aRow: Integer;
  const aStartCol: TLazSynDisplayTokenBound;
  const AnRtlInfo: TLazSynDisplayRtlInfo; out ANextPhys, ANextLog: Integer);
var
  i: Integer;
begin
  ANextPhys := -1;
  ANextLog := -1;
  if (FScope = lssOff) or (aRow <> FCurrentRow) then Exit;

  { The next boundary at or after the caller's column: either the start of a
    misspelling or the end of the one we are inside. }
  for i := 0 to FCount - 1 do
  begin
    if FStarts[i] > aStartCol.Logical then
    begin
      ANextLog := FStarts[i];
      Exit;
    end;
    if FEnds[i] > aStartCol.Logical then
    begin
      ANextLog := FEnds[i];
      Exit;
    end;
  end;
end;

end.
