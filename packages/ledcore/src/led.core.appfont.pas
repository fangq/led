{ led - a lightweight editor.  The fonts led brings with it.

  led ships Fira Code so that its default is the same font everywhere rather
  than whatever each desktop happens to call "Monospace".  Nothing is
  installed: each platform has a call that adds a font file to the running
  process and no further, which is the whole of this unit.

    fontconfig   FcConfigAppFontAddFile          (gtk2, qt)
    GDI          AddFontResourceEx .. FR_PRIVATE (Windows)
    CoreText     CTFontManagerRegisterFontsForURL, process scope (macOS)

  There is no LCL call for this -- nothing in the widgetset interface does it
  on any platform -- so the three are written out here.

  WHEN this runs is not a detail.  gtk builds pango's font map during
  gtk_init, and a font added to fontconfig after that is invisible no matter
  what the call returns.  gtk_init happens in the Interfaces unit's own
  initialization, so being early in the program's begin block -- even before
  Application.Initialize -- is already too late.  This unit is therefore
  listed before Interfaces in led.lpr and does its work from its
  initialization section, which the compiler runs in that order.

  Measured, loading a font that was not installed on the machine:

    added after Interfaces' initialization   not found, text fell back
    added before it                          found, and drawn

  Hence also why this lives in ledcore and uses nothing but SysUtils and
  Led.Core.Paths: a unit that pulled in an LCL unit would drag Interfaces in
  with it and initialise the widgetset before itself. }
unit Led.Core.AppFont;

{$mode objfpc}{$H+}

interface

{ The family led ships and prefers.  A constant rather than a string spelled
  out at each use: it is also what the font files call themselves, and the
  two have to agree or the preference silently falls back. }
const
  LedBundledFontName = 'Fira Code';

{ Registers the bundled fonts with the process.  Safe to call more than once
  and safe when the files are missing -- a source tree without data/fonts, or
  an install that dropped them, simply gets the platform default. }
procedure LedLoadBundledFonts;

{ Whether the last call managed it.  For the self-test, and for deciding
  whether the bundled family may be offered as a default. }
function LedBundledFontsLoaded: Boolean;

implementation

uses
  SysUtils, Led.Core.Paths
  {$IFDEF WINDOWS}, Windows{$ENDIF}
  {$IFDEF DARWIN}, MacOSAll{$ENDIF};

{$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}
function FcInit: LongBool; cdecl; external 'fontconfig';
function FcConfigAppFontAddFile(AConfig: Pointer; AFile: PChar): LongBool;
  cdecl; external 'fontconfig';
{$ENDIF}

var
  GLoaded: Boolean = False;
  GTried: Boolean = False;

function LedBundledFontsLoaded: Boolean;
begin
  Result := GLoaded;
end;

{ One file.  True when the platform took it. }
function AddOne(const AFileName: string): Boolean;
{$IFDEF DARWIN}
var
  URL: CFURLRef;
  Path: CFStringRef;
{$ENDIF}
begin
  Result := False;
  if not FileExists(AFileName) then Exit;

  {$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}
  Result := FcConfigAppFontAddFile(nil, PChar(AFileName));
  {$ELSEIF DEFINED(WINDOWS)}
  { FR_PRIVATE: visible to this process and gone when it exits, so led never
    touches the machine's installed fonts.  No WM_FONTCHANGE broadcast for the
    same reason -- there is nobody else to tell. }
  Result := AddFontResourceEx(PChar(AFileName), FR_PRIVATE, nil) > 0;
  {$ELSEIF DEFINED(DARWIN)}
  Path := CFStringCreateWithCString(nil, PChar(AFileName),
    kCFStringEncodingUTF8);
  try
    URL := CFURLCreateWithFileSystemPath(nil, Path,
      kCFURLPOSIXPathStyle, False);
    if URL = nil then Exit;
    try
      Result := CTFontManagerRegisterFontsForURL(URL,
        kCTFontManagerScopeProcess, nil);
    finally
      CFRelease(URL);
    end;
  finally
    CFRelease(Path);
  end;
  {$IFEND}
end;

procedure LedLoadBundledFonts;
var
  Dir: string;
begin
  if GTried then Exit;
  GTried := True;

  {$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}
  { Without this the first AddFile can land before fontconfig has read any
    configuration, and the font is added to a config that is then replaced. }
  FcInit;
  {$ENDIF}

  Dir := LedDataDir;
  if Dir = '' then Exit;
  Dir := IncludeTrailingPathDelimiter(Dir) + 'fonts' + PathDelim;

  { Both or neither is not required: a bold that failed to load is a
    synthesised bold, which is worse than the regular being missing too. }
  GLoaded := AddOne(Dir + 'FiraCode-Regular.ttf');
  if GLoaded then
    AddOne(Dir + 'FiraCode-Bold.ttf');
end;

initialization
  LedLoadBundledFonts;

end.
