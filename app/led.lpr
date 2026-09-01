{ led - a light editor. }
program led;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, Classes, SysUtils,
  Led.UI.Main, Led.UI.SelfTest, Led.UI.Bench;

function HasSwitch(const AName: string): Boolean;
var
  i: Integer;
begin
  for i := 1 to ParamCount do
    if ParamStr(i) = AName then Exit(True);
  Result := False;
end;

var
  Files: TStringList;
  i: Integer;
begin
  Application.Title := 'led';
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TLedMainForm, LedMainForm);

  if HasSwitch('--self-test') then
  begin
    ExitCode := LedRunSelfTest;
    Exit;
  end;

  if HasSwitch('--bench-longline') then
  begin
    ExitCode := LedRunLongLineBench;
    Exit;
  end;

  if ParamCount > 0 then
  begin
    Files := TStringList.Create;
    try
      for i := 1 to ParamCount do
        if (ParamStr(i) <> '') and (ParamStr(i)[1] <> '-') then
          Files.Add(ParamStr(i));
      if Files.Count > 0 then
        LedMainForm.OpenFiles(Files);
    finally
      Files.Free;
    end;
  end;

  Application.Run;
end.
