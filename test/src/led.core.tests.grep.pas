{ led - a light editor.  Headless tests for the file search. }
unit Led.Core.Tests.Grep;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Led.Core.Grep;

type
  TTestGrep = class(TTestCase)
  private
    FDir: string;
    FHits: TStringList;
    FDone: Boolean;
    FFiles: Integer;
    procedure Got(const AMatch: TLedGrepMatch);
    procedure Done(AFilesSearched, AMatches: Integer; ACancelled: Boolean);
    procedure Write(const ARelPath, AContent: string);
    function RunSearch(const AOptions: TLedGrepOptions): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure FindsAPlainString;
    procedure CaseInsensitiveByDefault;
    procedure CaseSensitiveWhenAsked;
    procedure WholeWordRejectsSubstrings;
    procedure RegexSearch;
    procedure FileMaskLimitsTheSearch;
    procedure RecursionCanBeTurnedOff;
    procedure VcsDirectoriesAreSkipped;
    procedure BinaryFilesAreSkipped;
    procedure MaxMatchesStopsTheSearch;
    procedure BinaryDetection;
  end;

implementation

procedure TTestGrep.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-grep-%d%s', [GetProcessID, PathDelim]);
  ForceDirectories(FDir);
  FHits := TStringList.Create;
end;

procedure TTestGrep.TearDown;

  procedure Nuke(const ADir: string);
  var
    Info: TSearchRec;
  begin
    if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, Info) = 0 then
    begin
      repeat
        if (Info.Name = '.') or (Info.Name = '..') then Continue;
        if (Info.Attr and faDirectory) <> 0 then
          Nuke(IncludeTrailingPathDelimiter(ADir) + Info.Name)
        else
          DeleteFile(IncludeTrailingPathDelimiter(ADir) + Info.Name);
      until FindNext(Info) <> 0;
      FindClose(Info);
    end;
    RemoveDir(ADir);
  end;

begin
  FHits.Free;
  Nuke(ExcludeTrailingPathDelimiter(FDir));
end;

procedure TTestGrep.Write(const ARelPath, AContent: string);
var
  Full: string;
  L: TStringList;
begin
  Full := FDir + StringReplace(ARelPath, '/', PathDelim, [rfReplaceAll]);
  ForceDirectories(ExtractFileDir(Full));
  L := TStringList.Create;
  try
    L.Text := AContent;
    L.SaveToFile(Full);
  finally
    L.Free;
  end;
end;

procedure TTestGrep.Got(const AMatch: TLedGrepMatch);
begin
  FHits.Add(Format('%s:%d:%s', [ExtractFileName(AMatch.FileName),
    AMatch.Line, AMatch.Text]));
end;

procedure TTestGrep.Done(AFilesSearched, AMatches: Integer; ACancelled: Boolean);
begin
  FDone := True;
  FFiles := AFilesSearched;
end;

{ The thread reports through Synchronize, which needs the main thread to be
  in CheckSynchronize; a console test has to pump it by hand. }
function TTestGrep.RunSearch(const AOptions: TLedGrepOptions): Integer;
var
  T: TLedGrepThread;
  Guard: Integer;
begin
  FHits.Clear;
  FDone := False;
  T := TLedGrepThread.Create(AOptions);
  try
    T.OnMatch := @Got;
    T.OnDone := @Done;
    T.Start;
    Guard := 0;
    while (not FDone) and (Guard < 2000) do
    begin
      CheckSynchronize(10);
      Inc(Guard);
    end;
    T.WaitFor;
    CheckSynchronize(10);
  finally
    T.Free;
  end;
  Result := FHits.Count;
end;

procedure TTestGrep.FindsAPlainString;
var
  O: TLedGrepOptions;
begin
  Write('a.txt', 'hello world' + LineEnding + 'nothing here');
  Write('b.txt', 'another hello');
  O := LedDefaultGrepOptions;
  O.Pattern := 'hello';
  O.Directory := FDir;
  AssertEquals(2, RunSearch(O));
end;

procedure TTestGrep.CaseInsensitiveByDefault;
var
  O: TLedGrepOptions;
begin
  Write('a.txt', 'Hello' + LineEnding + 'HELLO' + LineEnding + 'hello');
  O := LedDefaultGrepOptions;
  O.Pattern := 'hello';
  O.Directory := FDir;
  AssertEquals(3, RunSearch(O));
