{ led - a light editor.  Single instance and file hand-off.

  A second `led somefile.c` should open a tab in the window already on screen
  rather than starting a second editor.  medit did this with a per-display
  Unix socket; led uses FPC's TAdvancedSingleInstance, chosen over the simpler
  simpleipc because it has a reply channel and, more importantly, a real
  answer for the stale-lock case after a crash.

  The server id is scoped per user, and on Linux also per display, preserving
  medit's behaviour of keeping separate instances on separate displays.

  No LCL dependency. }
unit Led.Core.Instance;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, singleinstance, advancedsingleinstance;

const
  LedRequestOpen = 1;

type
  TLedOpenRequest = procedure(const APayload: string) of object;

  TLedInstanceRole = (lirServer, lirClient, lirStale);

  TLedInstance = class
  private
    FImpl: TAdvancedSingleInstance;
    FRole: TLedInstanceRole;
    FStarted: Boolean;
    FOnOpenRequest: TLedOpenRequest;
    procedure HandleCustomRequest(Sender: TBaseSingleInstance;
      MsgID, MsgType: Integer; MsgData: TStream);
  public
    constructor Create(const AName: string = '');
    destructor Destroy; override;

    { Becomes the server, or discovers a running one.  A stale lock left by a
      crashed instance is taken over rather than treated as a live server. }
    function Start: TLedInstanceRole;

    { Client side: hand APayload to the running instance.  True when it was
      accepted. }
    function SendOpen(const APayload: string): Boolean;

    { Server side: called from a timer; delivers anything a client posted. }
    procedure Poll;

    property Role: TLedInstanceRole read FRole;
    property OnOpenRequest: TLedOpenRequest read FOnOpenRequest
      write FOnOpenRequest;
  end;

{ "led_<user>" on Windows and macOS, "led_<user>_<display>" on Linux. }
function LedInstanceId(const AName: string): string;

implementation

{ advancedipc turns the server id straight into a file name and rejects
  anything but letters, digits and underscores -- not even a hyphen.  So the
  separator is an underscore too. }
function Sanitise(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_'] then
      Result := Result + S[i]
    else
      Result := Result + '_';
end;

function LedInstanceId(const AName: string): string;
var
  User, Display: string;
begin
  {$IFDEF WINDOWS}
  User := GetEnvironmentVariable('USERNAME');
  {$ELSE}
  User := GetEnvironmentVariable('USER');
  {$ENDIF}
  if User = '' then User := 'user';
  Result := 'led_' + Sanitise(User);

  {$IF DEFINED(LINUX) OR DEFINED(FREEBSD)}
  { Wayland first: a session may have both set, and the Wayland socket is the
    one that identifies the seat the user is actually looking at. }
  Display := GetEnvironmentVariable('WAYLAND_DISPLAY');
  if Display = '' then Display := GetEnvironmentVariable('DISPLAY');
  if Display <> '' then
    Result := Result + '_' + Sanitise(Display);
  {$ENDIF}

  if AName <> '' then
    Result := Result + '_' + Sanitise(AName);
end;

constructor TLedInstance.Create(const AName: string);
begin
  inherited Create;
  FImpl := TAdvancedSingleInstance.Create(nil);
  FImpl.ID := LedInstanceId(AName);
  FImpl.Global := False;
  FImpl.OnServerReceivedCustomRequest := @HandleCustomRequest;
end;

destructor TLedInstance.Destroy;
begin
  if FStarted then
    try
      FImpl.Stop;
    except
      { Shutting down is not a good time to fail. }
    end;
  FImpl.Free;
  inherited Destroy;
end;

function TLedInstance.Start: TLedInstanceRole;
begin
  case FImpl.Start of
    siServer: FRole := lirServer;
    siClient: FRole := lirClient;
  else
    { A lock file left behind by a crash.  Nothing is listening, so this
      instance takes over rather than refusing to start. }
    FRole := lirStale;
  end;
  FStarted := True;
  Result := FRole;
end;

function TLedInstance.SendOpen(const APayload: string): Boolean;
var
  Stream: TStringStream;
begin
  Result := False;
  if FRole <> lirClient then Exit;
  Stream := TStringStream.Create(APayload);
  try
    try
      Result := FImpl.ClientSendCustomRequest(LedRequestOpen, Stream);
    except
      { The server may have exited between the probe and the send. }
      Result := False;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TLedInstance.Poll;
begin
  if FRole = lirClient then Exit;
  try
    FImpl.ServerCheckMessages;
  except
    { A malformed message must not bring the editor down. }
  end;
end;

procedure TLedInstance.HandleCustomRequest(Sender: TBaseSingleInstance;
  MsgID, MsgType: Integer; MsgData: TStream);
var
  S: TStringStream;
begin
  if MsgType <> LedRequestOpen then Exit;
  if not Assigned(FOnOpenRequest) then Exit;
  S := TStringStream.Create('');
  try
    MsgData.Position := 0;
    S.CopyFrom(MsgData, MsgData.Size);
    FOnOpenRequest(S.DataString);
  finally
    S.Free;
  end;
end;

end.
