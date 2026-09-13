{ led - a lightweight editor.  The document model.

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
  Classes, SysUtils, Contnrs, Graphics, SynEdit, SynEditTypes,
  SynEditMiscClasses, SynEditHighlighter,
  Led.Core.Types, Led.Core.FileIO, Led.Core.Hex, Led.Core.Encodings,
  Led.Core.Config,
  Led.Core.Modeline, Led.Core.Prefs, Led.Core.Filters,
  Led.Syn.Languages, Led.Syn.Theme,
  Led.Syn.Factory, Led.UI.Edit, Led.UI.Dpi, Led.UI.SpellMarkup,
  Led.UI.LongLine;

type
  { One byte changed, so it can be changed back.  A hex edit never inserts or
    removes, so an undo record is a position and the value that was there --
    no ranges, no reflowing, and undoing in reverse order restores exactly
    the file that was loaded. }
  TLedHexUndo = record
    Offset: Integer;
    Value: Byte;
  end;

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
    FIsBinary: Boolean;         // shown as a hex dump rather than as text
    FForceText: Boolean;        // the user asked for the text editor anyway
    { The bytes themselves, when the document is a dump.  This is the file;
      the buffer the views show is a rendering of it, rebuilt a row at a time
      as bytes change. }
    FBytes: string;
    FHexUndo: array of TLedHexUndo;
    FHexUndoCount: Integer;
    FHexDirty: Boolean;
    FOnChanged: TLedDocumentEvent;
    function GetModified: Boolean;
    function GetView(AIndex: Integer): TLedEdit;
    function GetViewCount: Integer;
    procedure MasterStatusChange(Sender: TObject; AChanges: TSynStatusChanges);
    procedure ConfigChanged(Sender: TObject; AId: Integer);
    procedure NoteDiskState;
    procedure ApplyConfigToView(AView: TLedEdit);
    procedure RenderHexRow(AOffset: Integer);
    procedure HexKey(Sender: TObject; AOffset, ANibble: Integer;
      const AChar: string; var AHandled: Boolean);
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
    function SpellScopeForDocument: TLedSpellScope;

    { AForcedEncoding empty means "work it out": BOM, then the encoding this
      document last used, then the user's candidate list. }
    procedure LoadFromFile(const AFileName: string;
      const AForcedEncoding: string = '');
    { Reopens a file that was shown as hex in the ordinary text editor.  The
      detection is a heuristic -- a NUL early on -- and a heuristic needs a
      way to be overruled. }
    procedure OpenAsText;

    { Replaces the byte at AOffset and re-renders the row it is in.  The unit
      of editing in a dump: bytes are overwritten, never inserted, because the
      offsets down the left are part of what the reader is reading. }
    procedure SetHexByte(AOffset: Integer; AValue: Byte);
    { Puts back the last byte SetHexByte changed, and returns where it was so
      the caller can show it -- an undo you cannot see is hard to trust.  -1
      when there was nothing to undo.

      One keystroke, one record: a byte typed in the hex column takes two
      presses and undoes in two.  That is the rule everywhere else in the
      editor too -- undo takes back the last thing done, not the last thing
      finished. }
    function UndoHexByte: Integer;
    function CanUndoHex: Boolean;
    { The byte at AOffset, or -1 past the end. }
    function HexByte(AOffset: Integer): Integer;
    function HexSize: Integer;
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
    { True when the file was opened as a hex dump because it does not look
      like text.  The buffer then holds the dump, not the file, so it is
      read-only and Save refuses: writing the dump back would destroy the
      file it came from. }
    property IsBinary: Boolean read FIsBinary;
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

{ Every document open in this process, whichever window is showing it.
  medit's MooEditor is a singleton for the same reason: with a registry per
  window, opening a file that is already open in another window produced a
  second, independent document on the same path, and whichever was saved
  last silently discarded the other's work.  Neither copy could warn, because
  each was watching the disk against its own last-known timestamp. }
function LedDocuments: TLedDocuments;

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
  { Scaled on the way in, not on the way out: the preference keeps the size
    the user chose -- Preferences reads prefs.ini, not this font -- and only
    what is drawn is multiplied up to the display.  Ctrl+wheel zoom reads
    Font.Size back, so it now steps from the scaled value: a step is a
    smaller proportion of a bigger number, which is a finer zoom rather than
    a broken one, and LedMinFontSize..LedMaxFontSize still bracket it. }
  AView.Font.Size := LedScalePointSize(FontSize);
  { SynEdit's own constructor hard-codes fqNonAntialiased (SynDefaultFontQuality
    in synedit.pp) -- crisp-but-jagged was a deliberate default once, but it
    reads as a bug next to every other application on a modern display.

    Plain grayscale antialiasing, not ClearType: GDI's ClearType rendering is
    well documented as considerably more expensive than grayscale AA for a
    monospace font redrawn over and over.  A Windows scroll freeze reported
    around the same time as the pixelation turned out to be an unrelated
    infinite loop in the spell-checker's word scanner (see led.ui.spellmarkup
    .pas), not this -- but grayscale AA is still the cheaper, still-not-
    pixelated choice on its own merits, and ClearType's subpixel rendering
    is unlikely to be free on a control that repaints this often, so this
    stays the safer default regardless.  Ignored outright on every
    non-Windows widgetset (nothing in the GTK2 or Cocoa backends reads
    Font.Quality at all), so this only changes anything here. }
  AView.Font.Quality := fqAntialiased;

  { A dump's buffer is a rendering of bytes this document owns, so SynEdit's
    own editing must never touch it -- the rows would stop matching the file.
    The view stays read-only as far as SynEdit is concerned and routes keys
    to HexKey instead, which edits a byte and re-renders its row. }
  AView.ReadOnly := FIsBinary;
  AView.HexMode := FIsBinary;
  if FIsBinary then
    AView.OnHexKey := @HexKey
  else
    AView.OnHexKey := nil;

  AView.TabWidth := FConfig.GetInt(LedSetTabWidth);
  AView.BlockIndent := FConfig.GetInt(LedSetIndentWidth);

  if FConfig.GetBool(LedSetIndentUseTabs) then
    AView.Options := AView.Options - [eoTabsToSpaces]
  else
    AView.Options := AView.Options + [eoTabsToSpaces];

  AView.Gutter.LineNumberPart.Visible := FConfig.GetBool(LedSetShowLineNumbers);

  { How long a line has to be before only the first part of it is shown.
    medit's max_line_len, and 0 turns it off for anyone who would rather have
    the whole line and the cost that comes with it. }
  AView.LongLines.Limit :=
    LedPrefs.GetInt('Editor/max_line_len', LedDefaultLineLimit);

  AView.SetSpellScope(SpellScopeForDocument);
  LedApplyThemeToEditor(LedCurrentTheme, AView);

  { The block guides are a markup rather than an editor property, so the theme
    applier cannot reach them: it lives in ledsyn, and the markup hangs off a
    control in ledui.  It supplies the colour, this applies it. }
  AView.GuideColour :=
    LedThemeGuideColour(LedCurrentTheme, AView.Font.Color, AView.Color);

  { After the theme has been applied, because the column colours are mixed
    from the editor's own -- asking earlier would mix them from the last
    theme's. }
  if FIsBinary and (AView.HexMarkup <> nil) then
    AView.HexMarkup.SetColours(AView.Font.Color, AView.Color,
      AView.Gutter.LineNumberPart.MarkupInfo.Foreground,
      AView.LineHighlightColor.Background);

  Wrap := LowerCase(FConfig.GetStr(LedSetWrapMode));
  AView.WrapEnabled := (Wrap <> '') and (Wrap <> 'none');
end;

{ Languages whose files are prose rather than source.  Under the default
  "auto" these are checked end to end; everything else is checked in its
  comments and strings only.

  This is medit's documented behaviour rather than its implemented one:
  moospellcheck.cpp turns checking off for any file with a language at all,
  including Markdown and LaTeX, and its own comment says the
  comments-and-strings filter was never written.  led has that filter, so it
  can do what the preference page promises. }
const
  LedProseLanguages: array[0..5] of string =
    ('markdown', 'latex', 'rst', 't2t', 'bibtex', 'gtk-doc');

function TLedDocument.SpellScopeForDocument: TLedSpellScope;
var
  i: Integer;
  Id: string;
begin
  if not LedPrefs.GetBool('Editor/spell_enabled', True) then Exit(lssOff);

  Id := LowerCase(LedPrefs.GetStr('Editor/spell_scope', 'auto'));
  if Id = 'all' then Exit(lssAll);
  if Id = 'code' then Exit(lssCode);

  { auto: no language means plain text, which is prose. }
  if LangInfo = nil then Exit(lssAll);
  Id := LowerCase(LangInfo.Id);
  for i := Low(LedProseLanguages) to High(LedProseLanguages) do
    if Id = LedProseLanguages[i] then Exit(lssAll);
  Result := lssCode;
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
  { A dump's buffer is rewritten row by row rather than typed into, so
    FMaster.Modified says nothing about it -- the bytes are what changed. }
  if FIsBinary then Exit(FHexDirty);
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
  Text, Cached, Raw: string;
  Encodings: TStringList;
  Err: TLedFileError;
begin
  { The bytes first, because whether this is text at all is decided from
    them and a hex dump is made from them.  One read either way: the text
    path decodes what is already in hand rather than opening the file
    again. }
  Raw := LedReadRawFile(AFileName);
  FIsBinary := (not FForceText) and (AForcedEncoding = '') and
    LedLooksBinary(Raw);

  if FIsBinary then
  begin
    { No decoding, no encoding, no line-ending convention: the buffer holds a
      rendering of the file rather than the file, and saying otherwise would
      invite the save path to write it back. }
    FBytes := Raw;
    FHexUndoCount := 0;
    FHexDirty := False;
    Text := LedHexDump(Raw);
    FInfo := LedDefaultTextInfo;
    { Claim neither.  The buffer is a rendering of the bytes, so it has no
      encoding and no line-ending convention of its own, and recording the
      defaults would put a guess into the session file and onto the status
      bar as though it were known. }
    FInfo.Encoding := '';
    FInfo.LineEnd := leUnknown;
  end
  else
  begin
    FBytes := '';
    FHexUndoCount := 0;
    FHexDirty := False;
    Encodings := TStringList.Create;
    try
      LedParseEncodingList(
        LedPrefs.GetStr(LedPrefEncodings, LedDefaultEncodingList), Encodings);
      { A document that already knows its own encoding keeps it across a
        reload, so a file does not change its mind between openings. }
      Cached := FInfo.Encoding;
      if FFileName <> AFileName then Cached := '';
      { The same error LedLoadTextFile would have raised; only the reading is
        done differently, so "Reopen with encoding" still reports what went
        wrong with the encoding it was given. }
      Err := LedDecodeText(Raw, AForcedEncoding, Cached, Encodings, Text, FInfo);
      if Err <> lfeNone then
        raise ELedFileError.Create(Err, AFileName);
    finally
      Encodings.Free;
    end;
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
  { A dump has no modeline and no language: what it looks like is decided
    here, not by anything in the file. }
  if not FIsBinary then
  begin
    ReadModelines;
    DetectLanguage;
  end;
  { Glob rules are applied after detection because a rule may select on the
    language, and they outrank the modeline read just above. }
  LedFilterSettings.ApplyTo(FConfig, FFileName, FConfig.GetStr(LedSetLang));
  ApplyLanguage;
  ApplyConfigToViews;

  if Assigned(FOnChanged) then FOnChanged(Self);
end;

{ Re-renders just the row AOffset falls in.  A file of any size makes
  re-rendering the whole dump per keystroke the difference between typing and
  waiting, and a row is self-contained -- its offset and its sixteen bytes are
  all it needs. }
procedure TLedDocument.RenderHexRow(AOffset: Integer);
var
  Row: Integer;
begin
  Row := AOffset div LedHexBytesPerLine;
  if (Row < 0) or (Row >= FMaster.Lines.Count) then Exit;
  { Straight into the buffer rather than through an edit command: the views
    are read-only, and an undo of led's own is what SetHexByte keeps. }
  FMaster.Lines[Row] := LedHexDumpLine(FBytes, Row * LedHexBytesPerLine);
end;

function TLedDocument.HexSize: Integer;
begin
  Result := Length(FBytes);
end;

function TLedDocument.HexByte(AOffset: Integer): Integer;
begin
  if (AOffset < 0) or (AOffset >= Length(FBytes)) then Exit(-1);
  Result := Byte(FBytes[AOffset + 1]);
end;

procedure TLedDocument.SetHexByte(AOffset: Integer; AValue: Byte);
begin
  if not FIsBinary then Exit;
  if (AOffset < 0) or (AOffset >= Length(FBytes)) then Exit;
  if Byte(FBytes[AOffset + 1]) = AValue then Exit;

  if FHexUndoCount >= Length(FHexUndo) then
    SetLength(FHexUndo, Length(FHexUndo) * 2 + 64);
  FHexUndo[FHexUndoCount].Offset := AOffset;
  FHexUndo[FHexUndoCount].Value := Byte(FBytes[AOffset + 1]);
  Inc(FHexUndoCount);

  FBytes[AOffset + 1] := Chr(AValue);
  FHexDirty := True;
  RenderHexRow(AOffset);
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

function TLedDocument.CanUndoHex: Boolean;
begin
  Result := FIsBinary and (FHexUndoCount > 0);
end;

function TLedDocument.UndoHexByte: Integer;
var
  Offset: Integer;
begin
  Result := -1;
  if not CanUndoHex then Exit;
  Dec(FHexUndoCount);
  Offset := FHexUndo[FHexUndoCount].Offset;
  FBytes[Offset + 1] := Chr(FHexUndo[FHexUndoCount].Value);
  { Back to where it started only when every change has been undone -- the
    records are the file's original bytes, so an empty stack means the file on
    disk and the buffer agree again. }
  FHexDirty := FHexUndoCount > 0;
  RenderHexRow(Offset);
  Result := Offset;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

{ A key over a dump.  Which byte and which half of it the view worked out;
  what the key means is decided here, because it depends on the column it was
  typed in: a hex digit on the left replaces one nibble, and a character on
  the right replaces the whole byte.

  Overwrite only.  Inserting would move every byte after the caret and
  renumber every offset below it, which is not what a hex editor does and not
  what the offsets down the left-hand side would still be describing. }
procedure TLedDocument.HexKey(Sender: TObject; AOffset, ANibble: Integer;
  const AChar: string; var AHandled: Boolean);
var
  Digit, Old: Integer;
  Ch: Char;
  View: TLedEdit;
  NextCol: Integer;
begin
  AHandled := False;
  if (not FIsBinary) or (Length(AChar) <> 1) then Exit;
  Old := HexByte(AOffset);
  if Old < 0 then Exit;
  Ch := AChar[1];

  if ANibble >= 0 then
  begin
    Digit := LedHexDigitValue(Ch);
    { Anything that is not a hex digit is simply not a keystroke here. }
    if Digit < 0 then Exit;
    SetHexByte(AOffset, LedHexSetNibble(Byte(Old), ANibble = 0, Byte(Digit)));
  end
  else
  begin
    { The text column takes the character itself.  Only the printable ASCII
      range, because that is the only range the column can show back: a byte
      typed here has to be one a reader could recognise in the same place. }
    if (Ch < ' ') or (Ch >= #127) then Exit;
    SetHexByte(AOffset, Byte(Ch));
  end;

  AHandled := True;

  { Move on the way hexedit does -- across the two digits of a byte, then to
    the next byte, and from the end of a row to the start of the next. }
  View := TLedEdit(Sender);
  NextCol := LedHexNextColumn(View.CaretX);
  if NextCol = 0 then
  begin
    if View.CaretY < FMaster.Lines.Count then
    begin
      if ANibble >= 0 then NextCol := LedHexByteColumn(0)
      else NextCol := LedHexTextColumn(0);
      View.CaretXY := Point(NextCol, View.CaretY + 1);
    end;
  end
  else
    View.CaretX := NextCol;
end;

procedure TLedDocument.OpenAsText;
begin
  if FFileName = '' then Exit;
  FForceText := True;
  try
    LoadFromFile(FFileName);
  finally
    { One reopening, not a standing decision: a later Reload of a file that
      really is binary should go back to showing the dump. }
    FForceText := False;
  end;
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
  { A dump saves its bytes, never its buffer.  Writing the buffer would put
    the offsets and the bars over the bytes they describe, and the text path
    would normalise the line endings on the way out for good measure -- so
    this deliberately does not go near LedSaveTextFile. }
  if FIsBinary then
  begin
    LedWriteRawFile(AFileName, FBytes,
      LedPrefs.GetBool(LedPrefMakeBackups, False));
    FFileName := AFileName;
    FHexDirty := False;
    FHexUndoCount := 0;
    NoteDiskState;
    if Assigned(FOnChanged) then FOnChanged(Self);
    Exit;
  end;
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

{ The lowest number not currently in use, rather than one more than the last
  one ever handed out.

  A counter that only ever climbs is invisible until something makes closing
  easy.  Closing the last tab opens a fresh untitled document to replace it,
  so clicking the tab strip's close button repeatedly walked the title up --
  Untitled 9, 10, 11 -- with one empty document on screen the whole time.
  File > Close always did the same; the button just made it something you
  would sit there doing.

  Reuse keeps the numbers to as many as there are documents, so closing and
  reopening comes back to Untitled 1 instead of counting the session's
  accidents.  Result is not in FItems yet, so it cannot collide with itself. }
function TLedDocuments.NewDocument: TLedDocument;
var
  i, N: Integer;
  Taken: Boolean;
begin
  Result := TLedDocument.Create(nil);

  N := 0;
  repeat
    Inc(N);
    Taken := False;
    for i := 0 to FItems.Count - 1 do
      if TLedDocument(FItems[i]).IsUntitled and
         (TLedDocument(FItems[i]).UntitledNo = N) then
      begin
        Taken := True;
        Break;
      end;
  until not Taken;

  Result.UntitledNo := N;
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

var
  FDocuments: TLedDocuments = nil;

function LedDocuments: TLedDocuments;
begin
  if FDocuments = nil then
    FDocuments := TLedDocuments.Create(nil);
  Result := FDocuments;
end;

finalization
  FDocuments.Free;
  FUserConfig.Free;

end.
