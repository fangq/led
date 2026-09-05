{ led - a light editor.  Surviving an X error that nothing can act on.

  Over ssh X forwarding the X server is on the machine in front of you and
  the client is on the far one.  ssh forwards the extension list unchanged,
  so MIT-SHM is advertised and GDK offers the server a shared-memory segment
  -- one that lives on a different machine, which the server cannot possibly
  attach to.  It answers BadAccess:

    The error was 'BadAccess (attempt to access private resource denied)'.
    (Details: serial 2915 error_code 10 request_code 129 minor_code 1)

  where request_code is MIT-SHM's major opcode -- assigned by the server, so
  it is 129 on one machine and 130 on the next -- and minor_code 1 is
  X_ShmAttach.  GTK's default handler prints that paragraph and calls exit(),
  and an editor holding unsaved buffers dies of a failure its own libraries
  already know how to work around: every one of them falls back to ordinary
  images when shm is refused.

  So MIT-SHM errors are swallowed here, and nothing else is.  This is a last
  resort by construction: a library that wraps its own request in
  gdk_error_trap_push installs its own handler for the duration, so anything
  reaching this one has escaped every trap that was meant to catch it.
  Everything that is not MIT-SHM goes on to the handler GTK installed, which
  still aborts -- a protocol error in led's own drawing should stay loud.

  The opcode is looked up once, at install time, on a connection of this
  unit's own: extension opcodes are a property of the server rather than of
  the connection, and asking for it inside the error handler would mean
  making a protocol request from a place Xlib does not allow one. }
unit Led.UI.XError;

{$mode objfpc}{$H+}

{ X11 only, and only where the widgetset is one that talks to it.  Everywhere
  else the unit compiles to a pair of stubs so the callers need no ifdef. }
{$IF DEFINED(UNIX) and not DEFINED(DARWIN) and (DEFINED(LCLGtk2) or DEFINED(LCLGtk3) or DEFINED(LCLQt) or DEFINED(LCLQt5) or DEFINED(LCLQt6))}
  {$DEFINE LED_X11}
{$ENDIF}

interface

{ Installs the handler.  Call once, after Application.Initialize, so it
  replaces the one GTK put in rather than being replaced by it.  Does nothing
  when there is no display, or on a platform with no X. }
procedure LedInstallXErrorHandler;

{ How many errors have been ignored.  Zero on a healthy display; non-zero
  says shared memory was refused and the session is drawing the slow way,
  which is worth knowing when someone reports that led feels sluggish over
  ssh. }
function LedXErrorsIgnored: Integer;

{ The MIT-SHM major opcode this server assigned, or -1 when it was not asked
  for or the extension is absent.  Public for the self-test, which has to
  provoke the real error to check that it is survived. }
function LedXShmOpcode: Integer;

implementation

{$IFDEF LED_X11}
uses
  ctypes, x, xlib;

var
  FPrev: TXErrorHandler = nil;
  FShmOpcode: cint = -1;
  FIgnored: Integer = 0;
  FInstalled: Boolean = False;

function LedXErrorHandler(ADisplay: PDisplay; AEvent: PXErrorEvent): cint; cdecl;
begin
  Result := 0;
  if AEvent = nil then Exit;

  if (FShmOpcode > 0) and (AEvent^.request_code = FShmOpcode) then
  begin
    Inc(FIgnored);
    { Said once.  A broken display refuses every segment, and one line per
      refusal would be the whole session. }
    if FIgnored = 1 then
      WriteLn(StdErr, 'led: the X server refused shared memory ' +
        '(MIT-SHM), which is what happens over ssh X forwarding; ' +
        'drawing without it');
    Exit;
  end;

  if Assigned(FPrev) then Result := FPrev(ADisplay, AEvent);
end;

procedure LedInstallXErrorHandler;
var
  D: PDisplay;
  Major, FirstEvent, FirstError: cint;
begin
  if FInstalled then Exit;

  { A connection of this unit's own, opened and closed here.  The opcode is
    the server's, not the connection's, so GTK's display would give the same
    answer -- and reaching for it would mean depending on the widgetset. }
  D := XOpenDisplay(nil);
  if D = nil then Exit;
  try
    if XQueryExtension(D, 'MIT-SHM', @Major, @FirstEvent, @FirstError) then
      FShmOpcode := Major;
  finally
    XCloseDisplay(D);
  end;

  if FShmOpcode <= 0 then Exit;   { nothing to ignore; leave GTK's handler }

  FPrev := XSetErrorHandler(@LedXErrorHandler);
  FInstalled := True;
end;

function LedXErrorsIgnored: Integer;
begin
  Result := FIgnored;
end;

function LedXShmOpcode: Integer;
begin
  Result := FShmOpcode;
end;

{$ELSE}

procedure LedInstallXErrorHandler;
begin
end;

function LedXErrorsIgnored: Integer;
begin
  Result := 0;
end;

function LedXShmOpcode: Integer;
begin
  Result := -1;
end;

{$ENDIF}

end.
