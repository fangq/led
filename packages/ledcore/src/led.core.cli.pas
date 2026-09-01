{ led - a light editor.  Command line parsing.

  medit's option set, carried over so muscle memory and scripts keep working,
  including the "file:123" suffix that opens a file at a line.

  Pure string handling with no side effects, so the whole grammar can be
  tested headlessly -- which matters, because argument parsing is exactly the
  sort of code that quietly mis-handles one case forever. }
unit Led.Core.CLI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TLedFileArg = record
    Path: string;
    Line: Integer;        // 0 when unspecified
    Encoding: string;
  end;

  TLedCommandLine = class
  private
    FFiles: array of TLedFileArg;
    FErrors: TStringList;
    function GetFile(AIndex: Integer): TLedFileArg;
    function GetFileCount: Integer;
  public
    NewApp: Boolean;          // --new-app: do not hand over to a running one
    NewWindow: Boolean;
    NewTab: Boolean;
    Reload: Boolean;
    ShowVersion: Boolean;
    ShowHelp: Boolean;
    SelfTest: Boolean;
    BenchLongLine: Boolean;
    UseSession: Boolean;
    UseSessionSet: Boolean;
    AppName: string;
    Geometry: string;
    ScriptFile: string;

    constructor Create;
    destructor Destroy; override;

    { Parses the given arguments (excluding the program name).  Unknown
      options are recorded in Errors rather than silently ignored, so a typo
      does not look like a file that failed to open. }
    procedure Parse(AArgs: TStrings);
    procedure ParseCommandLine;

    { The file list rendered for handing to a running instance. }
    function ToJSON(const ACwd: string): string;
    procedure FromJSON(const AJSON: string; out ACwd: string);

    function HelpText: string;
    property Files[AIndex: Integer]: TLedFileArg read GetFile;
    property FileCount: Integer read GetFileCount;
    property Errors: TStringList read FErrors;
  end;

implementation

uses
  fpjson, jsonparser;

constructor TLedCommandLine.Create;
begin
  inherited Create;
  FErrors := TStringList.Create;
end;

destructor TLedCommandLine.Destroy;
begin
  FErrors.Free;
  inherited Destroy;
end;

function TLedCommandLine.GetFileCount: Integer;
begin
  Result := Length(FFiles);
end;

function TLedCommandLine.GetFile(AIndex: Integer): TLedFileArg;
begin
  Result := FFiles[AIndex];
end;

{ "notes.txt:42" opens at line 42.  A bare colon in a name is common on Unix
  and must not be mistaken for this, so the suffix counts only when every
  character after the last colon is a digit -- and, on Windows, only when the
  colon is not the drive separator. }
procedure SplitLineSuffix(const AArg: string; out APath: string;
  out ALine: Integer);
var
  P, i: Integer;
  Tail: string;
begin
  APath := AArg;
  ALine := 0;
  P := LastDelimiter(':', AArg);
  if P < 2 then Exit;
  {$IFDEF WINDOWS}
  if (P = 2) and (Length(AArg) > 2) then Exit;   // C:\...
  {$ENDIF}
  Tail := Copy(AArg, P + 1, MaxInt);
  if Tail = '' then Exit;
  for i := 1 to Length(Tail) do
    if not (Tail[i] in ['0'..'9']) then Exit;
  APath := Copy(AArg, 1, P - 1);
  ALine := StrToIntDef(Tail, 0);
end;

procedure TLedCommandLine.Parse(AArgs: TStrings);
var
  i, Line: Integer;
  Arg, Value, Path: string;
  PendingLine: Integer;
  PendingEncoding: string;

  { Options are accepted as --name=value and as --name value.  Returns True
    when the option *name* matched, whether or not a value followed, so that
    a missing value is reported once rather than also being mistaken for an
    unknown option further down the chain. }
  function TakeValue(const AName: string; out AValue: string): Boolean;
  begin
    AValue := '';
    Result := False;
    if Arg = AName then
    begin
      Result := True;
      if i + 1 < AArgs.Count then
      begin
        Inc(i);
        AValue := AArgs[i];
      end
      else
        FErrors.Add(Format('%s needs a value.', [AName]));
    end
    else if Copy(Arg, 1, Length(AName) + 1) = AName + '=' then
    begin
      AValue := Copy(Arg, Length(AName) + 2, MaxInt);
      Result := True;
    end;
  end;

