{ led - a light editor.  Headless tests for crash recovery.

  The interesting cases are the ones a clean run never produces: a journal
  entry whose text was still being written when the process died, an entry
  whose metadata never landed, and wreckage left by an older version.  Those
  are simulated here by writing the files directly, because there is no way
  to make them happen on purpose through the API -- which is the point. }
unit Led.Core.Tests.Recovery;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.Paths, Led.Core.Recovery;

type
  TTestRecovery = class(TTestCase)
  private
    FDir: string;
    function Rec: TLedRecovery;
    function MakeEntry(const AId, AFile, ADisplay: string): TLedRecoveryEntry;
    procedure PutFile(const AName, AContent: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure NothingPendingOnAFreshDirectory;
    procedure StoreThenScanRoundTrips;
    procedure UntitledDocumentSurvives;
    procedure DiscardRemovesOneEntry;
    procedure ClearRemovesEverything;
    procedure TruncatedTextIsRejectedAndSwept;
    procedure MetadataWithoutTextIsIgnored;
    procedure TextWithoutMetadataIsIgnored;
    procedure CorruptMetadataIsIgnoredNotFatal;
    procedure UnknownVersionIsIgnored;
    procedure StoreOverwritesTheSameId;
    procedure IdIsStableForAPathAndUniqueForUntitled;
    procedure EmptyBufferRoundTrips;
    procedure TextWithNewlinesAndUnicodeSurvives;
  end;

implementation

procedure TTestRecovery.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) +
    'led-rectest-' + IntToStr(GetProcessID) + '-' + IntToStr(Random(100000));
  ForceDirectories(FDir);
end;

procedure TTestRecovery.TearDown;
var
  R: TSearchRec;
begin
  if DirectoryExists(FDir) then
  begin
    if FindFirst(IncludeTrailingPathDelimiter(FDir) + '*', faAnyFile, R) = 0 then
      try
        repeat
          if (R.Name = '.') or (R.Name = '..') then Continue;
          DeleteFile(IncludeTrailingPathDelimiter(FDir) + R.Name);
        until FindNext(R) <> 0;
      finally
        FindClose(R);
      end;
    RemoveDir(FDir);
  end;
end;

function TTestRecovery.Rec: TLedRecovery;
begin
  Result := TLedRecovery.Create(FDir);
end;

function TTestRecovery.MakeEntry(const AId, AFile, ADisplay: string):
  TLedRecoveryEntry;
begin
  Result := Default(TLedRecoveryEntry);
  Result.Id := AId;
  Result.FileName := AFile;
  Result.DisplayName := ADisplay;
  Result.Encoding := 'UTF-8';
  Result.LineEnding := 'LF';
  Result.Language := 'pascal';
  Result.Line := 12;
  Result.Column := 5;
  Result.SavedAt := Now;
end;

procedure TTestRecovery.PutFile(const AName, AContent: string);
var
  S: TFileStream;
begin
  S := TFileStream.Create(IncludeTrailingPathDelimiter(FDir) + AName, fmCreate);
  try
    if AContent <> '' then
      S.WriteBuffer(AContent[1], Length(AContent));
  finally
    S.Free;
  end;
end;

procedure TTestRecovery.NothingPendingOnAFreshDirectory;
var
  R: TLedRecovery;
begin
  R := Rec;
  try
    AssertEquals('no entries', 0, Length(R.Scan));
    AssertFalse('nothing pending', R.HasPending);
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.StoreThenScanRoundTrips;
var
  R: TLedRecovery;
  E: TLedRecoveryEntry;
  Got: TLedRecoveryEntries;
begin
  R := Rec;
  try
    E := MakeEntry('file-0001', '/tmp/a.pas', 'a.pas');
    R.Store(E, 'unit A;');
    Got := R.Scan;
    AssertEquals('one entry', 1, Length(Got));
    AssertEquals('id', 'file-0001', Got[0].Id);
    AssertEquals('path', '/tmp/a.pas', Got[0].FileName);
    AssertEquals('display', 'a.pas', Got[0].DisplayName);
    AssertEquals('encoding', 'UTF-8', Got[0].Encoding);
    AssertEquals('line ending', 'LF', Got[0].LineEnding);
    AssertEquals('language', 'pascal', Got[0].Language);
    AssertEquals('line', 12, Got[0].Line);
    AssertEquals('column', 5, Got[0].Column);
    AssertEquals('text', 'unit A;', R.LoadText(Got[0]));
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.UntitledDocumentSurvives;
var
  R: TLedRecovery;
  Got: TLedRecoveryEntries;
begin
  { The case session.json explicitly skips, and the one where a crash costs
    the user everything rather than merely the last few edits. }
  R := Rec;
  try
    R.Store(MakeEntry('untitled-1', '', 'Untitled 1'), 'scratch work');
    Got := R.Scan;
    AssertEquals('one entry', 1, Length(Got));
    AssertEquals('no path', '', Got[0].FileName);
    AssertEquals('display name kept', 'Untitled 1', Got[0].DisplayName);
    AssertEquals('text', 'scratch work', R.LoadText(Got[0]));
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.DiscardRemovesOneEntry;
var
  R: TLedRecovery;
