{ led - a light editor.  Session and recent-file persistence.

  medit stored these as XML; led uses JSON, because the shape is nested and
  array-heavy -- windows hold tabs hold per-tab state -- and JSON expresses
  that without the Count/ItemN idiom an INI or XMLConf file would force.

  Both files are written atomically with one generation of backup: a session
  file truncated by a power cut is a bad way to greet someone at startup.

  No LCL dependency. }
unit Led.Core.Session;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, Led.Core.Paths;

const
  LedSessionVersion = 1;

type
  { One view of a document inside a tab.  A tab that has been split holds
    several, each with its own caret and scroll position. }
  TLedViewState = record
    Line: Integer;        // 1-based caret position
    Column: Integer;
    TopLine: Integer;     // first visible line, so the view is restored too
  end;

  TLedTabState = record
    FileName: string;
    Encoding: string;
    Language: string;
    Line: Integer;        // the active view's caret, kept for older sessions
    Column: Integer;
    TopLine: Integer;
    { Which tab group the tab was in.  0 is the only one unless the notebook
      is split; without this, everything the user moved into the second group
      was dropped on save without a word. }
    Notebook: Integer;
    { Every view, in creation order, and how the tab was split to make them.
      Empty for a session written before split views were recorded, in which
      case Line/Column/TopLine above still describe the single view. }
    Views: array of TLedViewState;
    SplitVertical: Boolean;
  end;

  TLedDockState = record
    Visible: Boolean;
    Size: Integer;
    ActivePane: string;
  end;

  TLedWindowState = record
    Left, Top, Width, Height: Integer;
    Maximized: Boolean;
    ActiveTab: Integer;
    Tabs: array of TLedTabState;
    Docks: array[0..3] of TLedDockState;   // left, right, top, bottom
  end;

  TLedSession = class
  private
    FWindows: array of TLedWindowState;
    FFileName: string;
    function GetWindow(AIndex: Integer): TLedWindowState;
    function GetWindowCount: Integer;
  public
    constructor Create(const AFileName: string = '');

    procedure Clear;
    function AddWindow: Integer;
    procedure SetWindow(AIndex: Integer; const AState: TLedWindowState);
    function AddTab(AWindow: Integer; const ATab: TLedTabState): Integer;

    { Returns False when there is nothing to restore -- no file, or a file
      written by a version that is not understood.  Never raises: a corrupt
      session must not stop the editor from starting. }
    function Load: Boolean;
    procedure Save;

    property Windows[AIndex: Integer]: TLedWindowState read GetWindow;
    property WindowCount: Integer read GetWindowCount;
    property FileName: string read FFileName;
  end;

  { The Open Recent list: newest first, capped, de-duplicated by path. }
  TLedRecentFiles = class
  private
    FItems: TStringList;
    FFileName: string;
    FMax: Integer;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): string;
  public
    constructor Create(const AFileName: string = ''; AMax: Integer = 20);
    destructor Destroy; override;
    procedure Add(const APath: string);
    procedure Remove(const APath: string);
    procedure Clear;
    procedure Load;
    procedure Save;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: string read GetItem; default;
    property Max: Integer read FMax write FMax;
  end;

implementation

{ TLedSession }

constructor TLedSession.Create(const AFileName: string);
begin
  inherited Create;
  if AFileName <> '' then
    FFileName := AFileName
  else
    FFileName := LedConfigFile('session.json');
end;

procedure TLedSession.Clear;
begin
  SetLength(FWindows, 0);
end;

function TLedSession.GetWindowCount: Integer;
begin
  Result := Length(FWindows);
end;

function TLedSession.GetWindow(AIndex: Integer): TLedWindowState;
begin
  Result := FWindows[AIndex];
end;

function TLedSession.AddWindow: Integer;
begin
  Result := Length(FWindows);
  SetLength(FWindows, Result + 1);
  FWindows[Result] := Default(TLedWindowState);
end;

procedure TLedSession.SetWindow(AIndex: Integer; const AState: TLedWindowState);
begin
  FWindows[AIndex] := AState;
end;

function TLedSession.AddTab(AWindow: Integer; const ATab: TLedTabState): Integer;
begin
  Result := Length(FWindows[AWindow].Tabs);
  SetLength(FWindows[AWindow].Tabs, Result + 1);
  FWindows[AWindow].Tabs[Result] := ATab;
end;