begin
  SetLength(FFiles, 0);
  FErrors.Clear;
  PendingLine := 0;
  PendingEncoding := '';

  i := 0;
  while i < AArgs.Count do
  begin
    Arg := AArgs[i];

    if Arg = '--' then
    begin
      { Everything after -- is a file, however it is spelled. }
      Inc(i);
      while i < AArgs.Count do
      begin
        SetLength(FFiles, Length(FFiles) + 1);
        FFiles[High(FFiles)].Path := AArgs[i];
        FFiles[High(FFiles)].Line := PendingLine;
        FFiles[High(FFiles)].Encoding := PendingEncoding;
        Inc(i);
      end;
      Break;
    end;

    if (Arg <> '') and (Arg[1] = '-') then
    begin
      if (Arg = '-n') or (Arg = '--new-app') then NewApp := True
      else if (Arg = '-w') or (Arg = '--new-window') then NewWindow := True
      else if (Arg = '-t') or (Arg = '--new-tab') then NewTab := True
      else if (Arg = '-r') or (Arg = '--reload') then Reload := True
      else if Arg = '--version' then ShowVersion := True
      else if (Arg = '-h') or (Arg = '--help') then ShowHelp := True
      else if Arg = '--self-test' then SelfTest := True
      else if Arg = '--bench-longline' then BenchLongLine := True
      else if TakeValue('--app-name', Value) then AppName := Value
      else if TakeValue('--geometry', Value) then Geometry := Value
      else if TakeValue('--script', Value) then ScriptFile := Value
      else if TakeValue('--encoding', Value) or TakeValue('-e', Value) then
        PendingEncoding := Value
      else if TakeValue('--line', Value) or TakeValue('-l', Value) then
      begin
        if Value = '' then
          { already reported as a missing value }
        else if TryStrToInt(Value, Line) then PendingLine := Line
        else FErrors.Add(Format('"%s" is not a line number.', [Value]));
      end
      else if TakeValue('--use-session', Value) then
      begin
        UseSessionSet := True;
        UseSession := (LowerCase(Value) = 'yes') or (Value = '1');
      end
      else if Arg = '-s' then
      begin
        UseSessionSet := True;
        UseSession := True;
      end
      else
        FErrors.Add(Format('Unknown option "%s".', [Arg]));
    end
    else
    begin
      SplitLineSuffix(Arg, Path, Line);
      SetLength(FFiles, Length(FFiles) + 1);
      FFiles[High(FFiles)].Path := Path;
      { An explicit --line wins over a :NN suffix, since it was typed later
        and more deliberately. }
      if PendingLine > 0 then
        FFiles[High(FFiles)].Line := PendingLine
      else
        FFiles[High(FFiles)].Line := Line;
      FFiles[High(FFiles)].Encoding := PendingEncoding;
    end;

    Inc(i);
  end;
end;

procedure TLedCommandLine.ParseCommandLine;
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    for i := 1 to ParamCount do
      L.Add(ParamStr(i));
    Parse(L);
  finally
    L.Free;
  end;
end;

function TLedCommandLine.ToJSON(const ACwd: string): string;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  Obj: TJSONObject;
  i: Integer;
begin
  Root := TJSONObject.Create;
  try
    { The client's directory travels with the request: relative paths must be
      resolved against where the user typed them, not where the running
      instance happens to have been started. }
    Root.Add('cwd', ACwd);
    Root.Add('newWindow', NewWindow);
    Root.Add('newTab', NewTab);
    Root.Add('reload', Reload);
    Arr := TJSONArray.Create;
    Root.Add('files', Arr);
    for i := 0 to High(FFiles) do
    begin
      Obj := TJSONObject.Create;
      Arr.Add(Obj);
      Obj.Add('path', FFiles[i].Path);
      Obj.Add('line', FFiles[i].Line);
      Obj.Add('encoding', FFiles[i].Encoding);
    end;
    Result := Root.AsJSON;
  finally
    Root.Free;
  end;
end;

procedure TLedCommandLine.FromJSON(const AJSON: string; out ACwd: string);
var
  Data: TJSONData;
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  i: Integer;
begin
  ACwd := '';
  SetLength(FFiles, 0);
  Data := nil;
  try
    try
      Data := GetJSON(AJSON);
    except
      Exit;
    end;
    if not (Data is TJSONObject) then Exit;
    Root := TJSONObject(Data);
    ACwd := Root.Get('cwd', '');
    NewWindow := Root.Get('newWindow', False);
    NewTab := Root.Get('newTab', False);
    Reload := Root.Get('reload', False);
    Arr := Root.Get('files', TJSONArray(nil));
    if Arr = nil then Exit;
    for i := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then Continue;
      Obj := TJSONObject(Arr.Items[i]);
      SetLength(FFiles, Length(FFiles) + 1);
      FFiles[High(FFiles)].Path := Obj.Get('path', '');
      FFiles[High(FFiles)].Line := Obj.Get('line', 0);
      FFiles[High(FFiles)].Encoding := Obj.Get('encoding', '');
    end;
  finally
    Data.Free;
  end;
end;

function TLedCommandLine.HelpText: string;
begin
  Result :=
    'Usage: led [OPTION...] [FILE[:LINE]...]' + LineEnding + LineEnding +
    '  -n, --new-app          start a new instance instead of reusing one' + LineEnding +
    '  -w, --new-window       open the files in a new window' + LineEnding +
    '  -t, --new-tab          open the files in new tabs' + LineEnding +
    '  -l, --line=N           put the caret on line N of the files that follow' + LineEnding +
    '  -e, --encoding=NAME    read the files that follow with this encoding' + LineEnding +
    '  -r, --reload           reload the files if they are already open' + LineEnding +
    '  -s, --use-session=yes|no   restore the saved session' + LineEnding +
    '      --app-name=NAME    address a named instance' + LineEnding +
    '      --geometry=WxH+X+Y set the window geometry' + LineEnding +
    '      --script=FILE      run a script and exit' + LineEnding +
    '      --self-test        run the built-in checks and exit' + LineEnding +
    '      --bench-longline   run the long-line benchmark and exit' + LineEnding +
    '  -h, --help             show this text' + LineEnding +
    '      --version          show the version';
end;

end.
