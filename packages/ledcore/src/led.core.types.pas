{ led - a light editor.  Core type definitions.

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
  LedVersion = '2.0.0-dev';

{ Which LCL backend this binary was built against -- gtk2, qt5, win32, cocoa.
  Worth quoting in a bug report, because most of what goes wrong in a GUI
  goes wrong in exactly one of them. }
function LedWidgetSetName: string;

implementation

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