procedure TLedSession.Save;
var
  Root: TJSONObject;
  WinArr, TabArr, DockArr, ViewArr: TJSONArray;
  WinObj, TabObj, DockObj, ViewObj: TJSONObject;
  i, j, k, v: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('version', LedSessionVersion);
    WinArr := TJSONArray.Create;
    Root.Add('windows', WinArr);

    for i := 0 to High(FWindows) do
    begin
      WinObj := TJSONObject.Create;
      WinArr.Add(WinObj);
      WinObj.Add('left', FWindows[i].Left);
      WinObj.Add('top', FWindows[i].Top);
      WinObj.Add('width', FWindows[i].Width);
      WinObj.Add('height', FWindows[i].Height);
      WinObj.Add('maximized', FWindows[i].Maximized);
      WinObj.Add('activeTab', FWindows[i].ActiveTab);

      TabArr := TJSONArray.Create;
      WinObj.Add('tabs', TabArr);
      for j := 0 to High(FWindows[i].Tabs) do
      begin
        TabObj := TJSONObject.Create;
        TabArr.Add(TabObj);
        TabObj.Add('file', FWindows[i].Tabs[j].FileName);
        TabObj.Add('encoding', FWindows[i].Tabs[j].Encoding);
        TabObj.Add('language', FWindows[i].Tabs[j].Language);
        TabObj.Add('line', FWindows[i].Tabs[j].Line);
        TabObj.Add('column', FWindows[i].Tabs[j].Column);
        TabObj.Add('topLine', FWindows[i].Tabs[j].TopLine);
        TabObj.Add('notebook', FWindows[i].Tabs[j].Notebook);
        if Length(FWindows[i].Tabs[j].Views) > 1 then
        begin
          TabObj.Add('splitVertical', FWindows[i].Tabs[j].SplitVertical);
          ViewArr := TJSONArray.Create;
          TabObj.Add('views', ViewArr);
          for v := 0 to High(FWindows[i].Tabs[j].Views) do
          begin
            ViewObj := TJSONObject.Create;
            ViewArr.Add(ViewObj);
            ViewObj.Add('line', FWindows[i].Tabs[j].Views[v].Line);
            ViewObj.Add('column', FWindows[i].Tabs[j].Views[v].Column);
            ViewObj.Add('topLine', FWindows[i].Tabs[j].Views[v].TopLine);
          end;
        end;
      end;

      DockArr := TJSONArray.Create;
      WinObj.Add('docks', DockArr);
      for k := 0 to 3 do
      begin
        DockObj := TJSONObject.Create;
        DockArr.Add(DockObj);
        DockObj.Add('visible', FWindows[i].Docks[k].Visible);
        DockObj.Add('size', FWindows[i].Docks[k].Size);
        DockObj.Add('activePane', FWindows[i].Docks[k].ActivePane);
      end;
    end;

    LedWriteFileAtomic(FFileName, Root.FormatJSON);
  finally
    Root.Free;
  end;
end;

function TLedSession.Load: Boolean;
var
  Text: string;
  Data: TJSONData;
  Root, WinObj, TabObj, DockObj, ViewObj: TJSONObject;
  WinArr, TabArr, DockArr, ViewArr: TJSONArray;
  L: TStringList;
  i, j, k, w, v: Integer;
  Tab: TLedTabState;