end;

procedure TTestGrep.CaseSensitiveWhenAsked;
var
  O: TLedGrepOptions;
begin
  Write('a.txt', 'Hello' + LineEnding + 'HELLO' + LineEnding + 'hello');
  O := LedDefaultGrepOptions;
  O.Pattern := 'hello';
  O.MatchCase := True;
  O.Directory := FDir;
  AssertEquals(1, RunSearch(O));
end;

procedure TTestGrep.WholeWordRejectsSubstrings;
var
  O: TLedGrepOptions;
begin
  Write('a.txt', 'cat' + LineEnding + 'concatenate' + LineEnding + 'the cat sat');
  O := LedDefaultGrepOptions;
  O.Pattern := 'cat';
  O.WholeWord := True;
  O.Directory := FDir;
  AssertEquals('"concatenate" must not count', 2, RunSearch(O));
end;

procedure TTestGrep.RegexSearch;
var
  O: TLedGrepOptions;
begin
  Write('a.txt', 'v1.2.3' + LineEnding + 'not a version' + LineEnding + 'v10.0.1');
  O := LedDefaultGrepOptions;
  O.Pattern := 'v\d+\.\d+\.\d+';
  O.Regex := True;
  O.Directory := FDir;
  AssertEquals(2, RunSearch(O));
end;

procedure TTestGrep.FileMaskLimitsTheSearch;
var
  O: TLedGrepOptions;
begin
  Write('a.txt', 'needle');
  Write('b.pas', 'needle');
  Write('c.md', 'needle');
  O := LedDefaultGrepOptions;
  O.Pattern := 'needle';
  O.FileMask := '*.pas;*.md';
  O.Directory := FDir;
  AssertEquals(2, RunSearch(O));
end;

procedure TTestGrep.RecursionCanBeTurnedOff;
var
  O: TLedGrepOptions;
begin
  Write('top.txt', 'needle');
  Write('sub/deep.txt', 'needle');
  O := LedDefaultGrepOptions;
  O.Pattern := 'needle';
  O.Directory := FDir;
  AssertEquals('recursive by default', 2, RunSearch(O));
  O.Recursive := False;
  AssertEquals(1, RunSearch(O));
end;

procedure TTestGrep.VcsDirectoriesAreSkipped;
var
  O: TLedGrepOptions;
begin
  { Searching .git turns a two-second search into a two-minute one, and
    nothing in there is what you were looking for. }
  Write('real.txt', 'needle');
  Write('.git/objects/pack.txt', 'needle');
  Write('node_modules/dep/index.js', 'needle');
  O := LedDefaultGrepOptions;
  O.Pattern := 'needle';
  O.Directory := FDir;
  AssertEquals(1, RunSearch(O));
  O.SkipVCS := False;
  AssertEquals(3, RunSearch(O));
end;

procedure TTestGrep.BinaryFilesAreSkipped;
var
  O: TLedGrepOptions;
  F: TFileStream;
  Data: string;
begin
  Write('text.txt', 'needle');
  Data := 'needle' + #0 + 'binary';
  F := TFileStream.Create(FDir + 'blob.bin', fmCreate);
  try
    F.WriteBuffer(Data[1], Length(Data));
  finally
    F.Free;
  end;
  O := LedDefaultGrepOptions;
  O.Pattern := 'needle';
  O.Directory := FDir;
  AssertEquals(1, RunSearch(O));
  O.SkipBinary := False;
  AssertEquals(2, RunSearch(O));
end;

procedure TTestGrep.MaxMatchesStopsTheSearch;
var
  O: TLedGrepOptions;
  i: Integer;
  S: string;
begin
  S := '';
  for i := 1 to 50 do S := S + 'needle' + LineEnding;
  Write('many.txt', S);
  O := LedDefaultGrepOptions;
  O.Pattern := 'needle';
  O.Directory := FDir;
  O.MaxMatches := 10;
  AssertEquals(10, RunSearch(O));
end;

procedure TTestGrep.BinaryDetection;
begin
  AssertTrue(LedLooksBinary('abc'#0'def'));
  AssertFalse(LedLooksBinary('plain text'));
  AssertFalse(LedLooksBinary(''));
end;

initialization
  RegisterTest(TTestGrep);

end.
