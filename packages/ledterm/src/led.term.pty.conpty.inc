{ led - a light editor.  The Windows half of Led.Term.Pty: ConPTY.

  Included from led.term.pty.pas under {$IFDEF WINDOWS}.  A separate file
  because it cannot be compiled on the machine it was written on -- there is
  no Windows cross-toolchain here -- and keeping it apart makes it possible
  to type-check against a mirror of the RTL's Win32 declarations.

  ConPTY is nothing like a Unix pty.  CreatePseudoConsole hands you two
  ordinary anonymous pipes and starts a headless conhost that owns the real
  console; the child attaches to it through a process-thread attribute rather
  than by inheriting a terminal.  Two consequences run through everything
  below:

    * What arrives on the pipe is conhost's *repaint* of a screen, not the
      child's byte stream.  Expect absolute cursor positioning and erases
      where a Unix pty would send plain text.  Led.Term.Screen already
      handles those, which is why nothing above this file changes.

    * conhost keeps no history of its own -- the buffer is exactly the rows
      asked for -- so anything scrolled away is only preserved if it left as
      a line feed.  Windows scrollback is therefore best-effort, and that is
      a property of ConPTY rather than something to fix here.

  Every function is resolved with GetProcAddress and never imported.  A PE
  import of CreatePseudoConsole is bound by the loader before any code runs,
  so a statically-linked build would fail to *start* on Windows 7, 8, or any
  Windows 10 before 1809 -- taking the whole editor down, not just the
  terminal -- with "the procedure entry point could not be located".  Bound
  this way, an old Windows simply reports the terminal unavailable, which is
  what the pane already knows how to show. }

const
  { ProcThreadAttributePseudoConsole(22) or PROC_THREAD_ATTRIBUTE_INPUT. }
  PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = $00020016;
  PSEUDOCONSOLE_INHERIT_CURSOR        = 1;

type
  HPCON = THandle;
  PPROC_THREAD_ATTRIBUTE_LIST = Pointer;

  { STARTUPINFOW followed by the attribute list.  cb must be the size of
    *this* record, not of the STARTUPINFOW inside it. }
  TStartupInfoExW = record
    StartupInfo: TStartupInfoW;
    lpAttributeList: PPROC_THREAD_ATTRIBUTE_LIST;
  end;

  TCreatePseudoConsole = function(size: TCoord; hInput, hOutput: THandle;
    dwFlags: DWORD; out phPC: HPCON): HRESULT; stdcall;
  TResizePseudoConsole = function(hPC: HPCON; size: TCoord): HRESULT; stdcall;
  TClosePseudoConsole = procedure(hPC: HPCON); stdcall;
  TInitializeProcThreadAttributeList = function(
    lpAttributeList: PPROC_THREAD_ATTRIBUTE_LIST; dwAttributeCount: DWORD;
    dwFlags: DWORD; var lpSize: SIZE_T): BOOL; stdcall;
  TUpdateProcThreadAttribute = function(
    lpAttributeList: PPROC_THREAD_ATTRIBUTE_LIST; dwFlags: DWORD;
    Attribute: DWORD_PTR; lpValue: Pointer; cbSize: SIZE_T;
    lpPreviousValue: Pointer; lpReturnSize: Pointer): BOOL; stdcall;
  TDeleteProcThreadAttributeList = procedure(
    lpAttributeList: PPROC_THREAD_ATTRIBUTE_LIST); stdcall;

var
  _CreatePseudoConsole: TCreatePseudoConsole = nil;
  _ResizePseudoConsole: TResizePseudoConsole = nil;
  _ClosePseudoConsole: TClosePseudoConsole = nil;
  _InitializeProcThreadAttributeList: TInitializeProcThreadAttributeList = nil;
  _UpdateProcThreadAttribute: TUpdateProcThreadAttribute = nil;
  _DeleteProcThreadAttributeList: TDeleteProcThreadAttributeList = nil;
  FConPtyProbed: Boolean = False;
  FConPtyOk: Boolean = False;

{ Resolves the six entry points once.  Failure is not an error: it means this
  Windows predates 1809 and the terminal is unavailable. }
function ConPtyLoad: Boolean;
var
  Lib: HMODULE;
