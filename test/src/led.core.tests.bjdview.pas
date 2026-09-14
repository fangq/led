// led - a lightweight editor.  Tests for the Binary JData structure view.
//
// Fixtures are built here rather than checked in, from the byte sequences in
// the BJData specification itself -- the 2x3x4 array at spec lines 570-595,
// the container forms at 435-505.  A golden file would only record what this
// code did on the day it was written; the spec's own bytes are the thing
// worth being right about.
//
// The view is checked against its rendered text, not against its internals,
// for the reason Led.Core.Tests.Hex gives: the geometry and the rendering can
// only drift apart if they are tested separately.

unit Led.Core.Tests.BJDView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, bjdata, Led.Core.BJDView;

type
  TTestBJDView = class(TTestCase)
  private
    function Render(const ABytes: array of Byte): string;
    function Row(const AText: string; AIndex: Integer): string;
  published
    procedure AnEmptyInputRendersNothing;
    procedure AnObjectShowsItsKeysIndented;
    procedure AStringShowsItsMarkerAndLength;
    procedure ACharKeepsItsOwnMarker;
    procedure EveryIntegerWidthKeepsItsMarker;
    procedure NullAndBooleansRenderAsWords;
    procedure AFlatArrayIsOneRow;
    procedure AnArrayOfContainersIsNot;
    procedure AnEmptyArrayIsOneRow;
    procedure AnNDArrayShowsItsDimensions;
    procedure AnNDArrayNeverPrintsItsPayload;
    procedure OffsetsPointAtTheRecord;
    procedure ABigContainerIsNotWalked;
    procedure NoTrailingNewline;
    procedure TheExtensionListIsBinaryOnly;
    procedure BadBytesRaiseWithAnOffset;
    procedure ATruncatedFileStillWalks;
    procedure TheErrorOffsetLandsOnTheDamage;
    procedure AShortPackedVectorIsInlined;
    procedure ALongPackedVectorIsNot;
  end;

implementation

function TTestBJDView.Render(const ABytes: array of Byte): string;
var
  Raw: string;
  Rows: TLedBJRows;
  i: Integer;
begin
  SetLength(Raw, Length(ABytes));
  for i := 0 to High(ABytes) do
    Raw[i + 1] := Chr(ABytes[i]);
  Result := LedBJRender(Raw, Rows);
end;

function TTestBJDView.Row(const AText: string; AIndex: Integer): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LineBreak := #10;
    L.Text := AText;
    if AIndex < L.Count then Result := L[AIndex] else Result := '';
  finally
    L.Free;
  end;
end;

procedure TTestBJDView.AnEmptyInputRendersNothing;
begin
  AssertEquals('', Render([]));
end;

procedure TTestBJDView.AnObjectShowsItsKeysIndented;
var
  S: string;
begin
  { {  U 1 "a"  U 7  U 1 "b"  Z  } }
  S := Render([$7B, $55,1,Ord('a'), $55,7, $55,1,Ord('b'), $5A, $7D]);
  AssertTrue('the object is the first row', Pos('{', Row(S, 0)) > 0);
  AssertTrue('a is indented under it', Pos('  a  ', Row(S, 1)) > 0);
  AssertTrue('and carries its value', Pos('7', Row(S, 1)) > 0);
  AssertTrue('b likewise', Pos('  b  ', Row(S, 2)) > 0);
  AssertTrue('null spelt as a word', Pos('null', Row(S, 2)) > 0);
end;

procedure TTestBJDView.AStringShowsItsMarkerAndLength;
var
  S: string;
begin
  { In an object, so the value gets a row of its own -- inside a flat array
    it would be folded onto one line and the marker column would not show. }
  S := Render([$7B, $55,1,Ord('s'), $53, $55, 2, Ord('h'), Ord('i'), $7D]);
  AssertTrue('marker and length are both shown, got: ' + S,
    Pos('S #2', S) > 0);
  AssertTrue('and the text', Pos('"hi"', S) > 0);
