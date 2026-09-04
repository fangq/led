{ led - a light editor.  A gdb subprocess, driven over its machine interface.

  One session is one `gdb --interpreter=mi3` child.  It owns the pipe, tags
  every command with a token so replies can be matched to what asked for them,
  keeps the state machine, and hands finished answers to whoever is listening.
  It draws nothing.

  Why this is in ledcore, when the tool runner it resembles is not: the
  reading is driven by an explicit Poll rather than by a timer this unit
  owns.  The editor calls Poll from a TTimer; the headless suite calls it in a
  loop.  That one decision is what lets the whole session layer -- spawning,
  tokens, dispatch, breakpoints, stack, locals -- be tested against a real gdb
  with no window, which is where every interesting bug in it will be.

  Polling rather than waiting on the child, for the reason Led.UI.ToolRunner
  gives: the editor is driven by Application.ProcessMessages under the
  self-test rather than by Application.Run, and the async-process callbacks
  are not reliably serviced there.  A poll costs nothing and always works.

  Two quoting rules that are not interchangeable, both learned from medit's
  plugin and both easy to get backwards:

    * -file-exec-and-symbols and -environment-cd take an MI c-string, so a
      path is wrapped in double quotes with the usual escapes.  Shell quoting
      is wrong: gdb would take the quotes as part of the filename.

    * -break-insert takes its location *unquoted*, because gdb echoes it back
      in original-location= and a quoted location comes back quoted, so the
      breakpoint can never be matched to the line that asked for it. }
unit Led.Core.Gdb;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, Led.Core.GdbMI;

