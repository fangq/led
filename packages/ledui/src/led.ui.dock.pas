{ led - a light editor.  The four-edge dock host.

  medit hand-built a 7,200-line docking system (MooBigPaned/MooPaned/MooPane).
  led does the same job with stock LCL: one TPanel plus one TSplitter per edge,
  each panel holding a TPageControl whose tabs are that edge's panes, wrapped
  around a centre control.  Panes are not detachable -- that was dropped
  deliberately, as it accounted for a large share of the original complexity. }
unit Led.UI.Dock;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, ComCtrls, Graphics;

type
  TLedDockEdge = (ledLeft, ledRight, ledTop, ledBottom);

  TLedDockHost = class(TPanel)
  private
    FPanels: array[TLedDockEdge] of TPanel;
    FSplitters: array[TLedDockEdge] of TSplitter;
    FBooks: array[TLedDockEdge] of TPageControl;
    FCenter: TPanel;
    FDefaultSize: array[TLedDockEdge] of Integer;
    function EnsureBook(AEdge: TLedDockEdge): TPageControl;
    function GetEdgeVisible(AEdge: TLedDockEdge): Boolean;
    procedure SetEdgeVisible(AEdge: TLedDockEdge; AValue: Boolean);
    function GetEdgeSize(AEdge: TLedDockEdge): Integer;
    procedure SetEdgeSize(AEdge: TLedDockEdge; AValue: Integer);
  public
    constructor Create(AOwner: TComponent); override;

    { Docks AControl as a new pane on AEdge and returns its page.  The pane is
      identified by AId for layout persistence; ACaption is what the user sees. }
    function AddPane(AEdge: TLedDockEdge; const AId, ACaption: string;
      AControl: TControl): TTabSheet;
    function FindPane(const AId: string): TTabSheet;
    procedure ShowPane(const AId: string);
    procedure ToggleEdge(AEdge: TLedDockEdge);

    property Center: TPanel read FCenter;
    property EdgeVisible[AEdge: TLedDockEdge]: Boolean
      read GetEdgeVisible write SetEdgeVisible;
    property EdgeSize[AEdge: TLedDockEdge]: Integer
      read GetEdgeSize write SetEdgeSize;
  end;

const
  LedDockEdgeName: array[TLedDockEdge] of string =
    ('left', 'right', 'top', 'bottom');

implementation

const
  EdgeAlign: array[TLedDockEdge] of TAlign =
    (alLeft, alRight, alTop, alBottom);
  EdgeDefault: array[TLedDockEdge] of Integer = (220, 220, 150, 180);

constructor TLedDockHost.Create(AOwner: TComponent);
var
  E: TLedDockEdge;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';

  { Child order decides alignment nesting: each edge panel is created before
    its splitter, so the splitter always ends up on the inner face. }
  for E := Low(TLedDockEdge) to High(TLedDockEdge) do
  begin
    FDefaultSize[E] := EdgeDefault[E];

    FPanels[E] := TPanel.Create(Self);
    FPanels[E].Parent := Self;
    FPanels[E].Align := EdgeAlign[E];
    FPanels[E].BevelOuter := bvNone;
    FPanels[E].Caption := '';
    FPanels[E].Visible := False;
    if E in [ledLeft, ledRight] then
      FPanels[E].Width := EdgeDefault[E]
    else
      FPanels[E].Height := EdgeDefault[E];

    FSplitters[E] := TSplitter.Create(Self);
    FSplitters[E].Parent := Self;
    FSplitters[E].Align := EdgeAlign[E];
    FSplitters[E].Visible := False;
    FSplitters[E].ResizeStyle := rsUpdate;
    FSplitters[E].MinSize := 60;
  end;

  FCenter := TPanel.Create(Self);
  FCenter.Parent := Self;
  FCenter.Align := alClient;
  FCenter.BevelOuter := bvNone;
  FCenter.Caption := '';
end;

function TLedDockHost.EnsureBook(AEdge: TLedDockEdge): TPageControl;
begin
  if FBooks[AEdge] = nil then
  begin
    FBooks[AEdge] := TPageControl.Create(Self);
    FBooks[AEdge].Parent := FPanels[AEdge];
    FBooks[AEdge].Align := alClient;
    if AEdge in [ledLeft, ledRight] then
      FBooks[AEdge].TabPosition := tpBottom;
  end;
  Result := FBooks[AEdge];
end;

function TLedDockHost.AddPane(AEdge: TLedDockEdge; const AId, ACaption: string;
  AControl: TControl): TTabSheet;
var
  Book: TPageControl;
begin
  Book := EnsureBook(AEdge);
  Result := Book.AddTabSheet;
  Result.Caption := ACaption;
  Result.Hint := AId;          // pane id, used by FindPane and by persistence
  if AControl <> nil then
  begin
    AControl.Parent := Result;
    AControl.Align := alClient;
  end;
  EdgeVisible[AEdge] := True;
end;

function TLedDockHost.FindPane(const AId: string): TTabSheet;
var
  E: TLedDockEdge;
  i: Integer;
begin
  for E := Low(TLedDockEdge) to High(TLedDockEdge) do
    if FBooks[E] <> nil then
      for i := 0 to FBooks[E].PageCount - 1 do
        if FBooks[E].Pages[i].Hint = AId then
          Exit(FBooks[E].Pages[i]);
  Result := nil;
end;

procedure TLedDockHost.ShowPane(const AId: string);
var
  Sheet: TTabSheet;
  Book: TPageControl;
  E: TLedDockEdge;
begin
  Sheet := FindPane(AId);
  if Sheet = nil then Exit;
  Book := TPageControl(Sheet.PageControl);
  Book.ActivePage := Sheet;
  for E := Low(TLedDockEdge) to High(TLedDockEdge) do
    if FBooks[E] = Book then
      EdgeVisible[E] := True;
end;

function TLedDockHost.GetEdgeVisible(AEdge: TLedDockEdge): Boolean;
begin
  Result := FPanels[AEdge].Visible;
end;

procedure TLedDockHost.SetEdgeVisible(AEdge: TLedDockEdge; AValue: Boolean);
begin
  if FPanels[AEdge].Visible = AValue then Exit;
  FPanels[AEdge].Visible := AValue;
  FSplitters[AEdge].Visible := AValue;
end;

function TLedDockHost.GetEdgeSize(AEdge: TLedDockEdge): Integer;
begin
  if AEdge in [ledLeft, ledRight] then
    Result := FPanels[AEdge].Width
  else
    Result := FPanels[AEdge].Height;
end;

procedure TLedDockHost.SetEdgeSize(AEdge: TLedDockEdge; AValue: Integer);
begin
  if AValue < 40 then AValue := FDefaultSize[AEdge];
  if AEdge in [ledLeft, ledRight] then
    FPanels[AEdge].Width := AValue
  else
    FPanels[AEdge].Height := AValue;
end;

procedure TLedDockHost.ToggleEdge(AEdge: TLedDockEdge);
begin
  EdgeVisible[AEdge] := not EdgeVisible[AEdge];
end;

end.
