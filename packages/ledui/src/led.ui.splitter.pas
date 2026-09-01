{ led - a light editor.  Splitters that keep both sides visible.

  TPairSplitter has no minimum of any kind -- only Position -- so every
  divider built on it could be dragged until one side was gone: a split view
  with one editor at zero width, a split notebook with an invisible group, a
  terminal split with nothing on one side.  Recovering meant finding a
  one-pixel divider and dragging it back.

  TCustomSplitter, by contrast, already refuses: it takes
  Max(MinSize, the control's own Constraints) for the control it resizes *and*
  for the one opposite.  So the LCL splitters only needed a larger MinSize
  than the default 30, and it is the pair splitters that needed a class.

  The clamp is applied on resize rather than by intercepting the drag,
  because SetPosition is not virtual and the divider is moved by the
  widgetset.  Correcting the position afterwards is what can be done from
  here, and it is enough: the side stops at the minimum instead of
  disappearing. }
unit Led.UI.Splitter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, PairSplitter;

type
  TLedPairSplitter = class(TPairSplitter)
  private
    FMinSide: Integer;
    procedure SetMinSide(AValue: Integer);
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Neither side may be squeezed below this many pixels.  Zero disables the
      clamp, which is the old behaviour and nobody's preference. }
    property MinSide: Integer read FMinSide write SetMinSide;
  end;

{ The extent the divider divides: width for a side-by-side split, height for a
  stacked one. }
function LedSplitterExtent(ASplitter: TPairSplitter): Integer;

implementation

function LedSplitterExtent(ASplitter: TPairSplitter): Integer;
begin
  if ASplitter = nil then Exit(0);
  if ASplitter.SplitterType = pstVertical then
    Result := ASplitter.Height
  else
    Result := ASplitter.Width;
end;

constructor TLedPairSplitter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMinSide := 60;
end;

procedure TLedPairSplitter.SetMinSide(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FMinSide = AValue then Exit;
  FMinSide := AValue;
  Resize;
end;

procedure TLedPairSplitter.Resize;
var
  Extent, Lo, Hi: Integer;
begin
  inherited Resize;
  if FMinSide <= 0 then Exit;

  Extent := LedSplitterExtent(Self);
  { Too small to honour the minimum on both sides: leave the divider alone
    rather than fight a window that is simply narrow, which would leave it
    jittering as the user resizes. }
  if Extent < FMinSide * 2 then Exit;

  Lo := FMinSide;
  Hi := Extent - FMinSide;
  if Position < Lo then
    Position := Lo
  else if Position > Hi then
    Position := Hi;
end;

end.
