{ led - a light editor.  Scripted GUI self-test.

  Run with `led --self-test`.  Drives the real main window through a sequence
  of actions, checking the state the user would see, and exits non-zero on the
  first failure.  This is what catches the integration bugs -- action
  enabling, tab lifecycle, split teardown -- that headless unit tests over
  ledcore structurally cannot.

  It needs a display; in CI it runs under xvfb-run. }
unit Led.UI.SelfTest;

{$mode objfpc}{$H+}

interface

function LedRunSelfTest: Integer;

implementation

uses
  Classes, SysUtils, Forms, ComCtrls,
  Led.Core.Types, Led.Core.FileIO,
  Led.UI.Main, Led.UI.Document, Led.UI.Tab, Led.UI.Edit, Led.UI.Dock;

var
  Failures: Integer = 0;
  Checks: Integer = 0;

procedure Check(const AName: string; ACondition: Boolean);
begin
  Inc(Checks);
  if ACondition then
    WriteLn('  ok    ', AName)
  else
  begin
    WriteLn('  FAIL  ', AName);
    Inc(Failures);
  end;
end;

procedure CheckEq(const AName: string; const AExpected, AActual: string);
begin
  Inc(Checks);
  if AExpected = AActual then
    WriteLn('  ok    ', AName)
  else
  begin
    WriteLn('  FAIL  ', AName);
    WriteLn('          expected: ', AExpected);
    WriteLn('          actual:   ', AActual);
    Inc(Failures);
  end;
end;

procedure CheckEqInt(const AName: string; AExpected, AActual: Integer);
begin
  CheckEq(AName, IntToStr(AExpected), IntToStr(AActual));
end;

procedure Pump;
var
  i: Integer;
begin
  for i := 1 to 5 do
    Application.ProcessMessages;
end;

function TempName(const ASuffix: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-selftest-%d-%s', [GetProcessID, ASuffix]);
end;

{ --- the spikes phase 0 exists to prove ------------------------------------ }

procedure TestSharedBufferSplitView(F: TLedMainForm);
var
  Tab: TLedTab;
  V0, V1: TLedEdit;
begin
  WriteLn('shared-buffer split view');
  Tab := F.ActiveTab;
  Check('a tab exists', Tab <> nil);
  if Tab = nil then Exit;

  CheckEqInt('one view to start', 1, Tab.ViewCount);
  V0 := Tab.ActiveView;
  V0.Lines.Text := 'alpha' + LineEnding + 'beta' + LineEnding + 'gamma';
  V0.ClearUndo;
  Pump;

  Tab.SplitView(False);
  Pump;
  CheckEqInt('two views after split', 2, Tab.ViewCount);
  V1 := Tab.Views[1];

  { The whole view model rests on this: one buffer, many views. }
  CheckEq('text is shared', V0.Lines.Text, V1.Lines.Text);

  { Edit the way a user does -- through the editor, not by poking the string
    list -- because that is what goes onto the undo list. }
  V0.CaretXY := Point(1, 2);
  V0.SelectLine(False);
  V0.SelText := 'BETA';
  Pump;
  CheckEq('edit in view 0 is visible in view 1', 'BETA', V1.Lines[1]);

  { Undo lives in the shared string list, so undoing through either view
    affects both. }
  V1.Undo;
  Pump;
  CheckEq('undo is shared', 'beta', V0.Lines[1]);
  V1.Redo;
  Pump;
  CheckEq('redo is shared', 'BETA', V0.Lines[1]);

  { Caret and scroll must stay independent, or split view is pointless. }
  V0.CaretXY := Point(1, 1);
  V1.CaretXY := Point(1, 3);
  Pump;
  Check('carets are independent', (V0.CaretY = 1) and (V1.CaretY = 3));

  { Marks are shared through eosShareMarks. }
  V0.SetBookMark(0, 1, 2);
  Pump;
  Check('bookmarks are shared', V1.Marks.Count > 0);

  Tab.Unsplit;
  Pump;
  CheckEqInt('back to one view after unsplit', 1, Tab.ViewCount);

  { Stacked split and cycling. }
  Tab.SplitView(True);
  Pump;
  CheckEqInt('two views after stacked split', 2, Tab.ViewCount);
  Tab.CycleViews;
  Pump;
  Tab.Unsplit;
  Pump;
  CheckEqInt('one view again', 1, Tab.ViewCount);
end;

procedure TestDockEdges(F: TLedMainForm);
var
  E: TLedDockEdge;
begin
  WriteLn('four-edge dock');
  for E := Low(TLedDockEdge) to High(TLedDockEdge) do
  begin
    F.Dock.EdgeVisible[E] := True;
    Pump;
    Check('edge ' + LedDockEdgeName[E] + ' shows', F.Dock.EdgeVisible[E]);
    F.Dock.EdgeVisible[E] := False;
    Pump;
    Check('edge ' + LedDockEdgeName[E] + ' hides', not F.Dock.EdgeVisible[E]);
  end;
  Check('a registered pane is findable', F.Dock.FindPane('files') <> nil);
  F.Dock.ShowPane('files');
  Pump;
  Check('showing a pane reveals its edge', F.Dock.EdgeVisible[ledLeft]);
  F.Dock.EdgeVisible[ledLeft] := False;
end;

procedure TestTabsAndFileRoundTrip(F: TLedMainForm);
var
  Path: string;
  Doc: TLedDocument;
  Before, After: string;
  Info: TLedTextInfo;
  N: Integer;
begin
  WriteLn('tabs and file round trip');
  N := F.Notebook.PageCount;
  F.AddTab(F.Documents.NewDocument);
  Pump;
  CheckEqInt('new tab added', N + 1, F.Notebook.PageCount);

  Path := TempName('roundtrip.txt');
  Doc := F.ActiveTab.Document;
  Doc.Master.Lines.Text := 'one' + LineEnding + 'two' + LineEnding + 'three';
  Doc.SaveToFile(Path);
  Pump;
  Check('document is no longer modified after save', not Doc.Modified);
  CheckEq('tab caption follows the file name', ExtractFileName(Path),
    F.ActiveTab.Sheet.Caption);

  Before := Doc.Master.Lines.Text;
  LedLoadTextFile(Path, After, Info);
  CheckEq('saved text reloads identically',
    StringReplace(Before, LineEnding, #10, [rfReplaceAll]),
    After);
  DeleteFile(Path);
end;

procedure TestLineEndDetection;
begin
  WriteLn('line-ending detection');
  Check('LF',    LedDetectLineEnd('a'#10'b') = leUnix);
  Check('CRLF',  LedDetectLineEnd('a'#13#10'b') = leWindows);
  Check('CR',    LedDetectLineEnd('a'#13'b') = leMac);
  Check('mixed', LedDetectLineEnd('a'#13#10'b'#10'c') = leMixed);
  Check('none',  LedDetectLineEnd('abc') = leUnknown);
end;

function LedRunSelfTest: Integer;
var
  F: TLedMainForm;
begin
  WriteLn('led self-test');
  WriteLn;

  F := LedMainForm;
  F.Show;
  Pump;

  TestLineEndDetection;
  WriteLn;
  TestSharedBufferSplitView(F);
  WriteLn;
  TestDockEdges(F);
  WriteLn;
  TestTabsAndFileRoundTrip(F);
  WriteLn;

  WriteLn(Format('%d checks, %d failures', [Checks, Failures]));
  if Failures = 0 then
    Result := 0
  else
    Result := 1;
end;

end.
