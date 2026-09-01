{ led - a light editor.  Editing commands.

  The operations that are more than a SynEdit call: comment/uncomment driven
  by the grammar's own markers, the one-space indent shift medit bound to
  Ctrl+0 and Ctrl+9, bracket navigation, and font zoom.

  Each one is a plain procedure over a view rather than a method, so the same
  command can be reached from a menu, a keystroke or a script without any of
  them owning it. }
unit Led.UI.Commands;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Clipbrd, SynEdit, SynEditTypes,
  SynEditHighlighter, SynEditHighlighterFoldBase,
  Led.Syn.Languages, Led.UI.Edit;

{ Moves the caret to ALine, clamped, and scrolls it into view. }
procedure LedGotoLine(AView: TLedEdit; ALine: Integer);

{ Ctrl+]: jumps between a bracket and its match.  Because the caret lands on
  the partner, pressing it again comes straight back. }
procedure LedToggleMatchingBracket(AView: TLedEdit);
procedure LedSelectToMatchingBracket(AView: TLedEdit);

{ Ctrl+0 adds one leading space to every selected line, Ctrl+9 removes one.
  Distinct from Tab/Shift-Tab, which shift by the indent width.  The whole
  block is one undo step. }
procedure LedShiftLinesBySpace(AView: TLedEdit; AAdd: Boolean);

{ Comments or uncomments the selected lines using ALang's markers.  Line
  comments are inserted at the common indentation of the block rather than at
  column one, which keeps indented code readable.  Falls back to the block
  comment when the language has no line comment. }
procedure LedCommentLines(AView: TLedEdit; ALang: TLedLangInfo);
procedure LedUncommentLines(AView: TLedEdit; ALang: TLedLangInfo);
function LedCanComment(ALang: TLedLangInfo): Boolean;

{ Temporary zoom, clamped to a sane range and never written to preferences. }
procedure LedZoomFont(AView: TLedEdit; ADelta: Integer);

{ Pastes the clipboard as a rectangular block at the caret's column: each
  clipboard line goes on a successive document line, at the same column,
  padding short lines with spaces.

  SynEdit already round-trips its own column selections through the clipboard,
  and understands the MSDEV column format, so this is for the other case --
  text copied from somewhere that does not mark it as a column at all.  With
  a column selection active the rectangle is replaced rather than pushed
  aside. }
procedure LedPasteColumn(AView: TLedEdit);

{ Escape: drop the selection but keep the caret. }
procedure LedClearSelection(AView: TLedEdit);

function LedHasColumnSelection(AView: TLedEdit): Boolean;

{ Folding.  SynEdit builds its fold tree from the highlighter, so these do
  nothing unless the active highlighter provides fold information -- Pascal,
  XML, HTML and LFM today, and every converted grammar once TextMate
  highlighting lands.  LedCanFold reports which, so the menu can grey out
  rather than appear broken. }
function LedCanFold(AView: TLedEdit): Boolean;
procedure LedToggleFold(AView: TLedEdit);
procedure LedFoldAll(AView: TLedEdit);
procedure LedUnfoldAll(AView: TLedEdit);

const
  LedMinFontSize = 4;
  LedMaxFontSize = 72;

implementation

procedure LedGotoLine(AView: TLedEdit; ALine: Integer);
begin
  if AView = nil then Exit;
  if ALine < 1 then ALine := 1;
  if ALine > AView.Lines.Count then ALine := AView.Lines.Count;
  AView.CaretXY := Point(1, ALine);
  AView.EnsureCursorPosVisible;
end;

procedure LedToggleMatchingBracket(AView: TLedEdit);
begin
  if AView = nil then Exit;
  AView.FindMatchingBracket(AView.CaretXY, True, True, False, False);
end;

procedure LedSelectToMatchingBracket(AView: TLedEdit);
begin
  if AView = nil then Exit;
  AView.FindMatchingBracket(AView.CaretXY, True, True, True, False);
