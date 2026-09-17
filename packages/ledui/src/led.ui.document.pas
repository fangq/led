{ LED - a lightweight editor.  The document model.

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
  Classes, SysUtils, Math, Contnrs, Graphics, ExtCtrls, LazFileUtils, SynEdit,
  SynEditTypes,
  SynEditMiscClasses, SynEditHighlighter, SynEditKeyCmds,
  Led.Core.Types, Led.Core.FileIO, Led.Core.Hex, Led.Core.BJDView,
  Led.Core.BJDEdit, Led.Core.NBFormat, Led.Core.NBView, Led.Core.NBMagic,
  Led.Core.Kernel,
  fpjson,
  Led.Syn.BJData, Led.Syn.Notebook,
  Led.Core.Encodings,
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

  { One value edit in a structure view, kept so it can be taken back.  The
    bytes that were there, not a copy of the file: these files run to tens of
    megabytes and a stack of copies of one is not something to hold in
    memory.

    Offset is where those bytes go back.  It stays true without being
    maintained: a later edit above this one moves them, but that edit is also
    undone before this one is, so by the time this entry is used the file is
    the one it was recorded against. }
  TLedBJUndo = record
    Offset: PtrUInt;
    Size: PtrUInt;      // how many bytes occupy that slot now
    Old: string;        // what was there before
  end;

  TLedDocument = class;

  TLedDocumentEvent = procedure(ADoc: TLedDocument) of object;
  { One cell of a notebook changed -- it ran, or its output arrived.  Carries
    which cell, so a view of the cells can redo that one rather than all of
    them. }
  TLedDocumentCellEvent = procedure(ADoc: TLedDocument;
    ACell: Integer) of object;

  { Asked whether to build ACount rows for one container.  True goes ahead. }
  TLedBJConfirmExpand = function(ACount: Int64): Boolean of object;

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
    FIsBinary: Boolean;         // shown as a rendering of bytes, not as text
    { A binary shown as a BJData structure rather than as a hex dump.  Both
      are renderings of FBytes and both are read-only and save their bytes,
      so this narrows FIsBinary rather than replacing it. }
    FIsBJData: Boolean;
    FBJRows: TLedBJRows;        // the record map behind the structure view
    { Set when a file with a BJData extension would not decode.  It is then
      opened as a hex dump instead, and these say what went wrong and which
      byte to put the caret on.  The window reports them and clears them --
      the document does not put dialogs on the screen. }
    FBJError: string;
    FBJErrorOffset: PtrUInt;
    { Containers the reader has asked to see in full, by file offset.  Kept
      across re-walks and reloads of the same file, so opening one and then
      opening another inside it does not close the first. }
    FBJExpanded: TLedBJExpanded;
    FOnConfirmExpand: TLedBJConfirmExpand;
    { The structure view's own highlighter, made when a document first needs
      one and owned by the document: it carries that document's rows, so it
      cannot be shared the way the language ones in Led.Syn.Factory are. }
    FBJHigh: TLedBJHighlighter;
    { A notebook's own highlighter, for the same reason: it carries this
      document's cell map and its own language highlighters. }
    FNBHigh: TLedNBHighlighter;
    { A Jupyter notebook.  Not a binary and not read-only: the buffer is
      editable text, and what the document protects is the handful of lines
      in it that are a rendering of the file rather than the file's own
      text -- the headers, the output labels and the outputs.

      Which lines those are is not worked out by looking at them.  Every
      rendered line carries a tag in the buffer's own per-line Objects,
      which SynEdit moves with its line when lines are inserted or deleted
      above it, so the map stays true through any amount of typing without
      the document having to follow the edits. }
    FIsNotebook: Boolean;
    FNotebook: TLedNotebook;
    FNBError: string;           // why a .ipynb would not open as one
    { The kernel this notebook's cells run in, and the runs in flight.

      A kernel belongs to the document rather than to the window: what it
      holds is this notebook's variables, and two windows onto the same
      notebook are two views of one session, not two sessions. }
    FKernel: TLedKernel;
    FKernelTimer: TTimer;
    { Output and execution counts live in the notebook rather than in the
      buffer, and SynEdit's Modified only knows about the buffer -- so a cell
      that has just run leaves the document changed in a way that has to be
      recorded here.  The hex view keeps its own flag for the same reason. }
    FNBDirty: Boolean;
    FRuns: array of record Id, Cell: Integer; end;
    FDirtyCells: array of Integer;   // cells whose output has just changed
    FOnKernel: TLedDocumentEvent;
    FOnCell: TLedDocumentCellEvent;
    FForceText: Boolean;        // the user asked for the text editor anyway
    { The bytes themselves, when the document is a dump.  This is the file;
      the buffer the views show is a rendering of it, rebuilt a row at a time
      as bytes change. }
    FBytes: string;
    FHexUndo: array of TLedHexUndo;
    FHexUndoCount: Integer;
    FBJUndo: array of TLedBJUndo;
    FBJUndoCount: Integer;
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
    procedure BJOpenRequested(Sender: TObject; ATextIdx: Integer);
    function BJLineForOffset(AOffset: PtrUInt): Integer;
    function BJRow(ATextIdx: Integer; out ARow: TLedBJRow): Boolean;
    function BJRewalk(ATextIdx: Integer; APatched: Boolean): Boolean;
    function NBTagOf(ALine: Integer): PtrInt;
    procedure NBTag(ALine: Integer; AKind, ACell: Integer);
    function NBHeaderAbove(ALine: Integer; out ACell: Integer): Integer;
    procedure NBRender;
    function NBGuard(Sender: TObject; ACommand: TSynEditorCommand): Boolean;
    function NBLineKind(ALine: Integer; out ACell: Integer;
      out ALang: string): TLedNBLine;
    function NBCellLanguage(ACell, AHeaderLine: Integer): string;
    function NBLineText(ALine: Integer): string;
    procedure NBTheme;
    procedure NBKernelEvent(Sender: TObject; const AEvent: TLedKernelEvent);
    procedure NBKernelTick(Sender: TObject);
    function NBCellOfRun(AId: Integer): Integer;
    procedure NBMarkDirty(ACell: Integer);
    procedure NBFlushDirty;
    procedure ReadModelines;
    procedure DetectLanguage;
    procedure ApplyLanguage;
    function PreparedText: string;
    { A hex dump, as opposed to the other kind of binary.  The byte-editing
      path and the hex markup are addressed in rows of LedHexBytesPerLine and
      mean nothing over a structure view. }
    function IsHexDump: Boolean;
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
    { True when the buffer is the BJData structure view.  IsBinary is true as
      well: the file is still bytes and the buffer is still a rendering. }
    property IsBJData: Boolean read FIsBJData;
    property BJDataRows: TLedBJRows read FBJRows;
    { Why a BJData file was opened as a hex dump instead, and where to look.
      Empty when nothing went wrong.  TakeBJDataError reads and clears, so a
      reload reports again and a redraw does not. }
    property BJDataErrorOffset: PtrUInt read FBJErrorOffset;
    function TakeBJDataError(out AOffset: PtrUInt): string;

    { Shows a container the walk summarised, given the 0-based buffer line it
      is on.  False when that line is not one, or when the reader said no.

      The rows below it are renumbered, so every view's caret is put back on
      the record it was on rather than on the line number it was at. }
    function BJOpenRow(ATextIdx: Integer): Boolean;

    { The value on buffer line ATextIdx as text to be typed over -- the
      number, the string without its quotes -- and whether it can be typed
      over at all.  AWhy is a sentence to show the reader when it cannot. }
    function BJRowValueText(ATextIdx: Integer): string;
    function BJRowCanEdit(ATextIdx: Integer; out AWhy: string): Boolean;

    { Writes ANewText into that record.  bjePatched means the new value was
      the same size as the old one and went where it was, so nothing below it
      moved and one line was re-rendered; bjeSpliced means it was a different
      size and the page was rebuilt.  Either way the rows are walked again,
      because a row's Value is a cursor into bytes that are now a different
      string.

      bjeRefused changes nothing and AWhy says what stopped it. }
    function EditBJRow(ATextIdx: Integer; const ANewText: string;
      out AWhy: string; AAsMarker: AnsiChar = #0): TLedBJEditKind;
    { Puts back the last value that changed, and returns the line it is on so
      the caller can show it.  -1 when there was nothing to take back.

      Byte for byte, not by re-typing the old text: a value that widened its
      marker on the way in would not come back through the same door. }
    function CanUndoBJEdit: Boolean;
    function UndoBJEdit: Integer;

    { True when the buffer is a rendering of a Jupyter notebook. }
    property IsNotebook: Boolean read FIsNotebook;
    { The notebook itself, for the kernel and for anything that needs the
      file rather than the rendering.  nil unless IsNotebook. }
    property Notebook: TLedNotebook read FNotebook;
    { Why a .ipynb opened as plain text instead.  Read and cleared, like the
      BJData one, so a reload reports again and a redraw does not. }
    function TakeNotebookError: string;

    { The cell a buffer line belongs to, or -1.  Lines in the gap between
      cells belong to none. }
    function NBCellOfLine(ATextIdx: Integer): Integer;
    { Whether a line is one the reader may type into: the cell's own source,
      as opposed to a header or an output. }
    function NBLineIsSource(ATextIdx: Integer): Boolean;
    { How many cells, and the line a cell's source starts on. }
    function NBCellCount: Integer;
    function NBSourceLineOf(ACell: Integer): Integer;
    { Replaces one cell's source, in the notebook and in the buffer at once.

      What the notebook pane calls when a cell is typed into: the pane edits
      a cell, and the line view has to say the same thing a moment later.
      The other direction needs nothing -- the buffer is read back into the
      notebook by NBSyncFromBuffer before anything that matters. }
    procedure NBSetCellSource(ACell: Integer; const AText: string);

    { Copies what the buffer holds back into the notebook, cell by cell.
      Called before saving and before running: the buffer is what the reader
      has been typing into, so it is the truth about the source. }
    procedure NBSyncFromBuffer;
    { Re-renders one cell's header and outputs from the notebook, leaving its
      source lines alone -- what running a cell needs. }
    procedure NBRefreshCell(ACell: Integer);

    { The kernel.  Starting one takes a second or two, so Start only says
      whether the helper went up: readiness arrives later and OnKernelChanged
      is fired for it, along with every other change of state. }
    function NBKernelStart(out AWhy: string): Boolean;
    function NBKernelState: TLedKernelState;
    { One line for the status bar: what the kernel is and what it is doing. }
    function NBKernelStatus: string;
    procedure NBKernelInterrupt;
    procedure NBKernelRestart;
    procedure NBKernelStop;
    { Sends a cell to the kernel, starting one if none is running.  False
      with a reason when it cannot: no kernel, or the row is not a code cell.
      The cell's own source is taken from the buffer, so what runs is what
      the reader can see. }
    function NBRunCell(ACell: Integer; out AWhy: string): Boolean;
    { Every code cell, in order.  The kernel runs them in the order they
      arrive, which is the order they are on the page. }
    function NBRunAll(out AWhy: string): Boolean;
    property OnKernelChanged: TLedDocumentEvent read FOnKernel write FOnKernel;
    { Fired for the one cell whose header or output has just changed.  A view
      that shows the cells uses this instead of rebuilding itself: on a real
      notebook rebuilding is a hundred cells and fifty page layouts, and
      doing it from inside a kernel event took the editor out. }
    property OnCellChanged: TLedDocumentCellEvent read FOnCell write FOnCell;

    { Asked before opening something large; nil means do not ask.  The
      document does not put dialogs on the screen -- the window supplies
      this, the same way it reports a failed decode. }
    property OnConfirmExpand: TLedBJConfirmExpand
      read FOnConfirmExpand write FOnConfirmExpand;
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

{ Whether a document is still open.

  For anything that holds a document across time -- a pane with a timer, say.
  A closed document is freed, and a pointer to one is not something that can
  be asked whether it is still valid, so what is asked instead is whether the
  collection still has it. }
function LedDocumentIsOpen(ADoc: TLedDocument): Boolean;

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
  { Owned here rather than by a component, because it carries this document's
    rows and nothing else's. }
  FBJHigh.Free;
  FNBHigh.Free;
  { Before the notebook: shutting a kernel down writes to it. }
  FKernelTimer.Free;
  FKernel.Free;
  FNotebook.Free;
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
  { Hex mode is the byte grid: fixed columns, a caret that snaps to a nibble,
    keys routed to HexKey.  A structure view shares none of that geometry, so
    it is read-only like a dump but is not one. }
  AView.HexMode := IsHexDump;
  { And the structure view says so too, which is what colours its offset
    column and keeps the caret out of it. }
  AView.BJDataMode := FIsBJData;
  AView.NotebookMode := FIsNotebook;
  if FIsNotebook then
    AView.OnNBGuard := @NBGuard
  else
    AView.OnNBGuard := nil;
  if IsHexDump then
    AView.OnHexKey := @HexKey
  else
    AView.OnHexKey := nil;
  if FIsBJData then
    AView.OnBJOpen := @BJOpenRequested
  else
    AView.OnBJOpen := nil;

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
  AView.FoldedLineColour :=
    LedThemeFoldedLineColour(LedCurrentTheme, AView.Font.Color, AView.Color);

  { The caret's row is marked with a rule above and below rather than with a
    band of colour behind it, so the theme's current-line colour moves off
    SynEdit's own row fill and onto LED's painter.

    Not the theme's colour as it stands: a tint chosen to fill a whole row is
    invisible in a one-pixel rule, which is what made the marker so faint in
    most schemes.  LedThemeCurrentLineColour takes it and pushes it far
    enough off the page to be seen -- and supplies one for a scheme that says
    nothing about the current line, which used to leave no rules at all.

    The hex markup keeps reading it from here. }
  AView.CurrentLineColour := LedThemeCurrentLineColour(LedCurrentTheme,
    AView.Font.Color, AView.Color);
  AView.LineHighlightColor.Background := clNone;

  { After the theme has been applied, because the column colours are mixed
    from the editor's own -- asking earlier would mix them from the last
    theme's. }
  { Both binary views, not just the dump: the structure view's offsets are
    drawn from the same colours, so that a file offset looks the same
    whichever of the two it is being read in. }
  if FIsBinary and (AView.HexMarkup <> nil) then
    AView.HexMarkup.SetColours(AView.Font.Color, AView.Color,
      AView.Gutter.LineNumberPart.MarkupInfo.Foreground,
      AView.CurrentLineColour);

  Wrap := LowerCase(FConfig.GetStr(LedSetWrapMode));
  AView.WrapEnabled := (Wrap <> '') and (Wrap <> 'none');
end;

{ Languages whose files are prose rather than source.  Under the default
  "auto" these are checked end to end; everything else is checked in its
  comments and strings only.

  This is medit's documented behaviour rather than its implemented one:
  moospellcheck.cpp turns checking off for any file with a language at all,
  including Markdown and LaTeX, and its own comment says the
  comments-and-strings filter was never written.  LED has that filter, so it
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
  { The structure view's highlighter belongs to this document, so LedRetheme
    -- which re-themes the shared language ones -- never reaches it.  Without
    this a theme change left the structure view in the old scheme's colours,
    which is how the check that reads a marker's contrast in every scheme
    found it. }
  if FBJHigh <> nil then
    LedApplyThemeToHighlighter(LedCurrentTheme, FBJHigh);
  NBTheme;
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
  { The structure view is coloured from the walk that rendered it rather than
    from a language.  The walk knew what every field was -- this record is a
    string, that column is a key, this count is LED's own -- so the view is
    told, instead of a grammar reading the text back and deciding again. }
  if FIsBJData then
  begin
    if FBJHigh = nil then FBJHigh := TLedBJHighlighter.Create(nil);
    FBJHigh.SetRows(FBJRows);
    LedApplyThemeToHighlighter(LedCurrentTheme, FBJHigh);
    HL := FBJHigh;
  end
  { A notebook is coloured from what the document knows about each line and,
    inside a cell, by the real highlighter for that cell's language: the same
    Python colouring a .py file gets, because it is the same highlighter. }
  else if FIsNotebook then
  begin
    if FNBHigh = nil then
    begin
      FNBHigh := TLedNBHighlighter.Create(nil);
      FNBHigh.OnLineKind := @NBLineKind;
      FNBHigh.OnLineText := @NBLineText;
    end;
    NBTheme;
    HL := FNBHigh;
  end
  else
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
  { A notebook is modified by typing into a cell -- which SynEdit sees -- and
    by running one, which it does not. }
  if FIsNotebook then Exit(FMaster.Modified or FNBDirty);
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
{ The view asked for a container to be opened. }
procedure TLedDocument.BJOpenRequested(Sender: TObject; ATextIdx: Integer);
begin
  BJOpenRow(ATextIdx);
end;

function TLedDocument.BJOpenRow(ATextIdx: Integer): Boolean;
var
  Row: TLedBJRow;
  Rows: TLedBJRows;
  Err: string;
  ErrAt, Want: PtrUInt;
  i, j: Integer;
  Carets: array of PtrUInt;
  Tops: array of Integer;
  V: TLedEdit;
begin
  Result := False;
  if not FIsBJData then Exit;
  if (ATextIdx < 0) or (ATextIdx > High(FBJRows)) then Exit;
  Row := FBJRows[ATextIdx];
  if not Row.CanExpand then Exit;

  { Asked before the work, not after: building a couple of hundred thousand
    rows is quick but the page that comes back is not one anybody scrolls
    through by accident. }
  if Assigned(FOnConfirmExpand) and (Row.ChildCount > LedBJAskAbove) then
    if not FOnConfirmExpand(Row.ChildCount) then Exit;

  Want := Row.Offset;
  for i := 0 to High(FBJExpanded) do
    if FBJExpanded[i] = Want then Exit;   // already open; nothing to do
  SetLength(FBJExpanded, Length(FBJExpanded) + 1);
  FBJExpanded[High(FBJExpanded)] := Want;

  { Which record each view was looking at, by offset.  Line numbers below the
    one being opened all change, so putting a caret back where it was on the
    page would land it somewhere else in the file. }
  SetLength(Carets, FViews.Count);
  SetLength(Tops, FViews.Count);
  for i := 0 to FViews.Count - 1 do
  begin
    V := TLedEdit(FViews[i]);
    Carets[i] := 0;
    Tops[i] := 1;
    j := V.CaretY - 1;
    if (j >= 0) and (j <= High(FBJRows)) then Carets[i] := FBJRows[j].Offset;
    Tops[i] := V.TopLine;
  end;

  if not LedBJTryWalk(FBytes, Rows, Err, ErrAt, FBJExpanded) then
  begin
    { The file has not changed, so a walk that fails now is a walk that would
      have failed before -- put the expansion back and leave the view alone
      rather than replacing a readable page with half of one. }
    SetLength(FBJExpanded, Length(FBJExpanded) - 1);
    Exit;
  end;

  FBJRows := Rows;
  if FBJHigh <> nil then FBJHigh.SetRows(FBJRows);

  FMaster.BeginUpdate;
  try
    FMaster.Lines.Text := LedBJRowsText(FBJRows);
    FMaster.ClearUndo;
    FMaster.Modified := False;
  finally
    FMaster.EndUpdate;
  end;

  for i := 0 to FViews.Count - 1 do
  begin
    V := TLedEdit(FViews[i]);
    j := BJLineForOffset(Carets[i]);
    if j >= 0 then
    begin
      V.CaretXY := Point(V.CaretX, j + 1);
      V.TopLine := Tops[i];
      V.EnsureCursorPosVisible;
    end;
  end;

  if Assigned(FOnChanged) then FOnChanged(Self);
  Result := True;
end;

function TLedDocument.BJRow(ATextIdx: Integer; out ARow: TLedBJRow): Boolean;
begin
  Result := FIsBJData and (ATextIdx >= 0) and (ATextIdx <= High(FBJRows));
  if Result then ARow := FBJRows[ATextIdx];
end;

function TLedDocument.BJRowValueText(ATextIdx: Integer): string;
var
  Row: TLedBJRow;
begin
  Result := '';
  if BJRow(ATextIdx, Row) then Result := LedBJValueText(Row);
end;

function TLedDocument.BJRowCanEdit(ATextIdx: Integer; out AWhy: string): Boolean;
var
  Row: TLedBJRow;
begin
  { Said before LedBJCanEdit is asked, because that clears AWhy on its way
    in: a line that is not a record at all never reaches it. }
  AWhy := 'this line is not a record of the file';
  Result := BJRow(ATextIdx, Row) and LedBJCanEdit(Row, AWhy);
end;

{ Puts the view back in step with FBytes after an edit changed them.

  APatched means no offset moved, so the only line whose rendering can have
  changed is ATextIdx's and the page does not so much as flicker.  A splice
  moved everything below the edit, so the buffer is rebuilt.

  The walk happens either way.  A row's Value is a pointer into the bytes,
  and the bytes are a different string now -- keeping the old rows would
  leave every cursor in the document pointing at a buffer nothing holds. }
function TLedDocument.BJRewalk(ATextIdx: Integer; APatched: Boolean): Boolean;
var
  Rows: TLedBJRows;
  Err: string;
  ErrAt: PtrUInt;
  i: Integer;
  V: TLedEdit;
  Carets: array of TPoint;
  Tops: array of Integer;
begin
  Result := LedBJTryWalk(FBytes, Rows, Err, ErrAt, FBJExpanded);
  if not Result then Exit;
  FBJRows := Rows;
  if FBJHigh <> nil then FBJHigh.SetRows(FBJRows);

  if APatched and (ATextIdx >= 0) and (ATextIdx < FMaster.Lines.Count) and
     (ATextIdx <= High(FBJRows)) then
  begin
    { Straight into the buffer rather than through an edit command, the same
      way a dump re-renders a row: the views are read-only and the undo that
      matters is the document's own. }
    FMaster.Lines[ATextIdx] := LedBJRowText(FBJRows[ATextIdx]);
    Exit;
  end;

  SetLength(Carets, FViews.Count);
  SetLength(Tops, FViews.Count);
  for i := 0 to FViews.Count - 1 do
  begin
    V := TLedEdit(FViews[i]);
    Carets[i] := V.CaretXY;
    Tops[i] := V.TopLine;
  end;

  FMaster.BeginUpdate;
  try
    FMaster.Lines.Text := LedBJRowsText(FBJRows);
    FMaster.ClearUndo;
    FMaster.Modified := False;
  finally
    FMaster.EndUpdate;
  end;

  { By line, unlike opening a container.  Changing a value never adds or
    removes a record, so the row a caret was on is still the record it was
    on even when every byte under it moved. }
  for i := 0 to FViews.Count - 1 do
  begin
    V := TLedEdit(FViews[i]);
    Carets[i].y := Min(Carets[i].y, FMaster.Lines.Count);
    V.CaretXY := Carets[i];
    V.TopLine := Tops[i];
  end;
end;

function TLedDocument.EditBJRow(ATextIdx: Integer; const ANewText: string;
  out AWhy: string; AAsMarker: AnsiChar): TLedBJEditKind;
var
  Row: TLedBJRow;
  Keep: string;
  Start, Size, NewSize: PtrUInt;
begin
  Result := bjeRefused;
  AWhy := 'this line is not a record of the file';
  if not BJRow(ATextIdx, Row) then Exit;

  { The bytes as they stand, held for the length of the edit.  Row.Value
    points into them and the edit hands FBytes a different string, so
    without this the cursor being edited would dangle halfway through its
    own edit.  It is also where a failed walk goes back to. }
  Keep := FBytes;
  Start := Row.Offset;
  Size := Row.Value.Size;

  Result := LedBJEditValue(FBytes, Row, ANewText, AWhy, AAsMarker);
  if not (Result in [bjePatched, bjeSpliced]) then Exit;

  if not BJRewalk(ATextIdx, Result = bjePatched) then
  begin
    { Not something a value edit should be able to do -- the marker written
      is one the file already used or one the library chose -- but a
      structure view that has stopped describing its own file is worse than
      an edit that refuses. }
    FBytes := Keep;
    BJRewalk(ATextIdx, False);
    AWhy := 'the file would not read back after that change';
    Exit(bjeRefused);
  end;

  { Where those bytes go back, and how many of them are there now.  Both are
    recorded as the file stands at this moment, and both are still true when
    this entry comes off the top of the stack: undo is last in, first out, so
    every edit made after this one has already been taken back by then and
    the file is byte for byte the one this entry was written against. }
  NewSize := PtrUInt(Int64(Size) +
    (Int64(Length(FBytes)) - Int64(Length(Keep))));

  if FBJUndoCount >= Length(FBJUndo) then
    SetLength(FBJUndo, Length(FBJUndo) * 2 + 16);
  FBJUndo[FBJUndoCount].Offset := Start;
  FBJUndo[FBJUndoCount].Size := NewSize;
  FBJUndo[FBJUndoCount].Old := Copy(Keep, Start + 1, Size);
  Inc(FBJUndoCount);

  FHexDirty := True;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

function TLedDocument.CanUndoBJEdit: Boolean;
begin
  Result := FIsBJData and (FBJUndoCount > 0);
end;

function TLedDocument.UndoBJEdit: Integer;
var
  Old: string;
  At, Size: PtrUInt;
begin
  Result := -1;
  if not CanUndoBJEdit then Exit;

  Dec(FBJUndoCount);
  At := FBJUndo[FBJUndoCount].Offset;
  Size := FBJUndo[FBJUndoCount].Size;
  Old := FBJUndo[FBJUndoCount].Old;
  FBJUndo[FBJUndoCount].Old := '';      // the bytes are going back in the file

  FBytes := Copy(FBytes, 1, At) + Old + Copy(FBytes, At + Size + 1, MaxInt);

  { The same rule a dump keeps: unmodified again only when every change has
    been taken back, because what is on the stack is the file's own bytes. }
  FHexDirty := FBJUndoCount > 0;
  Result := BJLineForOffset(At);
  BJRewalk(Result, PtrUInt(Length(Old)) = Size);
  { Looked up again after the walk when the page was rebuilt: the record is
    on the same line, but saying so from the rows in front of us is cheaper
    to believe than saying so from the ones that have gone. }
  if Result < 0 then Result := BJLineForOffset(At);
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

{ ---- notebooks ---- }

{ The tag on a rendered line, or 0 for a line of a cell's own source.

  Source lines are deliberately untagged.  Everything else -- the header, the
  output label, each output line, the gap between cells -- carries one, and a
  source line is then "an untagged line under a header".  That way the map
  depends only on lines the reader cannot edit, and the ones they can edit
  need no bookkeeping at all: SynEdit carries each tag along with its line
  when lines are inserted or deleted above it, so typing twenty lines into a
  cell moves every header below it without the document being told. }
const
  NBTagHeader = 1;
  NBTagOut    = 2;      // the output label and ordinary output lines
  NBTagErr    = 3;      // an output line that came from a traceback
  NBTagGap    = 4;      // the blank line between two cells
  NBTagKinds  = 8;      // room for those, and a power of two to divide by

function TLedDocument.NBTagOf(ALine: Integer): PtrInt;
begin
  Result := 0;
  if (ALine < 0) or (ALine >= FMaster.Lines.Count) then Exit;
  Result := PtrInt(FMaster.Lines.Objects[ALine]);
end;

procedure TLedDocument.NBTag(ALine: Integer; AKind, ACell: Integer);
begin
  if (ALine < 0) or (ALine >= FMaster.Lines.Count) then Exit;
  if AKind = 0 then
    FMaster.Lines.Objects[ALine] := nil
  else
    FMaster.Lines.Objects[ALine] := TObject(PtrInt(-(ACell * NBTagKinds + AKind)));
end;

{ The header line at or above ALine, and which cell it opens.  -1 when there
  is none above it, or when what is above is not a header -- an output line,
  say, which means ALine is not inside any cell's source. }
function TLedDocument.NBHeaderAbove(ALine: Integer;
  out ACell: Integer): Integer;
var
  i: Integer;
  T: PtrInt;
begin
  ACell := -1;
  Result := -1;
  { A line outside the buffer has no header above it, and saying otherwise is
    not a rounding error.  Something scanning down a cell asks about the line
    after the last one to find out where the cell ends; while a line past the
    end answered "the last cell's source" -- which it did, because walking up
    from beyond the end reaches that cell's header -- the scan never found an
    end, and every step of it walked the file again.  Measured on a 1000-line
    notebook: eight thousand million steps and climbing, which is what "led
    froze when opening this file" was.

    The guard is here rather than in each caller because this is the one
    place all three of them go through, and the first attempt put it in only
    one of the three. }
  if (ALine < 0) or (ALine >= FMaster.Lines.Count) then Exit;
  i := ALine;
  while i >= 0 do
  begin
    T := NBTagOf(i);
    if T <> 0 then
    begin
      if (-T) mod NBTagKinds = NBTagHeader then
      begin
        ACell := (-T) div NBTagKinds;
        Exit(i);
      end;
      Exit(-1);
    end;
    Dec(i);
  end;
end;

function TLedDocument.NBCellOfLine(ATextIdx: Integer): Integer;
var
  T: PtrInt;
  Cell: Integer;
begin
  Result := -1;
  if not FIsNotebook then Exit;
  T := NBTagOf(ATextIdx);
  if T <> 0 then
  begin
    if (-T) mod NBTagKinds = NBTagGap then Exit(-1);
    Exit((-T) div NBTagKinds);
  end;
  NBHeaderAbove(ATextIdx, Cell);
  Result := Cell;
end;

function TLedDocument.NBLineIsSource(ATextIdx: Integer): Boolean;
var
  Cell: Integer;
begin
  Result := FIsNotebook and (NBTagOf(ATextIdx) = 0) and
            (NBHeaderAbove(ATextIdx, Cell) >= 0);
end;

function TLedDocument.NBCellCount: Integer;
begin
  if FIsNotebook then Result := FNotebook.CellCount else Result := 0;
end;

function TLedDocument.NBSourceLineOf(ACell: Integer): Integer;
var
  i, Cell: Integer;
  T: PtrInt;
begin
  Result := -1;
  if not FIsNotebook then Exit;
  for i := 0 to FMaster.Lines.Count - 1 do
  begin
    T := NBTagOf(i);
    if (T <> 0) and ((-T) mod NBTagKinds = NBTagHeader) then
    begin
      Cell := (-T) div NBTagKinds;
      if Cell = ACell then
      begin
        { The line after the header, which always exists: a cell with no
          source is rendered with one empty line to type on. }
        if i + 1 < FMaster.Lines.Count then Result := i + 1;
        Exit;
      end;
    end;
  end;
end;

{ Whether an editing command may run.

  A command is refused when it would change a line that is a rendering
  rather than the file's own text.  The edges matter as much as the middle:
  a backspace at the start of a cell's first line would pull it into the
  header, and a delete at the end of its last line would swallow the output
  label, so both are refused even though the caret is on a line that is
  otherwise editable. }
function TLedDocument.NBGuard(Sender: TObject;
  ACommand: TSynEditorCommand): Boolean;
var
  View: TLedEdit;
  i, Y, Cell, OtherCell: Integer;
  B, E: TPoint;
begin
  Result := True;
  if not FIsNotebook then Exit;
  View := TLedEdit(Sender);

  { A real selection, not SynEdit's SelAvail: that is true of an empty
    selection as well, and an empty one took this branch and let the checks
    on the edges below be skipped -- which is how a backspace at the start of
    a cell came to pull the cell into its header. }
  if View.SelectionIsReal then
  begin
    B := View.BlockBegin;
    E := View.BlockEnd;
    { A selection that ends at the very start of a line does not include
      that line, and refusing on it would make a whole-line selection
      undeletable. }
    if (E.X = 1) and (E.Y > B.Y) then Dec(E.Y);
    Cell := NBCellOfLine(B.Y - 1);
    for i := B.Y - 1 to E.Y - 1 do
      if (not NBLineIsSource(i)) or (NBCellOfLine(i) <> Cell) then
        Exit(False);
    Exit;
  end;

  Y := View.CaretY - 1;
  if not NBLineIsSource(Y) then Exit(False);
  Cell := NBCellOfLine(Y);

  { Backspace at the left margin, and the two ways of deleting backwards
    over a line break.

    Spelled out rather than tested against a set: SynEdit numbers its editing
    commands from 501, a Pascal set holds 0..255, and "ACommand in [...]"
    compiled with a range-check warning and then matched nothing -- so a
    backspace at the start of a cell pulled the cell into its header until
    the compiler's own warning was read. }
  if ((ACommand = ecDeleteLastChar) or (ACommand = ecDeleteLastWord)) and
     (View.CaretX = 1) then
  begin
    if not NBLineIsSource(Y - 1) then Exit(False);
    OtherCell := NBCellOfLine(Y - 1);
    if OtherCell <> Cell then Exit(False);
  end;

  if ((ACommand = ecDeleteChar) or (ACommand = ecDeleteWord)) and
     (View.CaretX > Length(FMaster.Lines[Y])) then
  begin
    if not NBLineIsSource(Y + 1) then Exit(False);
    OtherCell := NBCellOfLine(Y + 1);
    if OtherCell <> Cell then Exit(False);
  end;
end;

{ The whole notebook into the buffer, with every rendered line tagged.  Used
  when a file is opened and when the structure changes; one cell's outputs
  changing goes through NBRefreshCell instead, which leaves the rest of the
  page and the undo history alone. }
procedure TLedDocument.NBRender;
var
  Rows: TLedNBRows;
  Text: string;
  i: Integer;
begin
  if not FIsNotebook then Exit;
  Text := LedNBRender(FNotebook, Rows);
  FMaster.BeginUpdate;
  try
    FMaster.Lines.Text := Text;
    { Lines.Text on an empty document leaves one line; a notebook always
      renders at least a header, so a mismatch here would mean the render
      and the buffer disagree, and the tags would go on the wrong lines. }
    for i := 0 to High(Rows) do
    begin
      if i >= FMaster.Lines.Count then Break;
      case Rows[i].Kind of
        nbrHeader:   NBTag(i, NBTagHeader, Rows[i].Cell);
        nbrOutLabel: NBTag(i, NBTagOut, Rows[i].Cell);
        nbrOutput:   if Rows[i].IsError then
                       NBTag(i, NBTagErr, Rows[i].Cell)
                     else
                       NBTag(i, NBTagOut, Rows[i].Cell);
        nbrBlank:    NBTag(i, NBTagGap, 0);
      else
        NBTag(i, 0, 0);
      end;
    end;
    FMaster.ClearUndo;
    FMaster.Modified := False;
  finally
    FMaster.EndUpdate;
  end;
end;

procedure TLedDocument.NBSetCellSource(ACell: Integer; const AText: string);
var
  Head, Stop, i: Integer;
  Lines: TStringList;
begin
  if not FIsNotebook then Exit;
  if (ACell < 0) or (ACell >= FNotebook.CellCount) then Exit;
  if FNotebook.CellSource(ACell) = AText then Exit;

  FNotebook.SetCellSource(ACell, AText);
  FNBDirty := True;

  { And the same text into the buffer, between this cell's header and
    whatever follows it.  The tags go back on as the lines are written: the
    ones being replaced take their tags with them. }
  Head := -1;
  for i := 0 to FMaster.Lines.Count - 1 do
    if (NBTagOf(i) <> 0) and ((-NBTagOf(i)) mod NBTagKinds = NBTagHeader) and
       ((-NBTagOf(i)) div NBTagKinds = ACell) then
    begin
      Head := i;
      Break;
    end;
  if Head < 0 then Exit;

  Stop := Head + 1;
  while (Stop < FMaster.Lines.Count) and (NBTagOf(Stop) = 0) do Inc(Stop);

  Lines := TStringList.Create;
  FMaster.BeginUpdate;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    if AText = '' then
      Lines.Add('')
    else
    begin
      Lines.Text := AText;
      if (Lines.Count > 1) and (Lines[Lines.Count - 1] = '') and
         (AText[Length(AText)] <> #10) then
        Lines.Delete(Lines.Count - 1);
    end;

    for i := Stop - 1 downto Head + 1 do FMaster.Lines.Delete(i);
    for i := 0 to Lines.Count - 1 do
    begin
      FMaster.Lines.Insert(Head + 1 + i, Lines[i]);
      NBTag(Head + 1 + i, 0, 0);
    end;
  finally
    FMaster.EndUpdate;
    Lines.Free;
  end;

  if Assigned(FOnChanged) then FOnChanged(Self);
end;

procedure TLedDocument.NBSyncFromBuffer;
var
  i, Cell, Line: Integer;
  Source: string;
  First: Boolean;
begin
  if not FIsNotebook then Exit;
  for Cell := 0 to FNotebook.CellCount - 1 do
  begin
    Line := NBSourceLineOf(Cell);
    if Line < 0 then Continue;
    Source := '';
    First := True;
    i := Line;
    while (i < FMaster.Lines.Count) and (NBTagOf(i) = 0) do
    begin
      if not First then Source := Source + #10;
      Source := Source + FMaster.Lines[i];
      First := False;
      Inc(i);
    end;
    { Only when it differs, so that a notebook opened and saved again is the
      same bytes: rewriting a cell's source splits it into lines afresh, and
      a file that stored its source as one string would come back as a list. }
    if Source <> FNotebook.CellSource(Cell) then
      FNotebook.SetCellSource(Cell, Source);
  end;
end;

procedure TLedDocument.NBRefreshCell(ACell: Integer);
var
  Head, i, Cell, Stop: Integer;
  T: PtrInt;
  Outs: TStringList;
  Errors: TLedNBFlags;
  Carets: array of TPoint;
  V: TLedEdit;
begin
  if not FIsNotebook then Exit;

  { Where the cell is now. }
  Head := -1;
  for i := 0 to FMaster.Lines.Count - 1 do
  begin
    T := NBTagOf(i);
    if (T <> 0) and ((-T) mod NBTagKinds = NBTagHeader) and
       ((-T) div NBTagKinds = ACell) then
    begin
      Head := i;
      Break;
    end;
  end;
  if Head < 0 then Exit;

  { Its source lines end where the next tagged line begins. }
  Stop := Head + 1;
  while (Stop < FMaster.Lines.Count) and (NBTagOf(Stop) = 0) do Inc(Stop);

  SetLength(Carets, FViews.Count);
  for i := 0 to FViews.Count - 1 do
    Carets[i] := TLedEdit(FViews[i]).CaretXY;

  Outs := TStringList.Create;
  FMaster.BeginUpdate;
  try
    Outs.TextLineBreakStyle := tlbsLF;
    LedNBOutputLines(FNotebook, ACell, Outs, Errors);

    { Out with the old output block: every tagged output line of this cell
      that follows the source. }
    i := Stop;
    while i < FMaster.Lines.Count do
    begin
      T := NBTagOf(i);
      if T = 0 then Break;
      Cell := (-T) div NBTagKinds;
      if ((-T) mod NBTagKinds <> NBTagOut) and
         ((-T) mod NBTagKinds <> NBTagErr) then Break;
      if Cell <> ACell then Break;
      FMaster.Lines.Delete(i);
    end;

    { And in with the new. }
    if Outs.Count > 0 then
    begin
      FMaster.Lines.Insert(Stop, LedNBOutLabelText);
      NBTag(Stop, NBTagOut, ACell);
      for i := 0 to Outs.Count - 1 do
      begin
        FMaster.Lines.Insert(Stop + 1 + i,
          StringOfChar(' ', LedNBOutIndent) + Outs[i]);
        if (i <= High(Errors)) and Errors[i] then
          NBTag(Stop + 1 + i, NBTagErr, ACell)
        else
          NBTag(Stop + 1 + i, NBTagOut, ACell);
      end;
    end;

    { The header carries the execution count, which is what just changed. }
    FMaster.Lines[Head] := LedNBHeaderText(FNotebook, ACell);
    NBTag(Head, NBTagHeader, ACell);
  finally
    FMaster.EndUpdate;
    Outs.Free;
  end;

  for i := 0 to FViews.Count - 1 do
  begin
    V := TLedEdit(FViews[i]);
    Carets[i].y := Min(Carets[i].y, FMaster.Lines.Count);
    V.CaretXY := Carets[i];
  end;

  if Assigned(FOnCell) then FOnCell(Self, ACell);
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

{ What a line is, for the highlighter.  From the tags, which is to say from
  what was rendered rather than from what the line looks like: a markdown
  cell whose text happens to read like a header is still text. }
{ Which language a cell's source is in.

  The notebook's own, unless the cell opens with a cell magic that names
  another.  A %%octave cell in a Python notebook is Octave, and these
  notebooks are full of them -- the whole point of the magic is that one
  file runs two languages.  A magic that is not a language -- %%timeit,
  %%capture -- names nothing LED can colour, and the test for that is simply
  whether LED has a highlighter for the word. }
function TLedDocument.NBCellLanguage(ACell, AHeaderLine: Integer): string;
var
  First: string;
begin
  Result := '';
  if (ACell < 0) or (ACell >= FNotebook.CellCount) then Exit;
  if FNotebook.CellKind(ACell) = nbkMarkdown then Exit('markdown');

  { The cell's first line is the one after its header, and it is read from
    the buffer rather than from the notebook: the reader may have just typed
    the magic, and the colouring follows as they type. }
  First := '';
  if (AHeaderLine >= 0) and (AHeaderLine + 1 < FMaster.Lines.Count) then
    First := FMaster.Lines[AHeaderLine + 1];
  { Which name goes with which highlighter is Led.Core.NBMagic's business,
    including the fall back to Python for a notebook that names nothing. }
  Result := LedNBCellLanguage(First, FNotebook.LanguageName);
end;

function TLedDocument.NBLineKind(ALine: Integer; out ACell: Integer;
  out ALang: string): TLedNBLine;
var
  T: PtrInt;
  Head: Integer;
begin
  ACell := -1;
  ALang := '';
  Result := nblGap;
  if not FIsNotebook then Exit;

  T := NBTagOf(ALine);
  if T = 0 then
  begin
    Head := NBHeaderAbove(ALine, ACell);
    if Head < 0 then Exit;
    Result := nblSource;
    ALang := NBCellLanguage(ACell, Head);
    { A magic is Jupyter's word, not the language's: %%shell says what the
      cell is, %load_ext and !pip are instructions to the front end, and none
      of the three is code the highlighter should try to read.  They are
      drawn the way a comment is drawn, which is how a notebook front end
      draws them and what they are. }
    if (ALine < FMaster.Lines.Count) and
       LedNBIsMagicLine(FMaster.Lines[ALine], ALine = Head + 1,
         LedNBCellMagic(NBLineText(Head + 1)) = '') then
      Result := nblMagic;
  end
  else
    case (-T) mod NBTagKinds of
      NBTagHeader: begin ACell := (-T) div NBTagKinds; Result := nblHeader; end;
      NBTagOut:    begin ACell := (-T) div NBTagKinds; Result := nblOutput; end;
      NBTagErr:    begin ACell := (-T) div NBTagKinds; Result := nblError; end;
    else
      Exit;
    end;

  { The label line and the output lines share a tag; the label is the one
    that starts with the word. }
  if (Result = nblOutput) and (ALine < FMaster.Lines.Count) and
     (Pos('out ', FMaster.Lines[ALine]) = 1) then
    Result := nblOutLabel;
end;

function TLedDocument.NBLineText(ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine < FMaster.Lines.Count) then
    Result := FMaster.Lines[ALine];
end;

{ The notebook highlighter and both of the language ones inside it.  Its own
  instances, so LedRetheme -- which re-themes the shared ones -- does not
  reach them. }
procedure TLedDocument.NBTheme;
var
  i: Integer;
begin
  if FNBHigh = nil then Exit;
  LedApplyThemeToHighlighter(LedCurrentTheme, FNBHigh);
  for i := 0 to FNBHigh.InnerCount - 1 do
    if FNBHigh.Inner(i) <> nil then
      LedApplyThemeToHighlighter(LedCurrentTheme, FNBHigh.Inner(i));
end;

{ ---- running cells ---- }

function TLedDocument.NBKernelState: TLedKernelState;
begin
  if FKernel = nil then Result := lksOff else Result := FKernel.State;
end;

function TLedDocument.NBKernelStatus: string;
begin
  Result := '';
  if not FIsNotebook then Exit;
  if FKernel = nil then Exit('No kernel');
  case FKernel.State of
    lksStarting: Result := Format('Starting %s', [FKernel.KernelName]);
    lksIdle:     Result := Format('%s: idle', [FKernel.KernelName]);
    lksBusy:     Result := Format('%s: running', [FKernel.KernelName]);
    lksFailed:   Result := Format('Kernel failed: %s', [FKernel.LastError]);
  else
    Result := 'No kernel';
  end;
end;

function TLedDocument.NBKernelStart(out AWhy: string): Boolean;
var
  Name_: string;
begin
  AWhy := '';
  Result := False;
  if not FIsNotebook then
  begin
    AWhy := 'this document is not a notebook';
    Exit;
  end;

  if (FKernel <> nil) and FKernel.Running and
     (FKernel.State <> lksFailed) then Exit(True);

  { The kernel the notebook was written against, and Python if it does not
    say: a notebook with no kernelspec is almost always one somebody wrote
    by hand or converted, and python3 is the kernel they meant. }
  Name_ := FNotebook.KernelName;
  if Name_ = '' then Name_ := 'python3';

  if FKernel = nil then
  begin
    FKernel := TLedKernel.Create;
    FKernel.OnEvent := @NBKernelEvent;
  end;
  Result := FKernel.Start(Name_, AWhy);

  if Result then
  begin
    if FKernelTimer = nil then
    begin
      FKernelTimer := TTimer.Create(Self);
      { Often enough that output appears as it is printed, seldom enough that
        a cell printing thousands of lines re-renders a few times a second
        rather than a few thousand. }
      FKernelTimer.Interval := 60;
      FKernelTimer.OnTimer := @NBKernelTick;
    end;
    FKernelTimer.Enabled := True;
  end;
  if Assigned(FOnKernel) then FOnKernel(Self);
end;

procedure TLedDocument.NBKernelStop;
begin
  if FKernelTimer <> nil then FKernelTimer.Enabled := False;
  if FKernel <> nil then FKernel.Shutdown;
  SetLength(FRuns, 0);
  if Assigned(FOnKernel) then FOnKernel(Self);
end;

procedure TLedDocument.NBKernelInterrupt;
begin
  if FKernel <> nil then FKernel.Interrupt;
end;

procedure TLedDocument.NBKernelRestart;
begin
  if FKernel = nil then Exit;
  { The runs in flight belong to the session that is going away. }
  SetLength(FRuns, 0);
  FKernel.Restart;
  if Assigned(FOnKernel) then FOnKernel(Self);
end;

procedure TLedDocument.NBKernelTick(Sender: TObject);
begin
  if FKernel = nil then Exit;
  FKernel.Poll;
  { The re-render happens here rather than as each output arrives: a cell
    printing a thousand lines would otherwise rebuild its block a thousand
    times. }
  NBFlushDirty;
  if (FKernel.State in [lksOff, lksFailed]) and (Length(FRuns) = 0) and
     (FKernelTimer <> nil) then
    FKernelTimer.Enabled := FKernel.Running;
end;

function TLedDocument.NBCellOfRun(AId: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FRuns) do
    if FRuns[i].Id = AId then Exit(FRuns[i].Cell);
end;

procedure TLedDocument.NBMarkDirty(ACell: Integer);
var
  i: Integer;
begin
  for i := 0 to High(FDirtyCells) do
    if FDirtyCells[i] = ACell then Exit;
  SetLength(FDirtyCells, Length(FDirtyCells) + 1);
  FDirtyCells[High(FDirtyCells)] := ACell;
end;

procedure TLedDocument.NBFlushDirty;
var
  i: Integer;
begin
  if Length(FDirtyCells) = 0 then Exit;
  for i := 0 to High(FDirtyCells) do
    NBRefreshCell(FDirtyCells[i]);
  SetLength(FDirtyCells, 0);
end;

procedure TLedDocument.NBKernelEvent(Sender: TObject;
  const AEvent: TLedKernelEvent);
var
  Cell, i, j: Integer;
begin
  case AEvent.Kind of
    lkeReady, lkeFailed, lkeStatus:
      if Assigned(FOnKernel) then FOnKernel(Self);

    lkeOutput:
      begin
        Cell := NBCellOfRun(AEvent.Id);
        if Cell < 0 then Exit;
        { Cloned: the event's output belongs to the poll that read it and is
          freed when the poll moves on, while the notebook keeps what it is
          given until the file is saved. }
        FNotebook.AddCellOutput(Cell, TJSONObject(AEvent.Output.Clone));
        FNBDirty := True;
        NBMarkDirty(Cell);
      end;

    lkeDone:
      begin
        Cell := NBCellOfRun(AEvent.Id);
        for i := 0 to High(FRuns) do
          if FRuns[i].Id = AEvent.Id then
          begin
            for j := i to High(FRuns) - 1 do FRuns[j] := FRuns[j + 1];
            SetLength(FRuns, Length(FRuns) - 1);
            Break;
          end;
        if Cell >= 0 then
        begin
          if AEvent.Count >= 0 then
          begin
            FNotebook.SetCellExecutionCount(Cell, AEvent.Count);
            FNBDirty := True;
          end;
          NBMarkDirty(Cell);
          NBFlushDirty;
        end;
        if Assigned(FOnKernel) then FOnKernel(Self);
      end;
  end;
end;

function TLedDocument.NBRunCell(ACell: Integer; out AWhy: string): Boolean;
var
  Id: Integer;
  Source: string;
begin
  Result := False;
  AWhy := '';
  if not FIsNotebook then
  begin
    AWhy := 'this document is not a notebook';
    Exit;
  end;
  if (ACell < 0) or (ACell >= FNotebook.CellCount) then
  begin
    AWhy := 'the caret is not in a cell';
    Exit;
  end;
  if FNotebook.CellKind(ACell) <> nbkCode then
  begin
    { Running a markdown cell is Jupyter's word for rendering it, and there
      is nothing here to render it into: the buffer shows its text, which is
      what a reader of a notebook in an editor wants anyway. }
    AWhy := 'only a code cell can be run';
    Exit;
  end;

  if not NBKernelStart(AWhy) then Exit;

  { What runs is what is on the page, not what was last saved -- and with
    Colab's own magics turned into the ones a kernel here understands; see
    LedNBRunnableSource.  The cell in the file is not changed. }
  NBSyncFromBuffer;
  Source := LedNBRunnableSource(FNotebook.CellSource(ACell));

  Id := FKernel.Run(Source);
  if Id < 0 then
  begin
    AWhy := 'the kernel is not listening';
    Exit;
  end;

  SetLength(FRuns, Length(FRuns) + 1);
  FRuns[High(FRuns)].Id := Id;
  FRuns[High(FRuns)].Cell := ACell;

  { Cleared the moment it is sent, the way Jupyter does: what is on screen
    under a running cell should be that run's output and not the last one's. }
  FNotebook.ClearCellOutputs(ACell);
  FNotebook.SetCellExecutionCount(ACell, -1);
  FNBDirty := True;
  NBRefreshCell(ACell);

  if Assigned(FOnKernel) then FOnKernel(Self);
  Result := True;
end;

function TLedDocument.NBRunAll(out AWhy: string): Boolean;
var
  i: Integer;
  Ran: Boolean;
begin
  Result := False;
  AWhy := '';
  if not FIsNotebook then
  begin
    AWhy := 'this document is not a notebook';
    Exit;
  end;
  Ran := False;
  for i := 0 to FNotebook.CellCount - 1 do
    if FNotebook.CellKind(i) = nbkCode then
      { Sent one after another without waiting: the kernel runs them in the
        order they arrive, which is the order they are on the page. }
      if NBRunCell(i, AWhy) then Ran := True;
  Result := Ran;
  if Ran then AWhy := '';
end;

function TLedDocument.TakeNotebookError: string;
begin
  Result := FNBError;
  FNBError := '';
end;

{ The line a record is on now, or -1.  Linear: this runs once per click. }
function TLedDocument.BJLineForOffset(AOffset: PtrUInt): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FBJRows) do
    if FBJRows[i].Offset = AOffset then Exit(i);
  Result := -1;
end;

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

function TLedDocument.IsHexDump: Boolean;
begin
  Result := FIsBinary and (not FIsBJData);
end;

function TLedDocument.TakeBJDataError(out AOffset: PtrUInt): string;
begin
  { Read and clear.  The window asks after opening a file, and a message that
    stayed set would come back on the next redraw or the next focus change --
    a reload is what should report it again. }
  Result := FBJError;
  AOffset := FBJErrorOffset;
  FBJError := '';
end;

procedure TLedDocument.LoadFromFile(const AFileName: string;
  const AForcedEncoding: string);
var
  Text, Cached, Raw: string;
  Encodings: TStringList;
  Err: TLedFileError;
  Binary, BJData, Detecting: Boolean;
  NBErr: string;
  BJRows: TLedBJRows;
  BJErr: string;
  BJOffset: PtrUInt;
  NewInfo: TLedTextInfo;
begin
  { The bytes first, because whether this is text at all is decided from
    them and a hex dump is made from them.  One read either way: the text
    path decodes what is already in hand rather than opening the file
    again. }
  Raw := LedReadRawFile(AFileName);

  { Detection is off when the user has asked for something specific: Open as
    Text, or a named encoding.  Both mean "show me the text editor". }
  Detecting := (not FForceText) and (AForcedEncoding = '');

  { BJData is asked about before LedLooksBinary, not after.  A BJData file is
    full of NULs and would be claimed by the hex path every time.

    The extension proposes and the parse disposes: a .bnii that is not really
    BJData, or is a truncated download, falls through to the dump rather than
    refusing to open.  When that happens BJErr and BJOffset say why and
    where, and the window shows them. }
  BJData := False;
  BJRows := nil;
  BJErr := '';
  BJOffset := 0;
  if Detecting and (Raw <> '') and LedBJIsBJDataName(AFileName) then
    BJData := LedBJTryWalk(Raw, BJRows, BJErr, BJOffset);

  { A file that was meant to be BJData and is not goes to the dump even if it
    has no NUL in the first few kilobytes -- what is wrong with it is a thing
    to look at byte by byte, and the text editor cannot show that. }
  Binary := (not BJData) and Detecting and
    ((BJErr <> '') or LedLooksBinary(Raw));

  { Worked out into locals, and only written to the document once it has all
    succeeded.

    Committing as it went was a way to lose a file.  FIsBinary and FBytes were
    cleared on the way into the text branch, which then raised on a decode it
    could not do -- so a dump that failed to reopen as text was left claiming
    not to be binary, with no bytes, and the hex dump still in the buffer.
    SaveToFile believed it: it took the text path and wrote the dump, in
    ASCII, over the user's binary.  Measured on a twenty-byte file, reopened
    with an encoding it could not be read in: it came back a hundred and
    sixty-two bytes of hexadecimal.

    Reachable from File > Open as Text on anything with a UTF-32 BOM, and from
    Reopen with Encoding on any binary at all -- both of which report the
    error and leave the document open, which is exactly when the next Ctrl+S
    happens. }
  NewInfo := LedDefaultTextInfo;
  if BJData or Binary then
  begin
    { No decoding, no encoding, no line-ending convention: the buffer holds a
      rendering of the file rather than the file, and saying otherwise would
      invite the save path to write it back. }
    if BJData then
      { The rows are already walked, so this renders them rather than
        reading the file a second time. }
      Text := LedBJRowsText(BJRows)
    else
      Text := LedHexDump(Raw);
    { Claim neither.  The buffer is a rendering of the bytes, so it has no
      encoding and no line-ending convention of its own, and recording the
      defaults would put a guess into the session file and onto the status
      bar as though it were known. }
    NewInfo.Encoding := '';
    NewInfo.LineEnd := leUnknown;
  end
  else
  begin
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
      Err := LedDecodeText(Raw, AForcedEncoding, Cached, Encodings, Text, NewInfo);
      if Err <> lfeNone then
        raise ELedFileError.Create(Err, AFileName);
    finally
      Encodings.Free;
    end;
  end;

  { A notebook, if the name says so and the contents agree.  Asked after the
    decode because a notebook is a text file: it is read as text like any
    other, and what makes it a notebook is that the text parses.

    A .ipynb that does not parse opens as plain text with the reason on
    offer -- the same bargain the structure view makes with a BJData file
    that will not decode.  The reader can still see the file, and the editor
    is not pretending to understand it. }
  FIsNotebook := False;
  FNBError := '';
  FNBDirty := False;
  FreeAndNil(FNotebook);
  if Detecting and LedNBIsNotebookName(AFileName) and
     (not Binary) and (not BJData) then
  begin
    FNotebook := TLedNotebook.Create;
    if FNotebook.LoadFromText(Text, NBErr) then
      FIsNotebook := True
    else
    begin
      FNBError := NBErr;
      FreeAndNil(FNotebook);
    end;
  end;

  { Past every raise: the document may be changed now. }
  FIsBinary := Binary or BJData;
  FIsBJData := BJData;
  FBJRows := BJRows;
  FBJError := BJErr;
  FBJErrorOffset := BJOffset;
  if FIsBinary then FBytes := Raw else FBytes := '';
  FHexUndoCount := 0;
  FBJUndoCount := 0;
  SetLength(FBJUndo, 0);
  FHexDirty := False;
  FInfo := NewInfo;

  FMaster.BeginUpdate;
  try
    FMaster.Lines.Text := Text;
    FMaster.ClearUndo;
    FMaster.Modified := False;
  finally
    FMaster.EndUpdate;
  end;

  { The buffer a notebook shows is its cells, not its JSON.  Done after the
    plain text has gone in, so that a render which fails leaves the file
    readable rather than leaving the buffer empty. }
  if FIsNotebook then NBRender;

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
  if FIsNotebook then
    { Not JSON, whatever the extension says: the buffer holds the cells, and
      each of them is coloured in its own language rather than the file's. }
    FConfig.SetStr(LedSetLang, '', lcsAuto)
  else if not FIsBinary then
  begin
    ReadModelines;
    DetectLanguage;
  end
  else if FIsBJData then
    { Except the structure view, which is coloured from the walk that built
      it rather than from a language: see ApplyLanguage. }
    FConfig.SetStr(LedSetLang, '', lcsAuto);
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
    are read-only, and an undo of LED's own is what SetHexByte keeps. }
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
  { A dump only.  The offsets a structure view shows are record starts, not
    a fixed grid, so poking a byte here and re-rendering "its row" would put
    hexadecimal into the middle of the structure. }
  if not IsHexDump then Exit;
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
  Result := IsHexDump and (FHexUndoCount > 0);
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
  if (not IsHexDump) or (Length(AChar) <> 1) then Exit;
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
    FBJUndoCount := 0;
    SetLength(FBJUndo, 0);
    NoteDiskState;
    if Assigned(FOnChanged) then FOnChanged(Self);
    Exit;
  end;
  { A notebook saves the notebook.  The buffer is a rendering of it -- with
    headers and outputs in it that are not in the file -- so writing the
    buffer would write those lines into somebody's JSON.  What the reader
    typed is in the cells' source lines, and that is copied back first. }
  if FIsNotebook then
  begin
    NBSyncFromBuffer;
    LedSaveTextFile(AFileName, FNotebook.SaveToText, FInfo,
      LedPrefs.GetBool(LedPrefMakeBackups, False));
    FFileName := AFileName;
    FMaster.Modified := False;
    FNBDirty := False;
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

{ The document already open on AFileName, or nil.

  Compared with the symbolic links followed, not merely expanded.  Two names
  for one file is the ordinary case on this kind of tree -- a home directory
  that links into a mounted volume, a project reached through both -- and a
  match on the literal path opens the file a second time: two documents over
  one file, each able to save over the other.  ResolveLink falls back to the
  expanded name when a path cannot be resolved, so a file that does not exist
  yet still compares sensibly. }
{$IFDEF UNIX}
function realpath(path: PChar; resolved: PChar): PChar; cdecl; external 'c';
{$ENDIF}

function TLedDocuments.FindByFileName(const AFileName: string): TLedDocument;

  function ResolveLink(const APath: string): string;
  {$IFDEF UNIX}
  var
    Buf: array[0..4095] of Char;
    P: PChar;
  {$ENDIF}
  begin
    Result := ExpandFileName(APath);
    if Result = '' then Exit;
    {$IFDEF UNIX}
    { realpath(3) rather than LazFileUtils' TryReadAllLinks, which resolves a
      link only in the final component: the case that matters here is a
      *directory* in the middle of the path being the link -- a home
      directory that points into a mounted volume -- and that one it returns
      unchanged.  Measured: /tmp/x-viadir/link/a.c came back as itself.

      realpath answers nil for a path that does not exist yet, which a
      Save As target legitimately is, so the expanded name stands in. }
    P := realpath(PChar(Result), @Buf[0]);
    if P <> nil then Result := string(P);
    {$ENDIF}
  end;

var
  i: Integer;
  Wanted: string;
begin
  Wanted := ResolveLink(AFileName);
  for i := 0 to FItems.Count - 1 do
    if (not Items[i].IsUntitled) and
       (ResolveLink(Items[i].FileName) = Wanted) then
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

function LedDocumentIsOpen(ADoc: TLedDocument): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (ADoc = nil) or (FDocuments = nil) then Exit;
  for i := 0 to FDocuments.Count - 1 do
    if FDocuments[i] = ADoc then Exit(True);
end;

finalization
  FDocuments.Free;
  FUserConfig.Free;

end.
