{ led - a light editor.  Pseudo-terminal.

  There is no PTY binding anywhere in FPC's RTL, so this is written against
  the syscalls: posix_openpt, grantpt, unlockpt, ptsname to get the pair, then
  fork and setsid so the child gets a controlling terminal.

  A pipe is not a substitute.  A shell checks isatty() and behaves quite
  differently when it is false: no job control, no prompt, no line editing.
  That is why medit linked libvte rather than reading a pipe, and why this
  exists.

  Windows needs ConPTY, which is a different mechanism entirely; the unit
  compiles there but reports that it is unavailable rather than pretending. }
unit Led.Term.Pty;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils
  {$IFDEF UNIX}, BaseUnix, termio, Unix{$ENDIF};

type
  TLedPty = class
  private
    FMaster: cint;
    FChildPid: TPid;
    FRunning: Boolean;
    FSlaveName: string;
    FCols, FRows: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    { Starts ACommand (a shell if empty) on a new pseudo-terminal.  Returns
      False, with no side effects, when a PTY cannot be had. }
    function Spawn(const ACommand, AWorkDir: string;
      ACols, ARows: Integer): Boolean;

    { Bytes waiting from the child, up to ACount.  Returns 0 when there is
      nothing right now; -1 when the child has gone. }
    function Read(var ABuffer; ACount: Integer): Integer;
    function Write(const ABuffer; ACount: Integer): Integer;
    procedure WriteString(const AText: string);

    { Tells the child its window changed.  Without this, full-screen programs
      draw at the wrong size after every resize. }
    procedure SetSize(ACols, ARows: Integer);

    procedure Terminate;
    function ChildExited: Boolean;

    property Running: Boolean read FRunning;
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
  end;

function LedPtyAvailable: Boolean;
function LedDefaultShell: string;

implementation

{$IFDEF UNIX}
const
  TIOCSWINSZ_ = {$IFDEF LINUX}$5414{$ELSE}$80087467{$ENDIF};

type
  TWinSize = record
    ws_row, ws_col, ws_xpixel, ws_ypixel: cushort;
  end;

function posix_openpt(oflag: cint): cint; cdecl; external 'c';
function grantpt(fd: cint): cint; cdecl; external 'c';
function unlockpt(fd: cint): cint; cdecl; external 'c';
function ptsname(fd: cint): PChar; cdecl; external 'c';
function setsid_: TPid; cdecl; external 'c' name 'setsid';
function ioctl_(fd: cint; request: culong; argp: Pointer): cint; cdecl;
  external 'c' name 'ioctl';
function setenv_(name, value: PChar; overwrite: cint): cint; cdecl;
  external 'c' name 'setenv';
function unsetenv_(name: PChar): cint; cdecl; external 'c' name 'unsetenv';
{$ENDIF}

function LedPtyAvailable: Boolean;
begin
  {$IFDEF UNIX}
  Result := True;
  {$ELSE}
  { ConPTY is a different mechanism and is not implemented yet.  Saying so is
    better than opening a window that never prints anything. }
  Result := False;
  {$ENDIF}
end;

function LedDefaultShell: string;
begin
  {$IFDEF UNIX}
  Result := GetEnvironmentVariable('SHELL');
  if Result = '' then Result := '/bin/sh';
  {$ELSE}
  Result := GetEnvironmentVariable('COMSPEC');
  if Result = '' then Result := 'cmd.exe';
  {$ENDIF}
end;

constructor TLedPty.Create;
begin
  inherited Create;
  {$IFDEF UNIX}
  FMaster := -1;
  {$ENDIF}
  FCols := 80;
  FRows := 24;
end;

destructor TLedPty.Destroy;
begin
  Terminate;
  inherited Destroy;
end;

{$IFDEF UNIX}
function TLedPty.Spawn(const ACommand, AWorkDir: string;
  ACols, ARows: Integer): Boolean;
var
  Slave: cint;
  Pid: TPid;
  Cmd: string;
  Args: array[0..2] of PChar;
  Flags: cint;
