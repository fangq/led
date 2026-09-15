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
  of exactly these bytes, because its offset is where the writing happens. }
function LedBJEditValue(var ABytes: string; const ARow: TLedBJRow;
  const ANewText: string; out AWhy: string): TLedBJEditKind;

{ The bytes one value encodes to, keeping AMarker when the value still fits
  it.  Public because it is the honest way to ask "how big would this be",
  which is what tells a patch from a splice before either is done. }
function LedBJEncodeValue(const AText: string; AMarker: AnsiChar;
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

{ A string's own bytes: the marker, a length marker, the length, the text.
  Written here rather than taken from TBJData.NewString().ToBytes so that the
  length marker can be chosen to match the one the file already uses, which is
  what keeps a same-length edit a patch. }
function EncodeString(const AText: string; ALenMarker: AnsiChar;
  AMarker: AnsiChar): string;
var
  n: Int64;
  Node: TBJData;
begin
  n := Length(AText);
  Node := TBJData.NewString(AText);
  try
    { The library picks the narrowest length marker.  Where the file used a
      wider one and the text still fits it, keep the file's. }
    if (ALenMarker <> #0) and BJIsIntMarker(ALenMarker) and
       IntFitsMarker(n, ALenMarker) then
    begin
      SetLength(Result, 2 + BJMarkerSize(ALenMarker) + n);
      Result[1] := AMarker;
      Result[2] := ALenMarker;
      PokeLE(Result, 3, ALenMarker, n);
      if n > 0 then Move(AText[1], Result[3 + BJMarkerSize(ALenMarker)], n);
    end
    else
      Result := BytesToStr(Node.ToBytes);
  finally
    Node.Free;
  end;
end;

function LedBJEncodeValue(const AText: string; AMarker: AnsiChar;
  out ABytes: string; out AWhy: string): Boolean;
var
  Node: TBJData;
  I: Int64;
  D: Double;
  Trimmed: string;
begin
  Result := False;
  ABytes := '';
  AWhy := '';
  Trimmed := Trim(AText);
  Node := nil;
  try
    if SameText(Trimmed, 'null') then
      Node := TBJData.NewNull
    else if SameText(Trimmed, 'no-op') then
      Node := TBJData.NewNoOp
    else if SameText(Trimmed, 'true') then
      Node := TBJData.NewBool(True)
    else if SameText(Trimmed, 'false') then
      Node := TBJData.NewBool(False)
    else if TryStrToInt64(Trimmed, I) then
    begin
      { The file's own marker, where the number still fits it. }
      if BJIsIntMarker(AMarker) and IntFitsMarker(I, AMarker) then
        Node := TBJData.NewInt(I, AMarker)
      else if BJIsFloatMarker(AMarker) then
        Node := TBJData.NewFloat(I, AMarker)
      else
        Node := TBJData.NewInt(I);
    end
    else if TryStrToFloat(Trimmed, D, EditFormat) then
    begin
      if BJIsFloatMarker(AMarker) then
        Node := TBJData.NewFloat(D, AMarker)
      else
        Node := TBJData.NewFloat(D);
    end
    else
    begin
      AWhy := 'not a number, a string, null, true or false';
      Exit;
    end;

    ABytes := BytesToStr(Node.ToBytes);
    Result := True;
  finally
    Node.Free;
  end;
end;

function LedBJEditValue(var ABytes: string; const ARow: TLedBJRow;
  const ANewText: string; out AWhy: string): TLedBJEditKind;
var
  Marker, LenMarker: AnsiChar;
  OldStart, OldSize: PtrUInt;
  Fresh: string;
  IsText: Boolean;
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

  { A string is edited as text, whatever it looks like: a value that reads as
    a number is still a string if that is what the file holds, and typing 8
    into a string field means the string "8". }
  IsText := ARow.Value.Kind = bjkString;
  if IsText then
  begin
    if ARow.Value.AsString = ANewText then Exit(bjeUnchanged);
    LenMarker := #0;
    if (OldSize >= 2) and (Marker in ['S', 'H']) then
      LenMarker := ABytes[OldStart + 2];
    { A char holds exactly one character and has no length at all. }
    if Marker = 'C' then
    begin
      if Length(ANewText) <> 1 then
      begin
        AWhy := 'a char holds one byte; use a string for more';
        Exit;
      end;
      Fresh := 'C' + ANewText;
    end
    else
      Fresh := EncodeString(ANewText, LenMarker, Marker);
  end
  else
  begin
    if SameText(Trim(ANewText), LedBJValueText(ARow)) then Exit(bjeUnchanged);
    if not LedBJEncodeValue(ANewText, Marker, Fresh, AWhy) then Exit;
  end;

  if Fresh = '' then
  begin
    AWhy := 'nothing to write';
    Exit;
  end;

  { The same bytes in the same place, or a different number of them and
    everything below moves.  Both are one assignment; which one it was is
    what the caller needs to know, because it decides whether the offsets on
    screen are still true. }
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
