{ led - a light editor.  Main window.

  Menus, the toolbar and the action list live in led.ui.main.lfm and are meant
  to be edited in the Lazarus form designer.  This unit holds only behaviour:
  action handlers, action enabling, and the wiring between the document model,
  the centre notebook and the dock host. }
unit Led.UI.Main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Dialogs, Menus, ActnList, ComCtrls,
  ExtCtrls, SynEdit, SynEditTypes,
  Led.Core.Types, Led.UI.Dock, Led.UI.Document, Led.UI.Tab, Led.UI.Edit;

type
  TLedMainForm = class(TForm)
    ActionList1: TActionList;
    actNew: TAction;
    actOpen: TAction;
    actSave: TAction;
    actSaveAs: TAction;
    actCloseTab: TAction;
    actQuit: TAction;
    actSplitSideBySide: TAction;
    actSplitStacked: TAction;
    actUnsplit: TAction;
    actCycleViews: TAction;
    actToggleLeftPane: TAction;
    actToggleBottomPane: TAction;
    MainMenu1: TMainMenu;
    mnuFile: TMenuItem;
    miNew: TMenuItem;
    miOpen: TMenuItem;
    miSep1: TMenuItem;
    miSave: TMenuItem;
    miSaveAs: TMenuItem;
    miSep2: TMenuItem;
    miCloseTab: TMenuItem;
    miQuit: TMenuItem;
    mnuView: TMenuItem;
    miSplitSideBySide: TMenuItem;
    miSplitStacked: TMenuItem;
    miUnsplit: TMenuItem;
    miCycleViews: TMenuItem;
    miSep3: TMenuItem;
    miToggleLeftPane: TMenuItem;
    miToggleBottomPane: TMenuItem;
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    StatusBar1: TStatusBar;
    procedure ActionList1Update(AAction: TBasicAction; var Handled: Boolean);
    procedure actCloseTabExecute(Sender: TObject);
    procedure actCycleViewsExecute(Sender: TObject);
    procedure actNewExecute(Sender: TObject);
    procedure actOpenExecute(Sender: TObject);
    procedure actQuitExecute(Sender: TObject);
    procedure actSaveAsExecute(Sender: TObject);
    procedure actSaveExecute(Sender: TObject);
    procedure actSplitSideBySideExecute(Sender: TObject);
    procedure actSplitStackedExecute(Sender: TObject);
    procedure actToggleBottomPaneExecute(Sender: TObject);
    procedure actToggleLeftPaneExecute(Sender: TObject);
    procedure actUnsplitExecute(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
  private
    FDocs: TLedDocuments;
    FDock: TLedDockHost;
    FBook: TPageControl;
    procedure BookChange(Sender: TObject);
    procedure DocChanged(ADoc: TLedDocument);
    procedure RefreshTabCaption(ATab: TLedTab);
    procedure UpdateStatusBar;
    procedure ViewStatusChange(Sender: TObject; AChanges: TSynStatusChanges);
    function ConfirmClose(ADoc: TLedDocument): Boolean;
  public
    procedure OpenFiles(AFiles: TStrings);

    { Public so the --self-test harness, and later the scripting API, can
      drive the window the same way a user would. }
    function ActiveTab: TLedTab;
    function ActiveView: TLedEdit;
    function AddTab(ADoc: TLedDocument): TLedTab;
    property Documents: TLedDocuments read FDocs;
    property Dock: TLedDockHost read FDock;
    property Notebook: TPageControl read FBook;
  end;

var
  LedMainForm: TLedMainForm;

implementation

{$R *.lfm}

procedure TLedMainForm.FormCreate(Sender: TObject);
begin
  FDocs := TLedDocuments.Create(Self);

  FDock := TLedDockHost.Create(Self);
  FDock.Parent := Self;
  FDock.Align := alClient;

  FBook := TPageControl.Create(Self);
  FBook.Parent := FDock.Center;
  FBook.Align := alClient;
  FBook.OnChange := @BookChange;

  { Phase 0 placeholders so the dock edges can be exercised; real panes arrive
    in phases 3 and 5. }
  FDock.AddPane(ledLeft, 'files', 'Files', nil);
  FDock.AddPane(ledBottom, 'output', 'Output', nil);
  FDock.EdgeVisible[ledLeft] := False;
  FDock.EdgeVisible[ledBottom] := False;

  actNewExecute(nil);
end;

function TLedMainForm.ActiveTab: TLedTab;
var
  i: Integer;
begin
  Result := nil;
  if (FBook = nil) or (FBook.ActivePage = nil) then Exit;
  for i := 0 to FBook.ActivePage.ControlCount - 1 do
    if FBook.ActivePage.Controls[i] is TLedTab then
      Exit(TLedTab(FBook.ActivePage.Controls[i]));
end;

function TLedMainForm.ActiveView: TLedEdit;
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab = nil then
    Result := nil
  else
    Result := Tab.ActiveView;
end;

function TLedMainForm.AddTab(ADoc: TLedDocument): TLedTab;
var
  Sheet: TTabSheet;
begin
  Sheet := FBook.AddTabSheet;
  Result := TLedTab.CreateForDocument(Self, ADoc);
  Result.Parent := Sheet;
  Result.Sheet := Sheet;
  ADoc.OnChanged := @DocChanged;
  Result.ActiveView.OnStatusChange := @ViewStatusChange;
  RefreshTabCaption(Result);
  FBook.ActivePage := Sheet;
  if Result.ActiveView.CanFocus then
    Result.ActiveView.SetFocus;
  UpdateStatusBar;
end;

procedure TLedMainForm.RefreshTabCaption(ATab: TLedTab);
var
  S: string;
begin
  if (ATab = nil) or (ATab.Sheet = nil) then Exit;
  S := ATab.Document.DisplayName;
  if ATab.Document.Modified then
    S := '*' + S;
  ATab.Sheet.Caption := S;
end;

procedure TLedMainForm.DocChanged(ADoc: TLedDocument);
var
  i, j: Integer;
  Tab: TLedTab;
begin
  for i := 0 to FBook.PageCount - 1 do
    for j := 0 to FBook.Pages[i].ControlCount - 1 do
      if FBook.Pages[i].Controls[j] is TLedTab then
      begin
        Tab := TLedTab(FBook.Pages[i].Controls[j]);
        if Tab.Document = ADoc then
          RefreshTabCaption(Tab);
      end;
  UpdateStatusBar;
end;

procedure TLedMainForm.BookChange(Sender: TObject);
begin
  UpdateStatusBar;
end;

procedure TLedMainForm.ViewStatusChange(Sender: TObject;
  AChanges: TSynStatusChanges);
begin
  if AChanges * [scCaretX, scCaretY, scSelection, scModified] <> [] then
    UpdateStatusBar;
end;

procedure TLedMainForm.UpdateStatusBar;
var
  V: TLedEdit;
  D: TLedDocument;
begin
  V := ActiveView;
  if V = nil then
  begin
    StatusBar1.Panels[0].Text := '';
    StatusBar1.Panels[1].Text := '';
    StatusBar1.Panels[2].Text := '';
    StatusBar1.Panels[3].Text := '';
    Caption := 'led';
    Exit;
  end;

  D := TLedDocument(V.Document);
  StatusBar1.Panels[0].Text :=
    Format('Line %d  Col %d', [V.CaretY, V.CaretX]);
  StatusBar1.Panels[1].Text := D.Info.Encoding;
  StatusBar1.Panels[2].Text := LedLineEndName(D.Info.LineEnd);
  if V.InsertMode then
    StatusBar1.Panels[3].Text := 'INS'
  else
    StatusBar1.Panels[3].Text := 'OVR';

  if D.IsUntitled then
    Caption := Format('led - %s', [D.DisplayName])
  else
    Caption := Format('led - %s', [D.FileName]);
end;

procedure TLedMainForm.ActionList1Update(AAction: TBasicAction;
  var Handled: Boolean);
var
  Tab: TLedTab;
  HasDoc: Boolean;
begin
  Tab := ActiveTab;
  HasDoc := Tab <> nil;

  actSave.Enabled := HasDoc and (Tab.Document.Modified or Tab.Document.IsUntitled);
  actSaveAs.Enabled := HasDoc;
  actCloseTab.Enabled := HasDoc;
  actSplitSideBySide.Enabled := HasDoc and Tab.CanSplit;
  actSplitStacked.Enabled := HasDoc and Tab.CanSplit;
  actUnsplit.Enabled := HasDoc and (Tab.ViewCount > 1);
  actCycleViews.Enabled := HasDoc and (Tab.ViewCount > 1);
  actToggleLeftPane.Checked := FDock.EdgeVisible[ledLeft];
  actToggleBottomPane.Checked := FDock.EdgeVisible[ledBottom];

  Handled := True;
end;

procedure TLedMainForm.actNewExecute(Sender: TObject);
begin
  AddTab(FDocs.NewDocument);
end;

procedure TLedMainForm.actOpenExecute(Sender: TObject);
begin
  if OpenDialog1.Execute then
    OpenFiles(OpenDialog1.Files);
end;

procedure TLedMainForm.OpenFiles(AFiles: TStrings);
var
  i: Integer;
  Doc: TLedDocument;
begin
  for i := 0 to AFiles.Count - 1 do
  begin
    try
      Doc := FDocs.OpenFile(AFiles[i]);
    except
      on E: Exception do
      begin
        MessageDlg('led', Format('Could not open %s:'#10'%s',
          [AFiles[i], E.Message]), mtError, [mbOK], 0);
        Continue;
      end;
    end;
    if Doc.ViewCount = 0 then
      AddTab(Doc);
  end;
end;

procedure TLedMainForm.actSaveExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab = nil then Exit;
  if Tab.Document.IsUntitled then
    actSaveAsExecute(Sender)
  else
    Tab.Document.Save;
end;

procedure TLedMainForm.actSaveAsExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab = nil then Exit;
  if not Tab.Document.IsUntitled then
    SaveDialog1.FileName := Tab.Document.FileName;
  if SaveDialog1.Execute then
  begin
    Tab.Document.SaveToFile(SaveDialog1.FileName);
    RefreshTabCaption(Tab);
    UpdateStatusBar;
  end;
end;

function TLedMainForm.ConfirmClose(ADoc: TLedDocument): Boolean;
var
  Res: Integer;
begin
  if not ADoc.Modified then Exit(True);
  Res := MessageDlg('led',
    Format('Save changes to %s before closing?', [ADoc.DisplayName]),
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  case Res of
    mrYes:
      begin
        actSaveExecute(nil);
        Result := not ADoc.Modified;
      end;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

procedure TLedMainForm.actCloseTabExecute(Sender: TObject);
var
  Tab: TLedTab;
  Sheet: TTabSheet;
  Doc: TLedDocument;
begin
  Tab := ActiveTab;
  if Tab = nil then Exit;
  Doc := Tab.Document;
  if not ConfirmClose(Doc) then Exit;

  Sheet := Tab.Sheet;
  Tab.Free;          // detaches its views from the document
  Sheet.Free;
  if Doc.ViewCount = 0 then
    FDocs.CloseDocument(Doc);

  if FBook.PageCount = 0 then
    actNewExecute(nil)
  else
    UpdateStatusBar;
end;

procedure TLedMainForm.actSplitSideBySideExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab <> nil then Tab.SplitView(False);
end;

procedure TLedMainForm.actSplitStackedExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab <> nil then Tab.SplitView(True);
end;

procedure TLedMainForm.actUnsplitExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab <> nil then Tab.Unsplit;
end;

procedure TLedMainForm.actCycleViewsExecute(Sender: TObject);
var
  Tab: TLedTab;
begin
  Tab := ActiveTab;
  if Tab <> nil then Tab.CycleViews;
end;

procedure TLedMainForm.actToggleLeftPaneExecute(Sender: TObject);
begin
  FDock.ToggleEdge(ledLeft);
end;

procedure TLedMainForm.actToggleBottomPaneExecute(Sender: TObject);
begin
  FDock.ToggleEdge(ledBottom);
end;

procedure TLedMainForm.actQuitExecute(Sender: TObject);
begin
  Close;
end;

procedure TLedMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  i: Integer;
begin
  for i := 0 to FDocs.Count - 1 do
    if not ConfirmClose(FDocs[i]) then
    begin
      CanClose := False;
      Exit;
    end;
  CanClose := True;
end;

end.
