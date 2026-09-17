// led - a lightweight editor.  Tests for reading and writing notebooks.
//
// The promise this layer makes is that a notebook comes back out as it went
// in: a file Jupyter wrote and LED saved must be the same bytes, or every
// save shows up in version control as a diff of the whole file.  So most of
// what is checked here is a round trip, and the fixture below is a real
// nbformat document -- written by nbformat and pasted in, not typed out by
// hand, because what is being checked is agreement with that tool.
//
// It carries the things that have gone wrong: a warning sign followed by a
// variation selector, an emoji outside the basic plane, a middle dot, a
// quote, a backslash and a tab, an execution count of null, and an empty
// cell.  Every one of those was a byte that moved at some point.

unit Led.Core.Tests.NBFormat;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, fpcunit, testregistry,
  Led.Core.Types, Led.Core.NBFormat;

type
  TTestNBFormat = class(TTestCase)
  private
    function Fixture: string;
    function Hex(const AText: string): string;
    function ReadValue(const AJSON, AKey: string): string;
  published
    { the round trip }
    procedure ANotebookComesBackAsItWentIn;
    procedure AFileThatIsNotJSONIsRefused;
    procedure AFileWithNoCellsIsNotANotebook;
    { the reader }
    procedure AnEscapedEmojiIsUTF8;
    procedure AVariationSelectorSurvives;
    procedure ALoneSurrogateBecomesTheReplacement;
    procedure AnEscapedBackslashIsNotAnEscape;
    procedure TheShortEscapesAreRead;
    procedure NumbersKeepTheirKind;
    procedure AnUnterminatedStringIsAnError;
    { the writer }
    procedure KeysAreWrittenInSortedOrder;
    procedure ControlCharactersAreWrittenAsPythonWritesThem;
    procedure FloatsAreWrittenAsPythonWritesThem;
    procedure EmptyContainersStayOnOneLine;
    { cells }
    procedure CellSourceIsOneStringWithoutItsLastNewline;
    procedure SettingSourceWritesTheLinesBackOut;
    procedure AnExecutionCountOfNullReadsAsMinusOne;
    procedure TheKernelAndLanguageAreFound;
    procedure OutputsAreThereToBeClearedAndAddedTo;
    { adding and removing cells }
    procedure ACodeCellIsInsertedWithWhatACodeCellNeeds;
    procedure AProseCellHasNoOutputsOrCount;
    procedure InsertingPushesTheRestDown;
    procedure PastTheEndIsAnAppend;
    procedure ACellCanBeTakenOut;
    procedure TheLastCellCannotBeTakenOut;
    procedure AnAddedCellSurvivesTheRoundTrip;
  end;

implementation

function TTestNBFormat.Fixture: string;
begin
  Result :=
    '{' + #10 +
    ' "cells": [' + #10 +
    '  {' + #10 +
    '   "cell_type": "markdown",' + #10 +
    '   "metadata": {},' + #10 +
    '   "source": [' + #10 +
    '    "# Heading ⚠️\n",' + #10 +
    '    "\n",' + #10 +
    '    "text with · and 📌"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": 3,' + #10 +
    '   "metadata": {' + #10 +
    '    "tags": [' + #10 +
    '     "keep"' + #10 +
    '    ]' + #10 +
    '   },' + #10 +
    '   "outputs": [' + #10 +
    '    {' + #10 +
    '     "name": "stdout",' + #10 +
    '     "output_type": "stream",' + #10 +
    '     "text": [' + #10 +
    '      "10\n",' + #10 +
    '      "done\n"' + #10 +
    '     ]' + #10 +
    '    },' + #10 +
    '    {' + #10 +
    '     "data": {' + #10 +
    '      "text/plain": [' + #10 +
    '       "array([0, 1, 2])"' + #10 +
    '      ]' + #10 +
    '     },' + #10 +
    '     "execution_count": 3,' + #10 +
    '     "metadata": {},' + #10 +
    '     "output_type": "execute_result"' + #10 +
    '    }' + #10 +
    '   ],' + #10 +
    '   "source": [' + #10 +
    '    "import numpy as np\n",' + #10 +
    '    "x = np.arange(3)\n",' + #10 +
    '    "print(x.sum())"' + #10 +
    '   ]' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "code",' + #10 +
    '   "execution_count": null,' + #10 +
    '   "metadata": {},' + #10 +
    '   "outputs": [],' + #10 +
    '   "source": []' + #10 +
    '  },' + #10 +
    '  {' + #10 +
    '   "cell_type": "raw",' + #10 +
    '   "metadata": {},' + #10 +
    '   "source": [' + #10 +
    '    "raw \"quoted\" \\ and a tab\there"' + #10 +
    '   ]' + #10 +
    '  }' + #10 +
    ' ],' + #10 +
    ' "metadata": {' + #10 +
    '  "kernelspec": {' + #10 +
    '   "display_name": "Python 3",' + #10 +
    '   "language": "python",' + #10 +
    '   "name": "python3"' + #10 +
    '  },' + #10 +
    '  "language_info": {' + #10 +
    '   "name": "python",' + #10 +
    '   "version": "3.10.12"' + #10 +
    '  }' + #10 +
    ' },' + #10 +
    ' "nbformat": 4,' + #10 +
    ' "nbformat_minor": 5' + #10 +
    '}' + #10 +
    '';
