// led - a lightweight editor.  Changing one value in a BJData file.
//
// The structure view shows a file record by record; this is what happens when
// the reader types a new value into one of those records.  It works on the
// bytes, not on a parsed tree, for the same reason the view does: these files
// reach tens of megabytes and hold millions of records, and turning one into
// objects to change six bytes in the middle of it is not a trade worth
// making.
//
// Two ways a value can change, and the difference is worth keeping visible.
//
//   Patched.  The new value encodes to exactly as many bytes as the old one,
//   so it is written where the old one was.  Nothing else in the file moves:
//   every offset the reader is looking at stays true, and the view re-renders
//   one row.  Editing an int32 to another int32, or a string to one of the
//   same length, is this.
//
//   Spliced.  The new value is a different size -- a longer string, a float
//   where an integer was -- so the old bytes are cut out and the new ones put
//   in, and everything after shifts.  The file is still valid because BJData
//   containers count their elements rather than measuring their bytes: no
//   header anywhere records how long the thing being replaced was.  That is
//   the property that makes this a splice and not a rewrite.  The offsets
//   below the edit all move, so the caller re-walks.
//
// The original marker is kept wherever the new value still fits it.  A file
// that stored a count as an int32 keeps storing it as an int32 after the
// count is changed to 7; shrinking it to the smallest marker that holds the
// number would quietly rewrite decisions the file's author made, and would
// turn most edits into splices for no reason.
//
// Only the value is editable here.  Keys, and adding or removing records, are
// structural: they change what a container holds, and a container that
// carries its element count has to have that count corrected in the same
// breath.  That is a separate piece of work and this file does not pretend to
// do it.

unit Led.Core.BJDEdit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, bjdata, Led.Core.BJDView;

type
  { What an edit did, or why it did nothing. }
  TLedBJEditKind = (
    bjeUnchanged,   // the new text says what the file already says
    bjePatched,     // written in place; no offset moved
    bjeSpliced,     // re-encoded; everything below the edit shifted
    bjeRefused);    // nothing was written, and AWhy says what stopped it

const
  { Every type a value can be written as, in the order the editor offers
    them.  'T' stands for a boolean of either value: which of the two bytes
    is written is what the text says, not what the type list says. }
  LedBJValueTypes = 'ZNTiUIulmLMBhdDSHC';

{ Reads ARow's value back as text to be edited: the number, the string
  without its quotes, "true", "null".  Not the rendering -- the rendering
  elides long values and quotes short ones, and neither is what anybody wants
  to type over. }
function LedBJValueText(const ARow: TLedBJRow): string;

{ Whether a row holds something this unit can change at all. }
function LedBJCanEdit(const ARow: TLedBJRow; out AWhy: string): Boolean;

{ Replaces ARow's value with ANewText, in ABytes.
//
  ABytes is the whole file.  On bjePatched or bjeSpliced it comes back
  changed; on anything else it is untouched.  ARow must have come from a walk
  of exactly these bytes, because its offset is where the writing happens.

  AAsMarker names the type to write it as; #0 means "the one the file uses,
  or the one the value needs", which is what typing into a row without
  choosing a type does. }
