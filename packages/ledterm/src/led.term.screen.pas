{ led - a light editor.  Terminal screen model and escape-sequence parser.

  A grid of cells, a scrollback ring, and a state machine that turns the byte
  stream from the child into changes to that grid.  The parser follows the
  usual ground / escape / CSI / OSC shape; it is a working subset of xterm
  rather than a complete one, and TERM is set to plain "xterm" so programs do
  not assume more than is implemented.

  Deliberately free of any LCL dependency: the model can be driven and checked
  without a window, which is the only practical way to test a terminal. }
unit Led.Term.Screen;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  LedTermMaxScrollback = 5000;

type
  TLedCellAttr = set of (caBold, caItalic, caUnderline, caInverse, caFaint,
                         caStrike);

  TLedCell = record
    Ch: string[6];       // one UTF-8 character
    FG, BG: SmallInt;    // -1 = default, 0..255 = palette index
    Attr: TLedCellAttr;
  end;

  TLedCellRow = array of TLedCell;

  TLedTermScreen = class
  private
    FCols, FRows: Integer;
    FGrid: array of TLedCellRow;
    FScrollback: TFPList;      // of PLedCellRow, oldest first
    FCurX, FCurY: Integer;
    FSaveX, FSaveY: Integer;
    FFG, FBG: SmallInt;
    FAttr: TLedCellAttr;
    FScrollTop, FScrollBottom: Integer;
    FCursorVisible: Boolean;
    FAltScreen: Boolean;
    FMainGrid: array of TLedCellRow;
    FTitle: string;
    FWrapPending: Boolean;
    FDirty: Boolean;

    // parser state
    FState: Integer;
    FParams: array[0..15] of Integer;
    FParamCount: Integer;
    FParamDigits: Boolean;
    FPrivate: Char;
    FOscBuf: string;
    FUtf8Buf: string;
    FUtf8Need: Integer;

    procedure BlankRow(var ARow: TLedCellRow);
    function NewRow: TLedCellRow;
    procedure ScrollUp(ACount: Integer);
    procedure ScrollDown(ACount: Integer);
    procedure PutChar(const AChar: string);
    procedure Execute(AByte: Byte);
    procedure DispatchCSI(AFinal: Char);
    procedure DispatchSGR;
    procedure SetMode(AEnable: Boolean);
    procedure EraseInDisplay(AMode: Integer);
    procedure EraseInLine(AMode: Integer);
    procedure InsertLines(ACount: Integer);
    procedure DeleteLines(ACount: Integer);
    procedure DeleteChars(ACount: Integer);
    procedure InsertChars(ACount: Integer);
    procedure EraseChars(ACount: Integer);
    function Param(AIndex, ADefault: Integer): Integer;
    procedure ClampCursor;
    procedure UseAltScreen(AOn: Boolean);
    function GetScrollbackCount: Integer;
  public
    constructor Create(ACols, ARows: Integer);
    destructor Destroy; override;

    procedure Resize(ACols, ARows: Integer);
    procedure Feed(const AData: string);
    procedure Reset;

    function Cell(ACol, ARow: Integer): TLedCell;
    { Rows are addressed with 0 as the first visible line; negative indices
      reach into the scrollback. }
    function VisibleRow(ARow: Integer): TLedCellRow;
    function ScrollbackRow(AIndex: Integer): TLedCellRow;
    function RowText(ARow: Integer): string;

    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
    property CursorX: Integer read FCurX;
    property CursorY: Integer read FCurY;
    property CursorVisible: Boolean read FCursorVisible;
    property ScrollbackCount: Integer read GetScrollbackCount;
    property Title: string read FTitle;
    property Dirty: Boolean read FDirty write FDirty;
  end;

implementation

const
  stGround = 0;
  stEscape = 1;
  stCSI    = 2;
  stOSC    = 3;

type
  PLedCellRow = ^TLedCellRow;

constructor TLedTermScreen.Create(ACols, ARows: Integer);
begin
  inherited Create;
  FScrollback := TFPList.Create;
  FCols := 1;
  FRows := 1;
  FFG := -1;
  FBG := -1;
  FCursorVisible := True;
  Resize(ACols, ARows);
