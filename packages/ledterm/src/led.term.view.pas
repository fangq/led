{ led - a light editor.  The terminal widget.

  Custom-drawn, because there is nothing in LCL to draw a character grid with
  per-cell colour.  It owns a pseudo-terminal and a screen model; a timer
  drains the child's output into the model and repaints when something
  changed.

  Reading on a timer rather than a thread is deliberate: the model is not
  thread-safe and the painting has to happen on the UI thread anyway, so a
  thread would buy nothing but a synchronisation problem. }
unit Led.Term.View;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, ExtCtrls, LCLType,
  LCLIntf,
  Led.Term.Pty, Led.Term.Screen;

type
  TLedTermScheme = record
    Name: string;
    Foreground, Background, Cursor: TColor;
    Palette: array[0..15] of TColor;
  end;

  TLedTermView = class(TCustomControl)
  private
    FInFontChange: Boolean;
    FPty: TLedPty;
    FScreen: TLedTermScreen;
    FTimer: TTimer;
    FLastCols, FLastRows: Integer;
    FCharW, FCharH: Integer;
    { Mouse selection, in cell coordinates on the visible screen.  Anchor is
      where the drag began and Head where it is now; either may be the
      earlier of the two, so the pair is ordered only when it is used. }
    FSelAnchor, FSelHead: TPoint;
    FSelecting: Boolean;
    FHasSel: Boolean;
    FScheme: Integer;
    FScrollOffset: Integer;    // lines scrolled back; 0 is the live view
    FOnTitleChange: TNotifyEvent;
    FOnExited: TNotifyEvent;
    procedure Poll(Sender: TObject);
    procedure MeasureFont;
    function ColourOf(AIndex: SmallInt; ADefault: TColor): TColor;
    procedure SendKey(const S: string);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    function CellAt(X, Y: Integer): TPoint;
    function SelectionOrdered(out AFrom, ATo: TPoint): Boolean;
    function CellSelected(ACol, ARow: Integer): Boolean;
    procedure DoEnter; override;
    procedure FontChanged(Sender: TObject); override;
    class function GetControlClassDefaultSize: TSize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function Start(const ACommand, AWorkDir: string): Boolean;
    procedure Stop;
    function Running: Boolean;
    procedure Paste(const AText: string);
    procedure SetScheme(AIndex: Integer);
    function SchemeName(AIndex: Integer): string;

    { The selected text, rows joined by newlines and trailing blanks on each
      row trimmed -- a terminal pads every row to full width, and pasting
      that padding back is never what anyone wants. }
    function SelectedText: string;
    function HasSelection: Boolean;
    procedure ClearSelection;
    procedure SelectAll;
    function SchemeCount: Integer;

    property Screen: TLedTermScreen read FScreen;
    property OnTitleChange: TNotifyEvent read FOnTitleChange write FOnTitleChange;
    property OnExited: TNotifyEvent read FOnExited write FOnExited;
  end;

{ The palette list, without needing a terminal to ask.  The pane used to
  construct a throwaway TLedTermView purely to read the names for its menu. }
function LedTermSchemeCount: Integer;
function LedTermSchemeName(AIndex: Integer): string;

implementation

