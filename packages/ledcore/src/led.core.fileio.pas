{ led - a light editor.  File loading and saving.

  Ported from medit's mooedit-fileops.cpp, which is the piece of medit with
  the least equivalent anywhere in Lazarus: LConvEncoding is only a codec
  table, and everything interesting -- the candidate list, the BOM rules, the
  mixed line-ending case, the backup, the error taxonomy -- lives here.

  The contract the rest of the editor relies on: loading a file and saving it
  again with no edits does not change a single byte.

  Two deliberate departures from medit:
    * BOM detection tests UTF-32 before UTF-16.  medit tests UTF-16 first
      (mooedit-fileops.cpp:1345), so on a little-endian machine a UTF-32LE
      file, whose BOM FF FE 00 00 starts with the UTF-16LE BOM, is misread as
      UTF-16.  Longest match wins here instead.
    * UTF-32 is detected and reported rather than decoded.  LConvEncoding has
      no UTF-32 codec, and refusing with a clear message beats mangling.

  No LCL dependency: this works on streams and strings so the whole encoding
  matrix can be exercised headlessly. }
unit Led.Core.FileIO;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LConvEncoding, Led.Core.Types, Led.Core.Encodings;

type
  TLedBOM = (bomNone, bomUTF8, bomUTF16LE, bomUTF16BE, bomUTF32LE, bomUTF32BE);

  { Why a load or save could not be done.  The editor turns these into
    messages; keeping them as a closed set stops "something went wrong"
    dialogs from proliferating. }
  TLedFileError = (
    lfeNone,
    lfeNotFound,
    lfeNotRegular,        // a directory, device, socket or fifo
    lfeAccessDenied,
    lfeEncodingFailed,    // no candidate encoding could decode the bytes
    lfeEncodingUnsupported,
    lfeIOError
  );

  ELedFileError = class(Exception)
  private
    FError: TLedFileError;
    FFileName: string;
  public
    constructor Create(AError: TLedFileError; const AFileName: string;
      const ADetail: string = '');
    property Error: TLedFileError read FError;
    property FileName: string read FFileName;
  end;

  { What a load produced beyond the text.  Save takes the same record back, so
    a round trip reproduces the original byte for byte. }
  TLedTextInfo = record
    Encoding:    string;      // LConvEncoding name
    BOM:         TLedBOM;
    LineEnd:     TLedLineEnd;
    TrailingEOL: Boolean;
  end;

function LedDefaultTextInfo: TLedTextInfo;

{ Detects the line-ending convention.  leMixed when more than one appears,
  leUnknown when the text holds no terminator at all. }
function LedDetectLineEnd(const AText: string): TLedLineEnd;

{ Identifies a leading byte-order mark without removing it. }
function LedDetectBOM(const AData: string): TLedBOM;
function LedBOMBytes(ABOM: TLedBOM): string;
function LedBOMEncoding(ABOM: TLedBOM): string;

{ True when APath exists and is an ordinary file.  Opening a directory or a
  device is a mistake worth catching before it produces gibberish. }
function LedIsRegularFile(const APath: string): Boolean;

{ Decodes ARaw to UTF-8.

  AForcedEncoding, when given, is the only candidate tried, and failure is
  reported rather than worked around -- that is what "Reopen with encoding"
  means.  Otherwise a BOM decides; failing that, ACandidates are tried in
  order, ACachedEncoding first when supplied (a file reopened in this session
  should not change its mind about its own encoding).

  Returns lfeNone on success. }
function LedDecodeText(const ARaw: string; const AForcedEncoding: string;
  const ACachedEncoding: string; ACandidates: TStrings;
  out AText: string; out AInfo: TLedTextInfo): TLedFileError;

{ Loads AFileName, normalising every line ending to LF.  Raises
  ELedFileError. }
procedure LedLoadTextFile(const AFileName: string; out AText: string;
  out AInfo: TLedTextInfo); overload;
procedure LedLoadTextFile(const AFileName, AForcedEncoding: string;
  const ACachedEncoding: string; AEncodingList: TStrings;
  out AText: string; out AInfo: TLedTextInfo); overload;

{ Writes AText (LF-separated) using AInfo's encoding, BOM and line-ending
  convention.  leUnknown and leMixed serialise as the platform native
  convention, which is how medit resolves a file that could not make up its
  mind.  With AMakeBackup, the previous contents are copied to "<name>~"
  first -- a copy rather than a rename, so symlinks, hard links, permissions
  and ownership all survive.  Raises ELedFileError. }
