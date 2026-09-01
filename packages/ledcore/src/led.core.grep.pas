{ led - a light editor.  Search across files.

  medit shelled out to grep and find.  That is the single worst portability
  bug in the old code -- neither exists on a stock Windows -- and it also
  means the editor cannot skip what it knows is not worth searching.  So this
  walks the tree itself.

  Runs on a worker thread and reports matches back on the main one, because a
  search over a large tree must not freeze the window, and because the caller
  wants to see results as they arrive.

  No LCL dependency. }
unit Led.Core.Grep;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Masks, RegExpr;

type
  TLedGrepMatch = record
    FileName: string;
    Line: Integer;
    Text: string;
  end;

  TLedGrepMatchEvent = procedure(const AMatch: TLedGrepMatch) of object;
  TLedGrepDoneEvent = procedure(AFilesSearched, AMatches: Integer;
    ACancelled: Boolean) of object;

  TLedGrepOptions = record
    Pattern: string;
    Directory: string;
    FileMask: string;      // semicolon-separated globs; empty means every file
    Recursive: Boolean;
    MatchCase: Boolean;
    WholeWord: Boolean;
    Regex: Boolean;
    SkipVCS: Boolean;
    SkipBinary: Boolean;
    MaxMatches: Integer;   // 0 means no limit
  end;

function LedDefaultGrepOptions: TLedGrepOptions;

type
  TLedGrepThread = class(TThread)
  private
    FOptions: TLedGrepOptions;
    FOnMatch: TLedGrepMatchEvent;
    FOnDone: TLedGrepDoneEvent;
    FCurrent: TLedGrepMatch;
    FFiles: Integer;
    FMatches: Integer;
    FRegex: TRegExpr;
    FNeedle: string;
    procedure ReportMatch;
    procedure ReportDone;
    function LineMatches(const ALine: string): Boolean;
    procedure SearchFile(const APath: string);
    procedure SearchDir(const ADir: string);
    function WantsFile(const AName: string): Boolean;
    function WantsDir(const AName: string): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AOptions: TLedGrepOptions);
    destructor Destroy; override;
    property OnMatch: TLedGrepMatchEvent read FOnMatch write FOnMatch;
    property OnDone: TLedGrepDoneEvent read FOnDone write FOnDone;
  end;

{ True when the buffer looks like something no one wants to see in a search
  result.  A NUL byte in the first few KB is the same test grep uses. }
function LedLooksBinary(const AData: string): Boolean;

implementation

const
  { Directories that are never worth searching.  medit skipped the first
    four; the rest are the ones that make a search over a modern working tree
    take minutes instead of seconds. }
  SkippedDirs: array[0..9] of string = (
    '.git', '.svn', '.hg', 'CVS', '.bzr',
    'node_modules', '__pycache__', '.tox', 'lib', '.cache');

function LedDefaultGrepOptions: TLedGrepOptions;
begin
  Result := Default(TLedGrepOptions);
  Result.Recursive := True;
  Result.SkipVCS := True;
  Result.SkipBinary := True;
  Result.MaxMatches := 5000;
end;

function LedLooksBinary(const AData: string): Boolean;
var
  i, Limit: Integer;
begin
  Limit := Length(AData);
  if Limit > 8192 then Limit := 8192;
  for i := 1 to Limit do
    if AData[i] = #0 then Exit(True);
  Result := False;
end;

constructor TLedGrepThread.Create(const AOptions: TLedGrepOptions);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOptions := AOptions;
  if FOptions.MatchCase then
    FNeedle := FOptions.Pattern
  else
    FNeedle := LowerCase(FOptions.Pattern);
end;

destructor TLedGrepThread.Destroy;
begin
  FRegex.Free;
  inherited Destroy;
end;

procedure TLedGrepThread.ReportMatch;
begin
  if Assigned(FOnMatch) then FOnMatch(FCurrent);
end;

procedure TLedGrepThread.ReportDone;
begin
  if Assigned(FOnDone) then FOnDone(FFiles, FMatches, Terminated);
end;

function TLedGrepThread.LineMatches(const ALine: string): Boolean;
var
  Hay: string;
  P: Integer;

  function IsWordChar(C: Char): Boolean;
  begin
    Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_'];
  end;

