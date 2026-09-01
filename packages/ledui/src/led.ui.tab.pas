{ led - a light editor.  One notebook tab: a document and its views.

  The tab holds a tree of TPairSplitter, so splitting is recursive: splitting
  the focused view wraps that view in a new splitter and puts a fresh view of
  the same document beside it.  Up to four views, matching medit. }
unit Led.UI.Tab;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, PairSplitter, ComCtrls,
  Led.UI.Document, Led.UI.Edit;

const
  LedMaxViewsPerTab = 4;

type
  TLedTab = class(TPanel)
  private
    FDocument: TLedDocument;
    FViews: TFPList;            // of TLedEdit, in creation order
    FActiveView: TLedEdit;
    FSheet: TTabSheet;          // the page this tab lives on
    procedure ViewEnter(Sender: TObject);
    function AddView(AParent: TWinControl): TLedEdit;
    function GetViewCount: Integer;
    function GetView(AIndex: Integer): TLedEdit;
  public
    constructor CreateForDocument(AOwner: TComponent; ADoc: TLedDocument);
    destructor Destroy; override;

    { AVertical selects a top/bottom arrangement; otherwise the views sit
      side by side. }
    procedure SplitView(AVertical: Boolean);
    procedure Unsplit;
    procedure CycleViews;
    function CanSplit: Boolean;

    property Document: TLedDocument read FDocument;
    property ActiveView: TLedEdit read FActiveView;
    property Views[AIndex: Integer]: TLedEdit read GetView;
    property ViewCount: Integer read GetViewCount;
    property Sheet: TTabSheet read FSheet write FSheet;
  end;

implementation

constructor TLedTab.CreateForDocument(AOwner: TComponent; ADoc: TLedDocument);
begin
  inherited Create(AOwner);
  FDocument := ADoc;
  FViews := TFPList.Create;

  BevelOuter := bvNone;
  Caption := '';
  Align := alClient;

  AddView(Self);
end;

destructor TLedTab.Destroy;
var
  i: Integer;
begin
  { Detach the views from the document before they are destroyed with us, so
    the document's view list never holds dangling pointers. }
  if FDocument <> nil then
    for i := 0 to FViews.Count - 1 do
      FDocument.RemoveView(TLedEdit(FViews[i]));
  FViews.Free;
  inherited Destroy;
end;

function TLedTab.GetViewCount: Integer;
begin
  Result := FViews.Count;
end;

function TLedTab.GetView(AIndex: Integer): TLedEdit;
begin
  Result := TLedEdit(FViews[AIndex]);
end;

function TLedTab.AddView(AParent: TWinControl): TLedEdit;
begin
  Result := FDocument.CreateView(Self);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.OnEnter := @ViewEnter;
  FViews.Add(Result);
  if FActiveView = nil then
    FActiveView := Result;
end;

procedure TLedTab.ViewEnter(Sender: TObject);
begin
  FActiveView := TLedEdit(Sender);
end;

function TLedTab.CanSplit: Boolean;
begin
  Result := FViews.Count < LedMaxViewsPerTab;
end;

procedure TLedTab.SplitView(AVertical: Boolean);
var
  Old: TLedEdit;
  Host: TWinControl;
  Splitter: TPairSplitter;
  NewView: TLedEdit;
begin
  if not CanSplit then Exit;
  Old := FActiveView;
  if Old = nil then Exit;

  Host := Old.Parent;

  Splitter := TPairSplitter.Create(Self);
  Splitter.Parent := Host;
  Splitter.Align := alClient;
  { pstHorizontal moves the divider horizontally, i.e. the views sit side by
    side; pstVertical stacks them.  Named here by the arrangement, not by the
    divider, because that is what the menu item promises. }
  if AVertical then
    Splitter.SplitterType := pstVertical
  else
    Splitter.SplitterType := pstHorizontal;

  Old.Parent := Splitter.Sides[0];
  Old.Align := alClient;

  NewView := AddView(Splitter.Sides[1]);
  { Start the new view where the old one is looking. }
  NewView.TopLine := Old.TopLine;
  NewView.CaretXY := Old.CaretXY;
end;

procedure TLedTab.Unsplit;
var
  Doomed: TLedEdit;
  Side: TWinControl;
  Splitter: TPairSplitter;
  Keeper: TControl;
  Host: TWinControl;
begin
  if FViews.Count < 2 then Exit;
  Doomed := FActiveView;
  if (Doomed = nil) or not (Doomed.Parent is TPairSplitterSide) then Exit;

  Side := Doomed.Parent;
  Splitter := TPairSplitter(Side.Parent);
  Host := Splitter.Parent;

  { Whatever lives on the other side takes the splitter's place. }
  if Splitter.Sides[0] = Side then
    Side := Splitter.Sides[1]
  else
    Side := Splitter.Sides[0];
  if Side.ControlCount = 0 then Exit;
  Keeper := Side.Controls[0];

  FViews.Remove(Doomed);
  FDocument.RemoveView(Doomed);
  FActiveView := nil;
  Doomed.Free;

  Keeper.Parent := Host;
  Keeper.Align := alClient;
  Splitter.Free;

  if FViews.Count > 0 then
    FActiveView := TLedEdit(FViews[0]);
  if (FActiveView <> nil) and FActiveView.CanFocus then
    FActiveView.SetFocus;
end;

procedure TLedTab.CycleViews;
var
  i: Integer;
begin
  if FViews.Count < 2 then Exit;
  i := FViews.IndexOf(FActiveView);
  i := (i + 1) mod FViews.Count;
  if TLedEdit(FViews[i]).CanFocus then
    TLedEdit(FViews[i]).SetFocus;
end;

end.
