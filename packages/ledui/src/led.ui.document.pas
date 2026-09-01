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
  Classes, SysUtils, Contnrs, SynEdit, SynEditTypes, SynEditMiscClasses,
  SynEditHighlighter,
  Led.Core.Types, Led.Core.FileIO, Led.Core.Encodings, Led.Core.Config,
  Led.Core.Modeline, Led.Core.Prefs, Led.Core.Filters,
  Led.Syn.Languages, Led.Syn.Theme,
  Led.Syn.Factory, Led.UI.Edit, Led.UI.Dpi;

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
    FConfig: TLedDocConfig;
    FDiskAge: LongInt;          // mtime as of the last load or save
    FDiskSize: Int64;
    FOnChanged: TLedDocumentEvent;
    function GetModified: Boolean;
    function GetView(AIndex: Integer): TLedEdit;
    function GetViewCount: Integer;
    procedure MasterStatusChange(Sender: TObject; AChanges: TSynStatusChanges);
    procedure ConfigChanged(Sender: TObject; AId: Integer);
    procedure NoteDiskState;
    procedure ApplyConfigToView(AView: TLedEdit);
    procedure ReadModelines;
    procedure DetectLanguage;
    procedure ApplyLanguage;
    function PreparedText: string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function CreateView(AOwner: TComponent): TLedEdit;
    procedure RemoveView(AView: TLedEdit);
    procedure ApplyConfigToViews;

    { AForcedEncoding empty means "work it out": BOM, then the encoding this
      document last used, then the user's candidate list. }
    procedure LoadFromFile(const AFileName: string;
      const AForcedEncoding: string = '');
    procedure Reload(const AForcedEncoding: string = '');
    procedure SaveToFile(const AFileName: string);
    procedure Save;

    { True when the file changed underneath us since the last load or save. }
    function ChangedOnDisk: Boolean;
    function DeletedFromDisk: Boolean;

    procedure SetEncoding(const AEncoding: string);
    procedure SetLineEnd(ALineEnd: TLedLineEnd);
    { An explicit choice from the Document menu; overrides detection. }
    procedure SetLanguage(const ALangId: string);
    function LangInfo: TLedLangInfo;

    function DisplayName: string;
    function IsUntitled: Boolean;

    property FileName: string read FFileName;
    property Info: TLedTextInfo read FInfo;
    property Config: TLedDocConfig read FConfig;
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
    function OpenFile(const AFileName: string;
      const AForcedEncoding: string = ''): TLedDocument;
    function FindByFileName(const AFileName: string): TLedDocument;
    procedure CloseDocument(ADoc: TLedDocument);

    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TLedDocument read GetItem; default;
  end;

{ The user's preferences expressed as a config, and the parent of every
  document's config.  Rebuilt whenever preferences change. }
function LedUserConfig: TLedDocConfig;
procedure LedReloadUserConfig;

{ The theme named by Editor/color_scheme, or nil when it is not installed. }
function LedCurrentTheme: TLedTheme;
procedure LedSetCurrentTheme(const AId: string);

{ The filename-glob rules, loaded from preferences on first use. }
function LedFilterSettings: TLedFilterSettings;

implementation

var
  FUserConfig: TLedDocConfig = nil;
  FTheme: TLedTheme = nil;
  FThemeResolved: Boolean = False;

function LedFilterSettings: TLedFilterSettings;
begin
  { Kept as a name of its own because the call sites read better, but the
    settings themselves belong to Led.Core.Filters, so the preferences page
    can edit them without depending on the document layer. }
  Result := LedFilters;
end;

function LedCurrentTheme: TLedTheme;
begin
  if not FThemeResolved then
  begin
    FTheme := LedThemes.FindById(
      LedPrefs.GetStr(LedPrefColorScheme, 'medit'));
    FThemeResolved := True;
  end;
  Result := FTheme;
end;

procedure LedSetCurrentTheme(const AId: string);
begin
  FTheme := LedThemes.FindById(AId);
  FThemeResolved := True;
  LedPrefs.SetStr(LedPrefColorScheme, AId);
  LedRetheme(FTheme);
end;

function LedUserConfig: TLedDocConfig;
begin
  if FUserConfig = nil then
  begin
    FUserConfig := TLedDocConfig.Create;
    LedPrefs.ApplyToConfig(FUserConfig);
  end;
  Result := FUserConfig;
end;

procedure LedReloadUserConfig;
begin
  LedUserConfig.UnsetBySource(lcsUser);
  LedPrefs.ApplyToConfig(FUserConfig);
end;

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

  FConfig := TLedDocConfig.Create(LedUserConfig);
  FConfig.OnChanged := @ConfigChanged;

  FInfo := LedDefaultTextInfo;

  { A freshly created TSynEdit's string list holds *no* lines, not one empty
    one, so a new untitled document had no line 1 for the gutter to number --
    which is why it opened with a blank gutter where medit shows "1".  The
    caret still reported 1:1, because CaretX and CaretY are 1-based whether
    or not a line exists, so the status bar looked right while the gutter did
    not.

    Giving the buffer its empty first line here covers every document: a file
    load replaces the contents wholesale, so this only ever shows through on
    the untitled case it is meant for. }
  if FMaster.Lines.Count = 0 then
    FMaster.Lines.Add('');
  FMaster.Modified := False;
end;

destructor TLedDocument.Destroy;
begin
  FConfig.Free;
  FViews.Free;
  inherited Destroy;
end;

procedure TLedDocument.ConfigChanged(Sender: TObject; AId: Integer);
begin
  ApplyConfigToViews;
end;

procedure TLedDocument.ApplyConfigToView(AView: TLedEdit);
var
  Wrap, FontName: string;
  FontSize: Integer;
begin
  { Editor/font existed as a preference, appeared in the Preferences dialog,
    and was read by nothing at all -- so choosing a font there did nothing
    and every view kept the hard-coded default.  It is a global preference
    rather than per-document, but this is the one place every view passes
    through, and PrefsApplied routes here, so a change takes effect at once.

    A consequence worth knowing: Ctrl+wheel zoom writes Font.Size directly
    and is deliberately not persisted, so any later config change resets it.
    medit's zoom is temporary in the same way. }
  LedParseFontSpec(LedPrefs.GetStr(LedPrefFont, ''), FontName, FontSize);
  AView.Font.Name := FontName;
  AView.Font.Size := FontSize;

  AView.TabWidth := FConfig.GetInt(LedSetTabWidth);
  AView.BlockIndent := FConfig.GetInt(LedSetIndentWidth);

  if FConfig.GetBool(LedSetIndentUseTabs) then
    AView.Options := AView.Options - [eoTabsToSpaces]
  else
    AView.Options := AView.Options + [eoTabsToSpaces];

  AView.Gutter.LineNumberPart.Visible := FConfig.GetBool(LedSetShowLineNumbers);
  LedApplyThemeToEditor(LedCurrentTheme, AView);

  { The block guides are a markup rather than an editor property, so the theme
    applier cannot reach them: it lives in ledsyn, and the markup hangs off a
    control in ledui.  It supplies the colour, this applies it. }
  AView.GuideColour :=
    LedThemeGuideColour(LedCurrentTheme, AView.Font.Color, AView.Color);

  Wrap := LowerCase(FConfig.GetStr(LedSetWrapMode));
  AView.WrapEnabled := (Wrap <> '') and (Wrap <> 'none');
end;

procedure TLedDocument.ApplyConfigToViews;
var
  i: Integer;
begin
  for i := 0 to FViews.Count - 1 do
    ApplyConfigToView(TLedEdit(FViews[i]));
end;

function TLedDocument.LangInfo: TLedLangInfo;
begin
  Result := LedLanguages.FindById(FConfig.GetStr(LedSetLang));
end;

{ Detection is recorded at lcsAuto, the most specific source, because a
  modeline saying "mode: python" has already been applied at lcsFile and a
  guess from the filename should not overrule it. }
procedure TLedDocument.DetectLanguage;
var
  Lang: TLedLangInfo;
  FirstLine: string;
begin
  if FConfig.HasValue(LedSetLang) and
     (FConfig.SourceOf(LedSetLang) <= lcsFile) then
  begin
    { A modeline already named one; honour it if it exists. }
    if LedLanguages.FindById(FConfig.GetStr(LedSetLang)) <> nil then Exit;
  end;

  FirstLine := '';
  if FMaster.Lines.Count > 0 then FirstLine := FMaster.Lines[0];
  Lang := LedLanguages.FindForFile(FFileName, FirstLine);
  if Lang <> nil then
    FConfig.SetStr(LedSetLang, Lang.Id, lcsAuto);
end;

procedure TLedDocument.ApplyLanguage;
var
  HL: TSynCustomHighlighter;
  i: Integer;
begin
  HL := LedHighlighterFor(FConfig.GetStr(LedSetLang));
  if HL <> nil then
    LedApplyThemeToHighlighter(LedCurrentTheme, HL);
  { The highlighter is a property of each editor, not of the shared buffer:
    setting it on the master alone leaves every visible view unhighlighted. }
  FMaster.Highlighter := HL;
  for i := 0 to FViews.Count - 1 do
  begin
    TLedEdit(FViews[i]).Highlighter := HL;
    { The guides read the highlighter's fold levels as they paint, so there is
      nothing to tell them; a repaint is enough. }
    TLedEdit(FViews[i]).Invalidate;
  end;
end;

procedure TLedDocument.SetLanguage(const ALangId: string);
begin
  FConfig.SetStr(LedSetLang, ALangId, lcsAuto);
  ApplyLanguage;
  if Assigned(FOnChanged) then FOnChanged(Self);
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
  ApplyConfigToView(Result);
  { A view created after the language was decided -- a split, or a session
    restore -- must pick the highlighter up too. }
  Result.Highlighter := FMaster.Highlighter;
end;

procedure TLedDocument.RemoveView(AView: TLedEdit);
begin
  FViews.Remove(AView);
end;

procedure TLedDocument.NoteDiskState;
begin
  FDiskAge := FileAge(FFileName);
  FDiskSize := 0;
  if FileExists(FFileName) then
    with TFileStream.Create(FFileName, fmOpenRead or fmShareDenyNone) do
      try
        FDiskSize := Size;
      finally
        Free;
      end;
end;

function TLedDocument.ChangedOnDisk: Boolean;
var
  Age: LongInt;
  Sz: Int64;
begin
  Result := False;
  if IsUntitled or not FileExists(FFileName) then Exit;
  Age := FileAge(FFileName);
  Sz := 0;
  try
    with TFileStream.Create(FFileName, fmOpenRead or fmShareDenyNone) do
      try
        Sz := Size;
      finally
        Free;
      end;
  except
    Exit;
  end;
  Result := (Age <> FDiskAge) or (Sz <> FDiskSize);
end;

function TLedDocument.DeletedFromDisk: Boolean;
begin
  Result := (not IsUntitled) and (not FileExists(FFileName));
end;

{ Modelines are read after the text is in the buffer, at source lcsFile, so
  they beat the user's preferences but still lose to a filename-glob rule. }
procedure TLedDocument.ReadModelines;
var
  L: TStringList;
  Count: Integer;
begin
  L := TStringList.Create;
  try
    if FMaster.Lines.Count > 0 then L.Add(FMaster.Lines[0]);
    if FMaster.Lines.Count > 1 then L.Add(FMaster.Lines[1]);
    Count := FMaster.Lines.Count;
    if Count > 2 then
    begin
      { LedApplyModelines reads index 0, 1 and the last; give it a list whose
        last entry really is the document's last line. }
      L.Add('');
      L[2] := FMaster.Lines[Count - 1];
    end;
    LedApplyModelines(L, FConfig);
  finally
    L.Free;
  end;
end;

procedure TLedDocument.LoadFromFile(const AFileName: string;
  const AForcedEncoding: string);
var
  Text, Cached: string;
  Encodings: TStringList;
begin
  Encodings := TStringList.Create;
  try
    LedParseEncodingList(
      LedPrefs.GetStr(LedPrefEncodings, LedDefaultEncodingList), Encodings);
    { A document that already knows its own encoding keeps it across a
      reload, so a file does not change its mind between openings. }
    Cached := FInfo.Encoding;
    if FFileName <> AFileName then Cached := '';
    LedLoadTextFile(AFileName, AForcedEncoding, Cached, Encodings, Text, FInfo);
  finally
    Encodings.Free;
  end;

  FMaster.BeginUpdate;
  try
    FMaster.Lines.Text := Text;
    FMaster.ClearUndo;
    FMaster.Modified := False;
  finally
    FMaster.EndUpdate;
  end;

  FFileName := AFileName;
  NoteDiskState;

  { Every derived layer is rebuilt from scratch, in precedence order, so that
    reloading or saving under a new name cannot leave a stale rule behind. }
  FConfig.UnsetBySource(lcsFile);
  FConfig.UnsetBySource(lcsFilename);
  FConfig.UnsetBySource(lcsAuto);
  FConfig.SetStr(LedSetEncoding, FInfo.Encoding, lcsAuto);
  FConfig.SetStr(LedSetLineEnd, LedLineEndName(FInfo.LineEnd), lcsAuto);
  ReadModelines;
  DetectLanguage;
  { Glob rules are applied after detection because a rule may select on the
    language, and they outrank the modeline read just above. }
  LedFilterSettings.ApplyTo(FConfig, FFileName, FConfig.GetStr(LedSetLang));
  ApplyLanguage;
  ApplyConfigToViews;

  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TLedDocument.Reload(const AForcedEncoding: string);
var
  Caret: TPoint;
  Top: Integer;
begin
  if IsUntitled then Exit;
  Caret := Point(1, 1);
  Top := 1;
  if FViews.Count > 0 then
  begin
    Caret := TLedEdit(FViews[0]).CaretXY;
    Top := TLedEdit(FViews[0]).TopLine;
  end;

  LoadFromFile(FFileName, AForcedEncoding);

  { Put the reader back where they were, as far as the new content allows. }
  if FViews.Count > 0 then
  begin
    if Caret.Y > FMaster.Lines.Count then Caret.Y := FMaster.Lines.Count;
    if Caret.Y < 1 then Caret.Y := 1;
    TLedEdit(FViews[0]).CaretXY := Caret;
    TLedEdit(FViews[0]).TopLine := Top;
  end;
end;

{ Applies the on-save text policies -- strip trailing whitespace, ensure a
  final newline -- without disturbing the buffer the user is looking at. }
function TLedDocument.PreparedText: string;
var
  L: TStringList;
  i: Integer;
begin
  Result := FMaster.Lines.Text;

  if FConfig.GetBool(LedSetStripTrailing) then
  begin
    L := TStringList.Create;
    try
      L.TextLineBreakStyle := tlbsLF;
      L.Text := Result;
      for i := 0 to L.Count - 1 do
        L[i] := TrimRight(L[i]);
      Result := L.Text;
    finally
      L.Free;
    end;
  end;

  if FConfig.GetBool(LedSetAddNewline) then
  begin
    if (Result <> '') and (Result[Length(Result)] <> #10) then
      Result := Result + #10;
  end
  else if not FInfo.TrailingEOL then
  begin
    { TStrings.Text always terminates the last line; drop it again when the
      file did not have one and the user has not asked for one. }
    while (Result <> '') and (Result[Length(Result)] in [#10, #13]) do
      SetLength(Result, Length(Result) - 1);
  end;
end;

procedure TLedDocument.SaveToFile(const AFileName: string);
var
  Renamed: Boolean;
begin
  Renamed := not SameText(AFileName, FFileName);
  LedSaveTextFile(AFileName, PreparedText, FInfo,
    LedPrefs.GetBool(LedPrefMakeBackups, False));
  FFileName := AFileName;
  FMaster.Modified := False;
  NoteDiskState;

  { Saving under a new name can change everything the name decides: the
    language, and the filename-glob rules layered on top of it.  Without
    this, "new file, type some C, save as main.c" stays plain text. }
  if Renamed then
  begin
    FConfig.UnsetBySource(lcsFilename);
    FConfig.UnsetBySource(lcsAuto);
    FConfig.SetStr(LedSetEncoding, FInfo.Encoding, lcsAuto);
    FConfig.SetStr(LedSetLineEnd, LedLineEndName(FInfo.LineEnd), lcsAuto);
    DetectLanguage;
    LedFilterSettings.ApplyTo(FConfig, FFileName, FConfig.GetStr(LedSetLang));
    ApplyLanguage;
    ApplyConfigToViews;
  end;

  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TLedDocument.SetEncoding(const AEncoding: string);
var
  Enc: string;
begin
  Enc := LedNormaliseEncoding(AEncoding);
  if Enc = '' then Exit;
  FInfo.Encoding := Enc;
  { Changing the encoding is a change to the file, even though the buffer is
    untouched, so the user is offered a save. }
  FMaster.Modified := True;
  FConfig.SetStr(LedSetEncoding, Enc, lcsAuto);
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TLedDocument.SetLineEnd(ALineEnd: TLedLineEnd);
begin
  if FInfo.LineEnd = ALineEnd then Exit;
  FInfo.LineEnd := ALineEnd;
  FMaster.Modified := True;
  FConfig.SetStr(LedSetLineEnd, LedLineEndName(ALineEnd), lcsAuto);
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

function TLedDocuments.OpenFile(const AFileName: string;
  const AForcedEncoding: string): TLedDocument;
begin
  Result := FindByFileName(AFileName);
  if Result <> nil then
    Exit;
  Result := TLedDocument.Create(nil);
  try
    Result.LoadFromFile(AFileName, AForcedEncoding);
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

finalization
  FUserConfig.Free;

end.
