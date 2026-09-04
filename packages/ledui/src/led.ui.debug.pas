{ led - a light editor.  The debugger: a pane, and the thing that drives it.

  Two classes with one job each.

  TLedDebugPane draws.  It shows the launch configurations, a row of
  execution buttons, and Locals, Call Stack and Watches stacked in resizable
  sections, and it turns clicks into events.  It knows nothing about gdb.

  TLedDebugger decides.  It owns the gdb session, the project, the list of
  breakpoints and the timer that pumps the protocol, and it puts the answers
  into the pane.  It knows nothing about menus or docking -- the main form
  hands it the callbacks it needs to open a file or write to the output pane,
  which is what keeps this unit out of the form and the form out of gdb.

  The console is the Output pane rather than one of its own.  medit built a
  second console because it had nothing else; led already has a pane that
  colours lines, buffers partial ones and turns file:line into a jump, and a
  debugger that reuses it costs no new widget and behaves like the rest of
  the editor. }
unit Led.UI.Debug;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, ComCtrls, StdCtrls, Forms, Graphics,
  Menus, ImgList,
  Led.Core.Gdb, Led.Core.Project, Led.UI.Edit;

type
  { What the toolbar asked for.  One event with a verb rather than eight
    events, because the main form's actions want the same list. }
  TLedDebugCommand = (ldcStart, ldcContinue, ldcPause, ldcStop,
                      ldcStepOver, ldcStepInto, ldcStepOut, ldcBuild);

  TLedDebugCommandEvent = procedure(Sender: TObject;
    ACommand: TLedDebugCommand) of object;
  TLedDebugFrameEvent = procedure(Sender: TObject; ALevel: Integer) of object;
  TLedDebugTextEvent = procedure(Sender: TObject; const AText: string) of object;
  TLedDebugJumpEvent = procedure(Sender: TObject; const AFileName: string;
    ALine: Integer) of object;
  { How the debugger reaches an open document, or nil when the file is not
    open.  Supplied by the main form; this unit does not know how tabs work. }
  TLedDebugViewLookup = function(const AFileName: string): TLedEdit of object;

  { TLedDebugPane }

  TLedDebugPane = class(TPanel)
  private
    FBar: TToolBar;
    FConfigs: TComboBox;
    FLocals: TListView;
    FStack: TListView;
    FWatches: TListView;
    FWatchEntry: TEdit;
    FCmdEntry: TEdit;
    FOnCommand: TLedDebugCommandEvent;
    FOnSelectFrame: TLedDebugFrameEvent;
    FOnAddWatch: TLedDebugTextEvent;
    FOnRemoveWatch: TLedDebugFrameEvent;
    FOnRawCommand: TLedDebugTextEvent;
    FOnConfigChanged: TNotifyEvent;
    procedure BarClick(Sender: TObject);
    procedure StackDouble(Sender: TObject);
    procedure WatchKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure WatchEntryKey(Sender: TObject; var Key: Char);
    procedure CmdEntryKey(Sender: TObject; var Key: Char);
    procedure ConfigChange(Sender: TObject);
    function AddButton(const ACaption, AHint: string; ACommand: TLedDebugCommand;
      AImage: Integer): TToolButton;
    function AddList(const ACols: array of string;
      const AWidths: array of Integer): TListView;
  public
    constructor Create(AOwner: TComponent); override;

    { The application's icons, passed in rather than reached for, so this
      unit does not depend on where they come from. }
    procedure SetImages(AImages: TCustomImageList; const AIndexes: array of Integer);

    procedure ShowLocals(const ALocals: TLedGdbLocals);
    procedure ShowFrames(const AFrames: TLedGdbFrames);
    procedure SetConfigNames(AList: TStrings; AActive: Integer);
    procedure SetWatch(AIndex: Integer; const AExpr, AValue: string;
      AIsError: Boolean);
    procedure ClearWatchValues;
    function WatchCount: Integer;
    function SelectedWatch: Integer;
    procedure AddWatchRow(const AExpr: string);
    procedure RemoveWatchRow(AIndex: Integer);
    procedure Clear;
    { Greys what cannot be done now, which is most of the toolbar most of the
      time -- stepping a program that is not stopped only produces errors. }
    procedure ReflectState(AState: TLedGdbState; AHasProject: Boolean);

    function ConfigIndex: Integer;
    property Locals: TListView read FLocals;
    property Stack: TListView read FStack;
    property Watches: TListView read FWatches;

    property OnCommand: TLedDebugCommandEvent read FOnCommand write FOnCommand;
    property OnSelectFrame: TLedDebugFrameEvent read FOnSelectFrame write FOnSelectFrame;
    property OnAddWatch: TLedDebugTextEvent read FOnAddWatch write FOnAddWatch;
    property OnRemoveWatch: TLedDebugFrameEvent read FOnRemoveWatch write FOnRemoveWatch;
    property OnRawCommand: TLedDebugTextEvent read FOnRawCommand write FOnRawCommand;
    property OnConfigChanged: TNotifyEvent read FOnConfigChanged write FOnConfigChanged;
  end;

  { TLedDebugger }

  TLedBreakpoint = record
    FileName: string;
    Line: Integer;
    Number: Integer;      // as gdb knows it, or -1 while it is still asking
  end;
  TLedBreakpoints = array of TLedBreakpoint;

  TLedDebugger = class(TComponent)
  private
    FSession: TLedGdbSession;
    FProject: TLedProject;
    FTimer: TTimer;
    FPane: TLedDebugPane;
    FBreaks: TLedBreakpoints;
    FWatchExprs: TStringList;
    FCurrentFile: string;
    FCurrentLine: Integer;
    FActiveFile: string;
    FTargetOverride: string;
    FPendingRun: Boolean;

    FOnJump: TLedDebugJumpEvent;
    FOnConsole: TLedDebugTextEvent;
    FOnStatus: TLedDebugTextEvent;
    FOnViewFor: TLedDebugViewLookup;
    FOnStateChanged: TNotifyEvent;

    procedure Tick(Sender: TObject);
    procedure SessionStopped(Sender: TObject; const AReason, AFileName: string;
      ALine: Integer; const AFunc: string);
    procedure SessionRunning(Sender: TObject);
    procedure SessionStateChanged(Sender: TObject);
    procedure SessionBreakAdded(Sender: TObject; ANumber: Integer;
      const AFileName: string; ALine: Integer);
    procedure SessionBreakRemoved(Sender: TObject; ANumber: Integer;
      const AFileName: string; ALine: Integer);
    procedure SessionLocals(Sender: TObject);
    procedure SessionFrames(Sender: TObject);
    procedure SessionEval(Sender: TObject; const ATag, AValue: string;
      AIsError: Boolean);
    procedure SessionText(Sender: TObject; const AText: string);
    procedure SessionError(Sender: TObject; const AText: string);

    procedure PaneCommand(Sender: TObject; ACommand: TLedDebugCommand);
    procedure PaneSelectFrame(Sender: TObject; ALevel: Integer);
    procedure PaneAddWatch(Sender: TObject; const AText: string);
    procedure PaneRemoveWatch(Sender: TObject; ALevel: Integer);
    procedure PaneRaw(Sender: TObject; const AText: string);
    procedure PaneConfigChanged(Sender: TObject);

    function IndexOfBreak(const AFileName: string; ALine: Integer): Integer;
    procedure PushMarksFor(const AFileName: string);
    procedure ClearDebugLine;
    procedure Say(const AText: string);
    function ActiveConfig: TLedLaunchConfig;
    function ResolvedTarget: string;
    procedure SendBreakpointsToGdb;
    procedure ReEvaluateWatches;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Attach(APane: TLedDebugPane);
    { Re-reads the project for the folder AFileName is in, and refreshes the
      configuration list.  Cheap and idempotent; called when the active tab
      changes. }
    procedure NoteActiveFile(const AFileName: string);

    function Start: Boolean;
    procedure Stop;
    procedure Command(ACommand: TLedDebugCommand);
    procedure ToggleBreakpoint(const AFileName: string; ALine: Integer);
    function BreakpointCount: Integer;
    function HasBreakpoint(const AFileName: string; ALine: Integer): Boolean;

    { Everything the main form needs to enable or disable a menu item. }
    function Running: Boolean;
    function Stopped: Boolean;
    function CanStep: Boolean;

    property Session: TLedGdbSession read FSession;
    property Project: TLedProject read FProject;
    property Pane: TLedDebugPane read FPane;
    property CurrentFile: string read FCurrentFile;
    property CurrentLine: Integer read FCurrentLine;
    { Overrides launch.json, for a folder that has none. }
    property TargetOverride: string read FTargetOverride write FTargetOverride;

    property OnJump: TLedDebugJumpEvent read FOnJump write FOnJump;
    property OnConsole: TLedDebugTextEvent read FOnConsole write FOnConsole;
    property OnStatus: TLedDebugTextEvent read FOnStatus write FOnStatus;
    property OnViewFor: TLedDebugViewLookup read FOnViewFor write FOnViewFor;
    property OnStateChanged: TNotifyEvent read FOnStateChanged write FOnStateChanged;
  end;

implementation

uses
  LCLType, LazFileUtils;

{ --- TLedDebugPane --------------------------------------------------------- }

constructor TLedDebugPane.Create(AOwner: TComponent);
var
  Body, Mid, Bottom: TPanel;
  Sp: TSplitter;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';

  FBar := TToolBar.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.EdgeBorders := [];
  FBar.ShowCaptions := False;
  FBar.Flat := True;
  FBar.AutoSize := True;

  { Built right to left: a TToolBar lays its children out in reverse order of
    creation unless each is given a Left, and giving them one hard-codes a
    width that stops being right the moment the icons scale. }
  AddButton('Build', 'Build the project'#13'Runs the configuration''s build command', ldcBuild, -1);
  AddButton('Breakpoint', 'Toggle breakpoint'#13'F9', ldcStop, -1);
  AddButton('Step Out', 'Step out'#13'Shift+F11', ldcStepOut, -1);
  AddButton('Step Into', 'Step into'#13'F11', ldcStepInto, -1);
  AddButton('Step Over', 'Step over'#13'F10', ldcStepOver, -1);
  AddButton('Stop', 'Stop debugging', ldcStop, -1);
  AddButton('Pause', 'Pause the program'#13'F6', ldcPause, -1);
  AddButton('Continue', 'Continue'#13'Ctrl+F8', ldcContinue, -1);
  AddButton('Start', 'Start debugging'#13'Ctrl+F5', ldcStart, -1);

  FConfigs := TComboBox.Create(Self);
  FConfigs.Parent := Self;
  FConfigs.Align := alTop;
  FConfigs.Style := csDropDownList;
  FConfigs.OnChange := @ConfigChange;
  FConfigs.Enabled := False;

  { Locals on top, then the stack, then the watches, each draggable.  Three
    stacked lists rather than a notebook because a debugger is read by
    glancing between them, and a tab hides two thirds of that. }
  Body := TPanel.Create(Self);
  Body.Parent := Self;
  Body.Align := alClient;
  Body.BevelOuter := bvNone;

  FLocals := AddList(['Name', 'Type', 'Value'], [90, 70, 120]);
  FLocals.Parent := Body;
  FLocals.Align := alTop;
  FLocals.Height := 150;

  Sp := TSplitter.Create(Self);
  Sp.Parent := Body;
  Sp.Align := alTop;
  Sp.MinSize := 40;
  Sp.Top := FLocals.Height + 1;

  Mid := TPanel.Create(Self);
  Mid.Parent := Body;
  Mid.Align := alClient;
  Mid.BevelOuter := bvNone;

  FStack := AddList(['#', 'Function', 'Location'], [28, 100, 150]);
  FStack.Parent := Mid;
  FStack.Align := alTop;
  FStack.Height := 130;
  FStack.OnDblClick := @StackDouble;

  Sp := TSplitter.Create(Self);
  Sp.Parent := Mid;
  Sp.Align := alTop;
  Sp.MinSize := 40;
  Sp.Top := FStack.Height + 1;

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Mid;
  Bottom.Align := alClient;
  Bottom.BevelOuter := bvNone;

  FWatchEntry := TEdit.Create(Self);
  FWatchEntry.Parent := Bottom;
  FWatchEntry.Align := alBottom;
  FWatchEntry.TextHint := 'Watch an expression, then Enter (Delete removes)';
  FWatchEntry.OnKeyPress := @WatchEntryKey;

  FWatches := AddList(['Expression', 'Value'], [110, 150]);
  FWatches.Parent := Bottom;
  FWatches.Align := alClient;
  FWatches.OnKeyDown := @WatchKey;

  FCmdEntry := TEdit.Create(Self);
  FCmdEntry.Parent := Self;
  FCmdEntry.Align := alBottom;
  FCmdEntry.TextHint := 'gdb command, e.g. info threads';
  FCmdEntry.OnKeyPress := @CmdEntryKey;

  ReflectState(lgsIdle, False);
end;

function TLedDebugPane.AddButton(const ACaption, AHint: string;
  ACommand: TLedDebugCommand; AImage: Integer): TToolButton;
begin
  Result := TToolButton.Create(Self);
  Result.Parent := FBar;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.ImageIndex := AImage;
  Result.Tag := Ord(ACommand);
  Result.OnClick := @BarClick;
end;

function TLedDebugPane.AddList(const ACols: array of string;
  const AWidths: array of Integer): TListView;
var
  i: Integer;
  C: TListColumn;
begin
  Result := TListView.Create(Self);
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Result.HideSelection := False;
  for i := 0 to High(ACols) do
  begin
    C := Result.Columns.Add;
    C.Caption := ACols[i];
    C.Width := AWidths[i];
  end;
end;

procedure TLedDebugPane.SetImages(AImages: TCustomImageList;
  const AIndexes: array of Integer);
var
  i: Integer;
begin
  FBar.Images := AImages;
  { The buttons were created back to front, so the indexes are applied the
    same way round as they were built. }
  for i := 0 to FBar.ButtonCount - 1 do
    if i <= High(AIndexes) then
      FBar.Buttons[i].ImageIndex := AIndexes[i];
end;

procedure TLedDebugPane.BarClick(Sender: TObject);
begin
  if Assigned(FOnCommand) then
    FOnCommand(Self, TLedDebugCommand(TToolButton(Sender).Tag));
end;

procedure TLedDebugPane.StackDouble(Sender: TObject);
begin
  if (FStack.Selected <> nil) and Assigned(FOnSelectFrame) then
    FOnSelectFrame(Self, FStack.Selected.Index);
end;

procedure TLedDebugPane.WatchKey(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_DELETE) and (FWatches.Selected <> nil) and
     Assigned(FOnRemoveWatch) then
  begin
    FOnRemoveWatch(Self, FWatches.Selected.Index);
    Key := 0;
  end;
end;

procedure TLedDebugPane.WatchEntryKey(Sender: TObject; var Key: Char);
begin
  if (Key = #13) and (Trim(FWatchEntry.Text) <> '') then
  begin
    if Assigned(FOnAddWatch) then FOnAddWatch(Self, Trim(FWatchEntry.Text));
    FWatchEntry.Text := '';
    Key := #0;
  end;
end;

procedure TLedDebugPane.CmdEntryKey(Sender: TObject; var Key: Char);
begin
  if (Key = #13) and (Trim(FCmdEntry.Text) <> '') then
  begin
    if Assigned(FOnRawCommand) then FOnRawCommand(Self, Trim(FCmdEntry.Text));
    FCmdEntry.Text := '';
    Key := #0;
  end;
end;

procedure TLedDebugPane.ConfigChange(Sender: TObject);
begin
  if Assigned(FOnConfigChanged) then FOnConfigChanged(Self);
end;

procedure TLedDebugPane.ShowLocals(const ALocals: TLedGdbLocals);
var
  i: Integer;
  It: TListItem;
begin
  FLocals.BeginUpdate;
  try
    FLocals.Items.Clear;
    for i := 0 to High(ALocals) do
    begin
      It := FLocals.Items.Add;
      It.Caption := ALocals[i].Name;
      It.SubItems.Add(ALocals[i].TypeName);
      It.SubItems.Add(ALocals[i].Value);
    end;
  finally
    FLocals.EndUpdate;
  end;
end;

procedure TLedDebugPane.ShowFrames(const AFrames: TLedGdbFrames);
var
  i: Integer;
  It: TListItem;
  Loc: string;
begin
  FStack.BeginUpdate;
  try
    FStack.Items.Clear;
    for i := 0 to High(AFrames) do
    begin
      It := FStack.Items.Add;
      It.Caption := IntToStr(AFrames[i].Level);
      It.SubItems.Add(AFrames[i].Func);
      if AFrames[i].FileName <> '' then
        Loc := ExtractFileName(AFrames[i].FileName) + ':' +
               IntToStr(AFrames[i].Line)
      else
        Loc := AFrames[i].Addr;
      It.SubItems.Add(Loc);
    end;
  finally
    FStack.EndUpdate;
  end;
end;

procedure TLedDebugPane.SetConfigNames(AList: TStrings; AActive: Integer);
begin
  FConfigs.Items.Assign(AList);
  FConfigs.Enabled := FConfigs.Items.Count > 0;
  if (AActive >= 0) and (AActive < FConfigs.Items.Count) then
    FConfigs.ItemIndex := AActive
  else if FConfigs.Items.Count > 0 then
    FConfigs.ItemIndex := 0;
end;

function TLedDebugPane.ConfigIndex: Integer;
begin
  Result := FConfigs.ItemIndex;
end;

procedure TLedDebugPane.AddWatchRow(const AExpr: string);
var
  It: TListItem;
begin
  It := FWatches.Items.Add;
  It.Caption := AExpr;
  It.SubItems.Add('');
end;

procedure TLedDebugPane.RemoveWatchRow(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FWatches.Items.Count) then
    FWatches.Items.Delete(AIndex);
end;

procedure TLedDebugPane.SetWatch(AIndex: Integer; const AExpr, AValue: string;
  AIsError: Boolean);
var
  It: TListItem;
begin
  if (AIndex < 0) or (AIndex >= FWatches.Items.Count) then Exit;
  It := FWatches.Items[AIndex];
  It.Caption := AExpr;
  if It.SubItems.Count = 0 then It.SubItems.Add('');
  { An expression that cannot be evaluated is shown with gdb's own wording
    rather than blanked, because "no symbol foo" is the answer. }
  if AIsError then
    It.SubItems[0] := '(' + AValue + ')'
  else
    It.SubItems[0] := AValue;
end;

procedure TLedDebugPane.ClearWatchValues;
var
  i: Integer;
begin
  for i := 0 to FWatches.Items.Count - 1 do
    if FWatches.Items[i].SubItems.Count > 0 then
      FWatches.Items[i].SubItems[0] := '';
end;

function TLedDebugPane.WatchCount: Integer;
begin
  Result := FWatches.Items.Count;
end;

function TLedDebugPane.SelectedWatch: Integer;
begin
  if FWatches.Selected = nil then Exit(-1);
  Result := FWatches.Selected.Index;
end;

procedure TLedDebugPane.Clear;
begin
  FLocals.Items.Clear;
  FStack.Items.Clear;
  ClearWatchValues;
end;

{ Greys what cannot be done now.  A debugger offers eight buttons of which
  at most four ever apply, and one that reports "the program is not running"
  when pressed is worse than one that is plainly unavailable. }
procedure TLedDebugPane.ReflectState(AState: TLedGdbState; AHasProject: Boolean);
var
  i: Integer;
  Live, AtRest: Boolean;
  B: TToolButton;
begin
  Live := AState in [lgsReady, lgsRunning, lgsStopped];
  AtRest := AState = lgsStopped;
  for i := 0 to FBar.ButtonCount - 1 do
  begin
    B := FBar.Buttons[i];
    case TLedDebugCommand(B.Tag) of
      ldcStart:    B.Enabled := AState in [lgsIdle, lgsReady, lgsStopped,
                                           lgsExited, lgsError];
      ldcContinue: B.Enabled := AtRest;
      ldcPause:    B.Enabled := AState = lgsRunning;
      ldcStop:     B.Enabled := Live;
      ldcStepOver, ldcStepInto, ldcStepOut:
                   B.Enabled := AtRest;
      ldcBuild:    B.Enabled := AHasProject;
    end;
  end;
  FCmdEntry.Enabled := Live;
end;

{ --- TLedDebugger ---------------------------------------------------------- }

constructor TLedDebugger.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSession := TLedGdbSession.Create;
  FSession.OnStopped := @SessionStopped;
  FSession.OnRunning := @SessionRunning;
  FSession.OnStateChanged := @SessionStateChanged;
  FSession.OnBreakAdded := @SessionBreakAdded;
  FSession.OnBreakRemoved := @SessionBreakRemoved;
  FSession.OnLocals := @SessionLocals;
  FSession.OnFrames := @SessionFrames;
  FSession.OnEval := @SessionEval;
  FSession.OnConsole := @SessionText;
  FSession.OnTarget := @SessionText;
  FSession.OnLog := @SessionText;
  FSession.OnError := @SessionError;

  FProject := TLedProject.Create;
  FWatchExprs := TStringList.Create;

  { 40 ms: fast enough that a step feels immediate, slow enough to cost
    nothing.  The protocol is drained here rather than waited on -- see the
    note at the top of Led.Core.Gdb. }
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 40;
  FTimer.Enabled := False;
  FTimer.OnTimer := @Tick;
end;

destructor TLedDebugger.Destroy;
begin
  FTimer.Enabled := False;
  FSession.Free;
  FProject.Free;
  FWatchExprs.Free;
  inherited Destroy;
end;

procedure TLedDebugger.Attach(APane: TLedDebugPane);
begin
  FPane := APane;
  if FPane = nil then Exit;
  FPane.OnCommand := @PaneCommand;
  FPane.OnSelectFrame := @PaneSelectFrame;
  FPane.OnAddWatch := @PaneAddWatch;
  FPane.OnRemoveWatch := @PaneRemoveWatch;
  FPane.OnRawCommand := @PaneRaw;
  FPane.OnConfigChanged := @PaneConfigChanged;
end;

procedure TLedDebugger.Say(const AText: string);
begin
  if Assigned(FOnConsole) then FOnConsole(Self, AText);
end;

procedure TLedDebugger.Tick(Sender: TObject);
begin
  FSession.Poll;
  if not FSession.Alive then FTimer.Enabled := False;
end;

{ --- project --- }

procedure TLedDebugger.NoteActiveFile(const AFileName: string);
var
  Names: TStringList;
  i: Integer;
begin
  FActiveFile := AFileName;
  if AFileName = '' then Exit;
  if (FProject.Root <> '') and
     (Pos(LowerCase(FProject.Root), LowerCase(AFileName)) = 1) then Exit;

  FProject.LoadFrom(AFileName);
  if FPane = nil then Exit;

  Names := TStringList.Create;
  try
    for i := 0 to FProject.ConfigCount - 1 do
      Names.Add(FProject[i].Name);
    FPane.SetConfigNames(Names, 0);
  finally
    Names.Free;
  end;
end;

function TLedDebugger.ActiveConfig: TLedLaunchConfig;
var
  i: Integer;
begin
  Result := nil;
  if FProject.ConfigCount = 0 then Exit;
  i := 0;
  if FPane <> nil then i := FPane.ConfigIndex;
  if (i < 0) or (i >= FProject.ConfigCount) then i := 0;
  Result := FProject[i];
end;

function TLedDebugger.ResolvedTarget: string;
var
  C: TLedLaunchConfig;
begin
  Result := '';
  C := ActiveConfig;
  if (C <> nil) and (C.Program_ <> '') then
    Result := FProject.Resolve(C.Program_, FActiveFile)
  else if FTargetOverride <> '' then
    Result := FTargetOverride
  else if FActiveFile <> '' then
    { The last resort medit uses too: a source's name without its extension
      is what gcc produces by default often enough to be worth trying. }
    Result := ChangeFileExt(FActiveFile, '');

  if (Result <> '') and (not FilenameIsAbsolute(Result)) then
  begin
    if FProject.Root <> '' then
      Result := IncludeTrailingPathDelimiter(FProject.Root) + Result
    else if FActiveFile <> '' then
      Result := IncludeTrailingPathDelimiter(ExtractFileDir(FActiveFile)) + Result;
  end;
end;

{ --- breakpoints --- }

function TLedDebugger.IndexOfBreak(const AFileName: string;
  ALine: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FBreaks) do
    if (FBreaks[i].Line = ALine) and
       SameFileName(FBreaks[i].FileName, AFileName) then Exit(i);
  Result := -1;
end;

function TLedDebugger.HasBreakpoint(const AFileName: string;
  ALine: Integer): Boolean;
begin
  Result := IndexOfBreak(AFileName, ALine) >= 0;
end;

function TLedDebugger.BreakpointCount: Integer;
begin
  Result := Length(FBreaks);
end;

procedure TLedDebugger.PushMarksFor(const AFileName: string);
var
  V: TLedEdit;
  Lines: array of Integer;
  i, n: Integer;
begin
  if not Assigned(FOnViewFor) then Exit;
  V := FOnViewFor(AFileName);
  if V = nil then Exit;
  SetLength(Lines, Length(FBreaks));
  n := 0;
  for i := 0 to High(FBreaks) do
    if SameFileName(FBreaks[i].FileName, AFileName) then
    begin
      Lines[n] := FBreaks[i].Line;
      Inc(n);
    end;
  SetLength(Lines, n);
  V.SetBreakpointLines(Lines);
end;

procedure TLedDebugger.ToggleBreakpoint(const AFileName: string;
  ALine: Integer);
var
  i, n: Integer;
begin
  if (AFileName = '') or (ALine <= 0) then Exit;
  i := IndexOfBreak(AFileName, ALine);
  if i >= 0 then
  begin
    if (FBreaks[i].Number > 0) and FSession.Alive then
      FSession.BreakDelete(FBreaks[i].Number);
    for n := i to High(FBreaks) - 1 do FBreaks[n] := FBreaks[n + 1];
    SetLength(FBreaks, Length(FBreaks) - 1);
  end
  else
  begin
    n := Length(FBreaks);
    SetLength(FBreaks, n + 1);
    FBreaks[n].FileName := AFileName;
    FBreaks[n].Line := ALine;
    FBreaks[n].Number := -1;
    { Sent now when gdb is up, and replayed at Start when it is not, so a
      breakpoint can be set before anything is running. }
    if FSession.Alive then FSession.BreakInsert(AFileName, ALine);
  end;
  PushMarksFor(AFileName);
end;

procedure TLedDebugger.SendBreakpointsToGdb;
var
  i: Integer;
begin
  for i := 0 to High(FBreaks) do
  begin
    FBreaks[i].Number := -1;
    FSession.BreakInsert(FBreaks[i].FileName, FBreaks[i].Line);
  end;
end;

{ --- session events --- }

procedure TLedDebugger.SessionBreakAdded(Sender: TObject; ANumber: Integer;
  const AFileName: string; ALine: Integer);
var
  i: Integer;
begin
  i := IndexOfBreak(AFileName, ALine);
  if i >= 0 then
    FBreaks[i].Number := ANumber
  else if (AFileName <> '') and (ALine > 0) then
  begin
    { Created from the gdb command box rather than from the gutter.  Adopted,
      so the dot appears where gdb says the breakpoint is. }
    i := Length(FBreaks);
    SetLength(FBreaks, i + 1);
    FBreaks[i].FileName := AFileName;
    FBreaks[i].Line := ALine;
    FBreaks[i].Number := ANumber;
  end;
  PushMarksFor(AFileName);
end;

procedure TLedDebugger.SessionBreakRemoved(Sender: TObject; ANumber: Integer;
  const AFileName: string; ALine: Integer);
var
  i, n: Integer;
  Gone: string;
begin
  for i := 0 to High(FBreaks) do
    if FBreaks[i].Number = ANumber then
    begin
      Gone := FBreaks[i].FileName;
      for n := i to High(FBreaks) - 1 do FBreaks[n] := FBreaks[n + 1];
      SetLength(FBreaks, Length(FBreaks) - 1);
      PushMarksFor(Gone);
      Exit;
    end;
end;

procedure TLedDebugger.ClearDebugLine;
var
  V: TLedEdit;
begin
  if (FCurrentFile <> '') and Assigned(FOnViewFor) then
  begin
    V := FOnViewFor(FCurrentFile);
    if V <> nil then V.DebugLine := 0;
  end;
  FCurrentFile := '';
  FCurrentLine := 0;
end;

procedure TLedDebugger.SessionRunning(Sender: TObject);
begin
  ClearDebugLine;
  if FPane <> nil then FPane.Clear;
  if Assigned(FOnStateChanged) then FOnStateChanged(Self);
end;

procedure TLedDebugger.SessionStopped(Sender: TObject;
  const AReason, AFileName: string; ALine: Integer; const AFunc: string);
var
  V: TLedEdit;
begin
  ClearDebugLine;

  if Pos('exited', AReason) > 0 then
  begin
    Say('[gdb] the program exited (' + AReason + ')');
    if FPane <> nil then FPane.Clear;
    if Assigned(FOnStateChanged) then FOnStateChanged(Self);
    Exit;
  end;

  FCurrentFile := AFileName;
  FCurrentLine := ALine;

  { Opened and shown before the mark is set, because the view has to exist
    for there to be a gutter to put it in. }
  if (AFileName <> '') and (ALine > 0) then
  begin
    if FileExists(AFileName) then
    begin
      if Assigned(FOnJump) then FOnJump(Self, AFileName, ALine);
      if Assigned(FOnViewFor) then
      begin
        V := FOnViewFor(AFileName);
        if V <> nil then
        begin
          V.DebugLine := ALine;
          PushMarksFor(AFileName);
        end;
      end;
    end
    else
      { glibc internals and anything else built elsewhere.  Said rather than
        offered as a file-not-found dialog. }
      Say(Format('[gdb] stopped in %s at %s:%d (no source here)',
        [AFunc, AFileName, ALine]));
  end;

  FSession.RequestLocals;
  FSession.RequestFrames;
  ReEvaluateWatches;
  if Assigned(FOnStateChanged) then FOnStateChanged(Self);
end;

procedure TLedDebugger.SessionStateChanged(Sender: TObject);
begin
  if FPane <> nil then
    FPane.ReflectState(FSession.State, FProject.ConfigCount > 0);
  if Assigned(FOnStateChanged) then FOnStateChanged(Self);
end;

procedure TLedDebugger.SessionLocals(Sender: TObject);
begin
  if FPane <> nil then FPane.ShowLocals(FSession.Locals);
end;

procedure TLedDebugger.SessionFrames(Sender: TObject);
begin
  if FPane <> nil then FPane.ShowFrames(FSession.Frames);
end;

procedure TLedDebugger.ReEvaluateWatches;
var
  i: Integer;
begin
  for i := 0 to FWatchExprs.Count - 1 do
    FSession.Evaluate(FWatchExprs[i], 'w:' + IntToStr(i));
end;

procedure TLedDebugger.SessionEval(Sender: TObject; const ATag, AValue: string;
  AIsError: Boolean);
var
  Idx: Integer;
begin
  if (FPane = nil) or (Copy(ATag, 1, 2) <> 'w:') then Exit;
  Idx := StrToIntDef(Copy(ATag, 3, Length(ATag)), -1);
  if (Idx < 0) or (Idx >= FWatchExprs.Count) then Exit;
  FPane.SetWatch(Idx, FWatchExprs[Idx], AValue, AIsError);
end;

procedure TLedDebugger.SessionText(Sender: TObject; const AText: string);
begin
  Say(AText);
end;

procedure TLedDebugger.SessionError(Sender: TObject; const AText: string);
begin
  Say('[gdb] ' + AText);
end;

{ --- pane events --- }

procedure TLedDebugger.PaneCommand(Sender: TObject; ACommand: TLedDebugCommand);
begin
  Command(ACommand);
end;

procedure TLedDebugger.PaneSelectFrame(Sender: TObject; ALevel: Integer);
var
  F: TLedGdbFrames;
begin
  F := FSession.Frames;
  if (ALevel < 0) or (ALevel > High(F)) then Exit;
  FSession.SelectFrame(F[ALevel].Level);
  FSession.RequestLocals;
  if (F[ALevel].FileName <> '') and (F[ALevel].Line > 0) and
     FileExists(F[ALevel].FileName) and Assigned(FOnJump) then
    FOnJump(Self, F[ALevel].FileName, F[ALevel].Line);
end;

procedure TLedDebugger.PaneAddWatch(Sender: TObject; const AText: string);
begin
  FWatchExprs.Add(AText);
  if FPane <> nil then FPane.AddWatchRow(AText);
  FSession.Evaluate(AText, 'w:' + IntToStr(FWatchExprs.Count - 1));
end;

procedure TLedDebugger.PaneRemoveWatch(Sender: TObject; ALevel: Integer);
begin
  if (ALevel < 0) or (ALevel >= FWatchExprs.Count) then Exit;
  FWatchExprs.Delete(ALevel);
  if FPane <> nil then FPane.RemoveWatchRow(ALevel);
  { The tags carry indexes, so everything after the hole has moved. }
  ReEvaluateWatches;
end;

procedure TLedDebugger.PaneRaw(Sender: TObject; const AText: string);
begin
  Say('(gdb) ' + AText);
  if FSession.Alive then
    FSession.SendRaw(AText)
  else
    Say('[gdb] no session; press Start first');
end;

procedure TLedDebugger.PaneConfigChanged(Sender: TObject);
begin
  { Nothing to do until Start: the configuration is read when the target is
    resolved, so switching it mid-session would only confuse. }
end;

{ --- commands --- }

function TLedDebugger.Start: Boolean;
var
  Target, Dir: string;
  C: TLedLaunchConfig;
  i: Integer;
  Args: TStringList;
begin
  Result := False;

  if not LedGdbAvailable then
  begin
    Say('[gdb] gdb is not installed, or not on PATH');
    Exit;
  end;

  if FSession.Alive and (FSession.State = lgsStopped) then
  begin
    { Already sitting at a stop: Start means carry on. }
    FSession.ExecContinue;
    Exit(True);
  end;

  Target := ResolvedTarget;
  if Target = '' then
  begin
    Say('[gdb] nothing to debug: name a program in .led/launch.json, ' +
        'or open the source you built');
    Exit;
  end;
  if not FileExists(Target) then
  begin
    Say(Format('[gdb] %s does not exist -- build it first ' +
               '(gcc -g -O0 source.c -o %s)',
               [Target, ExtractFileName(Target)]));
    Exit;
  end;

  if not FSession.Alive then
  begin
    if not FSession.Start then
    begin
      Say('[gdb] ' + FSession.LastError);
      Exit;
    end;
    FTimer.Enabled := True;
  end;

  Say('[gdb] debugging ' + Target);
  FSession.SetTarget(Target);

  C := ActiveConfig;
  Dir := '';
  if (C <> nil) and (C.Cwd <> '') then
    Dir := FProject.Resolve(C.Cwd, FActiveFile)
  else if FProject.Root <> '' then
    Dir := FProject.Root
  else
    Dir := ExtractFileDir(Target);
  FSession.SetWorkingDir(Dir);

  Args := TStringList.Create;
  try
    if C <> nil then
      for i := 0 to C.Args.Count - 1 do
        Args.Add(FProject.Resolve(C.Args[i], FActiveFile));
    FSession.SetArguments(Args);
  finally
    Args.Free;
  end;

  if C <> nil then
    for i := 0 to C.Environment.Count - 1 do
      FSession.SetEnvironmentVar(C.Environment.Names[i],
        FProject.Resolve(C.Environment.ValueFromIndex[i], FActiveFile));

  SendBreakpointsToGdb;
  FSession.ExecRun;
  Result := True;
end;

procedure TLedDebugger.Stop;
begin
  ClearDebugLine;
  FTimer.Enabled := False;
  FSession.Quit;
  if FPane <> nil then FPane.Clear;
  Say('[gdb] session ended');
  if Assigned(FOnStateChanged) then FOnStateChanged(Self);
end;

procedure TLedDebugger.Command(ACommand: TLedDebugCommand);
begin
  case ACommand of
    ldcStart: Start;
    ldcStop: Stop;
    ldcContinue: if FSession.Alive then FSession.ExecContinue;
    ldcPause: if FSession.Alive then FSession.ExecInterrupt;
    ldcStepOver: if CanStep then FSession.ExecNext;
    ldcStepInto: if CanStep then FSession.ExecStep;
    ldcStepOut: if CanStep then FSession.ExecFinish;
    ldcBuild: ;   { the main form runs builds; it owns the tool runner }
  end;
end;

function TLedDebugger.Running: Boolean;
begin
  Result := FSession.Alive and (FSession.State = lgsRunning);
end;

function TLedDebugger.Stopped: Boolean;
begin
  Result := FSession.Alive and (FSession.State = lgsStopped);
end;

function TLedDebugger.CanStep: Boolean;
begin
  Result := Stopped and FSession.InferiorAlive;
end;

end.