begin
  if FOptions.Regex then
  begin
    Result := False;
    try
      Result := FRegex.Exec(ALine);
    except
      Result := False;
    end;
    Exit;
  end;

  if FOptions.MatchCase then Hay := ALine else Hay := LowerCase(ALine);
  P := Pos(FNeedle, Hay);
  Result := P > 0;
  if Result and FOptions.WholeWord then
  begin
    { A whole-word hit needs a non-word character on both sides, or an edge. }
    if (P > 1) and IsWordChar(Hay[P - 1]) then Exit(False);
    if (P + Length(FNeedle) <= Length(Hay)) and
       IsWordChar(Hay[P + Length(FNeedle)]) then Exit(False);
  end;
end;

function TLedGrepThread.WantsFile(const AName: string): Boolean;
var
  Parts: TStringArray;
  i: Integer;
begin
  if FOptions.FileMask = '' then Exit(True);
  Parts := FOptions.FileMask.Split([';', ',']);
  for i := 0 to High(Parts) do
    if (Trim(Parts[i]) <> '') and MatchesMask(AName, Trim(Parts[i])) then
      Exit(True);
  Result := False;
end;

function TLedGrepThread.WantsDir(const AName: string): Boolean;
var
  i: Integer;
begin
  Result := True;
  if not FOptions.SkipVCS then Exit;
  for i := Low(SkippedDirs) to High(SkippedDirs) do
    if SameText(AName, SkippedDirs[i]) then Exit(False);
end;

procedure TLedGrepThread.SearchFile(const APath: string);
var
  Stream: TFileStream;
  Data: string;
  Lines: TStringList;
  i: Integer;
begin
  if Terminated then Exit;
  Data := '';
  try
    Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      { A file larger than 16 MB is almost never something you meant to
        search, and reading it costs more than the answer is worth. }
      if Stream.Size > 16 * 1024 * 1024 then Exit;
      SetLength(Data, Stream.Size);
      if Stream.Size > 0 then
        Stream.ReadBuffer(Data[1], Stream.Size);
    finally
      Stream.Free;
    end;
  except
    { Unreadable is not an error worth stopping for. }
    Exit;
  end;

  Inc(FFiles);
  if FOptions.SkipBinary and LedLooksBinary(Data) then Exit;

  Lines := TStringList.Create;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    Lines.Text := StringReplace(
      StringReplace(Data, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
    for i := 0 to Lines.Count - 1 do
    begin
      if Terminated then Exit;
      if not LineMatches(Lines[i]) then Continue;
      FCurrent.FileName := APath;
      FCurrent.Line := i + 1;
      FCurrent.Text := Lines[i];
      Inc(FMatches);
      Synchronize(@ReportMatch);
      if (FOptions.MaxMatches > 0) and (FMatches >= FOptions.MaxMatches) then
      begin
        Terminate;
        Exit;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TLedGrepThread.SearchDir(const ADir: string);
var
  Search: TSearchRec;
  Dir: string;
  SubDirs: TStringList;
  i: Integer;
begin
  if Terminated then Exit;
  Dir := IncludeTrailingPathDelimiter(ADir);
  SubDirs := TStringList.Create;
  try
    if FindFirst(Dir + '*', faAnyFile, Search) = 0 then
    begin
      repeat
        if (Search.Name = '.') or (Search.Name = '..') then Continue;
        if (Search.Attr and faDirectory) <> 0 then
        begin
          if FOptions.Recursive and WantsDir(Search.Name) then
            SubDirs.Add(Dir + Search.Name);
        end
        else if WantsFile(Search.Name) then
          SearchFile(Dir + Search.Name);
      until Terminated or (FindNext(Search) <> 0);
      FindClose(Search);
    end;

    { Directories are walked after the files in this one, so results appear
      breadth-first and the nearest matches show up first. }
    for i := 0 to SubDirs.Count - 1 do
    begin
      if Terminated then Break;
      SearchDir(SubDirs[i]);
    end;
  finally
    SubDirs.Free;
  end;
end;

procedure TLedGrepThread.Execute;
begin
  try
    if FOptions.Regex then
    begin
      FRegex := TRegExpr.Create;
      FRegex.Expression := FOptions.Pattern;
      FRegex.ModifierI := not FOptions.MatchCase;
      try
        FRegex.Compile;
      except
        Terminate;
      end;
    end;

    if (not Terminated) and (FOptions.Pattern <> '') and
       DirectoryExists(FOptions.Directory) then
      SearchDir(FOptions.Directory);
  finally
    Synchronize(@ReportDone);
  end;
end;

end.