end;

procedure TTestBJDView.ACharKeepsItsOwnMarker;
var
  S: string;
begin
  { A char is a string to the library, but the byte in the file says C and
    the view must not claim it says S. }
  S := Render([$7B, $55,1,Ord('u'), $43, Ord('s'), $7D]);
  AssertTrue('the C marker survives, got: ' + S, Pos('C #1', S) > 0);
  AssertTrue('and reads as a char', Pos('''s''', S) > 0);
end;

procedure TTestBJDView.EveryIntegerWidthKeepsItsMarker;
var
  S: string;
begin
  { One per key, so each keeps a row and shows its marker.  In an array these
    fold onto one line -- which is checked separately, and is where the values
    below were first confirmed. }
  S := Render([$7B,
               $55,1,Ord('a'), $69, 244,
               $55,1,Ord('b'), $55, 200,
               $55,1,Ord('c'), $49, $E8, $03,
               $55,1,Ord('d'), $6C, $70, $11, $01, $00,
               $7D]);
  AssertTrue('int8 marker, got: ' + S, Pos('  i  ', S) > 0);
  AssertTrue('int16 marker', Pos('  I  ', S) > 0);
  AssertTrue('int32 marker', Pos('  l  ', S) > 0);
  AssertTrue('the signed value', Pos('-12', S) > 0);
  AssertTrue('uint8 value', Pos('200', S) > 0);
  AssertTrue('int16 value, little-endian', Pos('1000', S) > 0);
  AssertTrue('int32 value', Pos('70000', S) > 0);
end;

procedure TTestBJDView.NullAndBooleansRenderAsWords;
var
  S: string;
begin
  S := Render([$5B, $5A, $54, $46, $5D]);
  AssertTrue('null', Pos('null', S) > 0);
  AssertTrue('true', Pos('true', S) > 0);
  AssertTrue('false', Pos('false', S) > 0);
end;

procedure TTestBJDView.AFlatArrayIsOneRow;
var
  S: string;
  L: TStringList;
begin
  { An array of scalars is a single fact, so it is a single row. }
  S := Render([$5B, $55,1, $55,2, $55,3, $5D]);
  L := TStringList.Create;
  try
    L.LineBreak := #10;
    L.Text := S;
    AssertEquals('one row, not one per element', 1, L.Count);
  finally
    L.Free;
  end;
  AssertTrue('with the elements on it, got: ' + S, Pos('[1, 2, 3]', S) > 0);
end;

procedure TTestBJDView.AnArrayOfContainersIsNot;
var
  S: string;
  L: TStringList;
begin
  { [ [U 1] [U 2] ] -- nested, so the structure is the point and each
    element keeps its own row. }
  S := Render([$5B, $5B, $55,1, $5D, $5B, $55,2, $5D, $5D]);
  L := TStringList.Create;
  try
    L.LineBreak := #10;
    L.Text := S;
    AssertTrue('more than one row, got: ' + S, L.Count > 1);
  finally
    L.Free;
  end;
end;

procedure TTestBJDView.AnEmptyArrayIsOneRow;
var
  S: string;
begin
  S := Render([$5B, $5D]);
  AssertTrue('rendered as empty brackets, got: ' + S, Pos('[]', S) > 0);
end;

procedure TTestBJDView.AnNDArrayShowsItsDimensions;
var
  S: string;
  B: array of Byte;
  i: Integer;
