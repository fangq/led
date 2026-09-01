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
  Classes, SysUtils, Controls, SynEdit, SynEditTypes,
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