end;

destructor TLedTermScreen.Destroy;
var
  i: Integer;
  P: PLedCellRow;
begin
  for i := 0 to FScrollback.Count - 1 do
  begin
    P := PLedCellRow(FScrollback[i]);
    Dispose(P);
  end;
  FScrollback.Free;
  inherited Destroy;
end;

function TLedTermScreen.GetScrollbackCount: Integer;
begin
  Result := FScrollback.Count;
end;

procedure TLedTermScreen.BlankRow(var ARow: TLedCellRow);
var
  i: Integer;
begin
  SetLength(ARow, FCols);
  for i := 0 to FCols - 1 do
  begin
    ARow[i].Ch := ' ';
    ARow[i].FG := -1;
    ARow[i].BG := -1;
    ARow[i].Attr := [];
  end;
end;

function TLedTermScreen.NewRow: TLedCellRow;
begin
  Result := nil;
  BlankRow(Result);
end;

procedure TLedTermScreen.Resize(ACols, ARows: Integer);
var
  Old: array of TLedCellRow;
  i, j, Keep: Integer;
begin
  if ACols < 1 then ACols := 1;
  if ARows < 1 then ARows := 1;
  if (ACols = FCols) and (ARows = FRows) then Exit;

  Old := FGrid;
  Keep := Length(Old);
  FCols := ACols;
  FRows := ARows;
  SetLength(FGrid, FRows);
  for i := 0 to FRows - 1 do
  begin
    FGrid[i] := NewRow;
    { Content is kept where it still fits.  Reflowing wrapped lines properly
      needs to know which line breaks were soft, which this model does not
      record, so it is not attempted -- medit's terminal did not reflow
      either. }
    if i < Keep then
      for j := 0 to FCols - 1 do
        if j < Length(Old[i]) then
          FGrid[i][j] := Old[i][j];
  end;

  FScrollTop := 0;
  FScrollBottom := FRows - 1;
  ClampCursor;
  FDirty := True;
end;

procedure TLedTermScreen.Reset;
var
  i: Integer;
begin
  for i := 0 to FRows - 1 do
    FGrid[i] := NewRow;
  FCurX := 0;
  FCurY := 0;
  FFG := -1;
  FBG := -1;
  FAttr := [];
  FScrollTop := 0;
  FScrollBottom := FRows - 1;
  FCursorVisible := True;
  FWrapPending := False;
  FState := stGround;
  FDirty := True;
end;

procedure TLedTermScreen.ClampCursor;
begin
  if FCurX < 0 then FCurX := 0;
  if FCurY < 0 then FCurY := 0;
  if FCurX >= FCols then FCurX := FCols - 1;
  if FCurY >= FRows then FCurY := FRows - 1;
end;

function TLedTermScreen.Cell(ACol, ARow: Integer): TLedCell;
begin
  if (ARow < 0) or (ARow >= FRows) or (ACol < 0) or (ACol >= FCols) then
  begin
    Result.Ch := ' ';
    Result.FG := -1;
    Result.BG := -1;
    Result.Attr := [];
    Exit;
  end;
  Result := FGrid[ARow][ACol];
end;

function TLedTermScreen.VisibleRow(ARow: Integer): TLedCellRow;
begin
  if (ARow < 0) or (ARow >= FRows) then
    Result := nil
  else
    Result := FGrid[ARow];
end;

function TLedTermScreen.ScrollbackRow(AIndex: Integer): TLedCellRow;
begin
  if (AIndex < 0) or (AIndex >= FScrollback.Count) then
    Result := nil
  else
    Result := PLedCellRow(FScrollback[AIndex])^;
end;

function TLedTermScreen.RowText(ARow: Integer): string;
var
  i: Integer;
  Row: TLedCellRow;
begin
  Result := '';
  Row := VisibleRow(ARow);
  if Row = nil then Exit;
  for i := 0 to High(Row) do
    Result := Result + Row[i].Ch;
  Result := TrimRight(Result);
