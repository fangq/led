{ led - a light editor.  File loading and saving.

  Phase 0 scope: BOM detection, line-ending detection (including the mixed
  case) and LF-normalised load / re-serialised save.  The full encoding
  try-list, the prompt flow, backups and the save-error taxonomy are ported
  from medit's mooedit-fileops.cpp in phase 1.

  No LCL dependency: everything here works on streams and strings so the
  encoding matrix can be exercised headlessly. }
unit Led.Core.FileIO;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LConvEncoding, Led.Core.Types;

type
  { What a load produced, beyond the text itself.  Save uses the same record
    so that a load/save round trip with no edits is byte-identical. }
  TLedTextInfo = record
    Encoding:    string;        // an LConvEncoding name, e.g. 'utf8', 'cp1251'
    HasBOM:      Boolean;
    LineEnd:     TLedLineEnd;
    TrailingEOL: Boolean;       // did the file end with a line terminator?
  end;

{ Detects the line-ending convention used by AText.  Returns leMixed when more
  than one convention appears, leUnknown when the text holds no terminator. }
function LedDetectLineEnd(const AText: string): TLedLineEnd;

{ Strips a leading BOM, reporting which encoding it implied. }
function LedStripBOM(var AText: string; out AEncoding: string): Boolean;

{ Loads AFileName into AText with all line endings normalised to LF, and
  fills AInfo with what was found.  Raises on I/O errors. }
procedure LedLoadTextFile(const AFileName: string; out AText: string;
  out AInfo: TLedTextInfo);

{ Writes AText (LF-separated) to AFileName using AInfo's encoding, BOM and
  line-ending convention.  leUnknown and leMixed serialise as the platform
  native convention. }
procedure LedSaveTextFile(const AFileName, AText: string;
  const AInfo: TLedTextInfo);

implementation

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

function LedStripBOM(var AText: string; out AEncoding: string): Boolean;
begin
  Result := True;
  if Copy(AText, 1, 3) = #$EF#$BB#$BF then
  begin
    AEncoding := EncodingUTF8;
    Delete(AText, 1, 3);
  end
  else if Copy(AText, 1, 2) = #$FF#$FE then
  begin
    AEncoding := EncodingUCS2LE;
    Delete(AText, 1, 2);
  end
  else if Copy(AText, 1, 2) = #$FE#$FF then
  begin
    AEncoding := EncodingUCS2BE;
    Delete(AText, 1, 2);
  end
  else
  begin
    AEncoding := '';
    Result := False;
  end;
end;

{ Collapses CRLF and lone CR to LF.  Done in one pass over the raw bytes,
  which matters because "open a 200 MB log" is a supported operation. }
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

procedure LedLoadTextFile(const AFileName: string; out AText: string;
  out AInfo: TLedTextInfo);
var
  Stream: TFileStream;
  Raw: string;
begin
  Raw := '';
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Raw, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Raw[1], Stream.Size);
  finally
    Stream.Free;
  end;

  AInfo := Default(TLedTextInfo);
  AInfo.HasBOM := LedStripBOM(Raw, AInfo.Encoding);
  if AInfo.Encoding = '' then
    AInfo.Encoding := EncodingUTF8;

  if AInfo.Encoding <> EncodingUTF8 then
    Raw := ConvertEncoding(Raw, AInfo.Encoding, EncodingUTF8);

  AInfo.LineEnd := LedDetectLineEnd(Raw);
  AInfo.TrailingEOL := (Raw <> '') and (Raw[Length(Raw)] in [#10, #13]);
  AText := NormaliseToLF(Raw);
end;

procedure LedSaveTextFile(const AFileName, AText: string;
  const AInfo: TLedTextInfo);
var
  Stream: TFileStream;
  Data: string;
begin
  Data := ExpandFromLF(AText, AInfo.LineEnd);

  if (AInfo.Encoding <> '') and (AInfo.Encoding <> EncodingUTF8) then
    Data := ConvertEncoding(Data, EncodingUTF8, AInfo.Encoding);

  if AInfo.HasBOM then
    if AInfo.Encoding = EncodingUCS2LE then Data := #$FF#$FE + Data
    else if AInfo.Encoding = EncodingUCS2BE then Data := #$FE#$FF + Data
    else Data := #$EF#$BB#$BF + Data;

  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if Data <> '' then
      Stream.WriteBuffer(Data[1], Length(Data));
  finally
    Stream.Free;
  end;
end;

end.