end;

{ Re-selects lines AFirst..ALast.  Block commands have to do this explicitly:
  editing through TextBetweenPoints collapses the selection, and without
  restoring it a second command -- uncomment right after comment, say --
  silently acts on the caret line alone. }
procedure ReselectLines(AView: TLedEdit; AFirst, ALast: Integer);
begin
  if ALast > AView.Lines.Count then ALast := AView.Lines.Count;
  if AFirst < 1 then AFirst := 1;
  if ALast < AFirst then Exit;
  AView.BlockBegin := Point(1, AFirst);
  if ALast < AView.Lines.Count then
    AView.BlockEnd := Point(1, ALast + 1)
  else
    AView.BlockEnd := Point(Length(AView.Lines[ALast - 1]) + 1, ALast);
end;

{ The line range a block operation should act on.  A selection that ends at
  column one does not include that last line -- otherwise selecting three
  lines by dragging down the gutter would comment four. }
procedure SelectedLineRange(AView: TLedEdit; out AFirst, ALast: Integer);
begin
  if AView.SelAvail then
  begin
    AFirst := AView.BlockBegin.Y;
    ALast := AView.BlockEnd.Y;
    if (ALast > AFirst) and (AView.BlockEnd.X = 1) then
      Dec(ALast);
  end
  else
  begin
    AFirst := AView.CaretY;
    ALast := AFirst;
  end;
end;

procedure LedShiftLinesBySpace(AView: TLedEdit; AAdd: Boolean);
var
  First, Last, i: Integer;
  S: string;
  Caret: TPoint;
  HadSelection: Boolean;
begin
  if (AView = nil) or AView.ReadOnly then Exit;
  HadSelection := AView.SelAvail;
  SelectedLineRange(AView, First, Last);
  Caret := AView.CaretXY;

  AView.BeginUndoBlock;
  try
    for i := First to Last do
    begin
      S := AView.Lines[i - 1];
      if AAdd then
        AView.TextBetweenPoints[Point(1, i), Point(1, i)] := ' '
      else if (S <> '') and (S[1] = ' ') then
        AView.TextBetweenPoints[Point(1, i), Point(2, i)] := '';
    end;
  finally
    AView.EndUndoBlock;
  end;

  if HadSelection then
    ReselectLines(AView, First, Last)
  else
  begin
    { Keep the caret on the same character it was on. }
    if AAdd then Inc(Caret.X) else if Caret.X > 1 then Dec(Caret.X);
    AView.CaretXY := Caret;
  end;
end;

function LedCanComment(ALang: TLedLangInfo): Boolean;
begin
  Result := (ALang <> nil) and ALang.HasComments;
end;

