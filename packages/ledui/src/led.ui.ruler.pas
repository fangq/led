{ The ruler above a document's pages, as Word's: the page's width in inches, its margins shaded, and the paragraph's
  indents (first line, hanging, right) and tab stops at the caret, each dragged to move it -- the left indent's
  box moves the first line with it, a tab dragged off the ruler goes, a click on the ruler sets a left tab, a
  double click opens the paragraph's dialog.  Lined up with the page the caret is on, at the editor's zoom. }
unit Led.UI.Ruler;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Math, parade, paradeedit;

type
  { what a press on the ruler holds }
  TLedRulerGrip = (rgNone, rgFirst, rgHanging, rgLeftBox, rgRight, rgTab);

  TLedRuler = class(TCustomControl)
  private
    FEdit: TParadeEdit;
    FGrip: TLedRulerGrip;
    FTab: Integer;              { the tab held, by its index in the paragraph's }
    FDragX: Integer;            { where it is being dragged to }
    FDragPt: Double;            { the same in points from the left margin, as snapped }
    FDownX: Integer;
    FOff: Boolean;              { dragged off the ruler: a tab let go there goes }
    FMoved: Boolean;
    FOnDblClick: TNotifyEvent;
    function Place(out TextL, TextR, PageL, PageR: Integer; out PxPt: Double): Boolean;
    function Snap(Pt: Double): Double;
    { the text column's width in points: the page's less its margins }
    function TextWidthPt: Double;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
  public
    constructor Create(AOwner: TComponent); override;
    { where a marker is drawn, in the ruler's pixels; -1 when it is not (no page, or no such tab) }
    function MarkerX(AGrip: TLedRulerGrip; ATab: Integer = 0): Integer;
    { the text column's left and right edge (the margins), in the ruler's pixels }
    function TextLeft: Integer;
    function TextRight: Integer;
    property Edit: TParadeEdit read FEdit write FEdit;
    { a double click: the paragraph's dialog, for the host to open }
    property OnRulerDblClick: TNotifyEvent read FOnDblClick write FOnDblClick;
  end;

implementation

uses
  Led.UI.Dpi;

const
  Grab = 5;     { how near a press is to a marker to take it, in pixels at 96 dpi }

constructor TLedRuler.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Height := LedScale96(24);
  FGrip := rgNone;
  FTab := -1;
  DoubleBuffered := True;
end;

{ the caret's page and its text column, in the ruler's pixels, and pixels a point }
function TLedRuler.Place(out TextL, TextR, PageL, PageR: Integer; out PxPt: Double): Boolean;
var
  Pg: Int32;
  X, Base, Asc, Desc: pd_sp;
  Info: pd_page_info;
  SP: pd_section_props;
  P0, P1: TPoint;
  WPt: Double;
begin
  Result := False;
  TextL := 0; TextR := 0; PageL := 0; PageR := 0; PxPt := 1;
  if (FEdit = nil) or (FEdit.PageCount = 0) then
    Exit;
  if pd_layout_caret(FEdit.Layout, FEdit.CaretPos, Pg, X, Base, Asc, Desc) <> PD_OK then
    Pg := 0;
  if (Pg < 0) or (Pg >= FEdit.PageCount) then
    Exit;
  pd_layout_page_info(FEdit.Layout, Pg, Info);
  WPt := Info.width / PD_SP_PER_PT;
  SP := FEdit.CurrentSectionProps;
  P0 := FEdit.PageToClient(Pg, 0, 0);
  P1 := FEdit.PageToClient(Pg, WPt, 0);
  { from the editor's pixels to the ruler's: both are as wide and side by side, so only their left edges differ }
  P0.X := P0.X + FEdit.Left - Left;
  P1.X := P1.X + FEdit.Left - Left;
  PageL := P0.X;
  PageR := P1.X;
  if WPt <= 0 then
    Exit;
  PxPt := (P1.X - P0.X) / WPt;
  TextL := PageL + Round(SP.margin_left / PD_SP_PER_PT * PxPt);
  TextR := PageR - Round(SP.margin_right / PD_SP_PER_PT * PxPt);
  Result := TextR > TextL;
end;

{ to the nearest sixteenth of an inch, as Word's ruler moves }
function TLedRuler.Snap(Pt: Double): Double;
begin
  Result := Round(Pt / 4.5) * 4.5;
end;

function TLedRuler.TextWidthPt: Double;
var
  Pg: Int32;
  X, Base, Asc, Desc: pd_sp;
  Info: pd_page_info;
  SP: pd_section_props;
begin
  Result := 0;
  if (FEdit = nil) or (FEdit.PageCount = 0) then
    Exit;
  if pd_layout_caret(FEdit.Layout, FEdit.CaretPos, Pg, X, Base, Asc, Desc) <> PD_OK then
    Pg := 0;
  pd_layout_page_info(FEdit.Layout, Pg, Info);
  SP := FEdit.CurrentSectionProps;
  Result := (Info.width - SP.margin_left - SP.margin_right) / PD_SP_PER_PT;
end;

function TLedRuler.TextLeft: Integer;
var
  R, PL, PR: Integer;
  K: Double;
begin
  if not Place(Result, R, PL, PR, K) then
    Result := -1;
end;

function TLedRuler.TextRight: Integer;
var
  L, PL, PR: Integer;
  K: Double;
begin
  if not Place(L, Result, PL, PR, K) then
    Result := -1;
end;

function TLedRuler.MarkerX(AGrip: TLedRulerGrip; ATab: Integer): Integer;
var
  L, R, PL, PR: Integer;
  K: Double;
  PP: pd_para_props;
begin
  Result := -1;
  if not Place(L, R, PL, PR, K) then
    Exit;
  PP := FEdit.CurrentParaProps;
  case AGrip of
    rgFirst: Result := L + Round((PP.indent_left + PP.indent_first) / PD_SP_PER_PT * K);
    rgHanging, rgLeftBox: Result := L + Round(PP.indent_left / PD_SP_PER_PT * K);
    rgRight: Result := R - Round(PP.indent_right / PD_SP_PER_PT * K);
    rgTab:
      if (ATab >= 0) and (ATab < PP.ntabs) then
        Result := L + Round(PP.tabs[ATab].position / PD_SP_PER_PT * K);
  end;
  { being dragged: where it is going }
  if (FGrip <> rgNone) and FMoved and ((AGrip = FGrip) or ((FGrip = rgLeftBox) and (AGrip in [rgFirst, rgHanging]))
     or ((FGrip = rgHanging) and (AGrip = rgLeftBox))) and ((AGrip <> rgTab) or (ATab = FTab)) then
    if (FGrip = rgLeftBox) and (AGrip = rgFirst) then
      Result := Result + (FDragX - FDownX)
    else
      Result := FDragX;
end;

procedure TLedRuler.Paint;
var
  L, R, PL, PR, X, I, H, Y0, N: Integer;
  K, Pt: Double;
  PP: pd_para_props;
  S: string;
  Tri: array[0..2] of TPoint;
begin
  Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(ClientRect);
  if not Place(L, R, PL, PR, K) then
    Exit;
  H := ClientHeight;
  Y0 := LedScale96(4);
  { the page: its margins shaded, the text column white }
  Canvas.Brush.Color := $00D8D8D8;
  Canvas.FillRect(Rect(PL, Y0, PR, H - Y0));
  Canvas.Brush.Color := clWhite;
  Canvas.FillRect(Rect(L, Y0, R, H - Y0));
  { an eighth of an inch a tick, the inches numbered out from the left margin both ways }
  Canvas.Font.Size := 7;
  Canvas.Font.Color := $00505050;
  Canvas.Pen.Color := $00707070;
  Canvas.Brush.Style := bsClear;
  N := Ceil((PR - PL) / (K * 9)) + 1;
  for I := -N to N do
  begin
    Pt := I * 9;      { an eighth of an inch: 9 points }
    X := L + Round(Pt * K);
    if (X < PL) or (X > PR) then
      Continue;
    if I mod 8 = 0 then
    begin
      if I <> 0 then
      begin
        S := IntToStr(Abs(I div 8));
        Canvas.TextOut(X - Canvas.TextWidth(S) div 2, (H - Canvas.TextHeight(S)) div 2, S);
      end;
    end
    else if I mod 4 = 0 then
    begin
      Canvas.MoveTo(X, H div 2 - LedScale96(3));
      Canvas.LineTo(X, H div 2 + LedScale96(3));
    end
    else if K * 9 >= 4 then
    begin
      Canvas.MoveTo(X, H div 2 - 1);
      Canvas.LineTo(X, H div 2 + 1);
    end;
  end;
  Canvas.Brush.Style := bsSolid;
  PP := FEdit.CurrentParaProps;
  { the tab stops: an L for a left one, an inverted T for a centred, a J for a right one, a dot more for decimal }
  Canvas.Pen.Color := clBlack;
  Canvas.Pen.Width := Max(1, LedScale96(2) div 2 + 1);
  for I := 0 to PP.ntabs - 1 do
  begin
    if FOff and (FGrip = rgTab) and (I = FTab) then
      Continue;     { on its way off }
    X := MarkerX(rgTab, I);
    if X < 0 then
      Continue;
    Canvas.MoveTo(X, H - Y0 - LedScale96(7));
    Canvas.LineTo(X, H - Y0 - 1);
    case PP.tabs[I].align of
      PD_TAB_CENTER:
        begin
          Canvas.MoveTo(X - LedScale96(4), H - Y0 - 1);
          Canvas.LineTo(X + LedScale96(4), H - Y0 - 1);
        end;
      PD_TAB_RIGHT:
        begin
          Canvas.MoveTo(X - LedScale96(5), H - Y0 - 1);
          Canvas.LineTo(X, H - Y0 - 1);
        end;
    else
      begin
        Canvas.MoveTo(X, H - Y0 - 1);
        Canvas.LineTo(X + LedScale96(5), H - Y0 - 1);
        if PP.tabs[I].align = PD_TAB_DECIMAL then
          Canvas.Rectangle(X + LedScale96(2), H - Y0 - LedScale96(5), X + LedScale96(4), H - Y0 - LedScale96(3));
      end;
    end;
  end;
  Canvas.Pen.Width := 1;
  { the indents: the first line's a triangle down from the top, the hanging one's up from the bottom over a box
    that moves both, the right one's up from the bottom }
  Canvas.Brush.Color := $00F0F0F0;
  Canvas.Pen.Color := $00404040;
  X := MarkerX(rgFirst);
  Tri[0] := Point(X - LedScale96(5), 0);
  Tri[1] := Point(X + LedScale96(5), 0);
  Tri[2] := Point(X, LedScale96(7));
  Canvas.Polygon(Tri);
  X := MarkerX(rgHanging);
  Tri[0] := Point(X - LedScale96(5), H - LedScale96(6));
  Tri[1] := Point(X + LedScale96(5), H - LedScale96(6));
  Tri[2] := Point(X, H - LedScale96(13));
  Canvas.Polygon(Tri);
  Canvas.Rectangle(X - LedScale96(5), H - LedScale96(6), X + LedScale96(5) + 1, H);
  X := MarkerX(rgRight);
  Tri[0] := Point(X - LedScale96(5), H - LedScale96(6));
  Tri[1] := Point(X + LedScale96(5), H - LedScale96(6));
  Tri[2] := Point(X, H - LedScale96(13));
  Canvas.Polygon(Tri);
  { the line a drag would put it at, down the ruler }
  if (FGrip <> rgNone) and FMoved then
  begin
    Canvas.Pen.Color := $00808080;
    Canvas.Pen.Style := psDot;
    Canvas.MoveTo(FDragX, 0);
    Canvas.LineTo(FDragX, H);
    Canvas.Pen.Style := psSolid;
  end;
end;

procedure TLedRuler.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I, TL, TR, PL, PR: Integer;
  K: Double;
  PP: pd_para_props;
  H: Integer;

  function Near(AX: Integer): Boolean;
  begin
    Result := (AX >= 0) and (Abs(X - AX) <= LedScale96(Grab));
  end;

begin
  inherited MouseDown(Button, Shift, X, Y);
  FGrip := rgNone;
  FTab := -1;
  FMoved := False;
  FOff := False;
  if (Button <> mbLeft) or (FEdit = nil) then
    Exit;
  H := ClientHeight;
  PP := FEdit.CurrentParaProps;
  { the box under the hanging indent first, then the triangles by which half of the ruler the press is in }
  if Near(MarkerX(rgLeftBox)) and (Y >= H - LedScale96(6)) then
    FGrip := rgLeftBox
  else if Near(MarkerX(rgFirst)) and (Y < H div 2) then
    FGrip := rgFirst
  else if Near(MarkerX(rgHanging)) and (Y >= H div 2) then
    FGrip := rgHanging
  else if Near(MarkerX(rgRight)) and (Y >= H div 2) then
    FGrip := rgRight
  else
    for I := 0 to PP.ntabs - 1 do
      if Near(MarkerX(rgTab, I)) then
      begin
        FGrip := rgTab;
        FTab := I;
        Break;
      end;
  FDownX := X;
  FDragX := X;
  if Place(TL, TR, PL, PR, K) then
    FDragPt := Snap((X - TL) / K);     { a click and no drag: here }
  if FGrip = rgNone then
    FGrip := rgTab;   { on the ruler's own ground: a new left tab, where it is let go }
  MouseCapture := True;
end;

procedure TLedRuler.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  L, R, PL, PR: Integer;
  K: Double;
begin
  inherited MouseMove(Shift, X, Y);
  if FGrip = rgNone then
    Exit;
  if not Place(L, R, PL, PR, K) then
    Exit;
  if ssAlt in Shift then
    FDragPt := (X - L) / K
  else if FGrip = rgRight then
    FDragPt := TextWidthPt - Snap(TextWidthPt - (X - L) / K)   { the right indent on the grid from the right margin }
  else
    FDragPt := Snap((X - L) / K);
  FDragX := L + Round(FDragPt * K);
  FMoved := FMoved or (Abs(X - FDownX) > 1);
  FOff := (FGrip = rgTab) and (FTab >= 0) and ((Y > ClientHeight + LedScale96(12)) or (Y < -LedScale96(12)));
  Invalidate;
end;

procedure TLedRuler.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  L, R, PL, PR, I, J: Integer;
  K, Pt: Double;
  PP, NP: pd_para_props;
  Grip: TLedRulerGrip;
begin
  inherited MouseUp(Button, Shift, X, Y);
  MouseCapture := False;
  Grip := FGrip;
  FGrip := rgNone;
  if (Grip = rgNone) or (FEdit = nil) or not Place(L, R, PL, PR, K) then
  begin
    Invalidate;
    Exit;
  end;
  MouseMove(Shift - [ssLeft], X, Y);   { the last place, snapped }
  FGrip := rgNone;
  PP := FEdit.CurrentParaProps;
  FillChar(NP, SizeOf(NP), 0);
  Pt := FDragPt;     { points from the left margin, as snapped }
  case Grip of
    rgFirst:
      if FMoved then
      begin
        NP.mask := PD_PP_INDENT_FIRST;
        NP.indent_first := Round(Pt * PD_SP_PER_PT) - PP.indent_left;
      end;
    rgHanging:
      if FMoved then
      begin   { the left indent, the first line staying where it is }
        NP.mask := PD_PP_INDENT_LEFT or PD_PP_INDENT_FIRST;
        NP.indent_left := Round(Pt * PD_SP_PER_PT);
        NP.indent_first := PP.indent_left + PP.indent_first - NP.indent_left;
      end;
    rgLeftBox:
      if FMoved then
      begin   { both, together }
        NP.mask := PD_PP_INDENT_LEFT;
        NP.indent_left := Round(Pt * PD_SP_PER_PT);
      end;
    rgRight:
      if FMoved then
      begin
        NP.mask := PD_PP_INDENT_RIGHT;
        NP.indent_right := Round((TextWidthPt - Pt) * PD_SP_PER_PT);
      end;
    rgTab:
      begin
        NP.mask := PD_PP_TABS;
        NP.ntabs := 0;
        for I := 0 to PP.ntabs - 1 do
          if I <> FTab then
          begin
            NP.tabs[NP.ntabs] := PP.tabs[I];
            Inc(NP.ntabs);
          end;
        if not FOff and ((FTab >= 0) or (Pt >= 0)) and (Pt <= (R - L) / K) and (NP.ntabs < PD_MAX_TABS) then
        begin   { moved there, or a new left one there; kept in order }
          if (FTab >= 0) and not FMoved then
            NP.mask := 0      { a click on a tab: nothing }
          else
          begin
            J := NP.ntabs;
            while (J > 0) and (NP.tabs[J - 1].position > Round(Pt * PD_SP_PER_PT)) do
            begin
              NP.tabs[J] := NP.tabs[J - 1];
              Dec(J);
            end;
            if FTab >= 0 then
              NP.tabs[J] := PP.tabs[FTab]
            else
            begin
              NP.tabs[J].align := PD_TAB_LEFT;
              NP.tabs[J].leader := 0;
            end;
            NP.tabs[J].position := Round(Pt * PD_SP_PER_PT);
            Inc(NP.ntabs);
          end;
        end
        else if FTab < 0 then
          NP.mask := 0;   { a click off the text column: no tab }
      end;
  end;
  FTab := -1;
  FOff := False;
  FMoved := False;
  if NP.mask <> 0 then
    FEdit.ApplyParaProps(NP);
  Invalidate;
end;

procedure TLedRuler.DblClick;
begin
  inherited DblClick;
  FGrip := rgNone;
  if Assigned(FOnDblClick) then
    FOnDblClick(Self);
end;

end.