begin
  if FConPtyProbed then Exit(FConPtyOk);
  FConPtyProbed := True;
  FConPtyOk := False;

  { PChar, not a bare literal: GetModuleHandle has both an A and a W
    overload and a string literal is ambiguous between them. }
  Lib := GetModuleHandle(PChar('kernel32.dll'));
  if Lib = 0 then Exit(False);

  Pointer(_CreatePseudoConsole) := GetProcAddress(Lib, 'CreatePseudoConsole');
  Pointer(_ResizePseudoConsole) := GetProcAddress(Lib, 'ResizePseudoConsole');
  Pointer(_ClosePseudoConsole) := GetProcAddress(Lib, 'ClosePseudoConsole');
  Pointer(_InitializeProcThreadAttributeList) :=
    GetProcAddress(Lib, 'InitializeProcThreadAttributeList');
  Pointer(_UpdateProcThreadAttribute) :=
    GetProcAddress(Lib, 'UpdateProcThreadAttribute');
  Pointer(_DeleteProcThreadAttributeList) :=
    GetProcAddress(Lib, 'DeleteProcThreadAttributeList');

  FConPtyOk := (_CreatePseudoConsole <> nil) and
               (_ResizePseudoConsole <> nil) and
               (_ClosePseudoConsole <> nil) and
               (_InitializeProcThreadAttributeList <> nil) and
               (_UpdateProcThreadAttribute <> nil) and
               (_DeleteProcThreadAttributeList <> nil);
  Result := FConPtyOk;
end;

{ The shell to start when the caller named no command.

  SysUtils. is not decoration.  The Windows unit exports a three-argument
  GetEnvironmentVariable(PChar; PChar; DWORD): DWORD, and it is in scope here
  because the enclosing unit uses Windows -- so the unqualified one-argument
  call that works everywhere else resolves to that instead and the build fails
  with "wrong number of parameters".  Which is exactly what it did. }
function ConPtyDefaultShell: string;
begin
  Result := SysUtils.GetEnvironmentVariable('COMSPEC');
  if Result = '' then Result := 'cmd.exe';
end;

function TLedPty.Spawn(const ACommand, AWorkDir: string;
  ACols, ARows: Integer): Boolean;
var
  Size: TCoord;
  InRead, OutWrite: THandle;
  SIEx: TStartupInfoExW;
  PI: TProcessInformation;
  ListSize: SIZE_T;
  Cmd, Dir: WideString;
  DirPtr: PWideChar;
  Ok: Boolean;
begin
  Result := False;
  if FRunning then Exit;
  if not ConPtyLoad then Exit;
  if ACols < 1 then ACols := 80;
  if ARows < 1 then ARows := 24;

  InRead := 0; OutWrite := 0;
  FInWrite := 0; FOutRead := 0; FPC := 0;
  SIEx := Default(TStartupInfoExW);
  PI := Default(TProcessInformation);

  { Two pipes, crossed: conhost reads what we write and writes what we read. }
  if not CreatePipe(InRead, FInWrite, nil, 0) then Exit;
  if not CreatePipe(FOutRead, OutWrite, nil, 0) then
  begin
    CloseHandle(InRead); CloseHandle(FInWrite);
    FInWrite := 0;
    Exit;
  end;

  Size.X := ACols;
  Size.Y := ARows;
  if _CreatePseudoConsole(Size, InRead, OutWrite, 0, FPC) <> S_OK then
  begin
    CloseHandle(InRead); CloseHandle(OutWrite);
    CloseHandle(FInWrite); CloseHandle(FOutRead);
    FInWrite := 0; FOutRead := 0;
    Exit;
  end;

  { CreatePseudoConsole duplicates what it needs; our ends of the child's
    side are dead weight and must go, or the pipe never reports EOF. }
  CloseHandle(InRead);
  CloseHandle(OutWrite);

  { The attribute list is sized by the first call, which is expected to fail
    with ERROR_INSUFFICIENT_BUFFER. }
  ListSize := 0;
  _InitializeProcThreadAttributeList(nil, 1, 0, ListSize);
  if ListSize = 0 then
  begin
    ConPtyCleanup;
    Exit;
  end;
  SIEx.lpAttributeList := GetMem(ListSize);
  if SIEx.lpAttributeList = nil then
  begin
    ConPtyCleanup;
    Exit;
  end;

  Ok := _InitializeProcThreadAttributeList(SIEx.lpAttributeList, 1, 0, ListSize);
  if Ok then
    Ok := _UpdateProcThreadAttribute(SIEx.lpAttributeList, 0,
      PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, Pointer(FPC), SizeOf(HPCON),
      nil, nil);
  if not Ok then
  begin
    FreeMem(SIEx.lpAttributeList);
    ConPtyCleanup;
    Exit;
  end;

  SIEx.StartupInfo.cb := SizeOf(TStartupInfoExW);

  if ACommand <> '' then Cmd := UTF8Decode(ACommand)
  else Cmd := UTF8Decode(ConPtyDefaultShell);
  { CreateProcessW may write to the command line buffer, so it cannot be a
    literal or a shared string. }
  UniqueString(Cmd);

  Dir := UTF8Decode(AWorkDir);
  if Dir <> '' then DirPtr := PWideChar(Dir) else DirPtr := nil;

  { bInheritHandles must be False: the child reaches the console through the
    attribute above, and inheriting our pipe ends would keep them open in the
    child and stop EOF ever arriving. }
  Ok := CreateProcessW(nil, PWideChar(Cmd), nil, nil, False,
    EXTENDED_STARTUPINFO_PRESENT or CREATE_UNICODE_ENVIRONMENT,
    nil, DirPtr, SIEx.StartupInfo, PI);

  _DeleteProcThreadAttributeList(SIEx.lpAttributeList);
  FreeMem(SIEx.lpAttributeList);

  if not Ok then
  begin
    ConPtyCleanup;
    Exit;
  end;

  CloseHandle(PI.hThread);
  FChildProc := PI.hProcess;
  FChildPid := PI.dwProcessId;
  FCols := ACols;
  FRows := ARows;
  FRunning := True;
  Result := True;
