// led - a lightweight editor.  Tests for turning a pipe back into lines.
//
// The splitter exists because a read ends where the operating system says it
// does and not where a message does, so the tests are mostly one stream cut
// in every possible place: if reassembly depends on where the cut fell, one
// of those offsets says so.
//
// The rest are the things the two hand-written copies of this code in
// Led.Core.Kernel and Led.Core.Gdb never had a test for: a carriage return
// separated from its newline by the end of a read, an empty line, a line
// that begins with a double quote -- which TStringList.DelimitedText
// silently eats half of, StrictDelimiter or not -- and a tail with no
// newline after it, which must be held back rather than handed over.

unit Led.Core.Tests.LineSplit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, fpcunit, testregistry,
  Led.Core.LineSplit;

type
  TTestLineSplit = class(TTestCase)
  private
    FS: TLedLineSplitter;
    { Everything the splitter hands back for AStream, when it is fed in
      pieces of ACut bytes, joined with a vertical bar.  The bar is not in
      any of the streams below, so a line boundary in the wrong place is
      visible in the failure message rather than inferred from a count. }
    function Split(const AStream: string; ACut: Integer): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure NothingComesOfNothing;
    procedure AWholeLineArrivesAsOne;
    procedure TheTailWaitsForItsNewline;
    procedure PendingIsTheHeldBackTail;
    procedure SeveralLinesInOneChunk;
    procedure AnEmptyLineIsStillALine;
    procedure CRLFLosesBothHalves;
    procedure ACarriageReturnMayArriveAloneBeforeItsNewline;
    procedure ALineThatBeginsWithAQuoteSurvivesWhole;
    procedure QuotesAndCommasInTheMiddleAreLeftAlone;
    procedure TheCutOffsetNeverChangesTheLines;
    procedure ALongLineAcrossManyChunks;
    procedure FlushHandsOverTheTail;
    procedure FlushOfNothingIsNothing;
    procedure FlushDoesNotRepeatItself;
    procedure ResetForgetsTheTail;
    procedure LineCountCountsWhatCameOut;
    procedure ManyLinesInOneReadCostWhatTheyWeigh;
  end;

implementation

procedure TTestLineSplit.SetUp;
begin
  FS := TLedLineSplitter.Create;
end;

procedure TTestLineSplit.TearDown;
begin
  FreeAndNil(FS);
end;

function TTestLineSplit.Split(const AStream: string; ACut: Integer): string;
var
  S: TLedLineSplitter;
  i: Integer;
  Line: string;
begin
  Result := '';
  S := TLedLineSplitter.Create;
  try
    i := 1;
    while i <= Length(AStream) do
    begin
      S.Feed(Copy(AStream, i, ACut));
      while S.Next(Line) do
      begin
        if Result <> '' then Result := Result + '|';
        Result := Result + Line;
      end;
      Inc(i, ACut);
    end;
  finally
    S.Free;
  end;
end;

procedure TTestLineSplit.NothingComesOfNothing;
var
  Line: string;
begin
  AssertFalse('no line from an empty splitter', FS.Next(Line));
  FS.Feed('');
  AssertFalse('nor from an empty chunk', FS.Next(Line));
  AssertEquals('and nothing is held', '', FS.Pending);
end;

procedure TTestLineSplit.AWholeLineArrivesAsOne;
var
  Line: string;