const
  { medit shipped ten named ANSI palettes (mooterminal.c:86); all ten are
    here as data, followed by led's own.  The cursor takes the foreground,
    which is what VTE does when a scheme does not name one.

    Colours are TColor, so $00BBGGRR -- the byte order is reversed from the
    #rrggbb in the C source, and these were converted rather than retyped. }
  Schemes: array[0..10] of TLedTermScheme = (
    (Name: 'Default'; Foreground: $ECECEC; Background: $000000;
     Cursor: $ECECEC;
     Palette: ($211417, $281CC0, $18B218, $4C73A2, $8B4812, $B218B2,
               $B3A12A, $CCCFD0, $645C5E, $5161F6, $7AD133, $0CADE9,
               $DE7B2A, $CB61C0, $DEC733, $FFFFFF)),
    (Name: 'Black on White'; Foreground: $000000; Background: $FFFFFF;
     Cursor: $000000;
     Palette: ($000000, $1818B2, $18B218, $1868B2, $B21818, $B218B2,
               $B2B218, $B2B2B2, $686868, $5454FF, $54FF54, $54FFFF,
               $FF5454, $FF54FF, $FFFF54, $FFFFFF)),
    (Name: 'Black on Light Yellow'; Foreground: $000000; Background: $DDFFFF;
     Cursor: $000000;
     Palette: ($000000, $1818B2, $18B218, $1868B2, $B21818, $B218B2,
               $B2B218, $B2B2B2, $686868, $5454FF, $54FF54, $54FFFF,
               $FF5454, $FF54FF, $FFFF54, $FFFFFF)),
    (Name: 'Marble'; Foreground: $FFFFFF; Background: $000000;
     Cursor: $FFFFFF;
     Palette: ($000000, $1818B2, $18B218, $1868B2, $B21818, $B218B2,
               $B2B218, $B2B2B2, $686868, $5454FF, $54FF54, $54FFFF,
               $FF5454, $FF54FF, $FFFF54, $FFFFFF)),
    (Name: 'Green on Black'; Foreground: $18F018; Background: $000000;
     Cursor: $18F018;
     Palette: ($000000, $1818B2, $18B218, $1868B2, $B21818, $B218B2,
               $B2B218, $B2B2B2, $686868, $5454FF, $54FF54, $54FFFF,
               $FF5454, $FF54FF, $FFFF54, $FFFFFF)),
    (Name: 'Paper, Light'; Foreground: $000000; Background: $FFFFFF;
     Cursor: $000000;
     Palette: ($000000, $1818B2, $18B218, $1868B2, $B21818, $B218B2,
               $B2B218, $B2B2B2, $686868, $5454FF, $54FF54, $54FFFF,
               $FF5454, $FF54FF, $FFFF54, $FFFFFF)),
    (Name: 'Paper'; Foreground: $000000; Background: $FFFFFF;
     Cursor: $000000;
     Palette: ($000000, $1818B2, $18B218, $1868B2, $B21818, $B218B2,
               $B2B218, $B2B2B2, $686868, $5454FF, $54FF54, $54FFFF,
               $FF5454, $FF54FF, $FFFF54, $FFFFFF)),
    (Name: 'Linux Colors'; Foreground: $B2B2B2; Background: $000000;
     Cursor: $B2B2B2;
     Palette: ($000000, $1818B2, $18B218, $1868B2, $B21818, $B218B2,
               $B2B218, $B2B2B2, $686868, $5454FF, $54FF54, $54FFFF,
               $FF5454, $FF54FF, $FFFF54, $FFFFFF)),
    (Name: 'VIM Colors'; Foreground: $000000; Background: $FFFFFF;
     Cursor: $000000;
     Palette: ($000000, $0000C0, $008000, $008080, $C00000, $C000C0,
               $808000, $C0C0C0, $808080, $6060FF, $00FF00, $00FFFF,
               $FF8080, $FF40FF, $FFFF00, $FFFFFF)),
    (Name: 'White on Black'; Foreground: $FFFFFF; Background: $000000;
     Cursor: $FFFFFF;
     Palette: ($000000, $1818B2, $18B218, $1868B2, $B21818, $B218B2,
               $B2B218, $B2B2B2, $686868, $5454FF, $54FF54, $54FFFF,
               $FF5454, $FF54FF, $FFFF54, $FFFFFF)),
    (Name: 'Solarized Dark'; Foreground: $98A183; Background: $362B00;
     Cursor: $98A183;
     Palette: ($362B00, $1B26DC, $868900, $89A716, $2F32CB, $8236D3,
               $98A125, $D5E8EE, $423607, $9A5F26, $756E58, $837B65,
               $96A1A1, $A1A6C3, $ACB0B0, $E3F6FD))
  );

{ Screen cell under a pixel, clamped, so a drag that leaves the window keeps
  extending the selection instead of stopping at the edge. }
function TLedTermView.CellAt(X, Y: Integer): TPoint;
begin
  if FCharW < 1 then Exit(Point(0, 0));
  Result.X := X div FCharW;
  Result.Y := Y div FCharH;
  if Result.X < 0 then Result.X := 0;
  if Result.Y < 0 then Result.Y := 0;
  if Result.X > FScreen.Cols then Result.X := FScreen.Cols;
  if Result.Y > FScreen.Rows - 1 then Result.Y := FScreen.Rows - 1;
end;

function TLedTermView.SelectionOrdered(out AFrom, ATo: TPoint): Boolean;
begin
  Result := FHasSel;
  if not Result then Exit;
  AFrom := FSelAnchor;
  ATo := FSelHead;
  if (ATo.Y < AFrom.Y) or ((ATo.Y = AFrom.Y) and (ATo.X < AFrom.X)) then
  begin
    AFrom := FSelHead;
    ATo := FSelAnchor;
  end;
end;

{ Selection runs by lines, not as a rectangle: everything from the start cell
  to the end cell in reading order, which is what a terminal selection means
  when the text wraps. }
function TLedTermView.CellSelected(ACol, ARow: Integer): Boolean;
var
  A, B: TPoint;
begin
  Result := False;
  if not SelectionOrdered(A, B) then Exit;
  if (ARow < A.Y) or (ARow > B.Y) then Exit;
  if (ARow = A.Y) and (ACol < A.X) then Exit;
  if (ARow = B.Y) and (ACol >= B.X) then Exit;
  Result := True;
end;

function TLedTermView.HasSelection: Boolean;
var
  A, B: TPoint;
begin
  Result := SelectionOrdered(A, B) and ((A.X <> B.X) or (A.Y <> B.Y));
end;

procedure TLedTermView.ClearSelection;
begin
  if not FHasSel then Exit;
  FHasSel := False;
  FSelecting := False;
  Invalidate;
end;

procedure TLedTermView.SelectAll;
begin
  FSelAnchor := Point(0, 0);
  FSelHead := Point(FScreen.Cols, FScreen.Rows - 1);
  FHasSel := True;
  Invalidate;
end;

function TLedTermView.SelectedText: string;
var
  A, B: TPoint;
  Row, C0, C1, X: Integer;
  Line: string;
begin
  Result := '';
  if not SelectionOrdered(A, B) then Exit;
  for Row := A.Y to B.Y do
  begin
    if Row = A.Y then C0 := A.X else C0 := 0;
    if Row = B.Y then C1 := B.X - 1 else C1 := FScreen.Cols - 1;
    Line := '';
    for X := C0 to C1 do
      Line := Line + FScreen.Cell(X, Row).Ch;
    { Every row is padded to full width; the padding is not text. }
    Line := TrimRight(Line);
    if Result <> '' then Result := Result + LineEnding;
    Result := Result + Line;
  end;
end;

procedure TLedTermView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  { Clicking a terminal should put the caret in it.  ledterm cannot use
    Led.UI.Focus -- ledui depends on ledterm, not the other way round -- and
    the guard is four lines, so it is repeated rather than inverted. }
  if CanFocus and (GetParentForm(Self) <> nil) and
     (GetParentForm(Self).Active or
      (GetParentForm(Self).IsControlVisible and GetParentForm(Self).Enabled)) then
    SetFocus;
  FSelAnchor := CellAt(X, Y);
  FSelHead := FSelAnchor;
  FSelecting := True;
  FHasSel := False;
  Invalidate;
end;

procedure TLedTermView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FSelecting then Exit;
  FSelHead := CellAt(X, Y);
  FHasSel := True;
  Invalidate;
end;

procedure TLedTermView.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FSelecting := False;
  { A click with no drag is a click, not an empty selection. }
  if not HasSelection then FHasSel := False;
  Invalidate;
end;

constructor TLedTermView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  { A text surface, so the pointer says so.  The control inherited the arrow,
    which reads as "nothing here to select" over a terminal you can in fact
    select from. }
  Cursor := crIBeam;
  Font.Name := {$IFDEF WINDOWS}'Consolas'{$ELSE}'Monospace'{$ENDIF};
  Font.Size := 10;

  FPty := TLedPty.Create;
  FScreen := TLedTermScreen.Create(80, 24);
  FCharW := 8;
  FCharH := 16;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 25;
  FTimer.OnTimer := @Poll;
  FTimer.Enabled := False;
end;

destructor TLedTermView.Destroy;
begin
  Stop;
  FScreen.Free;
  FPty.Free;
  inherited Destroy;
end;

class function TLedTermView.GetControlClassDefaultSize: TSize;
begin
  Result.CX := 480;
  Result.CY := 240;
end;

function LedTermSchemeCount: Integer;
begin
  Result := Length(Schemes);
end;

function LedTermSchemeName(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(Schemes)) then Exit('');
  Result := Schemes[AIndex].Name;
end;

function TLedTermView.SchemeCount: Integer;
begin
  Result := LedTermSchemeCount;
end;

function TLedTermView.SchemeName(AIndex: Integer): string;
begin
  Result := LedTermSchemeName(AIndex);
end;

procedure TLedTermView.SetScheme(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(Schemes)) then Exit;
  FScheme := AIndex;
  Invalidate;
end;

procedure TLedTermView.MeasureFont;
begin
  Canvas.Font := Font;
  { A monospace font still reports fractional advances on some platforms;
    rounding here once keeps every column aligned. }
  FCharW := Canvas.TextWidth('M');
  if FCharW < 1 then FCharW := 8;
  FCharH := Canvas.TextHeight('Mg');
  if FCharH < 1 then FCharH := 16;
end;

function TLedTermView.Start(const ACommand, AWorkDir: string): Boolean;
var
  C, R: Integer;
begin
  Result := False;
  if not LedPtyAvailable then Exit;
  if FPty.Running then Exit;

  MeasureFont;
  C := Width div FCharW;
  R := Height div FCharH;
  if C < 10 then C := 80;
  if R < 3 then R := 24;

  FScreen.Resize(C, R);
  FLastCols := C;
  FLastRows := R;
  Result := FPty.Spawn(ACommand, AWorkDir, C, R);
  FTimer.Enabled := Result;
  Invalidate;
end;

procedure TLedTermView.Stop;
begin
  FTimer.Enabled := False;
  FPty.Terminate;
end;

function TLedTermView.Running: Boolean;
begin
  Result := FPty.Running;
end;

procedure TLedTermView.Poll(Sender: TObject);
var
  Buf: array[0..8191] of Char;
  N: Integer;
  S: string;
  Title: string;
  Any: Boolean;
begin
  Any := False;
  { Drain everything waiting rather than one buffer per tick, so a burst of
    output is not spread over seconds of redraws. }
  repeat
    N := FPty.Read(Buf, SizeOf(Buf));
    if N > 0 then
    begin
      SetString(S, Buf, N);
      Title := FScreen.Title;
      FScreen.Feed(S);
      Any := True;
      if (FScreen.Title <> Title) and Assigned(FOnTitleChange) then
        FOnTitleChange(Self);
    end;
  until N <= 0;

  if N < 0 then
  begin
    { The shell has gone.  Everything this view needs to do to itself happens
      before the callback, and nothing at all after it: OnExited closes the
      pane, which frees this view, so touching a field here -- Invalidate was
      here, and it is what crashed -- is a use-after-free from inside the
      object's own timer handler. }
    FTimer.Enabled := False;
    Invalidate;
    if Assigned(FOnExited) then FOnExited(Self);
    Exit;
  end;

  if Any or FScreen.Dirty then
  begin
    FScreen.Dirty := False;
    FScrollOffset := 0;      { new output pulls the view back to the bottom }
    Invalidate;
  end;
end;

procedure TLedTermView.Resize;
var
  C, R: Integer;
begin
  inherited Resize;
  if FCharW < 1 then Exit;
  C := Width div FCharW;
  R := Height div FCharH;
  if (C < 1) or (R < 1) then Exit;

  { Dragging a splitter delivers a resize per pixel, and most of those land
    inside the same character cell.  Reallocating the cell grid and telling
    the child its window changed on every one of them is what made resizing
    the terminal feel like wading; the shell is told when the grid actually
    changes, which is what it cares about anyway. }
  if (C = FLastCols) and (R = FLastRows) then Exit;
  FLastCols := C;
  FLastRows := R;

  FScreen.Resize(C, R);
  FPty.SetSize(C, R);
  Invalidate;
end;

function TLedTermView.ColourOf(AIndex: SmallInt; ADefault: TColor): TColor;
var
  R, G, B, Level: Integer;
begin
  if AIndex < 0 then Exit(ADefault);
  if AIndex < 16 then Exit(Schemes[FScheme].Palette[AIndex]);
  if AIndex < 232 then
  begin
    { The 216-colour cube. }
    AIndex := AIndex - 16;
    R := (AIndex div 36) mod 6;
    G := (AIndex div 6) mod 6;
    B := AIndex mod 6;
    Result := RGBToColor(R * 51, G * 51, B * 51);
    Exit;
  end;
  { The 24-step grey ramp. }
  Level := 8 + (AIndex - 232) * 10;
  if Level > 255 then Level := 255;
  Result := RGBToColor(Level, Level, Level);
end;

procedure TLedTermView.Paint;
var
  X, Y, Row, PxX, PxY: Integer;
  C: TLedCell;
  FG, BG, T: TColor;
  Line: TLedCellRow;
  SbIndex: Integer;
begin
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Schemes[FScheme].Background;
  Canvas.FillRect(ClientRect);

  for Y := 0 to FScreen.Rows - 1 do
  begin
    Row := Y - FScrollOffset;
    if Row >= 0 then
      Line := FScreen.VisibleRow(Row)
    else
    begin
      SbIndex := FScreen.ScrollbackCount + Row;
      Line := FScreen.ScrollbackRow(SbIndex);
    end;
    if Line = nil then Continue;

    PxY := Y * FCharH;
    for X := 0 to High(Line) do
    begin
      C := Line[X];
      FG := ColourOf(C.FG, Schemes[FScheme].Foreground);
      BG := ColourOf(C.BG, Schemes[FScheme].Background);
      if caInverse in C.Attr then
      begin
        T := FG; FG := BG; BG := T;
      end;

      { Selected cells swap their colours, which reads correctly whatever
        the scheme and needs no colour of its own. }
      if (FScrollOffset = 0) and CellSelected(X, Y) then
      begin
        T := FG; FG := BG; BG := T;
      end;

      PxX := X * FCharW;
      if BG <> Schemes[FScheme].Background then
      begin
        Canvas.Brush.Color := BG;
        Canvas.FillRect(PxX, PxY, PxX + FCharW, PxY + FCharH);
      end;

      if (C.Ch <> '') and (C.Ch <> ' ') then
      begin
        Canvas.Font.Color := FG;
        Canvas.Font.Style := [];
        if caBold in C.Attr then Canvas.Font.Style := Canvas.Font.Style + [fsBold];
        if caItalic in C.Attr then Canvas.Font.Style := Canvas.Font.Style + [fsItalic];
        if caUnderline in C.Attr then
          Canvas.Font.Style := Canvas.Font.Style + [fsUnderline];
        Canvas.Brush.Style := bsClear;
        Canvas.TextOut(PxX, PxY, C.Ch);
        Canvas.Brush.Style := bsSolid;
      end;
    end;
  end;

  if FScreen.CursorVisible and (FScrollOffset = 0) and Focused then
  begin
    Canvas.Brush.Color := Schemes[FScheme].Cursor;
    Canvas.FillRect(FScreen.CursorX * FCharW, FScreen.CursorY * FCharH,
      FScreen.CursorX * FCharW + FCharW, FScreen.CursorY * FCharH + FCharH);
  end;
end;

procedure TLedTermView.SendKey(const S: string);
begin
  if FPty.Running then FPty.WriteString(S);
  FScrollOffset := 0;
end;

procedure TLedTermView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not FPty.Running then
  begin
    inherited KeyDown(Key, Shift);
    Exit;
  end;

  { Ctrl+Shift+C and V are the terminal convention, because plain Ctrl+C has
    to reach the child as an interrupt. }
  if (ssCtrl in Shift) and (ssShift in Shift) then
  begin
    inherited KeyDown(Key, Shift);
    Exit;
  end;

  case Key of
    VK_RETURN: SendKey(#13);
    VK_BACK:   SendKey(#127);
    VK_TAB:    SendKey(#9);
    VK_ESCAPE: SendKey(#27);
    VK_UP:     SendKey(#27'[A');
    VK_DOWN:   SendKey(#27'[B');
    VK_RIGHT:  SendKey(#27'[C');
    VK_LEFT:   SendKey(#27'[D');
    VK_HOME:   SendKey(#27'[H');
    VK_END:    SendKey(#27'[F');
    VK_PRIOR:  SendKey(#27'[5~');
    VK_NEXT:   SendKey(#27'[6~');
    VK_INSERT: SendKey(#27'[2~');
    VK_DELETE: SendKey(#27'[3~');
    VK_F1..VK_F4:
      SendKey(#27'O' + Chr(Ord('P') + (Key - VK_F1)));
  else
    if (ssCtrl in Shift) and (Key >= Ord('A')) and (Key <= Ord('Z')) then
      SendKey(Chr(Key - Ord('A') + 1))
    else
    begin
      inherited KeyDown(Key, Shift);
      Exit;
    end;
  end;
  Key := 0;
end;

procedure TLedTermView.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if FPty.Running and (Length(UTF8Key) > 0) and (UTF8Key[1] >= ' ') then
  begin
    SendKey(UTF8Key);
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

function TLedTermView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  { Scrolling back through the history, which is why the scrollback exists. }
  if WheelDelta > 0 then
    Inc(FScrollOffset, 3)
  else
    Dec(FScrollOffset, 3);
  if FScrollOffset < 0 then FScrollOffset := 0;
  if FScrollOffset > FScreen.ScrollbackCount then
    FScrollOffset := FScreen.ScrollbackCount;
  Invalidate;
  Result := True;
end;

procedure TLedTermView.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TLedTermView.FontChanged(Sender: TObject);
begin
  inherited FontChanged(Sender);
  { A different font means a different number of rows and columns, and the
    shell has to be told or it will keep wrapping at the old width.

    The guard is not optional.  Measuring touches the Canvas, which on gtk2
    realizes the control, which changes the font again -- so without it the
    first Parent assignment recurses until the program stops responding.
    Nothing can be measured before there is a handle anyway. }
  if FInFontChange or not HandleAllocated then Exit;
  FInFontChange := True;
  try
    MeasureFont;
    Resize;
  finally
    FInFontChange := False;
  end;
end;

procedure TLedTermView.Paste(const AText: string);
begin
  if FPty.Running then
    FPty.WriteString(StringReplace(AText, LineEnding, #13, [rfReplaceAll]));
end;

end.
