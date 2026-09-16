// led - a lightweight editor.  Reading and writing Jupyter notebooks.
//
// A .ipynb file is JSON, and almost none of it is LED's business.  A notebook
// carries kernel metadata, widget state, per-cell attachments, tags other
// tools put there and fields from versions of the format that did not exist
// when this was written.  An editor that parsed the parts it understood and
// wrote back only those would quietly delete the rest, and the reader would
// find out when something else stopped working.
//
// So the whole document is kept as parsed JSON and only the pieces being
// edited are touched.  What LED knows about is the cell list, each cell's
// source, its outputs and its execution count; everything else is carried
// from the file to the file.
//
// Saving writes the layout nbformat itself writes: one space of indent, keys
// in sorted order, non-ASCII left as itself, a trailing newline.  That is
// not decoration.  Notebooks live in version control, and a file saved here
// that came from Jupyter has to come out byte for byte the same or every
// save is a diff of the whole file.  The check for this reads a notebook
// nbformat wrote and compares the bytes.
//
// The JSON is read here rather than by fcl-json, which is the one part of
// this that was not a free choice.  Measured on a 47 KB notebook of lecture
// notes: fcl-json read "\u26a0\ufe0f" -- a warning sign and the variation
// selector after it -- as four bytes instead of six, dropping two of them,
// and turned "\ud83d\udccc" into "??".  Both read correctly on their own and
// wrongly inside the file, so what is wrong moves with the size or the
// position of the document.  A notebook that comes back from an editor with
// two bytes missing out of a heading is not a notebook that was edited, so
// the reader below is LED's own, and every escape it decodes is decoded in
// one place where it can be checked.
//
// The containers are still fcl-json's.  Those hold what they are given; it
// was the scanner that was wrong.

unit Led.Core.NBFormat;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

