{ led - a light editor.  The document model.

  A TLedDocument is the unit of "an open file".  It is not a widget and not a
  buffer: it owns a hidden master TSynEdit whose TSynEditStringList holds the
  text, the undo list and the marks, and every visible view shares that buffer
  through TCustomSynEdit.ShareTextBufferFrom.

  The consequences worth knowing:
    * text, undo/redo, modified state and bookmarks are shared across views;
    * caret, selection, scroll position and fold state stay per view;
    * a document can exist with no views at all, which find-in-files replace
      and session preload both need;
    * moving a tab between split notebooks is a reparent, not buffer surgery. }
unit Led.UI.Document;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, SynEdit, SynEditTypes, Led.Core.Types, Led.Core.FileIO,
  Led.UI.Edit;

type
  TLedDocument = class;

  TLedDocumentEvent = procedure(ADoc: TLedDocument) of object;

  TLedDocument = class(TComponent)
  private
    FMaster: TSynEdit;          // buffer owner; never parented, never shown
    FViews: TFPList;            // of TLedEdit
    FFileName: string;
    FInfo: TLedTextInfo;
    FUntitledNo: Integer;
    FOnChanged: TLedDocumentEvent;
    function GetModified: Boolean;
    function GetView(AIndex: Integer): TLedEdit;
    function GetViewCount: Integer;
    procedure MasterStatusChange(Sender: TObject; AChanges: TSynStatusChanges);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function CreateView(AOwner: TComponent): TLedEdit;
    procedure RemoveView(AView: TLedEdit);

    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
    procedure Save;

    function DisplayName: string;
    function IsUntitled: Boolean;

    property FileName: string read FFileName;
    property Info: TLedTextInfo read FInfo;
    property Modified: Boolean read GetModified;
    property Master: TSynEdit read FMaster;
    property Views[AIndex: Integer]: TLedEdit read GetView;
    property ViewCount: Integer read GetViewCount;
    property UntitledNo: Integer read FUntitledNo write FUntitledNo;
    property OnChanged: TLedDocumentEvent read FOnChanged write FOnChanged;
  end;

  { Owns every open document.  In phase 1 this grows the recent-file list,
    session handling and the file watcher; for now it is just the collection
    plus untitled-numbering. }
  TLedDocuments = class(TComponent)
  private
    FItems: TObjectList;        // owns the documents
    FNextUntitled: Integer;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TLedDocument;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function NewDocument: TLedDocument;
    function OpenFile(const AFileName: string): TLedDocument;
    function FindByFileName(const AFileName: string): TLedDocument;
    procedure CloseDocument(ADoc: TLedDocument);

    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TLedDocument read GetItem; default;
  end;

implementation

{ TLedDocument }

constructor TLedDocument.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FViews := TFPList.Create;

  FMaster := TSynEdit.Create(Self);
  FMaster.Name := '';
  FMaster.Visible := False;
  FMaster.Parent := nil;
  FMaster.OnStatusChange := @MasterStatusChange;

  FInfo.Encoding := 'utf8';
  FInfo.LineEnd := LedNativeLineEnd;
  FInfo.TrailingEOL := True;
end;

destructor TLedDocument.Destroy;
begin
  FViews.Free;
  inherited Destroy;
end;

function TLedDocument.GetModified: Boolean;
begin
  Result := FMaster.Modified;
end;

function TLedDocument.GetView(AIndex: Integer): TLedEdit;
begin
  Result := TLedEdit(FViews[AIndex]);
end;

function TLedDocument.GetViewCount: Integer;
begin
  Result := FViews.Count;
end;

procedure TLedDocument.MasterStatusChange(Sender: TObject;
  AChanges: TSynStatusChanges);
begin
  if (scModified in AChanges) and Assigned(FOnChanged) then
    FOnChanged(Self);
end;

function TLedDocument.CreateView(AOwner: TComponent): TLedEdit;
begin
  Result := TLedEdit.Create(AOwner);
  Result.Document := Self;
  { The shared buffer carries text, undo and marks.  Everything the view owns
    itself -- caret, selection, scroll, folds -- stays independent. }
  Result.ShareTextBufferFrom(FMaster);
  FViews.Add(Result);
end;

procedure TLedDocument.RemoveView(AView: TLedEdit);
begin
  FViews.Remove(AView);
end;

procedure TLedDocument.LoadFromFile(const AFileName: string);
var
  Text: string;
begin
  LedLoadTextFile(AFileName, Text, FInfo);
  FMaster.BeginUpdate;
  try
    FMaster.Lines.Text := Text;
    FMaster.ClearUndo;
    FMaster.Modified := False;
  finally
    FMaster.EndUpdate;
  end;
  FFileName := AFileName;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TLedDocument.SaveToFile(const AFileName: string);
begin
  LedSaveTextFile(AFileName, FMaster.Lines.Text, FInfo);
  FFileName := AFileName;
  FMaster.Modified := False;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TLedDocument.Save;
begin
  if IsUntitled then
    raise Exception.Create('Document has no file name');
  SaveToFile(FFileName);
end;

function TLedDocument.IsUntitled: Boolean;
begin
  Result := FFileName = '';
end;

function TLedDocument.DisplayName: string;
begin
  if IsUntitled then
    Result := Format('Untitled %d', [FUntitledNo])
  else
    Result := ExtractFileName(FFileName);
end;

{ TLedDocuments }

constructor TLedDocuments.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TObjectList.Create(True);
  FNextUntitled := 1;
end;

destructor TLedDocuments.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TLedDocuments.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TLedDocuments.GetItem(AIndex: Integer): TLedDocument;
begin
  Result := TLedDocument(FItems[AIndex]);
end;

function TLedDocuments.NewDocument: TLedDocument;
begin
  Result := TLedDocument.Create(nil);
  Result.UntitledNo := FNextUntitled;
  Inc(FNextUntitled);
  FItems.Add(Result);
end;

function TLedDocuments.OpenFile(const AFileName: string): TLedDocument;
begin
  Result := FindByFileName(AFileName);
  if Result <> nil then
    Exit;
  Result := TLedDocument.Create(nil);
  try
    Result.LoadFromFile(AFileName);
  except
    Result.Free;
    raise;
  end;
  FItems.Add(Result);
end;

function TLedDocuments.FindByFileName(const AFileName: string): TLedDocument;
var
  i: Integer;
  Wanted: string;
begin
  Wanted := ExpandFileName(AFileName);
  for i := 0 to FItems.Count - 1 do
    if (not Items[i].IsUntitled) and
       (ExpandFileName(Items[i].FileName) = Wanted) then
      Exit(Items[i]);
  Result := nil;
end;

procedure TLedDocuments.CloseDocument(ADoc: TLedDocument);
begin
  FItems.Remove(ADoc);   // owns the list, so this frees it
end;

end.
