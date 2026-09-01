{ led - a light editor.  Crash recovery for unsaved work.

  Until this existed, killing led lost everything unsaved: session.json holds
  paths and caret positions but no text, skips untitled documents outright,
  is off by default, and is written from the close handler -- which a kill
  never reaches.  An untitled buffer was gone completely and a modified file
  reverted to its last save.  The "<name>~" backup does not help; that is the
  contents *before* the last successful save, not the work in the window.

  The shape is a journal, not a save.  Every dirty document is periodically
  written to <config>/recovery, and the entry is dropped the moment the
  document is saved or closed.  A clean exit clears the directory, so
  anything still there at startup means the last run did not get to exit --
  no separate "was I running?" marker is needed, and there is no state to get
  out of step with reality.

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
  end;
  TLedRecoveryEntries = array of TLedRecoveryEntry;

  TLedRecovery = class
  private
    FDirOverride: string;
    function GetDir: string;
    function MetaPath(const AId: string): string;
    function TextPath(const AId: string): string;
    function ReadEntry(const AId: string; out AEntry: TLedRecoveryEntry): Boolean;
  public
    { ADirectory defaults to <config>/recovery.  The directory is created
      lazily, on the first Store, so merely starting led does not litter. }
    constructor Create(const ADirectory: string = '');

    { Write, or overwrite, the journal entry for one document.  AId must be
      stable for the life of the document; see LedRecoveryId. }
    procedure Store(const AEntry: TLedRecoveryEntry; const AText: string);

    { Forget one document: it was saved, or closed, or the user declined to
      recover it.  Silent when there is nothing to forget. }
    procedure Discard(const AId: string);

    { Forget everything.  Called on a clean exit, which is what makes a
      non-empty directory at startup mean "we were killed". }
    procedure Clear;

    { Every committed entry, oldest first.  Sweeps incomplete and orphaned
      files as it goes, so a directory that only holds wreckage comes back
      empty and the user is not asked about nothing. }
    function Scan: TLedRecoveryEntries;

    { The recovered text for an entry from Scan. }
    function LoadText(const AEntry: TLedRecoveryEntry): string;

    { True when Scan would return at least one entry.  Cheaper than Scan for
      the common "nothing to do" case at startup. }
    function HasPending: Boolean;

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

constructor TLedRecovery.Create(const ADirectory: string);
begin
  inherited Create;
  FDirOverride := ADirectory;
end;

function TLedRecovery.GetDir: string;
begin
  if FDirOverride <> '' then
    Result := FDirOverride
  else
    Result := LedConfigFile('recovery');
end;

function TLedRecovery.MetaPath(const AId: string): string;
begin
  Result := IncludeTrailingPathDelimiter(Dir) + AId + MetaExt;
end;

function TLedRecovery.TextPath(const AId: string): string;
begin
  Result := IncludeTrailingPathDelimiter(Dir) + AId + TextExt;
end;

procedure TLedRecovery.Store(const AEntry: TLedRecoveryEntry;
  const AText: string);
var
  Obj: TJSONObject;
begin
  if AEntry.Id = '' then Exit;
  if not DirectoryExists(Dir) then
    if not ForceDirectories(Dir) then
      Exit;   { nowhere to write; journaling is best-effort by nature }

  { Text first: the metadata written afterwards is what makes the pair
    count, so a crash between the two loses the entry rather than
    resurrecting half a buffer. }
  LedWriteFileAtomic(TextPath(AEntry.Id), AText);

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
    LedWriteFileAtomic(MetaPath(AEntry.Id), Obj.FormatJSON);
  finally
    Obj.Free;
  end;
end;

procedure TLedRecovery.Discard(const AId: string);
begin
  if AId = '' then Exit;
  DeleteFile(MetaPath(AId));
  DeleteFile(MetaPath(AId) + '.bak');
  DeleteFile(MetaPath(AId) + '.tmp');
  DeleteFile(TextPath(AId));
  DeleteFile(TextPath(AId) + '.bak');
  DeleteFile(TextPath(AId) + '.tmp');
end;

procedure TLedRecovery.Clear;
var
  Rec: TSearchRec;
begin
  if not DirectoryExists(Dir) then Exit;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, Rec) = 0 then
    try
      repeat
        if (Rec.Name = '.') or (Rec.Name = '..') then Continue;
        if (Rec.Attr and faDirectory) <> 0 then Continue;
        DeleteFile(IncludeTrailingPathDelimiter(Dir) + Rec.Name);
      until FindNext(Rec) <> 0;
    finally
      FindClose(Rec);
    end;
  { The directory itself goes too, so an untouched installation has no
    recovery directory at all rather than an empty one. }
  RemoveDir(Dir);
end;

function TLedRecovery.ReadEntry(const AId: string;
  out AEntry: TLedRecoveryEntry): Boolean;
var
  Stream: TFileStream;
  Data: TJSONData;
  Obj: TJSONObject;
  Txt: string;
  Actual: Int64;
begin
  Result := False;
  AEntry := Default(TLedRecoveryEntry);

  Txt := TextPath(AId);
  if not FileExists(MetaPath(AId)) then Exit;
  if not FileExists(Txt) then Exit;

  Data := nil;
  try
    Stream := TFileStream.Create(MetaPath(AId), fmOpenRead or fmShareDenyNone);
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
    AEntry.FileName    := Obj.Get('fileName', '');
    AEntry.DisplayName := Obj.Get('displayName', '');
    AEntry.Encoding    := Obj.Get('encoding', '');
    AEntry.LineEnding  := Obj.Get('lineEnding', '');
    AEntry.Language    := Obj.Get('language', '');
    AEntry.Line        := Obj.Get('line', 1);
    AEntry.Column      := Obj.Get('column', 1);
    AEntry.TextLength  := Obj.Get('textLength', Int64(-1));
    AEntry.SavedAt     := FileDateToDateTime(FileAge(MetaPath(AId)));

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

function TLedRecovery.Scan: TLedRecoveryEntries;
var
  Rec: TSearchRec;
  Id, Base: string;
  E: TLedRecoveryEntry;
  Ids: TStringList;
  i: Integer;
begin
  Result := nil;
  if not DirectoryExists(Dir) then Exit;

  Ids := TStringList.Create;
  try
    Ids.Sorted := True;
    Ids.Duplicates := dupIgnore;
    Base := IncludeTrailingPathDelimiter(Dir);

    if FindFirst(Base + '*' + MetaExt, faAnyFile, Rec) = 0 then
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
      if ReadEntry(Ids[i], E) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := E;
      end
      else
        { Incomplete or unreadable: sweep it, so the user is never asked
          about an entry that cannot be restored. }
        Discard(Ids[i]);
  finally
    Ids.Free;
  end;
end;

function TLedRecovery.HasPending: Boolean;
begin
  Result := Length(Scan) > 0;
end;

function TLedRecovery.LoadText(const AEntry: TLedRecoveryEntry): string;
var
  Stream: TFileStream;
begin
  Result := '';
  if not FileExists(TextPath(AEntry.Id)) then Exit;
  try
    Stream := TFileStream.Create(TextPath(AEntry.Id),
      fmOpenRead or fmShareDenyNone);
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
