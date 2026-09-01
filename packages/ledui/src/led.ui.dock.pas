{ led - a light editor.  The dock host.

  medit hand-built a 7,200-line docking system (MooBigPaned/MooPaned/MooPane)
  to get panes that could be dragged between edges, collapsed to a title bar
  and torn off into their own window.  led gets the same behaviour from
  AnchorDocking, the package the Lazarus IDE docks itself with: drag a pane by
  its header and drop it on any edge of any other pane, double-click the
  header to float it, close it with the button on the header, and the layout
  survives a restart.

  What this unit adds on top is the vocabulary the rest of led speaks.
  AnchorDocking has no notion of "the left edge" -- a pane is wherever the
  user last put it -- but the menu still has to offer "Left Pane", and a pane
  still has to appear somewhere sensible the first time it is shown.  So each
  pane is registered with the edge it belongs to by default, and an edge is
  "visible" when any of its panes is.

  Panes are ordinary controls; each is wrapped in a host form here, because
  AnchorDocking docks forms. }
unit Led.UI.Dock;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, ComCtrls, Buttons, Forms, Graphics,
  ImgList, AnchorDocking, AnchorDockPanel, AnchorDockStorage, XMLPropStorage;

type
  TLedDockEdge = (ledLeft, ledRight, ledTop, ledBottom);

  { The window each pane lives in.  It is a form because that is what
    AnchorDocking docks; the user never sees it as a window unless they float
    it, which is the point. }
  TLedPaneForm = class(TForm)
  private
    FPaneId: string;
    FEdge: TLedDockEdge;
    FContent: TControl;
    FIconName: string;
  public
    constructor CreatePane(AOwner: TComponent; const AId, ACaption: string;
      AEdge: TLedDockEdge; AControl: TControl);
    property PaneId: string read FPaneId;
    property Edge: TLedDockEdge read FEdge;
    property Content: TControl read FContent;
    { Which icon the edge rail draws for this pane.  Defaults to the pane id,
      which is right for the panes whose id happens to name an icon. }
    property IconName: string read FIconName write FIconName;
  end;

  TLedDockHost = class(TPanel)
  private
    FSite: TAnchorDockPanel;
    FCenter: TPanel;
    FCenterForm: TLedPaneForm;
    FPanes: TFPList;               // of TLedPaneForm, in registration order
    FReady: Boolean;
    FRails: array[TLedDockEdge] of TPanel;
    FImages: TCustomImageList;
    FShowRails: Boolean;
    FRailsStale: Boolean;
    FRailsSettle: TTimer;
    FDraggingWanted: Boolean;
    procedure ApplyDockPolicy;
    procedure RailsSettled(Sender: TObject);
    procedure BuildRail(AEdge: TLedDockEdge);
    procedure RailButtonClick(Sender: TObject);
    procedure SetShowRails(AValue: Boolean);
    procedure SetImages(AValue: TCustomImageList);
    function GetEdgeVisible(AEdge: TLedDockEdge): Boolean;
    procedure SetEdgeVisible(AEdge: TLedDockEdge; AValue: Boolean);
    function GetEdgeSize(AEdge: TLedDockEdge): Integer;
    procedure SetEdgeSize(AEdge: TLedDockEdge; AValue: Integer);
    function PaneById(const AId: string): TLedPaneForm;
    procedure DockPane(APane: TLedPaneForm);
    procedure MasterCreateControl(Sender: TObject; aName: string;
      var AControl: TControl; DoDisableAutoSizing: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Registers AControl as a pane and returns its host form.  AId identifies
      it in the saved layout; ACaption is the header text; AEdge is where it
      goes the first time, before the user has moved it. }
    function AddPane(AEdge: TLedDockEdge; const AId, ACaption: string;
      AControl: TControl; const AIconName: string = ''): TLedPaneForm;
    function FindPane(const AId: string): TLedPaneForm;
    procedure ShowPane(const AId: string);
    procedure HidePane(const AId: string);
    function PaneVisible(const AId: string): Boolean;
    procedure ToggleEdge(AEdge: TLedDockEdge);
    procedure TogglePane(const AId: string);

    { True when anything is registered for AEdge at all.  An edge with no
      panes cannot be shown, and the menu should say so rather than offering
      a toggle that does nothing. }
    function EdgeHasPanes(AEdge: TLedDockEdge): Boolean;

    { Tears APane off into a window of its own, and puts it back.  This is
      what medit's detachable panes did, and what AnchorDocking gives for
      free by dragging the header. }
    function FloatPane(const AId: string): Boolean;
    function RedockPane(const AId: string): Boolean;
    function PaneFloating(const AId: string): Boolean;

    { Puts every pane back where it started: all closed, the editor filling
      the window, and the saved layout discarded so a restart agrees.  This is
      the way out of a layout that dragging has made unusable, which
      AnchorDocking offers no other route back from. }
    procedure ResetLayout(const AFileName: string = '');

    { The layout, including floating windows and every splitter position. }
    procedure SaveLayout(const AFileName: string);
    function LoadLayout(const AFileName: string): Boolean;

    { The edge rails: a thin strip on each edge carrying one button per pane
      registered there, pressed while that pane is open.  Without them a
      closed pane can only be brought back from the View menu, because
      AnchorDocking removes the pane entirely rather than collapsing it to
      anything clickable -- which is what medit's collapsed pane titles were
      for.  Rebuilt when panes are added, refreshed when one opens or
      closes. }
    procedure RebuildRails;
    procedure RefreshRails;

    { Whether a pane can be torn off by dragging its header or its tab.  Those
      are the only two things AnchorDocking gates on this -- splitters, and so
      resizing a pane, are untouched. }
    function GetDragging: Boolean;
    procedure SetDragging(AValue: Boolean);

    property Center: TPanel read FCenter;
    property Images: TCustomImageList read FImages write SetImages;
    property DraggingAllowed: Boolean read GetDragging write SetDragging;
    property ShowRails: Boolean read FShowRails write SetShowRails;
    property EdgeVisible[AEdge: TLedDockEdge]: Boolean
      read GetEdgeVisible write SetEdgeVisible;
    property EdgeSize[AEdge: TLedDockEdge]: Integer
      read GetEdgeSize write SetEdgeSize;
  end;