function LedBJEditValue(var ABytes: string; const ARow: TLedBJRow;
  const ANewText: string; out AWhy: string;
  AAsMarker: AnsiChar = #0): TLedBJEditKind;

{ The name the type list shows for a marker: 'int32', 'float64', 'string'. }
function LedBJTypeName(AMarker: AnsiChar): string;

{ The types AText could be written as, drawn from LedBJValueTypes and in that
  order.  A type is in the list because the text was encoded with it and read
  back unchanged, not because a table says the two go together.

  ACurrent is offered whenever it can hold the text at all, round trip or
  not.  A float32 field holding 0.1 cannot represent it exactly and never
  could; dropping the file's own type off the list would mean every edit of
  such a field changed it. }
function LedBJTypesFor(const AText: string; ACurrent: AnsiChar): string;

{ Which of those types the plain path writes when nobody chooses: the file's
  own where the value still fits it, the narrowest that holds the value where
  it does not.  #0 when the text is not a value at all. }
function LedBJMarkerFor(const AText: string; ACurrent: AnsiChar): AnsiChar;

{ The bytes one value encodes to, keeping AMarker when the value still fits
  it.  Public because it is the honest way to ask "how big would this be",
  which is what tells a patch from a splice before either is done.

  ALenMarker is the length marker a string already uses, kept when the new
  text still fits it; #0 picks the narrowest. }
function LedBJEncodeValue(const AText: string; AMarker, ALenMarker: AnsiChar;
  out ABytes: string; out AWhy: string): Boolean;

{ The same, with the type decided rather than inferred: AMarker is written
  whatever the text looks like, or the call fails saying why it will not fit.
  This is what a chosen type in the editor comes down to. }
function LedBJEncodeAs(const AText: string; AMarker, ALenMarker: AnsiChar;
  out ABytes: string; out AWhy: string): Boolean;

implementation

{ The byte arithmetic is done here rather than borrowed from the library: its
  own poke-an-integer and does-this-fit helpers are implementation-only, and
  reaching into a vendored unit to widen two functions is a worse bargain
  than twenty lines that can be read on their own. }

var
  { Numbers are typed by a person, and these files are scientific: a decimal
    point is a point wherever the machine happens to be set to Frankfurt. }
  EditFormat: TFormatSettings;

{ Whether AValue can be stored under AMarker, from the ranges the format
  gives each one. }
function IntFitsMarker(AValue: Int64; AMarker: AnsiChar): Boolean;
begin
  case AMarker of
    'i': Result := (AValue >= -128) and (AValue <= 127);
    'U', 'B': Result := (AValue >= 0) and (AValue <= 255);
    'I': Result := (AValue >= -32768) and (AValue <= 32767);
    'u': Result := (AValue >= 0) and (AValue <= 65535);
    'l': Result := (AValue >= -2147483648) and (AValue <= 2147483647);
    'm': Result := (AValue >= 0) and (AValue <= 4294967295);
    'L': Result := True;
    'M': Result := AValue >= 0;
  else
    Result := False;
  end;
end;

{ An unsigned integer of AMarker's width, little-endian, which is how BJData
  stores every fixed-width number. }
procedure PokeLE(var ADest: string; AAt: Integer; AMarker: AnsiChar;
  AValue: Int64);
var
  i, n: Integer;
  V: QWord;
begin
  n := BJMarkerSize(AMarker);
  V := QWord(AValue);
  for i := 0 to n - 1 do
    ADest[AAt + i] := Chr((V shr (8 * i)) and $FF);
end;

function BytesToStr(const ABytes: TBytes): string;
begin
  SetLength(Result, Length(ABytes));
  if Length(ABytes) > 0 then
    Move(ABytes[0], Result[1], Length(ABytes));
end;

function LedBJValueText(const ARow: TLedBJRow): string;
begin
  Result := '';
  if not ARow.Value.IsValid then Exit;
  case ARow.Value.Kind of
    bjkNull:    Result := 'null';
    bjkNoOp:    Result := 'no-op';
    bjkBoolean: if ARow.Value.AsBoolean then Result := 'true' else Result := 'false';
    bjkInt:     Result := IntToStr(ARow.Value.AsInt64);
    bjkUInt:    Result := IntToStr(ARow.Value.AsQWord);
    bjkFloat:   Result := BJFloatToStr(ARow.Value.AsDouble);
    { The text itself, not the quoted rendering: what is being edited is the
      string, and the quotes are the view's punctuation. }
    bjkString:  Result := ARow.Value.AsString;
  end;
end;

function LedBJCanEdit(const ARow: TLedBJRow; out AWhy: string): Boolean;
begin
  AWhy := '';
  Result := False;

  if not ARow.Value.IsValid then
  begin
    AWhy := 'this row is not a record of the file';
    Exit;
  end;

  { A container is its children: there is no single value here to type over,
    and the rows underneath are where its contents are edited. }
  if ARow.Value.IsContainer then
  begin
    AWhy := 'a container has no value of its own; edit the records inside it';
    Exit;
  end;

  { A typed array is one row holding many numbers.  Changing one of them is a
    real thing to want and needs a way to say which -- that is an editor for
    the array, not a value to type over. }
  if ARow.Value.IsNDArray or ARow.Value.IsSoA then
  begin
    AWhy := 'a typed array is edited element by element, which is not built yet';
    Exit;
  end;

  case ARow.Value.Kind of
    bjkNull, bjkNoOp, bjkBoolean, bjkInt, bjkUInt, bjkFloat, bjkString:
      Result := True;
  else
    AWhy := 'this kind of value cannot be edited yet';
  end;
end;

{ Whether a marker holds a whole number.  The library's own predicate leaves
  out B, the byte type, because it is not one of UBJSON's integers -- but a
  number typed into a B field is still a number, and rewriting it as an i
  would take away a type the file chose. }
function IsWholeMarker(AMarker: AnsiChar): Boolean;
begin
  Result := BJIsIntMarker(AMarker) or (AMarker = 'B');
end;

function LedBJTypeName(AMarker: AnsiChar): string;
begin
  case AMarker of
    'Z': Result := 'null';
    'N': Result := 'no-op';
    'T', 'F': Result := 'boolean';
    'i': Result := 'int8';
    'U': Result := 'uint8';
    'B': Result := 'byte';
    'I': Result := 'int16';
    'u': Result := 'uint16';
    'l': Result := 'int32';
    'm': Result := 'uint32';
    'L': Result := 'int64';
    'M': Result := 'uint64';
    'h': Result := 'float16';
    'd': Result := 'float32';
    'D': Result := 'float64';
    'S': Result := 'string';
    'H': Result := 'high-precision';
    'C': Result := 'char';
  else
    Result := AMarker;
  end;
end;

{ A whole number of AMarker's width, marker and all. }
function WholeBytes(AMarker: AnsiChar; AValue: QWord): string;
begin
  SetLength(Result, 1 + BJMarkerSize(AMarker));
  Result[1] := AMarker;
  PokeLE(Result, 2, AMarker, Int64(AValue));
end;

{ A float of AMarker's width.  The library does the conversion, which for
  float16 is not something to write twice. }
function FloatBytes(AMarker: AnsiChar; AValue: Double): string;
var
  Node: TBJData;
begin
  Node := TBJData.NewFloat(AValue, AMarker);
  try
    Result := BytesToStr(Node.ToBytes);
  finally
    Node.Free;
  end;
end;

{ A string's own bytes: the marker, a length marker, the length, the text.
  Written here rather than taken from TBJData.NewString().ToBytes because
  that call picks the marker as well as the length, and both are the
  caller's to keep: a file's H is a high-precision number, and a value that
  came back from one edit as an S would have become text. }
function StringBytes(const AText: string; AMarker, ALenMarker: AnsiChar): string;
var
  n: Int64;
  LM: AnsiChar;
begin
  n := Length(AText);
  { The file's own length marker where the text still fits it, which is what
    keeps a same-length edit a patch; otherwise the narrowest that holds it. }
  if (ALenMarker <> #0) and BJIsIntMarker(ALenMarker) and
     IntFitsMarker(n, ALenMarker) then
    LM := ALenMarker
  else
    LM := BJIntMarkerFor(n);

  SetLength(Result, 2 + BJMarkerSize(LM) + n);
  Result[1] := AMarker;
  Result[2] := LM;
  PokeLE(Result, 3, LM, n);
  if n > 0 then Move(AText[1], Result[3 + BJMarkerSize(LM)], n);
end;

function LedBJEncodeAs(const AText: string; AMarker, ALenMarker: AnsiChar;
  out ABytes: string; out AWhy: string): Boolean;
var
  Trimmed: string;
  I: Int64;
  Q: QWord;
  D: Double;
begin
  ABytes := '';
  AWhy := '';
  Trimmed := Trim(AText);

  case AMarker of
    'Z':
      if SameText(Trimmed, 'null') then ABytes := 'Z'
      else AWhy := 'null holds nothing else';
    'N':
      if SameText(Trimmed, 'no-op') then ABytes := 'N'
      else AWhy := 'a no-op holds nothing else';
    'T', 'F':
      if SameText(Trimmed, 'true') then ABytes := 'T'
      else if SameText(Trimmed, 'false') then ABytes := 'F'
      else AWhy := 'a boolean is true or false';
    'i', 'U', 'B', 'I', 'u', 'l', 'm', 'L', 'M':
      if TryStrToInt64(Trimmed, I) then
      begin
        if IntFitsMarker(I, AMarker) then
          ABytes := WholeBytes(AMarker, QWord(I))
        else
          AWhy := Format('%s does not reach %s',
            [LedBJTypeName(AMarker), Trimmed]);
      end
      { Past Int64 there is one type left that can hold the number, and a
        file that uses it holds values this side of the line too. }
      else if (AMarker = 'M') and TryStrToQWord(Trimmed, Q) then
        ABytes := WholeBytes(AMarker, Q)
      else
        AWhy := Format('"%s" is not a whole number', [Trimmed]);
    'h', 'd', 'D':
      if TryStrToFloat(Trimmed, D, EditFormat) then
        ABytes := FloatBytes(AMarker, D)
      else
        AWhy := Format('"%s" is not a number', [Trimmed]);
    'S':
      ABytes := StringBytes(AText, AMarker, ALenMarker);
    'H':
      { High precision is a number written out in full, for values no float
        can hold.  It is stored as text, which is why it used to accept any:
        words written into one make a file that parses and says something
        that is not a number. }
      if TryStrToFloat(Trimmed, D, EditFormat) then
        ABytes := StringBytes(Trimmed, AMarker, ALenMarker)
      else
        AWhy := 'a high-precision value is a number written out in full';
    'C':
      if Length(AText) = 1 then ABytes := 'C' + AText
      else AWhy := 'a char holds one byte; use a string for more';
  else
    AWhy := Format('a %s cannot be typed into', [LedBJTypeName(AMarker)]);
  end;

  Result := ABytes <> '';
  if (not Result) and (AWhy = '') then AWhy := 'that is not a value';
end;

function LedBJEncodeValue(const AText: string; AMarker, ALenMarker: AnsiChar;
  out ABytes: string; out AWhy: string): Boolean;
var
  Trimmed: string;
  Pick: AnsiChar;
  I: Int64;
  Q: QWord;
  D: Double;
begin
  { A string is edited as text, whatever it looks like: a value that reads as
    a number is still a string if that is what the file holds, and typing 8
    into a string field means the string "8". }
  if AMarker in ['S', 'H', 'C'] then
    Exit(LedBJEncodeAs(AText, AMarker, ALenMarker, ABytes, AWhy));

  ABytes := '';
  AWhy := '';
  Trimmed := Trim(AText);

  if SameText(Trimmed, 'null') then Pick := 'Z'
  else if SameText(Trimmed, 'no-op') then Pick := 'N'
  else if SameText(Trimmed, 'true') or SameText(Trimmed, 'false') then Pick := 'T'
  else if TryStrToInt64(Trimmed, I) then
  begin
    { The file's own type, where the number still fits it. }
    if IsWholeMarker(AMarker) and IntFitsMarker(I, AMarker) then Pick := AMarker
    else if BJIsFloatMarker(AMarker) then Pick := AMarker
    else Pick := BJIntMarkerFor(I);
  end
  else if TryStrToQWord(Trimmed, Q) then
  begin
    if BJIsFloatMarker(AMarker) then Pick := AMarker else Pick := 'M';
  end
  else if TryStrToFloat(Trimmed, D, EditFormat) then
  begin
    if BJIsFloatMarker(AMarker) then Pick := AMarker else Pick := 'D';
  end
  else
  begin
    AWhy := 'not a number, a string, null, true or false';
    Exit(False);
  end;

  Result := LedBJEncodeAs(AText, Pick, #0, ABytes, AWhy);
end;

{ Whether bytes just written say what was typed when they are read back.
  Asked of the library rather than worked out: a float16 holding 0.1 and a
  uint8 holding 300 are both refusals nobody should have to tabulate. }
function RoundTrips(const ABytes, AText: string): Boolean;
var
  V: TBJValue;
  I: Int64;
  Q: QWord;
  D: Double;
  Trimmed: string;
begin
  Result := False;
  if ABytes = '' then Exit;
  Trimmed := Trim(AText);
  V := TBJValue.Create(PByte(@ABytes[1]), Length(ABytes));
  if not V.IsValid then Exit;
  case V.Kind of
    bjkInt:    Result := TryStrToInt64(Trimmed, I) and (V.AsInt64 = I);
    bjkUInt:   Result := (TryStrToInt64(Trimmed, I) and (V.AsInt64 = I)) or
                         (TryStrToQWord(Trimmed, Q) and (V.AsQWord = Q));
    bjkFloat:  Result := TryStrToFloat(Trimmed, D, EditFormat) and
                         (V.AsDouble = D);
    bjkString: Result := (V.AsString = AText) or (V.AsString = Trimmed);
  else
    { null, no-op and the booleans: the text named the value outright, and
      LedBJEncodeAs would not have written anything else. }
    Result := True;
  end;
end;

function LedBJTypesFor(const AText: string; ACurrent: AnsiChar): string;
var
  i: Integer;
  M: AnsiChar;
  Bytes, Why: string;
begin
  Result := '';
  for i := 1 to Length(LedBJValueTypes) do
  begin
    M := LedBJValueTypes[i];
    if not LedBJEncodeAs(AText, M, #0, Bytes, Why) then Continue;
    { The file's own type is always offered; the rest have to come back
      saying what went in.  T stands for both boolean markers. }
    if (M = ACurrent) or ((M = 'T') and (ACurrent = 'F')) or
       RoundTrips(Bytes, AText) then
      Result := Result + M;
  end;
end;

function LedBJMarkerFor(const AText: string; ACurrent: AnsiChar): AnsiChar;
var
  Bytes, Why: string;
begin
  Result := #0;
  if LedBJEncodeValue(AText, ACurrent, #0, Bytes, Why) and (Bytes <> '') then
    Result := Bytes[1];
end;

function LedBJEditValue(var ABytes: string; const ARow: TLedBJRow;
  const ANewText: string; out AWhy: string;
  AAsMarker: AnsiChar): TLedBJEditKind;
var
  Marker, LenMarker: AnsiChar;
  OldStart, OldSize: PtrUInt;
  Fresh: string;
  Ok: Boolean;
begin
  Result := bjeRefused;
  if not LedBJCanEdit(ARow, AWhy) then Exit;

  OldStart := ARow.Offset;
  OldSize := ARow.Value.Size;
  if OldStart + OldSize > PtrUInt(Length(ABytes)) then
  begin
    AWhy := 'the row is outside the file';
    Exit;
  end;

  Marker := ARow.Value.Marker;

  { The length marker the file already uses for this string, kept when the
    new text still fits it -- that is what makes a same-length edit a patch
    rather than a rewrite of two bytes nobody asked about.  It means nothing
    when the type is being changed out from under it. }
  LenMarker := #0;
  if (OldSize >= 2) and (Marker in ['S', 'H']) and
     (AAsMarker in [#0, Marker]) then
    LenMarker := ABytes[OldStart + 2];

  if AAsMarker = #0 then
    Ok := LedBJEncodeValue(ANewText, Marker, LenMarker, Fresh, AWhy)
  else
    Ok := LedBJEncodeAs(ANewText, AAsMarker, LenMarker, Fresh, AWhy);
  if not Ok then Exit;

  { The same bytes in the same place, or a different number of them and
    everything below moves.  Both are one assignment; which one it was is
    what the caller needs to know, because it decides whether the offsets on
    screen are still true.

    Byte for byte rather than value for value, so that a type changed without
    changing what the value says -- an int32 7 rewritten as an int8 -- counts
    as an edit, and retyping what is already there still does not. }
  if PtrUInt(Length(Fresh)) = OldSize then
  begin
    if Copy(ABytes, OldStart + 1, OldSize) = Fresh then Exit(bjeUnchanged);
    Result := bjePatched;
  end
  else
    Result := bjeSpliced;

  ABytes := Copy(ABytes, 1, OldStart) + Fresh +
            Copy(ABytes, OldStart + OldSize + 1, MaxInt);
end;

initialization
  EditFormat := DefaultFormatSettings;
  EditFormat.DecimalSeparator := '.';
  EditFormat.ThousandSeparator := #0;

end.
