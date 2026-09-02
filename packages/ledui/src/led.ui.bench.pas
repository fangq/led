{ led - a light editor.  Phase 0 long-line benchmark.

  medit truncates any line past 4096 characters and shows a clickable marker
  to reveal more, because GtkTextView's line-layout cache collapses on very
  long lines.  led ships the same feature, but how much machinery it needs
  depends on whether SynEdit has the same problem -- it paints only the
  visible horizontal window, so it may not.

  Run with `led --bench-longline`.  Needs a display. }
unit Led.UI.Bench;

{$mode objfpc}{$H+}

interface

function LedRunLongLineBench: Integer;

implementation

uses
  Classes, SysUtils, Forms, Controls, LCLIntf,
  Led.Core.FileIO, Led.UI.Main, Led.UI.Document, Led.UI.Tab, Led.UI.Edit;

type
  TStep = record
    Name: string;
    Millis: QWord;
  end;

var
  Steps: array of TStep;

{ The buffer length is printed beside every step on purpose.  Truncation is
  a display feature, so any step that changes this number has reached the
  text -- which is how the SelectAll-then-insert sequence below was caught
  replacing only the visible 4 KB. }
var
  WatchLen: function: Integer;

procedure Note(const AName: string; AStart: QWord);
var
  L: string;
begin
  SetLength(Steps, Length(Steps) + 1);
  Steps[High(Steps)].Name := AName;
  Steps[High(Steps)].Millis := GetTickCount64 - AStart;
  L := '';
  if WatchLen <> nil then
    L := Format('   buffer=%d', [WatchLen()]);
  WriteLn(Format('  %-42s %6d ms%s', [AName, Steps[High(Steps)].Millis, L]));
end;

procedure Pump;
var
  i: Integer;
begin
  for i := 1 to 3 do
    Application.ProcessMessages;
end;

function MakeSingleLineFile(AMegabytes: Integer): string;
var
  F: TFileStream;
  Chunk: string;
  i: Integer;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-bench-longline-%d.txt', [GetProcessID]);
  Chunk := StringOfChar('x', 1023) + ' ';        // 1 KiB, no line breaks
  F := TFileStream.Create(Result, fmCreate);
  try
    for i := 1 to AMegabytes * 1024 do
      F.WriteBuffer(Chunk[1], Length(Chunk));
  finally
    F.Free;
  end;
end;

{ The realistic long-line file: many of them, not one enormous one.  Minified
  JavaScript, a CSV of long records, a log with embedded payloads.  The
  single-line fixture is the pathological end of the range and the caret is
  always on the long line there, so it shows the truncation's overhead
  without any of its benefit; this one shows the case people actually open. }
function MakeManyLongLineFile(ALines, ALen: Integer): string;
var
  F: TFileStream;
  S: string;
  i: Integer;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-bench-manylong-%d.txt', [GetProcessID]);
  F := TFileStream.Create(Result, fmCreate);
  try
    for i := 1 to ALines do
    begin
      S := StringOfChar('x', ALen) + #10;
      F.WriteBuffer(S[1], Length(S));
    end;
  finally
    F.Free;
  end;
end;

function MakeManyLineFile(ALines: Integer): string;
var
  F: TFileStream;
  S: string;
  i: Integer;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-bench-manylines-%d.log', [GetProcessID]);
  F := TFileStream.Create(Result, fmCreate);
  try
    for i := 1 to ALines do
    begin
      S := Format('2026-09-01 00:00:00 [%7d] some log line with a bit of text'#10, [i]);
      F.WriteBuffer(S[1], Length(S));
    end;
  finally
    F.Free;
  end;
end;

function FileSizeKiB(const APath: string): Int64;
var
  S: TFileStream;
begin
  S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    Result := S.Size div 1024;
  finally
    S.Free;
  end;
end;

var
  BenchView: TLedEdit;

function BenchFirstLineLen: Integer;
begin
  if BenchView = nil then Exit(0);
  Result := Length(BenchView.Lines[0]);
end;

procedure BenchFile(F: TLedMainForm; const APath, ALabel: string);
var
  T: QWord;
  Tab: TLedTab;
  V: TLedEdit;
  Files: TStringList;
  i, Step: Integer;
begin
  WriteLn(Format('%s  (%d KiB on disk)', [ALabel, FileSizeKiB(APath)]));

  Files := TStringList.Create;
  try
    Files.Add(APath);
    T := GetTickCount64;
    F.OpenFiles(Files);
    Pump;
    Note('open file (decode + buffer + first paint)', T);
  finally
    Files.Free;
  end;

  Tab := F.ActiveTab;
  if Tab = nil then Exit;
  V := Tab.ActiveView;
  BenchView := V;
  WatchLen := @BenchFirstLineLen;

  T := GetTickCount64;
  V.CaretXY := Point(1, 1);
  Pump;
  Note('caret to start', T);

  T := GetTickCount64;
  V.CaretXY := Point(Length(V.Lines[0]) + 1, 1);
  Pump;
  Note('caret to end of the long line', T);

  T := GetTickCount64;
  V.CaretXY := Point(Length(V.Lines[0]) div 2, 1);
  Pump;
  Note('caret to the middle', T);

  { Scrolling, which is the operation long-line truncation exists to make
    cheap: every row that comes into view has to be measured and painted. }
  T := GetTickCount64;
  Step := V.Lines.Count div 20;
  if Step < 1 then Step := 1;
  i := 1;
  while i <= V.Lines.Count do
  begin
    V.TopLine := i;
    Application.ProcessMessages;
    Inc(i, Step);
  end;
  V.TopLine := 1;
  Pump;
  Note('scroll through the whole file', T);

  T := GetTickCount64;
  V.SelectAll;
  Pump;
  Note('select all', T);
  V.SelectionMode := V.SelectionMode;   { no-op; keep the selection alive }

  T := GetTickCount64;
  V.CaretXY := Point(1, 1);
  V.InsertTextAtCaret('typed ');
  Pump;
  Note('type one word at the start', T);

  T := GetTickCount64;
  V.Undo;
  Pump;
  Note('undo it', T);

  WriteLn(Format('  lines=%d  first line length=%d',
    [V.Lines.Count, Length(V.Lines[0])]));
  WriteLn;
end;

function LedRunLongLineBench: Integer;
var
  F: TLedMainForm;
  P1, P2, P3: string;
  T: QWord;
begin
  Result := 0;
  F := LedMainForm;
  F.Show;
  Pump;

  WriteLn('led long-line benchmark');
  WriteLn('  (decides how much machinery the truncate-and-reveal feature needs)');
  WriteLn;

  T := GetTickCount64;
  P1 := MakeSingleLineFile(5);
  P2 := MakeManyLineFile(200000);
  P3 := MakeManyLongLineFile(300, 30000);
  WriteLn(Format('fixtures generated in %d ms', [GetTickCount64 - T]));
  WriteLn;

  try
    BenchFile(F, P1, '5 MB on ONE line');
    BenchFile(F, P3, '300 lines of 30000 chars (the realistic case)');
    BenchFile(F, P2, '200k lines, ~13 MB');
  finally
    DeleteFile(P1);
    DeleteFile(P2);
    DeleteFile(P3);
  end;
end;

end.