end;

procedure TLedTermScreen.ScrollUp(ACount: Integer);
var
  i, n: Integer;
  P: PLedCellRow;
  Q: PLedCellRow;
begin
  for n := 1 to ACount do
  begin
    { Only the main screen keeps history.  A full-screen program on the
      alternate screen would otherwise fill the scrollback with its own
      redraws. }
    if (not FAltScreen) and (FScrollTop = 0) then
    begin
      New(P);
      P^ := FGrid[FScrollTop];
      FScrollback.Add(P);
      while FScrollback.Count > LedTermMaxScrollback do
      begin
        Q := PLedCellRow(FScrollback[0]);
        Dispose(Q);
        FScrollback.Delete(0);
      end;
    end;
    for i := FScrollTop to FScrollBottom - 1 do
      FGrid[i] := FGrid[i + 1];
    FGrid[FScrollBottom] := NewRow;
  end;
  FDirty := True;
end;

procedure TLedTermScreen.ScrollDown(ACount: Integer);
var
  i, n: Integer;
begin
  for n := 1 to ACount do
  begin
    for i := FScrollBottom downto FScrollTop + 1 do
      FGrid[i] := FGrid[i - 1];
    FGrid[FScrollTop] := NewRow;
  end;
  FDirty := True;
end;

procedure TLedTermScreen.PutChar(const AChar: string);
begin
  { Wrapping happens when the next character arrives, not when the last
    column is filled: a line that ends exactly at the margin should not
    produce a blank line. }
  if FWrapPending then
  begin
    FCurX := 0;
    if FCurY = FScrollBottom then ScrollUp(1) else Inc(FCurY);
    FWrapPending := False;
  end;

  if (FCurY >= 0) and (FCurY < FRows) and (FCurX >= 0) and (FCurX < FCols) then
  begin
    FGrid[FCurY][FCurX].Ch := AChar;
    FGrid[FCurY][FCurX].FG := FFG;
    FGrid[FCurY][FCurX].BG := FBG;
    FGrid[FCurY][FCurX].Attr := FAttr;
  end;

  if FCurX >= FCols - 1 then
    FWrapPending := True
  else
    Inc(FCurX);
  FDirty := True;
end;

function TLedTermScreen.Param(AIndex, ADefault: Integer): Integer;
begin
  if (AIndex < FParamCount) and (FParams[AIndex] >= 0) then
    Result := FParams[AIndex]
  else
    Result := ADefault;
end;

procedure TLedTermScreen.EraseInLine(AMode: Integer);
var
  i, First, Last: Integer;
begin
  case AMode of
    1: begin First := 0; Last := FCurX; end;
    2: begin First := 0; Last := FCols - 1; end;
  else
    First := FCurX; Last := FCols - 1;
  end;
  for i := First to Last do
    if (i >= 0) and (i < FCols) then
    begin
      FGrid[FCurY][i].Ch := ' ';
      FGrid[FCurY][i].FG := FFG;
      FGrid[FCurY][i].BG := FBG;
      FGrid[FCurY][i].Attr := [];
    end;
  FDirty := True;
end;

procedure TLedTermScreen.EraseInDisplay(AMode: Integer);
var
  i: Integer;
begin
  case AMode of
    1:
      begin
        for i := 0 to FCurY - 1 do FGrid[i] := NewRow;
        EraseInLine(1);
      end;
    2, 3:
      begin
        for i := 0 to FRows - 1 do FGrid[i] := NewRow;
        FCurX := 0;
        FCurY := 0;
      end;
  else
    EraseInLine(0);
    for i := FCurY + 1 to FRows - 1 do FGrid[i] := NewRow;
  end;
  FDirty := True;
end;

procedure TLedTermScreen.InsertLines(ACount: Integer);
var
  i, n: Integer;
begin
  if (FCurY < FScrollTop) or (FCurY > FScrollBottom) then Exit;
  for n := 1 to ACount do
  begin
    for i := FScrollBottom downto FCurY + 1 do
      FGrid[i] := FGrid[i - 1];
    FGrid[FCurY] := NewRow;
  end;
  FDirty := True;
