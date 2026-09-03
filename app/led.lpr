{ led - a light editor. }
program led;

{$mode objfpc}{$H+}

{ The application icon and the Windows manifest.  Generated from
  packaging/windows/led.rc by `make res`, and committed as led.res so a fresh
  clone builds without fpcres; only Windows reads it, but the directive is
  unconditional because FPC needs the file to exist on every target. }
{$R led.res}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, Forms, Classes, SysUtils,
  Led.Core.Types, Led.Core.CLI, Led.Core.Instance,
  Led.UI.Main, Led.UI.SelfTest, Led.UI.Bench, Led.UI.Dpi, Led.UI.Icons;

{ Returns the process exit code.  Written as a function rather than using
  Halt, so unit finalization still runs on the early exits -- otherwise every
  `led --version` ends with a leak report from heaptrc for allocations that
  were never actually leaked. }
function Run: Integer;
var
  Cmd: TLedCommandLine;
  Inst: TLedInstance;
  i: Integer;
  HandedOver: Boolean;
begin
  Result := 0;
  Cmd := TLedCommandLine.Create;
  try
    Cmd.ParseCommandLine;

    for i := 0 to Cmd.Errors.Count - 1 do
      WriteLn(StdErr, 'led: ', Cmd.Errors[i]);
    if Cmd.Errors.Count > 0 then
    begin
      WriteLn(StdErr, 'Try "led --help".');
      Exit(2);
    end;

    if Cmd.ShowHelp then
    begin
      WriteLn(Cmd.HelpText);
      Exit(0);
    end;
    if Cmd.ShowVersion then
    begin
      WriteLn('led ', LedVersion);
      Exit(0);
    end;

    { Hand over to an instance that is already running, unless told not to.
      The diagnostic modes always run in this process: handing --self-test to
      another instance would test the wrong binary. }
    HandedOver := False;
    Inst := TLedInstance.Create(Cmd.AppName);
    if (not Cmd.NewApp) and (not Cmd.SelfTest) and (not Cmd.BenchLongLine) then
    begin
      if Inst.Start = lirClient then
      begin
        if Cmd.FileCount > 0 then
          HandedOver := Inst.SendOpen(Cmd.ToJSON(GetCurrentDir))
        else
          { No files to pass on, but there is already an editor running, so
            just raise it rather than opening a second empty window. }
          HandedOver := Inst.SendOpen(Cmd.ToJSON(GetCurrentDir));
      end;
    end;

    if HandedOver then
    begin
      Inst.Free;
      Exit(0);
    end;

    { The app is LED; the binary, the config directory and the
      documentation stay lower-case 'led'. }
    Application.Title := LedAppTitle;
    RequireDerivedFormResource := True;
    {$IFDEF LINUX}
    { gtk2 caps Application.Scaled at the Xft DPI and reverts a manual bump on
      Show, so it cannot honour the desktop's integer window-scaling factor.
      Leave LCL auto-scaling off and scale the forms ourselves below.  See
      Led.UI.Dpi, ported from the sibling GotBox project. }
    Application.Scaled := False;
    {$ELSE}
    { Windows and macOS report a true per-monitor DPI; LCL is right there. }
    Application.Scaled := True;
    {$ENDIF}
    { Before the form, because building it reads a preference and TLedPrefs
      resolves its file name once, in its constructor. }
    if Cmd.SelfTest then
      LedPrepareSelfTestSandbox;

    Application.Initialize;
    Application.CreateForm(TLedMainForm, LedMainForm);
    { The window icon, from the PNG copy of the artwork embedded by
      packaging/windows/led.rc.

      Not from MAINICON, which is the same picture in the same binary.  The
      LCL reads that icon back correctly in process -- all seven sizes, the
      right image -- and then hands gtk2 something it publishes to the window
      manager with its colour channels striped and its alpha forced opaque,
      which is what a garbled title bar and task bar entry look like.  The
      PNG goes out intact, transparency and all.  MAINICON stays in the
      resource because Explorer and the installer read it off the file. }
    LedApplyWindowIcon;

    LedApplyAdaptiveScale;
    LedMainForm.AdoptInstance(Inst);

    if Cmd.SelfTest then
      Exit(LedRunSelfTest);
    if Cmd.BenchLongLine then
      Exit(LedRunLongLineBench);

    LedMainForm.ApplyCommandLine(Cmd, GetCurrentDir);
    Application.Run;
  finally
    Cmd.Free;
  end;
end;

begin
  ExitCode := Run;
end.