type
  TLedGdbState = (lgsIdle, lgsLoading, lgsReady, lgsRunning, lgsStopped,
                  lgsExited, lgsError);

  { What a reply is an answer to.  A token is matched to one of these rather
    than to a closure, because Pascal makes an array of records much easier to
    reason about than an array of anonymous methods -- and every request led
    makes is one of a fixed handful. }
  TLedGdbRequest = (lgrNone, lgrVersion, lgrBreakInsert, lgrBreakDelete,
                    lgrWatchInsert, lgrLocals, lgrFrames, lgrEval, lgrExec,
                    lgrVarCreate, lgrVarChildren);

  { A line breakpoint or one of the three kinds of watchpoint.

    One type rather than two lists, because gdb makes no distinction where it
    matters: they share a number space, -break-delete, -break-enable and
    -break-condition take any of them, and =breakpoint-created reports them
    all.  What differs is where they are shown -- a breakpoint has a line to
    draw a dot beside, a watchpoint has only an expression. }
  TLedGdbBreakKind = (lgbLine, lgbWatch, lgbReadWatch, lgbAccessWatch);

  TLedGdbBreakInfo = record
    Number: Integer;
    Kind: TLedGdbBreakKind;
    FileName: string;
    Line: Integer;
    Expression: string;   // what a watchpoint watches; '' for a line breakpoint
    Condition: string;
    Enabled: Boolean;
    HitCount: Integer;
    { True when this came from a full bkpt tuple -- the reply to
      -break-insert, or =breakpoint-created/-modified -- so every field is
      gdb's own answer.  False for the reply to -break-watch, which carries a
      number and an expression and nothing else: taking Condition, Enabled or
      HitCount from one of those would clear what is already known. }
    Complete: Boolean;
  end;

  TLedGdbLocal = record
    Name: string;
    TypeName: string;
    Value: string;
  end;
  TLedGdbLocals = array of TLedGdbLocal;

  TLedGdbFrame = record
    Level: Integer;
    Func: string;
    FileName: string;
    Line: Integer;
    Addr: string;
  end;
  TLedGdbFrames = array of TLedGdbFrame;

  { One child of a variable object: a struct field, an array element, or the
    pointee of a pointer.  VarObj is gdb's handle for it, which is what a
    further -var-list-children is asked about, so drilling in is recursive
    without led having to know anything about C types.

    An aggregate child arrives with no value at all under --simple-values --
    only leaves carry one -- so an empty Value means "expand me", not
    "failed". }
  TLedGdbVarChild = record
    VarObj: string;
    Expr: string;
    TypeName: string;
    Value: string;
    NumChild: Integer;
  end;
  TLedGdbVarChildren = array of TLedGdbVarChild;

  TLedGdbTextEvent = procedure(Sender: TObject; const AText: string) of object;
  TLedGdbStopEvent = procedure(Sender: TObject;
    const AReason, AFileName: string; ALine: Integer; const AFunc: string) of object;
  { A breakpoint or watchpoint gdb has told us about.  One record rather than
    six parameters: gdb reports the condition, the enabled flag and the hit
    count in the same tuple it reports the location in, and a list pane that
    shows all of them needs all of them. }
  TLedGdbBreakEvent = procedure(Sender: TObject;
    const AInfo: TLedGdbBreakInfo) of object;
  TLedGdbBreakGoneEvent = procedure(Sender: TObject; ANumber: Integer) of object;
  { A watchpoint fired.  AOldValue is '' for a read watchpoint, which reports
    only what was read; both are given for a write or access watchpoint.
    Fired before OnStopped, so a listener can say what changed and then deal
    with the stop as it would any other. }
  TLedGdbWatchHitEvent = procedure(Sender: TObject; ANumber: Integer;
    const AExpression, AOldValue, ANewValue: string) of object;
  TLedGdbEvalEvent = procedure(Sender: TObject; const ATag, AValue: string;
    AIsError: Boolean) of object;
  TLedGdbNotify = procedure(Sender: TObject) of object;
  TLedGdbVarCreatedEvent = procedure(Sender: TObject; const ATag, AVarObj,
    ATypeName, AValue: string; ANumChild: Integer) of object;
  TLedGdbVarChildrenEvent = procedure(Sender: TObject; const ATag: string;
    const AChildren: TLedGdbVarChildren) of object;

  TLedGdbSession = class
  private
    FProcess: TProcess;
    FState: TLedGdbState;
    FPending: string;                 // partial trailing line from the pipe
    FToken: Integer;
    FVersion: string;
    FInferiorAlive: Boolean;
    FLastError: string;

    { token -> what it was asking, and a caller-supplied tag (an expression,
      or "file:line") that the reply alone would not carry. }
    FPendTokens: array of Integer;
    FPendKinds: array of TLedGdbRequest;
    FPendTags: array of string;

    FLocals: TLedGdbLocals;
    FFrames: TLedGdbFrames;
    { Every variable object handed out, so they can all be dropped when the
      program moves.  A varobj is bound to the frame it was made in; kept
      across a resume it reports the old frame's memory, which is a wrong
      answer rather than an error. }
    FVarObjs: TStringList;

    FOnConsole: TLedGdbTextEvent;
    FOnTarget: TLedGdbTextEvent;
    FOnLog: TLedGdbTextEvent;
    FOnError: TLedGdbTextEvent;
    FOnStopped: TLedGdbStopEvent;
    FOnRunning: TLedGdbNotify;
    FOnStateChanged: TLedGdbNotify;
    FOnBreakAdded: TLedGdbBreakEvent;
    FOnBreakRemoved: TLedGdbBreakGoneEvent;
    FOnWatchHit: TLedGdbWatchHitEvent;
    FOnLocals: TLedGdbNotify;
    FOnFrames: TLedGdbNotify;
    FOnEval: TLedGdbEvalEvent;
    FOnVarCreated: TLedGdbVarCreatedEvent;
    FOnVarChildren: TLedGdbVarChildrenEvent;
    FOnExited: TLedGdbNotify;

    procedure SetState(AValue: TLedGdbState);
    function NextToken(AKind: TLedGdbRequest; const ATag: string): Integer;
    function TakePending(AToken: Integer; out AKind: TLedGdbRequest;
      out ATag: string): Boolean;
    procedure Dispatch(ARec: TLedMIRecord);
    procedure HandleResult(ARec: TLedMIRecord);
    procedure HandleExec(ARec: TLedMIRecord);
    procedure HandleNotify(ARec: TLedMIRecord);
    procedure ReadLocals(ARec: TLedMIRecord);
    procedure ReadFrames(ARec: TLedMIRecord);
    procedure ReadVarChildren(ARec: TLedMIRecord; const ATag: string);
    procedure EmitBreakpoint(AValue: TLedMIValue);
    procedure EmitWatchpoint(ARec: TLedMIRecord; const AExpression: string);
    procedure EmitWatchHit(ARec: TLedMIRecord; const AReason: string);
    procedure Send(const ACommand: string; AKind: TLedGdbRequest = lgrNone;
      const ATag: string = '');
  public
    constructor Create;
    destructor Destroy; override;

    { Spawns gdb.  False when it could not be started -- LastError says why,
      and the caller should say so rather than leaving a dead pane. }
    function Start(const AGdbPath: string = 'gdb'): Boolean;
    procedure Quit;
    function Alive: Boolean;

    { Drains whatever gdb has said and dispatches it.  Safe to call when
      nothing is running.  Returns True when it handled at least one line,
      which is what a test loop waits on. }
    function Poll: Boolean;

    { Waits up to ATimeoutMs for the session to reach one of AStates, polling
      as it goes.  For the headless suite; the editor never blocks. }
    function WaitForState(AStates: array of TLedGdbState;
      ATimeoutMs: Integer = 10000): Boolean;

    { --- configuring the target --- }
    procedure SetTarget(const APath: string);
    procedure SetArguments(AArgs: TStrings);
    procedure SetWorkingDir(const ADir: string);
    procedure SetEnvironmentVar(const AName, AValue: string);

    { --- execution --- }
    procedure ExecRun;
    procedure ExecContinue;
    procedure ExecNext;      // step over
    procedure ExecStep;      // step into
    procedure ExecFinish;    // step out
    procedure ExecInterrupt; // pause
    { Runs on until a line is reached, without stopping at anything in
      between -- "run to cursor".  Answers with reason="location-reached". }
    procedure ExecUntil(const AFileName: string; ALine: Integer);

    { --- breakpoints --- }
    { ACondition, when given, makes the breakpoint fire only where the
      expression is true. }
    procedure BreakInsert(const AFileName: string; ALine: Integer;
      const ACondition: string = '');
    procedure BreakDelete(ANumber: Integer);
    { Changes or -- with an empty expression -- clears the condition on a
      breakpoint gdb already knows about. }
    procedure BreakCondition(ANumber: Integer; const ACondition: string);
    { Turns a breakpoint or watchpoint off without forgetting it.  gdb sends
      no notification for this -- checked against 12.1, where -break-disable
      answers a bare ^done -- so the caller keeps the flag itself. }
    procedure BreakEnable(ANumber: Integer; AEnabled: Boolean);

    { --- watchpoints --- }
    { Stops the program when AExpression changes (lgbWatch), is read
      (lgbReadWatch), or either (lgbAccessWatch).

      Unlike a breakpoint this cannot be set ahead of time on anything but a
      global: gdb answers `No symbol "total" in current context.` for a local
      until there is a frame to find it in, which is reported on OnError with
      the expression named rather than swallowed. }
    procedure WatchInsert(const AExpression: string;
      AKind: TLedGdbBreakKind = lgbWatch);

    { --- inspection --- }
    procedure RequestLocals;
    procedure RequestFrames;
    procedure SelectFrame(ALevel: Integer);
    { The answer arrives on OnEval carrying ATag, so one handler can serve
      watches and hover without keeping a queue of its own. }
    procedure Evaluate(const AExpression, ATag: string);

    { Makes a variable object for AExpression and reports it on
      OnVarCreated.  NumChild > 0 means it can be drilled into. }
    procedure VarCreate(const AExpression, ATag: string);
    { The fields or elements of AVarObj, on OnVarChildren. }
    procedure VarChildren(const AVarObj, ATag: string);
    { Drops every variable object.  Done automatically on each resume. }
    procedure VarDeleteAll;

    procedure SendRaw(const ACommand: string);

    property State: TLedGdbState read FState;
    property InferiorAlive: Boolean read FInferiorAlive;
    property Version: string read FVersion;
    property LastError: string read FLastError;
    property Locals: TLedGdbLocals read FLocals;
    property Frames: TLedGdbFrames read FFrames;

    property OnConsole: TLedGdbTextEvent read FOnConsole write FOnConsole;
    property OnTarget: TLedGdbTextEvent read FOnTarget write FOnTarget;
    property OnLog: TLedGdbTextEvent read FOnLog write FOnLog;
    property OnError: TLedGdbTextEvent read FOnError write FOnError;
    property OnStopped: TLedGdbStopEvent read FOnStopped write FOnStopped;
    property OnRunning: TLedGdbNotify read FOnRunning write FOnRunning;
    property OnStateChanged: TLedGdbNotify read FOnStateChanged write FOnStateChanged;
    property OnBreakAdded: TLedGdbBreakEvent read FOnBreakAdded write FOnBreakAdded;
    property OnBreakRemoved: TLedGdbBreakGoneEvent read FOnBreakRemoved write FOnBreakRemoved;
    property OnWatchHit: TLedGdbWatchHitEvent read FOnWatchHit write FOnWatchHit;
    property OnLocals: TLedGdbNotify read FOnLocals write FOnLocals;
    property OnFrames: TLedGdbNotify read FOnFrames write FOnFrames;
    property OnEval: TLedGdbEvalEvent read FOnEval write FOnEval;
    property OnVarCreated: TLedGdbVarCreatedEvent
      read FOnVarCreated write FOnVarCreated;
    property OnVarChildren: TLedGdbVarChildrenEvent
      read FOnVarChildren write FOnVarChildren;
    property OnExited: TLedGdbNotify read FOnExited write FOnExited;
  end;