end;

{ Closes whatever of the pseudoconsole was built.  Safe to call at any point
  in Spawn's failure ladder, and again from Terminate. }
procedure TLedPty.ConPtyCleanup;
begin
  if FPC <> 0 then
  begin
    if _ClosePseudoConsole <> nil then _ClosePseudoConsole(FPC);
    FPC := 0;
  end;
  if FInWrite <> 0 then begin CloseHandle(FInWrite); FInWrite := 0; end;
  if FOutRead <> 0 then begin CloseHandle(FOutRead); FOutRead := 0; end;
  if FChildProc <> 0 then begin CloseHandle(FChildProc); FChildProc := 0; end;
end;

function TLedPty.Read(var ABuffer; ACount: Integer): Integer;
var
  Avail, Got: DWORD;
begin
  Result := -1;
  if (not FRunning) or (FOutRead = 0) then Exit;

  { The pipes are anonymous, so they cannot do overlapped I/O and a plain
    ReadFile would block until the child says something.  Peeking first is
    what keeps the poll in the view non-blocking. }
  Avail := 0;
  if not PeekNamedPipe(FOutRead, nil, 0, nil, @Avail, nil) then
  begin
    { The pipe is gone, which means conhost has. }
    FRunning := False;
    Exit(-1);
  end;
  if Avail = 0 then Exit(0);
  if Avail > DWORD(ACount) then Avail := ACount;

  Got := 0;
  if not ReadFile(FOutRead, ABuffer, Avail, Got, nil) then
  begin
    FRunning := False;
    Exit(-1);
  end;
  Result := Got;
end;

function TLedPty.Write(const ABuffer; ACount: Integer): Integer;
var
  Written: DWORD;
begin
  Result := 0;
  if (not FRunning) or (FInWrite = 0) or (ACount <= 0) then Exit;
  Written := 0;
  if not WriteFile(FInWrite, ABuffer, DWORD(ACount), Written, nil) then
    Exit(0);
  Result := Written;
end;

procedure TLedPty.SetSize(ACols, ARows: Integer);
var
  Size: TCoord;
begin
  if ACols < 1 then ACols := 1;
  if ARows < 1 then ARows := 1;
  if (ACols = FCols) and (ARows = FRows) then Exit;
  FCols := ACols;
  FRows := ARows;
  if (FPC <> 0) and (_ResizePseudoConsole <> nil) then
  begin
    Size.X := ACols;
    Size.Y := ARows;
    _ResizePseudoConsole(FPC, Size);
  end;
end;

procedure TLedPty.Terminate;
begin
  if FChildProc <> 0 then
    TerminateProcess(FChildProc, 0);
  ConPtyCleanup;
  FRunning := False;
end;

function TLedPty.ChildExited: Boolean;
begin
  Result := True;
  if not FRunning then Exit;
  if FChildProc = 0 then Exit;
  if WaitForSingleObject(FChildProc, 0) = WAIT_OBJECT_0 then
  begin
    FRunning := False;
    Exit(True);
  end;
  Result := False;
end;
