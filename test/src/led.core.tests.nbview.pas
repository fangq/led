// led - a lightweight editor.  Tests for rendering a notebook as lines.
//
// What matters about this rendering is not how it looks but what the rows
// claim about themselves: which cell a line belongs to, whether it may be
// typed into, and -- for a source line -- that what is in the buffer is the
// cell's own line with nothing added to it.  The document layer trusts all
// three of those to map an edit back onto a cell, so each is checked here
// rather than through the editor.

unit Led.Core.Tests.NBView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, fpcunit, testregistry,
  Led.Core.NBFormat, Led.Core.NBView;

type
  TTestNBView = class(TTestCase)
  private
    FNB: TLedNotebook;
    FRows: TLedNBRows;
    FText: string;
    { A notebook of one code cell holding ASource, with AOutputs as its
      outputs in nbformat's own shape. }
    procedure Given(const ASource: string; const AOutputs: string = '[]');
    procedure Render;
    function KindOfRow(ARow: Integer): TLedNBRowKind;
    function RowText(ARow: Integer): string;
    function Rows: Integer;
  protected
    procedure TearDown; override;
  published
    procedure ACellIsAHeaderAndItsSource;
    procedure ASourceLineIsTheCellsOwnLine;
    procedure TheHeaderSaysWhatRanAndInWhatLanguage;
    procedure AnEmptyCellStillHasALineToTypeOn;
    procedure CellsAreSeparatedByABlankLine;
    procedure OnlySourceRowsCanBeTypedInto;
    procedure EveryRowKnowsItsCell;
    procedure TheSourceComesBackFromTheRows;
    procedure StreamOutputIsItsText;
    procedure AResultIsItsPlainText;
    procedure AnImageIsDescribedRatherThanShown;
    procedure ATracebackIsOneLinePerLine;
    procedure ColourEscapesAreTakenOut;
    procedure ALongOutputIsSummarised;
    procedure ACellWithNoOutputHasNoOutputLabel;
    procedure TheTextAndTheRowsAgree;
  end;

implementation

const
  { The pieces of a notebook, so that each test can say what it is about in
    one line and nothing else moves. }
  Prologue =
    '{"cells":[{"cell_type":"code","execution_count":%s,"metadata":{},' +
    '"outputs":%s,"source":%s}],' +
    '"metadata":{"language_info":{"name":"python"}},' +
    '"nbformat":4,"nbformat_minor":5}';

{ JSON for a source string, split into lines the way the format stores it. }
function SourceJSON(const AText: string): string;
var
  L: TStringList;
  i: Integer;
  Line: string;
begin
  if AText = '' then Exit('[]');
  L := TStringList.Create;
  try
    L.TextLineBreakStyle := tlbsLF;
    L.Text := AText;
    while (L.Count > 0) and (L[L.Count - 1] = '') and
          (AText[Length(AText)] <> #10) do
      L.Delete(L.Count - 1);
    Result := '[';
    for i := 0 to L.Count - 1 do
    begin
      Line := StringReplace(L[i], '\', '\\', [rfReplaceAll]);
      Line := StringReplace(Line, '"', '\"', [rfReplaceAll]);
      if i < L.Count - 1 then Line := Line + '\n';
      if i > 0 then Result := Result + ',';
      Result := Result + '"' + Line + '"';
    end;
    Result := Result + ']';
  finally
    L.Free;
  end;
end;

procedure TTestNBView.Given(const ASource: string; const AOutputs: string);
var
  Err: string;
begin
  FreeAndNil(FNB);
  FNB := TLedNotebook.Create;
  AssertTrue('the fixture is a notebook: ' + Err,
    FNB.LoadFromText(Format(Prologue, ['1', AOutputs, SourceJSON(ASource)]),
      Err));
  Render;
end;

procedure TTestNBView.Render;
begin
  FText := LedNBRender(FNB, FRows);
end;

procedure TTestNBView.TearDown;
begin
  FreeAndNil(FNB);
  inherited TearDown;
end;

function TTestNBView.KindOfRow(ARow: Integer): TLedNBRowKind;
begin
  AssertTrue(Format('row %d is there', [ARow]), ARow <= High(FRows));
  Result := FRows[ARow].Kind;
end;

function TTestNBView.RowText(ARow: Integer): string;
begin
  AssertTrue(Format('row %d is there', [ARow]), ARow <= High(FRows));
  Result := FRows[ARow].Text;
end;

function TTestNBView.Rows: Integer;
begin
  Result := Length(FRows);
end;

procedure TTestNBView.ACellIsAHeaderAndItsSource;
begin
  Given('x = 1' + #10 + 'y = 2');
  AssertEquals('a header and two lines', 3, Rows);
  AssertEquals(Ord(nbrHeader), Ord(KindOfRow(0)));
  AssertEquals(Ord(nbrSource), Ord(KindOfRow(1)));
  AssertEquals(Ord(nbrSource), Ord(KindOfRow(2)));
end;

{ The invariant the document layer is built on. }
procedure TTestNBView.ASourceLineIsTheCellsOwnLine;
begin
  Given('    indented = True' + #10 + 'x = "  spaces  "');
  AssertEquals('no indent is added', '    indented = True', RowText(1));
  AssertEquals('and nothing is trimmed', 'x = "  spaces  "', RowText(2));
end;

procedure TTestNBView.TheHeaderSaysWhatRanAndInWhatLanguage;
begin
  Given('x = 1');
  AssertTrue('the count is there: ' + RowText(0),
    Pos('[1]', RowText(0)) = 1);
  AssertTrue('and the language', Pos('python', RowText(0)) > 0);
  AssertTrue('and a rule to the width of the page',
    Pos('---', RowText(0)) > 0);

  FNB.SetCellExecutionCount(0, -1);
  Render;
  AssertTrue('a cell that has not run says so: ' + RowText(0),
    Pos('[ ]', RowText(0)) = 1);
end;

procedure TTestNBView.AnEmptyCellStillHasALineToTypeOn;
begin
  Given('');
  AssertEquals('a header and one empty line', 2, Rows);
  AssertEquals(Ord(nbrSource), Ord(KindOfRow(1)));
  AssertEquals('', RowText(1));
  AssertTrue('which can be typed into', LedNBIsEditable(FRows, 1));
end;

procedure TTestNBView.CellsAreSeparatedByABlankLine;
var
  Err: string;
begin
  FreeAndNil(FNB);
  FNB := TLedNotebook.Create;
  AssertTrue(FNB.LoadFromText(
    '{"cells":[' +
    '{"cell_type":"code","execution_count":1,"metadata":{},"outputs":[],' +
     '"source":["a = 1"]},' +
    '{"cell_type":"markdown","metadata":{},"source":["# Two"]}],' +
    '"metadata":{},"nbformat":4,"nbformat_minor":5}', Err));
  Render;
  AssertEquals('header, source, blank, header, source', 5, Rows);
  AssertEquals(Ord(nbrBlank), Ord(KindOfRow(2)));
  AssertEquals('the gap belongs to no cell', -1, FRows[2].Cell);
  AssertTrue('and cannot be typed into', not LedNBIsEditable(FRows, 2));
  AssertTrue('the second header names markdown: ' + RowText(3),
    Pos('markdown', RowText(3)) > 0);
end;

procedure TTestNBView.OnlySourceRowsCanBeTypedInto;
begin
  Given('x = 1', '[{"name":"stdout","output_type":"stream","text":["1\n"]}]');
  AssertTrue('not the header', not LedNBIsEditable(FRows, 0));
  AssertTrue('the source', LedNBIsEditable(FRows, 1));
  AssertTrue('not the output label', not LedNBIsEditable(FRows, 2));
  AssertTrue('not the output', not LedNBIsEditable(FRows, 3));
  AssertTrue('and not a row that is not there',
    not LedNBIsEditable(FRows, 99));
end;

procedure TTestNBView.EveryRowKnowsItsCell;
begin
  Given('x = 1', '[{"name":"stdout","output_type":"stream","text":["1\n"]}]');
  AssertEquals('the header', 0, LedNBCellOf(FRows, 0));
  AssertEquals('the source', 0, LedNBCellOf(FRows, 1));
  AssertEquals('the label', 0, LedNBCellOf(FRows, 2));
  AssertEquals('the output', 0, LedNBCellOf(FRows, 3));
  AssertEquals('and nothing past the end', -1, LedNBCellOf(FRows, 99));
  AssertEquals('the first line to type on', 1,
    LedNBSourceRowOf(FRows, 0));
end;

procedure TTestNBView.TheSourceComesBackFromTheRows;
begin
  Given('one' + #10 + 'two' + #10 + 'three');
  AssertEquals('joined from the rows, and only the source rows',
    'one' + #10 + 'two' + #10 + 'three', LedNBSourceFromRows(FRows, 0));
  { What the document does after an edit: the rows are what is on screen. }
  FRows[2].Text := 'TWO';
  AssertEquals('including an edit the buffer has and the file does not',
    'one' + #10 + 'TWO' + #10 + 'three', LedNBSourceFromRows(FRows, 0));
end;

procedure TTestNBView.StreamOutputIsItsText;
begin
  Given('print(1)',
    '[{"name":"stdout","output_type":"stream","text":["1\n","2\n"]}]');
  AssertEquals(Ord(nbrOutLabel), Ord(KindOfRow(2)));
  AssertEquals('  1', RowText(3));
  AssertEquals('  2', RowText(4));
  AssertEquals('and no empty line for the newline on the end', 5, Rows);
end;

procedure TTestNBView.AResultIsItsPlainText;
begin
  Given('x',
    '[{"data":{"text/plain":["array([0, 1])"]},"execution_count":1,' +
     '"metadata":{},"output_type":"execute_result"}]');
  AssertEquals('  array([0, 1])', RowText(3));
end;

procedure TTestNBView.AnImageIsDescribedRatherThanShown;
begin
  { 100 characters of base64 is 75 bytes. }
  Given('plot()',
    '[{"data":{"image/png":["' + StringOfChar('A', 100) + '"]},' +
     '"metadata":{},"output_type":"display_data"}]');
  AssertTrue('the type is named: ' + RowText(3),
    Pos('image/png', RowText(3)) > 0);
  AssertTrue('and the size', Pos('75 bytes', RowText(3)) > 0);
end;

procedure TTestNBView.ATracebackIsOneLinePerLine;
begin
  { A traceback is a list of frames, not of lines: each entry is several
    lines with no newline on the end.  Concatenating them put the exception
    name, the banner and the first frame all on one line. }
  Given('boom()',
    '[{"ename":"ValueError","evalue":"no","output_type":"error",' +
     '"traceback":["ValueError  Traceback (most recent call last)",' +
     '"Cell In[1], line 1","ValueError: no"]}]');
  AssertEquals('  ValueError  Traceback (most recent call last)', RowText(3));
  AssertEquals('  Cell In[1], line 1', RowText(4));
  AssertEquals('  ValueError: no', RowText(5));
  AssertTrue('and the rows say they are an error', FRows[3].IsError);
end;

procedure TTestNBView.ColourEscapesAreTakenOut;
begin
  AssertEquals('a colour sequence', 'red', LedNBStripAnsi(#27'[0;31mred'#27'[0m'));
  AssertEquals('one with several parameters', 'x',
    LedNBStripAnsi(#27'[38;5;241mx'#27'[39;00m'));
  AssertEquals('text with no escapes is untouched', 'plain',
    LedNBStripAnsi('plain'));
  AssertEquals('and a stray escape does not eat the line', 'ab',
    LedNBStripAnsi('a'#27'b'));
end;

procedure TTestNBView.ALongOutputIsSummarised;
var
  Text: string;
  i: Integer;
begin
  Text := '';
  for i := 1 to LedNBMaxOutputLines + 20 do
    Text := Text + Format('"line %d\n",', [i]);
  SetLength(Text, Length(Text) - 1);
  Given('spam()',
    '[{"name":"stdout","output_type":"stream","text":[' + Text + ']}]');
  AssertEquals('the cap, plus one line saying what is missing',
    2 + 1 + LedNBMaxOutputLines + 1, Rows);
  AssertTrue('which says how many: ' + RowText(Rows - 1),
    Pos('20 more lines not shown', RowText(Rows - 1)) > 0);
end;

procedure TTestNBView.ACellWithNoOutputHasNoOutputLabel;
begin
  Given('x = 1');
  AssertEquals('a header and a line, and nothing else', 2, Rows);
  Given('x = 1', '[{"name":"stdout","output_type":"stream","text":[""]}]');
  AssertEquals('and an output of nothing is not an output either', 2, Rows);
end;

{ The buffer text and the rows are two views of one thing, and the document
  sets the first from the second.  They have to agree line for line. }
procedure TTestNBView.TheTextAndTheRowsAgree;
var
  L: TStringList;
  i: Integer;
begin
  Given('a' + #10 + 'b',
    '[{"name":"stdout","output_type":"stream","text":["out\n"]}]');
  L := TStringList.Create;
  try
    L.TextLineBreakStyle := tlbsLF;
    L.Text := FText;
    while (L.Count > 0) and (L[L.Count - 1] = '') and
          (FText[Length(FText)] <> #10) do
      L.Delete(L.Count - 1);
    AssertEquals('one line per row', Rows, L.Count);
    for i := 0 to L.Count - 1 do
      AssertEquals(Format('line %d', [i]), FRows[i].Text, L[i]);
  finally
    L.Free;
  end;
end;

initialization
  RegisterTest(TTestNBView);

end.
