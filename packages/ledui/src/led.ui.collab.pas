{ LED - a lightweight editor.  Editing together: a document shared through a
  relay with others, live (Parade's paradesync session).

  Both kinds of tab take part.  A page in the visual editor shares a rich
  document (the session's own TParadeEdit target); a text tab shares its
  text, through TLedTextTarget below -- the tab's buffer, its views' carets,
  the others' carets drawn as SynEdit markup.  What is around a session is
  the same for both and lives here: asking for the relay, hosting one inside
  LED (one relay for every document this LED hosts), invitation links, the
  status line.

  Built only when Parade's collaboration library is (LED_PARADE_SYNC). }
unit Led.UI.Collab;

{$mode objfpc}{$H+}

interface

{$I led.parade.inc}

{$IFDEF LED_PARADE_SYNC}
uses
  Classes, SysUtils, Controls, Forms, StdCtrls, Dialogs, Graphics, Clipbrd, IniFiles,
  SynEdit, SynEditMarkup, SynEditMiscClasses, SynEditTypes, SynEditKeyCmds, LazSynEditText, LCLType,
  parade, paradesync, paraderelay, paradetextsync;

type
  TLedCollabKind = (lckRich, lckText);

  { The others' carets and selections in a text view: the selection tinted in the person's colour, a bar
    at the caret. }
  TLedPeerMarkup = class(TSynEditMarkup)
  private
    FRows, FFrom, FTo: array of Integer;     { 1-based rows, logical columns [From, To) }
    FCaret: array of Boolean;
    FColors: array of TSynSelectedColor;
    FCount: Integer;
  public
    destructor Destroy; override;
    procedure SetCarets(const ACarets: array of TParadeTextCaret);
    function GetMarkupAttributeAtRowCol(const aRow: Integer; const aStartCol: TLazSynDisplayTokenBound;
      const AnRtlInfo: TLazSynDisplayRtlInfo): TSynSelectedColor; override;
    procedure GetNextMarkupColAfterRowCol(const aRow: Integer; const aStartCol: TLazSynDisplayTokenBound;
      const AnRtlInfo: TLazSynDisplayRtlInfo; out ANextPhys, ANextLog: Integer); override;
  end;

  { a text tab's buffer shared: its master SynEdit (the lines every view shows), the caret of the view
    in front }
  TLedTextTarget = class(TParadeTextTarget)
  private
    FMaster: TSynEdit;
    FOnPoll: TNotifyEvent;
    FViews: TList;              { the views showing the buffer, each with a TLedPeerMarkup }
    FMarkups: TList;
    FActive: TSynEdit;
    FCarets: array of TParadeTextCaret;
    procedure BufferEdited(Sender: TSynEditStrings; aLinePos, aBytePos, aCount, aLineBrkCnt: Integer;
      aText: String);
    procedure Command(Sender: TObject; AfterProcessing: Boolean; var Handled: Boolean;
      var ACommand: TSynEditorCommand; var AChar: TUTF8Char; Data: Pointer; HandlerData: Pointer);
  protected
    function LineCount: Integer; override;
    function GetLine(I: Integer): string; override;
    procedure SetText(const S: string); override;
    procedure ReplaceRange(Line1, Col1, Line2, Col2: Integer; const S: string); override;
    procedure GetCaret(out Line, Col, AnchorLine, AnchorCol: Integer); override;
    procedure ShowCarets(const Carets: array of TParadeTextCaret); override;
    procedure SetEditorReadOnly(AValue: Boolean); override;
  public
    constructor Create(AMaster: TSynEdit);
    destructor Destroy; override;
    { a view of the buffer: its caret can be the one shared, the others are drawn in it, its undo is this }
    procedure AddView(AView: TSynEdit);
    procedure RemoveView(AView: TSynEdit);
    { a view being destroyed let go of, not touched (its markups go with it) }
    procedure ForgetView(AView: TSynEdit);
    { the buffer being destroyed: the session closed, nothing touched again }
    procedure ForgetMaster;
    property Master: TSynEdit read FMaster;
    { the view whose caret the others see }
    property ActiveView: TSynEdit read FActive write FActive;
    { the others' carets drawn now }
    function PeerCaretCount: Integer;
    function Open(Publish: Boolean; out Why: string): Boolean; override;
    procedure Close; override;
    procedure Poll; override;
    { every tick, before anything else: the session's chance to look at its tab's views }
    property OnPoll: TNotifyEvent read FOnPoll write FOnPoll;
  end;

  { one document's session and what is around it: asking, hosting, inviting, leaving }
  TLedCollab = class(TComponent)
  private
    FSync: TParadeSync;
    FKind: TLedCollabKind;
    FHostDoc, FHostAddress: string;
    FHosting: Boolean;
    FOnChange: TNotifyEvent;
    procedure SyncChanged(Sender: TObject);
    procedure CopyClicked(Sender: TObject);
  public
    { a session (which AOwner owns) for this kind of document }
    constructor Create(AOwner: TComponent; ASync: TParadeSync; AKind: TLedCollabKind); reintroduce;
    { the editor's document shared through a relay the user names (ADoc: the name it is offered) }
    function Share(const ADoc: string): Boolean;
    { shared through a relay this LED runs: hosted, the invitation shown }
    function Host(const ADoc: string): Boolean;
    { joined (the editor's document replaced by the shared one) }
    function JoinWith(const Server, Doc, Token, Who: string): Boolean;
    { the links to send, a window to copy them from (hosting only) }
    procedure Invite;
    procedure Leave;
    function Active: Boolean;
    property Hosting: Boolean read FHosting;
    function StatusText: string;
    property Sync: TParadeSync read FSync;
    property Kind: TLedCollabKind read FKind;
    { the session's state changed (connected, offline, others came or went, left) }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { a text tab shared: owned by the tab, its buffer and every view of it bound }
  TLedTextSession = class(TComponent)
  private
    FTab: TComponent;           { a TLedTab: named so here only below, the tab's unit using this one }
    FTarget: TLedTextTarget;
    FSync: TParadeSync;
    FCollab: TLedCollab;
    procedure Polled(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    { for a TLedTab }
    constructor Create(ATab: TComponent); reintroduce;
    destructor Destroy; override;
    { the tab's session, nil when it has none }
    class function ForTab(ATab: TComponent): TLedTextSession;
    { the tab's session, made when it has none }
    class function Ensure(ATab: TComponent): TLedTextSession;
    property Collab: TLedCollab read FCollab;
    property Target: TLedTextTarget read FTarget;
    property Tab: TComponent read FTab;
  end;

{ the join dialog: an invitation link, or the relay, the document and a token; the kind of document it is
  (the link's word for it, else what the relay holds) }
function LedAskJoin(out Server, Doc, Token, Who: string; out Kind: TLedCollabKind): Boolean;
{ the relay address, document and token asked for (Share; Join without a link) }
function LedAskConnection(const ACaption: string; var AServer, ADoc, AToken, AName: string): Boolean;
{$ENDIF}

implementation

{$IFDEF LED_PARADE_SYNC}
uses
  Math, Led.Core.Paths, Led.UI.Dpi, Led.UI.Tab{$IFDEF UNIX}, BaseUnix, Unix{$ENDIF};

type
  TLedSynAccess = class(TSynEdit);    { its TextBuffer: protected there }


{ ---- settings and the hosting relay ---- }

function CollabIni: TIniFile;
begin
  ForceDirectories(LedConfigDir);
  Result := TIniFile.Create(IncludeTrailingPathDelimiter(LedConfigDir) + 'collab.ini');
end;

{ the key this LED's relay signs its tokens with, made on first use and kept with the settings }
function RelaySecret: RawByteString;
var
  F: string;
begin
  F := IncludeTrailingPathDelimiter(LedConfigDir) + 'relay.secret';
  if not FileExists(F) then
  begin
    ForceDirectories(LedConfigDir);
    with TStringList.Create do
    try
      Text := ParadeNewSecret;
      SaveToFile(F);
    finally
      Free;
    end;
    {$IFDEF UNIX}
    FpChmod(F, &600);
    {$ENDIF}
  end;
  Result := ParadeReadSecret(F);
end;

function ThisHostName: string;
begin
  {$IFDEF UNIX}
  Result := GetHostName;
  {$ELSE}
  Result := GetEnvironmentVariable('COMPUTERNAME');
  {$ENDIF}
  if Result = '' then
    Result := 'localhost';
end;

var
  { one relay for every document this LED hosts, running while any is }
  HostRelay: TParadeRelay = nil;
  HostUsers: Integer = 0;

function HostStart(APort: Integer; AEveryone: Boolean; out AWhy: string): Boolean;
begin
  AWhy := '';
  if (HostRelay <> nil) and HostRelay.Active then
  begin
    if HostRelay.Port <> APort then
    begin
      AWhy := Format('this LED hosts on port %d already: host this one there too', [HostRelay.Port]);
      Exit(False);
    end;
    Inc(HostUsers);
    Exit(True);
  end;
  if HostRelay = nil then
    HostRelay := TParadeRelay.Create(nil);
  try
    HostRelay.Secret := RelaySecret;
  except
    on E: Exception do
    begin
      AWhy := 'no signing key: ' + E.Message;
      Exit(False);
    end;
  end;
  HostRelay.DbFile := IncludeTrailingPathDelimiter(LedConfigDir) + 'relay.sqlite';
  HostRelay.Port := APort;
  if AEveryone then
    HostRelay.Host := '0.0.0.0'
  else
    HostRelay.Host := '127.0.0.1';
  if not HostRelay.Start then
  begin
    AWhy := 'the relay did not start: ' + HostRelay.LastError;
    Exit(False);
  end;
  HostUsers := 1;
  Result := True;
end;

procedure HostRelease;
begin
  if HostUsers > 0 then
    Dec(HostUsers);
  if (HostUsers = 0) and (HostRelay <> nil) then
    HostRelay.Stop;    { the last hosted document left: the others are told they are offline }
end;

function LedAskConnection(const ACaption: string; var AServer, ADoc, AToken, AName: string): Boolean;
var
  V: array of string;
  Ini: TIniFile;
begin
  Ini := CollabIni;
  try
    SetLength(V, 4);
    V[0] := Ini.ReadString('relay', 'server', 'http://127.0.0.1:8765');
    V[1] := ADoc;
    V[2] := Ini.ReadString('relay', 'token', '');
    V[3] := Ini.ReadString('relay', 'name', GetEnvironmentVariable('USER'));
    Result := InputQuery(ACaption, ['Relay address', 'Document', 'Token (from the host''s Invite, or parade_relay token)',
      'Your name'], V) and (Trim(V[0]) <> '') and (Trim(V[1]) <> '');
    if not Result then
      Exit;
    AServer := Trim(V[0]);
    ADoc := Trim(V[1]);
    AToken := Trim(V[2]);
    AName := Trim(V[3]);
    Ini.WriteString('relay', 'server', AServer);
    Ini.WriteString('relay', 'token', AToken);
    Ini.WriteString('relay', 'name', AName);
  finally
    Ini.Free;
  end;
end;

function LedAskJoin(out Server, Doc, Token, Who: string; out Kind: TLedCollabKind): Boolean;
var
  V: array of string;
  Ini: TIniFile;
  K: string;
begin
  Result := False;
  Server := '';
  Doc := '';
  Token := '';
  Kind := lckRich;
  Ini := CollabIni;
  try
    SetLength(V, 2);
    V[0] := '';
    V[1] := Ini.ReadString('relay', 'name', GetEnvironmentVariable('USER'));
    if not InputQuery('Join a shared document', ['Invitation link (blank: enter the relay, document and token)',
      'Your name'], V) then
      Exit;
    Who := Trim(V[1]);
    Ini.WriteString('relay', 'name', Who);
  finally
    Ini.Free;
  end;
  if Trim(V[0]) = '' then
  begin
    if not LedAskConnection('Join a shared document', Server, Doc, Token, Who) then
      Exit;
    K := '';
  end
  else if not ParadeParseInvite(V[0], Server, Doc, Token) then
  begin
    MessageDlg('Join', 'That is not an invitation link: it looks like http://host:8765/d/document#t=... ' +
      '(ask the host for Invite).', mtError, [mbOK], 0);
    Exit;
  end
  else
    K := ParadeInviteKind(V[0]);
  { a link from before the kind was written, or none: what the relay holds says }
  if K = '' then
    K := ParadeRelayKind(Server, Doc, Token);
  if K = 'text' then
    Kind := lckText;
  Result := True;
end;

{ ---- the others' carets in a text view ---- }

destructor TLedPeerMarkup.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FColors) do
    FColors[i].Free;
  inherited Destroy;
end;

procedure TLedPeerMarkup.SetCarets(const ACarets: array of TParadeTextCaret);
var
  i, R, AR, AC, BR, BC: Integer;
  Col: TColor;

  procedure Span(ARow, AFrom, ATo: Integer; ACaret: Boolean; AColour: TColor);
  var
    C: TSynSelectedColor;
  begin
    if FCount = Length(FRows) then
    begin
      SetLength(FRows, FCount * 2 + 8);
      SetLength(FFrom, FCount * 2 + 8);
      SetLength(FTo, FCount * 2 + 8);
      SetLength(FCaret, FCount * 2 + 8);
    end;
    FRows[FCount] := ARow;
    FFrom[FCount] := AFrom;
    FTo[FCount] := ATo;
    FCaret[FCount] := ACaret;
    if FCount >= Length(FColors) then
    begin
      SetLength(FColors, FCount + 1);
      FColors[FCount] := TSynSelectedColor.Create;
    end;
    C := FColors[FCount];
    C.Clear;
    if ACaret then
    begin   { a bar before the character the caret is at }
      C.FrameColor := AColour;
      C.FrameEdges := sfeLeft;
      C.FrameStyle := slsSolid;
    end
    else
      C.Background := RGBToColor((Red(AColour) + 3 * 255) div 4, (Green(AColour) + 3 * 255) div 4,
        (Blue(AColour) + 3 * 255) div 4);
    C.SetFrameBoundsLog(AFrom, ATo);
    Inc(FCount);
  end;

begin
  FCount := 0;
  for i := 0 to High(ACarets) do
  begin
    Col := RGBToColor((ACarets[i].Color shr 16) and $FF, (ACarets[i].Color shr 8) and $FF, ACarets[i].Color and $FF);
    { the selection, row by row, then the caret }
    if (ACarets[i].AnchorLine < ACarets[i].Line) or
       ((ACarets[i].AnchorLine = ACarets[i].Line) and (ACarets[i].AnchorCol < ACarets[i].Col)) then
    begin
      AR := ACarets[i].AnchorLine; AC := ACarets[i].AnchorCol; BR := ACarets[i].Line; BC := ACarets[i].Col;
    end
    else
    begin
      AR := ACarets[i].Line; AC := ACarets[i].Col; BR := ACarets[i].AnchorLine; BC := ACarets[i].AnchorCol;
    end;
    if (AR <> BR) or (AC <> BC) then
      for R := AR to BR do
        Span(R + 1, IfThen(R = AR, AC + 1, 1), IfThen(R = BR, BC + 1, MaxInt div 2), False, Col);
    Span(ACarets[i].Line + 1, ACarets[i].Col + 1, ACarets[i].Col + 2, True, Col);
  end;
  if SynEdit <> nil then
    SynEdit.Invalidate;
end;

function TLedPeerMarkup.GetMarkupAttributeAtRowCol(const aRow: Integer; const aStartCol: TLazSynDisplayTokenBound;
  const AnRtlInfo: TLazSynDisplayRtlInfo): TSynSelectedColor;
var
  i: Integer;
begin
  Result := nil;
  for i := FCount - 1 downto 0 do     { a caret over a selection }
    if (FRows[i] = aRow) and (aStartCol.Logical >= FFrom[i]) and (aStartCol.Logical < FTo[i]) then
      Exit(FColors[i]);
end;

procedure TLedPeerMarkup.GetNextMarkupColAfterRowCol(const aRow: Integer; const aStartCol: TLazSynDisplayTokenBound;
  const AnRtlInfo: TLazSynDisplayRtlInfo; out ANextPhys, ANextLog: Integer);
var
  i: Integer;
begin
  ANextPhys := -1;
  ANextLog := -1;
  for i := 0 to FCount - 1 do
    if FRows[i] = aRow then
    begin
      if (FFrom[i] > aStartCol.Logical) and ((ANextLog < 0) or (FFrom[i] < ANextLog)) then
        ANextLog := FFrom[i];
      if (FTo[i] > aStartCol.Logical) and (FTo[i] < MaxInt div 2) and ((ANextLog < 0) or (FTo[i] < ANextLog)) then
        ANextLog := FTo[i];
    end;
end;

{ ---- a text tab's buffer shared ---- }

constructor TLedTextTarget.Create(AMaster: TSynEdit);
begin
  inherited Create;
  FMaster := AMaster;
  FViews := TList.Create;
  FMarkups := TList.Create;
end;

destructor TLedTextTarget.Destroy;
begin
  Close;
  while FViews.Count > 0 do
    RemoveView(TSynEdit(FViews[0]));
  inherited Destroy;    { which closes again: the lists still there for it }
  FViews.Free;
  FMarkups.Free;
end;

procedure TLedTextTarget.ForgetMaster;
begin
  Close;
  FViews.Clear;      { the views go with the buffer: their markups with them }
  FMarkups.Clear;
  FActive := nil;
  FMaster := nil;
end;

procedure TLedTextTarget.AddView(AView: TSynEdit);
var
  M: TLedPeerMarkup;
begin
  if (AView = nil) or (FViews.IndexOf(AView) >= 0) then
    Exit;
  FViews.Add(AView);
  M := TLedPeerMarkup.Create(AView);
  AView.MarkupManager.AddMarkUp(M);
  FMarkups.Add(M);
  M.SetCarets(FCarets);
  AView.RegisterCommandHandler(@Command, nil, [hcfPreExec]);
  if FActive = nil then
    FActive := AView;
end;

procedure TLedTextTarget.RemoveView(AView: TSynEdit);
var
  K: Integer;
begin
  K := FViews.IndexOf(AView);
  if K < 0 then
    Exit;
  AView.UnregisterCommandHandler(@Command);
  AView.MarkupManager.RemoveMarkUp(TLedPeerMarkup(FMarkups[K]));
  TLedPeerMarkup(FMarkups[K]).Free;
  FMarkups.Delete(K);
  FViews.Delete(K);
  if FActive = AView then
    if FViews.Count > 0 then
      FActive := TSynEdit(FViews[0])
    else
      FActive := nil;
end;

procedure TLedTextTarget.ForgetView(AView: TSynEdit);
var
  K: Integer;
begin
  K := FViews.IndexOf(AView);
  if K < 0 then
    Exit;
  FMarkups.Delete(K);
  FViews.Delete(K);
  if FActive = AView then
    if FViews.Count > 0 then
      FActive := TSynEdit(FViews[0])
    else
      FActive := nil;
end;

function TLedTextTarget.Open(Publish: Boolean; out Why: string): Boolean;
begin
  if FMaster = nil then
  begin
    Why := 'the text is gone';
    Exit(False);
  end;
  Result := inherited Open(Publish, Why);
  if Result then
    TLedSynAccess(FMaster).ViewedTextBuffer.AddEditHandler(@BufferEdited);
end;

procedure TLedTextTarget.Close;
var
  i: Integer;
begin
  if FMaster <> nil then
    TLedSynAccess(FMaster).ViewedTextBuffer.RemoveEditHandler(@BufferEdited);
  SetLength(FCarets, 0);
  for i := 0 to FMarkups.Count - 1 do
    TLedPeerMarkup(FMarkups[i]).SetCarets([]);
  SetEditorReadOnly(False);
  inherited Close;
end;

procedure TLedTextTarget.BufferEdited(Sender: TSynEditStrings; aLinePos, aBytePos, aCount, aLineBrkCnt: Integer;
  aText: String);
begin
  if not Applying then
    Changed(Max(0, aLinePos - 2));     { from the line before: a joined line was the one above }
end;

{ Undo and Redo in a shared text: this side's own edits, through the session, not the editor's own list
  (which the others' edits would leave pointing at the wrong places) }
procedure TLedTextTarget.Command(Sender: TObject; AfterProcessing: Boolean; var Handled: Boolean;
  var ACommand: TSynEditorCommand; var AChar: TUTF8Char; Data: Pointer; HandlerData: Pointer);
begin
  if (ACommand = ecUndo) or (ACommand = ecRedo) then
  begin
    Undo(ACommand = ecRedo);
    Handled := True;
    ACommand := ecNone;
  end
  else if Sender is TSynEdit then
    FActive := TSynEdit(Sender);    { the view typed in is the one whose caret the others see }
end;

function TLedTextTarget.PeerCaretCount: Integer;
begin
  Result := Length(FCarets);
end;

{ an empty buffer is one empty line, as an empty text is (SynEdit can hold none) }
function TLedTextTarget.LineCount: Integer;
begin
  Result := Max(1, TLedSynAccess(FMaster).TextBuffer.Count);
end;

function TLedTextTarget.GetLine(I: Integer): string;
begin
  if I < TLedSynAccess(FMaster).TextBuffer.Count then
    Result := TLedSynAccess(FMaster).TextBuffer[I]
  else
    Result := '';
end;

procedure TLedTextTarget.SetText(const S: string);
begin
  FMaster.Lines.Text := StringReplace(S, #10, LineEnding, [rfReplaceAll]);
  FMaster.ClearUndo;
end;

procedure TLedTextTarget.ReplaceRange(Line1, Col1, Line2, Col2: Integer; const S: string);
begin
  { through the master, so every view's caret and the folds follow; not an edit of this side's to undo }
  if FMaster.Lines.Count = 0 then
    FMaster.Lines.Add('');     { the empty line the text has, there to write in }
  FMaster.TextBetweenPointsEx[Point(Col1 + 1, Line1 + 1), Point(Col2 + 1, Line2 + 1), scamIgnore] :=
    StringReplace(S, #10, LineEnding, [rfReplaceAll]);
  FMaster.ClearUndo;
end;

procedure TLedTextTarget.GetCaret(out Line, Col, AnchorLine, AnchorCol: Integer);
var
  E: TSynEdit;
  C, A: TPoint;
begin
  E := FActive;
  if E = nil then
    E := FMaster;
  C := E.LogicalCaretXY;
  A := C;
  if E.SelAvail then
  begin   { the selection's other end }
    if (E.BlockBegin.Y = C.Y) and (E.BlockBegin.X = C.X) then
      A := E.BlockEnd
    else
      A := E.BlockBegin;
  end;
  Line := C.Y - 1;
  Col := C.X - 1;
  AnchorLine := A.Y - 1;
  AnchorCol := A.X - 1;
end;

procedure TLedTextTarget.ShowCarets(const Carets: array of TParadeTextCaret);
var
  i: Integer;
begin
  SetLength(FCarets, Length(Carets));
  for i := 0 to High(Carets) do
    FCarets[i] := Carets[i];
  for i := 0 to FMarkups.Count - 1 do
    TLedPeerMarkup(FMarkups[i]).SetCarets(FCarets);
end;

procedure TLedTextTarget.SetEditorReadOnly(AValue: Boolean);
var
  i: Integer;
begin
  if FMaster <> nil then
    FMaster.ReadOnly := AValue;
  for i := 0 to FViews.Count - 1 do
    TSynEdit(FViews[i]).ReadOnly := AValue;
end;

procedure TLedTextTarget.Poll;
begin
  if FMaster = nil then
    Exit;
  if Assigned(FOnPoll) then
    FOnPoll(Self);
  inherited Poll;
end;

{ ---- a text tab's session ---- }

constructor TLedTextSession.Create(ATab: TComponent);
begin
  inherited Create(ATab);
  FTab := ATab;
  FTarget := TLedTextTarget.Create(TLedTab(ATab).Document.Master);
  FTarget.OnPoll := @Polled;
  FTarget.Master.FreeNotification(Self);
  FSync := TParadeSync.CreateFor(Self, FTarget);     { the session owns the target from here }
  FSync.OutboxDir := IncludeTrailingPathDelimiter(LedConfigDir) + 'outbox';   { offline edits outlive a quit }
  FCollab := TLedCollab.Create(Self, FSync, lckText);
  Polled(nil);
end;

destructor TLedTextSession.Destroy;
begin
  if FSync <> nil then
    FSync.Stop;
  inherited Destroy;
end;

{ the tab's views bound (a split made since included), the one in front the caret the others see }
procedure TLedTextSession.Polled(Sender: TObject);
var
  i: Integer;
  T: TLedTab;
begin
  T := TLedTab(FTab);
  for i := 0 to T.ViewCount - 1 do
  begin
    FTarget.AddView(T.Views[i]);
    T.Views[i].FreeNotification(Self);    { a split closed: let go of its view }
  end;
  if T.ActiveView <> nil then
    FTarget.ActiveView := T.ActiveView;
end;

procedure TLedTextSession.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TSynEdit) and (FTarget <> nil) then
    if AComponent = FTarget.Master then
    begin
      if FSync <> nil then
        FSync.Stop;
      FTarget.ForgetMaster;
    end
    else
      FTarget.ForgetView(TSynEdit(AComponent));
end;

class function TLedTextSession.ForTab(ATab: TComponent): TLedTextSession;
var
  i: Integer;
begin
  Result := nil;
  if ATab = nil then
    Exit;
  for i := 0 to ATab.ComponentCount - 1 do
    if ATab.Components[i] is TLedTextSession then
      Exit(TLedTextSession(ATab.Components[i]));
end;

class function TLedTextSession.Ensure(ATab: TComponent): TLedTextSession;
begin
  Result := ForTab(ATab);
  if Result = nil then
    Result := TLedTextSession.Create(ATab);
end;

{ ---- a session and what is around it ---- }

constructor TLedCollab.Create(AOwner: TComponent; ASync: TParadeSync; AKind: TLedCollabKind);
begin
  inherited Create(AOwner);
  FSync := ASync;
  FKind := AKind;
  FSync.OnStateChange := @SyncChanged;
end;

function KindWord(AKind: TLedCollabKind): string;
begin
  if AKind = lckText then
    Result := 'text'
  else
    Result := '';
end;

procedure TLedCollab.SyncChanged(Sender: TObject);
begin
  if (FSync.State = pssOff) and FHosting then
  begin   { the shared document went (another one opened in the tab): hosting it ends }
    FHosting := False;
    HostRelease;
  end;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TLedCollab.Active: Boolean;
begin
  Result := FSync.State <> pssOff;
end;

function TLedCollab.Share(const ADoc: string): Boolean;
var
  Server, Doc, Token, Who: string;
begin
  Doc := ADoc;
  Result := LedAskConnection('Share this document', Server, Doc, Token, Who);
  if not Result then
    Exit;
  Result := FSync.Start(Server, Doc, Token, Who, True);
  if not Result then
    MessageDlg('Share', 'Could not share: ' + FSync.LastError, mtError, [mbOK], 0);
end;

function TLedCollab.JoinWith(const Server, Doc, Token, Who: string): Boolean;
begin
  Result := FSync.Start(Server, Doc, Token, Who, False);
  if not Result then
    MessageDlg('Join', 'Could not join: ' + FSync.LastError, mtError, [mbOK], 0);
end;

function TLedCollab.Host(const ADoc: string): Boolean;
var
  V: array of string;
  Ini: TIniFile;
  Doc, Who, Why, Url: string;
  Port: Integer;
  Everyone: Boolean;
begin
  Result := False;
  Ini := CollabIni;
  try
    SetLength(V, 4);
    V[0] := ADoc;
    if V[0] = '' then
      V[0] := Ini.ReadString('host', 'document', 'document');
    V[1] := Ini.ReadString('relay', 'name', GetEnvironmentVariable('USER'));
    V[2] := IntToStr(Ini.ReadInteger('host', 'port', 8765));
    V[3] := Ini.ReadString('host', 'network', 'yes');
    if not InputQuery('Host this document',
      ['Document name', 'Your name', 'Port', 'Let other machines in (yes / no: this machine only)'], V) or
      (Trim(V[0]) = '') then
      Exit;
    Doc := Trim(V[0]);
    Who := Trim(V[1]);
    Port := StrToIntDef(Trim(V[2]), 8765);
    Everyone := not SameText(Trim(V[3]), 'no');
    Ini.WriteString('host', 'document', Doc);
    Ini.WriteString('relay', 'name', Who);
    Ini.WriteInteger('host', 'port', Port);
    Ini.WriteString('host', 'network', BoolToStr(Everyone, 'yes', 'no'));
  finally
    Ini.Free;
  end;
  if not HostStart(Port, Everyone, Why) then
  begin
    MessageDlg('Host', 'Could not host: ' + Why, mtError, [mbOK], 0);
    Exit;
  end;
  Url := Format('http://127.0.0.1:%d', [Port]);
  if not FSync.Start(Url, Doc, ParadeMakeToken(HostRelay.Secret, Who, Doc, 'editor', 3650), Who, True) then
  begin
    { hosted here before: its log is still here, and it is what the others have }
    if (HostRelay.Store.Last(Doc) > 0) and (MessageDlg('Host', Format('"%s" was hosted here before. Open it as the ' +
      'others left it, in place of this tab''s text?', [Doc]), mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
    begin
      if not FSync.Start(Url, Doc, ParadeMakeToken(HostRelay.Secret, Who, Doc, 'editor', 3650), Who, False) then
      begin
        MessageDlg('Host', 'Could not open it: ' + FSync.LastError, mtError, [mbOK], 0);
        HostRelease;
        Exit;
      end;
    end
    else
    begin
      if HostRelay.Store.Last(Doc) = 0 then
        MessageDlg('Host', 'Could not share: ' + FSync.LastError, mtError, [mbOK], 0);
      HostRelease;
      Exit;
    end;
  end;
  FHosting := True;
  FHostDoc := Doc;
  if Everyone then
    FHostAddress := Format('http://%s:%d', [ThisHostName, Port])
  else
    FHostAddress := Url;
  SyncChanged(nil);
  Invite;
  Result := True;
end;

procedure TLedCollab.Leave;
begin
  FSync.Stop;     { SyncChanged lets the hosted relay go }
end;

function TLedCollab.StatusText: string;
begin
  if FSync.State = pssOff then
    Exit('');
  if FHosting then
    Result := 'hosting ' + FHostAddress + ', ' + ParadeSyncStateName(FSync.State)
  else
    Result := 'shared: ' + ParadeSyncStateName(FSync.State);
  if FSync.PeerCount > 0 then
    Result := Result + Format(', %d other(s) here', [FSync.PeerCount]);
end;

procedure TLedCollab.CopyClicked(Sender: TObject);
begin
  Clipboard.AsText := TButton(Sender).Hint;
  TButton(Sender).Caption := 'Copied';
end;

{ what the others need to join: a link for each role, which carries the relay, the document, a token and
  what kind of document it is }
procedure TLedCollab.Invite;
var
  F: TForm;
  M: TMemo;
  B: TButton;
  EditLink, ReadLink: string;

  procedure CopyButton(const ACaption, AText: string);
  var
    C: TButton;
  begin
    C := TButton.Create(F);
    C.Parent := F;
    C.Align := alBottom;
    C.Caption := ACaption;
    C.Hint := AText;
    C.OnClick := @CopyClicked;
  end;

begin
  if not FHosting or (HostRelay = nil) then
  begin
    MessageDlg('Invite', 'Invitations come from the LED that hosts the document (Host).', mtInformation, [mbOK], 0);
    Exit;
  end;
  EditLink := ParadeInviteLink(FHostAddress, FHostDoc, ParadeMakeToken(HostRelay.Secret, 'guest', FHostDoc, 'editor',
    30), KindWord(FKind));
  ReadLink := ParadeInviteLink(FHostAddress, FHostDoc, ParadeMakeToken(HostRelay.Secret, 'reader', FHostDoc, 'viewer',
    30), KindWord(FKind));
  F := TForm.CreateNew(nil);
  try
    F.Caption := 'Invite to "' + FHostDoc + '"';
    F.Position := poMainFormCenter;
    F.SetBounds(0, 0, LedScale96(720), LedScale96(360));
    M := TMemo.Create(F);
    M.Parent := F;
    M.Align := alClient;
    M.ReadOnly := True;
    M.WordWrap := True;
    M.ScrollBars := ssAutoVertical;
    M.Lines.Add('Send a link to whoever is to join: in their LED, File > Join Shared Document, and paste it. ' +
      'Each is good for 30 days; whoever has one can get in, so send it privately.');
    M.Lines.Add('');
    M.Lines.Add('To edit:');
    M.Lines.Add(EditLink);
    M.Lines.Add('');
    M.Lines.Add('To read only:');
    M.Lines.Add(ReadLink);
    M.Lines.Add('');
    M.Lines.Add('The document stays reachable while this LED shares it (until Leave).');
    CopyButton('Copy the link to read', ReadLink);
    CopyButton('Copy the link to edit', EditLink);
    B := TButton.Create(F);
    B.Parent := F;
    B.Align := alBottom;
    B.Caption := 'OK';
    B.ModalResult := mrOK;
    B.Default := True;
    F.ShowModal;
  finally
    F.Free;
  end;
end;

finalization
  FreeAndNil(HostRelay);
{$ENDIF}
end.