end;

{ A \u escape, built rather than written out: a test that spells one in a
  string literal is a test that whatever generated the file might have
  decoded for it.  This one was written with the emoji already in it, so the
  reader took its no-escapes fast path and the escape code it was meant to
  check was never run. }
function Esc(const AHex: string): string;
begin
  Result := Chr(92) + 'u' + AHex;
end;

function TTestNBFormat.Hex(const AText: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(AText) do
    Result := Result + IntToHex(Ord(AText[i]), 2) + ' ';
  Result := Trim(Result);
end;

{ The value of AKey in a one-level JSON document, read back through the
  reader under test -- which is the point: what a check wants to know is what
  this reader made of the bytes, not what some other reader would have. }
function TTestNBFormat.ReadValue(const AJSON, AKey: string): string;
var
  D: TJSONData;
  Err: string;
begin
  Result := '';
  D := LedNBParseJSON(AJSON, Err);
  AssertTrue('the fixture parses: ' + Err, D <> nil);
  try
    Result := TJSONObject(D).Elements[AKey].AsString;
  finally
    D.Free;
  end;
end;

procedure TTestNBFormat.ANotebookComesBackAsItWentIn;
var
  NB: TLedNotebook;
  Err: string;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue('it reads: ' + Err, NB.LoadFromText(Fixture, Err));
    AssertEquals('four cells', 4, NB.CellCount);
    AssertEquals('and it writes back byte for byte', Fixture, NB.SaveToText);
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.AFileThatIsNotJSONIsRefused;
var
  NB: TLedNotebook;
  Err: string;
begin
  NB := TLedNotebook.Create;
  try
    AssertFalse('rubbish is not a notebook',
      NB.LoadFromText('this is not JSON at all', Err));
    AssertTrue('and it says so: ' + Err, Err <> '');
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.AFileWithNoCellsIsNotANotebook;
var
  NB: TLedNotebook;
  Err: string;
begin
  NB := TLedNotebook.Create;
  try
    AssertFalse('valid JSON is not enough',
      NB.LoadFromText('{"nbformat": 4}', Err));
    AssertTrue('and the reason names the cells: ' + Err,
      Pos('cells', Err) > 0);
  finally
    NB.Free;
  end;
end;

{ The bug this reader exists for: fcl-json turned this pair of escapes into
  two question marks. }
procedure TTestNBFormat.AnEscapedEmojiIsUTF8;
begin
  AssertEquals('a surrogate pair is one character in four bytes',
    'F0 9F 93 8C',
    Hex(ReadValue('{"k":"' + Esc('d83d') + Esc('dccc') + '"}', 'k')));
end;

{ And the second one: four bytes came back where six went in, which took the
  variation selector off the end of a warning sign. }
procedure TTestNBFormat.AVariationSelectorSurvives;
begin
  AssertEquals('both characters, six bytes',
    'E2 9A A0 EF B8 8F',
    Hex(ReadValue('{"k":"' + Esc('26a0') + Esc('fe0f') + '"}', 'k')));
end;

procedure TTestNBFormat.ALoneSurrogateBecomesTheReplacement;
begin
  { Half of a character is not a character, and there is nothing to write for
    it that is both valid UTF-8 and true. }
  AssertEquals('U+FFFD', 'EF BF BD',
    Hex(ReadValue('{"k":"' + Esc('d83d') + '"}', 'k')));
end;

procedure TTestNBFormat.AnEscapedBackslashIsNotAnEscape;
var
  B: string;
begin
  { A backslash, then the letters u0041 -- not the letter A.  Getting this
    wrong turns a Windows path in somebody's notebook into mojibake. }
  B := Chr(92);
  AssertEquals('the backslash ate itself and nothing else',
    B + 'u0041', ReadValue('{"k":"' + B + B + 'u0041"}', 'k'));
end;

procedure TTestNBFormat.TheShortEscapesAreRead;
var
  B: string;
begin
  B := Chr(92);
  AssertEquals('all eight of them',
    '22 5C 2F 08 0C 0A 0D 09',
    Hex(ReadValue('{"k":"' + B + '"' + B + B + B + '/' + B + 'b' +
      B + 'f' + B + 'n' + B + 'r' + B + 't"}', 'k')));
end;

procedure TTestNBFormat.NumbersKeepTheirKind;
var
  D: TJSONData;
  Err: string;
begin
  D := LedNBParseJSON('{"i":3,"big":12345678901234,"f":1.5,"e":1e3,"n":-2}', Err);
  AssertTrue('it parses: ' + Err, D <> nil);
  try
    AssertEquals('a small whole number is an integer',
      Ord(ntInteger), Ord(TJSONNumber(TJSONObject(D).Elements['i']).NumberType));
    AssertEquals('a big one is an int64',
      Ord(ntInt64), Ord(TJSONNumber(TJSONObject(D).Elements['big']).NumberType));
    AssertEquals('one with a point is a float',
      Ord(ntFloat), Ord(TJSONNumber(TJSONObject(D).Elements['f']).NumberType));
    AssertEquals('and so is one with an exponent',
      Ord(ntFloat), Ord(TJSONNumber(TJSONObject(D).Elements['e']).NumberType));
    AssertEquals('a negative one is read whole',
      -2, TJSONObject(D).Elements['n'].AsInteger);
  finally
    D.Free;
  end;
end;

procedure TTestNBFormat.AnUnterminatedStringIsAnError;
var
  D: TJSONData;
  Err: string;
begin
  D := LedNBParseJSON('{"k":"no end', Err);
  AssertTrue('nothing comes back', D = nil);
  AssertTrue('and the reason says what happened: ' + Err,
    Pos('closed', Err) > 0);
  AssertTrue('and where: ' + Err, Pos('byte', Err) > 0);
end;

procedure TTestNBFormat.KeysAreWrittenInSortedOrder;
var
  D: TJSONData;
  Err: string;
begin
  D := LedNBParseJSON('{"b":1,"a":2,"C":3}', Err);
  try
    AssertEquals('sorted by their bytes, as Python sorts them',
      '{' + #10 + ' "C": 3,' + #10 + ' "a": 2,' + #10 + ' "b": 1' + #10 + '}',
      LedNBWriteJSON(D));
  finally
    D.Free;
  end;
end;

procedure TTestNBFormat.ControlCharactersAreWrittenAsPythonWritesThem;
var
  D: TJSONObject;
begin
  D := TJSONObject.Create;
  try
    D.Add('k', 'a' + #11 + 'b' + #10 + 'c"d\e');
    AssertEquals('short forms where there are any, lower-case hex otherwise',
      '{' + #10 + ' "k": "a\u000bb\nc\"d\\e"' + #10 + '}',
      LedNBWriteJSON(D));
  finally
    D.Free;
  end;
end;

procedure TTestNBFormat.FloatsAreWrittenAsPythonWritesThem;
var
  D: TJSONObject;
begin
  D := TJSONObject.Create;
  try
    D.Add('a', TJSONFloatNumber.Create(1.0));
    D.Add('b', TJSONFloatNumber.Create(0.1));
    D.Add('c', TJSONFloatNumber.Create(1e20));
    AssertEquals('a whole float keeps its point, and no digits are invented',
      '{' + #10 + ' "a": 1.0,' + #10 + ' "b": 0.1,' + #10 + ' "c": 1e+20' +
      #10 + '}',
      LedNBWriteJSON(D));
  finally
    D.Free;
  end;
end;

procedure TTestNBFormat.EmptyContainersStayOnOneLine;
var
  D: TJSONData;
  Err: string;
begin
  D := LedNBParseJSON('{"a":{},"b":[]}', Err);
  try
    AssertEquals('as Python writes them',
      '{' + #10 + ' "a": {},' + #10 + ' "b": []' + #10 + '}',
      LedNBWriteJSON(D));
  finally
    D.Free;
  end;
end;

procedure TTestNBFormat.CellSourceIsOneStringWithoutItsLastNewline;
var
  NB: TLedNotebook;
  Err: string;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    AssertEquals('the lines, joined, with no newline hanging off the end',
      'import numpy as np' + #10 + 'x = np.arange(3)' + #10 + 'print(x.sum())',
      NB.CellSource(1));
    AssertEquals('an empty cell is an empty string', '', NB.CellSource(2));
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.SettingSourceWritesTheLinesBackOut;
var
  NB: TLedNotebook;
  Err: string;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    NB.SetCellSource(2, 'one' + #10 + 'two');
    AssertTrue('the newline goes back on every line but the last',
      Pos('"one\n",', NB.SaveToText) > 0);
    AssertTrue('and not on the last', Pos('"two"', NB.SaveToText) > 0);
    AssertEquals('and it reads back as it was set',
      'one' + #10 + 'two', NB.CellSource(2));

    NB.SetCellSource(2, '');
    AssertEquals('an emptied cell is empty again', '', NB.CellSource(2));
    AssertTrue('and is written as an empty list',
      Pos('"source": []', NB.SaveToText) > 0);
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.AnExecutionCountOfNullReadsAsMinusOne;
var
  NB: TLedNotebook;
  Err: string;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    AssertEquals('a cell that has run says so', 3, NB.CellExecutionCount(1));
    AssertEquals('one that has not is -1', -1, NB.CellExecutionCount(2));

    NB.SetCellExecutionCount(2, 7);
    AssertEquals('setting it takes', 7, NB.CellExecutionCount(2));
    NB.SetCellExecutionCount(2, -1);
    AssertEquals('and clearing it gives back the null the file had',
      -1, NB.CellExecutionCount(2));
    AssertTrue('written as null, not as -1',
      Pos('"execution_count": null', NB.SaveToText) > 0);
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.TheKernelAndLanguageAreFound;
var
  NB: TLedNotebook;
  Err: string;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    AssertEquals('python3', NB.KernelName);
    AssertEquals('python', NB.LanguageName);
    AssertEquals('the kinds are read', Ord(nbkMarkdown), Ord(NB.CellKind(0)));
    AssertEquals(Ord(nbkCode), Ord(NB.CellKind(1)));
    AssertEquals(Ord(nbkRaw), Ord(NB.CellKind(3)));
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.OutputsAreThereToBeClearedAndAddedTo;
var
  NB: TLedNotebook;
  Err: string;
  Written: TJSONObject;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    AssertEquals('the cell that ran has two outputs',
      2, NB.CellOutputs(1).Count);
    AssertTrue('a markdown cell has none at all', NB.CellOutputs(0) = nil);

    NB.ClearCellOutputs(1);
    AssertEquals('clearing leaves the list empty, not missing',
      0, NB.CellOutputs(1).Count);

    Written := TJSONObject.Create;
    Written.Add('output_type', 'stream');
    Written.Add('name', 'stdout');
    Written.Add('text', TJSONArray.Create(['hello' + #10]));
    NB.AddCellOutput(1, Written);
    AssertEquals('and one can be put back', 1, NB.CellOutputs(1).Count);
    AssertTrue('where the file can see it',
      Pos('"hello\n"', NB.SaveToText) > 0);
  finally
    NB.Free;
  end;
end;

{ ---- adding and removing cells ----

  What the hover bar in the pane does, and what nbformat asks of the result:
  a code cell has outputs and an execution count of null, a prose cell has
  neither, and both have metadata -- a cell without it is not a valid
  notebook, however cheerfully most tools read one. }

procedure TTestNBFormat.ACodeCellIsInsertedWithWhatACodeCellNeeds;
var
  NB: TLedNotebook;
  Err, Text: string;
  Cells: Integer;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    Cells := NB.CellCount;
    AssertEquals('it goes where it was asked to', 1, NB.InsertCell(1, nbkCode));
    AssertEquals('and the notebook has one more', Cells + 1, NB.CellCount);
    AssertTrue('it is a code cell', NB.CellKind(1) = nbkCode);
    AssertEquals('with nothing in it', '', NB.CellSource(1));
    AssertEquals('and no execution count', -1, NB.CellExecutionCount(1));
    AssertTrue('but a list to put outputs in', NB.CellOutputs(1) <> nil);
    AssertEquals('which is empty', 0, NB.CellOutputs(1).Count);

    Text := NB.SaveToText;
    AssertTrue('the file says it is code: ' + Copy(Text, 1, 200),
      Pos('"cell_type": "code"', Text) > 0);
    AssertTrue('and gives it metadata, which nbformat requires',
      Pos('"metadata": {}', Text) > 0);
    AssertTrue('and a null count, not a zero',
      Pos('"execution_count": null', Text) > 0);
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.AProseCellHasNoOutputsOrCount;
var
  NB: TLedNotebook;
  Err: string;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    NB.InsertCell(0, nbkMarkdown);
    AssertTrue('it is a prose cell', NB.CellKind(0) = nbkMarkdown);
    AssertTrue('with no outputs', NB.CellOutputs(0) = nil);
    AssertEquals('and no count', -1, NB.CellExecutionCount(0));
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.InsertingPushesTheRestDown;
var
  NB: TLedNotebook;
  Err, Was: string;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    Was := NB.CellSource(1);
    NB.InsertCell(1, nbkCode);
    AssertEquals('what was there is one further down', Was, NB.CellSource(2));
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.PastTheEndIsAnAppend;
var
  NB: TLedNotebook;
  Err: string;
  n: Integer;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    n := NB.CellCount;
    { Which is how "add a cell at the bottom" asks for one. }
    AssertEquals('it lands at the end', n, NB.InsertCell(999, nbkCode));
    AssertEquals('and there is one more', n + 1, NB.CellCount);
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.ACellCanBeTakenOut;
var
  NB: TLedNotebook;
  Err, Second: string;
  Cells: Integer;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    Cells := NB.CellCount;
    Second := NB.CellSource(1);
    AssertTrue('taken out', NB.DeleteCell(0));
    AssertEquals('one fewer', Cells - 1, NB.CellCount);
    AssertEquals('and the one below has moved up', Second, NB.CellSource(0));
    AssertFalse('a cell that is not there cannot be taken out',
      NB.DeleteCell(7));
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.TheLastCellCannotBeTakenOut;
var
  NB: TLedNotebook;
  Err: string;
begin
  NB := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    while NB.CellCount > 1 do
      AssertTrue('each one goes', NB.DeleteCell(0));
    { A notebook with an empty cell list opens as a page with nothing to
      type into, and getting back from there means editing the JSON. }
    AssertFalse('and the last one stays', NB.DeleteCell(0));
    AssertEquals('so there is always something there', 1, NB.CellCount);
  finally
    NB.Free;
  end;
end;

procedure TTestNBFormat.AnAddedCellSurvivesTheRoundTrip;
var
  NB, Again: TLedNotebook;
  Err, Text: string;
  Cells: Integer;
begin
  NB := TLedNotebook.Create;
  Again := TLedNotebook.Create;
  try
    AssertTrue(NB.LoadFromText(Fixture, Err));
    Cells := NB.CellCount;
    NB.InsertCell(1, nbkMarkdown);
    NB.SetCellSource(1, 'Some prose.');
    Text := NB.SaveToText;

    AssertTrue('the file it wrote is a notebook: ' + Err,
      Again.LoadFromText(Text, Err));
    AssertEquals('with the cell in it', Cells + 1, Again.CellCount);
    AssertTrue('of the kind it was made', Again.CellKind(1) = nbkMarkdown);
    AssertEquals('and the text that was typed into it', 'Some prose.',
      Again.CellSource(1));
  finally
    NB.Free;
    Again.Free;
  end;
end;

initialization
  RegisterTest(TTestNBFormat);

end.
