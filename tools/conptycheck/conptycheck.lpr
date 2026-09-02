{ Type-checks led.term.pty.conpty.inc on Linux.

  There is no Windows cross-toolchain on this machine, so CI would otherwise
  be the first compiler ever to see that file.  This mirrors the Win32
  surface it uses, copied signature-for-signature out of FPC 3.2.2's
  rtl/win/wininc, and includes the real source.  It cannot prove the code is
  correct against Windows, but it catches every typo, arity mistake and type
  error before a push. }
program conptycheck;

{$mode objfpc}{$H+}

uses SysUtils;

type
  DWORD      = LongWord;
  UINT       = LongWord;
  BOOL       = LongBool;
  HMODULE    = PtrUInt;
  ULONG_PTR  = PtrUInt;
  DWORD_PTR  = ULONG_PTR;
  SIZE_T     = ULONG_PTR;
  SHORT      = SmallInt;
  FARPROC    = Pointer;
  LPVOID     = Pointer;
  LPDWORD    = ^DWORD;
  LPWSTR     = PWideChar;
  PSecurityAttributes = Pointer;
  POverlapped = Pointer;

  TCoord = record X, Y: SHORT; end;

  TStartupInfoW = record
    cb: DWORD;
    lpReserved, lpDesktop, lpTitle: LPWSTR;
    dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars,
    dwFillAttribute, dwFlags: DWORD;
    wShowWindow, cbReserved2: Word;
    lpReserved2: PByte;
    hStdInput, hStdOutput, hStdError: THandle;
  end;

  TProcessInformation = record
    hProcess, hThread: THandle;
    dwProcessId, dwThreadId: DWORD;
  end;

const
  S_OK                          = HRESULT(0);
  WAIT_OBJECT_0                 = 0;
  EXTENDED_STARTUPINFO_PRESENT  = $00080000;
  CREATE_UNICODE_ENVIRONMENT    = $00000400;

{ Signatures copied from rtl/win/wininc/{func,redef}.inc. }
function GetModuleHandle(lpModuleName: PChar): HMODULE; forward;
function GetProcAddress(hModule: HMODULE; lpProcName: PChar): FARPROC; forward;
function CreatePipe(var hReadPipe, hWritePipe: THandle;
  lpPipeAttributes: PSecurityAttributes; nSize: DWORD): BOOL; forward;
function CloseHandle(hObject: THandle): BOOL; forward;
function PeekNamedPipe(hNamedPipe: THandle; lpBuffer: LPVOID;
  nBufferSize: DWORD; lpBytesRead: LPDWORD; lpTotalBytesAvail: LPDWORD;
  lpBytesLeftThisMessage: LPDWORD): BOOL; forward;
function ReadFile(hFile: THandle; var Buffer; nNumberOfBytesToRead: DWORD;
  var lpNumberOfBytesRead: DWORD; lpOverlapped: POverlapped): BOOL; forward;
function WriteFile(hFile: THandle; const Buffer;
  nNumberOfBytesToWrite: DWORD; var lpNumberOfBytesWritten: DWORD;
  lpOverlapped: POverlapped): BOOL; forward;
function CreateProcessW(lpApplicationName: LPWSTR; lpCommandLine: LPWSTR;
  lpProcessAttributes, lpThreadAttributes: PSecurityAttributes;
  bInheritHandles: BOOL; dwCreationFlags: DWORD; lpEnvironment: Pointer;
  lpCurrentDirectory: LPWSTR; const lpStartupInfo: TStartupInfoW;
  var lpProcessInformation: TProcessInformation): BOOL; forward;
function TerminateProcess(hProcess: THandle; uExitCode: UINT): BOOL; forward;
function WaitForSingleObject(hHandle: THandle; dwMilliseconds: DWORD): DWORD; forward;

type
  { The parts of TLedPty the include touches. }
  TLedPty = class
  private
    FRunning: Boolean;
    FCols, FRows: Integer;
    FChildPid: DWORD;
    FPC, FInWrite, FOutRead, FChildProc: THandle;
    procedure ConPtyCleanup;
  public
    function Spawn(const ACommand, AWorkDir: string; ACols, ARows: Integer): Boolean;
    function Read(var ABuffer; ACount: Integer): Integer;
    function Write(const ABuffer; ACount: Integer): Integer;
    procedure SetSize(ACols, ARows: Integer);
    procedure Terminate;
    function ChildExited: Boolean;
  end;

function LedDefaultShell: string; forward;

{$I led.term.pty.conpty.inc}

{ Stubs, never called; present only so the program links. }
function GetModuleHandle(lpModuleName: PChar): HMODULE; begin Result := 0; end;
function GetProcAddress(hModule: HMODULE; lpProcName: PChar): FARPROC; begin Result := nil; end;
function CreatePipe(var hReadPipe, hWritePipe: THandle; lpPipeAttributes: PSecurityAttributes; nSize: DWORD): BOOL; begin hReadPipe := 0; hWritePipe := 0; Result := False; end;
function CloseHandle(hObject: THandle): BOOL; begin Result := True; end;
function PeekNamedPipe(hNamedPipe: THandle; lpBuffer: LPVOID; nBufferSize: DWORD; lpBytesRead: LPDWORD; lpTotalBytesAvail: LPDWORD; lpBytesLeftThisMessage: LPDWORD): BOOL; begin Result := False; end;
function ReadFile(hFile: THandle; var Buffer; nNumberOfBytesToRead: DWORD; var lpNumberOfBytesRead: DWORD; lpOverlapped: POverlapped): BOOL; begin lpNumberOfBytesRead := 0; Result := False; end;
function WriteFile(hFile: THandle; const Buffer; nNumberOfBytesToWrite: DWORD; var lpNumberOfBytesWritten: DWORD; lpOverlapped: POverlapped): BOOL; begin lpNumberOfBytesWritten := 0; Result := False; end;
function CreateProcessW(lpApplicationName: LPWSTR; lpCommandLine: LPWSTR; lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: BOOL; dwCreationFlags: DWORD; lpEnvironment: Pointer; lpCurrentDirectory: LPWSTR; const lpStartupInfo: TStartupInfoW; var lpProcessInformation: TProcessInformation): BOOL; begin Result := False; end;
function TerminateProcess(hProcess: THandle; uExitCode: UINT): BOOL; begin Result := True; end;
function WaitForSingleObject(hHandle: THandle; dwMilliseconds: DWORD): DWORD; begin Result := 0; end;
function LedDefaultShell: string; begin Result := 'cmd.exe'; end;

begin
  WriteLn('conpty include type-checks');
end.
