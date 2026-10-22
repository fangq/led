{ LED - a lightweight editor.  A scripted run of the window, for looking at it.

  With LED_DEMO set, the main window runs its steps once it is up and then
  quits: what a reviewer would click, done by name, with a picture of the
  whole screen saved where asked -- open menus included, which are windows
  of their own that no capture of the main form shows.  It is how the
  look of the window is checked on a machine with no one at it, under a
  virtual X server, at any dpi.

  LED_DEMO is the steps, separated by `;`:

    act:NAME        the action of that name, as its menu item would run it
    menu:CAPTION    open that main-menu item's menu (its caption without &)
    close           close any open menu
    pane:NAME       show the dock pane of that name
    edge:SIDE,W     the dock's left, right, top or bottom edge W pixels deep
    split:NAME,DX   the splitter right of the named control moved DX pixels,
                    as a drag of it would (negative is left)
    size:WxH        the window's size
    wait:MS         let the window run for that long
    shot:PATH       the screen as a PNG
    move:X,Y        the pointer there, in screen pixels
    click:X,Y       a left click there; dclick:X,Y a double click
    dump:NAME       the named control's children and their bounds, on stdout
    drag:X1,Y1,X2,Y2  press at the first point, move to the second, release
    drop:PATH       that file dropped on the window (its OnDropFiles)
    quit            (implied at the end)

  e.g.  LED_DEMO='wait:1500;act:actHelp;wait:500;shot:/tmp/help.png'

  Off, it costs nothing: the timer is made only when the variable is set. }
unit Led.UI.Demo;

{$mode objfpc}{$H+}

{$IF DEFINED(LINUX) and DEFINED(LCLGtk2)}
  {$DEFINE LED_DEMO_GTK2}
{$ENDIF}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, ExtCtrls, Menus, ActnList, ComCtrls;

type
  { What a step needs of the window that LED does not export another way }
  TLedDemoPaneProc = procedure(const AName: string) of object;

{ Start the steps in LED_DEMO, if there are any, against AForm.  APane shows
  a dock pane by name. }
procedure LedDemoStart(AForm: TCustomForm; AMenu: TMainMenu; AActions: TActionList;
  APane: TLedDemoPaneProc);

implementation

uses
  StrUtils{$IFDEF LED_DEMO_GTK2}, Glib2, Gdk2, Gdk2pixbuf, Gtk2, Gdk2x, dynlibs{$ENDIF};

{$IFDEF LED_DEMO_GTK2}
{ The pointer, moved and pressed as a person would: XTest's, loaded when a
  step first asks, so a run with no such step needs no libXtst }
var
  GXtst: TLibHandle = NilHandle;
  XMotion: function(d: Pointer; screen, x, y: LongInt; delay: PtrUInt): LongInt; cdecl = nil;
  XButton: function(d: Pointer; button: LongWord; press: LongInt; delay: PtrUInt): LongInt; cdecl = nil;
  XFlushFn: function(d: Pointer): LongInt; cdecl = nil;

function XtstReady: Boolean;
var
  X11: TLibHandle;
begin
  if GXtst = NilHandle then
  begin
    GXtst := LoadLibrary('libXtst.so.6');
    if GXtst <> NilHandle then
    begin
      Pointer(XMotion) := GetProcAddress(GXtst, 'XTestFakeMotionEvent');
      Pointer(XButton) := GetProcAddress(GXtst, 'XTestFakeButtonEvent');
      X11 := LoadLibrary('libX11.so.6');
      if X11 <> NilHandle then
        Pointer(XFlushFn) := GetProcAddress(X11, 'XFlush');
    end;
  end;
  Result := Assigned(XMotion) and Assigned(XButton) and Assigned(XFlushFn);
end;
{$ENDIF}

type
  TLedDemo = class(TComponent)
  private
    FForm: TCustomForm;
    FMenu: TMainMenu;
    FActions: TActionList;
    FPane: TLedDemoPaneProc;
    FSteps: TStringList;
    FAt: Integer;
    FTimer: TTimer;
    procedure Tick(Sender: TObject);
    procedure Step(const S: string; out AWait: Integer);
    procedure Shot(const APath: string);
    procedure OpenMenu(const ACaption: string);
    procedure Pointer_(const AVerb, AArg: string);
    procedure DumpTree(ATree: TCustomTreeView);
  public
    destructor Destroy; override;
  end;

destructor TLedDemo.Destroy;
begin
  FSteps.Free;
  inherited Destroy;
end;

procedure TLedDemo.Tick(Sender: TObject);
var
  W: Integer;
begin
  FTimer.Enabled := False;
  if FAt >= FSteps.Count then
  begin
    Application.Terminate;
    Exit;
  end;
  W := 50;
  try
    Step(Trim(FSteps[FAt]), W);
  except
    on E: Exception do
      WriteLn(StdErr, 'LED_DEMO: step "', FSteps[FAt], '" failed: ', E.Message);
  end;
  Inc(FAt);
  FTimer.Interval := W;
  FTimer.Enabled := True;