begin
  R := Rec;
  try
    R.Store(MakeEntry('a', '/x', 'x'), 'one');
    R.Store(MakeEntry('b', '/y', 'y'), 'two');
    AssertEquals('both stored', 2, Length(R.Scan));
    R.Discard('a');
    AssertEquals('one left', 1, Length(R.Scan));
    AssertEquals('the right one', 'b', R.Scan[0].Id);
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.ClearRemovesEverything;
var
  R: TLedRecovery;
begin
  { Clear is what a clean exit calls, and it is the whole basis for "anything
    still here means we were killed". }
  R := Rec;
  try
    R.Store(MakeEntry('a', '/x', 'x'), 'one');
    R.Store(MakeEntry('b', '/y', 'y'), 'two');
    R.Clear;
    AssertFalse('nothing pending', R.HasPending);
    AssertFalse('directory gone', DirectoryExists(FDir));
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.TruncatedTextIsRejectedAndSwept;
var
  R: TLedRecovery;
begin
  { Killed midway through writing the text.  Restoring this would hand the
    user a truncated buffer and invite them to save it over their file, so
    it must be refused, not offered. }
  R := Rec;
  try
    R.Store(MakeEntry('a', '/x', 'x'), 'the whole buffer');
    PutFile('a.txt', 'the whole');      // shorter than the metadata claims
    AssertEquals('not offered', 0, Length(R.Scan));
    AssertFalse('and swept', FileExists(IncludeTrailingPathDelimiter(FDir) + 'a.json'));
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.MetadataWithoutTextIsIgnored;
var
  R: TLedRecovery;
begin
  R := Rec;
  try
    R.Store(MakeEntry('a', '/x', 'x'), 'body');
    DeleteFile(IncludeTrailingPathDelimiter(FDir) + 'a.txt');
    AssertEquals('ignored', 0, Length(R.Scan));
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.TextWithoutMetadataIsIgnored;
var
  R: TLedRecovery;
begin
  { Killed after the text landed but before the metadata: the entry has no
    path, encoding or caret, so there is nothing to restore it *as*. }
  R := Rec;
  try
    PutFile('orphan.txt', 'body with no metadata');
    AssertEquals('ignored', 0, Length(R.Scan));
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.CorruptMetadataIsIgnoredNotFatal;
var
  R: TLedRecovery;
begin
  R := Rec;
  try
    PutFile('a.txt', 'body');
    PutFile('a.json', '{ this is not json');
    AssertEquals('ignored', 0, Length(R.Scan));
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.UnknownVersionIsIgnored;
var
  R: TLedRecovery;
begin
  R := Rec;
  try
    PutFile('a.txt', 'body');
    PutFile('a.json', '{"version": 99, "fileName": "/x", "textLength": 4}');
    AssertEquals('ignored', 0, Length(R.Scan));
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.StoreOverwritesTheSameId;
var
  R: TLedRecovery;
  Got: TLedRecoveryEntries;
begin
  { The journal is rewritten every few seconds; entries must replace, not
    accumulate. }
  R := Rec;
  try
    R.Store(MakeEntry('a', '/x', 'x'), 'first');
    R.Store(MakeEntry('a', '/x', 'x'), 'second, longer');
    Got := R.Scan;
    AssertEquals('still one', 1, Length(Got));
    AssertEquals('latest text', 'second, longer', R.LoadText(Got[0]));
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.IdIsStableForAPathAndUniqueForUntitled;
begin
  AssertEquals('same path, same id',
    LedRecoveryId('/home/u/x.pas', 0), LedRecoveryId('/home/u/x.pas', 0));
  AssertTrue('different paths differ',
    LedRecoveryId('/home/u/x.pas', 0) <> LedRecoveryId('/home/u/y.pas', 0));
  AssertTrue('untitled documents differ',
    LedRecoveryId('', 1) <> LedRecoveryId('', 2));
end;

procedure TTestRecovery.EmptyBufferRoundTrips;
var
  R: TLedRecovery;
  Got: TLedRecoveryEntries;
begin
  { A zero-length text is legitimate -- the user emptied the buffer -- and
    must not read as a truncated write. }
  R := Rec;
  try
    R.Store(MakeEntry('a', '', 'Untitled 1'), '');
    Got := R.Scan;
    AssertEquals('offered', 1, Length(Got));
    AssertEquals('empty', '', R.LoadText(Got[0]));
  finally
    R.Free;
  end;
end;

procedure TTestRecovery.TextWithNewlinesAndUnicodeSurvives;
var
  R: TLedRecovery;
  Body: string;
  Got: TLedRecoveryEntries;
begin
  Body := 'первая'#10'第二行'#10'  trailing spaces   '#10;
  R := Rec;
  try
    R.Store(MakeEntry('a', '/x', 'x'), Body);
    Got := R.Scan;
    AssertEquals('offered', 1, Length(Got));
    AssertEquals('byte-identical', Body, R.LoadText(Got[0]));
  finally
    R.Free;
  end;
end;

initialization
  RegisterTest(TTestRecovery);

end.
