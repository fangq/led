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
  { The sentence under the name in About.  A tagline says what a program is
    called; this says what it is. }
  LedDefaultAppAbout   = 'A fast, no-nonsense editor for code and text, '
                       + 'with its own highlighting, panes and debugger.';

{ And what the MATLAB-language fork calls itself.

  **Mima is the name; `mima` is the command.**  Written with the capital
  everywhere a reader sees it -- the title bar, the About box, a dialog, the
  documentation -- and lower-case only where it is being typed or executed:
  the binary, the configuration directory, `mima --version`, MIMA_RUN.  The
  two are not interchangeable and the lower-case form had leaked into places
  that are prose.

  Three projects, one family:
    Mima     (`mima`)     -- this program, the IDE: Mighty Matrix
    Mimagen  (`mima-cli`, `mimac`, libmima) -- the engine it runs:
                            Mighty Matrix Engine
    Mimamo   (`mimamo`)   -- the C++17 library the engine computes and draws
                            with: Mighty Matrix Module }
const
  MimaAppName    = 'Mima';
  MimaAppTagline = 'Mighty Matrix';
  MimaAppTitle   = 'Mima - Mighty Matrix';
  MimaAppId      = 'mima';
  { Where this fork's source is, which is not where the editor's is.  Shown
    in About and in a bug report. }
  MimaAppHome    = 'https://github.com/fangq/mima';
  { Mima's own version, which is not the editor's it was forked from. }
  MimaVersion    = '0.1.0';

  { What this is: an implementation of the MATLAB *language*, in one line a
    greeting has room for. }
  { Short enough to fit the pane it is printed in: the command window is
    about seventy columns at its default size, and a greeting whose third
    line runs off the right-hand edge is a poor first impression. }
  MimaAppAbout   = 'An IDE for the MATLAB language, running Mimagen '
                 + 'over Mimamo.';

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
{ Where the source is.  Shown in About and in a bug report, so a reader who
  has one of those in front of them has somewhere to send it. }
function LedAppHome: string;
{ What this program is, in a sentence: the subtitle in About. }
function LedAppAbout: string;
{ The version this program reports -- LedVersion for the editor, the fork's
  own for a fork, which is not the editor's: Mima announced itself as LED's
  0.5.0-dev. }
function LedAppVersion: string;
procedure LedSetAppIdentity(const AName, ATagline: string;
  const AHome: string = ''; const AAbout: string = '';
  const AVersion: string = '');

{ Which LCL backend this binary was built against -- gtk2, qt5, win32, cocoa.
  Worth quoting in a bug report, because most of what goes wrong in a GUI
  goes wrong in exactly one of them. }
function LedWidgetSetName: string;

implementation

var
  FAppName: string = LedDefaultAppName;
  FAppTagline: string = LedDefaultAppTagline;
  FAppHome: string = 'https://github.com/fangq/led';
  FAppAbout: string = LedDefaultAppAbout;
  FAppVersion: string = LedVersion;

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

function LedAppHome: string;
begin
  Result := FAppHome;
end;

function LedAppAbout: string;
begin
  Result := FAppAbout;
end;

function LedAppVersion: string;
begin
  Result := FAppVersion;
end;

procedure LedSetAppIdentity(const AName, ATagline: string;
  const AHome: string = ''; const AAbout: string = '';
  const AVersion: string = '');
begin
  if AVersion <> '' then FAppVersion := AVersion;
  if AName <> '' then FAppName := AName;
  if ATagline <> '' then FAppTagline := ATagline;
  if AHome <> '' then FAppHome := AHome;
  if AAbout <> '' then FAppAbout := AAbout;
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
