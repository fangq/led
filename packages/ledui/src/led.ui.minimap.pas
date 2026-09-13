{ LED - a lightweight editor.  The minimap: the whole file, too small to read.

  A strip down the right-hand side of a view showing every line as a short
  coloured bar -- one pixel per character, two per line -- with the part of
  the file currently on screen boxed.  Clicking or dragging in it scrolls the
  text.  Sublime Text introduced it and VS Code made it standard; what it is
  good for is shape rather than content: where the long functions are, where
  the comment blocks are, roughly how far down the file you are.

  Drawn rather than rendered.  The obvious implementation -- a second SynEdit
  with a two-point font -- was not attempted: SynEdit's smallest useful font
  is still several pixels a line, it lays out and folds and wraps
  independently, and every one of its own paint costs would be paid twice.
  Bars are cheaper than glyphs and, at this size, no less informative: a
  glyph two pixels tall is a smudge in the colour of its token, which is what
  this draws directly.

  The colours come from the document's own highlighter, asked line by line.
  That is safe to do here because the ranges it reads were computed by the
  editor's own scan -- this only replays them -- and because the highlighter's
  position is restored afterwards, which matters when two views share one.

  Drawn in view space, not text space: a folded block is one line here
  because it is one line on screen.  SynEdit's TopLine is in view space too,
  so this is also the coordinate the scrolling has to be done in -- drawn and
  scrolled in text lines instead, a file with anything folded shut scrolled
  to the wrong place, and further wrong the more was folded.

  Only the lines that fit are drawn.  A minimap of a hundred-thousand-line
  file cannot show every line in three hundred pixels, and scaling lines
  together into one bar loses exactly the shape the thing exists to show, so
  instead it scrolls: the strip is a window onto the file, positioned so that
  the boxed part sits where the caret is in the file as a whole. }
unit Led.UI.MiniMap;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LCLType, Forms,
  SynEdit, SynEditTypes, SynEditHighlighter,
  Led.UI.Edit, Led.UI.Dpi, Led.Syn.Factory;