end;

procedure TLedTermScreen.DeleteLines(ACount: Integer);
var
  i, n: Integer;
begin
  if (FCurY < FScrollTop) or (FCurY > FScrollBottom) then Exit;
  for n := 1 to ACount do
  begin
    for i := FCurY to FScrollBottom - 1 do
      FGrid[i] := FGrid[i + 1];
    FGrid[FScrollBottom] := NewRow;
  end;
  FDirty := True;
end;

procedure TLedTermScreen.DeleteChars(ACount: Integer);
var
  i, n: Integer;
begin
  for n := 1 to ACount do
  begin
    for i := FCurX to FCols - 2 do
      FGrid[FCurY][i] := FGrid[FCurY][i + 1];
    FGrid[FCurY][FCols - 1].Ch := ' ';
    FGrid[FCurY][FCols - 1].Attr := [];
  end;
  FDirty := True;
end;

procedure TLedTermScreen.InsertChars(ACount: Integer);
var
  i, n: Integer;
begin
  for n := 1 to ACount do
  begin
    for i := FCols - 1 downto FCurX + 1 do
      FGrid[FCurY][i] := FGrid[FCurY][i - 1];
    FGrid[FCurY][FCurX].Ch := ' ';
    FGrid[FCurY][FCurX].Attr := [];
  end;
  FDirty := True;
end;

procedure TLedTermScreen.EraseChars(ACount: Integer);
var
  i: Integer;
begin
  for i := FCurX to FCurX + ACount - 1 do
    if i < FCols then
    begin
      FGrid[FCurY][i].Ch := ' ';
      FGrid[FCurY][i].Attr := [];
    end;
  FDirty := True;
end;

procedure TLedTermScreen.UseAltScreen(AOn: Boolean);
var
  i: Integer;
begin
  if AOn = FAltScreen then Exit;
  if AOn then
  begin
    SetLength(FMainGrid, FRows);
    for i := 0 to FRows - 1 do FMainGrid[i] := FGrid[i];
    for i := 0 to FRows - 1 do FGrid[i] := NewRow;
    FAltScreen := True;
  end
  else
  begin
    for i := 0 to FRows - 1 do
      if i < Length(FMainGrid) then FGrid[i] := FMainGrid[i]
      else FGrid[i] := NewRow;
    SetLength(FMainGrid, 0);
    FAltScreen := False;
  end;
  FDirty := True;
end;

procedure TLedTermScreen.SetMode(AEnable: Boolean);
var
  i: Integer;
begin
  if FPrivate <> '?' then Exit;
  for i := 0 to FParamCount - 1 do
    case FParams[i] of
      25: FCursorVisible := AEnable;
      1047, 1049:
        begin
          UseAltScreen(AEnable);
          if AEnable and (FParams[i] = 1049) then
          begin
            FSaveX := FCurX;
            FSaveY := FCurY;
            FCurX := 0;
            FCurY := 0;
          end
          else if FParams[i] = 1049 then
          begin
            FCurX := FSaveX;
            FCurY := FSaveY;
          end;
        end;
    end;
end;

procedure TLedTermScreen.DispatchSGR;
var
  i, P: Integer;
