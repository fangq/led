{ led - a lightweight editor.  Adaptive high-DPI scaling.

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

{ The font correction near the bottom of this unit is gtk2's alone.  Split out
  so the interface can promise the same functions on every target and answer
  "nothing to correct" everywhere else. }
{$IF DEFINED(LINUX) and DEFINED(LCLGtk2)}
  {$DEFINE LED_GTK2_CHROME}
{$ENDIF}

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

{ Install the resource style that scales everything gtk draws for itself.
  Call once at startup, before the first widget exists: a widget is asked how
  big it wants to be as it is built, and both gtk and the LCL keep the answer,
  so a style arriving later changes what things are drawn with and not how big
  they were made.  Called again when the desktop scale moves, where
  re-styling is all that is wanted. }
procedure LedInstallChromeStyle;

{ Scale every form from the moment it is first shown, for the rest of the
  session.  Call once at startup.

  LedApplyAdaptiveScale only reaches the forms that exist when it runs, and
  LedScaleForm has to be called by hand for the rest -- which works for led's
  own dialogs and not at all for the ones the LCL builds internally.  A
  message box, and the dialog TApplication puts up for an unhandled
  exception, are created deep inside the LCL and shown without led ever
  holding a reference: they came up at their design size, a third of the
  window that raised them, with text to match.

  Hooked on visibility rather than on creation.  Screen.AddForm fires from
  TCustomForm.CreateNew, before the .lfm is read and before any descendant
  constructor has added a control, so a form scaled there would be an empty
  one.  By the time Visible turns on, the form is furnished.

  Scaling is idempotent, so this and the startup sweep cannot compound:
  TCustomDesignControl.AutoAdjustLayout returns immediately when the form is
  already at the target PPI, and records the new one when it is not. }
procedure LedInstallFormScaler;

{ Re-read the desktop scale and re-scale everything if it moved.  Returns True
  when a change was applied.  Suitable for a low-frequency timer: gtk2 never
  tells us the desktop scale changed. }
function LedRefreshScale: Boolean;

{ Scale a pixel constant that was chosen at 96 dpi.  Sizes written as literals
  -- gutter widths, icon paddings -- do not go through AutoAdjustLayout when
  the control is created after the form was scaled, so they need this. }
function LedScale96(APixels: Integer): Integer;

{ The point size to actually assign to a font so that a preference of
  APoints ends up the size led's windows are scaled to.  The sibling of
  LedScale96, for point sizes rather than pixel constants.

  Not a matter of Font.Height or Font.PixelsPerInch: on gtk2 neither moves
  the rendered size by a pixel.  CreateFontIndirectEx builds the pango
  description from the point size the font carries and says so in its own
  comment -- "if font specified size, prefer this instead of 'possibly'
  inaccurate lfHeight" -- and pango then renders those points at the screen's
  resolution, which is the Xft DPI and not the PPI the forms were scaled to.
  So the number of points is the only lever there is.

  Windows and macOS do honour the height, and there the factor is 1 and this
  returns APoints untouched. }
function LedScalePointSize(APoints: Integer): Integer;

{ How much bigger the text gtk draws for itself has to be to sit at the same
  size as everything led scales.  1 when there is nothing to correct. }
function LedChromeFontFactor: Double;

{ The desktop's own UI font at that factor, as a pango description string --
  "Ubuntu 20" -- or '' when the factor is 1 or the platform draws its own
  widgets at the right size already.  Public for the self-test. }
function LedScaledChromeFont: string;

{ The point size the editor should use when the user has expressed no
  preference: the system UI font's size, so led does not open smaller than
  every other application on the desktop.  A monospace face at the UI font's
  size is what medit effectively did by inheriting the GTK theme font. }
function LedDefaultFontSize: Integer;

{ The default monospace family for this platform. }
function LedDefaultFontName: string;

{ Split an "Editor/font" value into a family and a point size.  The
  Preferences dialog writes these as Pango does -- "Fira Code 11" -- so the
  size is a trailing integer and everything before it is the family, which
  may itself contain spaces.  An empty or unparseable spec yields the
  platform defaults rather than an error: a bad font preference should look
  wrong, not stop the editor. }
procedure LedParseFontSpec(const ASpec: string; out AName: string;
  out ASize: Integer);

{ Darkens (or reverts) AForm's Windows title bar via DWM's immersive-dark-mode
  attribute.  A no-op everywhere else, and a silent no-op on Windows builds too
  old to know the attribute -- this is cosmetic and must never fail loudly. }
procedure LedApplyDarkTitleBar(AForm: TCustomForm; AEnable: Boolean);

implementation

{ The whole clause is conditional, not just the unit inside it: on Windows a
  "uses {$IFDEF LINUX}...{$ENDIF};" collapses to "uses ;", which is a syntax
  error rather than an empty list.  Same trap as the BaseUnix import in
  Led.Core.FileIO. }
{$IFDEF LINUX}
uses
  Process{$IFDEF LED_GTK2_CHROME}, Glib2, Gtk2, Pango{$ENDIF};
{$ENDIF}
{$IFDEF WINDOWS}
uses
  Windows;
{$ENDIF}

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
  GAppliedChromeFont: string = '';  { what gtk was last told to draw its own widgets in }
  { The theme's own font, read once and kept.  The style installed below is
    global, so after it has been installed the default style no longer reports
    the theme's size -- it reports ours.  Everything that needs the original
    reads it from here instead, which is what stops a second pass multiplying
    the factor in again. }
  GBaseFontSpec: string = '';
  GBaseFontSize: Integer = 0;
  GBaseFontTaken: Boolean = False;

function LedDesiredPPI: Integer;
var
  S: string;
  Fs: TFormatSettings;
  Factor: Double;
  Wsf: Integer;
begin
  { An explicit override wins, as a factor relative to 96.  Qualified
    because the Windows unit, pulled in below for the dark-title-bar call,
    declares its own GetEnvironmentVariable with a different signature. }
  S := SysUtils.GetEnvironmentVariable('LED_SCALE');
  if S = '' then
    S := SysUtils.GetEnvironmentVariable('GDK_SCALE');
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

{ The PPI the windows are actually at: the applied one once the startup sweep
  has run, the desired one before it. }
function ActivePPI: Integer;
begin
  Result := GAppliedPPI;
  if Result <= 0 then
    Result := LedDesiredPPI;
  if Result <= 0 then
    Result := 96;
end;

function LedScale96(APixels: Integer): Integer;
begin
  Result := (APixels * ActivePPI) div 96;
  if (APixels > 0) and (Result < 1) then
    Result := 1;
end;

{ Every string gtk2 draws -- its own menu captions, and the text of any font
  led hands it -- is rendered from a point size at the pango resolution, which
  is Xft.dpi.  Nothing about that resolution follows the desktop's integer
  window-scaling factor, and nothing about it follows the PPI the forms were
  scaled to either: gtk2 ignores the first and never hears about the second.

  So on a 150-dpi Xft desktop scaled by 2, everything drawn from a point size
  lands at 150 dpi inside windows laid out for 300 -- a menu bar half the
  height of every other application's, and an editor whose 10-point
  preference draws 21 pixels tall in a window scaled for 42.

  This is the one ratio that closes both gaps, and it is why the two fixes
  below share it: LedScalePointSize multiplies the sizes led assigns, and the
  resource style multiplies the size gtk uses for the widgets led does not
  own.  Never below 1 -- the theme font is the user's own choice of size, and
  shrinking it would answer a complaint nobody made. }
function LedChromeFontFactor: Double;
{$IFDEF LED_GTK2_CHROME}
var
  Base: Integer;
begin
  Base := Screen.PixelsPerInch;      { the DPI gtk2 will draw its menus at }
  if Base <= 0 then
    Exit(1.0);
  Result := ActivePPI / Base;
  if Result < 1.0 then
    Result := 1.0;
end;
{$ELSE}
begin
  { Windows and macOS scale their menus with the rest of the window, and gtk3
    and qt both honour the desktop's scaling factor themselves. }
  Result := 1.0;
end;
{$ENDIF}

{ Reads the theme's font once and remembers it.  Must run before the style
  below is installed, which it does: the first thing that wants a scaled font
  has to ask for the unscaled one to build it from. }
procedure TakeBaseFont;
{$IFDEF LED_GTK2_CHROME}
var
  Style: PGtkStyle;
  Spec: PChar;
begin
  if GBaseFontTaken then Exit;
  GBaseFontTaken := True;
  Style := gtk_widget_get_default_style;
  if (Style = nil) or (Style^.font_desc = nil) then Exit;
  GBaseFontSize := pango_font_description_get_size(Style^.font_desc);
  if not pango_font_description_get_size_is_absolute(Style^.font_desc) then
    GBaseFontSize := GBaseFontSize div PANGO_SCALE;
  Spec := pango_font_description_to_string(Style^.font_desc);
  if Spec <> nil then
  begin
    GBaseFontSpec := StrPas(Spec);
    g_free(Spec);
  end;
end;
{$ELSE}
begin
end;
{$ENDIF}

function LedScaledChromeFont: string;
{$IFDEF LED_GTK2_CHROME}
var
  Factor: Double;
  Scaled: PPangoFontDescription;
  Size: gint;
  Spec: PChar;
begin
  Result := '';
  TakeBaseFont;
  Factor := LedChromeFontFactor;
  { Not "<= 1": the factor is a ratio of two integer DPIs, and a fraction of a
    point either way is not worth overriding the theme for. }
  if Factor <= 1.001 then
    Exit;

  { Built from the remembered theme font, not from whatever the default style
    says now -- the style below is global, so by the second call the default
    style is already ours. }
  if GBaseFontSpec = '' then
    Exit;
  Scaled := pango_font_description_from_string(PChar(GBaseFontSpec));
  if Scaled = nil then
    Exit;
  try
    Size := pango_font_description_get_size(Scaled);
    { A description that carries no size; nothing to scale. }
    if Size <= 0 then
      Exit;
    { A size is in points or in device pixels, and the two are set by
      different calls: set_size on an absolute description would quietly
      reinterpret its pixels as points. }
    if pango_font_description_get_size_is_absolute(Scaled) then
      pango_font_description_set_absolute_size(Scaled, Size * Factor)
    else
      pango_font_description_set_size(Scaled, Round(Size * Factor));
    Spec := pango_font_description_to_string(Scaled);
    if Spec <> nil then
    begin
      Result := StrPas(Spec);
      g_free(Spec);
    end;
  finally
    pango_font_description_free(Scaled);
  end;
end;
{$ELSE}
begin
  Result := '';
end;
{$ENDIF}

function LedScalePointSize(APoints: Integer): Integer;
begin
  Result := Round(APoints * LedChromeFontFactor);
  { A factor of 1 -- and any font whose size is unset -- comes back unchanged
    rather than rounded to nothing. }
  if Result < 1 then
    Result := APoints;
end;

{ Hand gtk the scaled font as a resource style, for every widget it draws.

  Scoped to menus, the status bar and dialogs to begin with, on the theory
  that everything else went through a TFont led controls.  It does not.  A
  gtk widget's own style font stays the theme's until the LCL decides to
  override it per widget, and a great deal is sized from that style rather
  than from the font:

    - gtk_widget_size_request, which is where an AutoSize control gets its
      height.  A TEdit came out 34 pixels tall holding 42-pixel text, because
      the GtkEntry was asked how tall it wanted to be while it still had the
      21-pixel theme font.
    - a tree view's column headers, which are buttons of gtk's own and never
      see the font the LCL puts on the tree.

  So the style is global now.  It cannot reach anything led sizes itself: a
  control whose TFont carries a height pushes that font to its widget with
  gtk_widget_modify_font, and a modification beats a style.  What is left is
  exactly the set that was wrong -- widgets still drawing with the theme's
  font because nothing had told them otherwise.

  What this does not carry is a check box's indicator, which is not text but a
  style property in device pixels.  Setting GtkCheckButton::indicator-size in
  this same style does move it for a check button built by hand -- measured,
  40 instead of 13 -- and does not move the ones the LCL builds, through any
  of the three pattern forms.  So a check box is still a 16-pixel box beside
  40-pixel text, and the cause is not yet understood.  Left out rather than
  left in and not working. }
procedure LedInstallChromeStyle;
{$IFDEF LED_GTK2_CHROME}
var
  Spec: string;
begin
  Spec := LedScaledChromeFont;
  if (Spec = '') or (Spec = GAppliedChromeFont) then
    Exit;
  gtk_rc_parse_string(PChar(
    'style "led_scaled_chrome"'#10 +
    '{'#10 +
    '  font_name = "' + Spec + '"'#10 +
    '}'#10 +
    'class "*" style "led_scaled_chrome"'#10));
  { For the refresh: at startup this runs before there is anything to
    re-style, but when the desktop scale moves every widget already exists. }
  gtk_rc_reset_styles(gtk_settings_get_default);
  GAppliedChromeFont := Spec;
end;
{$ELSE}
begin
  { Nothing to hand anyone: LedScaledMenuFont is empty off gtk2. }
end;
{$ENDIF}

{ Puts back the fonts of every control that did not have one of its own.

  With the resource style in place the theme font is already the right size,
  so a control that never set a font is already drawn correctly -- gtk2
  resolves a font carrying neither size nor height from the default style, and
  the default style is ours.  AutoAdjustLayout does not know that: it reads
  the height back off that same scaled widget and multiplies it by the PPI
  ratio, which turns 42 pixels into 84.

  So the ones that were untouched before the scaling are made untouched again
  afterwards.  Only those: a control that carries a real size keeps it, which
  is what the editor, the terminal and the output pane rely on.

  The alternative was to leave the style until after the forms were built,
  which keeps the fonts right and leaves every widget the wrong size -- an
  AutoSize control is measured as it is built, and a TEdit measured with the
  21-pixel theme font is 34 pixels tall for ever after.  Asking it again later
  does not help: the widget still has the theme's font, because the LCL never
  pushes a font to an entry that inherits one. }
procedure LedKeepDefaultFonts(AControl: TControl; ACollect: Boolean;
  AList: TFPList);
var
  i: Integer;
begin
  if AControl = nil then Exit;
  if ACollect then
  begin
    if (AControl.Font <> nil) and (AControl.Font.Height = 0) and
       (AControl.Font.Size = 0) then
      AList.Add(AControl);
  end
  else if AList.IndexOf(AControl) >= 0 then
    AControl.Font.Height := 0;
  if AControl is TWinControl then
    for i := 0 to TWinControl(AControl).ControlCount - 1 do
      LedKeepDefaultFonts(TWinControl(AControl).Controls[i], ACollect, AList);
end;

{ Scale one form between two PPI values, in either direction. }
procedure LedScaleFormTo(AForm: TCustomForm; ATargetPPI: Integer);
var
  Cur: Integer;
  Untouched: TFPList;
begin
  if (AForm = nil) or (ATargetPPI <= 0) then
    Exit;
  Cur := AForm.PixelsPerInch;
  if Cur <= 0 then
    Cur := 96;
  if ATargetPPI <> Cur then
  begin
    Untouched := TFPList.Create;
    try
      LedKeepDefaultFonts(AForm, True, Untouched);
      AForm.AutoAdjustLayout(lapAutoAdjustForDPI, Cur, ATargetPPI,
        AForm.Width, Round(AForm.Width * ATargetPPI / Cur));
      LedKeepDefaultFonts(AForm, False, Untouched);
    finally
      Untouched.Free;
    end;
  end;
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
  { After GAppliedPPI, which is the target the menu font is measured against. }
  LedInstallChromeStyle;
end;

procedure LedApplyAdaptiveScale;
begin
  LedApplyScaleAll(LedDesiredPPI);
end;

type
  { Screen's handler lists take a method, and this unit is otherwise all
    plain procedures, so one hidden instance carries the callback. }
  TLedFormScaler = class
    procedure FormVisibleChanged(Sender: TObject; AForm: TCustomForm);
  end;

procedure TLedFormScaler.FormVisibleChanged(Sender: TObject;
  AForm: TCustomForm);
begin
  if (AForm = nil) or (not AForm.Visible) then Exit;
  try
    LedScaleForm(AForm);
  except
    { As everywhere else here: a form that will not scale is a cosmetic
      problem, and this one runs while another dialog is being shown -- quite
      possibly the one reporting an error already. }
  end;
end;

var
  GFormScaler: TLedFormScaler = nil;

procedure LedInstallFormScaler;
begin
  if GFormScaler <> nil then Exit;
  GFormScaler := TLedFormScaler.Create;
  Screen.AddHandlerFormVisibleChanged(@GFormScaler.FormVisibleChanged);
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

procedure LedParseFontSpec(const ASpec: string; out AName: string;
  out ASize: Integer);
var
  Spec, Tail: string;
  p, n: Integer;
begin
  AName := LedDefaultFontName;
  ASize := LedDefaultFontSize;

  Spec := Trim(ASpec);
  if Spec = '' then Exit;

  p := 0;
  for n := Length(Spec) downto 1 do
    if Spec[n] = ' ' then
    begin
      p := n;
      Break;
    end;
  n := -1;
  if p > 1 then
  begin
    Tail := Copy(Spec, p + 1, MaxInt);
    n := StrToIntDef(Tail, -1);
  end;
  if n > 0 then
  begin
    AName := Trim(Copy(Spec, 1, p - 1));
    ASize := n;
    if AName = '' then
      AName := LedDefaultFontName;
  end
  else
    { No trailing size: the whole thing is a family name, and the size stays
      at the system default rather than reverting to a hard-coded one. }
    AName := Spec;

  { A family that is not actually installed -- "Monospace" surviving from a
    Linux prefs.ini, or a bad literal an older build wrote to disk -- looks
    pixelated at every size rather than merely wrong at one, so it gets the
    same fallback an empty preference does.  Checked here rather than only
    where the preference is read, so a value already on disk self-heals
    without the user having to touch Preferences. }
  if Screen.Fonts.IndexOf(AName) < 0 then
    AName := LedDefaultFontName;
end;

function LedDefaultFontSize: Integer;
begin
  { The theme's own size, taken before the resource style replaced it.  Asking
    Screen.SystemFont now would hand back the scaled one, and this number is
    multiplied by the same factor again on its way to the editor -- the
    desktop's ten points would come back as twenty, be clamped to sixteen, and
    open the editor at thirty-two. }
  Result := 0;
  {$IFDEF LED_GTK2_CHROME}
  TakeBaseFont;
  Result := GBaseFontSize;
  {$ENDIF}
  { Screen.SystemFont carries the desktop's UI font.  A negative Size means it
    was given in pixels and a zero means "widgetset default"; neither is a
    point size, and converting a pixel height here would need the font's own
    DPI, so fall back rather than guess. }
  if (Result <= 0) and (Screen.SystemFont <> nil) then
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

{$IFDEF WINDOWS}
const
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

function DwmSetWindowAttribute(hWnd: HWND; dwAttribute: DWORD;
  pvAttribute: Pointer; cbAttribute: DWORD): HRESULT;
  stdcall; external 'dwmapi.dll';

procedure LedApplyDarkTitleBar(AForm: TCustomForm; AEnable: Boolean);
var
  Flag: LongBool;
begin
  if AForm = nil then Exit;
  try
    Flag := AEnable;
    DwmSetWindowAttribute(AForm.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE,
      @Flag, SizeOf(Flag));
  except
    { Older Windows builds do not know this attribute; leave the title bar
      as the widgetset drew it. }
  end;
end;
{$ELSE}
procedure LedApplyDarkTitleBar(AForm: TCustomForm; AEnable: Boolean);
begin
  { Only Windows has a title bar to darken this way. }
end;
{$ENDIF}

finalization
  { Screen outlives this unit's data, so the handler has to come off before
    the object it points into goes away. }
  if GFormScaler <> nil then
  begin
    if Screen <> nil then
      Screen.RemoveHandlerFormVisibleChanged(@GFormScaler.FormVisibleChanged);
    FreeAndNil(GFormScaler);
  end;

end.
