{ LED - a lightweight editor.  Where the time goes on the way up.

  LED_STARTUP_TRACE=1 prints, on stderr, how long after the process began
  each milestone of the start was reached and how long the step before it
  took; LED_STARTUP_TRACE=quit also closes the window once it is up and the
  first idle has come, so a start can be timed from a script.  Unset, each
  call is one test of a Boolean. }
unit Led.Core.StartTrace;

{$mode objfpc}{$H+}

interface

var
  LedStartTraceOn: Boolean = False;
  LedStartTraceQuit: Boolean = False;

{ a milestone, by name }
procedure LedStartTrace(const AWhat: string);

implementation

uses
  SysUtils {$IFDEF UNIX}, BaseUnix, Unix{$ENDIF};

var
  T0, TLast: QWord;

function NowUs: QWord;
{$IFDEF UNIX}
var
  Tv: TTimeVal;
begin
  fpgettimeofday(@Tv, nil);
  Result := QWord(Tv.tv_sec) * 1000000 + QWord(Tv.tv_usec);
end;
{$ELSE}
begin
  Result := GetTickCount64 * 1000;
end;
{$ENDIF}

procedure LedStartTrace(const AWhat: string);
var
  T: QWord;
begin
  if not LedStartTraceOn then
    Exit;
  T := NowUs;
  WriteLn(StdErr, Format('[start] %8.1f ms  +%7.1f  %s', [(T - T0) / 1000, (T - TLast) / 1000, AWhat]));
  TLast := T;
end;

var
  E: string;

initialization
  T0 := NowUs;
  TLast := T0;
  E := LowerCase(GetEnvironmentVariable('LED_STARTUP_TRACE'));
  LedStartTraceOn := (E <> '') and (E <> '0');
  LedStartTraceQuit := E = 'quit';
end.