begin
  Result := False;
  if FRunning then Exit;

  FMaster := posix_openpt(O_RDWR or O_NOCTTY);
  if FMaster < 0 then Exit;
  if (grantpt(FMaster) <> 0) or (unlockpt(FMaster) <> 0) then
  begin
    FpClose(FMaster);
    FMaster := -1;
    Exit;
  end;
  FSlaveName := StrPas(ptsname(FMaster));

  FCols := ACols;
  FRows := ARows;

  Cmd := ACommand;
  if Cmd = '' then Cmd := LedDefaultShell;

  Pid := FpFork;
  if Pid < 0 then
  begin
    FpClose(FMaster);
    FMaster := -1;
    Exit;
  end;

  if Pid = 0 then
  begin
    { Child.  A new session, then opening the slave makes it the controlling
      terminal -- which is the whole point, and what a pipe cannot give. }
    setsid_;
    Slave := FpOpen(FSlaveName, O_RDWR);
    if Slave < 0 then FpExit(127);

    FpDup2(Slave, 0);
    FpDup2(Slave, 1);
    FpDup2(Slave, 2);
    if Slave > 2 then FpClose(Slave);
    FpClose(FMaster);

    if (AWorkDir <> '') and DirectoryExists(AWorkDir) then
      FpChdir(AWorkDir);

    { Programs consult TERM to decide what they may emit.  Claiming
      xterm-256color and then not understanding it would be worse than
      claiming less. }
    unsetenv_('LINES');
    unsetenv_('COLUMNS');
    setenv_('TERM', 'xterm', 1);

    Args[0] := PChar(Cmd);
    Args[1] := nil;
    Args[2] := nil;
    FpExecv(PChar(Cmd), @Args[0]);
    FpExit(127);
  end;

  FChildPid := Pid;
  FRunning := True;

  { Non-blocking, because the reader runs on the UI timer and must never
    wait for a child that has nothing to say. }
  Flags := FpFcntl(FMaster, F_GetFl, 0);
  FpFcntl(FMaster, F_SetFl, Flags or O_NONBLOCK);

  SetSize(ACols, ARows);
  Result := True;
end;

function TLedPty.Read(var ABuffer; ACount: Integer): Integer;
begin
  Result := 0;
  if not FRunning then Exit(-1);
  Result := FpRead(FMaster, ABuffer, ACount);
  if Result < 0 then
  begin
    { EAGAIN just means "nothing yet"; anything else means the child is gone. }
    if fpgeterrno = ESysEAGAIN then
      Result := 0
    else
    begin
      FRunning := False;
      Result := -1;
    end;
  end
  else if Result = 0 then
  begin
    FRunning := False;
    Result := -1;
  end;
end;

function TLedPty.Write(const ABuffer; ACount: Integer): Integer;
begin
  Result := 0;
  if not FRunning then Exit;
  Result := FpWrite(FMaster, ABuffer, ACount);
end;

procedure TLedPty.SetSize(ACols, ARows: Integer);
var
  WS: TWinSize;
begin
  if ACols < 1 then ACols := 1;
  if ARows < 1 then ARows := 1;
  FCols := ACols;
  FRows := ARows;
  if not FRunning then Exit;
  WS.ws_row := ARows;
  WS.ws_col := ACols;
  WS.ws_xpixel := 0;
  WS.ws_ypixel := 0;
  ioctl_(FMaster, TIOCSWINSZ_, @WS);
  { The child is told through SIGWINCH, which the kernel raises for us. }
end;

procedure TLedPty.Terminate;
var
  Status: cint;
begin
  if FRunning and (FChildPid > 0) then
  begin
    FpKill(FChildPid, SIGHUP);
    FpWaitPid(FChildPid, Status, WNOHANG);
  end;
  if FMaster >= 0 then
  begin
    FpClose(FMaster);
    FMaster := -1;
  end;
  FRunning := False;
end;

function TLedPty.ChildExited: Boolean;
var
  Status: cint;
begin
  Result := not FRunning;
  if not FRunning then Exit;
  if FpWaitPid(FChildPid, Status, WNOHANG) = FChildPid then
  begin
    FRunning := False;
    Result := True;
  end;
end;

{$ELSE}

function TLedPty.Spawn(const ACommand, AWorkDir: string;
  ACols, ARows: Integer): Boolean;
begin
  Result := False;
end;

function TLedPty.Read(var ABuffer; ACount: Integer): Integer;
begin
  Result := -1;
end;

function TLedPty.Write(const ABuffer; ACount: Integer): Integer;
begin
  Result := 0;
end;

procedure TLedPty.SetSize(ACols, ARows: Integer);
begin
  FCols := ACols;
  FRows := ARows;
end;

procedure TLedPty.Terminate;
begin
  FRunning := False;
end;

function TLedPty.ChildExited: Boolean;
begin
  Result := True;
end;

{$ENDIF}

procedure TLedPty.WriteString(const AText: string);
begin
  if AText <> '' then
    Write(AText[1], Length(AText));
end;

end.