{ The C expression around column ACol of ALine, or '' when there is nothing
  worth asking gdb about.

  Deliberately more than an identifier.  medit's plugin takes the bare
  `[A-Za-z_][A-Za-z0-9_]*` run and its own notes list `a->b`, `a.b` and
  `a[i]` as unsupported -- which is most of what one actually wants to look
  at while stopped in C.  This walks left through field access, arrow and
  subscript so hovering the `y` of `box.tl.y` asks about `box.tl.y`.

  Keywords and type names return '' : `int`, `if` and `return` are never
  worth a round trip, and gdb answers each of them with an error that would
  otherwise be shown as though it meant something. }
function LedExpressionAt(const ALine: string; ACol: Integer): string;

{ True when a gdb that speaks mi3 can be found.  The pane greys itself out
  rather than failing at the first click. }
function LedGdbAvailable(const AGdbPath: string = 'gdb'): Boolean;

implementation

uses
  FileUtil, LazFileUtils;

var
  { Probed once; the answer cannot change while the editor runs, and the
    probe costs a process. }
  FGdbProbed: Boolean = False;
  FGdbFound: Boolean = False;

function LedGdbAvailable(const AGdbPath: string): Boolean;
begin
  if FGdbProbed then Exit(FGdbFound);
  FGdbProbed := True;
  FGdbFound := (AGdbPath <> '') and
               ((FileExists(AGdbPath) and FileIsExecutable(AGdbPath)) or
                (FindDefaultExecutablePath(AGdbPath) <> ''));
  Result := FGdbFound;
end;

const
  { Not worth asking about, and each would come back as an error. }
  CNoise: array[0..37] of string = (
    'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default',
    'break', 'continue', 'return', 'goto', 'sizeof', 'typedef',
    'struct', 'union', 'enum', 'const', 'volatile', 'static', 'extern',
    'register', 'inline', 'void', 'char', 'short', 'int', 'long',
    'float', 'double', 'signed', 'unsigned', 'NULL', 'true', 'false',
    'nullptr', 'auto', 'restrict');

function IsWordCh(C: Char): Boolean; inline;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']);
end;

function LedExpressionAt(const ALine: string; ACol: Integer): string;
var
  Start_, Stop_, k, Depth, Saved: Integer;
  Word_: string;
