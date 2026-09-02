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
  overridden.

  What this column does NOT draw, deliberately:

    * the vertical rule tying a block to its end.  led draws guides down the
      body of every open block in the text itself, which says the same thing
      in the place the eye already is; two rules for one fact left a broken
      line in the gutter that went out of step with the text after every
      fold.

    * anything derived from FoldClasifications.  SynEdit's own
      FoldTypeForLine consults fncBlockSelection so that a *selection* can be
      folded, and reading it here put a chevron beside lines merely because
      they were highlighted -- a marker on a line with no block starting on
      it.  Only a real fold start gets a chevron now.

  What is left is one question per line -- does a block start here, and is it
  collapsed -- which is all a marker column needs to know.

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
    function LedFoldTypeForLine(AScreenLine: Integer): TSynEditFoldLineCapability;
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

{ Does a foldable block start on this screen line, and is it collapsed?

  Everything the previous version borrowed from SynEdit's private
  FoldTypeForLine -- the look at the line above, the block-selection
  classifications, the single-line-hide special case -- is gone.  It existed
  to place a rule and to fold selections, and this column does neither. }
function TLedGutterCodeFolding.LedFoldTypeForLine(
  AScreenLine: Integer): TSynEditFoldLineCapability;
var
  Caps: TSynEditFoldLineCapabilities;
begin
  Result := cfNone;
  if AScreenLine < 0 then Exit;
  Caps := FoldView.FoldType[AScreenLine];
  if cfCollapsedFold in Caps then Result := cfCollapsedFold
  else if cfFoldStart in Caps then Result := cfFoldStart;
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
  iLine, LineHeight: Integer;
  rcFold: TRect;
  NodeType: TSynEditFoldLineCapability;
begin
  if not Visible then Exit;
  LineHeight := SynEdit.LineHeight;

  if MarkupInfo.Background <> clNone then
  begin
    ACanvas.Brush.Color := MarkupInfo.Background;
    LCLIntf.SetBkColor(ACanvas.Handle, TColorRef(ACanvas.Brush.Color));
    ACanvas.FillRect(AClip);
  end;

  rcFold.Left := AClip.Left;
  rcFold.Right := AClip.Left + Width;
  rcFold.Bottom := AClip.Top;

  for iLine := FirstLine to LastLine do
  begin
    rcFold.Top := rcFold.Bottom;
    Inc(rcFold.Bottom, LineHeight);

    NodeType := LedFoldTypeForLine(iLine);
    if NodeType = cfNone then Continue;
    DrawChevron(ACanvas, rcFold, NodeType = cfCollapsedFold);
  end;
end;

end.