const
  LedDockEdgeName: array[TLedDockEdge] of string =
    ('left', 'right', 'top', 'bottom');

implementation

uses
  Led.UI.Icons;

const
  { Where each edge's panes are dropped the first time.  After that the saved
    layout decides, and after that the user does. }
  EdgeAlign: array[TLedDockEdge] of TAlign =
    (alLeft, alRight, alTop, alBottom);
  EdgeDefault: array[TLedDockEdge] of Integer = (220, 220, 150, 180);

{ TLedPaneForm }

constructor TLedPaneForm.CreatePane(AOwner: TComponent;
  const AId, ACaption: string; AEdge: TLedDockEdge; AControl: TControl);
begin
  { CreateNew, not Create: there is no .lfm for these and there does not need
    to be -- the pane control supplies the whole contents. }
  inherited CreateNew(AOwner);
  FPaneId := AId;
  FEdge := AEdge;
  FContent := AControl;
  FIconName := AId;    { overridden by AddPane where the id names no icon }

  { AnchorDocking identifies a control by its Name in the saved layout, and
    the LCL only accepts an identifier, so the id is sanitised rather than
    used raw. }
  Name := 'Pane_' + StringReplace(AId, '-', '_', [rfReplaceAll]);
  Caption := ACaption;
  BorderStyle := bsSizeable;
  Width := EdgeDefault[AEdge];
  Height := EdgeDefault[AEdge];

  if AControl <> nil then
  begin
    AControl.Parent := Self;
    AControl.Align := alClient;
  end;
end;

{ TLedDockHost }

