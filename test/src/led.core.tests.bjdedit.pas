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
      out AWhy: string): TLedBJEditKind;
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
  out AWhy: string): TLedBJEditKind;
var
  Err: string;
  ErrAt: PtrUInt;
begin
  Result := LedBJEditValue(FBytes, FRows[ARow], AText, AWhy);
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

initialization
  RegisterTest(TTestBJDEdit);

end.
