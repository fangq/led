{ led - a light editor.  Display-only truncation of very long lines.

  medit truncates any line past 4096 characters and draws a clickable "..."
  marker to reveal 4096 more, because GtkTextView's line-layout cache
  collapses on very long lines.  led's first pass at this concluded SynEdit
  did not need it, on the grounds that a 5 MB single line still *opens* in
  128 ms.  That was the wrong measurement.  `led --bench-longline` was
  already reporting the real cost in the same output:

    caret to start                                 16 ms
    caret to the middle                            77 ms
    caret to end of the long line                 121 ms
    select all                                    156 ms
    type one word at the start                    126 ms

  Opening is fine; *using* the file is not, and the shape of those numbers
  says why -- the cost tracks the caret's column, not the file size.  A
  13 MB file spread over 200k lines does every one of those in 0-2 ms.

  The scan is SynEdit's, not led's.  TSynEditStrings.GetPhysicalCharWidths
  reads Strings[Index] whole and allocates one TPhysicalCharWidth per byte
  before mapping a single column, so every logical/physical conversion on a
  5 MB line walks 5 MB.  Truncating what that method can see is therefore
  the whole fix.

  Why this is safe, which is the part the earlier deferral was right to worry
  about.  SynEdit keeps two separate paths to the text:

    * FLines, the real buffer.  TCustomSynEdit.Lines is a TSynEditLines built
      directly on it -- `FStrings := TSynEditLines.Create(FLines, ...)` -- so
      it bypasses the view chain entirely.  led loads and saves through
      Lines, so the bytes on disk are the bytes in the buffer, always.

    * FTheLinesView, the top of the view chain, which is what the caret and
      the painter use.  TSynTextViewsManager.ReconnectViews makes the
      last-added view the top one.

  So a view that shortens what it returns from Get() changes what the caret
  and the painter see and nothing else.  Edits are unaffected for a second
  reason: TSynEditStringsLinked routes reads and writes through different
  delegates, and this class overrides only the read.  An insert at column N
  reaches the buffer as column N, and N can never exceed the visible prefix,
  which is byte-identical to the buffer's.

  What this does *not* do is pretend the hidden tail is not there.  A line
  that is truncated reports the visible length, so "select to end of line"
  selects to the truncation point rather than to the real end.  medit
  behaves the same way, and it is why both offer a reveal rather than
  silently hiding text. }
unit Led.UI.LongLine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LazSynEditText, SynEditTypes;