{ Leading whitespace of S, measured in characters. }
function IndentOf(const S: string): Integer;
begin
  Result := 0;
  while (Result < Length(S)) and (S[Result + 1] in [' ', #9]) do
    Inc(Result);
end;

procedure LedCommentLines(AView: TLedEdit; ALang: TLedLangInfo);
var
  First, Last, i, Common, Ind: Integer;
  S, Marker: string;
  AnyContent: Boolean;
begin
  if (AView = nil) or AView.ReadOnly or not LedCanComment(ALang) then Exit;
  SelectedLineRange(AView, First, Last);

  if ALang.LineComment <> '' then
  begin
    Marker := ALang.LineComment + ' ';

    { Insert at the shallowest indentation in the block, so a commented
      block keeps its shape.  Blank lines are ignored when measuring. }
    Common := MaxInt;
    AnyContent := False;
    for i := First to Last do
    begin
      S := AView.Lines[i - 1];
      if Trim(S) = '' then Continue;
      AnyContent := True;
      Ind := IndentOf(S);
      if Ind < Common then Common := Ind;
    end;
    if not AnyContent then Common := 0;

    AView.BeginUndoBlock;
    try
      for i := First to Last do
      begin
        S := AView.Lines[i - 1];
        if (Trim(S) = '') and (First <> Last) then Continue;
        if Length(S) < Common then
          AView.TextBetweenPoints[Point(Length(S) + 1, i),
                                  Point(Length(S) + 1, i)] := Marker
        else
          AView.TextBetweenPoints[Point(Common + 1, i),
                                  Point(Common + 1, i)] := Marker;
      end;
    finally
      AView.EndUndoBlock;
    end;
    ReselectLines(AView, First, Last);
  end
  else
  begin
    { No line comment: wrap the whole block.  The closing marker is written
      first, so appending it cannot shift the opening marker's position. }
    AView.BeginUndoBlock;
    try
      S := AView.Lines[Last - 1];
      AView.TextBetweenPoints[Point(Length(S) + 1, Last),
                              Point(Length(S) + 1, Last)] :=
        ' ' + ALang.BlockCommentEnd;
      AView.TextBetweenPoints[Point(1, First), Point(1, First)] :=
        ALang.BlockCommentStart + ' ';
    finally
      AView.EndUndoBlock;
    end;
    ReselectLines(AView, First, Last);
  end;
end;

procedure LedUncommentLines(AView: TLedEdit; ALang: TLedLangInfo);
var
  First, Last, i, P, Len: Integer;
  S: string;
begin
  if (AView = nil) or AView.ReadOnly or not LedCanComment(ALang) then Exit;
  SelectedLineRange(AView, First, Last);

  AView.BeginUndoBlock;
  try
    if ALang.LineComment <> '' then
      for i := First to Last do
      begin
        S := AView.Lines[i - 1];
        P := Pos(ALang.LineComment, S);
        if P = 0 then Continue;
        { Only a marker that starts the line's content counts; one inside
          code is part of the code. }
        if Trim(Copy(S, 1, P - 1)) <> '' then Continue;
        Len := Length(ALang.LineComment);
        { Take the single space commenting added, if it is still there. }
        if Copy(S, P + Len, 1) = ' ' then Inc(Len);
        AView.TextBetweenPoints[Point(P, i), Point(P + Len, i)] := '';
      end
    else
    begin
      { Trailing marker first, so removing the leading one cannot invalidate
        the position of the trailing one. }
      S := AView.Lines[Last - 1];
      P := Pos(ALang.BlockCommentEnd, S);
      if P > 0 then
      begin
        Len := Length(ALang.BlockCommentEnd);
        if (P > 1) and (S[P - 1] = ' ') then
        begin
          Dec(P);
          Inc(Len);
        end;
        AView.TextBetweenPoints[Point(P, Last), Point(P + Len, Last)] := '';
      end;
      S := AView.Lines[First - 1];
      P := Pos(ALang.BlockCommentStart, S);
      if P > 0 then
      begin
        Len := Length(ALang.BlockCommentStart);
        if Copy(S, P + Len, 1) = ' ' then Inc(Len);
        AView.TextBetweenPoints[Point(P, First), Point(P + Len, First)] := '';
      end;
    end;
  finally
    AView.EndUndoBlock;
  end;
  ReselectLines(AView, First, Last);
end;

function LedHasColumnSelection(AView: TLedEdit): Boolean;
begin
  Result := (AView <> nil) and AView.SelAvail and
    (AView.SelectionMode = smColumn);
end;

procedure LedClearSelection(AView: TLedEdit);
var
  P: TPoint;
begin
  if (AView = nil) or not AView.SelAvail then Exit;
  P := AView.CaretXY;
  AView.SelStart := AView.SelEnd;
  AView.CaretXY := P;
end;

procedure LedPasteColumn(AView: TLedEdit);
var
  Lines: TStringList;
  i, Col, Line, Deficit: Integer;
  Text, Existing: string;
begin
  if (AView = nil) or AView.ReadOnly then Exit;
  Text := Clipboard.AsText;
  if Text = '' then Exit;

  Lines := TStringList.Create;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    Lines.Text := Text;
    { TStrings.Text adds a terminator, which would paste a stray blank line. }
    while (Lines.Count > 0) and (Lines[Lines.Count - 1] = '') do
      Lines.Delete(Lines.Count - 1);
    if Lines.Count = 0 then Exit;

    AView.BeginUndoBlock;
    try
      if LedHasColumnSelection(AView) then
      begin
        Col := AView.BlockBegin.X;
        Line := AView.BlockBegin.Y;
        AView.SelText := '';         { clears the rectangle, column-wise }
        AView.CaretXY := Point(Col, Line);
      end
      else
      begin
        Col := AView.CaretX;
        Line := AView.CaretY;
      end;

      for i := 0 to Lines.Count - 1 do
      begin
        { Past the last line, extend the document rather than losing text. }
        while AView.Lines.Count < Line + i do
          AView.TextBetweenPoints[
            Point(Length(AView.Lines[AView.Lines.Count - 1]) + 1,
                  AView.Lines.Count),
            Point(Length(AView.Lines[AView.Lines.Count - 1]) + 1,
                  AView.Lines.Count)] := LineEnding;

        Existing := AView.Lines[Line + i - 1];
        Deficit := Col - 1 - Length(Existing);
        if Deficit > 0 then
          AView.TextBetweenPoints[
            Point(Length(Existing) + 1, Line + i),
            Point(Length(Existing) + 1, Line + i)] := StringOfChar(' ', Deficit);

        AView.TextBetweenPoints[Point(Col, Line + i), Point(Col, Line + i)] :=
          Lines[i];
      end;
    finally
      AView.EndUndoBlock;
    end;

    AView.CaretXY := Point(Col, Line + Lines.Count - 1);
  finally
    Lines.Free;
  end;
end;

function LedCanFold(AView: TLedEdit): Boolean;
begin
  Result := (AView <> nil) and (AView.Highlighter <> nil) and
    (AView.Highlighter is TSynCustomFoldHighlighter);
end;

{ TSynEdit keeps its fold view private and exposes only these three, which
  carry a deprecated marker but are the whole public surface for folding.
  Wrapping them here means one place to revisit if that changes. }
{$PUSH}{$WARN SYMBOL_DEPRECATED OFF}
{ Folds or unfolds the block the caret is in.

  Not CodeFoldAction: that resolves the line to a screen row first and does
  nothing at all unless the display happens to be in the state it expects --
  measured, it never fired from a menu.  The folded view's own method works
  from the text and is forgiving about where inside the block you point it.

  Its index is 0-based, whatever its comment says; that was measured too. }
procedure LedToggleFold(AView: TLedEdit);
var
  Idx: Integer;
  Before: string;
begin
  if not LedCanFold(AView) then Exit;
  Idx := AView.CaretY - 1;
  Before := AView.FoldState;

  { Unfold first: if the caret is inside something folded, that is what the
    reader means.  If nothing was folded there, this changes nothing and the
    fold is applied instead. }
  AView.FoldedView.UnFoldAtTextIndex(Idx);
  if AView.FoldState <> Before then Exit;
  AView.FoldedView.FoldAtTextIndex(Idx);
end;

procedure LedFoldAll(AView: TLedEdit);
begin
  if not LedCanFold(AView) then Exit;
  AView.FoldAll(0, True);
end;

procedure LedUnfoldAll(AView: TLedEdit);
begin
  if not LedCanFold(AView) then Exit;
  AView.UnfoldAll;
end;
{$POP}

procedure LedZoomFont(AView: TLedEdit; ADelta: Integer);
var
  Size: Integer;
begin
  if AView = nil then Exit;
  Size := AView.Font.Size + ADelta;
  if Size < LedMinFontSize then Size := LedMinFontSize;
  if Size > LedMaxFontSize then Size := LedMaxFontSize;
  AView.Font.Size := Size;
end;

end.