constructor TLedDockHost.Create(AOwner: TComponent);
var
  E: TLedDockEdge;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  FPanes := TFPList.Create;
  FShowRails := True;

  { The rails are created before the dock site and aligned to the edges, so
    the site's alClient takes what is left and the strips stay outside it --
    they must not become part of anything AnchorDocking can rearrange, or the
    user could drag a pane on top of the control for reopening it. }
  for E := Low(TLedDockEdge) to High(TLedDockEdge) do
  begin
    FRails[E] := TPanel.Create(Self);
    FRails[E].Parent := Self;
    FRails[E].BevelOuter := bvNone;
    FRails[E].Caption := '';
    FRails[E].Align := EdgeAlign[E];
    FRails[E].Visible := False;      { until an edge has panes }
    FRails[E].Width := 0;
    FRails[E].Height := 0;
  end;

  FRailsSettle := TTimer.Create(Self);
  FRailsSettle.Interval := 250;
  FRailsSettle.Enabled := False;
  FRailsSettle.OnTimer := @RailsSettled;

  FSite := TAnchorDockPanel.Create(Self);
  FSite.Parent := Self;
  FSite.Align := alClient;
  FSite.Name := 'LedDockSite';

  { The centre is a pane like any other, so that the panes around it can be
    dragged past it and it keeps its share of the space.  It is the one pane
    without a close button: closing the editor area would leave nothing. }
  FCenter := TPanel.Create(Self);
  FCenter.BevelOuter := bvNone;
  FCenter.Caption := '';

  FCenterForm := TLedPaneForm.CreatePane(Self, 'editor', 'Editor',
    ledLeft, FCenter);

  DockMaster.MakeDockPanel(FSite, admrpChild);
  DockMaster.OnCreateControl := @MasterCreateControl;

  FDraggingWanted := True;
  ApplyDockPolicy;

  { No header on the editor, and that is the fix for a state the user could
    not get out of: dragging the editor's header tore the editor out into a
    window of its own, and once out it could not be dropped back -- the site
    it came from is a TAnchorDockPanel, and with its only child gone there is
    nothing left on screen to aim at.  The editor area is not a pane the user
    can usefully float anyway; medit's was not detachable either.

    The fourth argument is AddDockHeader.  Without a header there is nothing
    to grab and nothing to close, which is what the comment above FCenterForm
    already claimed and this now actually implements.  Panes still dock
    around it, because they dock to the site rather than to the header. }
  DockMaster.MakeDockable(FCenterForm, True, True, False);
  DockMaster.ManualDock(DockMaster.GetAnchorSite(FCenterForm), FSite, alClient);
  FReady := True;
end;

destructor TLedDockHost.Destroy;
begin
  FPanes.Free;
  inherited Destroy;
end;

procedure TLedDockHost.MasterCreateControl(Sender: TObject; aName: string;
  var AControl: TControl; DoDisableAutoSizing: Boolean);
var
  i: Integer;
  Pane: TLedPaneForm;
begin
  { Restoring a saved layout asks for controls by name.  Every pane already
    exists by then, so this is a lookup rather than a factory. }
  AControl := nil;
  for i := 0 to FPanes.Count - 1 do
  begin
    Pane := TLedPaneForm(FPanes[i]);
    if SameText(Pane.Name, aName) then
    begin
      AControl := Pane;
      Break;
    end;
  end;
  if (AControl = nil) and SameText(FCenterForm.Name, aName) then
    AControl := FCenterForm;
  if (AControl <> nil) and DoDisableAutoSizing then
    AControl.DisableAutoSizing;
end;

function TLedDockHost.AddPane(AEdge: TLedDockEdge;
  const AId, ACaption: string; AControl: TControl;
  const AIconName: string): TLedPaneForm;
begin
  Result := TLedPaneForm.CreatePane(Self, AId, ACaption, AEdge, AControl);
  if AIconName <> '' then
    Result.IconName := AIconName;
  FPanes.Add(Result);
  DockMaster.MakeDockable(Result, False, True, True);
  BuildRail(AEdge);
end;

function TLedDockHost.PaneById(const AId: string): TLedPaneForm;
var
  i: Integer;
begin
  for i := 0 to FPanes.Count - 1 do
    if SameText(TLedPaneForm(FPanes[i]).PaneId, AId) then
      Exit(TLedPaneForm(FPanes[i]));
  { The centre is a pane too, and deliberately not in FPanes -- it must not
    appear on a rail or in the pane menu.  It still has to be findable, or
    RedockPane cannot rescue an editor that an older layout left floating. }
  if (FCenterForm <> nil) and SameText(FCenterForm.PaneId, AId) then
    Exit(FCenterForm);
  Result := nil;
end;

