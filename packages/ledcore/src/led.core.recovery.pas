{ LED - a lightweight editor.  Crash recovery for unsaved work.

  Until this existed, killing LED lost everything unsaved: session.json holds
  paths and caret positions but no text, skips untitled documents outright,
  is off by default, and is written from the close handler -- which a kill
  never reaches.  An untitled buffer was gone completely and a modified file
  reverted to its last save.  The "<name>~" backup does not help; that is the
  contents *before* the last successful save, not the work in the window.

  The shape is a journal, not a save.  Every dirty document is periodically
  written to the journal, and the entry is dropped the moment the document
  is saved or closed.  A clean exit clears it.

  Each running editor keeps a journal of its own: <config>/recovery/<session>/,
  beside <config>/recovery/<session>.lock, a file it holds open, locked, for
  as long as it runs.  The directory was once shared by every instance, and
  then a clean exit was not the signal it was meant to be: an editor still
  running wrote its dirty documents back twenty seconds after another had
  cleared them, and the next one to start offered to "recover" work that was
  open in a window, from a shutdown that had been clean.  Now a journal is
  left over only when its lock can be taken, which is exactly when the
  process that held it has gone -- the system releases a dead process's lock,
  and a reused process id cannot hold one it never took.  A clean exit clears
  its own journal and no other.

  Entries an older version wrote straight into <config>/recovery have no
  lock to ask.  They are offered once they have not been rewritten for
  LedRecoveryLegacyAge -- a running editor rewrites its entries every few
  seconds -- and left alone until then.

  Each entry is two files:

    <id>.txt    the text, exactly as the buffer holds it (UTF-8, LF)
    <id>.json   the metadata, and the byte length of the .txt

  The text goes first and the metadata second, so the metadata is the commit
  record: an entry counts only when its .json parses *and* the .txt on disk
  is the length the .json claims.  A crash midway through writing therefore
  leaves an entry that is ignored rather than one that restores a truncated
  buffer over the user's file.  Both are written through
  LedWriteFileAtomic.

  Text rather than JSON-embedded text because "open a 200 MB log" is a
  supported operation here, and escaping that into a JSON string would cost
  several times its size in memory for no benefit.

  No LCL dependency. }
unit Led.Core.Recovery;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, Led.Core.Paths;

const
  LedRecoveryVersion = 1;
  { How long an entry in the old shared layout must have gone unwritten
    before it counts as left by a dead editor; see above. }
  LedRecoveryLegacyAge = 5 / (24 * 60);

