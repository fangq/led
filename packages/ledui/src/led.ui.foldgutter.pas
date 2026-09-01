{ led - a light editor.  Fold markers drawn as chevrons, the way medit drew
  them.

  SynEdit's own fold column draws a boxed [-] and [+], which is the Windows
  tree-view idiom and looks a decade older than the rest of the window.  medit
  drew a chevron instead: two stroked segments meeting at an apex, pointing
  down when the block is open and right when it is collapsed.  Lighter weight
  than a filled triangle, and no font dependency.

  The geometry here is a straight port of draw_fold_mark in
  moo/mooedit/mootextview.c, including its proportions -- the arms reach 0.7
  of the half-size across and 0.45 along, the stroke is a third of the
  half-size clamped to [1.2, 2.4] -- so the two editors' markers are the same
  shape at the same size.

  Why a whole Paint override for one glyph: TSynGutterCodeFolding draws the
  symbol in DrawNodeSymbol, which is *private* and not virtual, and it draws
  the surrounding box in there too.  Paint is the nearest thing that can be
  overridden.  The node-type logic below is therefore a reimplementation of
  the private FoldTypeForLine and its two helpers, over the same FoldView the
  original reads, and the vertical rule joining a block to its end is kept
  because that is medit behaviour too and the thing this column is for.

  Everything else -- mouse actions, the collapse/expand clicks, the context
  menu -- is inherited untouched: none of it goes through Paint. }
unit Led.UI.FoldGutter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, LCLIntf, LCLType,
  SynEditTypes, SynEditFoldedView, SynGutterCodeFolding, SynEditMiscClasses,
  SynEditMiscProcs;

type
  TLedGutterCodeFolding = class(TSynGutterCodeFolding)
  private
    FHidePrevious: Boolean;
    function LedFoldTypeForLine(AScreenLine: Integer): TSynEditFoldLineCapability;
    function LedIsSingleLineHide(AScreenLine: Integer): Boolean;
    procedure DrawChevron(ACanvas: TCanvas; const ARect: TRect;
      ACollapsed: Boolean);
  public
    procedure Paint(ACanvas: TCanvas; AClip: TRect;
      FirstLine, LastLine: Integer); override;
  end;

implementation

const
  { The inset SynEdit uses between the glyph and the line box. }
  cNodeOffset = 1;