const
  { medit's MOO_MAX_LINE_LEN. }
  LedDefaultLineLimit = 4096;

  { What the marker looks like.  medit's MOO_LONG_LINE_MARKER_TEXT. }
  LedLongLineMarker = ' ...';

type
  TLedLongLineView = class;

  { TLedLongLineDisplay

    Truncating Get() makes the caret and every metric cheap, but it does not
    change one glyph on screen: with no highlighter TLazSynDisplayBuffer
    fetches the row with FBuffer.GetPChar, straight from the raw buffer, and
    with one the highlighter is fed the buffer's line too.  Neither passes
    through the view chain, which is why the first version of this measured
    two to five times faster and still drew the whole line.

    So the byte count the painter is handed gets clamped here, and any token
    that would run past the truncation point is cut short. }
  TLedLongLineDisplay = class(TLazSynDisplayViewEx)
  private
    FOwner: TLedLongLineView;
    FVisible: Integer;   { of the row being drawn; -1 means "all of it" }
    FSoFar: Integer;     { bytes handed out for this row already }
  public
    constructor Create(AOwner: TLedLongLineView);
    procedure SetHighlighterTokensLine(ALine: TLineIdx; out ARealLine: TLineIdx;
      out AStartBytePos, ALineByteLen: Integer); override;
    function GetNextHighlighterToken(out ATokenInfo: TLazSynDisplayTokenInfo): Boolean; override;
  end;

  { TLedLongLineView }

  TLedLongLineView = class(TSynEditStringsLinked)
  private
    FLimit: Integer;
    FViewChangeStamp: int64;
    { Sparse: only lines the user has revealed past the limit appear here,
      because a file with one 5 MB line has one entry and a file with none
      has an empty list.  Keyed by line index, value is the revealed
      length. }
    FRevealed: TStringList;
    FLiveFirst, FLiveLast: Integer;
    FDisplay: TLedLongLineDisplay;
    procedure Bump;
    function RevealedLen(AIndex: Integer): Integer;
    procedure SetLimit(AValue: Integer);
  protected
    function Get(Index: integer): string; override;
    function GetViewedLines(Index: integer): string; override;
    function GetExpandedString(Index: integer): string; override;
    function GetLengthOfLongestLine: integer; override;
    function GetViewChangeStamp: int64; override;
    function GetDisplayView: TLazSynDisplayView; override;
  public
    constructor Create;
    destructor Destroy; override;

    { The untruncated line, straight from the buffer below. }
    function FullLine(AIndex: Integer): string;
    function FullLength(AIndex: Integer): Integer;

    { How much of it the caret and the painter can see. }
    function VisibleLength(AIndex: Integer): Integer;
    function IsTruncated(AIndex: Integer): Boolean;

    { Reveals one more limit's worth, or all of it.  Returns False when there
      was nothing hidden. }
    function RevealMore(AIndex: Integer): Boolean;
    function RevealAll(AIndex: Integer): Boolean;
    procedure HideAgain(AIndex: Integer);
    procedure HideAll;

    { The lines the caret or the selection is touching, which must never be
      truncated -- see the note at the top of the unit.  A no-op when the
      range has not moved, because this is called on every caret change and
      bumping the stamp forces a full relayout. }
    procedure SetLiveRange(AFirst, ALast: Integer);

    { The display view, so a check can ask what the painter would be handed
      rather than photograph the result.  Truncating Get() alone left the
      metrics short and every glyph on screen, and no assertion about the
      view caught it. }
    function Display: TLedLongLineDisplay;

    { 0 disables truncation, and is what a user who wants the old behaviour
      sets Editor/max_line_len to. }
    property Limit: Integer read FLimit write SetLimit;
  end;

implementation

{ TLedLongLineDisplay }

constructor TLedLongLineDisplay.Create(AOwner: TLedLongLineView);
begin
  inherited Create;
  FOwner := AOwner;
  FVisible := -1;
end;

procedure TLedLongLineDisplay.SetHighlighterTokensLine(ALine: TLineIdx; out
  ARealLine: TLineIdx; out AStartBytePos, ALineByteLen: Integer);
begin
  inherited SetHighlighterTokensLine(ALine, ARealLine, AStartBytePos, ALineByteLen);
  FSoFar := 0;
  FVisible := -1;
  if FOwner = nil then Exit;
  if not FOwner.IsTruncated(ARealLine) then Exit;
  FVisible := FOwner.VisibleLength(ARealLine);
  if ALineByteLen > FVisible then
    ALineByteLen := FVisible;
end;

function TLedLongLineDisplay.GetNextHighlighterToken(out
  ATokenInfo: TLazSynDisplayTokenInfo): Boolean;
var
  Room: Integer;
begin
  Result := inherited GetNextHighlighterToken(ATokenInfo);
  if not Result then Exit;
  if FVisible < 0 then Exit;

  { Tokens arrive one after another across the row, so what is left of the
    budget is what has not been handed out yet.  A token that starts past the
    point ends the row: returning False here is what stops the highlighter
    walking the remaining five megabytes. }
  Room := FVisible - FSoFar;
  if Room <= 0 then Exit(False);
  if ATokenInfo.TokenLength > Room then
    ATokenInfo.TokenLength := Room;
  Inc(FSoFar, ATokenInfo.TokenLength);
end;

{ TLedLongLineView }

constructor TLedLongLineView.Create;
begin
  FRevealed := TStringList.Create;
  FRevealed.Sorted := True;
  FRevealed.Duplicates := dupIgnore;
  FLimit := LedDefaultLineLimit;
  FLiveFirst := -1;
  FLiveLast := -1;
  FDisplay := TLedLongLineDisplay.Create(Self);
  inherited Create;
end;

destructor TLedLongLineView.Destroy;
begin
  inherited Destroy;
  FDisplay.Free;
  FRevealed.Free;
end;

function TLedLongLineView.GetDisplayView: TLazSynDisplayView;
begin
  Result := FDisplay;
end;

function TLedLongLineView.Display: TLedLongLineDisplay;
begin
  Result := FDisplay;
end;

{ Every change of what is visible has to invalidate SynEdit's layout caches,
  and GetViewChangeStamp is how a view says so.  Without this a reveal
  changes Get() and nothing repaints. }
procedure TLedLongLineView.Bump;
begin
  {$PUSH}{$Q-}{$R-}
  Inc(FViewChangeStamp);
  {$POP}
end;

function TLedLongLineView.GetViewChangeStamp: int64;
begin
  Result := inherited GetViewChangeStamp;
  {$PUSH}{$Q-}{$R-}
  Result := Result + FViewChangeStamp;
  {$POP}
end;

procedure TLedLongLineView.SetLimit(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FLimit = AValue then Exit;
  FLimit := AValue;
  FRevealed.Clear;
  Bump;
end;

function TLedLongLineView.RevealedLen(AIndex: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  if FRevealed.Count = 0 then Exit;
  i := FRevealed.IndexOf(IntToStr(AIndex));
  if i >= 0 then
    Result := PtrInt(FRevealed.Objects[i]);
end;

function TLedLongLineView.FullLine(AIndex: Integer): string;
begin
  Result := NextLines.Strings[AIndex];
end;

function TLedLongLineView.FullLength(AIndex: Integer): Integer;
begin
  Result := Length(FullLine(AIndex));
end;

function TLedLongLineView.VisibleLength(AIndex: Integer): Integer;
var
  Full, Allow: Integer;
begin
  Full := FullLength(AIndex);
  if FLimit <= 0 then Exit(Full);

  { A line the caret or selection is on is never truncated.  This is the
    invariant that keeps editing correct: SynEdit computes a selection's end
    from the line it can see, so a truncated line that takes part in an edit
    loses its tail -- `led --bench-longline` reproduced exactly that, a
    select-all then insert leaving buffer=4101 of 5242880 with the undo
    record holding only the visible part. }
  if (AIndex >= FLiveFirst) and (AIndex <= FLiveLast) then Exit(Full);

  Allow := FLimit;
  if RevealedLen(AIndex) > Allow then Allow := RevealedLen(AIndex);
  if Allow >= Full then
    Result := Full
  else
    Result := Allow;
end;

function TLedLongLineView.IsTruncated(AIndex: Integer): Boolean;
begin
  Result := (FLimit > 0) and (VisibleLength(AIndex) < FullLength(AIndex));
end;

{ The one override that matters.  Everything above -- the caret, the painter,
  GetPhysicalCharWidths and so every logical/physical conversion -- reads the
  line through here. }
function TLedLongLineView.Get(Index: integer): string;
var
  V: Integer;
begin
  Result := NextLines.Strings[Index];
  if FLimit <= 0 then Exit;
  if Length(Result) <= FLimit then Exit;
  V := VisibleLength(Index);
  { No Copy when nothing is hidden.  A live or fully revealed line has
    VisibleLength = Length, and copying a string to its own length still
    copies it -- on the caret's own 5 MB line that turned every Get into a
    5 MB memcpy and made typing slower than with the feature switched off. }
  if V >= Length(Result) then Exit;
  Result := Copy(Result, 1, V);
end;

function TLedLongLineView.GetViewedLines(Index: integer): string;
begin
  Result := Get(Index);
end;

function TLedLongLineView.GetExpandedString(Index: integer): string;
var
  V: Integer;
begin
  Result := inherited GetExpandedString(Index);
  if FLimit <= 0 then Exit;
  if Length(Result) <= FLimit then Exit;
  V := VisibleLength(Index);
  if V >= Length(Result) then Exit;
  Result := Copy(Result, 1, V);
end;

{ Uncapped, this is the other half of the cost: it is what sizes the
  horizontal scrollbar, so a 5 MB line asks for a 5-million-column range. }
function TLedLongLineView.GetLengthOfLongestLine: integer;
begin
  Result := inherited GetLengthOfLongestLine;
  if (FLimit > 0) and (Result > FLimit) then
  begin
    Result := FLimit;
    { A revealed line may legitimately be longer than the limit. }
    if FRevealed.Count > 0 then
      Result := inherited GetLengthOfLongestLine;
  end;
end;

function TLedLongLineView.RevealMore(AIndex: Integer): Boolean;
var
  Cur: Integer;
begin
  Result := False;
  if not IsTruncated(AIndex) then Exit;
  Cur := VisibleLength(AIndex);
  HideAgain(AIndex);
  FRevealed.AddObject(IntToStr(AIndex), TObject(PtrInt(Cur + FLimit)));
  Bump;
  Result := True;
end;

function TLedLongLineView.RevealAll(AIndex: Integer): Boolean;
begin
  Result := False;
  if not IsTruncated(AIndex) then Exit;
  HideAgain(AIndex);
  FRevealed.AddObject(IntToStr(AIndex), TObject(PtrInt(FullLength(AIndex))));
  Bump;
  Result := True;
end;

procedure TLedLongLineView.HideAgain(AIndex: Integer);
var
  i: Integer;
begin
  i := FRevealed.IndexOf(IntToStr(AIndex));
  if i >= 0 then
  begin
    FRevealed.Delete(i);
    Bump;
  end;
end;

procedure TLedLongLineView.SetLiveRange(AFirst, ALast: Integer);
begin
  if (FLiveFirst = AFirst) and (FLiveLast = ALast) then Exit;
  FLiveFirst := AFirst;
  FLiveLast := ALast;
  Bump;
end;

procedure TLedLongLineView.HideAll;
begin
  if FRevealed.Count = 0 then Exit;
  FRevealed.Clear;
  Bump;
end;

end.