type
  { What is known about one unsaved buffer.  Everything except Text, which is
    read separately so a scan does not pull every recovered buffer into
    memory at once. }
  TLedRecoveryEntry = record
    Id: string;
    FileName: string;      // the document's path; '' when it was untitled
    DisplayName: string;   // what the tab said, e.g. "Untitled 1"
    Encoding: string;
    LineEnding: string;
    Language: string;
    Line, Column: Integer;
    SavedAt: TDateTime;    // UTC, when the journal entry was written
    TextLength: Int64;
    Folder: string;        // the journal it was read from
  end;
  TLedRecoveryEntries = array of TLedRecoveryEntry;

  TLedRecovery = class
  private
    FDirOverride: string;
    FSession: string;
    FLock: THandle;
    FLockPath: string;
    function GetDir: string;
    function GetSessionDir: string;
    function Held: Boolean;
    procedure Release;
    function TakeLock: Boolean;
    function ReadEntry(const AFolder, AId: string; out AEntry: TLedRecoveryEntry): Boolean;
    function ScanFolder(const AFolder: string; AMinAge: TDateTime): TLedRecoveryEntries;
  public
    { ADirectory defaults to <config>/recovery.  Nothing is created until
      the first Store, so merely starting LED does not litter. }
    constructor Create(const ADirectory: string = '');
    destructor Destroy; override;

    { Write, or overwrite, the journal entry for one document.  AId must be
      stable for the life of the document; see LedRecoveryId. }
    procedure Store(const AEntry: TLedRecoveryEntry; const AText: string);

    { Forget one document: it was saved, or closed, or the user declined to
      recover it.  Silent when there is nothing to forget. }
    procedure Discard(const AId: string);

    { Forget this editor's journal, and give up its lock.  Called on a
      clean exit; other editors' journals are not touched. }
    procedure Clear;

    { This editor's committed entries.  Sweeps incomplete files as it goes,
      so a journal that only holds wreckage comes back empty. }
    function Scan: TLedRecoveryEntries;

    { The entries editors that are no longer running left behind: what to
      offer at startup.  Never this editor's own, nor a running one's. }
    function ScanOrphans: TLedRecoveryEntries;

    { Delete entries from ScanOrphans -- recovered, or declined -- and the
      journals they leave empty. }
    procedure ForgetOrphans(const AEntries: TLedRecoveryEntries);

    { The recovered text for an entry from Scan or ScanOrphans. }
    function LoadText(const AEntry: TLedRecoveryEntry): string;

    { True when Scan would return at least one entry. }
    function HasPending: Boolean;

    { This editor's own journal folder, resolved as Dir is. }
    property SessionDir: string read GetSessionDir;

    { Resolved on every use rather than captured in the constructor.  The
      self-test installs its own configuration directory *after* the main
      form is built, so a journal object that had already resolved the path
      would keep pointing at the real ~/.config/led -- and would then offer
      the developer's genuine unsaved work in a modal dialog, hanging a
      headless run.  Late binding is what keeps the test honest. }
    property Dir: string read GetDir;
  end;

{ A journal id that is stable across runs for a saved file -- so a second
  crash overwrites the first entry instead of accumulating -- and unique per
  document for an untitled one, which has no identity to hash. }
function LedRecoveryId(const AFileName: string; AUntitledIndex: Integer): string;

implementation

const
  MetaExt = '.json';
  TextExt = '.txt';

function LedRecoveryId(const AFileName: string; AUntitledIndex: Integer): string;
var
  H: Cardinal;
  i: Integer;
begin
  if AFileName = '' then
    Exit(Format('untitled-%d', [AUntitledIndex]));

  { FNV-1a over the path.  A hash, not the path itself, because a path is not
    a legal file name and escaping one is more code than this. }
  H := 2166136261;
  for i := 1 to Length(AFileName) do
  begin
    H := H xor Byte(AFileName[i]);
    H := H * 16777619;
  end;
  Result := Format('file-%.8x', [H]);
end;

var
  SessionCounter: Integer = 0;

function JoinPath(const ADir, AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ADir) + AName;
end;

procedure DeleteFolderFiles(const AFolder: string);
var
  Rec: TSearchRec;
begin
  if not DirectoryExists(AFolder) then Exit;
  if FindFirst(JoinPath(AFolder, '*'), faAnyFile, Rec) = 0 then
    try
      repeat
        if (Rec.Name = '.') or (Rec.Name = '..') then Continue;
        if (Rec.Attr and faDirectory) <> 0 then Continue;
        DeleteFile(JoinPath(AFolder, Rec.Name));
      until FindNext(Rec) <> 0;
    finally
      FindClose(Rec);
    end;
  RemoveDir(AFolder);
end;

procedure DiscardIn(const AFolder, AId: string);
begin
  if AId = '' then Exit;
  DeleteFile(JoinPath(AFolder, AId + MetaExt));
  DeleteFile(JoinPath(AFolder, AId + MetaExt + '.bak'));
  DeleteFile(JoinPath(AFolder, AId + MetaExt + '.tmp'));
  DeleteFile(JoinPath(AFolder, AId + TextExt));
  DeleteFile(JoinPath(AFolder, AId + TextExt + '.bak'));
  DeleteFile(JoinPath(AFolder, AId + TextExt + '.tmp'));
end;

constructor TLedRecovery.Create(const ADirectory: string);
begin
  inherited Create;
  FDirOverride := ADirectory;
  FLock := THandle(-1);
  { The process and a counter name it: two journals in one process -- the
    tests make several -- are as separate as two editors. }
  Inc(SessionCounter);
  FSession := Format('session-%d-%d-%.6x', [GetProcessID, SessionCounter,
    Random($1000000)]);
end;

destructor TLedRecovery.Destroy;
begin
  { The lock only: a journal outlives the object that wrote it unless Clear
    said otherwise, which is what lets the next run find it. }
  Release;
  inherited Destroy;
end;

function TLedRecovery.GetDir: string;
begin
  if FDirOverride <> '' then
    Result := FDirOverride
  else
    Result := LedConfigFile('recovery');
end;

function TLedRecovery.GetSessionDir: string;
begin
  Result := JoinPath(Dir, FSession);
end;

function TLedRecovery.Held: Boolean;
begin
  { Held where Dir is now: the self-test moves the configuration directory
    after the journal object exists, and a lock taken in the old place says
    nothing about the new one. }
  Result := (FLock <> THandle(-1)) and
    (FLockPath = JoinPath(Dir, FSession + '.lock'));
end;

procedure TLedRecovery.Release;
begin
  if FLock <> THandle(-1) then
    FileClose(FLock);
  FLock := THandle(-1);
  FLockPath := '';
end;

function TLedRecovery.TakeLock: Boolean;
var
  Path: string;
begin
  Result := Held;
  if Result then Exit;
  Release;
  if not DirectoryExists(Dir) then
    if not ForceDirectories(Dir) then
      Exit;
  { The lock before the folder: a folder found without its lock is one
    whose editor died, never one whose editor is still starting. }
  Path := JoinPath(Dir, FSession + '.lock');
  if not FileExists(Path) then
    FileClose(FileCreate(Path));
  FLock := FileOpen(Path, fmOpenReadWrite or fmShareExclusive);
  if FLock = THandle(-1) then Exit;
  FLockPath := Path;
  Result := ForceDirectories(SessionDir);
end;

procedure TLedRecovery.Store(const AEntry: TLedRecoveryEntry;
  const AText: string);
var
  Obj: TJSONObject;
begin
  if AEntry.Id = '' then Exit;
  if not TakeLock then
    Exit;   { nowhere to write; journaling is best-effort by nature }

  { Text first: the metadata written afterwards is what makes the pair
    count, so a crash between the two loses the entry rather than
    resurrecting half a buffer. }
  LedWriteFileAtomic(JoinPath(SessionDir, AEntry.Id + TextExt), AText);

  Obj := TJSONObject.Create;
  try
    Obj.Add('version', LedRecoveryVersion);
    Obj.Add('id', AEntry.Id);
    Obj.Add('fileName', AEntry.FileName);
    Obj.Add('displayName', AEntry.DisplayName);
    Obj.Add('encoding', AEntry.Encoding);
    Obj.Add('lineEnding', AEntry.LineEnding);
    Obj.Add('language', AEntry.Language);
    Obj.Add('line', AEntry.Line);
    Obj.Add('column', AEntry.Column);
    Obj.Add('savedAt', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', AEntry.SavedAt));
    Obj.Add('textLength', Length(AText));
    LedWriteFileAtomic(JoinPath(SessionDir, AEntry.Id + MetaExt), Obj.FormatJSON);
  finally
    Obj.Free;
  end;
end;

procedure TLedRecovery.Discard(const AId: string);
begin
  DiscardIn(SessionDir, AId);
end;

procedure TLedRecovery.Clear;
var
  Lock: string;
begin
  DeleteFolderFiles(SessionDir);
  Lock := JoinPath(Dir, FSession + '.lock');
  Release;
  DeleteFile(Lock);
  { The directory itself goes too when nothing else is in it, so an
    untouched installation has no recovery directory at all. }
  RemoveDir(Dir);
end;

function TLedRecovery.ReadEntry(const AFolder, AId: string;
  out AEntry: TLedRecoveryEntry): Boolean;
var
  Stream: TFileStream;
  Data: TJSONData;
  Obj: TJSONObject;
  Meta, Txt: string;
  Actual: Int64;
begin
  Result := False;
  AEntry := Default(TLedRecoveryEntry);

  Meta := JoinPath(AFolder, AId + MetaExt);
  Txt := JoinPath(AFolder, AId + TextExt);
  if not FileExists(Meta) then Exit;
  if not FileExists(Txt) then Exit;

  Data := nil;
  try
    Stream := TFileStream.Create(Meta, fmOpenRead or fmShareDenyNone);
    try
      Data := GetJSON(Stream);
    finally
      Stream.Free;
    end;
  except
    { Unparseable metadata is wreckage, not an error to report. }
    FreeAndNil(Data);
    Exit;
  end;

  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    if Obj.Get('version', 0) <> LedRecoveryVersion then Exit;

    AEntry.Id          := AId;
    AEntry.Folder      := AFolder;
    AEntry.FileName    := Obj.Get('fileName', '');
    AEntry.DisplayName := Obj.Get('displayName', '');
    AEntry.Encoding    := Obj.Get('encoding', '');
    AEntry.LineEnding  := Obj.Get('lineEnding', '');
    AEntry.Language    := Obj.Get('language', '');
    AEntry.Line        := Obj.Get('line', 1);
    AEntry.Column      := Obj.Get('column', 1);
    AEntry.TextLength  := Obj.Get('textLength', Int64(-1));
    AEntry.SavedAt     := FileDateToDateTime(FileAge(Meta));

    { The length check is the commit test: it fails exactly when the text was
      being written as the process died. }
    Actual := 0;
    try
      Stream := TFileStream.Create(Txt, fmOpenRead or fmShareDenyNone);
      try
        Actual := Stream.Size;
      finally
        Stream.Free;
      end;
    except
      Exit;
    end;
    if (AEntry.TextLength < 0) or (Actual <> AEntry.TextLength) then Exit;

    Result := True;
  finally
    Data.Free;
  end;
end;

function TLedRecovery.ScanFolder(const AFolder: string;
  AMinAge: TDateTime): TLedRecoveryEntries;
var
  Rec: TSearchRec;
  Id: string;
  E: TLedRecoveryEntry;
  Ids: TStringList;
  i: Integer;
begin
  Result := nil;
  if not DirectoryExists(AFolder) then Exit;

  Ids := TStringList.Create;
  try
    Ids.Sorted := True;
    Ids.Duplicates := dupIgnore;

    if FindFirst(JoinPath(AFolder, '*' + MetaExt), faAnyFile, Rec) = 0 then
      try
        repeat
          if (Rec.Attr and faDirectory) <> 0 then Continue;
          Id := ChangeFileExt(Rec.Name, '');
          if Id <> '' then Ids.Add(Id);
        until FindNext(Rec) <> 0;
      finally
        FindClose(Rec);
      end;

    for i := 0 to Ids.Count - 1 do
      if ReadEntry(AFolder, Ids[i], E) then
      begin
        { too fresh to be anyone's but a running editor's: not yet }
        if (AMinAge > 0) and (Now - E.SavedAt < AMinAge) then Continue;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := E;
      end
      else if AMinAge = 0 then
        { Incomplete or unreadable: sweep it, so the user is never asked
          about an entry that cannot be restored.  Not in the shared old
          layout, whose half-written entry may be a running editor's. }
        DiscardIn(AFolder, Ids[i]);
  finally
    Ids.Free;
  end;
end;

function TLedRecovery.Scan: TLedRecoveryEntries;
begin
  Result := ScanFolder(SessionDir, 0);
end;

function TLedRecovery.ScanOrphans: TLedRecoveryEntries;
var
  Rec: TSearchRec;
  Lock, Folder: string;
  H: THandle;
  Found: TLedRecoveryEntries;
  i: Integer;
begin
  Result := nil;
  if not DirectoryExists(Dir) then Exit;

  if FindFirst(JoinPath(Dir, '*'), faDirectory, Rec) = 0 then
    try
      repeat
        if (Rec.Name = '.') or (Rec.Name = '..') then Continue;
        if (Rec.Attr and faDirectory) = 0 then Continue;
        if Rec.Name = FSession then Continue;
        Folder := JoinPath(Dir, Rec.Name);
        Lock := Folder + '.lock';
        { A lock that can be taken was held by a process that has gone; a
          folder with no lock never got one, and its editor is gone too. }
        if FileExists(Lock) then
        begin
          H := FileOpen(Lock, fmOpenReadWrite or fmShareExclusive);
          if H = THandle(-1) then Continue;    // its editor is running
          FileClose(H);
        end;
        Found := ScanFolder(Folder, 0);
        for i := 0 to High(Found) do
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := Found[i];
        end;
        if Length(Found) = 0 then
        begin
          { nothing restorable: the folder and its lock are wreckage }
          DeleteFolderFiles(Folder);
          DeleteFile(Lock);
        end;
      until FindNext(Rec) <> 0;
    finally
      FindClose(Rec);
    end;

  { the shared layout of older versions, once its writer has stopped }
  Found := ScanFolder(Dir, LedRecoveryLegacyAge);
  for i := 0 to High(Found) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Found[i];
  end;
end;

procedure TLedRecovery.ForgetOrphans(const AEntries: TLedRecoveryEntries);
var
  i: Integer;
  Folder: string;
begin
  for i := 0 to High(AEntries) do
  begin
    Folder := AEntries[i].Folder;
    if (Folder = '') or (Folder = SessionDir) then Continue;
    DiscardIn(Folder, AEntries[i].Id);
    { a dead editor's folder that is now empty goes, with its lock }
    if (ExcludeTrailingPathDelimiter(Folder) <> ExcludeTrailingPathDelimiter(Dir))
       and RemoveDir(Folder) then
      DeleteFile(Folder + '.lock');
  end;
  RemoveDir(Dir);
end;

function TLedRecovery.HasPending: Boolean;
begin
  Result := Length(Scan) > 0;
end;

function TLedRecovery.LoadText(const AEntry: TLedRecoveryEntry): string;
var
  Stream: TFileStream;
  Path: string;
begin
  Result := '';
  Path := JoinPath(AEntry.Folder, AEntry.Id + TextExt);
  if AEntry.Folder = '' then
    Path := JoinPath(SessionDir, AEntry.Id + TextExt);
  if not FileExists(Path) then Exit;
  try
    Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, Stream.Size);
      if Stream.Size > 0 then
        Stream.ReadBuffer(Result[1], Stream.Size);
    finally
      Stream.Free;
    end;
  except
    Result := '';
  end;
end;

end.