{ A reimplementation of TSynGutterCodeFolding.FoldTypeForLine, which is
  private.  Same reads, same order of precedence; FHidePrevious stands in for
  the original's FIsFoldHidePreviousLine. }
function TLedGutterCodeFolding.LedFoldTypeForLine(
  AScreenLine: Integer): TSynEditFoldLineCapability;
var
  tmp, tmp2: TSynEditFoldLineCapabilities;
begin
  tmp := FoldView.FoldType[AScreenLine];
  tmp2 := FoldView.FoldType[AScreenLine - 1];
  FHidePrevious := False;

  if (AScreenLine = 0) and (ToIdx(GutterArea.TextArea.TopLine) = 0) and
     (cfCollapsedHide in tmp2) then
  begin
    Result := cfCollapsedHide;
    FHidePrevious := True;
  end
  else if cfCollapsedFold in tmp then Result := cfCollapsedFold
  else if cfCollapsedHide in tmp then Result := cfCollapsedHide
  else if cfFoldStart     in tmp then Result := cfFoldStart
  else if cfHideStart     in tmp then Result := cfHideStart
  else if cfFoldEnd       in tmp then Result := cfFoldEnd
  else if cfFoldBody      in tmp then Result := cfFoldBody
  else Result := cfNone;

  if (Result in [cfCollapsedFold, cfCollapsedHide, cfFoldStart]) and
     (cfHideStart in tmp) and
     (fncBlockSelection in FoldView.FoldClasifications[AScreenLine]) then
    Result := cfHideStart;

  if (Result in [cfFoldBody, cfFoldEnd]) and
     not (fncBlockSelection in FoldView.FoldClasifications[AScreenLine - 1]) then
  begin
    tmp := FoldView.FoldType[AScreenLine - 1];
    if tmp * [cfHideStart, cfFoldStart, cfCollapsedFold, cfCollapsedHide]
       = [cfHideStart, cfFoldStart] then
    begin
      FHidePrevious := True;
      Result := cfHideStart;
    end;
  end;
end;

function TLedGutterCodeFolding.LedIsSingleLineHide(
  AScreenLine: Integer): Boolean;
var
  tmp: TSynEditFoldLineCapabilities;
begin
  tmp := FoldView.FoldType[AScreenLine];
  Result := (tmp * [cfHideStart, cfFoldStart, cfCollapsedFold] =
             [cfHideStart, cfFoldStart, cfCollapsedFold])
            or (cfSingleLineHide in tmp);
end;

{ medit's draw_fold_mark, in LCL terms.

  Collapsed is the right-pointing chevron, open is the downward one.  The
  original strokes at 0.75 alpha over the gutter; a plain TCanvas has no
  alpha, so the pen colour is blended toward the background by the same
  quarter, which lands in the same place. }
procedure TLedGutterCodeFolding.DrawChevron(ACanvas: TCanvas;
  const ARect: TRect; ACollapsed: Boolean);
var
  CX, CY, Target: Integer;
  Half, LW: Double;
  Fg, Bg: TColor;

  function Blend(A, B: TColor; AFactorNum, AFactorDen: Integer): TColor;
  var
    R, G, Bl: Integer;
  begin
    R  := ((A and $FF) * AFactorNum + (B and $FF) * (AFactorDen - AFactorNum)) div AFactorDen;
    G  := (((A shr 8) and $FF) * AFactorNum + ((B shr 8) and $FF) * (AFactorDen - AFactorNum)) div AFactorDen;
    Bl := (((A shr 16) and $FF) * AFactorNum + ((B shr 16) and $FF) * (AFactorDen - AFactorNum)) div AFactorDen;
    Result := TColor(R or (G shl 8) or (Bl shl 16));
  end;

  procedure Arm(X1, Y1, X2, Y2: Double);
  begin
    ACanvas.MoveTo(CX + Round(X1), CY + Round(Y1));
    ACanvas.LineTo(CX + Round(X2), CY + Round(Y2));
  end;

begin
  CX := (ARect.Left + ARect.Right) div 2;
  CY := (ARect.Top + ARect.Bottom) div 2;

  Target := Width - 4;
  if Target < 6 then Target := 6;
  Half := Target / 2;

  { Stroke width is a third of the half-size, so the marker keeps its weight
    as the display scales, clamped at both ends: below about a pixel it
    disappears, above two or three it turns clumsy. }
  LW := Half / 3;
  if LW < 1.2 then LW := 1.2;
  if LW > 2.4 then LW := 2.4;

  Fg := MarkupInfo.Foreground;
  if Fg = clNone then Fg := ACanvas.Pen.Color;
  Bg := MarkupInfo.Background;
  if Bg = clNone then Bg := ACanvas.Brush.Color;

  ACanvas.Pen.Color := Blend(ColorToRGB(Fg), ColorToRGB(Bg), 3, 4);
  ACanvas.Pen.Width := Max(1, Round(LW));
  ACanvas.Pen.Style := psSolid;
  { Round ends and joins, as the original: at these sizes a mitred apex reads
    as a blob. }
  ACanvas.Pen.EndCap := pecRound;
  ACanvas.Pen.JoinStyle := pjsRound;

  { Wider and flatter than medit's proportions: the arms reach further across
    (0.95 rather than 0.7) and less far along the axis (0.34 rather than
    0.45), which reads better at the sizes this gutter runs at. }
  if ACollapsed then
  begin
    { Apex on the right, opening leftward. }
    Arm(-Half * 0.34, -Half * 0.95,  Half * 0.34, 0);
    Arm( Half * 0.34,             0, -Half * 0.34, Half * 0.95);
  end
  else
  begin
    { Apex at the bottom, opening upward. }
    Arm(-Half * 0.95, -Half * 0.34, 0,            Half * 0.34);
    Arm( 0,            Half * 0.34, Half * 0.95, -Half * 0.34);
  end;
end;

procedure TLedGutterCodeFolding.Paint(ACanvas: TCanvas; AClip: TRect;
  FirstLine, LastLine: Integer);
var
  iLine, LineHeight, LineOffset, CenterX: Integer;
  rcLine, rcFold: TRect;
  NodeType: TSynEditFoldLineCapability;
  RuleColour: TColor;

  { The vertical rule that ties a block to its end, and the foot that turns
    it into an L at the closing line.  medit draws the same guide; without it
    the markers are unattached ticks and a long block reads as unrelated
    lines. }
  procedure RuleThrough(const R: TRect);
  begin
    ACanvas.Pen.Width := 1;
    ACanvas.Pen.Color := RuleColour;
    ACanvas.MoveTo(CenterX, R.Top + LineOffset);
    ACanvas.LineTo(CenterX, R.Bottom);
    LineOffset := 0;
  end;

  procedure RuleToFoot(const R: TRect);
  begin
    ACanvas.Pen.Width := 1;
    ACanvas.Pen.Color := RuleColour;
    ACanvas.MoveTo(CenterX, R.Top + LineOffset);
    ACanvas.LineTo(CenterX, R.Bottom - 1);
    ACanvas.LineTo(R.Right, R.Bottom - 1);
    LineOffset := Min(2, (R.Top + R.Bottom) div 2);
  end;

begin
  if not Visible then Exit;

  LineHeight := SynEdit.LineHeight;
  LineOffset := 0;
  if (FirstLine > 0) and
     (FoldView.FoldType[FirstLine - 1] - [cfFoldBody] = [cfFoldEnd]) then
    LineOffset := 2;

  if MarkupInfo.Background <> clNone then
  begin
    ACanvas.Brush.Color := MarkupInfo.Background;
    LCLIntf.SetBkColor(ACanvas.Handle, TColorRef(ACanvas.Brush.Color));
    ACanvas.FillRect(AClip);
  end;

  { The rule is quieter than the markers: it is structure, not a control, and
    at full strength it draws the eye away from the code. }
  RuleColour := MarkupInfo.Foreground;
  if (RuleColour <> clNone) and (MarkupInfo.Background <> clNone) then
  begin
    RuleColour := TColor(
      ((ColorToRGB(RuleColour) and $FF) + (ColorToRGB(MarkupInfo.Background) and $FF)) div 2
      or (((((ColorToRGB(RuleColour) shr 8) and $FF) + ((ColorToRGB(MarkupInfo.Background) shr 8) and $FF)) div 2) shl 8)
      or (((((ColorToRGB(RuleColour) shr 16) and $FF) + ((ColorToRGB(MarkupInfo.Background) shr 16) and $FF)) div 2) shl 16));
  end;

  CenterX := AClip.Left + Width div 2;
  rcLine.Bottom := AClip.Top;

  for iLine := FirstLine to LastLine do
  begin
    rcLine.Top := rcLine.Bottom;
    Inc(rcLine.Bottom, LineHeight);

    rcFold.Left := AClip.Left;
    rcFold.Right := AClip.Left + Width;
    rcFold.Top := rcLine.Top;
    rcFold.Bottom := rcLine.Bottom;

    NodeType := LedFoldTypeForLine(iLine);
    case NodeType of
      cfFoldStart, cfHideStart, cfCollapsedFold, cfCollapsedHide:
        begin
          { A block that continues below gets the rule as well as the marker,
            so the chevron sits on the line rather than beside it. }
          if (not FHidePrevious) and
             (cfFoldBody in FoldView.FoldType[iLine + 1]) and
             (not LedIsSingleLineHide(iLine)) and
             (NodeType in [cfFoldStart, cfHideStart]) then
          begin
            ACanvas.Pen.Width := 1;
            ACanvas.Pen.Color := RuleColour;
            ACanvas.MoveTo(CenterX, rcFold.Top + LineHeight div 2);
            ACanvas.LineTo(CenterX, rcFold.Bottom);
          end;
          DrawChevron(ACanvas, rcFold,
            NodeType in [cfCollapsedFold, cfCollapsedHide]);
          LineOffset := 0;
        end;
      cfFoldBody:
        RuleThrough(rcFold);
      cfFoldEnd:
        RuleToFoot(rcFold);
      else
        LineOffset := 0;
    end;
  end;
end;

end.