begin
  Result := '';
  if (ACol < 1) or (ACol > Length(ALine)) then Exit;
  if not IsWordCh(ALine[ACol]) then Exit;
  { A number on its own is not a variable. }
  if ALine[ACol] in ['0'..'9'] then
  begin
    k := ACol;
    while (k > 1) and IsWordCh(ALine[k - 1]) do Dec(k);
    if ALine[k] in ['0'..'9'] then Exit;
  end;

  Stop_ := ACol;
  while (Stop_ < Length(ALine)) and IsWordCh(ALine[Stop_ + 1]) do Inc(Stop_);
  Start_ := ACol;
  while (Start_ > 1) and IsWordCh(ALine[Start_ - 1]) do Dec(Start_);

  { The identifier alone decides whether this is noise -- `int` in
    `int x` must not become a request just because `x` follows it. }
  Word_ := Copy(ALine, Start_, Stop_ - Start_ + 1);
  for k := 0 to High(CNoise) do
    if Word_ = CNoise[k] then Exit;

  { Now walk left through whatever qualifies it.

    Each turn consumes one qualifier -- `.`, `->` or a balanced `[...]` --
    and then the name in front of it.  A qualifier with nothing before it is
    not part of an expression, so the position is put back: hovering the `x`
    of a line beginning `.x` asks about `x`, not about `.x`. }
  repeat
    Saved := Start_;

    if (Start_ > 1) and (ALine[Start_ - 1] = '.') then
      Dec(Start_)
    else if (Start_ > 2) and (ALine[Start_ - 2] = '-') and
            (ALine[Start_ - 1] = '>') then
      Dec(Start_, 2)
    else if (Start_ > 1) and (ALine[Start_ - 1] = ']') then
    begin
      { Back over a balanced subscript, so a[i][j] and a[f(1)] both work. }
      Depth := 0;
      k := Start_ - 1;
      while k >= 1 do
      begin
        if ALine[k] = ']' then Inc(Depth)
        else if ALine[k] = '[' then
        begin
          Dec(Depth);
          if Depth = 0 then Break;
        end;
        Dec(k);
      end;
      if (k < 1) or (Depth <> 0) then Break;
      Start_ := k;
    end
    else
      Break;

    if (Start_ > 1) and IsWordCh(ALine[Start_ - 1]) then
      while (Start_ > 1) and IsWordCh(ALine[Start_ - 1]) do Dec(Start_)
    else if (Start_ > 1) and (ALine[Start_ - 1] = ']') then
      { `arr[2].x` -- the thing being qualified is itself subscripted, so
        let the next turn take the subscript.  Breaking here instead is what
        made this return ".x". }
      Continue
    else
    begin
      Start_ := Saved;
      Break;
    end;
  until False;

  Result := Copy(ALine, Start_, Stop_ - Start_ + 1);
end;

{ --- lifecycle ------------------------------------------------------------- }

constructor TLedGdbSession.Create;
begin
  inherited Create;
  FState := lgsIdle;
  FToken := 0;
  FVarObjs := TStringList.Create;
end;

destructor TLedGdbSession.Destroy;
begin
  Quit;
  FProcess.Free;
  FVarObjs.Free;
  inherited Destroy;
end;

function TLedGdbSession.Alive: Boolean;
begin
  Result := (FProcess <> nil) and FProcess.Running;
end;

procedure TLedGdbSession.SetState(AValue: TLedGdbState);
begin
  if FState = AValue then Exit;
  FState := AValue;
  if Assigned(FOnStateChanged) then FOnStateChanged(Self);
end;

function TLedGdbSession.Start(const AGdbPath: string): Boolean;
begin
  Result := False;
  FLastError := '';
  if Alive then Exit(True);

  FreeAndNil(FProcess);
  FProcess := TProcess.Create(nil);
  FProcess.Executable := AGdbPath;
  { -nx so a personal .gdbinit cannot change the protocol under us, --quiet
    so the banner does not arrive as a dozen unknown records. }
  FProcess.Parameters.Add('--interpreter=mi3');
  FProcess.Parameters.Add('-nx');
  FProcess.Parameters.Add('--quiet');
  FProcess.Options := [poUsePipes, poStderrToOutPut, poNoConsole];

  try
    FProcess.Execute;
  except
    on E: Exception do
    begin
      FLastError := 'could not start ' + AGdbPath + ': ' + E.Message;
      FreeAndNil(FProcess);
      SetState(lgsError);
      Exit;
    end;
  end;

  FPending := '';
  FInferiorAlive := False;
  SetState(lgsLoading);
  { Proves the pipe works and gives us a version to show. }
  Send('-gdb-version', lgrVersion);
  Result := True;
end;

procedure TLedGdbSession.Quit;
begin
  if FProcess = nil then Exit;
  if FProcess.Running then
  begin
    try
      Send('-gdb-exit');
      { gdb goes away on its own after -gdb-exit; give it a moment, then
        insist.  Terminate on a process that has already gone is harmless. }
      Sleep(60);
      Poll;
      if FProcess.Running then FProcess.Terminate(0);
    except
      { A pipe that has already closed raises on write.  Nothing to do. }
    end;
  end;
  SetState(lgsExited);
end;

{ --- writing --------------------------------------------------------------- }

function TLedGdbSession.NextToken(AKind: TLedGdbRequest;
  const ATag: string): Integer;
var
  n: Integer;
begin
  Inc(FToken);
  Result := FToken;
  if AKind = lgrNone then Exit;
  n := Length(FPendTokens);
  SetLength(FPendTokens, n + 1);
  SetLength(FPendKinds, n + 1);
  SetLength(FPendTags, n + 1);
  FPendTokens[n] := Result;
  FPendKinds[n] := AKind;
  FPendTags[n] := ATag;
end;

function TLedGdbSession.TakePending(AToken: Integer;
  out AKind: TLedGdbRequest; out ATag: string): Boolean;
var
  i, j: Integer;
begin
  Result := False;
  AKind := lgrNone;
  ATag := '';
  for i := 0 to High(FPendTokens) do
    if FPendTokens[i] = AToken then
    begin
      AKind := FPendKinds[i];
      ATag := FPendTags[i];
      { Removed before the caller is told, so a handler may issue another
        command without tripping over its own entry. }
      for j := i to High(FPendTokens) - 1 do
      begin
        FPendTokens[j] := FPendTokens[j + 1];
        FPendKinds[j] := FPendKinds[j + 1];
        FPendTags[j] := FPendTags[j + 1];
      end;
      SetLength(FPendTokens, Length(FPendTokens) - 1);
      SetLength(FPendKinds, Length(FPendKinds) - 1);
      SetLength(FPendTags, Length(FPendTags) - 1);
      Exit(True);
    end;
end;

procedure TLedGdbSession.Send(const ACommand: string; AKind: TLedGdbRequest;
  const ATag: string);
var
  Line: string;
  Tok: Integer;
begin
  if not Alive then Exit;
  Tok := NextToken(AKind, ATag);
  Line := IntToStr(Tok) + ACommand + LineEnding;
  try
    FProcess.Input.Write(Line[1], Length(Line));
  except
    on E: Exception do
    begin
      FLastError := E.Message;
      SetState(lgsError);
    end;
  end;
