{ led - a light editor.  Projects: a root, launch configurations, build tasks.

  led has had two things called "project" and neither is this one.  The
  Project pane is a curated list of files with no root and no build; the user
  tools are commands with no project.  This is the third thing both of those
  deliberately are not: a folder that knows how to build and run what is in
  it.

  The format is VS Code's, because it is the one already sitting in most C
  and C++ checkouts:

    <root>/.led/launch.json      led's own, looked at first
    <root>/.vscode/launch.json   the project's existing one
    <root>/<either>/tasks.json   optional, for preLaunchTask

  Looked for by walking up from the file being edited, so opening any source
  in a tree finds the tree's configuration without being told where it is.
  `.led` first means a led-tuned configuration can shadow a project's VS Code
  one without editing it -- the same precedence medit's plugin uses for
  `.medit`.

  Two departures from medit's version, both deliberate:

    * `environment` is accepted as an object as well as an array of
      {name,value}.  medit's header documents the object form and its code
      only handles the array, so a file that reads correctly to a person is
      silently ignored.

    * variables are resolved at *use* time, not at load.  `${file}` means the
      document that is open now, so resolving once at load would freeze it to
      whatever happened to be open when the folder was first seen.

  No LCL dependency, so the headless suite covers all of it. }
unit Led.Core.Project;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, jsonscanner;

const
  { Searched in this order at every level on the way up. }
  LedProjectDirs: array[0..1] of string = ('.led', '.vscode');

