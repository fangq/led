{ led - a light editor.  Character-encoding names and detection helpers.

  medit named encodings the way iconv does ("UTF-8", "ISO_8859-15"); Lazarus
  names them the way LConvEncoding does ("utf8", "iso885915").  Everything
  inside led uses the LConvEncoding spelling, and this unit is the single
  place that translates, so a preference file or a modeline written in either
  dialect still resolves. }
unit Led.Core.Encodings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LConvEncoding, LazUTF8;

const
  { The literal a user writes to mean "whatever this machine's locale is".
    Kept spelled as medit spelled it so existing habits carry over. }
  LedEncodingLocale = 'LOCALE';

  { Tried in order when a file carries no BOM and the user has not forced an
    encoding.  Same list and same order as medit's default: UTF-8 first
    because it is right almost always, then the locale charset, then the two
    Latin variants that cover most remaining source files.  ISO-8859-1 accepts
    any byte sequence at all, so it must stay last -- it is the fallback that
    never fails. }
  LedDefaultEncodingList = 'utf8,' + LedEncodingLocale + ',iso885915,iso88591';

{ Maps a name from any dialect onto the LConvEncoding spelling.  Returns ''
  when the name is not recognised.  LedEncodingLocale resolves to this
  machine's charset. }
function LedNormaliseEncoding(const AName: string): string;

{ The charset of the current locale, in LConvEncoding spelling. }
function LedLocaleEncoding: string;

{ Human-facing name for the status bar and the encoding menu. }
function LedEncodingDisplayName(const AName: string): string;

{ True when the bytes are well-formed UTF-8.  This is what makes "try UTF-8
  first" trustworthy: invalid UTF-8 is rejected rather than mangled. }
function LedIsValidUTF8(const AData: string): Boolean;

{ Splits a comma-separated candidate list into normalised, de-duplicated
  encoding names. }
procedure LedParseEncodingList(const AList: string; AResult: TStrings);

implementation

type
  TAlias = record
    Alias, Canonical: string;
  end;

const
  { Only the spellings that actually turn up: iconv names as used by medit's
    preferences and modelines, plus the common punctuation variants. }
  Aliases: array[0..27] of TAlias = (
    (Alias: 'utf-8';        Canonical: EncodingUTF8),
    (Alias: 'utf8';         Canonical: EncodingUTF8),
    (Alias: 'us-ascii';     Canonical: EncodingUTF8),
    (Alias: 'ascii';        Canonical: EncodingUTF8),
    (Alias: 'utf-16le';     Canonical: EncodingUCS2LE),
    (Alias: 'ucs-2le';      Canonical: EncodingUCS2LE),
    (Alias: 'utf-16be';     Canonical: EncodingUCS2BE),
    (Alias: 'ucs-2be';      Canonical: EncodingUCS2BE),
    (Alias: 'iso_8859-1';   Canonical: EncodingCPIso1),
    (Alias: 'iso-8859-1';   Canonical: EncodingCPIso1),
    (Alias: 'latin1';       Canonical: EncodingCPIso1),
    (Alias: 'iso_8859-2';   Canonical: EncodingCPIso2),
    (Alias: 'iso-8859-2';   Canonical: EncodingCPIso2),
    (Alias: 'iso_8859-15';  Canonical: EncodingCPIso15),
    (Alias: 'iso-8859-15';  Canonical: EncodingCPIso15),
    (Alias: 'latin9';       Canonical: EncodingCPIso15),
    (Alias: 'windows-1250'; Canonical: EncodingCP1250),
    (Alias: 'windows-1251'; Canonical: EncodingCP1251),
    (Alias: 'windows-1252'; Canonical: EncodingCP1252),
    (Alias: 'windows-1256'; Canonical: EncodingCP1256),
    (Alias: 'koi8-r';       Canonical: EncodingCPKOI8R),
    (Alias: 'koi8-u';       Canonical: EncodingCPKOI8U),
    (Alias: 'gb2312';       Canonical: EncodingCP936),
    (Alias: 'gbk';          Canonical: EncodingCP936),
    (Alias: 'big5';         Canonical: EncodingCP950),
    (Alias: 'shift_jis';    Canonical: EncodingCP932),
    (Alias: 'sjis';         Canonical: EncodingCP932),
    (Alias: 'euc-kr';       Canonical: EncodingCP949)
  );

var
  FCanonical: TStringList = nil;

{ GetSupportedEncodings hands back display spellings ("UTF-8", "ISO-8859-1",
  "UCS-2LE"), not the internal ones the Encoding* constants use.  Running each
  through NormalizeEncoding -- lowercase, strip '-' -- lands exactly on the
  constant, so this is the authoritative set of names led considers canonical. }
function Canonical: TStringList;
var
  Raw: TStringList;
  i: Integer;
begin
  if FCanonical = nil then
  begin
    FCanonical := TStringList.Create;
    FCanonical.CaseSensitive := False;
    Raw := TStringList.Create;
    try
      GetSupportedEncodings(Raw);
      for i := 0 to Raw.Count - 1 do
        FCanonical.Add(NormalizeEncoding(Raw[i]));
    finally
      Raw.Free;
    end;
  end;
  Result := FCanonical;
end;

function LedLocaleEncoding: string;
begin
  Result := GetDefaultTextEncoding;
  if Result = '' then
    Result := EncodingUTF8;
end;

function LedNormaliseEncoding(const AName: string): string;
var
  Lower, Stripped: string;
  i: Integer;
begin
  Lower := LowerCase(Trim(AName));
  if Lower = '' then Exit('');

  if SameText(Lower, LedEncodingLocale) then
    Exit(LedLocaleEncoding);

  { Aliases first: they are the spellings that need real translation rather
    than mere punctuation cleanup. }
  for i := Low(Aliases) to High(Aliases) do
    if Aliases[i].Alias = Lower then
      Exit(Aliases[i].Canonical);

  if Canonical.IndexOf(NormalizeEncoding(Lower)) >= 0 then
    Exit(NormalizeEncoding(Lower));

  { Last resort: drop the punctuation iconv-style names carry, so
    "ISO_8859-15" and "ISO 8859 15" both reach "iso885915". }
  Stripped := Lower;
  Stripped := StringReplace(Stripped, '-', '', [rfReplaceAll]);
  Stripped := StringReplace(Stripped, '_', '', [rfReplaceAll]);
  Stripped := StringReplace(Stripped, ' ', '', [rfReplaceAll]);
  if Canonical.IndexOf(Stripped) >= 0 then
    Exit(Stripped);

  Result := '';
end;

function LedEncodingDisplayName(const AName: string): string;
begin
  if AName = EncodingUTF8 then Result := 'UTF-8'
  else if AName = EncodingUCS2LE then Result := 'UTF-16LE'
  else if AName = EncodingUCS2BE then Result := 'UTF-16BE'
  else if AName = EncodingCPIso1 then Result := 'ISO-8859-1'
  else if AName = EncodingCPIso15 then Result := 'ISO-8859-15'
  else if Copy(AName, 1, 2) = 'cp' then
    Result := 'CP' + Copy(AName, 3, MaxInt)
  else
    Result := UpperCase(AName);
end;

function LedIsValidUTF8(const AData: string): Boolean;
begin
  if AData = '' then Exit(True);
  Result := FindInvalidUTF8Codepoint(PChar(AData), Length(AData)) < 0;
end;

procedure LedParseEncodingList(const AList: string; AResult: TStrings);
var
  Parts: TStringArray;
  i: Integer;
  Enc: string;
begin
  AResult.Clear;
  Parts := AList.Split([',']);
  for i := 0 to High(Parts) do
  begin
    Enc := LedNormaliseEncoding(Parts[i]);
    if (Enc <> '') and (AResult.IndexOf(Enc) < 0) then
      AResult.Add(Enc);
  end;
end;

finalization
  FCanonical.Free;

end.