begin
  if FParamCount = 0 then
  begin
    FAttr := [];
    FFG := -1;
    FBG := -1;
    Exit;
  end;
  i := 0;
  while i < FParamCount do
  begin
    P := FParams[i];
    if P < 0 then P := 0;
    case P of
      0: begin FAttr := []; FFG := -1; FBG := -1; end;
      1: Include(FAttr, caBold);
      2: Include(FAttr, caFaint);
      3: Include(FAttr, caItalic);
      4: Include(FAttr, caUnderline);
      7: Include(FAttr, caInverse);
      9: Include(FAttr, caStrike);
      21, 22: FAttr := FAttr - [caBold, caFaint];
      23: Exclude(FAttr, caItalic);
      24: Exclude(FAttr, caUnderline);
      27: Exclude(FAttr, caInverse);
      29: Exclude(FAttr, caStrike);
      30..37: FFG := P - 30;
      39: FFG := -1;
      40..47: FBG := P - 40;
      49: FBG := -1;
      90..97: FFG := P - 90 + 8;
      100..107: FBG := P - 100 + 8;
      38, 48:
        begin
          { 256-colour and truecolour.  Truecolour is reduced to the nearest
            of the 216-colour cube, because the cell stores a palette index;
            keeping a full RGB per cell would triple the grid for a gain
            almost nobody sees in a terminal. }
          if (i + 1 < FParamCount) and (FParams[i + 1] = 5) and
             (i + 2 < FParamCount) then
          begin
            if P = 38 then FFG := FParams[i + 2] else FBG := FParams[i + 2];
            Inc(i, 2);
          end
          else if (i + 1 < FParamCount) and (FParams[i + 1] = 2) and
                  (i + 4 < FParamCount) then
          begin
            if P = 38 then
              FFG := 16 + 36 * (FParams[i + 2] * 5 div 255)
                        + 6 * (FParams[i + 3] * 5 div 255)
                        + (FParams[i + 4] * 5 div 255)
            else
              FBG := 16 + 36 * (FParams[i + 2] * 5 div 255)
                        + 6 * (FParams[i + 3] * 5 div 255)
                        + (FParams[i + 4] * 5 div 255);
            Inc(i, 4);
          end;
        end;
    end;
    Inc(i);
  end;
end;

procedure TLedTermScreen.DispatchCSI(AFinal: Char);
var
  N: Integer;
begin
  case AFinal of
    'A': begin Dec(FCurY, Param(0, 1)); ClampCursor; end;
    'B': begin Inc(FCurY, Param(0, 1)); ClampCursor; end;
    'C': begin Inc(FCurX, Param(0, 1)); FWrapPending := False; ClampCursor; end;
    'D': begin Dec(FCurX, Param(0, 1)); FWrapPending := False; ClampCursor; end;
    'E': begin Inc(FCurY, Param(0, 1)); FCurX := 0; ClampCursor; end;
    'F': begin Dec(FCurY, Param(0, 1)); FCurX := 0; ClampCursor; end;
    'G', '`': begin FCurX := Param(0, 1) - 1; FWrapPending := False; ClampCursor; end;
    'd': begin FCurY := Param(0, 1) - 1; ClampCursor; end;
    'H', 'f':
      begin
        FCurY := Param(0, 1) - 1;
        FCurX := Param(1, 1) - 1;
        FWrapPending := False;
        ClampCursor;
      end;
    'J': EraseInDisplay(Param(0, 0));
    'K': EraseInLine(Param(0, 0));
    'L': InsertLines(Param(0, 1));
    'M': DeleteLines(Param(0, 1));
    'P': DeleteChars(Param(0, 1));
    '@': InsertChars(Param(0, 1));
    'X': EraseChars(Param(0, 1));
    'S': ScrollUp(Param(0, 1));
    'T': ScrollDown(Param(0, 1));
    'h': SetMode(True);
    'l': SetMode(False);
    'm': DispatchSGR;
    'r':
      begin
        FScrollTop := Param(0, 1) - 1;
        FScrollBottom := Param(1, FRows) - 1;
        if FScrollTop < 0 then FScrollTop := 0;
        if FScrollBottom >= FRows then FScrollBottom := FRows - 1;
        if FScrollBottom < FScrollTop then FScrollBottom := FScrollTop;
        FCurX := 0;
        FCurY := FScrollTop;
      end;
    's': begin FSaveX := FCurX; FSaveY := FCurY; end;
    'u': begin FCurX := FSaveX; FCurY := FSaveY; ClampCursor; end;
  end;
  FDirty := True;
end;