type
  { One entry of launch.json's "configurations". }
  TLedLaunchConfig = class
  private
    FArgs: TStringList;
    FEnvironment: TStringList;   // name=value, in file order
  public
    Name: string;
    Program_: string;            // "program", or led's "target"
    Cwd: string;
    PreLaunchTask: string;
    BuildCommand: string;        // "build", or resolved from tasks.json
    StopAtEntry: Boolean;
    constructor Create;
    destructor Destroy; override;
    property Args: TStringList read FArgs;
    property Environment: TStringList read FEnvironment;
  end;

  TLedProject = class
  private
    FRoot: string;
    FConfigDir: string;          // absolute path of the .led / .vscode folder
    FLaunchPath: string;
    FConfigs: TFPList;           // of TLedLaunchConfig, owned
    FTasks: TStringList;         // label=command
    procedure Clear;
    procedure ReadLaunch(const AText: string);
    procedure ReadTasks(const AText: string);
    function GetConfig(AIndex: Integer): TLedLaunchConfig;
  public
    constructor Create;
    destructor Destroy; override;

    { Walks up from AStartPath -- a file or a directory -- looking for a
      configuration.  False when there is none, leaving the project empty
      rather than raising: not having a project is the normal case. }
    function LoadFrom(const AStartPath: string): Boolean;

    function ConfigCount: Integer;
    property Configs[AIndex: Integer]: TLedLaunchConfig read GetConfig; default;
    function FindConfig(const AName: string): TLedLaunchConfig;

    { Substitutes ${...} against this project and the document open now.
      An unknown variable is left as written, so a typo shows up in the error
      message instead of turning into an empty string. }
    function Resolve(const ARaw, AActiveFile: string): string;

    { The command that builds AConfig: its own "build", else the command its
      preLaunchTask names in tasks.json.  '' when there is neither. }
    function BuildCommandFor(AConfig: TLedLaunchConfig): string;

    property Root: string read FRoot;
    property ConfigDir: string read FConfigDir;
    property LaunchPath: string read FLaunchPath;
    property Tasks: TStringList read FTasks;
  end;

{ The root of the project AStartPath belongs to, or '' when it belongs to
  none.  AConfigDir and ALaunchPath come back absolute. }
function LedFindProjectRoot(const AStartPath: string;
  out AConfigDir, ALaunchPath: string): string;

{ Parses JSON the way people actually write launch.json: with // comments and
  trailing commas.  fpjson's GetJSON refuses both. }
function LedParseJsonc(const AText: string): TJSONData;

{ Quotes an argument for /bin/sh.  tasks.json splits a command from its
  arguments, and they have to be rejoined without a space in a path becoming
  two arguments. }
function LedShellQuote(const AText: string): string;

{ True when ABinary needs rebuilding: it is missing, or some source under
  ARoot is newer than it.

  Deliberately shallow and cheap.  It runs before every Start, so it must not
  walk a whole checkout: it stops at ADepth levels, skips hidden directories
  and the usual output and dependency folders, and looks only at the
  extensions a C or C++ program is built from.  Getting it wrong in the
  cautious direction costs a rebuild; getting it wrong the other way debugs
  yesterday's binary, so a file it cannot stat counts as newer. }
function LedBinaryIsStale(const ARoot, ABinary: string;
  ADepth: Integer = 5): Boolean;

implementation

{ --- helpers --------------------------------------------------------------- }

function LedParseJsonc(const AText: string): TJSONData;
var
  P: TJSONParser;
begin
  Result := nil;
  if Trim(AText) = '' then Exit;
  { The same option set the vendored TextMate engine uses on grammar files,
    for the same reason: real-world JSON in a repository has comments in it. }
  P := TJSONParser.Create(AText, [joUTF8, joComments, joIgnoreTrailingComma]);
  try
    try
      Result := P.Parse;
    except
      Result := nil;
    end;
  finally
    P.Free;
  end;
end;

function LedShellQuote(const AText: string): string;
var
  i: Integer;
  Safe: Boolean;
begin
  { Nothing to do for a plain word, and leaving it alone keeps the command
    readable when it is echoed into the output pane. }
  Safe := AText <> '';
  for i := 1 to Length(AText) do
    if not (AText[i] in ['A'..'Z', 'a'..'z', '0'..'9',
                         '_', '-', '.', '/', ':', '=', '+', ',', '@', '%']) then
    begin
      Safe := False;
      Break;
    end;
  if Safe then Exit(AText);

  { Single quotes, with the one escape sh allows: end the quoting, emit a
    literal quote, start again. }
  Result := '''' + StringReplace(AText, '''', '''\''''', [rfReplaceAll]) + '''';
end;

function JStr(AObj: TJSONObject; const AName, ADefault: string): string;
var
  D: TJSONData;
begin
  Result := ADefault;
  if AObj = nil then Exit;
  D := AObj.Find(AName);
  if (D <> nil) and (D.JSONType in [jtString, jtNumber, jtBoolean]) then
    Result := D.AsString;
end;

function LedFindProjectRoot(const AStartPath: string;
  out AConfigDir, ALaunchPath: string): string;
var
  Dir, Prev, Cand, Launch: string;
  k: Integer;
begin
  Result := '';
  AConfigDir := '';
  ALaunchPath := '';
  if AStartPath = '' then Exit;

  Dir := ExpandFileName(AStartPath);
  if not DirectoryExists(Dir) then
    Dir := ExtractFileDir(Dir);

  Prev := '';
  while (Dir <> '') and (Dir <> Prev) do
  begin
    for k := 0 to High(LedProjectDirs) do
    begin
      Cand := IncludeTrailingPathDelimiter(Dir) + LedProjectDirs[k];
      Launch := IncludeTrailingPathDelimiter(Cand) + 'launch.json';
      if FileExists(Launch) then
      begin
        AConfigDir := Cand;
        ALaunchPath := Launch;
        Exit(Dir);
      end;
    end;
    Prev := Dir;
    Dir := ExtractFileDir(Dir);
  end;
end;

function LedBinaryIsStale(const ARoot, ABinary: string;
  ADepth: Integer): Boolean;
const
  SourceExts: array[0..7] of string =
    ('.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp', '.hxx');
  { Where build output and other people's code live.  Walking these is both
    slow and pointless -- a freshly written object file is not a reason to
    rebuild. }
  SkipDirs: array[0..7] of string =
    ('build', 'build-md', 'build-rel', 'node_modules', 'bin', 'obj',
     'target', 'dist');
var
  BinAge: TDateTime;

  function IsSource(const AName: string): Boolean;
  var
    Ext: string;
    k: Integer;
  begin
    Ext := LowerCase(ExtractFileExt(AName));
    for k := 0 to High(SourceExts) do
      if Ext = SourceExts[k] then Exit(True);
    Result := False;
  end;

  function Skip(const AName: string): Boolean;
  var
    k: Integer;
  begin
    Result := (AName = '') or (AName[1] = '.');
    if Result then Exit;
    for k := 0 to High(SkipDirs) do
      if SameText(AName, SkipDirs[k]) then Exit(True);
  end;

  function Walk(const ADir: string; ALeft: Integer): Boolean;
  var
    R: TSearchRec;
    Age: TDateTime;
  begin
    Result := False;
    if ALeft < 0 then Exit;
    if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, R) <> 0 then
      Exit;
    try
      repeat
        if (R.Name = '.') or (R.Name = '..') then Continue;
        if (R.Attr and faDirectory) <> 0 then
        begin
          if Skip(R.Name) then Continue;
          if Walk(IncludeTrailingPathDelimiter(ADir) + R.Name, ALeft - 1) then
            Exit(True);
        end
        else if IsSource(R.Name) then
        begin
          if FileAge(IncludeTrailingPathDelimiter(ADir) + R.Name, Age) then
          begin
            if Age > BinAge then Exit(True);
          end
          else
            { Cannot be read now; assume it moved. }
            Exit(True);
        end;
      until FindNext(R) <> 0;
    finally
      FindClose(R);
    end;
  end;

begin
  if ABinary = '' then Exit(True);
  if not FileExists(ABinary) then Exit(True);
  if (ARoot = '') or (not DirectoryExists(ARoot)) then Exit(False);
  if not FileAge(ABinary, BinAge) then Exit(True);
  Result := Walk(ExcludeTrailingPathDelimiter(ARoot), ADepth);
end;

{ --- TLedLaunchConfig ------------------------------------------------------ }

constructor TLedLaunchConfig.Create;
begin
  inherited Create;
  FArgs := TStringList.Create;
  FEnvironment := TStringList.Create;
end;

destructor TLedLaunchConfig.Destroy;
begin
  FEnvironment.Free;
  FArgs.Free;
  inherited Destroy;
end;

{ --- TLedProject ----------------------------------------------------------- }

constructor TLedProject.Create;
begin
  inherited Create;
  FConfigs := TFPList.Create;
  FTasks := TStringList.Create;
end;

destructor TLedProject.Destroy;
begin
  Clear;
  FConfigs.Free;
  FTasks.Free;
  inherited Destroy;
end;

procedure TLedProject.Clear;
var
  i: Integer;
begin
  for i := 0 to FConfigs.Count - 1 do
    TLedLaunchConfig(FConfigs[i]).Free;
  FConfigs.Clear;
  FTasks.Clear;
  FRoot := '';
  FConfigDir := '';
  FLaunchPath := '';
end;

function TLedProject.ConfigCount: Integer;
begin
  Result := FConfigs.Count;
end;

function TLedProject.GetConfig(AIndex: Integer): TLedLaunchConfig;
begin
  if (AIndex < 0) or (AIndex >= FConfigs.Count) then Exit(nil);
  Result := TLedLaunchConfig(FConfigs[AIndex]);
end;

function TLedProject.FindConfig(const AName: string): TLedLaunchConfig;
var
  i: Integer;
begin
  for i := 0 to FConfigs.Count - 1 do
    if TLedLaunchConfig(FConfigs[i]).Name = AName then
      Exit(TLedLaunchConfig(FConfigs[i]));
  Result := nil;
end;

{ Is this a configuration gdb can run?  An unknown type is somebody else's
  debugger -- a "pwa-chrome" entry in the dropdown would only mislead -- but a
  file with no type at all is a hand-written one, and that is for us. }
function ConfigIsForGdb(AObj: TJSONObject): Boolean;
var
  T: string;
begin
  T := LowerCase(JStr(AObj, 'type', ''));
  Result := (T = '') or (T = 'cppdbg') or (T = 'gdb') or (T = 'cppvsdbg') or
            (T = 'by-gdb') or (T = 'cortex-debug');
end;

procedure TLedProject.ReadLaunch(const AText: string);
var
  Data: TJSONData;
  Doc: TJSONObject;
  Arr, Sub: TJSONArray;
  Obj, EObj: TJSONObject;
  C: TLedLaunchConfig;
  i, j: Integer;
  D: TJSONData;
begin
  Data := LedParseJsonc(AText);
  if Data = nil then Exit;
  try
    if not (Data is TJSONObject) then Exit;
    Doc := TJSONObject(Data);
    D := Doc.Find('configurations');
    if not (D is TJSONArray) then Exit;
    Arr := TJSONArray(D);

    for i := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      Obj := TJSONObject(Arr.Items[i]);
      if not ConfigIsForGdb(Obj) then Continue;

      C := TLedLaunchConfig.Create;
      C.Name := JStr(Obj, 'name', '(unnamed)');
      { "target" is led's own spelling; "program" is VS Code's. }
      C.Program_ := JStr(Obj, 'program', JStr(Obj, 'target', ''));
      C.Cwd := JStr(Obj, 'cwd', '');
      C.PreLaunchTask := JStr(Obj, 'preLaunchTask', '');
      C.BuildCommand := JStr(Obj, 'build', '');
      C.StopAtEntry := LowerCase(JStr(Obj, 'stopAtEntry', 'false')) = 'true';

      D := Obj.Find('args');
      if D is TJSONArray then
      begin
        Sub := TJSONArray(D);
        for j := 0 to Sub.Count - 1 do
          C.Args.Add(Sub.Items[j].AsString);
      end;

      D := Obj.Find('environment');
      if D is TJSONArray then
      begin
        { VS Code's shape: [{"name":"X","value":"1"}] }
        Sub := TJSONArray(D);
        for j := 0 to Sub.Count - 1 do
          if Sub.Items[j] is TJSONObject then
          begin
            EObj := TJSONObject(Sub.Items[j]);
            if JStr(EObj, 'name', '') <> '' then
              C.Environment.Add(JStr(EObj, 'name', '') + '=' +
                                JStr(EObj, 'value', ''));
          end;
      end
      else if D is TJSONObject then
      begin
        { The plain object anybody would write, and which medit's own header
          promises.  Accepted here. }
        EObj := TJSONObject(D);
        for j := 0 to EObj.Count - 1 do
          C.Environment.Add(EObj.Names[j] + '=' + EObj.Items[j].AsString);
      end;

      FConfigs.Add(C);
    end;
  finally
    Data.Free;
  end;
end;

procedure TLedProject.ReadTasks(const AText: string);
var
  Data: TJSONData;
  Doc: TJSONObject;
  Arr, ArgArr: TJSONArray;
  Obj: TJSONObject;
  i, j: Integer;
  D: TJSONData;
  Cmd, Lbl: string;
begin
  Data := LedParseJsonc(AText);
  if Data = nil then Exit;
  try
    if not (Data is TJSONObject) then Exit;
    Doc := TJSONObject(Data);
    D := Doc.Find('tasks');
    if not (D is TJSONArray) then Exit;
    Arr := TJSONArray(D);

    for i := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      Obj := TJSONObject(Arr.Items[i]);
      Lbl := JStr(Obj, 'label', '');
      Cmd := JStr(Obj, 'command', '');
      if (Lbl = '') or (Cmd = '') then Continue;

      D := Obj.Find('args');
      if D is TJSONArray then
      begin
        { With arguments the whole line has to be quoted, or a path with a
          space in it becomes two arguments.  Without them the command is
          taken verbatim, so "make -j8" in one string still works. }
        ArgArr := TJSONArray(D);
        Cmd := LedShellQuote(Cmd);
        for j := 0 to ArgArr.Count - 1 do
          Cmd := Cmd + ' ' + LedShellQuote(ArgArr.Items[j].AsString);
      end;
      FTasks.Values[Lbl] := Cmd;
    end;
  finally
    Data.Free;
  end;
end;

function TLedProject.LoadFrom(const AStartPath: string): Boolean;
var
  L: TStringList;
  TasksPath: string;
begin
  Clear;
  FRoot := LedFindProjectRoot(AStartPath, FConfigDir, FLaunchPath);
  Result := FRoot <> '';
  if not Result then Exit;

  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FLaunchPath);
      ReadLaunch(L.Text);
    except
      { A launch.json that cannot be read leaves an empty configuration list
        and a valid root, which is what the UI needs to say so. }
    end;

    TasksPath := IncludeTrailingPathDelimiter(FConfigDir) + 'tasks.json';
    if FileExists(TasksPath) then
      try
        L.LoadFromFile(TasksPath);
        ReadTasks(L.Text);
      except
      end;
  finally
    L.Free;
  end;
end;

function TLedProject.BuildCommandFor(AConfig: TLedLaunchConfig): string;
begin
  Result := '';
  if AConfig = nil then Exit;
  if AConfig.BuildCommand <> '' then Exit(AConfig.BuildCommand);
  if AConfig.PreLaunchTask <> '' then
    Result := FTasks.Values[AConfig.PreLaunchTask];
end;

function TLedProject.Resolve(const ARaw, AActiveFile: string): string;
var
  i, Close_: Integer;
  Body, Repl: string;
  Known: Boolean;
begin
  Result := '';
  i := 1;
  while i <= Length(ARaw) do
  begin
    if (i + 1 <= Length(ARaw)) and (ARaw[i] = '$') and (ARaw[i + 1] = '{') then
    begin
      Close_ := i + 2;
      while (Close_ <= Length(ARaw)) and (ARaw[Close_] <> '}') do Inc(Close_);
      if Close_ > Length(ARaw) then
      begin
        { Unterminated.  Emit the rest as written so the typo is visible. }
        Result := Result + Copy(ARaw, i, Length(ARaw));
        Exit;
      end;

      Body := Copy(ARaw, i + 2, Close_ - i - 2);
      Known := True;
      if Body = 'workspaceFolder' then
        Repl := FRoot
      else if Body = 'workspaceFolderBasename' then
        Repl := ExtractFileName(ExcludeTrailingPathDelimiter(FRoot))
      else if Body = 'file' then
        Repl := AActiveFile
      else if Body = 'fileBasename' then
        Repl := ExtractFileName(AActiveFile)
      else if Body = 'fileBasenameNoExtension' then
        Repl := ChangeFileExt(ExtractFileName(AActiveFile), '')
      else if Body = 'fileDirname' then
        Repl := ExcludeTrailingPathDelimiter(ExtractFileDir(AActiveFile))
      else if Body = 'cwd' then
        Repl := GetCurrentDir
      else if (Length(Body) > 4) and (Copy(Body, 1, 4) = 'env:') then
        Repl := GetEnvironmentVariable(Copy(Body, 5, Length(Body)))
      else
      begin
        Known := False;
        Repl := '';
      end;

      if Known then
        Result := Result + Repl
      else
        { Left exactly as written -- see the note on the declaration. }
        Result := Result + Copy(ARaw, i, Close_ - i + 1);
      i := Close_ + 1;
      Continue;
    end;
    Result := Result + ARaw[i];
    Inc(i);
  end;
end;

end.