type

  { TLedMiniMap }

  TLedMiniMap = class(TCustomControl)
  private
    FEdit: TLedEdit;
    FDragging: Boolean;
    FRowHeight: Integer;
    FColWidth: Integer;
    FTopLine: Integer;          { first document line drawn, 1 based }
    procedure EditStatusChange(Sender: TObject; AChanges: TSynStatusChanges);
    procedure DetachEdit;
    function LinesThatFit: Integer;
    function DocLineCount: Integer;
    procedure ScrollTo(AY: Integer);
    procedure PaintLine(AViewPos, AY: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure Notification(AComponent: TComponent;
      Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { The view this maps.  Attaching hooks the view's status changes, which is
      how the box follows the text; detaching is automatic when either goes. }
    procedure Attach(AEdit: TLedEdit);

    { Takes the editor's colours.  Called when the theme changes, and once on
      attach; the strip is a picture of the page and has to be lit like it. }
    procedure ApplyTheme;

    { Which document line the top of the strip is showing, and which line is
      at a given pixel row.  Public for the checks, which have no other way
      to ask what the picture is of. }
    property TopLine: Integer read FTopLine;
    function LineAtY(AY: Integer): Integer;
    function RowHeight: Integer;
    function LinesShown: Integer;
    property Editor: TLedEdit read FEdit;
  end;

{ How wide a minimap is, in device pixels: about eighty characters at one
  pixel each, which is the width a file is usually written to. }
function LedMiniMapWidth: Integer;

implementation

function LedMiniMapWidth: Integer;
begin
  Result := LedScale96(86);
end;

{ How wide the shadow down the left edge is, in device pixels. }
function ShadowWidth: Integer;
begin
  Result := LedScale96(6);
  if Result < 3 then Result := 3;
end;

constructor TLedMiniMap.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FTopLine := 1;
  { Two pixels a line and one a character.  Scaled, because on a 200% display
    a one-pixel bar is half a logical pixel and the whole strip reads as a
    smear. }
  FRowHeight := LedScale96(2);
  if FRowHeight < 2 then FRowHeight := 2;
  FColWidth := LedScale96(1);
  if FColWidth < 1 then FColWidth := 1;
  Width := LedMiniMapWidth;
  Cursor := crArrow;
end;

destructor TLedMiniMap.Destroy;
begin
  DetachEdit;
  inherited Destroy;
end;

procedure TLedMiniMap.DetachEdit;
begin
  if FEdit = nil then Exit;
  FEdit.UnRegisterStatusChangedHandler(@EditStatusChange);
  FEdit.RemoveFreeNotification(Self);
  FEdit := nil;
end;

procedure TLedMiniMap.Attach(AEdit: TLedEdit);
begin
  if AEdit = FEdit then Exit;
  DetachEdit;
  FEdit := AEdit;
  if FEdit = nil then Exit;
  FEdit.FreeNotification(Self);
  { scTopLine for the scrollbar and the wheel, scCaretY for a caret moved by
    the keyboard, scLinesInWindow for a resized view, and scModified because
    typing changes the shape of what is drawn.  Registered rather than
    assigned: OnStatusChange belongs to the main form, which uses it for the
    status bar and the preview. }
  FEdit.RegisterStatusChangedHandler(@EditStatusChange,
    [scTopLine, scCaretY, scLinesInWindow, scModified]);
  ApplyTheme;
  Invalidate;
end;

procedure TLedMiniMap.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FEdit) then
    FEdit := nil;
end;

procedure TLedMiniMap.ApplyTheme;
begin
  if FEdit = nil then Exit;
  { A shade off the page rather than the page itself, so the strip reads as a
    separate thing and its edge does not need a rule drawn down it.

    Six parts ink to ninety-four of page -- that way round.  Written the other
    way it was ninety-four parts ink, which on a light theme is a black strip
    down the side of a white page: not a shade off the page but the opposite
    of it. }
  Color := LedMixColours(FEdit.Font.Color, FEdit.Color, 6);
  Invalidate;
end;

function TLedMiniMap.RowHeight: Integer;
begin
  Result := FRowHeight;
end;

{ In view lines -- see the note at the top of the unit. }
function TLedMiniMap.DocLineCount: Integer;
begin
  Result := 0;
  if FEdit <> nil then Result := FEdit.ViewLineCount;
end;

function TLedMiniMap.LinesThatFit: Integer;
begin
  Result := Height div FRowHeight;
  if Result < 1 then Result := 1;
end;

function TLedMiniMap.LinesShown: Integer;
begin
  Result := LinesThatFit;
  if Result > DocLineCount then Result := DocLineCount;
end;

function TLedMiniMap.LineAtY(AY: Integer): Integer;
begin
  Result := FTopLine + (AY div FRowHeight);
  if Result < 1 then Result := 1;
  if Result > DocLineCount then Result := DocLineCount;
end;

procedure TLedMiniMap.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TLedMiniMap.EditStatusChange(Sender: TObject;
  AChanges: TSynStatusChanges);
begin
  Invalidate;
end;

{ AViewPos is 1-based and in view space; the text it shows may be any line of
  the buffer, and is what the highlighter is asked about. }
procedure TLedMiniMap.PaintLine(AViewPos, AY: Integer);
var
  AIndex: Integer;
  S: string;
  HL: TSynCustomHighlighter;
  Attr: TSynHighlighterAttributes;
  Tok: PChar;
  TokLen, TokPos, X, W, i: Integer;
  Ink: TColor;
begin
  if FEdit = nil then Exit;
  AIndex := FEdit.ViewLineToTextIndex(AViewPos);
  if (AIndex < 0) or (AIndex >= FEdit.Lines.Count) then Exit;
  S := FEdit.Lines[AIndex];
  if Trim(S) = '' then Exit;

  HL := FEdit.Highlighter;
  Ink := LedMixColours(FEdit.Font.Color, Color, 82);

  if HL = nil then
  begin
    { No highlighter: one bar for the line, indentation included, so the shape
      of the file is still there. }
    i := 1;
    while (i <= Length(S)) and (S[i] in [#9, ' ']) do Inc(i);
    X := ShadowWidth + (i - 1) * FColWidth;
    W := (Length(TrimRight(S)) - (i - 1)) * FColWidth;
    if W <= 0 then Exit;
    Canvas.Brush.Color := Ink;
    Canvas.FillRect(X, AY, X + W, AY + FRowHeight - 1);
    Exit;
  end;

  { Token by token, in the token's own colour.  StartAtLineIndex replays the
    range the editor's own scan stored for the line before this one, so this
    is a re-run of work already done rather than a second scan of the file. }
  HL.StartAtLineIndex(AIndex);
  while not HL.GetEol do
  begin
    HL.GetTokenEx(Tok, TokLen);
    TokPos := HL.GetTokenPos;
    if TokLen > 0 then
    begin
      Attr := HL.GetTokenAttribute;
      if (Attr <> nil) and (Attr.Foreground <> clNone) then
        Ink := LedMixColours(Attr.Foreground, Color, 82)
      else
        Ink := LedMixColours(FEdit.Font.Color, Color, 82);

      { Whitespace leaves a gap -- that gap is the indentation, which is most
        of what a minimap shows. }
      if Trim(Copy(S, TokPos + 1, TokLen)) <> '' then
      begin
        X := ShadowWidth + TokPos * FColWidth;
        W := TokLen * FColWidth;
        if X < Width then
        begin
          if X + W > Width then W := Width - X;
          Canvas.Brush.Color := Ink;
          Canvas.FillRect(X, AY, X + W, AY + FRowHeight - 1);
        end;
      end;
    end;
    HL.Next;
  end;
end;

{ Where the strip sits in the file.

  Whole file in view: the top.  Otherwise the strip is placed in proportion to
  how far down the file the view is -- at the top of the file the strip starts
  at line one, at the bottom it ends at the last line, and in between it moves
  smoothly.  The box therefore stays inside the strip without the strip having
  to be dragged separately, which is the behaviour Sublime and VS Code share
  and the reason neither gives the minimap a scrollbar of its own. }
procedure TLedMiniMap.Paint;
var
  Fit, Count, Last, i, Y: Integer;
  Span, First: Integer;
  BoxTop, BoxBottom: Integer;
  Wash: TColor;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  if FEdit = nil then Exit;

  Count := DocLineCount;
  if Count <= 0 then Exit;
  Fit := LinesThatFit;

  { Where the window onto the file sits.  Proportional to how far down the
    file the view is, so the box is always inside the strip. }
  if Count <= Fit then
    FTopLine := 1
  else
  begin
    Span := Count - FEdit.LinesInWindow;
    if Span < 1 then Span := 1;
    First := FEdit.TopLine - 1;
    if First < 0 then First := 0;
    if First > Span then First := Span;
    FTopLine := 1 + Round(First * ((Count - Fit) / Span));
    if FTopLine < 1 then FTopLine := 1;
  end;

  Last := FTopLine + Fit - 1;
  if Last > Count then Last := Count;

  { The box first, under the bars: a wash the text is drawn over reads as the
    page behind it, where one drawn over the text dims exactly the part being
    looked at. }
  BoxTop := (FEdit.TopLine - FTopLine) * FRowHeight;
  BoxBottom := BoxTop + FEdit.LinesInWindow * FRowHeight;
  if (BoxBottom > 0) and (BoxTop < Height) then
  begin
    Wash := LedMixColours(FEdit.Font.Color, FEdit.Color, 14);
    Canvas.Brush.Color := Wash;
    Canvas.FillRect(0, BoxTop, Width, BoxBottom);
  end;

  Y := 0;
  for i := FTopLine to Last do
  begin
    PaintLine(i, Y);
    Inc(Y, FRowHeight);
  end;

  { A shadow down the left edge, so the strip reads as sitting above the page
    rather than butted against it.  Six columns, each a little less of the
    ink colour than the last -- a gradient rather than a rule, which is what
    makes it read as depth instead of as a border. }
  for i := 0 to ShadowWidth - 1 do
  begin
    Canvas.Brush.Color := LedMixColours(FEdit.Font.Color, Color,
      14 - (14 * i) div ShadowWidth);
    Canvas.FillRect(i, 0, i + 1, Height);
  end;

  { And its edges over everything, so the boundary is readable against bars
    of any colour. }
  if (BoxBottom > 0) and (BoxTop < Height) then
  begin
    Canvas.Brush.Color := LedMixColours(FEdit.Font.Color, FEdit.Color, 34);
    Canvas.FillRect(0, BoxTop, Width, BoxTop + 1);
    Canvas.FillRect(0, BoxBottom - 1, Width, BoxBottom);
  end;
end;

{ Clicking puts the line under the pointer in the middle of the view, rather
  than at its top: a click in a minimap is "show me this", and what is wanted
  is the thing clicked with its surroundings, not the thing clicked pinned to
  the first row. }
procedure TLedMiniMap.ScrollTo(AY: Integer);
var
  Line, First: Integer;
begin
  if FEdit = nil then Exit;
  Line := LineAtY(AY);
  First := Line - FEdit.LinesInWindow div 2;
  if First < 1 then First := 1;
  { View lines, because TopLine is one.  Clamped against the view's own count
    rather than the buffer's: with a block folded there are fewer of them. }
  if First > FEdit.ViewLineCount then First := FEdit.ViewLineCount;
  FEdit.TopLine := First;
end;

procedure TLedMiniMap.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FDragging := True;
  ScrollTo(Y);
end;

procedure TLedMiniMap.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging and (ssLeft in Shift) then
    ScrollTo(Y);
end;

procedure TLedMiniMap.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

end.