procedure TLedTermScreen.Execute(AByte: Byte);
begin
  case AByte of
    7: ;                                  { bell: nothing visual }
    8: begin
         if FWrapPending then FWrapPending := False
         else if FCurX > 0 then Dec(FCurX);
       end;
    9: begin
         FCurX := ((FCurX div 8) + 1) * 8;
         if FCurX >= FCols then FCurX := FCols - 1;
       end;
    10, 11, 12:
       begin
         FWrapPending := False;
         if FCurY = FScrollBottom then ScrollUp(1) else Inc(FCurY);
       end;
    13: begin FCurX := 0; FWrapPending := False; end;
  end;
  FDirty := True;
end;

procedure TLedTermScreen.Feed(const AData: string);
var
  i, n: Integer;
  B: Byte;
  C: Char;
begin
  i := 1;
  while i <= Length(AData) do
  begin
    C := AData[i];
    B := Ord(C);

    { A multi-byte UTF-8 character may be split across reads, so the tail is
      carried over rather than shown as replacement characters. }
    if FUtf8Need > 0 then
    begin
      FUtf8Buf := FUtf8Buf + C;
      Dec(FUtf8Need);
      if FUtf8Need = 0 then
      begin
        if FState = stGround then PutChar(FUtf8Buf);
        FUtf8Buf := '';
      end;
      Inc(i);
      Continue;
    end;

    case FState of
      stGround:
        begin
          if B = 27 then
            FState := stEscape
          else if B < 32 then
            Execute(B)
          else if B < 128 then
            PutChar(C)
          else
          begin
            if (B and $E0) = $C0 then n := 1
            else if (B and $F0) = $E0 then n := 2
            else if (B and $F8) = $F0 then n := 3
            else n := 0;
            if n = 0 then
              PutChar('?')
            else
            begin
              FUtf8Buf := C;
              FUtf8Need := n;
            end;
          end;
        end;

      stEscape:
        begin
          case C of
            '[':
              begin
                FState := stCSI;
                FParamCount := 0;
                FParamDigits := False;
                FPrivate := #0;
                FillChar(FParams, SizeOf(FParams), 0);
              end;
            ']':
              begin
                FState := stOSC;
                FOscBuf := '';
              end;
            'M':
              begin
                if FCurY = FScrollTop then ScrollDown(1) else Dec(FCurY);
                FState := stGround;
              end;
            '7': begin FSaveX := FCurX; FSaveY := FCurY; FState := stGround; end;
            '8': begin FCurX := FSaveX; FCurY := FSaveY; FState := stGround; end;
            'c': begin Reset; FState := stGround; end;
          else
            FState := stGround;
          end;
        end;

      stCSI:
        begin
          if (C = '?') or (C = '>') or (C = '!') then
            FPrivate := C
          else if (C >= '0') and (C <= '9') then
          begin
            if not FParamDigits then
            begin
              if FParamCount < High(FParams) then Inc(FParamCount);
              FParams[FParamCount - 1] := 0;
              FParamDigits := True;
            end;
            FParams[FParamCount - 1] :=
              FParams[FParamCount - 1] * 10 + (Ord(C) - Ord('0'));
          end
          else if C = ';' then
          begin
            if not FParamDigits then
            begin
              if FParamCount < High(FParams) then Inc(FParamCount);
              FParams[FParamCount - 1] := -1;
            end;
            FParamDigits := False;
          end
          else if (C >= '@') and (C <= '~') then
          begin
            DispatchCSI(C);
            FState := stGround;
          end;
        end;

      stOSC:
        begin
          { Ends at BEL or at ESC \.  Only the window title is acted on. }
          if (B = 7) or (B = 27) then
          begin
            if (Length(FOscBuf) > 2) and (Copy(FOscBuf, 1, 2) = '0;') then
              FTitle := Copy(FOscBuf, 3, MaxInt)
            else if (Length(FOscBuf) > 2) and (Copy(FOscBuf, 1, 2) = '2;') then
              FTitle := Copy(FOscBuf, 3, MaxInt);
            FState := stGround;
            if B = 27 then Inc(i);      { swallow the backslash }
          end
          else
            FOscBuf := FOscBuf + C;
        end;
    end;

    Inc(i);
  end;
end;

end.