end;

procedure TLedDemo.Step(const S: string; out AWait: Integer);
var
  Verb, Arg: string;
  P, X: Integer;
  C: TComponent;
begin
  AWait := 50;
  P := Pos(':', S);
  if P > 0 then
  begin
    Verb := LowerCase(Copy(S, 1, P - 1));
    Arg := Copy(S, P + 1, MaxInt);
  end
  else
  begin
    Verb := LowerCase(S);
    Arg := '';
  end;
  if Verb = '' then Exit;
  if Verb = 'wait' then
    AWait := StrToIntDef(Arg, 100)
  else if Verb = 'act' then
  begin
    C := FActions.FindComponent(Arg);
    if C = nil then C := FForm.FindComponent(Arg);
    if C is TBasicAction then
      TBasicAction(C).Execute
    else
      WriteLn(StdErr, 'LED_DEMO: no action ', Arg);
  end
  else if Verb = 'menu' then
    OpenMenu(Arg)
  else if Verb = 'close' then
  begin
{$IFDEF LED_DEMO_GTK2}
    if (FMenu <> nil) and FMenu.HandleAllocated then
      gtk_menu_shell_deactivate(PGtkMenuShell(FMenu.Handle));
{$ENDIF}
  end
  else if Verb = 'pane' then
  begin
    if Assigned(FPane) then FPane(Arg);
  end
  else if Verb = 'split' then
  begin
    X := Pos(',', Arg);
    C := FForm.FindComponent(Copy(Arg, 1, X - 1));
    { up from the control to the first that is anchored on its right to a
      splitter: a dock site, whose splitter is the one a drag would move }
    while (C is TControl) and not (TControl(C).AnchorSide[akRight].Control is TCustomSplitter) do
      C := TControl(C).Parent;
    if C is TControl then
    begin
      TCustomSplitter(TControl(C).AnchorSide[akRight].Control).MoveSplitter(
        StrToIntDef(Copy(Arg, X + 1, MaxInt), 0));
      AWait := 500;
    end
    else
      WriteLn(StdErr, 'LED_DEMO: no splitter right of ', Copy(Arg, 1, X - 1));
  end
  else if Verb = 'edge' then
  begin
    { through the same proc, as "edge:left,400" }
    if Assigned(FPane) then FPane('@edge:' + Arg);
    AWait := 500;
  end
  else if Verb = 'size' then
  begin
    X := Pos('x', LowerCase(Arg));
    if X > 0 then
      FForm.SetBounds(FForm.Left, FForm.Top, StrToIntDef(Copy(Arg, 1, X - 1), FForm.Width),
        StrToIntDef(Copy(Arg, X + 1, MaxInt), FForm.Height));
    AWait := 300;
  end
  else if Verb = 'shot' then
    Shot(Arg)
  else if Verb = 'dump' then
  begin
    C := FForm.FindComponent(Arg);
    if C is TWinControl then
    begin
      WriteLn(Format('LED_DEMO: %s %s %d,%d %dx%d', [Arg, C.ClassName,
        TWinControl(C).Left, TWinControl(C).Top, TWinControl(C).Width, TWinControl(C).Height]));
      for X := 0 to TWinControl(C).ControlCount - 1 do
      begin
        with TWinControl(C).Controls[X] do
          WriteLn(Format('LED_DEMO:   %s %s %d,%d %dx%d visible=%s', [Name, ClassName,
            Left, Top, Width, Height, BoolToStr(Visible, True)]));
        { a tree's rows, as it holds them: their order, depth and place }
        if TWinControl(C).Controls[X] is TCustomTreeView then
          DumpTree(TCustomTreeView(TWinControl(C).Controls[X]));
      end;
    end
    else
      WriteLn(StdErr, 'LED_DEMO: no control ', Arg);
  end
  else if (Verb = 'move') or (Verb = 'click') or (Verb = 'dclick') or (Verb = 'drag') then
    Pointer_(Verb, Arg)
  else if Verb = 'drop' then
  begin
    { files dropped on the window, as the widget set hands them over }
    if Assigned(FForm.OnDropFiles) then
      FForm.OnDropFiles(FForm, [Arg]);
    AWait := 500;
  end
  else if Verb = 'quit' then
    FAt := FSteps.Count
  else
    WriteLn(StdErr, 'LED_DEMO: no step ', Verb);
end;

procedure TLedDemo.DumpTree(ATree: TCustomTreeView);
var
  N: TTreeNode;
  K: Integer;
  R: TRect;
begin
  N := ATree.Items.GetFirstNode;
  K := 0;
  while (N <> nil) and (K < 40) do
  begin
    R := N.DisplayRect(False);
    WriteLn(Format('LED_DEMO:     [%d] %s%s visible=%s y=%d', [N.Level,
      StringOfChar(' ', 2 * N.Level), N.Text, BoolToStr(N.IsVisible, True), R.Top]));
    N := N.GetNext;
    Inc(K);
  end;
end;

procedure TLedDemo.OpenMenu(const ACaption: string);
var
  I: Integer;
  It: TMenuItem;
begin
  if FMenu = nil then Exit;
  for I := 0 to FMenu.Items.Count - 1 do
  begin
    It := FMenu.Items[I];
    if SameText(StripHotkey(It.Caption), ACaption) then
    begin
{$IFDEF LED_DEMO_GTK2}
      if It.HandleAllocated and FMenu.HandleAllocated then
        gtk_menu_shell_select_item(PGtkMenuShell(FMenu.Handle), PGtkWidget(It.Handle));
{$ENDIF}
      Exit;
    end;
  end;
  WriteLn(StdErr, 'LED_DEMO: no menu ', ACaption);
end;

procedure TLedDemo.Pointer_(const AVerb, AArg: string);
{$IFDEF LED_DEMO_GTK2}
var
  C, X, Y, K: Integer;
  D: Pointer;
begin
  C := Pos(',', AArg);
  X := StrToIntDef(Trim(Copy(AArg, 1, C - 1)), 0);
  Y := StrToIntDef(Trim(Copy(AArg, C + 1, MaxInt)), 0);
  if AVerb = 'drag' then
  begin
    { X1,Y1,X2,Y2: in steps, as a hand moves, so a splitter follows }
    with TStringList.Create do
    try
      CommaText := AArg;
      if (Count = 4) and XtstReady then
      begin
        D := gdk_x11_get_default_xdisplay;
        XMotion(D, -1, StrToInt(Strings[0]), StrToInt(Strings[1]), 0);
        XButton(D, 1, 1, 50);
        for K := 1 to 10 do
          XMotion(D, -1, StrToInt(Strings[0]) + (StrToInt(Strings[2]) - StrToInt(Strings[0])) * K div 10,
            StrToInt(Strings[1]) + (StrToInt(Strings[3]) - StrToInt(Strings[1])) * K div 10, 20);
        XButton(D, 1, 0, 50);
        XFlushFn(D);
      end;
    finally
      Free;
    end;
    Exit;
  end;
  if not XtstReady then
  begin
    WriteLn(StdErr, 'LED_DEMO: no libXtst for ', AVerb);
    Exit;
  end;
  D := gdk_x11_get_default_xdisplay;
  { queued in the X server and handled by the window's own loop once this
    step returns -- not pumped from here: a click that opens a menu runs
    the menu's loop, which this step, inside a timer, would wait on }
  XMotion(D, -1, X, Y, 0);
  if AVerb <> 'move' then
    for K := 1 to Ord(AVerb = 'dclick') + 1 do
    begin
      XButton(D, 1, 1, 30);
      XButton(D, 1, 0, 30);
    end;
  XFlushFn(D);
end;
{$ELSE}
begin
  WriteLn(StdErr, 'LED_DEMO: ', AVerb, ' needs gtk2');
end;
{$ENDIF}

procedure TLedDemo.Shot(const APath: string);
{$IFDEF LED_DEMO_GTK2}
var
  Root: PGdkWindow;
  W, H: gint;
  Pix: PGdkPixbuf;
  Err: PGError;
begin
  Root := gdk_get_default_root_window;
  gdk_drawable_get_size(Root, @W, @H);
  Pix := gdk_pixbuf_get_from_drawable(nil, Root, nil, 0, 0, 0, 0, W, H);
  if Pix = nil then
  begin
    WriteLn(StdErr, 'LED_DEMO: the screen could not be read');
    Exit;
  end;
  Err := nil;
  if not gdk_pixbuf_save(Pix, PChar(APath), 'png', @Err, [nil]) then
    WriteLn(StdErr, 'LED_DEMO: cannot write ', APath);
  g_object_unref(Pix);
  WriteLn('LED_DEMO: ', APath);
end;
{$ELSE}
begin
  WriteLn(StdErr, 'LED_DEMO: shot needs gtk2');
end;
{$ENDIF}

procedure LedDemoStart(AForm: TCustomForm; AMenu: TMainMenu; AActions: TActionList;
  APane: TLedDemoPaneProc);
var
  D: TLedDemo;
  S: string;
begin
  S := GetEnvironmentVariable('LED_DEMO');
  if S = '' then Exit;
  D := TLedDemo.Create(AForm);
  D.FForm := AForm;
  D.FMenu := AMenu;
  D.FActions := AActions;
  D.FPane := APane;
  D.FSteps := TStringList.Create;
  D.FSteps.Delimiter := ';';
  D.FSteps.StrictDelimiter := True;
  D.FSteps.DelimitedText := S;
  D.FTimer := TTimer.Create(D);
  { the window and its panes are up, and the first idle refresh has run }
  D.FTimer.Interval := 1000;
  D.FTimer.OnTimer := @D.Tick;
  D.FTimer.Enabled := True;
end;

end.
