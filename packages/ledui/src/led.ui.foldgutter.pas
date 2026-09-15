{ LED - a lightweight editor.  Fold markers drawn as chevrons, the way medit drew
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

    * the vertical rule tying a block to its end.  LED draws guides down the
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
  SynEditMiscProcs, SynEditMouseCmds, LazSynEditMouseCmdsTypes;

type
  { Asked of a 0-based text line. }
  TLedFoldLineQuery = function(ATextIdx: Integer): Boolean of object;
  TLedFoldLineEvent = procedure(ATextIdx: Integer) of object;

  TLedGutterCodeFolding = class(TSynGutterCodeFolding)
  private
    FOnCanOpen: TLedFoldLineQuery;
    FOnOpen: TLedFoldLineEvent;
    function LedFoldTypeForLine(AScreenLine: Integer): TSynEditFoldLineCapability;
    function TextIdxOf(AScreenLine: Integer): Integer;
    procedure DrawChevron(ACanvas: TCanvas; const ARect: TRect;
      ACollapsed: Boolean);
  public
    procedure Paint(ACanvas: TCanvas; AClip: TRect;
      FirstLine, LastLine: Integer); override;
    function MaybeHandleMouseAction(var AnInfo: TSynEditMouseActionInfo;
      HandleActionProc: TSynEditMouseActionHandler): Boolean; override;

    { A line that is not folded but stands for content the view has chosen not
      to build: a BJData container with more children than the walk renders.

      It has no fold block -- there are no lines under it to hide -- so the
      fold machinery knows nothing about it.  But to the reader it is the same
      gesture: a chevron that says "there is more here", and a click that
      shows it.  OnCanOpen decides which lines those are and OnOpen is what a
      click on one does. }
    property OnCanOpen: TLedFoldLineQuery read FOnCanOpen write FOnCanOpen;
    property OnOpen: TLedFoldLineEvent read FOnOpen write FOnOpen;
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
{ The 0-based text line a screen line is showing, or -1. }
function TLedGutterCodeFolding.TextIdxOf(AScreenLine: Integer): Integer;
begin
  Result := -1;
  if AScreenLine < 0 then Exit;
  if AScreenLine >= FoldView.Count then Exit;
  Result := FoldView.TextIndex[AScreenLine];
end;

function TLedGutterCodeFolding.LedFoldTypeForLine(
  AScreenLine: Integer): TSynEditFoldLineCapability;
var
  Caps: TSynEditFoldLineCapabilities;
begin
  Result := cfNone;
  if AScreenLine < 0 then Exit;

  { A container held back for its size draws the collapsed chevron even
    though nothing is folded: what the mark means to the reader is "there is
    more here", and that is true either way. }
  if Assigned(FOnCanOpen) and FOnCanOpen(TextIdxOf(AScreenLine)) then
    Exit(cfCollapsedFold);

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
const
  { How much of the fold column the glyph fills.  Named because it is a
    judgement about how loud the marker should be, not a derived number. }
  ChevronScale = 0.7;
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

  { Seven tenths of the column it sits in, rather than all but four pixels of
    it.  The old figure is proportionally the same at every scale, which is
    the trouble: on a 3.125x display an eighteen-pixel column is fifty-six,
    and a chevron forty-nine across reads as a button rather than as a hint
    at the edge of the text.  Fine detail does not have to grow with the
    text, and the column keeps its width so the click target does not move. }
  Target := Round((Width - 4) * ChevronScale);
  if Target < 6 then Target := 6;
  Half := Target / 2;

  { Stroke width is a third of the half-size, so the marker keeps its weight
    as the display scales, clamped at both ends: below about a pixel it
    disappears, above two or three it turns clumsy. }
  LW := Half / 3;
  { medit clamped this to [1.2, 2.4] against a GTK canvas that antialiased
    the stroke; a plain TCanvas rounds it to whole pixels, so the same
    numbers came out a hairline.  Heavier, so the marker reads as a control
    rather than a scratch. }
  if LW < 1.8 then LW := 1.8;
  if LW > 3.0 then LW := 3.0;

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

{ A click on one of those chevrons opens the record instead of folding.

  Taken before the inherited handler rather than after: the line may also
  start a real fold block -- a container can be both over the element cap and
  the parent of the rows already shown -- and then both would fire, opening
  the record and collapsing it in the same click. }
function TLedGutterCodeFolding.MaybeHandleMouseAction(
  var AnInfo: TSynEditMouseActionInfo;
  HandleActionProc: TSynEditMouseActionHandler): Boolean;
var
  Idx: Integer;
begin
  if Assigned(FOnOpen) and Assigned(FOnCanOpen) and
     (AnInfo.Button = LazSynEditMouseCmdsTypes.mbLeft) then
  begin
    Idx := ToIdx(AnInfo.NewCaret.LinePos);
    if FOnCanOpen(Idx) then
    begin
      FOnOpen(Idx);
      Exit(True);
    end;
  end;
  Result := inherited MaybeHandleMouseAction(AnInfo, HandleActionProc);
end;

end.