type
  { What a cell holds.  Raw cells are carried and shown but have no meaning
    of their own -- they are whatever the reader's toolchain makes of them. }
  TLedNBCellKind = (nbkCode, nbkMarkdown, nbkRaw);

  TLedNotebook = class
  private
    FRoot: TJSONObject;
    FCells: TJSONArray;
    function CellAt(AIndex: Integer): TJSONObject;
    function MetaOf(const AKey: string): TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;

    { Reads ARaw.  False leaves the notebook as it was and says what was
      wrong with the file; the caller shows it as a hex dump or refuses to
      open, the same as a BJData file that will not decode. }
    function LoadFromText(const ARaw: string; out AError: string): Boolean;
    { The file, as nbformat would have written it. }
    function SaveToText: string;

    function CellCount: Integer;
    function CellKind(AIndex: Integer): TLedNBCellKind;
    { The cell's source as one string, newline-separated, with no trailing
      newline -- which is how the buffer holds it and how a person thinks of
      it.  The file stores it as a list of lines with the newlines on the end
      of each, and that is a detail of the file. }
    function CellSource(AIndex: Integer): string;
    procedure SetCellSource(AIndex: Integer; const AText: string);
    { -1 where the file says null, which means "not run since it was last
      cleared" and is what a fresh cell has. }
    function CellExecutionCount(AIndex: Integer): Integer;
    procedure SetCellExecutionCount(AIndex, AValue: Integer);

    { The cell's outputs, as they are in the file.  Code cells have them;
      anything else has none and this is nil. }
    function CellOutputs(AIndex: Integer): TJSONArray;
    procedure ClearCellOutputs(AIndex: Integer);
    { Takes ownership of AOutput. }
    procedure AddCellOutput(AIndex: Integer; AOutput: TJSONObject);

    { Which kernel the notebook was written against, from its metadata:
      'python3', 'octave'.  Empty when the file does not say, which is not an
      error -- a notebook that has never been run may have no kernelspec. }
    function KernelName: string;
    { The language those code cells are in, as the file names it: 'python',
      'octave'.  This is what the view colours them with. }
    function LanguageName: string;

    property Root: TJSONObject read FRoot;
  end;

{ Whether a name is a notebook.  Only .ipynb: the format has no other
  extension, and guessing from content would open every JSON file as one. }
function LedNBIsNotebookName(const AFileName: string): Boolean;

{ One string as a JSON string: quoted, with the escapes Python uses and no
  others.  Public because the kernel protocol is JSON too, and a command that
  carries a cell of Python has to escape it by exactly these rules. }
function LedNBJSONString(const AText: string): string;

{ One JSON value, written the way Python's json.dumps writes it with
  indent=1, sort_keys=True and ensure_ascii=False -- which is what nbformat
  calls, and therefore what every notebook on disk already looks like.

  Public because it is the whole of the round-trip promise, and a check of it
  should not have to go through a notebook to get at it. }
function LedNBWriteJSON(AValue: TJSONData): string;

{ The other direction, and LED's own for the reason in the file header.  nil
  means the text is not JSON, and AError says what stopped it and where. }
function LedNBParseJSON(const AText: string; out AError: string): TJSONData;

implementation

const
  { Where a cell's pieces live.  Named rather than spelled out at each use so
    that a typo is a compile error instead of a field that is silently never
    found. }
  KeyCells = 'cells';
  KeyType = 'cell_type';
  KeySource = 'source';
  KeyOutputs = 'outputs';
  KeyExecCount = 'execution_count';
  KeyMetadata = 'metadata';

function LedNBIsNotebookName(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.ipynb');
end;

{ ---- writing ---- }

{ A JSON string, escaped as Python escapes it: the two characters that must
  be, the five control characters with short forms, the rest of the controls
  as \u00xx -- and nothing else.  ensure_ascii is off, so text in any
  language is written as itself rather than as a row of escapes. }
function JSONText(const AValue: string): string;
var
  i: Integer;
  c: Char;
  B: TStringBuilder;
begin
  B := TStringBuilder.Create;
  try
    B.Append('"');
    for i := 1 to Length(AValue) do
    begin
      c := AValue[i];
      case c of
        '"':  B.Append('\"');
        '\':  B.Append('\\');
        #8:   B.Append('\b');
        #9:   B.Append('\t');
        #10:  B.Append('\n');
        #12:  B.Append('\f');
        #13:  B.Append('\r');
      else
        if c < ' ' then
          { Lower case, because that is what Python writes and an escape in
            somebody's traceback is not worth a whole-file diff. }
          B.Append('\u' + LowerCase(IntToHex(Ord(c), 4)))
        else
          B.Append(c);
      end;
    end;
    B.Append('"');
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

{ A float as Python's repr writes it: the shortest text that reads back as
  the same number, and a '.0' on the end of anything that would otherwise
  look like an integer.  Notebooks hold few of these -- a version number in
  somebody's metadata -- but a file that comes back with 1.0 as 1 is a file
  that changed. }
function FloatText(AValue: Double): string;
var
  Digits: Integer;
  S: string;
  Fmt: TFormatSettings;
  Back: Double;
  E: Integer;
begin
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  Fmt.ThousandSeparator := #0;

  Result := '';
  for Digits := 15 to 17 do
  begin
    S := FloatToStrF(AValue, ffGeneral, Digits, 0, Fmt);
    if TryStrToFloat(S, Back, Fmt) and (Back = AValue) then
    begin
      Result := S;
      Break;
    end;
  end;
  if Result = '' then Result := FloatToStrF(AValue, ffGeneral, 17, 0, Fmt);

  { FPC writes E+004 where Python writes e+04, and neither the case nor the
    padding is ours to keep. }
  E := Pos('E', UpperCase(Result));
  if E > 0 then
  begin
    S := Copy(Result, E + 1, MaxInt);
    Result := Copy(Result, 1, E - 1);
    if (S <> '') and (S[1] in ['+', '-']) then
    begin
      while (Length(S) > 3) and (S[2] = '0') do Delete(S, 2, 1);
      Result := Result + 'e' + S;
    end
    else
      Result := Result + 'e+' + S;
  end
  else if (Pos('.', Result) = 0) and (Pos('n', LowerCase(Result)) = 0) then
    Result := Result + '.0';
end;

{ Byte order, which for UTF-8 text is code-point order -- what Python
  compares when it sorts keys.  Not a locale-aware comparison: that would
  put the keys in an order that depends on where the machine thinks it is. }
function CompareKeys(AList: TStringList; A, B: Integer): Integer;
begin
  Result := CompareStr(AList[A], AList[B]);
end;

{ The keys of an object in the order Python sorts them. }
procedure SortedKeys(AObject: TJSONObject; AInto: TStringList);
var
  i: Integer;
begin
  AInto.Clear;
  for i := 0 to AObject.Count - 1 do AInto.Add(AObject.Names[i]);
  AInto.CustomSort(@CompareKeys);
end;

function WriteValue(AValue: TJSONData; ALevel: Integer): string; forward;

function WriteObject(AObject: TJSONObject; ALevel: Integer): string;
var
  Keys: TStringList;
  B: TStringBuilder;
  Pad, Inner: string;
  i: Integer;
begin
  if AObject.Count = 0 then Exit('{}');
  Pad := StringOfChar(' ', ALevel);
  Inner := StringOfChar(' ', ALevel + 1);
  Keys := TStringList.Create;
  B := TStringBuilder.Create;
  try
    SortedKeys(AObject, Keys);
    B.Append('{'#10);
    for i := 0 to Keys.Count - 1 do
    begin
      B.Append(Inner);
      B.Append(JSONText(Keys[i]));
      B.Append(': ');
      B.Append(WriteValue(AObject.Elements[Keys[i]], ALevel + 1));
      if i < Keys.Count - 1 then B.Append(',');
      B.Append(#10);
    end;
    B.Append(Pad);
    B.Append('}');
    Result := B.ToString;
  finally
    B.Free;
    Keys.Free;
  end;
end;

function WriteArray(AArray: TJSONArray; ALevel: Integer): string;
var
  B: TStringBuilder;
  Pad, Inner: string;
  i: Integer;
begin
  if AArray.Count = 0 then Exit('[]');
  Pad := StringOfChar(' ', ALevel);
  Inner := StringOfChar(' ', ALevel + 1);
  B := TStringBuilder.Create;
  try
    B.Append('['#10);
    for i := 0 to AArray.Count - 1 do
    begin
      B.Append(Inner);
      B.Append(WriteValue(AArray.Items[i], ALevel + 1));
      if i < AArray.Count - 1 then B.Append(',');
      B.Append(#10);
    end;
    B.Append(Pad);
    B.Append(']');
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

function WriteValue(AValue: TJSONData; ALevel: Integer): string;
begin
  if (AValue = nil) or (AValue.JSONType = jtNull) then Exit('null');
  case AValue.JSONType of
    jtObject:  Result := WriteObject(TJSONObject(AValue), ALevel);
    jtArray:   Result := WriteArray(TJSONArray(AValue), ALevel);
    jtString:  Result := JSONText(AValue.AsString);
    jtBoolean: if AValue.AsBoolean then Result := 'true' else Result := 'false';
    jtNumber:
      if TJSONNumber(AValue).NumberType in [ntInteger, ntInt64, ntQWord] then
        Result := AValue.AsString
      else
        Result := FloatText(AValue.AsFloat);
  else
    Result := 'null';
  end;
end;

function LedNBWriteJSON(AValue: TJSONData): string;
begin
  Result := WriteValue(AValue, 0);
end;

function LedNBJSONString(const AText: string): string;
begin
  Result := JSONText(AText);
end;

{ ---- reading ---- }

{ A recursive-descent reader over the raw bytes.  It never converts the text
  to anything else: what is not an escape is copied byte for byte, and what
  is an escape is turned into UTF-8 here.  That is the whole reason it
  exists. }

type
  TLedJSONReader = class
  private
    FText: string;
    FAt: Integer;         // 1-based, the next byte to look at
    FError: string;
    procedure Fail(const AWhat: string);
    procedure SkipSpace;
    function AtEnd: Boolean; inline;
    function Peek: Char; inline;
    function ReadValue: TJSONData;
    function ReadString(out AValue: string): Boolean;
    function ReadObject: TJSONData;
    function ReadArray: TJSONData;
    function ReadNumber: TJSONData;
    function ReadWord(const AWord: string): Boolean;
  public
    function Parse(const AText: string; out AError: string): TJSONData;
  end;

{ One code point, as UTF-8, appended to a buffer that grows by doubling.
  ALen is the used length; the buffer is trimmed to it at the end. }
procedure AppendUTF8(var ABuf: string; var ALen: Integer; ACode: LongWord);

  procedure Put(AByte: Byte);
  begin
    if ALen >= Length(ABuf) then SetLength(ABuf, Length(ABuf) * 2 + 16);
    Inc(ALen);
    ABuf[ALen] := Chr(AByte);
  end;

begin
  if ACode < $80 then
    Put(ACode)
  else if ACode < $800 then
  begin
    Put($C0 or (ACode shr 6));
    Put($80 or (ACode and $3F));
  end
  else if ACode < $10000 then
  begin
    Put($E0 or (ACode shr 12));
    Put($80 or ((ACode shr 6) and $3F));
    Put($80 or (ACode and $3F));
  end
  else
  begin
    Put($F0 or (ACode shr 18));
    Put($80 or ((ACode shr 12) and $3F));
    Put($80 or ((ACode shr 6) and $3F));
    Put($80 or (ACode and $3F));
  end;
end;

function HexNibble(AChar: Char; out AValue: Integer): Boolean; forward;

{ The four hexadecimal digits of a \u escape, starting at AAt.  False when
  they are not four digits, and then ACode is not to be used. }
function HexQuad(const AText: string; AAt, ALimit: Integer;
  out ACode: LongWord): Boolean;
var
  i, Nibble: Integer;
begin
  ACode := 0;
  Result := AAt + 3 <= ALimit;
  if not Result then Exit;
  for i := 0 to 3 do
  begin
    if not HexNibble(AText[AAt + i], Nibble) then Exit(False);
    ACode := ACode * 16 + LongWord(Nibble);
  end;
end;

function HexNibble(AChar: Char; out AValue: Integer): Boolean;
begin
  Result := True;
  case AChar of
    '0'..'9': AValue := Ord(AChar) - Ord('0');
    'a'..'f': AValue := Ord(AChar) - Ord('a') + 10;
    'A'..'F': AValue := Ord(AChar) - Ord('A') + 10;
  else
    AValue := 0;
    Result := False;
  end;
end;

procedure TLedJSONReader.Fail(const AWhat: string);
begin
  if FError = '' then
    FError := Format('%s at byte %d', [AWhat, FAt - 1]);
end;

function TLedJSONReader.AtEnd: Boolean;
begin
  Result := FAt > Length(FText);
end;

function TLedJSONReader.Peek: Char;
begin
  if AtEnd then Result := #0 else Result := FText[FAt];
end;

procedure TLedJSONReader.SkipSpace;
begin
  while (not AtEnd) and (FText[FAt] in [' ', #9, #10, #13]) do Inc(FAt);
end;

function TLedJSONReader.ReadWord(const AWord: string): Boolean;
begin
  Result := (FAt + Length(AWord) - 1 <= Length(FText)) and
            (Copy(FText, FAt, Length(AWord)) = AWord);
  if Result then Inc(FAt, Length(AWord));
end;

{ A string, from the opening quote to the closing one.

  The common case -- no backslash anywhere in it -- is one Copy of the span,
  because a notebook is mostly strings and a per-character loop over a
  megabyte of them is the difference between opening now and opening
  presently. }
function TLedJSONReader.ReadString(out AValue: string): Boolean;
var
  Start, i, Len, k: Integer;
  Code, Low_: LongWord;
  Buf: string;
  Escaped: Boolean;
  c: Char;
begin
  Result := False;
  AValue := '';
  if Peek <> '"' then
  begin
    Fail('a string was expected');
    Exit;
  end;
  Inc(FAt);
  Start := FAt;

  Escaped := False;
  i := FAt;
  while i <= Length(FText) do
  begin
    c := FText[i];
    if c = '"' then Break;
    if c = '\' then
    begin
      Escaped := True;
      Inc(i, 2);         // whatever follows a backslash is part of the escape
      Continue;
    end;
    Inc(i);
  end;
  if i > Length(FText) then
  begin
    Fail('a string was never closed');
    Exit;
  end;

  if not Escaped then
  begin
    AValue := Copy(FText, Start, i - Start);
    FAt := i + 1;
    Exit(True);
  end;

  SetLength(Buf, (i - Start) + 16);
  Len := 0;
  k := Start;
  while k < i do
  begin
    c := FText[k];
    if c <> '\' then
    begin
      if Len >= Length(Buf) then SetLength(Buf, Length(Buf) * 2 + 16);
      Inc(Len);
      Buf[Len] := c;
      Inc(k);
      Continue;
    end;

    Inc(k);
    if k > i then Break;
    case FText[k] of
      '"':  begin AppendUTF8(Buf, Len, Ord('"')); Inc(k); end;
      '\':  begin AppendUTF8(Buf, Len, Ord('\')); Inc(k); end;
      '/':  begin AppendUTF8(Buf, Len, Ord('/')); Inc(k); end;
      'b':  begin AppendUTF8(Buf, Len, 8); Inc(k); end;
      'f':  begin AppendUTF8(Buf, Len, 12); Inc(k); end;
      'n':  begin AppendUTF8(Buf, Len, 10); Inc(k); end;
      'r':  begin AppendUTF8(Buf, Len, 13); Inc(k); end;
      't':  begin AppendUTF8(Buf, Len, 9); Inc(k); end;
      'u':
        begin
          Inc(k);
          if not HexQuad(FText, k, i - 1, Code) then
          begin
            Fail('a \u escape is not four hexadecimal digits');
            Exit;
          end;
          Inc(k, 4);
          { A character outside the basic plane is written as two escapes, a
            high surrogate and a low one, and means nothing on its own.  This
            is the pair fcl-json lost. }
          if (Code >= $D800) and (Code <= $DBFF) and (k + 1 <= i - 1) and
             (FText[k] = '\') and (FText[k + 1] = 'u') and
             HexQuad(FText, k + 2, i - 1, Low_) and
             (Low_ >= $DC00) and (Low_ <= $DFFF) then
          begin
            Code := $10000 + (Code - $D800) * $400 + (Low_ - $DC00);
            Inc(k, 6);
          end;
          { A surrogate with no partner is not a character.  Nothing can be
            written for it that is both valid UTF-8 and what was meant, so
            what goes in is the character that says exactly that. }
          if (Code >= $D800) and (Code <= $DFFF) then Code := $FFFD;
          AppendUTF8(Buf, Len, Code);
        end;
    else
      Fail('a backslash is followed by something that is not an escape');
      Exit;
    end;
  end;

  SetLength(Buf, Len);
  AValue := Buf;
  FAt := i + 1;
  Result := True;
end;

function TLedJSONReader.ReadNumber: TJSONData;
var
  Start: Integer;
  Text: string;
  IsFloat: Boolean;
  I64: Int64;
  D: Double;
  Fmt: TFormatSettings;
begin
  Result := nil;
  Start := FAt;
  IsFloat := False;
  if Peek = '-' then Inc(FAt);
  while (not AtEnd) and (FText[FAt] in ['0'..'9']) do Inc(FAt);
  if Peek = '.' then
  begin
    IsFloat := True;
    Inc(FAt);
    while (not AtEnd) and (FText[FAt] in ['0'..'9']) do Inc(FAt);
  end;
  if Peek in ['e', 'E'] then
  begin
    IsFloat := True;
    Inc(FAt);
    if Peek in ['+', '-'] then Inc(FAt);
    while (not AtEnd) and (FText[FAt] in ['0'..'9']) do Inc(FAt);
  end;

  Text := Copy(FText, Start, FAt - Start);
  if Text = '' then
  begin
    Fail('a value was expected');
    Exit;
  end;

  if not IsFloat then
  begin
    if TryStrToInt64(Text, I64) then
    begin
      if (I64 >= Low(Integer)) and (I64 <= High(Integer)) then
        Result := TJSONIntegerNumber.Create(Integer(I64))
      else
        Result := TJSONInt64Number.Create(I64);
      Exit;
    end;
    { Too big for Int64 -- legal JSON, and a float is the only thing left
      that can hold it. }
    IsFloat := True;
  end;

  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  Fmt.ThousandSeparator := #0;
  if not TryStrToFloat(Text, D, Fmt) then
  begin
    Fail(Format('"%s" is not a number', [Text]));
    Exit;
  end;
  Result := TJSONFloatNumber.Create(D);
end;

function TLedJSONReader.ReadArray: TJSONData;
var
  Arr: TJSONArray;
  Item: TJSONData;
begin
  Result := nil;
  Inc(FAt);                         // the [
  Arr := TJSONArray.Create;
  try
    SkipSpace;
    if Peek = ']' then
    begin
      Inc(FAt);
      Exit(Arr);
    end;
    repeat
      SkipSpace;
      Item := ReadValue;
      if Item = nil then Exit;
      Arr.Add(Item);
      SkipSpace;
      if Peek = ',' then
      begin
        Inc(FAt);
        Continue;
      end;
      if Peek = ']' then
      begin
        Inc(FAt);
        Exit(Arr);
      end;
      Fail('a comma or a closing bracket was expected');
      Exit;
    until False;
  finally
    { Arr is the result on the way out, and rubbish on the way to an error. }
    if Result = nil then Arr.Free;
  end;
end;

function TLedJSONReader.ReadObject: TJSONData;
var
  Obj: TJSONObject;
  Key: string;
  Value: TJSONData;
begin
  Result := nil;
  Inc(FAt);                         // the {
  Obj := TJSONObject.Create;
  try
    SkipSpace;
    if Peek = '}' then
    begin
      Inc(FAt);
      Exit(Obj);
    end;
    repeat
      SkipSpace;
      if not ReadString(Key) then Exit;
      SkipSpace;
      if Peek <> ':' then
      begin
        Fail('a colon was expected after a key');
        Exit;
      end;
      Inc(FAt);
      SkipSpace;
      Value := ReadValue;
      if Value = nil then Exit;
      { A repeated key is not something to guess about: the last one wins,
        which is what every JSON reader in the world does. }
      if Obj.IndexOfName(Key) >= 0 then Obj.Delete(Obj.IndexOfName(Key));
      Obj.Add(Key, Value);
      SkipSpace;
      if Peek = ',' then
      begin
        Inc(FAt);
        Continue;
      end;
      if Peek = '}' then
      begin
        Inc(FAt);
        Exit(Obj);
      end;
      Fail('a comma or a closing brace was expected');
      Exit;
    until False;
  finally
    if Result = nil then Obj.Free;
  end;
end;

function TLedJSONReader.ReadValue: TJSONData;
var
  Text: string;
begin
  Result := nil;
  SkipSpace;
  if AtEnd then
  begin
    Fail('the file ends where a value was expected');
    Exit;
  end;
  case Peek of
    '{': Result := ReadObject;
    '[': Result := ReadArray;
    '"':
      if ReadString(Text) then Result := TJSONString.Create(Text);
    't':
      if ReadWord('true') then Result := TJSONBoolean.Create(True)
      else Fail('a value was expected');
    'f':
      if ReadWord('false') then Result := TJSONBoolean.Create(False)
      else Fail('a value was expected');
    'n':
      if ReadWord('null') then Result := TJSONNull.Create
      else Fail('a value was expected');
    '-', '0'..'9':
      Result := ReadNumber;
  else
    Fail('a value was expected');
  end;
end;

function TLedJSONReader.Parse(const AText: string; out AError: string): TJSONData;
begin
  FText := AText;
  FAt := 1;
  FError := '';
  Result := ReadValue;
  if Result <> nil then
  begin
    SkipSpace;
    if not AtEnd then
    begin
      Fail('there is more in the file after the end of the JSON');
      FreeAndNil(Result);
    end;
  end;
  AError := FError;
end;

function LedNBParseJSON(const AText: string; out AError: string): TJSONData;
var
  Reader: TLedJSONReader;
begin
  AError := '';
  Reader := TLedJSONReader.Create;
  try
    Result := Reader.Parse(AText, AError);
  finally
    Reader.Free;
  end;
  if (Result = nil) and (AError = '') then AError := 'the file is not JSON';
end;

{ ---- the notebook ---- }

constructor TLedNotebook.Create;
begin
  inherited Create;
  FRoot := TJSONObject.Create;
  FCells := TJSONArray.Create;
  FRoot.Add(KeyCells, FCells);
  FRoot.Add(KeyMetadata, TJSONObject.Create);
  FRoot.Add('nbformat', 4);
  FRoot.Add('nbformat_minor', 5);
end;

destructor TLedNotebook.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TLedNotebook.LoadFromText(const ARaw: string;
  out AError: string): Boolean;
var
  Parsed: TJSONData;
  Cells: TJSONData;
begin
  Result := False;
  Parsed := LedNBParseJSON(ARaw, AError);
  if Parsed = nil then Exit;

  try
    if (Parsed = nil) or (Parsed.JSONType <> jtObject) then
    begin
      AError := 'the file is not a JSON object';
      Exit;
    end;
    Cells := TJSONObject(Parsed).Find(KeyCells);
    if (Cells = nil) or (Cells.JSONType <> jtArray) then
    begin
      AError := 'there is no list of cells, so this is not a notebook';
      Exit;
    end;

    FRoot.Free;
    FRoot := TJSONObject(Parsed);
    Parsed := nil;                  // owned by the notebook now
    FCells := TJSONArray(Cells);
    Result := True;
  finally
    Parsed.Free;
  end;
end;

function TLedNotebook.SaveToText: string;
begin
  { The newline nbformat puts on the end.  Without it every save of an
    untouched file is a one-line diff. }
  Result := LedNBWriteJSON(FRoot) + #10;
end;

function TLedNotebook.CellAt(AIndex: Integer): TJSONObject;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex >= FCells.Count) then Exit;
  if FCells.Items[AIndex].JSONType <> jtObject then Exit;
  Result := TJSONObject(FCells.Items[AIndex]);
end;

function TLedNotebook.MetaOf(const AKey: string): TJSONObject;
var
  Meta, Sub: TJSONData;
begin
  Result := nil;
  Meta := FRoot.Find(KeyMetadata);
  if (Meta = nil) or (Meta.JSONType <> jtObject) then Exit;
  Sub := TJSONObject(Meta).Find(AKey);
  if (Sub = nil) or (Sub.JSONType <> jtObject) then Exit;
  Result := TJSONObject(Sub);
end;

function TLedNotebook.CellCount: Integer;
begin
  Result := FCells.Count;
end;

function TLedNotebook.CellKind(AIndex: Integer): TLedNBCellKind;
var
  Cell: TJSONObject;
  Kind: TJSONData;
begin
  { Raw is the fallback rather than code: a cell of an unknown type is
    carried and shown, and running something because its type was not
    recognised is the one wrong answer. }
  Result := nbkRaw;
  Cell := CellAt(AIndex);
  if Cell = nil then Exit;
  Kind := Cell.Find(KeyType);
  if (Kind = nil) or (Kind.JSONType <> jtString) then Exit;
  if Kind.AsString = 'code' then Result := nbkCode
  else if Kind.AsString = 'markdown' then Result := nbkMarkdown;
end;

{ A source or a text output: the file holds either a list of lines with their
  newlines attached, or one string.  Both are legal and both are in the wild,
  so both are read. }
function JoinLines(AValue: TJSONData): string;
var
  i: Integer;
  Arr: TJSONArray;
begin
  Result := '';
  if AValue = nil then Exit;
  if AValue.JSONType = jtString then Exit(AValue.AsString);
  if AValue.JSONType <> jtArray then Exit;
  Arr := TJSONArray(AValue);
  for i := 0 to Arr.Count - 1 do
    if Arr.Items[i].JSONType = jtString then
      Result := Result + Arr.Items[i].AsString;
end;

{ The other direction: one string back into the list of lines the file
  keeps, each with its newline except the last.  An empty cell is an empty
  list, which is what Jupyter writes for one. }
function SplitLines(const AText: string): TJSONArray;
var
  Start, i: Integer;
begin
  Result := TJSONArray.Create;
  if AText = '' then Exit;
  Start := 1;
  for i := 1 to Length(AText) do
    if AText[i] = #10 then
    begin
      Result.Add(Copy(AText, Start, i - Start + 1));
      Start := i + 1;
    end;
  if Start <= Length(AText) then
    Result.Add(Copy(AText, Start, MaxInt));
end;

function TLedNotebook.CellSource(AIndex: Integer): string;
var
  Cell: TJSONObject;
begin
  Result := '';
  Cell := CellAt(AIndex);
  if Cell = nil then Exit;
  Result := JoinLines(Cell.Find(KeySource));
  { The file's trailing newline is punctuation between lines, not a line of
    its own; a buffer that showed it would grow an empty line per cell. }
  if (Result <> '') and (Result[Length(Result)] = #10) then
    SetLength(Result, Length(Result) - 1);
end;

procedure TLedNotebook.SetCellSource(AIndex: Integer; const AText: string);
var
  Cell: TJSONObject;
  At: Integer;
begin
  Cell := CellAt(AIndex);
  if Cell = nil then Exit;
  At := Cell.IndexOfName(KeySource);
  if At >= 0 then Cell.Delete(At);
  Cell.Add(KeySource, SplitLines(AText));
end;

function TLedNotebook.CellExecutionCount(AIndex: Integer): Integer;
var
  Cell: TJSONObject;
  N: TJSONData;
begin
  Result := -1;
  Cell := CellAt(AIndex);
  if Cell = nil then Exit;
  N := Cell.Find(KeyExecCount);
  if (N = nil) or (N.JSONType <> jtNumber) then Exit;
  Result := N.AsInteger;
end;

procedure TLedNotebook.SetCellExecutionCount(AIndex, AValue: Integer);
var
  Cell: TJSONObject;
  At: Integer;
begin
  Cell := CellAt(AIndex);
  if Cell = nil then Exit;
  At := Cell.IndexOfName(KeyExecCount);
  if At >= 0 then Cell.Delete(At);
  if AValue < 0 then
    Cell.Add(KeyExecCount, TJSONNull.Create)
  else
    Cell.Add(KeyExecCount, AValue);
end;

function TLedNotebook.CellOutputs(AIndex: Integer): TJSONArray;
var
  Cell: TJSONObject;
  Outs: TJSONData;
begin
  Result := nil;
  Cell := CellAt(AIndex);
  if Cell = nil then Exit;
  Outs := Cell.Find(KeyOutputs);
  if (Outs <> nil) and (Outs.JSONType = jtArray) then Result := TJSONArray(Outs);
end;

procedure TLedNotebook.ClearCellOutputs(AIndex: Integer);
var
  Cell: TJSONObject;
  At: Integer;
begin
  Cell := CellAt(AIndex);
  if Cell = nil then Exit;
  if CellKind(AIndex) <> nbkCode then Exit;
  At := Cell.IndexOfName(KeyOutputs);
  if At >= 0 then Cell.Delete(At);
  Cell.Add(KeyOutputs, TJSONArray.Create);
end;

procedure TLedNotebook.AddCellOutput(AIndex: Integer; AOutput: TJSONObject);
var
  Outs: TJSONArray;
begin
  Outs := CellOutputs(AIndex);
  if Outs = nil then
  begin
    AOutput.Free;
    Exit;
  end;
  Outs.Add(AOutput);
end;

function TLedNotebook.KernelName: string;
var
  Spec: TJSONObject;
  N: TJSONData;
begin
  Result := '';
  Spec := MetaOf('kernelspec');
  if Spec = nil then Exit;
  N := Spec.Find('name');
  if (N <> nil) and (N.JSONType = jtString) then Result := N.AsString;
end;

function TLedNotebook.LanguageName: string;
var
  Info, Spec: TJSONObject;
  N: TJSONData;
begin
  Result := '';
  Info := MetaOf('language_info');
  if Info <> nil then
  begin
    N := Info.Find('name');
    if (N <> nil) and (N.JSONType = jtString) then Exit(N.AsString);
  end;
  { A notebook that has never been run has no language_info, but its
    kernelspec still says which kernel it is for, and the two agree often
    enough to be worth falling back on. }
  Spec := MetaOf('kernelspec');
  if Spec = nil then Exit;
  N := Spec.Find('language');
  if (N <> nil) and (N.JSONType = jtString) then Result := N.AsString;
end;

end.
