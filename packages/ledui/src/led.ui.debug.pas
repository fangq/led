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
  { One row of the Locals tree.

    Held in an object hung off the node rather than in the node's text,
    because a drill-down is answered asynchronously and the answer has to
    find the row that asked.  Serial is what the request carries: the tree is
    rebuilt on every stop, so a reply for a serial that is no longer listed is
    a reply about a frame that has gone, and is dropped. }
  TLedLocalNode = class
    Serial: Integer;
    VarObj: string;       // gdb's handle, once one has been made
    Expr: string;         // what to ask gdb about, for a top-level row
    Loaded: Boolean;      // children already fetched
    Requested: Boolean;   // ...or on their way
  end;

  { What the toolbar asked for.  One event with a verb rather than eight
    events, because the main form's actions want the same list. }
  TLedDebugCommand = (ldcStart, ldcContinue, ldcPause, ldcStop,
                      ldcStepOver, ldcStepInto, ldcStepOut, ldcBuild,
                      ldcToggleBreakpoint);

  TLedDebugCommandEvent = procedure(Sender: TObject;
    ACommand: TLedDebugCommand) of object;
  TLedDebugFrameEvent = procedure(Sender: TObject; ALevel: Integer) of object;
  TLedDebugTextEvent = procedure(Sender: TObject; const AText: string) of object;
  TLedDebugJumpEvent = procedure(Sender: TObject; const AFileName: string;
    ALine: Integer) of object;
  { How the debugger reaches an open document, or nil when the file is not
    open.  Supplied by the main form; this unit does not know how tabs work. }
  TLedDebugViewLookup = function(const AFileName: string): TLedEdit of object;
  { ASerial identifies the row; AVarObj is '' when gdb has no handle for it
    yet and AExpr must be used to make one. }
  TLedDebugExpandEvent = procedure(Sender: TObject; ASerial: Integer;
    const AExpr, AVarObj: string) of object;

  { TLedDebugPane }

  TLedDebugPane = class(TPanel)
  private
    FBar: TToolBar;
    FConfigs: TComboBox;
    FLocals: TTreeView;
    FLocalNodes: TFPList;      // of TLedLocalNode, owned
    FNextSerial: Integer;
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
    FOnExpandLocal: TLedDebugExpandEvent;
    procedure BarClick(Sender: TObject);
    procedure StackDouble(Sender: TObject);
    procedure WatchKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure WatchEntryKey(Sender: TObject; var Key: Char);
    procedure CmdEntryKey(Sender: TObject; var Key: Char);
    procedure ConfigChange(Sender: TObject);
    procedure LocalsExpanding(Sender: TObject; Node: TTreeNode;
      var AllowExpansion: Boolean);
    function NewLocalNode(const AExpr, AVarObj: string): TLedLocalNode;
    function LocalNodeBySerial(ASerial: Integer): TLedLocalNode;
    procedure ClearLocalNodes;
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
    { Fills in a row's children once gdb has answered.  ASerial identifies the
      row; an unknown one is ignored. }
    procedure SetLocalChildren(ASerial: Integer;
      const AChildren: TLedGdbVarChildren);
    procedure SetLocalVarObj(ASerial: Integer; const AVarObj: string;
      ANumChild: Integer);
    function LocalRowCount: Integer;
    procedure ShowFrames(const AFrames: TLedGdbFrames);
    procedure SetConfigNames(AList: TStrings; AActive: Integer);
    procedure SetWatch(AIndex: Integer; const AExpr, AValue: string;
      AIsError: Boolean);
    procedure ClearWatchValues;
    function WatchCount: Integer;
    function SelectedWatch: Integer;
    { Types an expression into the watch box and presses Enter, so a test
      goes through the widget rather than the event behind it. }
    procedure TypeWatch(const AExpr: string);
    procedure AddWatchRow(const AExpr: string);
    procedure RemoveWatchRow(AIndex: Integer);
    procedure Clear;
    { Greys what cannot be done now, which is most of the toolbar most of the
      time -- stepping a program that is not stopped only produces errors. }
    procedure ReflectState(AState: TLedGdbState; AHasProject: Boolean);

    function ConfigIndex: Integer;
    { The toolbar itself, so a test can press the button rather than raise
      the event the button happens to raise. }
    property Bar: TToolBar read FBar;
    property Locals: TTreeView read FLocals;
    property Stack: TListView read FStack;
    property Watches: TListView read FWatches;

    property OnCommand: TLedDebugCommandEvent read FOnCommand write FOnCommand;
    property OnSelectFrame: TLedDebugFrameEvent read FOnSelectFrame write FOnSelectFrame;
    property OnAddWatch: TLedDebugTextEvent read FOnAddWatch write FOnAddWatch;
    property OnRemoveWatch: TLedDebugFrameEvent read FOnRemoveWatch write FOnRemoveWatch;
    property OnRawCommand: TLedDebugTextEvent read FOnRawCommand write FOnRawCommand;
    property OnConfigChanged: TNotifyEvent read FOnConfigChanged write FOnConfigChanged;
    { A row was opened and needs filling.  Carries the serial, and either the
      expression (no varobj yet) or the varobj. }
    property OnExpandLocal: TLedDebugExpandEvent
      read FOnExpandLocal write FOnExpandLocal;
  end;

  { TLedDebugger }

  { One row of the breakpoint list: a line breakpoint or a watchpoint.  Kept
    in one array for the same reason gdb keeps them in one number space --
    everything that acts on a breakpoint acts on a watchpoint too. }
  TLedBreakpoint = record
    Kind: TLedGdbBreakKind;
    FileName: string;     // line breakpoints only
    Line: Integer;        // line breakpoints only
    Expression: string;   // watchpoints only
    Number: Integer;      // as gdb knows it, or -1 while it is still asking
    Condition: string;    // '' for one that always fires
    Enabled: Boolean;
    HitCount: Integer;
  end;
  TLedBreakpoints = array of TLedBreakpoint;

  { The buttons on the breakpoint pane's toolbar, in the order SetImages
    expects their icons.  A tag rather than a position, because a TToolBar
    lists its buttons in the order they were created and they are created in
    reverse so they read left to right. }
  TLedBreakButton = (lbbEnable, lbbCondition, lbbRemove, lbbRemoveAll);

  TLedBreakRowEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  TLedBreakAddEvent = procedure(Sender: TObject; const AExpression: string;
    AKind: TLedGdbBreakKind) of object;

  { TLedBreakPane -- every breakpoint and watchpoint in one list.

    Its own pane rather than a fourth section of the debugger pane: the three
    sections there are read by glancing between them while stepping, and this
    is not that.  It is a list one goes to in order to change something --
    disable a breakpoint, see why one is not firing, watch a variable -- and
    it wants width, which is what the bottom edge has and the right edge has
    not. }
  TLedBreakPane = class(TPanel)
  private
    FList: TListView;
    FBar: TToolBar;
    FEntry: TEdit;
    FKind: TComboBox;
    FFilling: Boolean;
    FOnJump: TLedBreakRowEvent;
    FOnRemove: TLedBreakRowEvent;
    FOnToggleEnabled: TLedBreakRowEvent;
    FOnEditCondition: TLedBreakRowEvent;
    FOnRemoveAll: TNotifyEvent;
    FOnAddWatchpoint: TLedBreakAddEvent;
    procedure ListDouble(Sender: TObject);
    procedure ListKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EntryKey(Sender: TObject; var Key: Char);
    procedure RemoveClick(Sender: TObject);
    procedure RemoveAllClick(Sender: TObject);
    procedure EnableClick(Sender: TObject);
    procedure ConditionClick(Sender: TObject);
    function AddButton(const ACaption, AHint: string;
      AOnClick: TNotifyEvent; ATag: Integer): TToolButton;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetImages(AImages: TCustomImageList; const AIndexes: array of Integer);
    { Redraws the whole list.  Cheap -- there are never many -- and it keeps
      the selection where it was, which a rebuild otherwise loses. }
    procedure ShowBreakpoints(const ABreaks: TLedBreakpoints);
    function RowCount: Integer;
    function RowText(AIndex, AColumn: Integer): string;
    function Selected: Integer;
    procedure Select(AIndex: Integer);
    { For the self-test, and for anything else that wants to add a watchpoint
      without typing into the box. }
    procedure TypeWatchpoint(const AExpression: string; AKind: TLedGdbBreakKind);

    property List: TListView read FList;
    property OnJump: TLedBreakRowEvent read FOnJump write FOnJump;
    property OnRemove: TLedBreakRowEvent read FOnRemove write FOnRemove;
    property OnToggleEnabled: TLedBreakRowEvent
      read FOnToggleEnabled write FOnToggleEnabled;
    property OnEditCondition: TLedBreakRowEvent
      read FOnEditCondition write FOnEditCondition;
    property OnRemoveAll: TNotifyEvent read FOnRemoveAll write FOnRemoveAll;
    property OnAddWatchpoint: TLedBreakAddEvent
      read FOnAddWatchpoint write FOnAddWatchpoint;
  end;

  TLedDebugger = class(TComponent)
  private
    FSession: TLedGdbSession;
    FProject: TLedProject;
    FTimer: TTimer;
    FPane: TLedDebugPane;
    FBreakPane: TLedBreakPane;
    FBreaks: TLedBreakpoints;
    FWatchExprs: TStringList;
    { What has already been asked about at this stop, so moving the pointer
      back over something does not ask again.  Emptied on every resume,
      because the values belong to the frame. }
    FHoverCache: TStringList;
    { Expressions gdb has already refused.  Cleared with the cache, because a
      name that is a type here may be a variable in the next frame. }
    FHoverBad: TStringList;
    FHoverView: TLedEdit;
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
    FOnEditCondition: TLedDebugJumpEvent;
    FOnToggleBreakpoint: TNotifyEvent;
    FOnCommand: TLedDebugCommandEvent;

    procedure Tick(Sender: TObject);
    procedure SessionStopped(Sender: TObject; const AReason, AFileName: string;
      ALine: Integer; const AFunc: string);
    procedure SessionRunning(Sender: TObject);
    procedure SessionStateChanged(Sender: TObject);
    procedure SessionBreakAdded(Sender: TObject; const AInfo: TLedGdbBreakInfo);
    procedure SessionBreakRemoved(Sender: TObject; ANumber: Integer);
    procedure SessionWatchHit(Sender: TObject; ANumber: Integer;
      const AExpression, AOldValue, ANewValue: string);
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
    procedure PaneExpandLocal(Sender: TObject; ASerial: Integer;
      const AExpr, AVarObj: string);
    procedure SessionVarCreated(Sender: TObject; const ATag, AVarObj,
      ATypeName, AValue: string; ANumChild: Integer);
    procedure SessionVarChildren(Sender: TObject; const ATag: string;
      const AChildren: TLedGdbVarChildren);

    function IndexOfBreak(const AFileName: string; ALine: Integer): Integer;
    function IndexOfNumber(ANumber: Integer): Integer;
    function IndexOfPendingWatch(const AExpression: string): Integer;
    function NewBreakRow: Integer;
    procedure DropBreakRow(AIndex: Integer);
    procedure PushMarksFor(const AFileName: string);
    { Repaints the breakpoint list, and the gutter of whatever the row
      touches.  Called from everything that changes FBreaks, because a list
      that is right only after the next stop is worse than none. }
    procedure RefreshBreakList;
    procedure BreakPaneJump(Sender: TObject; AIndex: Integer);
    procedure BreakPaneRemove(Sender: TObject; AIndex: Integer);
    procedure BreakPaneToggle(Sender: TObject; AIndex: Integer);
    procedure BreakPaneCondition(Sender: TObject; AIndex: Integer);
    procedure BreakPaneRemoveAll(Sender: TObject);
    procedure BreakPaneAddWatchpoint(Sender: TObject; const AExpression: string;
      AKind: TLedGdbBreakKind);
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
    procedure AttachBreakPane(APane: TLedBreakPane);
    { Re-reads the project for the folder AFileName is in, and refreshes the
      configuration list.  Cheap and idempotent; called when the active tab
      changes. }
    procedure NoteActiveFile(const AFileName: string);

    function Start: Boolean;
    procedure Stop;
    procedure Command(ACommand: TLedDebugCommand);
    procedure ToggleBreakpoint(const AFileName: string; ALine: Integer);
    { Sets, changes or -- with an empty expression -- clears the condition on
      the breakpoint at AFileName:ALine, creating one if there is none. }
    procedure SetBreakpointCondition(const AFileName: string; ALine: Integer;
      const ACondition: string);
    function BreakpointCondition(const AFileName: string;
      ALine: Integer): string;
    { Runs on to a line without stopping at anything between. }
    procedure RunToCursor(const AFileName: string; ALine: Integer);
    { Hover-to-inspect.  Answers from the cache at once when it can, so a
      value the pointer has already been over appears without a round trip. }
    procedure HoverExpression(AView: TLedEdit; const AExpr: string);
    function BreakpointCount: Integer;
    function HasBreakpoint(const AFileName: string; ALine: Integer): Boolean;
    { A copy of a row, for anything that wants to read the list without
      being able to corrupt it. }
    function Breakpoint(AIndex: Integer): TLedBreakpoint;
    { Stops the program when AExpression changes, is read, or either.

      Remembered whether or not gdb takes it, and replayed at the next Start,
      so a watchpoint on a global can be set before anything is running --
      one on a local cannot, and gdb says so. }
    procedure AddWatchpoint(const AExpression: string;
      AKind: TLedGdbBreakKind = lgbWatch);
    procedure RemoveBreakpoint(AIndex: Integer);
    procedure RemoveAllBreakpoints;
    procedure SetBreakpointEnabled(AIndex: Integer; AEnabled: Boolean);

    { Everything the main form needs to enable or disable a menu item. }
    function Running: Boolean;
    function Stopped: Boolean;
    function CanStep: Boolean;

    property Session: TLedGdbSession read FSession;
    property Project: TLedProject read FProject;
    property Pane: TLedDebugPane read FPane;
    { Where the program to debug is, resolved from the configuration or
      guessed from the open file.  Public so the form can ask whether it
      needs rebuilding before a launch. }
    function TargetPath: string;
    property CurrentFile: string read FCurrentFile;
    property CurrentLine: Integer read FCurrentLine;
    { Overrides launch.json, for a folder that has none. }
    property TargetOverride: string read FTargetOverride write FTargetOverride;

    property OnJump: TLedDebugJumpEvent read FOnJump write FOnJump;
    property OnConsole: TLedDebugTextEvent read FOnConsole write FOnConsole;
    property OnStatus: TLedDebugTextEvent read FOnStatus write FOnStatus;
    property OnViewFor: TLedDebugViewLookup read FOnViewFor write FOnViewFor;
    property OnStateChanged: TNotifyEvent read FOnStateChanged write FOnStateChanged;
    { The breakpoint list asked for a condition to be edited.  Raised rather
      than prompted for here: the dialog belongs to the main form, which
      already has one for the same job on the caret's line. }
    property OnEditCondition: TLedDebugJumpEvent
      read FOnEditCondition write FOnEditCondition;
    { The pane's Breakpoint button was pressed.  Raised for the same reason
      as OnEditCondition: it is a question about the caret. }
    property OnToggleBreakpoint: TNotifyEvent
      read FOnToggleBreakpoint write FOnToggleBreakpoint;
    { A toolbar button in the pane was pressed.  When the window takes this
      the button does exactly what the menu item does; when nothing does, it
      falls back to running the command directly. }
    property OnCommand: TLedDebugCommandEvent read FOnCommand write FOnCommand;
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
  AddButton('Breakpoint', 'Toggle breakpoint'#13'F9', ldcToggleBreakpoint, -1);
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

  { A tree rather than a list, because a struct has to open.  LCL's TTreeView
    has no columns, so a row reads "name = value" for a leaf and "name: type"
    for something that can be opened -- which is also the cue that it can. }
  FLocals := TTreeView.Create(Self);
  FLocals.Parent := Body;
  FLocals.Align := alTop;
  FLocals.Height := 150;
  FLocals.ReadOnly := True;
  FLocals.RowSelect := True;
  FLocals.HideSelection := False;
  FLocals.OnExpanding := @LocalsExpanding;
  FLocalNodes := TFPList.Create;

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

{ AIndexes is read by command, not by position.

  It used to be by position, on the belief that a TToolBar lists its buttons
  in the reverse of the order they were created -- so building them back to
  front would line them up again.  It does not: Buttons[] is in creation
  order, and every icon but Step Over's landed on the wrong button.  Continue
  wore the breakpoint icon, Toggle Breakpoint wore Run's triangle, and Build
  wore the debugger's bug.  Nobody noticed while the breakpoint icon was a
  plain disc.

  Reading the button's own Tag removes the question: it holds the command,
  and the caller lists one icon per command in the order they are declared. }
procedure TLedDebugPane.SetImages(AImages: TCustomImageList;
  const AIndexes: array of Integer);
var
  i, Cmd: Integer;
begin
  FBar.Images := AImages;
  for i := 0 to FBar.ButtonCount - 1 do
  begin
    Cmd := FBar.Buttons[i].Tag;
    if (Cmd >= 0) and (Cmd <= High(AIndexes)) then
      FBar.Buttons[i].ImageIndex := AIndexes[Cmd];
  end;
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

procedure TLedDebugPane.ClearLocalNodes;
var
  i: Integer;
begin
  for i := 0 to FLocalNodes.Count - 1 do
    TLedLocalNode(FLocalNodes[i]).Free;
  FLocalNodes.Clear;
end;

function TLedDebugPane.NewLocalNode(const AExpr, AVarObj: string): TLedLocalNode;
begin
  Result := TLedLocalNode.Create;
  Inc(FNextSerial);
  Result.Serial := FNextSerial;
  Result.Expr := AExpr;
  Result.VarObj := AVarObj;
  FLocalNodes.Add(Result);
end;

function TLedDebugPane.LocalNodeBySerial(ASerial: Integer): TLedLocalNode;
var
  i: Integer;
begin
  for i := 0 to FLocalNodes.Count - 1 do
    if TLedLocalNode(FLocalNodes[i]).Serial = ASerial then
      Exit(TLedLocalNode(FLocalNodes[i]));
  Result := nil;
end;

{ A row that can be opened gets one placeholder child, because a TTreeView
  draws no expander for a node with no children -- so without it there is
  nothing to click and the struct looks like a leaf. }
procedure AddPlaceholder(ATree: TTreeView; ANode: TTreeNode);
begin
  ATree.Items.AddChild(ANode, '...');
end;

procedure TLedDebugPane.ShowLocals(const ALocals: TLedGdbLocals);
var
  i: Integer;
  N: TTreeNode;
  Info: TLedLocalNode;
  Aggregate: Boolean;
begin
  FLocals.BeginUpdate;
  try
    FLocals.Items.Clear;
    ClearLocalNodes;
    for i := 0 to High(ALocals) do
    begin
      { --simple-values leaves a struct or an array without a value, which is
        how one is told from a scalar without parsing C types. }
      Aggregate := (ALocals[i].Value = '') or (ALocals[i].Value = '{...}');
      if Aggregate then
        N := FLocals.Items.AddChild(nil,
          ALocals[i].Name + ': ' + ALocals[i].TypeName)
      else
        { Tidied: a char array arrives padded to its declared length, and the
          run of \000 after the text is the array's size restated. }
        N := FLocals.Items.AddChild(nil,
          ALocals[i].Name + ' = ' + LedTidyValue(ALocals[i].Value));
      Info := NewLocalNode(ALocals[i].Name, '');
      N.Data := Info;
      if Aggregate then AddPlaceholder(FLocals, N);
    end;
  finally
    FLocals.EndUpdate;
  end;
end;

procedure TLedDebugPane.LocalsExpanding(Sender: TObject; Node: TTreeNode;
  var AllowExpansion: Boolean);
var
  Info: TLedLocalNode;
begin
  AllowExpansion := True;
  if Node = nil then Exit;
  Info := TLedLocalNode(Node.Data);
  if Info = nil then Exit;
  if Info.Loaded or Info.Requested then Exit;
  Info.Requested := True;
  if Assigned(FOnExpandLocal) then
    FOnExpandLocal(Self, Info.Serial, Info.Expr, Info.VarObj);
end;

procedure TLedDebugPane.SetLocalVarObj(ASerial: Integer;
  const AVarObj: string; ANumChild: Integer);
var
  Info: TLedLocalNode;
begin
  Info := LocalNodeBySerial(ASerial);
  if Info = nil then Exit;
  Info.VarObj := AVarObj;
  if AVarObj = '' then
  begin
    { gdb would not make one -- nothing to open. }
    Info.Loaded := True;
    Info.Requested := False;
  end;
end;

{ Replaces the placeholder with what gdb said is in there. }
procedure TLedDebugPane.SetLocalChildren(ASerial: Integer;
  const AChildren: TLedGdbVarChildren);
var
  Info, Kid: TLedLocalNode;
  Owner_, N: TTreeNode;
  i: Integer;
  Aggregate: Boolean;
begin
  Info := LocalNodeBySerial(ASerial);
  if Info = nil then Exit;
  Info.Loaded := True;
  Info.Requested := False;

  Owner_ := nil;
  for i := 0 to FLocals.Items.Count - 1 do
    if FLocals.Items[i].Data = Pointer(Info) then
    begin
      Owner_ := FLocals.Items[i];
      Break;
    end;
  if Owner_ = nil then Exit;

  FLocals.BeginUpdate;
  try
    Owner_.DeleteChildren;
    for i := 0 to High(AChildren) do
    begin
      Aggregate := (AChildren[i].Value = '') or (AChildren[i].Value = '{...}');
      if Aggregate then
        N := FLocals.Items.AddChild(Owner_,
          AChildren[i].Expr + ': ' + AChildren[i].TypeName)
      else
        N := FLocals.Items.AddChild(Owner_,
          AChildren[i].Expr + ' = ' + LedTidyValue(AChildren[i].Value));
      Kid := NewLocalNode(AChildren[i].Expr, AChildren[i].VarObj);
      N.Data := Kid;
      { Its own children are fetched only if it is opened in turn, so a deep
        structure costs one round trip per level the user actually looks at. }
      if AChildren[i].NumChild > 0 then
      begin
        AddPlaceholder(FLocals, N);
        Kid.Loaded := False;
      end
      else
        Kid.Loaded := True;
    end;
    Owner_.Expand(False);
  finally
    FLocals.EndUpdate;
  end;
end;

function TLedDebugPane.LocalRowCount: Integer;
begin
  Result := FLocals.Items.Count;
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

procedure TLedDebugPane.TypeWatch(const AExpr: string);
var
  Key: Char;
begin
  FWatchEntry.Text := AExpr;
  Key := #13;
  WatchEntryKey(FWatchEntry, Key);
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
    It.SubItems[0] := LedTidyValue(AValue);
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
  ClearLocalNodes;
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
      ldcToggleBreakpoint: B.Enabled := True;
    end;
  end;
  FCmdEntry.Enabled := Live;
end;

{ --- TLedBreakPane --------------------------------------------------------- }

const
  { What each kind is called in the list.  gdb's own words are "hw
    watchpoint" and "acc watchpoint", which say how it is implemented rather
    than what it does. }
  BreakKindNames: array[TLedGdbBreakKind] of string =
    ('Breakpoint', 'Write watch', 'Read watch', 'Access watch');

constructor TLedBreakPane.Create(AOwner: TComponent);
var
  Foot: TPanel;
  C: TListColumn;
  K: TLedGdbBreakKind;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';

  FBar := TToolBar.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.EdgeBorders := [];
  FBar.ShowCaptions := True;
  FBar.Flat := True;
  FBar.AutoSize := True;

  { Back to front, so they read left to right: a TToolBar lays its children
    out in reverse unless each is given a Left.  Each carries its own tag so
    SetImages can find it without depending on any of that. }
  AddButton('Remove All', 'Forget every breakpoint and watchpoint',
    @RemoveAllClick, Ord(lbbRemoveAll));
  AddButton('Remove', 'Forget the selected one'#13'Delete', @RemoveClick,
    Ord(lbbRemove));
  AddButton('Condition...', 'Only stop where an expression is true',
    @ConditionClick, Ord(lbbCondition));
  AddButton('Enable', 'Turn the selected one off, or back on'#13'Space',
    @EnableClick, Ord(lbbEnable));

  Foot := TPanel.Create(Self);
  Foot.Parent := Self;
  Foot.Align := alBottom;
  Foot.BevelOuter := bvNone;
  Foot.AutoSize := True;

  FKind := TComboBox.Create(Self);
  FKind.Parent := Foot;
  FKind.Align := alLeft;
  FKind.Style := csDropDownList;
  for K := lgbWatch to lgbAccessWatch do FKind.Items.Add(BreakKindNames[K]);
  FKind.ItemIndex := 0;
  FKind.Width := 110;

  FEntry := TEdit.Create(Self);
  FEntry.Parent := Foot;
  FEntry.Align := alClient;
  FEntry.TextHint := 'Watch an expression -- stop when it changes -- then Enter';
  FEntry.OnKeyPress := @EntryKey;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnDblClick := @ListDouble;
  FList.OnKeyDown := @ListKey;

  { On is a word rather than a checkbox: LCL's list-view checkboxes fire
    OnItemChecked while the list is being filled as well as when a person
    clicks, so the state would have to be guarded going in and out.  A
    column and a button say the same thing and can be driven by a test. }
  C := FList.Columns.Add; C.Caption := '#';          C.Width := 40;
  C := FList.Columns.Add; C.Caption := 'On';         C.Width := 40;
  C := FList.Columns.Add; C.Caption := 'Kind';       C.Width := 100;
  C := FList.Columns.Add; C.Caption := 'Where';      C.Width := 260;
  C := FList.Columns.Add; C.Caption := 'Condition';  C.Width := 180;
  C := FList.Columns.Add; C.Caption := 'Hits';       C.Width := 50;
end;

function TLedBreakPane.AddButton(const ACaption, AHint: string;
  AOnClick: TNotifyEvent; ATag: Integer): TToolButton;
begin
  Result := TToolButton.Create(Self);
  Result.Parent := FBar;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.ImageIndex := -1;
  Result.Tag := ATag;
  Result.OnClick := AOnClick;
end;

{ By tag, for the reason TLedDebugPane.SetImages gives: Buttons[] is in
  creation order, and these are created in reverse so they read left to
  right. }
procedure TLedBreakPane.SetImages(AImages: TCustomImageList;
  const AIndexes: array of Integer);
var
  i, Which: Integer;
begin
  FBar.Images := AImages;
  for i := 0 to FBar.ButtonCount - 1 do
  begin
    Which := FBar.Buttons[i].Tag;
    if (Which >= 0) and (Which <= High(AIndexes)) then
      FBar.Buttons[i].ImageIndex := AIndexes[Which];
  end;
end;

procedure TLedBreakPane.ShowBreakpoints(const ABreaks: TLedBreakpoints);
var
  i, Keep: Integer;
  It: TListItem;
  Where: string;
begin
  Keep := Selected;
  FFilling := True;
  FList.BeginUpdate;
  try
    FList.Items.Clear;
    for i := 0 to High(ABreaks) do
    begin
      It := FList.Items.Add;
      { Dashed rather than blank while gdb has not answered yet, because a
        breakpoint with no number is one that is only in led so far -- which
        is the ordinary state of one set before the session starts. }
      if ABreaks[i].Number > 0 then
        It.Caption := IntToStr(ABreaks[i].Number)
      else
        It.Caption := '--';
      if ABreaks[i].Enabled then It.SubItems.Add('yes')
                            else It.SubItems.Add('no');
      It.SubItems.Add(BreakKindNames[ABreaks[i].Kind]);
      if ABreaks[i].Kind = lgbLine then
        Where := Format('%s:%d', [ExtractFileName(ABreaks[i].FileName),
                                  ABreaks[i].Line])
      else
        Where := ABreaks[i].Expression;
      It.SubItems.Add(Where);
      It.SubItems.Add(ABreaks[i].Condition);
      It.SubItems.Add(IntToStr(ABreaks[i].HitCount));
    end;
  finally
    FList.EndUpdate;
    FFilling := False;
  end;
  Select(Keep);
end;

function TLedBreakPane.RowCount: Integer;
begin
  Result := FList.Items.Count;
end;

function TLedBreakPane.RowText(AIndex, AColumn: Integer): string;
begin
  Result := '';
  if (AIndex < 0) or (AIndex >= FList.Items.Count) then Exit;
  if AColumn = 0 then Exit(FList.Items[AIndex].Caption);
  if AColumn - 1 < FList.Items[AIndex].SubItems.Count then
    Result := FList.Items[AIndex].SubItems[AColumn - 1];
end;

function TLedBreakPane.Selected: Integer;
begin
  if FList.Selected = nil then Result := -1
                          else Result := FList.Selected.Index;
end;

procedure TLedBreakPane.Select(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FList.Items.Count) then
    FList.Items[AIndex].Selected := True;
end;

procedure TLedBreakPane.TypeWatchpoint(const AExpression: string;
  AKind: TLedGdbBreakKind);
var
  Key: Char;
begin
  if AKind = lgbLine then Exit;
  FKind.ItemIndex := Ord(AKind) - Ord(lgbWatch);
  FEntry.Text := AExpression;
  { Through the same key handler a person's Enter goes through, so the test
    exercises the widget rather than the event it happens to raise. }
  Key := #13;
  EntryKey(FEntry, Key);
end;

procedure TLedBreakPane.ListDouble(Sender: TObject);
begin
  if (Selected >= 0) and Assigned(FOnJump) then FOnJump(Self, Selected);
end;

procedure TLedBreakPane.ListKey(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Selected < 0 then Exit;
  if Key = VK_DELETE then
  begin
    if Assigned(FOnRemove) then FOnRemove(Self, Selected);
    Key := 0;
  end
  else if Key = VK_SPACE then
  begin
    if Assigned(FOnToggleEnabled) then FOnToggleEnabled(Self, Selected);
    Key := 0;
  end;
end;

procedure TLedBreakPane.EntryKey(Sender: TObject; var Key: Char);
var
  K: TLedGdbBreakKind;
begin
  if (Key <> #13) or (Trim(FEntry.Text) = '') then Exit;
  K := TLedGdbBreakKind(Ord(lgbWatch) + FKind.ItemIndex);
  if Assigned(FOnAddWatchpoint) then
    FOnAddWatchpoint(Self, Trim(FEntry.Text), K);
  FEntry.Text := '';
  Key := #0;
end;

procedure TLedBreakPane.RemoveClick(Sender: TObject);
begin
  if (Selected >= 0) and Assigned(FOnRemove) then FOnRemove(Self, Selected);
end;

procedure TLedBreakPane.RemoveAllClick(Sender: TObject);
begin
  if Assigned(FOnRemoveAll) then FOnRemoveAll(Self);
end;

procedure TLedBreakPane.EnableClick(Sender: TObject);
begin
  if (Selected >= 0) and Assigned(FOnToggleEnabled) then
    FOnToggleEnabled(Self, Selected);
end;

procedure TLedBreakPane.ConditionClick(Sender: TObject);
begin
  if (Selected >= 0) and Assigned(FOnEditCondition) then
    FOnEditCondition(Self, Selected);
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
  FSession.OnWatchHit := @SessionWatchHit;
  FSession.OnLocals := @SessionLocals;
  FSession.OnFrames := @SessionFrames;
  FSession.OnEval := @SessionEval;
  FSession.OnVarCreated := @SessionVarCreated;
  FSession.OnVarChildren := @SessionVarChildren;
  FSession.OnConsole := @SessionText;
  FSession.OnTarget := @SessionText;
  FSession.OnLog := @SessionText;
  FSession.OnError := @SessionError;

  FProject := TLedProject.Create;
  FWatchExprs := TStringList.Create;
  FHoverCache := TStringList.Create;
  FHoverBad := TStringList.Create;

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
  FHoverCache.Free;
  FHoverBad.Free;
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
  FPane.OnExpandLocal := @PaneExpandLocal;
end;

procedure TLedDebugger.AttachBreakPane(APane: TLedBreakPane);
begin
  FBreakPane := APane;
  if FBreakPane = nil then Exit;
  FBreakPane.OnJump := @BreakPaneJump;
  FBreakPane.OnRemove := @BreakPaneRemove;
  FBreakPane.OnToggleEnabled := @BreakPaneToggle;
  FBreakPane.OnEditCondition := @BreakPaneCondition;
  FBreakPane.OnRemoveAll := @BreakPaneRemoveAll;
  FBreakPane.OnAddWatchpoint := @BreakPaneAddWatchpoint;
  RefreshBreakList;
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
    if (FBreaks[i].Kind = lgbLine) and (FBreaks[i].Line = ALine) and
       SameFileName(FBreaks[i].FileName, AFileName) then Exit(i);
  Result := -1;
end;

{ A watchpoint led has asked for but gdb has not numbered yet.  Matched on
  the expression, which is all the reply carries. }
function TLedDebugger.IndexOfPendingWatch(const AExpression: string): Integer;
var
  i: Integer;
begin
  if AExpression <> '' then
    for i := 0 to High(FBreaks) do
      if (FBreaks[i].Kind <> lgbLine) and (FBreaks[i].Number < 0) and
         (FBreaks[i].Expression = AExpression) then Exit(i);
  Result := -1;
end;

function TLedDebugger.IndexOfNumber(ANumber: Integer): Integer;
var
  i: Integer;
begin
  if ANumber > 0 then
    for i := 0 to High(FBreaks) do
      if FBreaks[i].Number = ANumber then Exit(i);
  Result := -1;
end;

{ A blank row with the defaults every kind shares.  Written once because
  forgetting Enabled leaves a breakpoint that the list draws as off and that
  Start then tries to disable. }
function TLedDebugger.NewBreakRow: Integer;
begin
  Result := Length(FBreaks);
  SetLength(FBreaks, Result + 1);
  FBreaks[Result].Kind := lgbLine;
  FBreaks[Result].FileName := '';
  FBreaks[Result].Line := 0;
  FBreaks[Result].Expression := '';
  FBreaks[Result].Number := -1;
  FBreaks[Result].Condition := '';
  FBreaks[Result].Enabled := True;
  FBreaks[Result].HitCount := 0;
end;

procedure TLedDebugger.DropBreakRow(AIndex: Integer);
var
  n: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FBreaks)) then Exit;
  for n := AIndex to High(FBreaks) - 1 do FBreaks[n] := FBreaks[n + 1];
  SetLength(FBreaks, Length(FBreaks) - 1);
end;

procedure TLedDebugger.RefreshBreakList;
begin
  if FBreakPane <> nil then FBreakPane.ShowBreakpoints(FBreaks);
end;

function TLedDebugger.Breakpoint(AIndex: Integer): TLedBreakpoint;
begin
  { Set field by field rather than with FillChar: the record holds strings,
    and zeroing a managed field behind the compiler's back is how one gets a
    reference count that is wrong later rather than a crash now. }
  Result.Kind := lgbLine;
  Result.FileName := '';
  Result.Line := 0;
  Result.Expression := '';
  Result.Number := -1;
  Result.Condition := '';
  Result.Enabled := False;
  Result.HitCount := 0;
  if (AIndex < 0) or (AIndex > High(FBreaks)) then Exit;
  Result := FBreaks[AIndex];
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
  Marks: TLedGutterBreaks;
  i, n: Integer;
begin
  if not Assigned(FOnViewFor) then Exit;
  V := FOnViewFor(AFileName);
  if V = nil then Exit;
  SetLength(Marks, Length(FBreaks));
  n := 0;
  for i := 0 to High(FBreaks) do
    if (FBreaks[i].Kind = lgbLine) and
       SameFileName(FBreaks[i].FileName, AFileName) then
    begin
      Marks[n].Line := FBreaks[i].Line;
      Marks[n].Conditional := FBreaks[i].Condition <> '';
      Marks[n].Enabled := FBreaks[i].Enabled;
      Inc(n);
    end;
  SetLength(Marks, n);
  V.SetBreakpointLines(Marks);
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
    { Dropped before gdb is told, not after.  BreakDelete reports the removal
      straight back through OnBreakRemoved -- which drops the row itself --
      so removing it again by an index that has already shifted took the next
      breakpoint with it. }
    n := FBreaks[i].Number;
    DropBreakRow(i);
    if (n > 0) and FSession.Alive then FSession.BreakDelete(n);
  end
  else
  begin
    n := NewBreakRow;
    FBreaks[n].FileName := AFileName;
    FBreaks[n].Line := ALine;
    { Sent now when gdb is up, and replayed at Start when it is not, so a
      breakpoint can be set before anything is running. }
    if FSession.Alive then FSession.BreakInsert(AFileName, ALine);
  end;
  PushMarksFor(AFileName);
  RefreshBreakList;
end;

procedure TLedDebugger.SendBreakpointsToGdb;
var
  i: Integer;
begin
  for i := 0 to High(FBreaks) do
  begin
    FBreaks[i].Number := -1;
    if FBreaks[i].Kind = lgbLine then
      { With its condition, so one set before the session started still only
        fires where it was meant to. }
      FSession.BreakInsert(FBreaks[i].FileName, FBreaks[i].Line,
        FBreaks[i].Condition)
    else
      { Watchpoints are replayed too, and a local's will be refused until
        there is a frame -- gdb says so, and the row stays with no number
        so the list shows it has not taken. }
      FSession.WatchInsert(FBreaks[i].Expression, FBreaks[i].Kind);
  end;
  RefreshBreakList;
end;

function TLedDebugger.BreakpointCondition(const AFileName: string;
  ALine: Integer): string;
var
  i: Integer;
begin
  Result := '';
  i := IndexOfBreak(AFileName, ALine);
  if i >= 0 then Result := FBreaks[i].Condition;
end;

procedure TLedDebugger.SetBreakpointCondition(const AFileName: string;
  ALine: Integer; const ACondition: string);
var
  i: Integer;
begin
  if (AFileName = '') or (ALine <= 0) then Exit;
  i := IndexOfBreak(AFileName, ALine);
  if i < 0 then
  begin
    { Asking for a condition on a line with no breakpoint means both. }
    ToggleBreakpoint(AFileName, ALine);
    i := IndexOfBreak(AFileName, ALine);
    if i < 0 then Exit;
  end;

  FBreaks[i].Condition := ACondition;
  if FSession.Alive and (FBreaks[i].Number > 0) then
    FSession.BreakCondition(FBreaks[i].Number, ACondition);
  if ACondition <> '' then
    Say(Format('[gdb] breakpoint at %s:%d fires when %s',
      [ExtractFileName(AFileName), ALine, ACondition]))
  else
    Say(Format('[gdb] breakpoint at %s:%d always fires',
      [ExtractFileName(AFileName), ALine]));
  PushMarksFor(AFileName);
  RefreshBreakList;
end;

{ --- watchpoints and the list --------------------------------------------- }

procedure TLedDebugger.AddWatchpoint(const AExpression: string;
  AKind: TLedGdbBreakKind);
var
  n: Integer;
begin
  if Trim(AExpression) = '' then Exit;
  if AKind = lgbLine then AKind := lgbWatch;
  n := NewBreakRow;
  FBreaks[n].Kind := AKind;
  FBreaks[n].Expression := Trim(AExpression);
  if FSession.Alive then
    FSession.WatchInsert(FBreaks[n].Expression, AKind)
  else
    Say(Format('[gdb] will watch %s when the session starts',
      [FBreaks[n].Expression]));
  RefreshBreakList;
end;

procedure TLedDebugger.RemoveBreakpoint(AIndex: Integer);
var
  Gone: string;
  Num: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FBreaks)) then Exit;
  Gone := FBreaks[AIndex].FileName;
  { The row goes first, for the reason ToggleBreakpoint gives. }
  Num := FBreaks[AIndex].Number;
  DropBreakRow(AIndex);
  if (Num > 0) and FSession.Alive then FSession.BreakDelete(Num);
  if Gone <> '' then PushMarksFor(Gone);
  RefreshBreakList;
end;

procedure TLedDebugger.RemoveAllBreakpoints;
var
  i: Integer;
  Files: TStringList;
  Numbers: array of Integer;
begin
  Files := TStringList.Create;
  Numbers := nil;
  try
    Files.Duplicates := dupIgnore;
    Files.Sorted := True;
    SetLength(Numbers, Length(FBreaks));
    for i := 0 to High(FBreaks) do
    begin
      if FBreaks[i].FileName <> '' then Files.Add(FBreaks[i].FileName);
      Numbers[i] := FBreaks[i].Number;
    end;
    { Emptied before gdb is told, again so that the removals it reports back
      find nothing left to drop. }
    SetLength(FBreaks, 0);
    if FSession.Alive then
      for i := 0 to High(Numbers) do
        if Numbers[i] > 0 then FSession.BreakDelete(Numbers[i]);
    { Every file that had one, because the gutter is pushed per view. }
    for i := 0 to Files.Count - 1 do PushMarksFor(Files[i]);
  finally
    Files.Free;
  end;
  RefreshBreakList;
end;

procedure TLedDebugger.SetBreakpointEnabled(AIndex: Integer; AEnabled: Boolean);
begin
  if (AIndex < 0) or (AIndex > High(FBreaks)) then Exit;
  FBreaks[AIndex].Enabled := AEnabled;
  if (FBreaks[AIndex].Number > 0) and FSession.Alive then
    FSession.BreakEnable(FBreaks[AIndex].Number, AEnabled);
  if FBreaks[AIndex].Kind = lgbLine then
    PushMarksFor(FBreaks[AIndex].FileName);
  RefreshBreakList;
end;

procedure TLedDebugger.RunToCursor(const AFileName: string; ALine: Integer);
begin
  if not CanStep then
  begin
    Say('[gdb] nothing is stopped, so there is nowhere to run from');
    Exit;
  end;
  FSession.ExecUntil(AFileName, ALine);
end;

{ --- session events --- }

{ gdb has told us about a breakpoint or watchpoint.

  Matched by number first, because =breakpoint-modified -- which is how hit
  counts and a watchpoint's real type arrive -- is about one we already have.
  Failing that it is a new one: matched to the row that asked for it, by line
  for a breakpoint and by expression for a watchpoint, both of which are
  waiting with no number yet. }
procedure TLedDebugger.SessionBreakAdded(Sender: TObject;
  const AInfo: TLedGdbBreakInfo);
var
  i: Integer;
begin
  i := IndexOfNumber(AInfo.Number);

  if i < 0 then
  begin
    if AInfo.Kind = lgbLine then
      i := IndexOfBreak(AInfo.FileName, AInfo.Line)
    else
      i := IndexOfPendingWatch(AInfo.Expression);
  end;

  if i < 0 then
  begin
    { Created from the gdb command box rather than from the gutter or the
      list.  Adopted, so the dot appears where gdb says it is. }
    if (AInfo.Kind = lgbLine) and ((AInfo.FileName = '') or (AInfo.Line <= 0))
      then Exit;
    if (AInfo.Kind <> lgbLine) and (AInfo.Expression = '') then Exit;
    i := NewBreakRow;
    FBreaks[i].Kind := AInfo.Kind;
    FBreaks[i].FileName := AInfo.FileName;
    FBreaks[i].Line := AInfo.Line;
    FBreaks[i].Expression := AInfo.Expression;
  end;

  FBreaks[i].Number := AInfo.Number;
  { A watchpoint only learns which of the three kinds it is from the full
    record; the short insert reply guesses from the field name and is right,
    but =breakpoint-modified is gdb's own word for it. }
  if AInfo.Complete then
  begin
    FBreaks[i].Kind := AInfo.Kind;
    { gdb's answer wins: a condition it rejected is not one we have. }
    FBreaks[i].Condition := AInfo.Condition;
    FBreaks[i].HitCount := AInfo.HitCount;
    if AInfo.Kind <> lgbLine then FBreaks[i].Expression := AInfo.Expression;
  end;

  { Disabling sends no notification, so a row that was turned off before the
    session started has to turn itself off again now it has a number. }
  if (not FBreaks[i].Enabled) and AInfo.Enabled and FSession.Alive then
    FSession.BreakEnable(AInfo.Number, False)
  else if AInfo.Complete then
    FBreaks[i].Enabled := AInfo.Enabled;

  if FBreaks[i].Kind = lgbLine then PushMarksFor(FBreaks[i].FileName);
  RefreshBreakList;
end;

procedure TLedDebugger.SessionBreakRemoved(Sender: TObject; ANumber: Integer);
var
  i: Integer;
  Gone: string;
begin
  i := IndexOfNumber(ANumber);
  if i < 0 then Exit;
  Gone := FBreaks[i].FileName;
  DropBreakRow(i);
  if Gone <> '' then PushMarksFor(Gone);
  RefreshBreakList;
end;

{ A watchpoint fired.  Said before the stop is handled, because by the time
  the caret has moved and the locals have been re-read the interesting part
  -- what the value was a moment ago -- is gone from everywhere but here. }
procedure TLedDebugger.SessionWatchHit(Sender: TObject; ANumber: Integer;
  const AExpression, AOldValue, ANewValue: string);
begin
  if AOldValue = '' then
    Say(Format('[gdb] watchpoint %d: %s read, value %s',
      [ANumber, AExpression, ANewValue]))
  else
    Say(Format('[gdb] watchpoint %d: %s changed from %s to %s',
      [ANumber, AExpression, AOldValue, ANewValue]));
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
  { The values belonged to the frame that has just been left. }
  FHoverCache.Clear;
  FHoverBad.Clear;
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
  FHoverCache.Clear;
  FHoverBad.Clear;

  if Pos('exited', AReason) > 0 then
  begin
    Say('[gdb] the program exited (' + AReason + ')');
    if FPane <> nil then FPane.Clear;
    if Assigned(FOnStateChanged) then FOnStateChanged(Self);
    Exit;
  end;

  { gdb deletes a watchpoint whose variable has gone out of scope, and tells
    us so through =breakpoint-deleted -- but a stop with no visible cause is
    alarming, so it is named. }
  if AReason = 'watchpoint-scope' then
    Say('[gdb] a watched variable went out of scope; its watchpoint is gone');

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

procedure TLedDebugger.HoverExpression(AView: TLedEdit; const AExpr: string);
var
  i: Integer;
begin
  if (AView = nil) or (AExpr = '') then Exit;
  FHoverView := AView;

  { Asked once and answered with an error: a type name, a label, a macro.
    Asking again on every pass of the pointer would fill the log. }
  if FHoverBad.IndexOf(AExpr) >= 0 then
  begin
    AView.HideHoverValue(AExpr);
    Exit;
  end;

  i := FHoverCache.IndexOfName(AExpr);
  if i >= 0 then
  begin
    AView.ShowHoverValue(AExpr, FHoverCache.ValueFromIndex[i]);
    Exit;
  end;

  { Nothing to ask when the program is not sitting at a stop -- and saying
    so beats leaving "= ..." on screen for ever. }
  if not CanStep then
  begin
    AView.ShowHoverValue(AExpr, '(not stopped)');
    Exit;
  end;
  FSession.Evaluate(AExpr, 'h:' + AExpr);
end;

procedure TLedDebugger.SessionEval(Sender: TObject; const ATag, AValue: string;
  AIsError: Boolean);
var
  Idx: Integer;
  Expr, Expanded: string;
begin
  { Hover first: its tag carries the expression itself, because the answer
    has to be matched to a place on screen rather than to a row. }
  if Copy(ATag, 1, 2) = 'h:' then
  begin
    Expr := Copy(ATag, 3, Length(ATag));
    { Nothing worth showing.  Hovering the type in `Item *it` asks gdb about
      `Item`, which answers "Attempt to use a type name as an expression" --
      and that was then displayed as though it were the value.  Remembered so
      the same word is not asked about again on every pass of the pointer. }
    if AIsError then
    begin
      if FHoverBad.IndexOf(Expr) < 0 then FHoverBad.Add(Expr);
      if FHoverView <> nil then FHoverView.HideHoverValue(Expr);
      Exit;
    end;
    { Expanded: a struct arrives on one line, which in a tooltip is where
      "it does not show the subfields" comes from -- they are all there, in a
      paragraph nobody can read. }
    Expanded := LedExpandValue(LedTidyValue(AValue));
    FHoverCache.Values[Expr] := Expanded;
    if FHoverView <> nil then FHoverView.ShowHoverValue(Expr, Expanded);
    Exit;
  end;

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

{ The pane's toolbar.  Handed to the window rather than run here when the
  window is listening, because pressing Start is more than starting: the
  active file has to be noted first -- which is what finds the project, and
  therefore what there is to debug -- the Output pane has to be shown, and a
  binary older than its sources has to be rebuilt.

  All of that lived in the form's DebugCommand, so the menu and Ctrl+F5 got
  it and the pane's own buttons did not: Start there reported "nothing to
  debug" in a project the same key debugged fine. }
procedure TLedDebugger.PaneCommand(Sender: TObject; ACommand: TLedDebugCommand);
begin
  if Assigned(FOnCommand) then
    FOnCommand(Self, ACommand)
  else
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

{ A Locals row was opened.

  Two round trips the first time and one afterwards: a top-level row has no
  variable object yet, so one is made and its children asked for when the
  handle comes back; a row that already has a handle -- every row produced by
  a previous expansion does -- goes straight to asking.

  The serial travels in the tag, because by the time gdb answers the tree may
  have been rebuilt by another stop, and a reply about a frame that has gone
  must be dropped rather than written into whatever row now sits there. }
procedure TLedDebugger.PaneExpandLocal(Sender: TObject; ASerial: Integer;
  const AExpr, AVarObj: string);
begin
  if AVarObj <> '' then
    FSession.VarChildren(AVarObj, 'x:' + IntToStr(ASerial))
  else
    FSession.VarCreate(AExpr, 'x:' + IntToStr(ASerial));
end;

procedure TLedDebugger.SessionVarCreated(Sender: TObject; const ATag, AVarObj,
  ATypeName, AValue: string; ANumChild: Integer);
var
  Serial: Integer;
begin
  if (FPane = nil) or (Copy(ATag, 1, 2) <> 'x:') then Exit;
  Serial := StrToIntDef(Copy(ATag, 3, Length(ATag)), -1);
  if Serial < 0 then Exit;
  FPane.SetLocalVarObj(Serial, AVarObj, ANumChild);
  if AVarObj <> '' then
    FSession.VarChildren(AVarObj, ATag);
end;

procedure TLedDebugger.SessionVarChildren(Sender: TObject; const ATag: string;
  const AChildren: TLedGdbVarChildren);
var
  Serial: Integer;
begin
  if (FPane = nil) or (Copy(ATag, 1, 2) <> 'x:') then Exit;
  Serial := StrToIntDef(Copy(ATag, 3, Length(ATag)), -1);
  if Serial < 0 then Exit;
  FPane.SetLocalChildren(Serial, AChildren);
end;

{ --- breakpoint pane events ------------------------------------------------ }

procedure TLedDebugger.BreakPaneJump(Sender: TObject; AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FBreaks)) then Exit;
  { A watchpoint has nowhere to go -- it belongs to an expression, not a
    line -- so a double click on one does nothing rather than jumping to
    whatever file happens to be blank. }
  if FBreaks[AIndex].Kind <> lgbLine then Exit;
  if (FBreaks[AIndex].FileName <> '') and Assigned(FOnJump) then
    FOnJump(Self, FBreaks[AIndex].FileName, FBreaks[AIndex].Line);
end;

procedure TLedDebugger.BreakPaneRemove(Sender: TObject; AIndex: Integer);
begin
  RemoveBreakpoint(AIndex);
end;

procedure TLedDebugger.BreakPaneToggle(Sender: TObject; AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FBreaks)) then Exit;
  SetBreakpointEnabled(AIndex, not FBreaks[AIndex].Enabled);
end;

procedure TLedDebugger.BreakPaneCondition(Sender: TObject; AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FBreaks)) then Exit;
  if FBreaks[AIndex].Kind <> lgbLine then
  begin
    Say('[gdb] a condition can only be put on a breakpoint here; ' +
        'use the gdb box for one on a watchpoint');
    Exit;
  end;
  if Assigned(FOnEditCondition) then
    FOnEditCondition(Self, FBreaks[AIndex].FileName, FBreaks[AIndex].Line);
end;

procedure TLedDebugger.BreakPaneRemoveAll(Sender: TObject);
begin
  RemoveAllBreakpoints;
end;

procedure TLedDebugger.BreakPaneAddWatchpoint(Sender: TObject;
  const AExpression: string; AKind: TLedGdbBreakKind);
begin
  AddWatchpoint(AExpression, AKind);
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
    { Two different problems, and the same sentence for both said nothing
      useful for either.  A project is found by walking up from the open
      file, so with nothing open there is nowhere to look. }
    if FActiveFile = '' then
      Say('[gdb] nothing to debug: open the source file first -- the ' +
          'project is found by walking up from it')
    else
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
    { Neither is this one's to do: which line to put a breakpoint on is a
      question about the caret, and the caret belongs to the window.  The
      button used to be wired to ldcStop, so pressing Breakpoint ended the
      session. }
    ldcToggleBreakpoint:
      if Assigned(FOnToggleBreakpoint) then FOnToggleBreakpoint(Self);
  end;
end;

function TLedDebugger.TargetPath: string;
begin
  Result := ResolvedTarget;
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