begin
  { The specification's own example, lines 570-595: a 2x3x4 uint8 array
    written [$U#[U2 U3 U4] followed by 24 bytes.  The closing bracket of the
    dimension array is not optional -- without it the payload's first bytes
    are read as further dimensions, which is what the first draft did. }
  SetLength(B, 12 + 24);
  B[0] := $5B; B[1] := $24; B[2] := $55; B[3] := $23; B[4] := $5B;
  B[5] := $55; B[6] := 2; B[7] := $55; B[8] := 3; B[9] := $55; B[10] := 4;
  B[11] := $5D;
  for i := 0 to 23 do B[12 + i] := i;
  S := Render(B);
  AssertTrue('the dimensions are shown, got: ' + S, Pos('2 3 4', S) > 0);
  AssertTrue('and the element type', Pos('$U', S) > 0);
end;

procedure TTestBJDView.AnNDArrayNeverPrintsItsPayload;
var
  S: string;
  B: array of Byte;
  i: Integer;
begin
  SetLength(B, 12 + 24);
  B[0] := $5B; B[1] := $24; B[2] := $55; B[3] := $23; B[4] := $5B;
  B[5] := $55; B[6] := 2; B[7] := $55; B[8] := 3; B[9] := $55; B[10] := 4;
  B[11] := $5D;
  for i := 0 to 23 do B[12 + i] := 99;
  S := Render(B);
  { 24 values is small, but the rule is about the kind and not the size: a
    packed array is why these files are large and is never spelt out. }
  AssertTrue('summarised by count, got: ' + S, Pos('24 values', S) > 0);
  AssertTrue('no element is printed', Pos('99, 99', S) = 0);
end;

procedure TTestBJDView.OffsetsPointAtTheRecord;
var
  Raw: string;
  Rows: TLedBJRows;
begin
  { { U 1 "a" U 7 } -- the object is at 0 and its one value at 4. }
  Raw := #$7B#$55#$01'a'#$55#$07#$7D;
  LedBJWalk(Raw, Rows);
  AssertEquals('two rows', 2, Length(Rows));
  AssertEquals('the object starts at the first byte', 0, Rows[0].Offset);
  AssertEquals('the value follows its key', 4, Rows[1].Offset);
  AssertEquals('and the key is carried', 'a', Rows[1].Key);
end;

procedure TTestBJDView.ABigContainerIsNotWalked;
var
  Raw: string;
  Rows: TLedBJRows;
  i: Integer;
begin
  { An array of LedBJMaxElements + 1 *containers*, so the flat-array path
    does not take it: it must be summarised, not expanded. }
  Raw := '[';
  for i := 0 to LedBJMaxElements do
    Raw := Raw + '[' + #$55#$01 + ']';
  Raw := Raw + ']';
  LedBJWalk(Raw, Rows);
  AssertEquals('summarised to a single row', 1, Length(Rows));
  AssertTrue('and says so', Rows[0].Elided);
end;

procedure TTestBJDView.NoTrailingNewline;
var
  S: string;
begin
  S := Render([$7B, $55,1,Ord('a'), $5A, $7D]);
  AssertTrue('a dump does not end in a newline',
    (S <> '') and (S[Length(S)] <> #10));
end;

procedure TTestBJDView.TheExtensionListIsBinaryOnly;
begin
  AssertTrue('.bjd', LedBJIsBJDataName('x.bjd'));
  AssertTrue('.bnii', LedBJIsBJDataName('x.bnii'));
  AssertTrue('.bmsh', LedBJIsBJDataName('x.bmsh'));
  AssertTrue('.bnirs', LedBJIsBJDataName('x.bnirs'));
  AssertTrue('.jdb', LedBJIsBJDataName('x.jdb'));
  AssertTrue('case does not matter', LedBJIsBJDataName('X.BJD'));
  { .jdat is text JData -- JSON -- and belongs in the text view.  Every
    sample of it on hand opens with a brace, a newline and a quoted key. }
  AssertFalse('.jdat is not binary', LedBJIsBJDataName('x.jdat'));
  AssertFalse('.json is not', LedBJIsBJDataName('x.json'));
end;

procedure TTestBJDView.BadBytesRaiseWithAnOffset;
var
  Raised: Boolean;
  Msg: string;
begin
  Raised := False;
  Msg := '';
  try
    { 'q' is not a type marker. }
    Render([$5B, Ord('q')]);
  except
    on E: EBJData do
    begin
      Raised := True;
      Msg := E.Message;
    end;
  end;
  AssertTrue('rubbish is rejected', Raised);
  AssertTrue('names the marker, got: ' + Msg, Pos('"q"', Msg) > 0);
  AssertTrue('and where it is, got: ' + Msg,
    Pos('byte offset', LowerCase(Msg)) > 0);
end;

procedure TTestBJDView.ATruncatedFileStillWalks;
var
  Raw: string;
  Rows: TLedBJRows;
  Err: string;
  Where: PtrUInt;
begin
  { An object of three keys whose third value is cut off mid-string.

    The rows before the damage must survive.  They did not used to: a
    container's child count is obtained by walking that container, so the
    root row alone traversed the whole file and the first bad byte anywhere
    surfaced as a failure before a single child had been rendered. }
  Raw := #$7B +
         #$55#$01'a' + #$55#$07 +
         #$55#$01'b' + #$55#$08 +
         #$55#$01'c' + #$53#$55#$40'short';   { says 64 bytes, gives 5 }

  AssertFalse('the walk reports failure',
    LedBJTryWalk(Raw, Rows, Err, Where));
  AssertTrue('and keeps what it read, got ' + IntToStr(Length(Rows)) + ' rows',
    Length(Rows) >= 3);
  AssertEquals('a is still there', 'a', Rows[1].Key);
  AssertEquals('and so is b', 'b', Rows[2].Key);
  AssertTrue('the message is the parser own words', Err <> '');
end;

procedure TTestBJDView.TheErrorOffsetLandsOnTheDamage;
var
  Raw: string;
  Rows: TLedBJRows;
  Err: string;
  Where: PtrUInt;
begin
  { [ U 1, <not a marker> ] -- the rubbish is the 'q' at index 3, and the
    offset comes back as 4.

    The reader reports the position it had reached, and for an unrecognised
    marker it has already consumed the byte, so the caret sits just past it.
    For the errors that actually occur in real files it is exact: a length or
    a count is checked before it is consumed, so the offset is the first byte
    of the field that does not fit -- verified against mousehead.bnii, where
    615 is the first byte of the count that overruns the file.

    Either way the caret lands inside the damaged record rather than at the
    start of the file, which is the whole point of the second pass. }
  Raw := '[' + #$55#$01 + 'q' + ']';
  AssertFalse('rejected', LedBJTryWalk(Raw, Rows, Err, Where));
  AssertEquals('the caret goes where the reader stopped', 4, Where);
end;

procedure TTestBJDView.AShortPackedVectorIsInlined;
var
  S: string;
begin
  { [$U#U3 then 50 53 44 -- a NIfTI Dim.  Packed or not, three numbers are
    one fact, and "3 values, 3 bytes" is not the fact the reader wants. }
  S := Render([$5B, $24, $55, $23, $55, 3, 50, 53, 44]);
  AssertTrue('the values are shown, got: ' + S, Pos('[50, 53, 44]', S) > 0);
end;

procedure TTestBJDView.ALongPackedVectorIsNot;
var
  B: array of Byte;
  S: string;
  i: Integer;
begin
  { Same shape, over the cap: this is where the size of these files lives. }
  SetLength(B, 5 + 300);
  B[0] := $5B; B[1] := $24; B[2] := $55; B[3] := $23;
  B[4] := $55;
  { a count of 300 does not fit in U, so write it as u (uint16) }
  SetLength(B, 6 + 300);
  B[4] := $75; B[5] := 44; B[6] := 1;
  SetLength(B, 7 + 300);
  for i := 0 to 299 do B[7 + i] := 7;
  S := Render(B);
  AssertTrue('summarised, got: ' + S, Pos('300 values', S) > 0);
  AssertTrue('not spelt out', Pos('7, 7, 7', S) = 0);
end;

initialization
  RegisterTest(TTestBJDView);

end.
