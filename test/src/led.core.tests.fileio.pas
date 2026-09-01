{ led - a light editor.  Headless tests for Led.Core.FileIO.

  These run with no widgetset at all: the ledcore package depends on LazUtils
  but on nothing visual, which is the constraint that keeps the interesting
  logic testable in CI. }
unit Led.Core.Tests.FileIO;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.Types, Led.Core.FileIO;

type
  TTestLineEnd = class(TTestCase)
  published
    procedure DetectsUnix;
    procedure DetectsWindows;
    procedure DetectsMac;
    procedure DetectsMixed;
    procedure DetectsNone;
    procedure TrailingCROnly;
  end;

  TTestRoundTrip = class(TTestCase)
  private
    FDir: string;
    function WriteRaw(const AName, AContent: string): string;
    function ReadRaw(const APath: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure UnixRoundTripIsByteIdentical;
    procedure WindowsRoundTripIsByteIdentical;
    procedure MacRoundTripIsByteIdentical;
    procedure Utf8BomIsPreserved;
    procedure NoBomStaysWithoutBom;
    procedure LinesAreNormalisedToLFOnLoad;
    procedure EmptyFile;
  end;

implementation

{ TTestLineEnd }

procedure TTestLineEnd.DetectsUnix;
begin
  AssertTrue(LedDetectLineEnd('a'#10'b'#10) = leUnix);
end;

procedure TTestLineEnd.DetectsWindows;
begin
  AssertTrue(LedDetectLineEnd('a'#13#10'b'#13#10) = leWindows);
end;

procedure TTestLineEnd.DetectsMac;
begin
  AssertTrue(LedDetectLineEnd('a'#13'b'#13) = leMac);
end;

procedure TTestLineEnd.DetectsMixed;
begin
  AssertTrue('CRLF + LF', LedDetectLineEnd('a'#13#10'b'#10) = leMixed);
  AssertTrue('CR + LF',   LedDetectLineEnd('a'#13'b'#10) = leMixed);
  AssertTrue('CR + CRLF', LedDetectLineEnd('a'#13'b'#13#10) = leMixed);
end;

procedure TTestLineEnd.DetectsNone;
begin
  AssertTrue(LedDetectLineEnd('no terminator here') = leUnknown);
  AssertTrue(LedDetectLineEnd('') = leUnknown);
end;

procedure TTestLineEnd.TrailingCROnly;
begin
  { A lone CR at the very end must not be misread as the start of a CRLF. }
  AssertTrue(LedDetectLineEnd('abc'#13) = leMac);
end;

{ TTestRoundTrip }

procedure TTestRoundTrip.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-test-%d%s', [GetProcessID, PathDelim]);
  ForceDirectories(FDir);
end;

procedure TTestRoundTrip.TearDown;
var
  Info: TSearchRec;
begin
  if FindFirst(FDir + '*', faAnyFile, Info) = 0 then
  begin
    repeat
      if (Info.Name <> '.') and (Info.Name <> '..') then
        DeleteFile(FDir + Info.Name);
    until FindNext(Info) <> 0;
    FindClose(Info);
  end;
  RemoveDir(FDir);
end;

function TTestRoundTrip.WriteRaw(const AName, AContent: string): string;
var
  S: TFileStream;
begin
  Result := FDir + AName;
  S := TFileStream.Create(Result, fmCreate);
  try
    if AContent <> '' then
      S.WriteBuffer(AContent[1], Length(AContent));
  finally
    S.Free;
  end;
end;

function TTestRoundTrip.ReadRaw(const APath: string): string;
var
  S: TFileStream;
begin
  S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then
      S.ReadBuffer(Result[1], S.Size);
  finally
    S.Free;
  end;
end;

{ The contract that matters most: loading a file and saving it again with no
  edits must not change a single byte.  Everything else in the file layer is
  built on top of that promise. }
procedure TTestRoundTrip.UnixRoundTripIsByteIdentical;
var
  Path, Text, Original: string;
  Info: TLedTextInfo;
begin
  Original := 'one'#10'two'#10'three'#10;
  Path := WriteRaw('unix.txt', Original);
  LedLoadTextFile(Path, Text, Info);
  AssertTrue('detected LF', Info.LineEnd = leUnix);
  LedSaveTextFile(Path, Text, Info);
  AssertEquals(Original, ReadRaw(Path));
end;

procedure TTestRoundTrip.WindowsRoundTripIsByteIdentical;
var
  Path, Text, Original: string;
  Info: TLedTextInfo;
begin
  Original := 'one'#13#10'two'#13#10'three'#13#10;
  Path := WriteRaw('win.txt', Original);
  LedLoadTextFile(Path, Text, Info);
  AssertTrue('detected CRLF', Info.LineEnd = leWindows);
  LedSaveTextFile(Path, Text, Info);
  AssertEquals(Original, ReadRaw(Path));
end;

procedure TTestRoundTrip.MacRoundTripIsByteIdentical;
var
  Path, Text, Original: string;
  Info: TLedTextInfo;
begin
  Original := 'one'#13'two'#13'three'#13;
  Path := WriteRaw('mac.txt', Original);
  LedLoadTextFile(Path, Text, Info);
  AssertTrue('detected CR', Info.LineEnd = leMac);
  LedSaveTextFile(Path, Text, Info);
  AssertEquals(Original, ReadRaw(Path));
end;

procedure TTestRoundTrip.Utf8BomIsPreserved;
var
  Path, Text, Original: string;
  Info: TLedTextInfo;
begin
  Original := #$EF#$BB#$BF + 'caf'#$C3#$A9#10;
  Path := WriteRaw('bom.txt', Original);
  LedLoadTextFile(Path, Text, Info);
  AssertTrue('BOM was seen', Info.HasBOM);
  AssertEquals('BOM is not part of the text', 'caf'#$C3#$A9#10, Text);
  LedSaveTextFile(Path, Text, Info);
  AssertEquals(Original, ReadRaw(Path));
end;

procedure TTestRoundTrip.NoBomStaysWithoutBom;
var
  Path, Text, Original: string;
  Info: TLedTextInfo;
begin
  Original := 'plain'#10;
  Path := WriteRaw('nobom.txt', Original);
  LedLoadTextFile(Path, Text, Info);
  AssertFalse('no BOM reported', Info.HasBOM);
  LedSaveTextFile(Path, Text, Info);
  AssertEquals(Original, ReadRaw(Path));
end;

procedure TTestRoundTrip.LinesAreNormalisedToLFOnLoad;
var
  Path, Text: string;
  Info: TLedTextInfo;
begin
  Path := WriteRaw('mixed.txt', 'a'#13#10'b'#13'c'#10'd');
  LedLoadTextFile(Path, Text, Info);
  AssertTrue('mixed is detected', Info.LineEnd = leMixed);
  AssertEquals('a'#10'b'#10'c'#10'd', Text);
end;

procedure TTestRoundTrip.EmptyFile;
var
  Path, Text: string;
  Info: TLedTextInfo;
begin
  Path := WriteRaw('empty.txt', '');
  LedLoadTextFile(Path, Text, Info);
  AssertEquals('', Text);
  AssertFalse(Info.TrailingEOL);
  LedSaveTextFile(Path, Text, Info);
  AssertEquals('', ReadRaw(Path));
end;

initialization
  RegisterTest(TTestLineEnd);
  RegisterTest(TTestRoundTrip);

end.
