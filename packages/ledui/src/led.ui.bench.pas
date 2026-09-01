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

procedure Note(const AName: string; AStart: QWord);
begin
  SetLength(Steps, Length(Steps) + 1);
  Steps[High(Steps)].Name := AName;
  Steps[High(Steps)].Millis := GetTickCount64 - AStart;
  WriteLn(Format('  %-42s %6d ms', [AName, Steps[High(Steps)].Millis]));
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

procedure BenchFile(F: TLedMainForm; const APath, ALabel: string);
var
  T: QWord;
  Tab: TLedTab;
  V: TLedEdit;
  Files: TStringList;
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
  P1, P2: string;
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
  WriteLn(Format('fixtures generated in %d ms', [GetTickCount64 - T]));
  WriteLn;

  try
    BenchFile(F, P1, '5 MB on ONE line');
    BenchFile(F, P2, '200k lines, ~13 MB');
  finally
    DeleteFile(P1);
    DeleteFile(P2);
  end;
end;

end.