end;

procedure TLedGdbSession.SendRaw(const ACommand: string);
begin
  Send(ACommand);
end;

{ --- reading --------------------------------------------------------------- }

function TLedGdbSession.Poll: Boolean;
var
  Buf: array[0..8191] of Char;
  N, i: Integer;
  Chunk, Line: string;
  Lines: TStringList;
  Rec: TLedMIRecord;
begin
  Result := False;
  if FProcess = nil then Exit;

  { Everything waiting, but no waiting: a poll must never block the editor. }
  while (FProcess.Output <> nil) and (FProcess.Output.NumBytesAvailable > 0) do
  begin
    N := FProcess.Output.Read(Buf, SizeOf(Buf));
    if N <= 0 then Break;
    SetString(Chunk, Buf, N);
    FPending := FPending + Chunk;
    Result := True;
  end;

  if FPending <> '' then
  begin
    Lines := TStringList.Create;
    try
      { A record is a line, and a read can end in the middle of one -- the
        tail is held back until its newline arrives, or half a *stopped
        would be parsed as garbage and the stop would be missed. }
      FPending := StringReplace(FPending, #13#10, #10, [rfReplaceAll]);
      Lines.StrictDelimiter := True;
      Lines.Delimiter := #10;
      Lines.DelimitedText := FPending;
      if (FPending <> '') and (FPending[Length(FPending)] = #10) then
        FPending := ''
      else if Lines.Count > 0 then
      begin
        FPending := Lines[Lines.Count - 1];
        Lines.Delete(Lines.Count - 1);
      end;

      for i := 0 to Lines.Count - 1 do
      begin
        Line := Lines[i];
        if Trim(Line) = '' then Continue;
        Rec := LedMIParse(Line);
        try
          Dispatch(Rec);
        finally
          Rec.Free;
        end;
      end;
    finally
      Lines.Free;
    end;
  end;

  { gdb itself going away is a state change the pane has to show. }
  if (FProcess <> nil) and (not FProcess.Running) and
     (FState <> lgsExited) and (FState <> lgsError) then
  begin
    FInferiorAlive := False;
    SetState(lgsExited);
    if Assigned(FOnExited) then FOnExited(Self);
  end;
end;

function TLedGdbSession.WaitForState(AStates: array of TLedGdbState;
  ATimeoutMs: Integer): Boolean;
var
  Waited, i: Integer;
begin
  Waited := 0;
  while Waited < ATimeoutMs do
  begin
    Poll;
    for i := 0 to High(AStates) do
      if FState = AStates[i] then Exit(True);
    Sleep(10);
    Inc(Waited, 10);
  end;
  Result := False;
end;

{ --- dispatch -------------------------------------------------------------- }

procedure TLedGdbSession.Dispatch(ARec: TLedMIRecord);
begin
  case ARec.Kind of
    mirResult:  HandleResult(ARec);
    mirExec:    HandleExec(ARec);
    mirNotify:  HandleNotify(ARec);
    mirConsole:
      begin
        { -gdb-version answers with console lines and a bare ^done -- there
          is no version= field to read, which the first version of this
          assumed.  The banner's first line is the version. }
        if (FVersion = '') and (Pos('GNU gdb', ARec.Text) > 0) then
          FVersion := Trim(ARec.Text);
        if Assigned(FOnConsole) then FOnConsole(Self, ARec.Text);
      end;
    mirTarget:  if Assigned(FOnTarget) then FOnTarget(Self, ARec.Text);
    mirLog:     if Assigned(FOnLog) then FOnLog(Self, ARec.Text);
    mirPrompt:
      if FState = lgsLoading then SetState(lgsReady);
    mirUnknown:
      { The debugged program's own output.  On a pipe the inferior inherits
        gdb's stdout and writes to it directly, so its text arrives as a bare
        line between the records rather than in an @ record -- checked
        against gdb 12.1, where `printf("total=5")` lands exactly here.
        Treating it as target output is what stops it disappearing. }
      if (ARec.Text <> '') and Assigned(FOnTarget) then
        FOnTarget(Self, ARec.Text + LineEnding);
  end;
end;

procedure TLedGdbSession.HandleResult(ARec: TLedMIRecord);
var
  Kind: TLedGdbRequest;
  Tag, Msg: string;
  Known: Boolean;
begin
  Known := TakePending(ARec.Token, Kind, Tag);

  if ARec.Class_ = 'error' then
  begin
    Msg := ARec.Results.Str('msg', 'gdb reported an error');
    { An evaluation that failed is an answer, not a fault: hovering over a
      name that is not in scope is the ordinary case, and posting it as a
      session error would fill the console with noise. }
    if Known and (Kind = lgrEval) then
    begin
      if Assigned(FOnEval) then FOnEval(Self, Tag, Msg, True);
      Exit;
    end;
    { A watchpoint that could not be set is reported with the expression in
      it: gdb's own `No symbol "total" in current context.` does not say
      which of the things one just asked for it was talking about. }
    if Known and (Kind = lgrWatchInsert) then
      Msg := Format('cannot watch %s: %s', [Tag, Msg]);
    FLastError := Msg;
    if Assigned(FOnError) then FOnError(Self, Msg);
    Exit;
  end;

  if not Known then Exit;

  case Kind of
    lgrVersion:
      { Only as a fallback: gdb answers this on the console stream, and the
        console handler above has already taken it. }
      if FVersion = '' then
        FVersion := Trim(ARec.Results.Str('version', ''));
    lgrBreakInsert:
      EmitBreakpoint(ARec.Results.ByName('bkpt'));
    lgrWatchInsert:
      EmitWatchpoint(ARec, Tag);
    lgrLocals:
      ReadLocals(ARec);
    lgrFrames:
      ReadFrames(ARec);
    lgrEval:
      if Assigned(FOnEval) then
        FOnEval(Self, Tag, ARec.Results.Str('value', ''), False);
    lgrVarCreate:
      begin
        if ARec.Results.Str('name', '') <> '' then
          FVarObjs.Add(ARec.Results.Str('name', ''));
        if Assigned(FOnVarCreated) then
          FOnVarCreated(Self, Tag,
            ARec.Results.Str('name', ''),
            ARec.Results.Str('type', ''),
            ARec.Results.Str('value', ''),
            ARec.Results.Int('numchild', 0));
      end;
    lgrVarChildren:
      ReadVarChildren(ARec, Tag);
  end;
end;

procedure TLedGdbSession.HandleExec(ARec: TLedMIRecord);
var
  Reason, FileName, Func: string;
  Line: Integer;
begin
  if ARec.Class_ = 'running' then
  begin
    { Frame-bound, so they cannot outlive the stop that made them. }
    VarDeleteAll;
    FInferiorAlive := True;
    SetState(lgsRunning);
    if Assigned(FOnRunning) then FOnRunning(Self);
    Exit;
  end;

  if ARec.Class_ <> 'stopped' then Exit;

  Reason := ARec.Results.Str('reason', '');
  { fullname is the absolute path; file may be relative to the compilation
    directory, which is not where the editor is. }
  FileName := ARec.Results.Str('frame.fullname',
                               ARec.Results.Str('frame.file', ''));
  Line := ARec.Results.Int('frame.line', 0);
  Func := ARec.Results.Str('frame.func', '');

  { The program finishing is a stop like any other as far as gdb is
    concerned -- it is still there and can be re-run -- but nothing may be
    evaluated afterwards, or gdb answers "No registers." to everything. }
  if Copy(Reason, 1, 6) = 'exited' then
    FInferiorAlive := False;

  { Announced before the stop, so a listener can say what changed while it
    still has both values, then handle the stop like any other. }
  if Pos('watchpoint-trigger', Reason) > 0 then
    EmitWatchHit(ARec, Reason);

  SetState(lgsStopped);
  if Assigned(FOnStopped) then FOnStopped(Self, Reason, FileName, Line, Func);
end;

procedure TLedGdbSession.HandleNotify(ARec: TLedMIRecord);
var
  Num: Integer;
begin
  if (ARec.Class_ = 'breakpoint-created') or
     (ARec.Class_ = 'breakpoint-modified') then
    EmitBreakpoint(ARec.Results.ByName('bkpt'))
  else if ARec.Class_ = 'breakpoint-deleted' then
  begin
    Num := ARec.Results.Int('id', -1);
    if (Num >= 0) and Assigned(FOnBreakRemoved) then
      FOnBreakRemoved(Self, Num);
  end;
end;

{ The kind gdb names in a bkpt tuple.  Its words, checked against 12.1:
  "breakpoint", "hw watchpoint", "read watchpoint", "acc watchpoint" -- and
  matched on the tail rather than in full, because a software watchpoint is
  plain "watchpoint" where a hardware one is "hw watchpoint". }
function BreakKindOf(const AType: string): TLedGdbBreakKind;
begin
  if Pos('read watchpoint', AType) > 0 then Result := lgbReadWatch
  else if Pos('acc watchpoint', AType) > 0 then Result := lgbAccessWatch
  else if Pos('watchpoint', AType) > 0 then Result := lgbWatch
  else Result := lgbLine;
end;

procedure TLedGdbSession.EmitBreakpoint(AValue: TLedMIValue);
var
  Loc: string;
  p: Integer;
  Info: TLedGdbBreakInfo;
begin
  if AValue = nil then Exit;
  Info.Number := AValue.Int('number', -1);
  if Info.Number < 0 then Exit;

  Info.Kind := BreakKindOf(AValue.Str('type', ''));
  Info.FileName := AValue.Str('fullname', AValue.Str('file', ''));
  Info.Line := AValue.Int('line', 0);
  { A watchpoint's expression is in what=, which is also where a breakpoint on
    a function would put its name -- so it is only read for a watchpoint. }
  if Info.Kind = lgbLine then
    Info.Expression := ''
  else
    Info.Expression := AValue.Str('what', AValue.Str('original-location', ''));
  Info.Condition := AValue.Str('cond', '');
  Info.Enabled := AValue.Str('enabled', 'y') <> 'n';
  Info.HitCount := AValue.Int('times', 0);
  Info.Complete := True;

  { A pending breakpoint -- set before any binary was loaded -- has no file
    or line of its own; gdb only echoes back what was asked for.  Watchpoints
    are exempt: their original-location is the expression, not a place. }
  if (Info.Kind = lgbLine) and ((Info.FileName = '') or (Info.Line = 0)) then
  begin
    Loc := AValue.Str('original-location', '');
    p := LastDelimiter(':', Loc);
    if p > 1 then
    begin
      Info.FileName := Copy(Loc, 1, p - 1);
      Info.Line := StrToIntDef(Copy(Loc, p + 1, Length(Loc)), 0);
    end;
  end;

  if Assigned(FOnBreakAdded) then FOnBreakAdded(Self, Info);
end;

{ The reply to -break-watch, which is not a bkpt tuple: gdb answers
  ^done,wpt={number,exp} for a write watchpoint and names the field
  hw-rwpt or hw-awpt for the other two -- so the field name is the kind.

  It carries nothing else, which is why Complete is False: the full record
  arrives later, in the =breakpoint-modified that the first hit produces. }
procedure TLedGdbSession.EmitWatchpoint(ARec: TLedMIRecord;
  const AExpression: string);
var
  V: TLedMIValue;
  Info: TLedGdbBreakInfo;
begin
  Info.Kind := lgbWatch;
  V := ARec.Results.ByName('wpt');
  if V = nil then
  begin
    V := ARec.Results.ByName('hw-rwpt');
    Info.Kind := lgbReadWatch;
  end;
  if V = nil then
  begin
    V := ARec.Results.ByName('hw-awpt');
    Info.Kind := lgbAccessWatch;
  end;
  if V = nil then Exit;

  Info.Number := V.Int('number', -1);
  if Info.Number < 0 then Exit;
  Info.FileName := '';
  Info.Line := 0;
  Info.Expression := V.Str('exp', AExpression);
  Info.Condition := '';
  Info.Enabled := True;
  Info.HitCount := 0;
  Info.Complete := False;

  if Assigned(FOnBreakAdded) then FOnBreakAdded(Self, Info);
end;

{ A watchpoint stop.  The tuple naming the watchpoint is called wpt, hw-rwpt
  or hw-awpt exactly as in the insert reply, and the values arrive as
  value={old,new} for a write, value={value} for a read. }
procedure TLedGdbSession.EmitWatchHit(ARec: TLedMIRecord;
  const AReason: string);
var
  V: TLedMIValue;
  Num: Integer;
  Expr, Old, New_: string;
begin
  if not Assigned(FOnWatchHit) then Exit;
  V := ARec.Results.ByName('wpt');
  if V = nil then V := ARec.Results.ByName('hw-rwpt');
  if V = nil then V := ARec.Results.ByName('hw-awpt');
  if V = nil then Exit;

  Num := V.Int('number', -1);
  Expr := V.Str('exp', '');
  Old := ARec.Results.Str('value.old', '');
  New_ := ARec.Results.Str('value.new', ARec.Results.Str('value.value', ''));
  FOnWatchHit(Self, Num, Expr, Old, New_);
end;

procedure TLedGdbSession.ReadLocals(ARec: TLedMIRecord);
var
  V, E: TLedMIValue;
  i, n: Integer;
begin
  SetLength(FLocals, 0);
  V := ARec.Results.ByName('variables');
  if V = nil then Exit;
  n := 0;
  SetLength(FLocals, V.Count);
  for i := 0 to V.Count - 1 do
  begin
    E := V[i];
    if E = nil then Continue;
    FLocals[n].Name := E.Str('name', '');
    FLocals[n].TypeName := E.Str('type', '');
    { --simple-values leaves an aggregate without a value; saying so is
      better than an empty cell that looks like a failure. }
    FLocals[n].Value := E.Str('value', '{...}');
    if FLocals[n].Name <> '' then Inc(n);
  end;
  SetLength(FLocals, n);
  if Assigned(FOnLocals) then FOnLocals(Self);
end;

procedure TLedGdbSession.ReadFrames(ARec: TLedMIRecord);
var
  V, E: TLedMIValue;
  i, n: Integer;
begin
  SetLength(FFrames, 0);
  V := ARec.Results.ByName('stack');
  if V = nil then Exit;
  n := 0;
  SetLength(FFrames, V.Count);
  for i := 0 to V.Count - 1 do
  begin
    E := V[i];
    if E = nil then Continue;
    FFrames[n].Level := E.Int('level', n);
    FFrames[n].Func := E.Str('func', '??');
    FFrames[n].FileName := E.Str('fullname', E.Str('file', ''));
    FFrames[n].Line := E.Int('line', 0);
    FFrames[n].Addr := E.Str('addr', '');
    Inc(n);
  end;
  SetLength(FFrames, n);
  if Assigned(FOnFrames) then FOnFrames(Self);
end;

procedure TLedGdbSession.ReadVarChildren(ARec: TLedMIRecord;
  const ATag: string);
var
  V, E: TLedMIValue;
  Kids: TLedGdbVarChildren;
  i, n: Integer;
begin
  SetLength(Kids, 0);
  V := ARec.Results.ByName('children');
  if V <> nil then
  begin
    SetLength(Kids, V.Count);
    n := 0;
    for i := 0 to V.Count - 1 do
    begin
      E := V[i];
      if E = nil then Continue;
      Kids[n].VarObj := E.Str('name', '');
      Kids[n].Expr := E.Str('exp', '');
      Kids[n].TypeName := E.Str('type', '');
      { Absent for an aggregate -- see the note on the record. }
      Kids[n].Value := E.Str('value', '');
      Kids[n].NumChild := E.Int('numchild', 0);
      if Kids[n].VarObj <> '' then Inc(n);
    end;
    SetLength(Kids, n);
  end;
  if Assigned(FOnVarChildren) then FOnVarChildren(Self, ATag, Kids);
end;

{ --- commands -------------------------------------------------------------- }

procedure TLedGdbSession.SetTarget(const APath: string);
begin
  { MI quoting, not shell quoting -- see the note at the top. }
  Send('-file-exec-and-symbols ' + LedMIQuote(APath));
end;

procedure TLedGdbSession.SetArguments(AArgs: TStrings);
var
  i: Integer;
  Line: string;
begin
  Line := '';
  if AArgs <> nil then
    for i := 0 to AArgs.Count - 1 do
      Line := Line + ' ' + LedMIQuote(AArgs[i]);
  { Sent even when empty, to clear arguments left over from a previous run. }
  Send('-exec-arguments' + Line);
end;

procedure TLedGdbSession.SetWorkingDir(const ADir: string);
begin
  if ADir = '' then Exit;
  Send('-environment-cd ' + LedMIQuote(ADir));
end;

procedure TLedGdbSession.SetEnvironmentVar(const AName, AValue: string);
begin
  if AName = '' then Exit;
  Send('-gdb-set environment ' + AName + '=' + AValue);
end;

procedure TLedGdbSession.ExecRun;
begin
  Send('-exec-run', lgrExec);
end;

procedure TLedGdbSession.ExecContinue;
begin
  Send('-exec-continue', lgrExec);
end;

procedure TLedGdbSession.ExecNext;
begin
  Send('-exec-next', lgrExec);
end;

procedure TLedGdbSession.ExecStep;
begin
  Send('-exec-step', lgrExec);
end;

procedure TLedGdbSession.ExecFinish;
begin
  Send('-exec-finish', lgrExec);
end;

procedure TLedGdbSession.ExecInterrupt;
begin
  Send('-exec-interrupt --all', lgrExec);
end;

procedure TLedGdbSession.ExecUntil(const AFileName: string; ALine: Integer);
begin
  if (AFileName = '') or (ALine <= 0) then Exit;
  Send(Format('-exec-until %s:%d', [AFileName, ALine]), lgrExec);
end;

procedure TLedGdbSession.BreakInsert(const AFileName: string; ALine: Integer;
  const ACondition: string);
var
  Cmd: string;
begin
  { -f allows a breakpoint before any binary is loaded, which is what makes
    setting one in the editor before pressing Start work. }
  Cmd := '-break-insert -f';
  { The condition *is* quoted here, because it is one argument among several
    and holds spaces.  BreakCondition below must not quote -- the two are not
    interchangeable, and each was checked against gdb 12.1. }
  if ACondition <> '' then
    Cmd := Cmd + ' -c ' + LedMIQuote(ACondition);
  { The location stays unquoted: gdb echoes it back in original-location, and
    a quoted one comes back quoted so the breakpoint can never be matched to
    the line that asked for it. }
  Cmd := Cmd + Format(' %s:%d', [AFileName, ALine]);
  Send(Cmd, lgrBreakInsert, Format('%s:%d', [AFileName, ALine]));
end;

procedure TLedGdbSession.BreakCondition(ANumber: Integer;
  const ACondition: string);
begin
  if ANumber <= 0 then Exit;
  { Unquoted, and deliberately: -break-condition takes the whole rest of the
    line as the expression, so quoting it makes the quotes part of it.  An
    empty expression clears the condition, which is gdb's own convention. }
  if ACondition = '' then
    Send(Format('-break-condition %d', [ANumber]))
  else
    Send(Format('-break-condition %d %s', [ANumber, ACondition]));
end;

procedure TLedGdbSession.BreakEnable(ANumber: Integer; AEnabled: Boolean);
begin
  if ANumber <= 0 then Exit;
  if AEnabled then
    Send(Format('-break-enable %d', [ANumber]))
  else
    Send(Format('-break-disable %d', [ANumber]));
end;

{ Unquoted, like -break-condition and for the same reason: -break-watch takes
  the rest of the line as the expression, so quotes would become part of what
  is watched and gdb would answer that there is no such symbol. }
procedure TLedGdbSession.WatchInsert(const AExpression: string;
  AKind: TLedGdbBreakKind);
var
  Opt: string;
begin
  if AExpression = '' then Exit;
  case AKind of
    lgbReadWatch:   Opt := ' -r';
    lgbAccessWatch: Opt := ' -a';
  else
    Opt := '';
  end;
  Send('-break-watch' + Opt + ' ' + AExpression, lgrWatchInsert, AExpression);
end;

procedure TLedGdbSession.BreakDelete(ANumber: Integer);
begin
  Send(Format('-break-delete %d', [ANumber]), lgrBreakDelete);
  { Reported locally as well as from =breakpoint-deleted: the notify does not
    always arrive, and a duplicate removal is harmless. }
  if Assigned(FOnBreakRemoved) then
    FOnBreakRemoved(Self, ANumber);
end;

procedure TLedGdbSession.RequestLocals;
begin
  if not FInferiorAlive then Exit;
  Send('-stack-list-variables --simple-values', lgrLocals);
end;

procedure TLedGdbSession.RequestFrames;
begin
  if not FInferiorAlive then Exit;
  Send('-stack-list-frames', lgrFrames);
end;

procedure TLedGdbSession.SelectFrame(ALevel: Integer);
begin
  Send(Format('-stack-select-frame %d', [ALevel]));
end;

procedure TLedGdbSession.Evaluate(const AExpression, ATag: string);
begin
  if AExpression = '' then Exit;
  { Answered immediately rather than sent, when there is nothing to ask: the
    caller gets one code path instead of two. }
  if (FState <> lgsStopped) or (not FInferiorAlive) then
  begin
    if Assigned(FOnEval) then
      FOnEval(Self, ATag, 'not running', True);
    Exit;
  end;
  Send('-data-evaluate-expression ' + LedMIQuote(AExpression), lgrEval, ATag);
end;

procedure TLedGdbSession.VarCreate(const AExpression, ATag: string);
begin
  if (AExpression = '') or (FState <> lgsStopped) or (not FInferiorAlive) then
  begin
    if Assigned(FOnVarCreated) then FOnVarCreated(Self, ATag, '', '', '', 0);
    Exit;
  end;
  { "-" lets gdb name it, "*" means the current frame. }
  Send('-var-create - * ' + LedMIQuote(AExpression), lgrVarCreate, ATag);
end;

procedure TLedGdbSession.VarChildren(const AVarObj, ATag: string);
var
  Empty: TLedGdbVarChildren;
begin
  if (AVarObj = '') or (FState <> lgsStopped) or (not FInferiorAlive) then
  begin
    SetLength(Empty, 0);
    if Assigned(FOnVarChildren) then FOnVarChildren(Self, ATag, Empty);
    Exit;
  end;
  Send('-var-list-children --simple-values ' + AVarObj, lgrVarChildren, ATag);
end;

procedure TLedGdbSession.VarDeleteAll;
var
  i: Integer;
begin
  if FVarObjs.Count = 0 then Exit;
  if Alive then
    for i := 0 to FVarObjs.Count - 1 do
      Send('-var-delete ' + FVarObjs[i]);
  FVarObjs.Clear;
end;

end.