procedure LedSaveTextFile(const AFileName, AText: string;
  const AInfo: TLedTextInfo; AMakeBackup: Boolean = False);

function LedFileErrorMessage(AError: TLedFileError; const AFileName: string): string;

implementation

{ BaseUnix supplies FpStat/FpS_ISREG for LedIsRegularFile, which is the only
  platform-specific call in this unit and is already guarded at its call site.
  The clause has to be conditional too, or the Windows build cannot even find
  the unit. }
{$IFDEF UNIX}
uses
  BaseUnix;
{$ENDIF}

const
  BOMBytes: array[TLedBOM] of string = (
    '', #$EF#$BB#$BF, #$FF#$FE, #$FE#$FF, #$FF#$FE#$00#$00, #$00#$00#$FE#$FF);

  { Longest first, so UTF-32LE is not swallowed by the UTF-16LE prefix. }
  BOMProbeOrder: array[0..4] of TLedBOM =
    (bomUTF32LE, bomUTF32BE, bomUTF8, bomUTF16LE, bomUTF16BE);

{ ELedFileError }

constructor ELedFileError.Create(AError: TLedFileError; const AFileName: string;
  const ADetail: string);
var
  Msg: string;
begin
  Msg := LedFileErrorMessage(AError, AFileName);
  if ADetail <> '' then
    Msg := Msg + LineEnding + ADetail;
  inherited Create(Msg);
  FError := AError;
  FFileName := AFileName;
end;

function LedFileErrorMessage(AError: TLedFileError; const AFileName: string): string;
var
  N: string;
begin
  N := ExtractFileName(AFileName);
  case AError of
    lfeNotFound:      Result := Format('%s does not exist.', [N]);
    lfeNotRegular:    Result := Format('%s is not an ordinary file.', [N]);
    lfeAccessDenied:  Result := Format('Access to %s was denied.', [N]);
    lfeEncodingFailed:
      Result := Format('The character encoding of %s could not be determined.', [N]);
    lfeEncodingUnsupported:
      Result := Format('%s uses a character encoding led cannot read.', [N]);
    lfeIOError:       Result := Format('%s could not be read or written.', [N]);
  else
    Result := '';
  end;
end;

function LedDefaultTextInfo: TLedTextInfo;
begin
  Result.Encoding := EncodingUTF8;
  Result.BOM := bomNone;
  Result.LineEnd := LedNativeLineEnd;
  Result.TrailingEOL := True;
end;

function LedDetectLineEnd(const AText: string): TLedLineEnd;
var
  i, n: SizeInt;
  SawLF, SawCRLF, SawCR: Boolean;
begin
  SawLF := False; SawCRLF := False; SawCR := False;
  n := Length(AText);
  i := 1;
  while i <= n do
  begin
    case AText[i] of
      #13:
        if (i < n) and (AText[i + 1] = #10) then
        begin
          SawCRLF := True;
          Inc(i);
        end
        else
          SawCR := True;
      #10:
        SawLF := True;
    end;
    Inc(i);
  end;

  if Ord(SawLF) + Ord(SawCRLF) + Ord(SawCR) > 1 then
    Result := leMixed
  else if SawCRLF then Result := leWindows
  else if SawCR   then Result := leMac
  else if SawLF   then Result := leUnix
  else Result := leUnknown;
end;

function LedDetectBOM(const AData: string): TLedBOM;
var
  i: Integer;
  B: TLedBOM;
begin
  for i := Low(BOMProbeOrder) to High(BOMProbeOrder) do
  begin
    B := BOMProbeOrder[i];
    if (Length(AData) >= Length(BOMBytes[B])) and
       (Copy(AData, 1, Length(BOMBytes[B])) = BOMBytes[B]) then
      Exit(B);
  end;
  Result := bomNone;
end;

function LedBOMBytes(ABOM: TLedBOM): string;
begin
  Result := BOMBytes[ABOM];
end;

function LedBOMEncoding(ABOM: TLedBOM): string;
begin
  case ABOM of
    bomUTF8:    Result := EncodingUTF8;
    bomUTF16LE: Result := EncodingUCS2LE;
    bomUTF16BE: Result := EncodingUCS2BE;
  else
    Result := '';      // UTF-32 and bomNone have no usable codec here
  end;
end;

function LedIsRegularFile(const APath: string): Boolean;
{$IFDEF UNIX}
var
  Info: stat;
{$ENDIF}
begin
  {$IFDEF UNIX}
  if FpStat(APath, Info) <> 0 then Exit(False);
  Result := FpS_ISREG(Info.st_mode);
  {$ELSE}
  Result := FileExists(APath) and not DirectoryExists(APath);
  {$ENDIF}
end;

{ Collapses CRLF and lone CR to LF in one pass.  Single-pass matters: "open a
  200 MB log" is a supported operation. }
function NormaliseToLF(const AText: string): string;
var
  i, j, n: SizeInt;
begin
  Result := '';
  n := Length(AText);
  SetLength(Result, n);
  i := 1; j := 0;
  while i <= n do
  begin
    if AText[i] = #13 then
    begin
      Inc(j);
      Result[j] := #10;
      if (i < n) and (AText[i + 1] = #10) then
        Inc(i);
    end
    else
    begin
      Inc(j);
      Result[j] := AText[i];
    end;
    Inc(i);
  end;
  SetLength(Result, j);
end;

function ExpandFromLF(const AText: string; ALineEnd: TLedLineEnd): string;
var
  Term: string;
begin
  if ALineEnd in [leUnknown, leMixed] then
    ALineEnd := LedNativeLineEnd;
  Term := LedLineEndStr[ALineEnd];
  if Term = #10 then
    Result := AText
  else
    Result := StringReplace(AText, #10, Term, [rfReplaceAll]);
end;

{ Tries one encoding.  Returns False when the bytes are not valid in it --
  which for UTF-8 is a real test, and for the single-byte codepages is always
  true, which is exactly why ISO-8859-1 has to be the last candidate. }
function TryDecode(const ARaw, AEncoding: string; out AText: string): Boolean;
begin
  AText := '';
  if AEncoding = EncodingUTF8 then
  begin
    Result := LedIsValidUTF8(ARaw);
    if Result then AText := ARaw;
    Exit;
  end;

  try
    AText := ConvertEncoding(ARaw, AEncoding, EncodingUTF8);
  except
    Exit(False);
  end;
  { ConvertEncoding returns the input unchanged when it does not know the
    encoding; treat that as a failure unless the bytes really are unchanged
    because they are pure ASCII. }
  Result := LedIsValidUTF8(AText);
end;

function LedDecodeText(const ARaw: string; const AForcedEncoding: string;
  const ACachedEncoding: string; ACandidates: TStrings;
  out AText: string; out AInfo: TLedTextInfo): TLedFileError;
var
  Body, Enc: string;
  i: Integer;
  Tried: TStringList;
begin
  AText := '';
  AInfo := LedDefaultTextInfo;

  AInfo.BOM := LedDetectBOM(ARaw);
  Body := Copy(ARaw, Length(BOMBytes[AInfo.BOM]) + 1, MaxInt);

  if AInfo.BOM in [bomUTF32LE, bomUTF32BE] then
    Exit(lfeEncodingUnsupported);

  { An explicit choice is honoured exactly: no silent fallback, because the
    user asking for CP1251 wants to know when CP1251 is wrong. }
  if AForcedEncoding <> '' then
  begin
    Enc := LedNormaliseEncoding(AForcedEncoding);
    if Enc = '' then Exit(lfeEncodingUnsupported);
    if not TryDecode(Body, Enc, AText) then Exit(lfeEncodingFailed);
    AInfo.Encoding := Enc;
  end
  else if AInfo.BOM <> bomNone then
  begin
    Enc := LedBOMEncoding(AInfo.BOM);
    if not TryDecode(Body, Enc, AText) then Exit(lfeEncodingFailed);
    AInfo.Encoding := Enc;
  end
  else
  begin
    Tried := TStringList.Create;
    try
      Tried.CaseSensitive := False;
      Enc := LedNormaliseEncoding(ACachedEncoding);
      if Enc <> '' then Tried.Add(Enc);
      if ACandidates <> nil then
        for i := 0 to ACandidates.Count - 1 do
        begin
          Enc := LedNormaliseEncoding(ACandidates[i]);
          if (Enc <> '') and (Tried.IndexOf(Enc) < 0) then
            Tried.Add(Enc);
        end;
      if Tried.Count = 0 then
        Tried.Add(EncodingUTF8);

      for i := 0 to Tried.Count - 1 do
        if TryDecode(Body, Tried[i], AText) then
        begin
          AInfo.Encoding := Tried[i];
          Break;
        end
        else if i = Tried.Count - 1 then
          Exit(lfeEncodingFailed);
    finally
      Tried.Free;
    end;
  end;

  AInfo.LineEnd := LedDetectLineEnd(AText);
  AInfo.TrailingEOL := (AText <> '') and (AText[Length(AText)] in [#10, #13]);
  AText := NormaliseToLF(AText);
  Result := lfeNone;
end;

function ReadWholeFile(const AFileName: string): string;
var
  Stream: TFileStream;
begin
  Result := '';
  { Order matters: FileExists is false for a directory on Unix, so testing it
    first would report a directory as missing. }
  if DirectoryExists(AFileName) then
    raise ELedFileError.Create(lfeNotRegular, AFileName);
  if not FileExists(AFileName) then
    raise ELedFileError.Create(lfeNotFound, AFileName);
  if not LedIsRegularFile(AFileName) then
    raise ELedFileError.Create(lfeNotRegular, AFileName);
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  except
    on E: EFOpenError do
      raise ELedFileError.Create(lfeAccessDenied, AFileName, E.Message);
  end;
  try
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[1], Stream.Size);
  except
    on E: EStreamError do
      raise ELedFileError.Create(lfeIOError, AFileName, E.Message);
  end;
  Stream.Free;
end;

procedure LedLoadTextFile(const AFileName, AForcedEncoding: string;
  const ACachedEncoding: string; AEncodingList: TStrings;
  out AText: string; out AInfo: TLedTextInfo);
var
  Raw: string;
  Err: TLedFileError;
  Owned: TStringList;
begin
  Raw := ReadWholeFile(AFileName);

  Owned := nil;
  try
    if AEncodingList = nil then
    begin
      Owned := TStringList.Create;
      LedParseEncodingList(LedDefaultEncodingList, Owned);
      AEncodingList := Owned;
    end;
    Err := LedDecodeText(Raw, AForcedEncoding, ACachedEncoding, AEncodingList,
      AText, AInfo);
  finally
    Owned.Free;
  end;

  if Err <> lfeNone then
    raise ELedFileError.Create(Err, AFileName);
end;

procedure LedLoadTextFile(const AFileName: string; out AText: string;
  out AInfo: TLedTextInfo);
begin
  LedLoadTextFile(AFileName, '', '', nil, AText, AInfo);
end;

procedure CopyFileTo(const ASource, ADest: string);
var
  Src, Dst: TFileStream;
begin
  Src := TFileStream.Create(ASource, fmOpenRead or fmShareDenyNone);
  try
    Dst := TFileStream.Create(ADest, fmCreate);
    try
      if Src.Size > 0 then
        Dst.CopyFrom(Src, Src.Size);
    finally
      Dst.Free;
    end;
  finally
    Src.Free;
  end;
end;

procedure LedSaveTextFile(const AFileName, AText: string;
  const AInfo: TLedTextInfo; AMakeBackup: Boolean);
var
  Stream: TFileStream;
  Data: string;
begin
  Data := ExpandFromLF(AText, AInfo.LineEnd);

  if (AInfo.Encoding <> '') and (AInfo.Encoding <> EncodingUTF8) then
    try
      Data := ConvertEncoding(Data, EncodingUTF8, AInfo.Encoding);
    except
      on E: Exception do
        raise ELedFileError.Create(lfeEncodingFailed, AFileName, E.Message);
    end;

  Data := BOMBytes[AInfo.BOM] + Data;

  if AMakeBackup and FileExists(AFileName) and LedIsRegularFile(AFileName) then
    try
      CopyFileTo(AFileName, AFileName + '~');
    except
      { A backup that cannot be written must not block the save itself. }
    end;

  try
    Stream := TFileStream.Create(AFileName, fmCreate);
  except
    on E: EFCreateError do
      raise ELedFileError.Create(lfeAccessDenied, AFileName, E.Message);
  end;
  try
    if Data <> '' then
      Stream.WriteBuffer(Data[1], Length(Data));
  except
    on E: EStreamError do
      raise ELedFileError.Create(lfeIOError, AFileName, E.Message);
  end;
  Stream.Free;
end;

end.