function TLedDockHost.FindPane(const AId: string): TLedPaneForm;
begin
  Result := PaneById(AId);
end;

procedure TLedDockHost.DockPane(APane: TLedPaneForm);
begin
  { First appearance: put it on the edge it was registered for, against the
    editor area.  Afterwards AnchorDocking remembers where it was, so this
    only runs once per pane per layout. }
  DockMaster.ShowControl(APane.Name, True);
  if DockMaster.GetAnchorSite(APane) = nil then Exit;
  if DockMaster.GetAnchorSite(APane).Parent = nil then
    DockMaster.ManualDock(DockMaster.GetAnchorSite(APane), FSite,
      EdgeAlign[APane.Edge]);
end;

procedure TLedDockHost.ShowPane(const AId: string);
var
  Pane: TLedPaneForm;
begin
  Pane := PaneById(AId);
  if Pane = nil then Exit;
  DockPane(Pane);
end;

procedure TLedDockHost.HidePane(const AId: string);
var
  Pane: TLedPaneForm;
  Site: TAnchorDockHostSite;
begin
  Pane := PaneById(AId);
  if Pane = nil then Exit;
  Site := DockMaster.GetAnchorSite(Pane);
  { Closing the site is what the header's close button does, so hiding a pane
    from the menu leaves exactly the state closing it by hand would. }
  if Site <> nil then
    Site.CloseSite
  else
    Pane.Hide;
end;

function TLedDockHost.PaneVisible(const AId: string): Boolean;
var
  Pane: TLedPaneForm;
  Site: TCustomForm;
begin
  Result := False;
  Pane := PaneById(AId);
  if Pane = nil then Exit;
  Site := DockMaster.GetSite(Pane);
  Result := (Site <> nil) and Site.Visible and Pane.Visible;
end;

procedure TLedDockHost.TogglePane(const AId: string);
begin
  if PaneVisible(AId) then HidePane(AId) else ShowPane(AId);
  RefreshRails;
end;

{ --- edge rails ----------------------------------------------------------- }

procedure TLedDockHost.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  FImages := AValue;
  RebuildRails;
end;

procedure TLedDockHost.SetShowRails(AValue: Boolean);
var
  E: TLedDockEdge;
begin
  if FShowRails = AValue then Exit;
  FShowRails := AValue;
  for E := Low(TLedDockEdge) to High(TLedDockEdge) do
    if FRails[E] <> nil then
      FRails[E].Visible := FShowRails and EdgeHasPanes(E);
end;

procedure TLedDockHost.RailButtonClick(Sender: TObject);
begin
  if not (Sender is TSpeedButton) then Exit;
  TogglePane(TSpeedButton(Sender).Hint);
end;

{ One button per pane registered for this edge, laid out along it.  The rail
  is built from scratch rather than patched, because panes are registered
  once at startup and the cost is irrelevant next to getting the incremental
  case wrong. }
procedure TLedDockHost.BuildRail(AEdge: TLedDockEdge);
var
  Rail: TPanel;
  Btn: TSpeedButton;
  Pane: TLedPaneForm;
  i, N, Size, Pad: Integer;
  Horizontal: Boolean;
begin
  Rail := FRails[AEdge];
  if Rail = nil then Exit;

  Horizontal := AEdge in [ledTop, ledBottom];

  while Rail.ControlCount > 0 do
    Rail.Controls[0].Free;

  { Sized from the image list so the rail follows the display: the icons are
    built at 16 for a 96-dpi screen and scaled with everything else. }
  Size := 16;
  if (FImages <> nil) and (FImages.Width > 0) then
    Size := FImages.Width;
  Pad := 4;

  N := 0;
  for i := 0 to FPanes.Count - 1 do
  begin
    Pane := TLedPaneForm(FPanes[i]);
    if Pane.Edge <> AEdge then Continue;

    Btn := TSpeedButton.Create(Rail);
    Btn.Parent := Rail;
    Btn.Width := Size + Pad * 2;
    Btn.Height := Size + Pad * 2;
    if Horizontal then
    begin
      Btn.Left := N * (Size + Pad * 2);
      Btn.Top := 0;
    end
    else
    begin
      Btn.Left := 0;
      Btn.Top := N * (Size + Pad * 2);
    end;
    Btn.Flat := True;
    Btn.AllowAllUp := True;
    Btn.GroupIndex := 1000 + i;      { so Down can be toggled independently }
    { The id travels in Hint: it is also the tooltip the user needs, and it
      saves a parallel lookup table that could fall out of step. }
    Btn.Hint := Pane.PaneId;
    Btn.ShowHint := True;
    Btn.Images := FImages;
    Btn.ImageIndex := LedIconIndex(Pane.IconName);
    if Btn.ImageIndex < 0 then
    begin
      { No icon for this pane: fall back to a letter, so the button is still
        something the user can hit rather than a blank square. }
      Btn.Images := nil;
      if Pane.PaneId <> '' then
        Btn.Caption := UpperCase(Copy(Pane.PaneId, 1, 1));
    end;
    Btn.OnClick := @RailButtonClick;
    Inc(N);
  end;

  if Horizontal then
    Rail.Height := Size + Pad * 2
  else
    Rail.Width := Size + Pad * 2;
  Rail.Visible := FShowRails and (N > 0);

  RefreshRails;
