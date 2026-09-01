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
  Classes, SysUtils, Controls, ExtCtrls, ComCtrls, Forms, Graphics,
  AnchorDocking, AnchorDockPanel, AnchorDockStorage, XMLPropStorage;

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
  public
    constructor CreatePane(AOwner: TComponent; const AId, ACaption: string;
      AEdge: TLedDockEdge; AControl: TControl);
    property PaneId: string read FPaneId;
    property Edge: TLedDockEdge read FEdge;
    property Content: TControl read FContent;
  end;

  TLedDockHost = class(TPanel)
  private
    FSite: TAnchorDockPanel;
    FCenter: TPanel;
    FCenterForm: TLedPaneForm;
    FPanes: TFPList;               // of TLedPaneForm, in registration order
    FReady: Boolean;
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
      AControl: TControl): TLedPaneForm;
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

    { The layout, including floating windows and every splitter position. }
    procedure SaveLayout(const AFileName: string);
    function LoadLayout(const AFileName: string): Boolean;

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
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  FPanes := TFPList.Create;

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
  DockMaster.HideHeaderCaptionFloatingControl := False;
  DockMaster.ShowHeaderCaption := True;

  DockMaster.MakeDockable(FCenterForm, True, True, True);
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
  const AId, ACaption: string; AControl: TControl): TLedPaneForm;
begin
  Result := TLedPaneForm.CreatePane(Self, AId, ACaption, AEdge, AControl);
  FPanes.Add(Result);
  DockMaster.MakeDockable(Result, False, True, True);
end;

function TLedDockHost.PaneById(const AId: string): TLedPaneForm;
var
  i: Integer;
begin
  for i := 0 to FPanes.Count - 1 do
    if SameText(TLedPaneForm(FPanes[i]).PaneId, AId) then
      Exit(TLedPaneForm(FPanes[i]));
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
end;

end.