begin
  Clear;
  Result := False;
  if not FileExists(FFileName) then Exit;

  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FFileName);
      Text := L.Text;
    except
      Exit;
    end;
  finally
    L.Free;
  end;

  Data := nil;
  try
    try
      Data := GetJSON(Text);
    except
      { A corrupt session file must never stop startup. }
      Exit;
    end;
    if not (Data is TJSONObject) then Exit;
    Root := TJSONObject(Data);
    if Root.Get('version', 0) <> LedSessionVersion then Exit;

    WinArr := Root.Get('windows', TJSONArray(nil));
    if WinArr = nil then Exit;

    for i := 0 to WinArr.Count - 1 do
    begin
      if not (WinArr.Items[i] is TJSONObject) then Continue;
      WinObj := TJSONObject(WinArr.Items[i]);
      w := AddWindow;
      FWindows[w].Left := WinObj.Get('left', 0);
      FWindows[w].Top := WinObj.Get('top', 0);
      FWindows[w].Width := WinObj.Get('width', 0);
      FWindows[w].Height := WinObj.Get('height', 0);
      FWindows[w].Maximized := WinObj.Get('maximized', False);
      FWindows[w].ActiveTab := WinObj.Get('activeTab', 0);

      TabArr := WinObj.Get('tabs', TJSONArray(nil));
      if TabArr <> nil then
        for j := 0 to TabArr.Count - 1 do
        begin
          if not (TabArr.Items[j] is TJSONObject) then Continue;
          TabObj := TJSONObject(TabArr.Items[j]);
          Tab := Default(TLedTabState);
          Tab.FileName := TabObj.Get('file', '');
          Tab.Encoding := TabObj.Get('encoding', '');
          Tab.Language := TabObj.Get('language', '');
          Tab.Line := TabObj.Get('line', 1);
          Tab.Column := TabObj.Get('column', 1);
          Tab.TopLine := TabObj.Get('topLine', 1);
          Tab.Notebook := TabObj.Get('notebook', 0);
          Tab.SplitVertical := TabObj.Get('splitVertical', False);

          ViewArr := TabObj.Get('views', TJSONArray(nil));
          if ViewArr <> nil then
          begin
            SetLength(Tab.Views, ViewArr.Count);
            for v := 0 to ViewArr.Count - 1 do
              if ViewArr.Items[v] is TJSONObject then
              begin
                ViewObj := TJSONObject(ViewArr.Items[v]);
                Tab.Views[v].Line := ViewObj.Get('line', 1);
                Tab.Views[v].Column := ViewObj.Get('column', 1);
                Tab.Views[v].TopLine := ViewObj.Get('topLine', 1);
              end;
          end;

          if Tab.FileName <> '' then
            AddTab(w, Tab);
        end;

      DockArr := WinObj.Get('docks', TJSONArray(nil));
      if DockArr <> nil then
        for k := 0 to DockArr.Count - 1 do
        begin
          if (k > 3) or not (DockArr.Items[k] is TJSONObject) then Continue;
          DockObj := TJSONObject(DockArr.Items[k]);
          FWindows[w].Docks[k].Visible := DockObj.Get('visible', False);
          FWindows[w].Docks[k].Size := DockObj.Get('size', 0);
          FWindows[w].Docks[k].ActivePane := DockObj.Get('activePane', '');
        end;
    end;

    Result := True;
  finally
    Data.Free;
  end;
end;

{ TLedRecentFiles }

constructor TLedRecentFiles.Create(const AFileName: string; AMax: Integer);
begin
  inherited Create;
  FItems := TStringList.Create;
  FMax := AMax;
  if AFileName <> '' then
    FFileName := AFileName
  else
    FFileName := LedConfigFile('recent.json');
end;

destructor TLedRecentFiles.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TLedRecentFiles.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TLedRecentFiles.GetItem(AIndex: Integer): string;
begin
  Result := FItems[AIndex];
end;

procedure TLedRecentFiles.Add(const APath: string);
var
  Full: string;
  i: Integer;
begin
  if APath = '' then Exit;
  Full := ExpandFileName(APath);
  { Re-opening a file moves it to the top rather than duplicating it. }
  for i := FItems.Count - 1 downto 0 do
    if {$IFDEF WINDOWS}SameText{$ELSE}SameStr{$ENDIF}(FItems[i], Full) then
      FItems.Delete(i);
  FItems.Insert(0, Full);
  while FItems.Count > FMax do
    FItems.Delete(FItems.Count - 1);
end;

procedure TLedRecentFiles.Remove(const APath: string);
var
  i: Integer;
  Full: string;
begin
  Full := ExpandFileName(APath);
  for i := FItems.Count - 1 downto 0 do
    if {$IFDEF WINDOWS}SameText{$ELSE}SameStr{$ENDIF}(FItems[i], Full) then
      FItems.Delete(i);
end;

procedure TLedRecentFiles.Clear;
begin
  FItems.Clear;
end;

procedure TLedRecentFiles.Load;
var
  Data: TJSONData;
  Arr: TJSONArray;
  L: TStringList;
  i: Integer;
begin
  FItems.Clear;
  if not FileExists(FFileName) then Exit;

  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FFileName);
    except
      Exit;
    end;
    Data := nil;
    try
      try
        Data := GetJSON(L.Text);
      except
        Exit;
      end;
      if not (Data is TJSONArray) then Exit;
      Arr := TJSONArray(Data);
      for i := 0 to Arr.Count - 1 do
        if (Arr.Items[i].JSONType = jtString) and (FItems.Count < FMax) then
          FItems.Add(Arr.Items[i].AsString);
    finally
      Data.Free;
    end;
  finally
    L.Free;
  end;
end;

procedure TLedRecentFiles.Save;
var
  Arr: TJSONArray;
  i: Integer;
begin
  Arr := TJSONArray.Create;
  try
    for i := 0 to FItems.Count - 1 do
      Arr.Add(FItems[i]);
    LedWriteFileAtomic(FFileName, Arr.FormatJSON);
  finally
    Arr.Free;
  end;
end;

end.