end;

{ A drag leaves the rails out of date, and the drop itself is the worst
  moment to read the dock.  So the refresh is deferred: a short one-shot
  timer fires once the layout has settled, well after AnchorDocking has
  finished rebuilding its sites.  Quarter of a second is below noticing and
  far above the rebuild. }
procedure TLedDockHost.RailsSettled(Sender: TObject);
begin
  FRailsSettle.Enabled := False;
  if (DragManager <> nil) and DragManager.IsDragging then
  begin
    { still going -- come back }
    FRailsSettle.Enabled := True;
    Exit;
  end;
  RefreshRails;
end;

procedure TLedDockHost.RebuildRails;
var
  E: TLedDockEdge;
begin
  for E := Low(TLedDockEdge) to High(TLedDockEdge) do
    BuildRail(E);
end;

{ Reflect which panes are actually open.  Called after led changes a pane
  itself; the main form also calls it on idle, because a pane closed with the
  header's own close button never comes through here. }
procedure TLedDockHost.RefreshRails;
var
  E: TLedDockEdge;
  i: Integer;
  Btn: TSpeedButton;
begin
  { Never while a drag is in flight.  This is called from the action-update
    pass, which runs on every idle -- including throughout a drag -- and
    PaneVisible reads DockMaster.GetSite(Pane).Visible.  During a drop
    AnchorDocking is tearing down and building host sites, so those reads can
    land on a site that is part-way through being freed.  At the gtk2 level
    that surfaces as

      GLib-GObject-WARNING: instance with invalid (NULL) class pointer
      GLib-GObject-CRITICAL: g_signal_stop_emission_by_name: assertion
        'G_TYPE_CHECK_INSTANCE (instance)' failed

    and then an access violation.  The rails are a convenience; they have no
    business reading the dock's internals at the one moment those internals
    are not a consistent structure.  RefreshAfterDrag picks it up once the
    drag is over. }
  if (DragManager <> nil) and DragManager.IsDragging then
  begin
    FRailsStale := True;
    if FRailsSettle <> nil then
      FRailsSettle.Enabled := True;
    Exit;
  end;
  FRailsStale := False;

  for E := Low(TLedDockEdge) to High(TLedDockEdge) do
  begin
    if FRails[E] = nil then Continue;
    for i := 0 to FRails[E].ControlCount - 1 do
      if FRails[E].Controls[i] is TSpeedButton then
      begin
        Btn := TSpeedButton(FRails[E].Controls[i]);
        Btn.Down := PaneVisible(Btn.Hint);
      end;
  end;
end;

function TLedDockHost.GetEdgeVisible(AEdge: TLedDockEdge): Boolean;
var
  i: Integer;
  Pane: TLedPaneForm;
begin
  { An edge is as visible as its panes.  There is no edge any more, strictly
    speaking, but the menu still asks the question. }
  for i := 0 to FPanes.Count - 1 do
  begin
    Pane := TLedPaneForm(FPanes[i]);
    if (Pane.Edge = AEdge) and PaneVisible(Pane.PaneId) then Exit(True);
  end;
  Result := False;
end;

procedure TLedDockHost.SetEdgeVisible(AEdge: TLedDockEdge; AValue: Boolean);
var
  i: Integer;
  Pane: TLedPaneForm;
begin
  if AValue and (GetEdgeVisible(AEdge) = AValue) then Exit;
  for i := 0 to FPanes.Count - 1 do
  begin
    Pane := TLedPaneForm(FPanes[i]);
    if Pane.Edge <> AEdge then Continue;
    if AValue then
    begin
      { Showing an edge shows the first pane registered for it, not all of
        them; showing four stacked panes because one was asked for is not
        what the menu item promises. }
      DockPane(Pane);
      Exit;
    end
    else
      HidePane(Pane.PaneId);
  end;
end;

function TLedDockHost.GetEdgeSize(AEdge: TLedDockEdge): Integer;
var
  i: Integer;
  Pane: TLedPaneForm;
  Site: TCustomForm;
begin
  Result := EdgeDefault[AEdge];
  for i := 0 to FPanes.Count - 1 do
  begin
    Pane := TLedPaneForm(FPanes[i]);
    if Pane.Edge <> AEdge then Continue;
    Site := DockMaster.GetSite(Pane);
    if Site = nil then Continue;
    if AEdge in [ledLeft, ledRight] then
      Exit(Site.Width)
    else
      Exit(Site.Height);
  end;
end;

procedure TLedDockHost.SetEdgeSize(AEdge: TLedDockEdge; AValue: Integer);
var
  i: Integer;
  Pane: TLedPaneForm;
  Site: TCustomForm;
begin
  if AValue < 40 then Exit;
  for i := 0 to FPanes.Count - 1 do
  begin
    Pane := TLedPaneForm(FPanes[i]);
    if Pane.Edge <> AEdge then Continue;
    Site := DockMaster.GetSite(Pane);
    if Site = nil then Continue;
    if AEdge in [ledLeft, ledRight] then
      Site.Width := AValue
    else
      Site.Height := AValue;
    Exit;
  end;
end;

function TLedDockHost.EdgeHasPanes(AEdge: TLedDockEdge): Boolean;
var
  i: Integer;
begin
  for i := 0 to FPanes.Count - 1 do
    if TLedPaneForm(FPanes[i]).Edge = AEdge then Exit(True);
  Result := False;
end;

function TLedDockHost.FloatPane(const AId: string): Boolean;
var
  Pane: TLedPaneForm;
  Site: TAnchorDockHostSite;
begin
  Result := False;
  Pane := PaneById(AId);
  if Pane = nil then Exit;
  DockPane(Pane);
  Site := DockMaster.GetAnchorSite(Pane);
  if Site = nil then Exit;
  if Site.Parent = nil then Exit(True);      // already floating
  { ManualFloat is the public route to what the header's undock button does. }
  DockMaster.ManualFloat(Pane);
  Site := DockMaster.GetAnchorSite(Pane);
  Result := (Site <> nil) and (Site.Parent = nil);
end;

function TLedDockHost.RedockPane(const AId: string): Boolean;
var
  Pane: TLedPaneForm;
  Site: TAnchorDockHostSite;
begin
  Result := False;
  Pane := PaneById(AId);
  if Pane = nil then Exit;
  Site := DockMaster.GetAnchorSite(Pane);
  if Site = nil then Exit;
  if Site.Parent <> nil then Exit(True);     // already docked
  DockMaster.ManualDock(Site, FSite, EdgeAlign[Pane.Edge]);
  Result := Site.Parent <> nil;
end;

function TLedDockHost.PaneFloating(const AId: string): Boolean;
var
  Pane: TLedPaneForm;
  Site: TAnchorDockHostSite;
begin
  Result := False;
  Pane := PaneById(AId);
  if Pane = nil then Exit;
  Site := DockMaster.GetAnchorSite(Pane);
  Result := (Site <> nil) and (Site.Parent = nil) and Site.Visible;
end;

procedure TLedDockHost.ToggleEdge(AEdge: TLedDockEdge);
begin
  EdgeVisible[AEdge] := not EdgeVisible[AEdge];
end;

{ Everything led deliberately decides about the dock, in one place that can
  be re-asserted.

  It has to be re-assertable because layout.xml carries these very settings:
  TAnchorDockSettings.LoadFromConfig restores AllowDragging, HeaderStyle,
  HeaderFlatten, HeaderFilled and HeaderHighlightFocused among others, and
  LoadLayout feeds them straight onto the master.  Setting them once in the
  constructor therefore lasted until the saved layout was read, a few lines
  later in FormCreate, and then silently reverted -- which is why locking the
  panes appeared to do nothing at all, and why the flat headers would come
  back beveled for anyone with an older layout file. }
procedure TLedDockHost.ApplyDockPolicy;
begin
  DockMaster.HideHeaderCaptionFloatingControl := False;
  DockMaster.ShowHeaderCaption := True;

  { The pane headers, left to themselves, are three bevels deep: the header
    paint draws Frame3d(r,1,bvRaised) around everything unless HeaderFlatten
    is set, and the default 'Frame3D' style then adds Frame3d(r,2,bvLowered)
    and Frame3d(r,4,bvRaised) on top.  Flattened, with the 'Line' style, the
    affordance is a single hairline down the middle -- the same idea, one
    stroke instead of six edges. }
  DockMaster.HeaderFlatten := True;
  DockMaster.HeaderFilled := False;
  DockMaster.HeaderStyle := 'Line';

  { With flat headers nothing else says which pane has focus, a cue the
    bevels used to carry by accident. }
  DockMaster.HeaderHighlightFocused := True;

  DockMaster.AllowDragging := FDraggingWanted;
end;

function TLedDockHost.GetDragging: Boolean;
begin
  Result := DockMaster.AllowDragging;
end;

procedure TLedDockHost.SetDragging(AValue: Boolean);
begin
  FDraggingWanted := AValue;
  DockMaster.AllowDragging := AValue;
end;

procedure TLedDockHost.ResetLayout(const AFileName: string);
var
  i: Integer;
  Pane: TLedPaneForm;
begin
  { Close every pane.  The defaults this restores are the ones FormCreate
    sets up: nothing open but the editor, which is also what a first run
    looks like. }
  for i := 0 to FPanes.Count - 1 do
  begin
    Pane := TLedPaneForm(FPanes[i]);
    try
      HidePane(Pane.PaneId);
    except
      { One pane that will not close must not stop the rest going back. }
    end;
  end;

  { The editor may have been floated by an older layout, or left somewhere
    unhelpful.  It has no header to drag back by, so put it back here. }
  if PaneFloating('editor') then
    RedockPane('editor');

  { Discard the saved layout too.  Resetting the window and then restoring
    the old arrangement on the next start would be a reset that did not. }
  if (AFileName <> '') and FileExists(AFileName) then
    DeleteFile(AFileName);

  RebuildRails;
end;

procedure TLedDockHost.SaveLayout(const AFileName: string);
var
  Cfg: TXMLConfigStorage;
begin
  if not FReady then Exit;
  Cfg := TXMLConfigStorage.Create(AFileName, False);
  try
    DockMaster.SaveLayoutToConfig(Cfg);
    DockMaster.SaveSettingsToConfig(Cfg);
    Cfg.WriteToDisk;
  finally
    Cfg.Free;
  end;
end;

function TLedDockHost.LoadLayout(const AFileName: string): Boolean;
var
  Cfg: TXMLConfigStorage;
begin
  Result := False;
  if not FileExists(AFileName) then Exit;
  try
    Cfg := TXMLConfigStorage.Create(AFileName, True);
    try
      DockMaster.LoadSettingsFromConfig(Cfg);
      Result := DockMaster.LoadLayoutFromConfig(Cfg, True);
    finally
      Cfg.Free;
    end;
  except
    { A layout from an older build, or a corrupt one, is not worth failing to
      start over: fall back to the defaults. }
    Result := False;
  end;

  { The saved layout has just overwritten every setting above, so put led's
    own back.  This is the whole reason ApplyDockPolicy exists. }
  ApplyDockPolicy;

  { A layout saved before the editor lost its header can have the editor
    floating, and there is now no header to drag it back by.  Put it back
    rather than leaving the user with an empty window and their text in a
    stray one. }
  if PaneFloating('editor') then
    RedockPane('editor');

  RebuildRails;
end;

end.
