{ LED - a lightweight editor.  Core type definitions.

  This unit is deliberately free of any LCL dependency so that it, and every
  other unit in the ledcore package, can be compiled and unit-tested with
  LCLWidgetType=nogui. }
unit Led.Core.Types;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { How a text file terminates its lines.  leMixed is recorded when a single
    file uses more than one convention; saving then normalises to the user's
    chosen default.  Mirrors medit's MooLineEndType. }
  TLedLineEnd = (leUnknown, leUnix, leWindows, leMac, leMixed);

  { Precedence of a per-document setting.  A write at source S is applied only
    if the target slot is unset or its current source is <= S.  Ported from
    mooeditconfig.cpp; the numeric values are kept so the ordering is explicit
    rather than incidental to declaration order. }
  TLedConfigSource = (
    lcsUser     = 0,    // global preferences
    lcsFile     = 10,   // modeline inside the document
    lcsFilename = 20,   // filename glob rule
    lcsLang     = 30,   // language default
    lcsAuto     = 40    // detected from the content
  );

const
  LedLineEndStr: array[TLedLineEnd] of string = ('', #10, #13#10, #13, '');

function LedLineEndName(ALineEnd: TLedLineEnd): string;
function LedNativeLineEnd: TLedLineEnd;

{ The version, in one place.  led.lpr prints it for --version, the About
  box shows it and the bug-report text quotes it. }
const
  LedVersion = '0.5.0-dev';

{ What the editor calls itself.  The name is upper-case because it is one --
  the pun the icon draws; the binary, the configuration directory and the
  documentation stay lower-case "led". }
const
  LedDefaultAppName    = 'LED';
  LedDefaultAppTagline = 'a lightweight editor';

{ And what the matlab-language fork calls itself.

  **Mima is the name; `mima` is the command.**  Written with the capital
  everywhere a reader sees it -- the title bar, the About box, a dialog, the
  documentation -- and lower-case only where it is being typed or executed:
  the binary, the configuration directory, `mima --version`, MIMA_RUN.  The
  two are not interchangeable and the lower-case form had leaked into places
  that are prose.

  Mighty Matrix, after mimamo, the matrix library the engine computes with. }
const
  MimaAppName    = 'Mima';
  MimaAppTagline = 'Mighty Matrix';
  MimaAppTitle   = 'Mima - Mighty Matrix';
  MimaAppId      = 'mima';

  { What this is: an implementation of the matlab *language*, in one line a
    greeting has room for. }
  { Short enough to fit the pane it is printed in: the command window is
    about seventy columns at its default size, and a greeting whose third
    line runs off the right-hand edge is a poor first impression. }
  MimaAppAbout   = 'An independent parser and runtime for the matlab '
                 + 'language, over mimamo.';

{ Whose it is.  In one place because the greeting, the About box and a bug
  report all quote it. }
const
  LedAppAuthor    = 'Qianqian Fang';
  LedAppContact   = 'q.fang at neu.edu';
  LedAppCopyright = '(C) 2026 ' + LedAppAuthor + ' <' + LedAppContact + '>';

{ ...and which of those this process is.  Read rather than spelled out,
  because the fork and the editor are one set of sources: the title bar, the
  About box, the message-box captions and the %a in a user's window-title
  format all went through a constant that said LED, so the IDE announced
  itself as the editor it was built from.

  The same shape as LedSetAppId in Led.Core.Paths, and set in the same
  breath: one call before anything reads it, rather than a literal edited out
  of every shared unit.  A fork that forgets the call is named LED, which is
  wrong but harmless -- there is no state here to get half-initialised. }
function LedAppName: string;
function LedAppTagline: string;
function LedAppTitle: string;
procedure LedSetAppIdentity(const AName, ATagline: string);

{ Which LCL backend this binary was built against -- gtk2, qt5, win32, cocoa.
  Worth quoting in a bug report, because most of what goes wrong in a GUI
  goes wrong in exactly one of them. }
function LedWidgetSetName: string;

implementation

var
  FAppName: string = LedDefaultAppName;
  FAppTagline: string = LedDefaultAppTagline;

function LedAppName: string;
begin
  Result := FAppName;
end;

function LedAppTagline: string;
begin
  Result := FAppTagline;
end;

function LedAppTitle: string;
begin
  Result := FAppName + ' - ' + FAppTagline;
end;

procedure LedSetAppIdentity(const AName, ATagline: string);
begin
  if AName <> '' then FAppName := AName;
  if ATagline <> '' then FAppTagline := ATagline;
end;

function LedLineEndName(ALineEnd: TLedLineEnd): string;
begin
  case ALineEnd of
    leUnix:    Result := 'LF';
    leWindows: Result := 'CRLF';
    leMac:     Result := 'CR';
    leMixed:   Result := 'Mixed';
  else
    Result := '?';
  end;
end;

function LedNativeLineEnd: TLedLineEnd;
begin
  {$IFDEF WINDOWS}
  Result := leWindows;
  {$ELSE}
  Result := leUnix;
  {$ENDIF}
end;

function LedWidgetSetName: string;
begin
  {$IF DEFINED(LCLGTK2)}     Result := 'gtk2';
  {$ELSEIF DEFINED(LCLGTK3)} Result := 'gtk3';
  {$ELSEIF DEFINED(LCLQT5)}  Result := 'qt5';
  {$ELSEIF DEFINED(LCLQT6)}  Result := 'qt6';
  {$ELSEIF DEFINED(LCLWIN32)}Result := 'win32';
  {$ELSEIF DEFINED(LCLCOCOA)}Result := 'cocoa';
  {$ELSEIF DEFINED(LCLNOGUI)}Result := 'nogui';
  {$ELSE}                    Result := 'unknown';
  {$IFEND}
end;

end.
