{ led - a light editor.  Headless tests for encoding detection and the
  load/save contract.  This is the matrix the plan calls the highest-value
  thing to get right, so it is tested harder than anything else. }
unit Led.Core.Tests.Encodings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, LConvEncoding,
  Led.Core.Types, Led.Core.Encodings, Led.Core.FileIO;

type
  TTestEncodingNames = class(TTestCase)
  published
    procedure IconvSpellingsResolve;
    procedure LConvSpellingsPassThrough;
    procedure PunctuationIsIgnored;
    procedure LocaleResolves;
    procedure UnknownReturnsEmpty;
    procedure DefaultListParsesAndDeduplicates;
    procedure Iso88591IsLastSoItCanBeTheFallback;
  end;

  TTestBOM = class(TTestCase)
  published
    procedure Utf8;
    procedure Utf16LE;
    procedure Utf16BE;
    procedure Utf32LEIsNotMistakenForUtf16;
    procedure Utf32BE;
    procedure None;
    procedure ShortBufferIsNotABOM;
  end;

  TTestDecode = class(TTestCase)
  private
    FList: TStringList;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure PlainUtf8;
    procedure InvalidUtf8FallsBackToLatin1;
    procedure ForcedEncodingIsHonoured;
    procedure ForcedEncodingThatFailsIsReported;
    procedure CachedEncodingIsTriedFirst;
    procedure Utf32IsRefusedNotMangled;
    procedure BomWins;
  end;

  TTestSaveLoad = class(TTestCase)
  private
    FDir: string;
    function Path(const AName: string): string;
    function WriteRaw(const AName, AContent: string): string;
    function ReadRaw(const APath: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Utf8BomRoundTrip;
    procedure Utf16LERoundTrip;
    procedure Latin1RoundTrip;
    procedure BackupIsWrittenWhenAsked;
    procedure BackupIsNotWrittenByDefault;
    procedure MissingFileRaisesNotFound;
    procedure DirectoryRaisesNotRegular;
  end;

implementation

{ TTestEncodingNames }

procedure TTestEncodingNames.IconvSpellingsResolve;
begin
  AssertEquals(EncodingUTF8,    LedNormaliseEncoding('UTF-8'));
  AssertEquals(EncodingCPIso1,  LedNormaliseEncoding('ISO_8859-1'));
  AssertEquals(EncodingCPIso15, LedNormaliseEncoding('ISO_8859-15'));
  AssertEquals(EncodingCP1251,  LedNormaliseEncoding('windows-1251'));
  AssertEquals(EncodingCP936,   LedNormaliseEncoding('GB2312'));
  AssertEquals(EncodingCP932,   LedNormaliseEncoding('Shift_JIS'));
end;

procedure TTestEncodingNames.LConvSpellingsPassThrough;
begin
  AssertEquals(EncodingCP1252, LedNormaliseEncoding('cp1252'));
  AssertEquals(EncodingUTF8,   LedNormaliseEncoding('utf8'));
end;

procedure TTestEncodingNames.PunctuationIsIgnored;
begin
  AssertEquals(EncodingCPIso2, LedNormaliseEncoding('iso-8859-2'));
  AssertEquals(EncodingCPIso2, LedNormaliseEncoding('ISO 8859 2'));
end;

procedure TTestEncodingNames.LocaleResolves;
begin
  AssertTrue('LOCALE resolves to something',
    LedNormaliseEncoding(LedEncodingLocale) <> '');
  AssertEquals(LedLocaleEncoding, LedNormaliseEncoding('locale'));
end;

procedure TTestEncodingNames.UnknownReturnsEmpty;
begin
  AssertEquals('', LedNormaliseEncoding('not-a-real-encoding'));
  AssertEquals('', LedNormaliseEncoding(''));
end;

procedure TTestEncodingNames.DefaultListParsesAndDeduplicates;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    LedParseEncodingList('utf8,UTF-8,iso88591,ISO_8859-1', L);
    AssertEquals('duplicates collapse', 2, L.Count);
    AssertEquals(EncodingUTF8, L[0]);
    AssertEquals(EncodingCPIso1, L[1]);
  finally
    L.Free;
  end;
end;

procedure TTestEncodingNames.Iso88591IsLastSoItCanBeTheFallback;
var
  L: TStringList;
begin
  { ISO-8859-1 accepts any byte at all, so any candidate placed after it would
    never be reached.  Guard the ordering, not just the contents. }
  L := TStringList.Create;
  try
    LedParseEncodingList(LedDefaultEncodingList, L);
    AssertTrue('utf8 comes first', L[0] = EncodingUTF8);
    AssertEquals('iso88591 is last', EncodingCPIso1, L[L.Count - 1]);
  finally
    L.Free;
  end;
end;

{ TTestBOM }

procedure TTestBOM.Utf8;
begin
  AssertTrue(LedDetectBOM(#$EF#$BB#$BF'hi') = bomUTF8);
end;

procedure TTestBOM.Utf16LE;
begin
  AssertTrue(LedDetectBOM(#$FF#$FE'h'#0) = bomUTF16LE);
end;

procedure TTestBOM.Utf16BE;
begin
  AssertTrue(LedDetectBOM(#$FE#$FF#0'h') = bomUTF16BE);
end;

procedure TTestBOM.Utf32LEIsNotMistakenForUtf16;
begin
  { medit tests UTF-16 before UTF-32, so on a little-endian machine this
    exact input is misread as UTF-16LE.  Longest match must win. }
  AssertTrue(LedDetectBOM(#$FF#$FE#$00#$00'x') = bomUTF32LE);
end;

procedure TTestBOM.Utf32BE;
begin
  AssertTrue(LedDetectBOM(#$00#$00#$FE#$FF'x') = bomUTF32BE);
end;

procedure TTestBOM.None;
begin
  AssertTrue(LedDetectBOM('plain text') = bomNone);
  AssertTrue(LedDetectBOM('') = bomNone);
end;

procedure TTestBOM.ShortBufferIsNotABOM;
begin
  { Two bytes that begin a UTF-32 BOM but are all the file holds must fall
    back to the UTF-16 reading rather than overrun. }
  AssertTrue(LedDetectBOM(#$FF#$FE) = bomUTF16LE);
  AssertTrue(LedDetectBOM(#$FF) = bomNone);
end;

{ TTestDecode }

procedure TTestDecode.SetUp;
begin
  FList := TStringList.Create;
  LedParseEncodingList(LedDefaultEncodingList, FList);
end;

procedure TTestDecode.TearDown;
begin
  FList.Free;
end;

procedure TTestDecode.PlainUtf8;
var
  Text: string;
  Info: TLedTextInfo;
begin
  AssertTrue(LedDecodeText('caf'#$C3#$A9, '', '', FList, Text, Info) = lfeNone);
  AssertEquals(EncodingUTF8, Info.Encoding);
  AssertEquals('caf'#$C3#$A9, Text);
end;

procedure TTestDecode.InvalidUtf8FallsBackToLatin1;
var
  Text: string;
  Info: TLedTextInfo;
begin
  { A lone 0xE9 is Latin-1 e-acute and invalid UTF-8. }
  AssertTrue(LedDecodeText('caf'#$E9, '', '', FList, Text, Info) = lfeNone);
  AssertTrue('did not claim UTF-8', Info.Encoding <> EncodingUTF8);
  AssertEquals('decoded to UTF-8 e-acute', 'caf'#$C3#$A9, Text);
end;

procedure TTestDecode.ForcedEncodingIsHonoured;
var
  Text: string;
  Info: TLedTextInfo;
begin
  { 0xC0 is A-grave in CP1251's Cyrillic block, not Latin-1's A-grave. }
  AssertTrue(LedDecodeText(#$C0, 'cp1251', '', FList, Text, Info) = lfeNone);
  AssertEquals(EncodingCP1251, Info.Encoding);
  AssertEquals('Cyrillic A', #$D0#$90, Text);
end;

procedure TTestDecode.ForcedEncodingThatFailsIsReported;
var
  Text: string;
  Info: TLedTextInfo;
begin
  { Asking for UTF-8 explicitly, on bytes that are not UTF-8, must fail rather
    than quietly fall back -- that is the whole point of "Reopen with". }
  AssertTrue(LedDecodeText('caf'#$E9, 'utf8', '', FList, Text, Info)
    = lfeEncodingFailed);
end;

procedure TTestDecode.CachedEncodingIsTriedFirst;
var
  Text: string;
  Info: TLedTextInfo;
begin
  { The bytes decode under both cp1251 and iso88591; the cached choice decides,
    so a file does not change its mind about itself between reloads. }
  AssertTrue(LedDecodeText(#$C0, '', 'cp1251', FList, Text, Info) = lfeNone);
  AssertEquals(EncodingCP1251, Info.Encoding);
end;

procedure TTestDecode.Utf32IsRefusedNotMangled;
var
  Text: string;
  Info: TLedTextInfo;
begin
  AssertTrue(LedDecodeText(#$FF#$FE#$00#$00'x'#0#0#0, '', '', FList, Text, Info)
    = lfeEncodingUnsupported);
end;

procedure TTestDecode.BomWins;
var
  Text: string;
  Info: TLedTextInfo;
begin
  AssertTrue(LedDecodeText(#$EF#$BB#$BF'hi', '', 'cp1251', FList, Text, Info)
    = lfeNone);
  AssertEquals(EncodingUTF8, Info.Encoding);
  AssertTrue(Info.BOM = bomUTF8);
  AssertEquals('BOM is not part of the text', 'hi', Text);
end;

{ TTestSaveLoad }

procedure TTestSaveLoad.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-enc-%d%s', [GetProcessID, PathDelim]);
  ForceDirectories(FDir);
end;

procedure TTestSaveLoad.TearDown;
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

function TTestSaveLoad.Path(const AName: string): string;
begin
  Result := FDir + AName;
end;

function TTestSaveLoad.WriteRaw(const AName, AContent: string): string;
var
  S: TFileStream;
begin
  Result := Path(AName);
  S := TFileStream.Create(Result, fmCreate);
  try
    if AContent <> '' then
      S.WriteBuffer(AContent[1], Length(AContent));
  finally
    S.Free;
  end;
end;

function TTestSaveLoad.ReadRaw(const APath: string): string;
var
  S: TFileStream;
begin
  Result := '';
  S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then
      S.ReadBuffer(Result[1], S.Size);
  finally
    S.Free;
  end;
end;

procedure TTestSaveLoad.Utf8BomRoundTrip;
var
  P, Text, Original: string;
  Info: TLedTextInfo;
begin
  Original := #$EF#$BB#$BF'caf'#$C3#$A9#13#10'x'#13#10;
  P := WriteRaw('bom.txt', Original);
  LedLoadTextFile(P, Text, Info);
  AssertTrue(Info.BOM = bomUTF8);
  AssertTrue(Info.LineEnd = leWindows);
  LedSaveTextFile(P, Text, Info);
  AssertEquals(Original, ReadRaw(P));
end;

procedure TTestSaveLoad.Utf16LERoundTrip;
var
  P, Text, Original: string;
  Info: TLedTextInfo;
begin
  Original := #$FF#$FE'h'#0'i'#0#10#0;
  P := WriteRaw('u16.txt', Original);
  LedLoadTextFile(P, Text, Info);
  AssertTrue(Info.BOM = bomUTF16LE);
  AssertEquals(EncodingUCS2LE, Info.Encoding);
  AssertEquals('hi'#10, Text);
  LedSaveTextFile(P, Text, Info);
  AssertEquals(Original, ReadRaw(P));
end;

procedure TTestSaveLoad.Latin1RoundTrip;
var
  P, Text, Original: string;
  Info: TLedTextInfo;
begin
  Original := 'caf'#$E9#10;
  P := WriteRaw('latin1.txt', Original);
  LedLoadTextFile(P, Text, Info);
  AssertTrue('not read as UTF-8', Info.Encoding <> EncodingUTF8);
  LedSaveTextFile(P, Text, Info);
  AssertEquals(Original, ReadRaw(P));
end;

procedure TTestSaveLoad.BackupIsWrittenWhenAsked;
var
  P, Text: string;
  Info: TLedTextInfo;
begin
  P := WriteRaw('bk.txt', 'before'#10);
  LedLoadTextFile(P, Text, Info);
  LedSaveTextFile(P, 'after'#10, Info, True);
  AssertTrue('backup exists', FileExists(P + '~'));
  AssertEquals('backup holds the old text', 'before'#10, ReadRaw(P + '~'));
  AssertEquals('file holds the new text', 'after'#10, ReadRaw(P));
end;

procedure TTestSaveLoad.BackupIsNotWrittenByDefault;
var
  P, Text: string;
  Info: TLedTextInfo;
begin
  P := WriteRaw('nobk.txt', 'before'#10);
  LedLoadTextFile(P, Text, Info);
  LedSaveTextFile(P, 'after'#10, Info);
  AssertFalse(FileExists(P + '~'));
end;

procedure TTestSaveLoad.MissingFileRaisesNotFound;
var
  Text: string;
  Info: TLedTextInfo;
  Caught: TLedFileError;
begin
  Caught := lfeNone;
  try
    LedLoadTextFile(Path('nope.txt'), Text, Info);
  except
    on E: ELedFileError do Caught := E.Error;
  end;
  AssertTrue(Caught = lfeNotFound);
end;

procedure TTestSaveLoad.DirectoryRaisesNotRegular;
var
  Text: string;
  Info: TLedTextInfo;
  Caught: TLedFileError;
begin
  Caught := lfeNone;
  try
    LedLoadTextFile(ExcludeTrailingPathDelimiter(FDir), Text, Info);
  except
    on E: ELedFileError do Caught := E.Error;
  end;
  AssertTrue('a directory is not an ordinary file', Caught = lfeNotRegular);
end;

initialization
  RegisterTest(TTestEncodingNames);
  RegisterTest(TTestBOM);
  RegisterTest(TTestDecode);
  RegisterTest(TTestSaveLoad);

end.
