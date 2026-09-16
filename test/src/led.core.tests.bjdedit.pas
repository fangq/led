// led - a lightweight editor.  Tests for editing a value in a BJData file.
//
// Every test here ends the same way: the edited bytes are parsed again, by the
// library rather than by anything of LED's, and asked what they now hold.  A
// byte-level edit that produces a file only LED can read is not an edit, and
// comparing the output against a string of expected bytes would check that
// this code does what it did the day it was written rather than that it
// wrote BJData.
//
// The distinction the tests are built around is patch against splice: whether
// the file's other offsets survived the edit.  It is the thing the view and
// the reader both depend on, and it is invisible in the parsed result, so it
// is asserted separately from the value.

unit Led.Core.Tests.BJDEdit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, bjdata,
  Led.Core.BJDView, Led.Core.BJDEdit;

type
  TTestBJDEdit = class(TTestCase)
  private
    FBytes: string;
    FRows: TLedBJRows;
    { An object of one key holding AValue's bytes, walked and ready to edit. }
    procedure Given(const AKey: string; const AValue: array of Byte);
    function Edit(ARow: Integer; const AText: string;
      out AWhy: string; AAs: AnsiChar = #0): TLedBJEditKind;
    function Reparse: TBJData;
    function ValueOf(const AKey: string): TBJData;
  published
    procedure AnIntegerOfTheSameWidthIsPatched;
    procedure TheFilesOwnMarkerIsKept;
    procedure ANumberTooBigForItsMarkerWidens;
    procedure AFloatStaysAFloat;
    procedure AnIntegerTypedIntoAFloatStaysAFloat;
    procedure ABooleanFlips;
    procedure NullBecomesANumber;
    procedure AStringOfTheSameLengthIsPatched;
    procedure AShorterStringIsStillValid;
    procedure ALongerStringSplices;
    procedure ARecordBelowAnEditKeepsItsValue;
    procedure OffsetsMoveOnlyWhenSpliced;
    procedure ACharTakesOneCharacter;
    procedure AContainerIsRefused;
    procedure RubbishIsRefused;
    procedure TheSameValueIsNotAnEdit;
    procedure NothingIsWrittenWhenRefused;
    procedure ValueTextIsWhatOneWouldType;
    { The file's own type, in the two places it used to be thrown away. }
    procedure AHighPrecisionNumberStaysHighPrecision;
    procedure AHighPrecisionNumberRefusesWords;
    procedure AByteKeepsItsMarker;
    procedure AByteTooBigForItIsWidened;
    procedure AUInt64PastInt64IsStillANumber;
    { The type list the editor offers, and writing one of them. }
    procedure TheTypeListOffersWhatHoldsTheValue;
    procedure TheTypeListLeavesOutWhatWouldLoseIt;
    procedure TheFilesOwnTypeIsOfferedEvenWhenItLoses;
    procedure ChoosingATypeWritesThatType;
    procedure ChoosingATypeThatCannotHoldItIsRefused;
    procedure ChoosingStringTurnsANumberIntoOne;
    procedure ChangingOnlyTheTypeIsStillAnEdit;
  end;

implementation

const
  { "a": <value>, "z": 9 -- the second key is there so that every test can ask
    whether the record after the edited one survived it. }
  KeyA: array[0..2] of Byte = ($55, $01, $61);
  KeyZ: array[0..2] of Byte = ($55, $01, $7A);
  IntNine: array[0..1] of Byte = ($69, $09);          // i 9

procedure TTestBJDEdit.Given(const AKey: string; const AValue: array of Byte);
var
  i: Integer;
  Err: string;
  ErrAt: PtrUInt;
begin
  FBytes := '{';
  FBytes := FBytes + Chr($55) + Chr(Length(AKey)) + AKey;
  for i := Low(AValue) to High(AValue) do
    FBytes := FBytes + Chr(AValue[i]);
  for i := Low(KeyZ) to High(KeyZ) do FBytes := FBytes + Chr(KeyZ[i]);
  for i := Low(IntNine) to High(IntNine) do FBytes := FBytes + Chr(IntNine[i]);
  FBytes := FBytes + '}';

  AssertTrue('the fixture is BJData',
    LedBJTryWalk(FBytes, FRows, Err, ErrAt));
end;

function TTestBJDEdit.Edit(ARow: Integer; const AText: string;
  out AWhy: string; AAs: AnsiChar): TLedBJEditKind;
var
  Err: string;
  ErrAt: PtrUInt;
begin
  Result := LedBJEditValue(FBytes, FRows[ARow], AText, AWhy, AAs);
  { A caller re-walks after an edit, and so does this: the rows hold cursors
    into the bytes that were just replaced. }
  if Result in [bjePatched, bjeSpliced] then
    AssertTrue('the edited file is still BJData',
      LedBJTryWalk(FBytes, FRows, Err, ErrAt));
end;

function TTestBJDEdit.Reparse: TBJData;
begin
  Result := TBJData.Parse(FBytes[1], Length(FBytes));
end;

function TTestBJDEdit.ValueOf(const AKey: string): TBJData;
var
  Doc: TBJData;
begin
  Doc := Reparse;
  try
    Result := Doc.Extract(Doc.IndexOfName(AKey));
  finally
    Doc.Free;
  end;
end;

procedure TTestBJDEdit.AnIntegerOfTheSameWidthIsPatched;
var
  Why: string;
  V: TBJData;
  Was: Integer;
begin
  Given('a', [$69, $07]);                  // i 7
  Was := Length(FBytes);
  AssertEquals('patched', Ord(bjePatched), Ord(Edit(1, '42', Why)));
  AssertEquals('the file is the same size', Was, Length(FBytes));
  V := ValueOf('a');
  try
    AssertEquals('and holds the new number', 42, V.AsInt64);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.TheFilesOwnMarkerIsKept;
var
  Why: string;
begin
  { An int32 that could be an int8 stays an int32: the file said four bytes
    and 7 does not make that untrue. }
  Given('a', [$6C, $07, $00, $00, $00]);   // l 7
  AssertEquals('patched', Ord(bjePatched), Ord(Edit(1, '8', Why)));
  AssertEquals('still an int32', 'l', FBytes[FRows[1].Offset + 1]);
end;

procedure TTestBJDEdit.ANumberTooBigForItsMarkerWidens;
var
  Why: string;
  V: TBJData;
begin
  Given('a', [$69, $07]);                  // i 7, one byte of payload
  AssertEquals('spliced', Ord(bjeSpliced), Ord(Edit(1, '100000', Why)));
  V := ValueOf('a');
  try
    AssertEquals('and holds it', 100000, V.AsInt64);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.AFloatStaysAFloat;
var
  Why: string;
  V: TBJData;
begin
  Given('a', [$44, $00, $00, $00, $00, $00, $00, $F8, $3F]);   // D 1.5
  AssertEquals('patched', Ord(bjePatched), Ord(Edit(1, '2.25', Why)));
  V := ValueOf('a');
  try
    AssertEquals('the new value', 2.25, V.AsDouble, 0.0001);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.AnIntegerTypedIntoAFloatStaysAFloat;
var
  Why: string;
  V: TBJData;
begin
  { Typing 3 into a field the file stores as a double means 3.0 there.  Making
    it an int8 would shrink the record and change the file's own idea of what
    that field is. }
  Given('a', [$44, $00, $00, $00, $00, $00, $00, $F8, $3F]);   // D 1.5
  AssertEquals('patched', Ord(bjePatched), Ord(Edit(1, '3', Why)));
  AssertEquals('still a double', 'D', FBytes[FRows[1].Offset + 1]);
  V := ValueOf('a');
  try
    AssertEquals('holding three', 3.0, V.AsDouble, 0.0001);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.ABooleanFlips;
var
  Why: string;
  V: TBJData;
begin
  Given('a', [$54]);                       // T
  AssertEquals('patched', Ord(bjePatched), Ord(Edit(1, 'false', Why)));
  V := ValueOf('a');
  try
    AssertFalse('now false', V.AsBoolean);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.NullBecomesANumber;
var
  Why: string;
  V: TBJData;
begin
  Given('a', [$5A]);                       // Z
  AssertEquals('spliced', Ord(bjeSpliced), Ord(Edit(1, '5', Why)));
  V := ValueOf('a');
  try
    AssertEquals('five', 5, V.AsInt64);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.AStringOfTheSameLengthIsPatched;
var
  Why: string;
  V: TBJData;
  Was: Integer;
begin
  Given('a', [$53, $55, $02, $68, $69]);   // S U 2 "hi"
  Was := Length(FBytes);
  AssertEquals('patched', Ord(bjePatched), Ord(Edit(1, 'ok', Why)));
  AssertEquals('same size', Was, Length(FBytes));
  V := ValueOf('a');
  try
    AssertEquals('the new text', 'ok', V.AsString);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.AShorterStringIsStillValid;
var
  Why: string;
  V: TBJData;
begin
  Given('a', [$53, $55, $05, $68, $65, $6C, $6C, $6F]);   // S U 5 "hello"
  AssertEquals('spliced', Ord(bjeSpliced), Ord(Edit(1, 'hi', Why)));
  V := ValueOf('a');
  try
    AssertEquals('the new text', 'hi', V.AsString);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.ALongerStringSplices;
var
  Why: string;
  V: TBJData;
  Was: Integer;
begin
  Given('a', [$53, $55, $02, $68, $69]);   // S U 2 "hi"
  Was := Length(FBytes);
  AssertEquals('spliced', Ord(bjeSpliced),
    Ord(Edit(1, 'a much longer value', Why)));
  AssertTrue('the file grew', Length(FBytes) > Was);
  V := ValueOf('a');
  try
    AssertEquals('the new text', 'a much longer value', V.AsString);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.ARecordBelowAnEditKeepsItsValue;
var
  Why: string;
  V: TBJData;
begin
  { The reason a splice is allowed at all: nothing in the file records how
    long the replaced value was, so the record after it is still found. }
  Given('a', [$53, $55, $02, $68, $69]);
  Edit(1, 'a much longer value', Why);
  V := ValueOf('z');
  try
    AssertEquals('the record after the edit', 9, V.AsInt64);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.OffsetsMoveOnlyWhenSpliced;
var
  Why: string;
  Before: PtrUInt;
begin
  Given('a', [$53, $55, $02, $68, $69]);
  Before := FRows[2].Offset;               { the "z" record }

  Edit(1, 'no', Why);                      { same length: a patch }
  AssertEquals('a patch moves nothing', Before, FRows[2].Offset);

  Edit(1, 'a much longer value', Why);     { a splice }
  AssertTrue('a splice moves what is below it', FRows[2].Offset > Before);
end;

procedure TTestBJDEdit.ACharTakesOneCharacter;
var
  Why: string;
  V: TBJData;
begin
  Given('a', [$43, $73]);                  // C 's'
  AssertEquals('patched', Ord(bjePatched), Ord(Edit(1, 'x', Why)));
  V := ValueOf('a');
  try
    AssertEquals('the new character', 'x', V.AsString);
  finally
    V.Free;
  end;

  AssertEquals('two characters are refused', Ord(bjeRefused),
    Ord(Edit(1, 'xy', Why)));
  AssertTrue('and it says why', Pos('one byte', Why) > 0);
end;

procedure TTestBJDEdit.AContainerIsRefused;
var
  Why: string;
begin
  Given('a', [$69, $07]);
  AssertEquals('the root object cannot be typed over', Ord(bjeRefused),
    Ord(Edit(0, '5', Why)));
  AssertTrue('and it says why', Pos('container', Why) > 0);
end;

procedure TTestBJDEdit.RubbishIsRefused;
var
  Why: string;
begin
  Given('a', [$69, $07]);
  AssertEquals('refused', Ord(bjeRefused), Ord(Edit(1, 'orange', Why)));
  AssertTrue('and it says why', Why <> '');
end;

procedure TTestBJDEdit.TheSameValueIsNotAnEdit;
var
  Why: string;
begin
  Given('a', [$69, $07]);
  AssertEquals('typing what is there changes nothing', Ord(bjeUnchanged),
    Ord(Edit(1, '7', Why)));
end;

procedure TTestBJDEdit.NothingIsWrittenWhenRefused;
var
  Why, Was: string;
begin
  Given('a', [$69, $07]);
  Was := FBytes;
  Edit(1, 'orange', Why);
  AssertEquals('the file is untouched', Was, FBytes);
end;

procedure TTestBJDEdit.ValueTextIsWhatOneWouldType;
begin
  Given('a', [$53, $55, $02, $68, $69]);
  AssertEquals('a string comes back unquoted', 'hi',
    LedBJValueText(FRows[1]));

  Given('a', [$54]);
  AssertEquals('a boolean is a word', 'true', LedBJValueText(FRows[1]));

  Given('a', [$5A]);
  AssertEquals('and so is null', 'null', LedBJValueText(FRows[1]));
end;

{ ---- the file's own type ---- }

{ An H is a number written out in full, not a string.  Where the new text
  needed a wider length marker the encoder used to fall back to the library,
  which writes an S -- so one edit turned a high-precision number into text.

  The fixture's length marker is an int8, so 200 digits do not fit it and the
  fallback is the path taken. }
procedure TTestBJDEdit.AHighPrecisionNumberStaysHighPrecision;
var
  Why, Long: string;
  V: TBJData;
  i: Integer;
begin
  { H i 3 "1.5" }
  Given('a', [$48, $69, $03, $31, $2E, $35]);
  Long := '1.';
  for i := 1 to 200 do Long := Long + '5';

  AssertEquals('spliced', Ord(bjeSpliced), Ord(Edit(1, Long, Why)));
  V := ValueOf('a');
  try
    AssertEquals('it is still high precision', 'H', V.Marker);
    AssertEquals('and holds the digits typed', Long, V.AsString);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.AHighPrecisionNumberRefusesWords;
var
  Why, Was: string;
begin
  Given('a', [$48, $69, $03, $31, $2E, $35]);
  Was := FBytes;
  AssertEquals('refused', Ord(bjeRefused), Ord(Edit(1, 'orange', Why)));
  AssertEquals('the file is untouched', Was, FBytes);
  AssertTrue('and it says why: ' + Why, Pos('number', Why) > 0);
end;

{ B is BJData's byte type.  The library's BJIsIntMarker leaves it out because
  UBJSON has no such type, and going through that predicate meant a number
  typed into a byte field came back as an int8: the same size, so it read as
  a patch, with the type quietly changed underneath. }
procedure TTestBJDEdit.AByteKeepsItsMarker;
var
  Why: string;
  V: TBJData;
begin
  Given('a', [$42, $07]);                  // B 7
  AssertEquals('patched', Ord(bjePatched), Ord(Edit(1, '200', Why)));
  V := ValueOf('a');
  try
    AssertEquals('it is still a byte', 'B', V.Marker);
    AssertEquals('holding the new number', 200, V.AsInt64);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.AByteTooBigForItIsWidened;
var
  Why: string;
  V: TBJData;
begin
  Given('a', [$42, $07]);
  AssertEquals('spliced', Ord(bjeSpliced), Ord(Edit(1, '300', Why)));
  V := ValueOf('a');
  try
    AssertEquals('and holds it', 300, V.AsInt64);
  finally
    V.Free;
  end;
end;

{ Past Int64 there is one type left that can hold the number.  Parsing the
  text as a signed integer fails there, and falling through to the float
  branch turned a uint64 into a double. }
procedure TTestBJDEdit.AUInt64PastInt64IsStillANumber;
var
  Why: string;
  V: TBJData;
begin
  { M 9223372036854775807 -- the largest signed value, in a uint64 field }
  Given('a', [$4D, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $7F]);
  AssertEquals('patched', Ord(bjePatched),
    Ord(Edit(1, '18446744073709551610', Why)));
  V := ValueOf('a');
  try
    AssertEquals('it is still a uint64', 'M', V.Marker);
    AssertTrue('holding a number past Int64',
      V.AsQWord = QWord(18446744073709551610));
  finally
    V.Free;
  end;
end;

{ ---- the type list ---- }

procedure TTestBJDEdit.TheTypeListOffersWhatHoldsTheValue;
var
  Types: string;
begin
  Types := LedBJTypesFor('42', 'l');
  AssertTrue('an int8 holds 42: ' + Types, Pos('i', Types) > 0);
  AssertTrue('so does the file''s own int32', Pos('l', Types) > 0);
  AssertTrue('and a float64', Pos('D', Types) > 0);
  AssertTrue('and a string of it', Pos('S', Types) > 0);
  AssertTrue('null does not', Pos('Z', Types) = 0);
  AssertTrue('nor does a boolean', Pos('T', Types) = 0);
  AssertTrue('nor a char, which is one byte', Pos('C', Types) = 0);

  Types := LedBJTypesFor('true', 'T');
  AssertTrue('a boolean is offered for true: ' + Types, Pos('T', Types) > 0);
  AssertTrue('and a string of it', Pos('S', Types) > 0);
  AssertTrue('but no number', Pos('l', Types) = 0);
end;

procedure TTestBJDEdit.TheTypeListLeavesOutWhatWouldLoseIt;
var
  Types: string;
begin
  { 300 does not fit a byte or a uint8, and 0.1 is not a float32 or a
    float16 -- the list is built by writing the value and reading it back,
    so neither has to be tabulated. }
  Types := LedBJTypesFor('300', 'I');
  AssertTrue('a uint8 cannot hold 300: ' + Types, Pos('U', Types) = 0);
  AssertTrue('nor can a byte', Pos('B', Types) = 0);
  AssertTrue('an int16 can', Pos('I', Types) > 0);

  Types := LedBJTypesFor('0.1', 'D');
  AssertTrue('a float32 cannot hold 0.1 exactly: ' + Types, Pos('d', Types) = 0);
  AssertTrue('nor can a float16', Pos('h', Types) = 0);
  AssertTrue('a float64 can', Pos('D', Types) > 0);
end;

{ A float32 field holding 0.1 never could hold it exactly.  Leaving the
  file's own type off the list would mean every edit of such a field changed
  its type, which is the opposite of what keeping the marker is for. }
procedure TTestBJDEdit.TheFilesOwnTypeIsOfferedEvenWhenItLoses;
var
  Types: string;
begin
  Types := LedBJTypesFor('0.1', 'd');
  AssertTrue('the field''s own float32 is offered: ' + Types,
    Pos('d', Types) > 0);
  AssertTrue('and a float64 beside it', Pos('D', Types) > 0);
end;

procedure TTestBJDEdit.ChoosingATypeWritesThatType;
var
  Why: string;
  V: TBJData;
begin
  Given('a', [$6C, $2A, $00, $00, $00]);   // l 42
  AssertEquals('spliced', Ord(bjeSpliced), Ord(Edit(1, '42', Why, 'D')));
  V := ValueOf('a');
  try
    AssertEquals('it is a float64 now', 'D', V.Marker);
    AssertEquals('holding the same number', 42.0, V.AsDouble, 0.0);
  finally
    V.Free;
  end;
end;

procedure TTestBJDEdit.ChoosingATypeThatCannotHoldItIsRefused;
var
  Why, Was: string;
begin
  Given('a', [$6C, $2A, $00, $00, $00]);
  Was := FBytes;
  AssertEquals('refused', Ord(bjeRefused), Ord(Edit(1, '300', Why, 'i')));
  AssertEquals('the file is untouched', Was, FBytes);
  AssertTrue('and it names the type: ' + Why, Pos('int8', Why) > 0);
end;

{ Typing into a number field cannot turn it into a string -- digits typed
  there are a number.  Choosing the type is how one says otherwise. }
procedure TTestBJDEdit.ChoosingStringTurnsANumberIntoOne;
var
  Why: string;
  V: TBJData;
begin
  Given('a', [$6C, $2A, $00, $00, $00]);
  { Patched, not spliced: an int32 and a two-character string are both five
    bytes.  Which of the two an edit is has nothing to do with whether the
    type changed -- only with how many bytes it came to. }
  AssertEquals('patched', Ord(bjePatched), Ord(Edit(1, '42', Why, 'S')));
  V := ValueOf('a');
  try
    AssertEquals('it is a string now', Ord(bjkString), Ord(V.Kind));
    AssertEquals('of the digits typed', '42', V.AsString);
  finally
    V.Free;
  end;
end;

{ The same value in a narrower type is a change to the file even though
  nothing about what it says has changed, so it must not be reported as
  nothing having happened. }
procedure TTestBJDEdit.ChangingOnlyTheTypeIsStillAnEdit;
var
  Why: string;
  V: TBJData;
begin
  Given('a', [$6C, $07, $00, $00, $00]);   // l 7
  AssertEquals('spliced', Ord(bjeSpliced), Ord(Edit(1, '7', Why, 'i')));
  V := ValueOf('a');
  try
    AssertEquals('it is an int8 now', 'i', V.Marker);
    AssertEquals('saying what it said before', 7, V.AsInt64);
  finally
    V.Free;
  end;

  { And retyping the same value in the same type is still not an edit. }
  AssertEquals('unchanged', Ord(bjeUnchanged), Ord(Edit(1, '7', Why, 'i')));
end;

initialization
  RegisterTest(TTestBJDEdit);

end.