begin
  FS.Feed('hello'#10);
  AssertTrue('a line came out', FS.Next(Line));
  AssertEquals('it is the line', 'hello', Line);
  AssertFalse('and there is not a second one', FS.Next(Line));
end;

procedure TTestLineSplit.TheTailWaitsForItsNewline;
var
  Line: string;
begin
  { The whole point of the unit: eleven bytes of a message are not a
    message. }
  FS.Feed('{"partia');
  AssertFalse('half a line is not a line', FS.Next(Line));
  FS.Feed('l":1}'#10);
  AssertTrue('the newline releases it', FS.Next(Line));
  AssertEquals('whole and in order', '{"partial":1}', Line);
end;

procedure TTestLineSplit.PendingIsTheHeldBackTail;
begin
  FS.Feed('one'#10'tw');
  AssertEquals('the tail is held, not lost', 'tw', FS.Pending);
end;

procedure TTestLineSplit.SeveralLinesInOneChunk;
begin
  AssertEquals('three lines from one read', 'a|b|c',
    Split('a'#10'b'#10'c'#10, 64));
end;

procedure TTestLineSplit.AnEmptyLineIsStillALine;
begin
  { A blank line between two records is a record boundary in some
    protocols; dropping it changes what the reader sees. }
  AssertEquals('the blank line is kept', 'a||b', Split('a'#10#10'b'#10, 64));
end;

procedure TTestLineSplit.CRLFLosesBothHalves;
var
  Line: string;
begin
  FS.Feed('hello'#13#10);
  AssertTrue('a line came out', FS.Next(Line));
  AssertEquals('without either half of its ending', 'hello', Line);
end;

procedure TTestLineSplit.ACarriageReturnMayArriveAloneBeforeItsNewline;
var
  Line: string;
begin
  { A read from a Windows child can end between the two.  Normalising a
    chunk on arrival cannot see this; normalising at the newline can. }
  FS.Feed('hello'#13);
  AssertFalse('a carriage return does not end a line', FS.Next(Line));
  FS.Feed(#10'next'#10);
  AssertTrue('the newline does', FS.Next(Line));
  AssertEquals('and the return went with it', 'hello', Line);
  AssertTrue('the line after it is intact', FS.Next(Line));
  AssertEquals('', 'next', Line);
end;

procedure TTestLineSplit.ALineThatBeginsWithAQuoteSurvivesWhole;
var
  Line: string;
begin
  { TStringList.DelimitedText reads this as a quoted string however
    StrictDelimiter is set: it collapses the doubled quotes and throws away
    everything past the closing one.  Which is why this does not use it. }
  FS.Feed('"a ""b"" c" trailing'#10);
  AssertTrue('a line came out', FS.Next(Line));
  AssertEquals('byte for byte what went in',
    '"a ""b"" c" trailing', Line);
end;

procedure TTestLineSplit.QuotesAndCommasInTheMiddleAreLeftAlone;
var
  Line: string;
begin
  FS.Feed('{"message":{"content":"a, b \"c\""},"done":false}'#10);
  AssertTrue('a line came out', FS.Next(Line));
  AssertEquals('unchanged',
    '{"message":{"content":"a, b \"c\""},"done":false}', Line);
end;

procedure TTestLineSplit.TheCutOffsetNeverChangesTheLines;
const
  { Two JSON chunks of the shape a model streams, a blank line, a CRLF line
    and a line with a quote first -- everything above, in one stream. }
  Stream = '{"a":1}'#10 +
           #10 +
           '"quoted, first"'#13#10 +
           '{"b":"x, \"y\""}'#10 +
           'last'#10;
  Want = '{"a":1}||"quoted, first"|{"b":"x, \"y\""}|last';
var
  Cut: Integer;
begin
  { Every place a read could end, including one byte at a time. }
  for Cut := 1 to Length(Stream) + 1 do
    AssertEquals(Format('cut into %d-byte reads', [Cut]),
      Want, Split(Stream, Cut));
end;

procedure TTestLineSplit.ALongLineAcrossManyChunks;
var
  Want, Line: string;
  i: Integer;
begin
  Want := StringOfChar('x', 40000);
  for i := 1 to 40 do
    FS.Feed(StringOfChar('x', 1000));
  AssertFalse('no newline yet, so no line', FS.Next(Line));
  FS.Feed(#10);
  AssertTrue('and then there is one', FS.Next(Line));
  AssertEquals('every byte of it', Length(Want), Length(Line));
  AssertEquals('and the right bytes', Want, Line);
end;

procedure TTestLineSplit.FlushHandsOverTheTail;
var
  Line: string;
begin
  { A child that exits without a final newline still said something. }
  FS.Feed('one'#10'two');
  AssertTrue('the line is a line', FS.Next(Line));
  AssertFalse('the tail is not, yet', FS.Next(Line));
  AssertTrue('at the end of the stream it is', FS.Flush(Line));
  AssertEquals('', 'two', Line);
end;

procedure TTestLineSplit.FlushOfNothingIsNothing;
var
  Line: string;
begin
  FS.Feed('one'#10);
  AssertTrue('', FS.Next(Line));
  AssertFalse('a stream that ended on a newline has no tail', FS.Flush(Line));
  AssertEquals('', '', Line);
end;

procedure TTestLineSplit.FlushDoesNotRepeatItself;
var
  Line: string;
begin
  FS.Feed('tail');
  AssertTrue('', FS.Flush(Line));
  AssertFalse('the tail is handed over once', FS.Flush(Line));
  AssertEquals('and nothing is still held', '', FS.Pending);
end;

procedure TTestLineSplit.ResetForgetsTheTail;
var
  Line: string;
begin
  FS.Feed('half a line');
  FS.Reset;
  AssertEquals('the tail is gone', '', FS.Pending);
  AssertFalse('and it does not come back', FS.Next(Line));
  AssertEquals('the count starts again', 0, FS.LineCount);
end;

procedure TTestLineSplit.LineCountCountsWhatCameOut;
var
  Line: string;
begin
  FS.Feed('a'#10'b'#10'c');
  while FS.Next(Line) do ;
  AssertEquals('two whole lines, and a tail that is not one', 2, FS.LineCount);
  FS.Flush(Line);
  AssertEquals('the tail counts once it is handed over', 3, FS.LineCount);
end;

procedure TTestLineSplit.ManyLinesInOneReadCostWhatTheyWeigh;
const
  Many = 500000;
var
  Buf: TStringList;
  Line, Last: string;
  Started: TDateTime;
  Took, i: Integer;
begin
  { A read off a busy pipe holds hundreds of lines, and taking each one by
    cutting the front off the buffer copies everything behind it -- which
    turns a pass over the data into a pass per line.  The same shape of
    mistake in the preview's page builder took sixteen seconds over half a
    megabyte.  A cursor makes this linear, and the only way to say so in a
    check is to say how long it took.

    Measured here, half a million lines: 104 ms with a cursor, and 26.1
    seconds with a Delete per line.  Two seconds sits an order of magnitude
    above the first and an order below the second, which is what makes it a
    check on the algorithm rather than on how busy the machine is.  A
    hundred thousand lines is not enough to tell them apart -- 21 ms against
    970 ms, both comfortably inside any bound worth setting. }
  Buf := TStringList.Create;
  try
    for i := 1 to Many do
      Buf.Add(Format('{"n":%d}', [i]));
    Buf.LineBreak := #10;

    Started := Now;
    FS.Feed(Buf.Text);
    i := 0;
    Last := '';
    while FS.Next(Line) do
    begin
      Inc(i);
      Last := Line;
    end;
    Took := MilliSecondsBetween(Now, Started);

    AssertEquals('every line came out', Many, i);
    AssertEquals('and the last one is whole',
      Format('{"n":%d}', [Many]), Last);
    AssertTrue(Format('taking %d lines took %d ms', [Many, Took]),
      Took < 2000);
  finally
    Buf.Free;
  end;
end;

initialization
  RegisterTest(TTestLineSplit);

end.
