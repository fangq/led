{ led - a light editor.  Adaptive high-DPI scaling.

  Ported from the sibling Lazarus project GotBox, whose comments explain the
  problem better than a summary can: on gtk2, Application.Scaled caps at the
  Xft DPI and will not honour the desktop's integer window-scaling factor --
  it even reverts a manual bump on Show -- so on Linux we leave LCL
  auto-scaling off and scale the forms ourselves, to
  Xft.dpi * WindowScalingFactor.  That is what gtk3 applications render at, so
  led's geometry and fonts grow together and match everything else on screen.

  Windows and macOS report a true per-monitor DPI and LCL's own scaling is
  correct there, so this is a no-op: the target equals the form's current PPI
  and every routine returns without touching anything.

  LED_SCALE, or GDK_SCALE, overrides the target as a factor relative to 96. }
unit Led.UI.Dpi;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, Graphics;

{ The PPI forms should be scaled to right now.  Recomputed on every call, with
  no caching, so a desktop scale change is picked up live. }
function LedDesiredPPI: Integer;

{ Scale one form from its current PPI to the desktop target.  Call for forms
  built in code -- dialogs -- which are not covered by the startup sweep. }
procedure LedScaleForm(AForm: TCustomForm);

{ Scale every form that exists to the desktop target.  Call once at startup,
  after the forms are created. }
procedure LedApplyAdaptiveScale;

{ Re-read the desktop scale and re-scale everything if it moved.  Returns True
  when a change was applied.  Suitable for a low-frequency timer: gtk2 never
  tells us the desktop scale changed. }
function LedRefreshScale: Boolean;

{ Scale a pixel constant that was chosen at 96 dpi.  Sizes written as literals
  -- gutter widths, icon paddings -- do not go through AutoAdjustLayout when
  the control is created after the form was scaled, so they need this. }
function LedScale96(APixels: Integer): Integer;

{ The point size the editor should use when the user has expressed no
  preference: the system UI font's size, so led does not open smaller than
  every other application on the desktop.  A monospace face at the UI font's
  size is what medit effectively did by inheriting the GTK theme font. }
function LedDefaultFontSize: Integer;

{ The default monospace family for this platform. }
function LedDefaultFontName: string;

implementation

uses
  {$IFDEF LINUX}Process{$ENDIF};

{ The desktop's integer window-scaling factor -- xfce's
  Gdk/WindowScalingFactor -- or 0 when it cannot be determined.  gtk2 ignores
  it, so read it directly and match what other applications do. }
function LedDesktopScalingFactor: Integer;
{$IFDEF LINUX}
var
  Outp: string;
begin
  Result := 0;
  Outp := '';
  try
    if RunCommand('xfconf-query',
      ['-c', 'xsettings', '-p', '/Gdk/WindowScalingFactor'], Outp) then
      Result := StrToIntDef(Trim(Outp), 0);
  except
    { xfconf-query missing, or no xsettings channel.  Not an error: most
      desktops do not have one, and 0 means "assume 1". }
    Result := 0;
  end;
end;
{$ELSE}
begin
  Result := 0;
end;
{$ENDIF}

var
  GAppliedPPI: Integer = 0;   { the PPI every form is currently scaled to }

function LedDesiredPPI: Integer;
var
  S: string;
  Fs: TFormatSettings;
  Factor: Double;
  Wsf: Integer;
begin
  { An explicit override wins, as a factor relative to 96. }
  S := GetEnvironmentVariable('LED_SCALE');
  if S = '' then
    S := GetEnvironmentVariable('GDK_SCALE');
  if S <> '' then
  begin
    Fs := DefaultFormatSettings;
    Fs.DecimalSeparator := '.';
    Factor := StrToFloatDef(StringReplace(S, ',', '.', []), 0, Fs);
    if Factor > 0 then
      Exit(Round(96 * Factor));
  end;

  { Baseline: the DPI the widgetset reports, which on gtk2 is Xft.dpi.  gtk2
    renders fonts at that DPI but lays forms out at 96, so scaling to it alone
    leaves the geometry lagging the fonts; multiplying by the desktop's
    integer factor makes both grow together. }
  Result := Screen.PixelsPerInch;
  if Result <= 0 then
    Result := 96;
  Wsf := LedDesktopScalingFactor;
  if Wsf >= 2 then
    Result := Result * Wsf;
end;

function LedScale96(APixels: Integer): Integer;
var
  Ppi: Integer;
begin
  Ppi := GAppliedPPI;
  if Ppi <= 0 then
    Ppi := LedDesiredPPI;
  if Ppi <= 0 then
    Ppi := 96;
  Result := (APixels * Ppi) div 96;
  if (APixels > 0) and (Result < 1) then
    Result := 1;
end;

{ Scale one form between two PPI values, in either direction. }
procedure LedScaleFormTo(AForm: TCustomForm; ATargetPPI: Integer);
var
  Cur: Integer;
begin
  if (AForm = nil) or (ATargetPPI <= 0) then
    Exit;
  Cur := AForm.PixelsPerInch;
  if Cur <= 0 then
    Cur := 96;
  if ATargetPPI <> Cur then
    AForm.AutoAdjustLayout(lapAutoAdjustForDPI, Cur, ATargetPPI,
      AForm.Width, Round(AForm.Width * ATargetPPI / Cur));
end;

procedure LedScaleForm(AForm: TCustomForm);
var
  Tgt: Integer;
begin
  Tgt := GAppliedPPI;          { match whatever the open windows are at }
  if Tgt <= 0 then
    Tgt := LedDesiredPPI;
  LedScaleFormTo(AForm, Tgt);
end;

procedure LedApplyScaleAll(ATargetPPI: Integer);
var
  i: Integer;
begin
  for i := 0 to Screen.CustomFormCount - 1 do
    try
      LedScaleFormTo(Screen.CustomForms[i], ATargetPPI);
    except
      { Scaling is cosmetic and must never take the editor down with it. }
    end;
  GAppliedPPI := ATargetPPI;
end;

procedure LedApplyAdaptiveScale;
begin
  LedApplyScaleAll(LedDesiredPPI);
end;

function LedRefreshScale: Boolean;
var
  D: Integer;
begin
  D := LedDesiredPPI;
  Result := (D > 0) and (D <> GAppliedPPI);
  if Result then
    LedApplyScaleAll(D);
end;

function LedDefaultFontName: string;
begin
  Result := {$IFDEF WINDOWS}'Consolas'{$ELSE}
            {$IFDEF DARWIN}'Menlo'{$ELSE}'Monospace'{$ENDIF}{$ENDIF};
end;

function LedDefaultFontSize: Integer;
begin
  { Screen.SystemFont carries the desktop's UI font.  A negative Size means it
    was given in pixels and a zero means "widgetset default"; neither is a
    point size, and converting a pixel height here would need the font's own
    DPI, so fall back rather than guess. }
  Result := 0;
  if Screen.SystemFont <> nil then
    Result := Screen.SystemFont.Size;
  if Result <= 0 then
    Result := 10;
  { A monospace face at the UI size reads slightly larger than the
    proportional original, but smaller is the complaint that actually gets
    made, and medit inherited the theme font unchanged. }
  if Result < 9 then
    Result := 9;
  if Result > 16 then
    Result := 16;
end;

end.
