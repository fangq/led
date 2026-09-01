{ led - a light editor.  User-defined tools.

  medit kept these in menu.xml and context.xml; led keeps one file per tool,
  because a tool is mostly a shell script and a script wants to be a file you
  can read, not a CDATA block inside XML.

      # ~/.config/led/tools/sort-lines.ini
      [tool]
      name=Sort Lines
      place=menu
      options=need-doc
      type=exe
      input=lines
      output=insert
      filter=default
      [code]
      sort

  Everything before [code] is INI; everything after it is the command body,
  verbatim.  The vocabulary -- the option names, the input and output modes,
  the environment variables -- is medit's, so tools port by copying the body.

  No LCL dependency. }
unit Led.Core.Tools;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, Masks;

type
  { What has to be true before the tool can run.  Anything missing greys the
    menu entry out rather than failing once it is too late. }
  TLedToolOption = (ltoNeedDoc, ltoNeedFile, ltoNeedSave, ltoNeedSaveAll);
  TLedToolOptions = set of TLedToolOption;

  TLedToolKind = (ltkExe, ltkScript, ltkPython);

  TLedToolInput = (ltiNone, ltiLines, ltiSelection, ltiDoc, ltiDocCopy);

  TLedToolOutput = (ltoNoOutput, ltoAsync, ltoPane, ltoInsert, ltoNewDoc);

  TLedToolPlace = (ltpMenu, ltpContext);

  TLedTool = class
  public
    Id: string;
    Name: string;
    Place: TLedToolPlace;
    Options: TLedToolOptions;
    Kind: TLedToolKind;
    Input: TLedToolInput;
    Output: TLedToolOutput;
    Filter: string;
    Langs: string;        // comma-separated language ids; empty means any
    FileFilter: string;   // semicolon-separated globs; empty means any
    Accel: string;
    Code: string;
    Enabled: Boolean;
    FileName: string;

    constructor Create;
    function LoadFromFile(const APath: string): Boolean;
    procedure SaveToFile(const APath: string);
    { True when this tool should appear for a document with the given
      language and name. }
    function AppliesTo(const ALangId, AFileName: string): Boolean;
  end;

  TLedTools = class
  private
    FItems: TFPList;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TLedTool;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Add: TLedTool;
    { Reads every *.ini in ADirectory.  Returns how many were understood. }
    function LoadDirectory(const ADirectory: string): Integer;
    function FindById(const AId: string): TLedTool;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TLedTool read GetItem; default;
  end;

function LedToolOptionsFromString(const S: string): TLedToolOptions;
function LedToolOptionsToString(AOptions: TLedToolOptions): string;
function LedToolKindFromString(const S: string): TLedToolKind;
function LedToolKindToString(AKind: TLedToolKind): string;
function LedToolInputFromString(const S: string): TLedToolInput;
function LedToolInputToString(AInput: TLedToolInput): string;
function LedToolOutputFromString(const S: string): TLedToolOutput;
function LedToolOutputToString(AOutput: TLedToolOutput): string;

implementation

const
  OptionNames: array[TLedToolOption] of string =
    ('need-doc', 'need-file', 'need-save', 'need-save-all');
  KindNames: array[TLedToolKind] of string = ('exe', 'script', 'python');
  InputNames: array[TLedToolInput] of string =
    ('none', 'lines', 'selection', 'doc', 'doc-copy');
  OutputNames: array[TLedToolOutput] of string =
    ('none', 'async', 'pane', 'insert', 'new-doc');

function LedToolOptionsFromString(const S: string): TLedToolOptions;
var
  Parts: TStringArray;
  i: Integer;
  O: TLedToolOption;
  Name: string;
begin
  Result := [];
  Parts := LowerCase(S).Split([',', ';', ' ']);
  for i := 0 to High(Parts) do
  begin
    Name := Trim(Parts[i]);
    if Name = '' then Continue;
    { medit accepted both "save" and "need-save"; take either. }
    if Name = 'save' then Name := 'need-save';
    if Name = 'save-all' then Name := 'need-save-all';
    for O := Low(TLedToolOption) to High(TLedToolOption) do
      if OptionNames[O] = Name then
        Include(Result, O);
  end;
end;

function LedToolOptionsToString(AOptions: TLedToolOptions): string;
var
  O: TLedToolOption;
begin
  Result := '';
  for O := Low(TLedToolOption) to High(TLedToolOption) do
    if O in AOptions then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + OptionNames[O];
    end;
end;

function LedToolKindFromString(const S: string): TLedToolKind;
var
  K: TLedToolKind;
  N: string;
begin
  N := LowerCase(Trim(S));
  { medit called the in-process script type "lua"; led's is PascalScript, but
    a tool file written for medit should still land somewhere sensible. }
  if (N = 'lua') or (N = 'pascal') then N := 'script';
  for K := Low(TLedToolKind) to High(TLedToolKind) do
    if KindNames[K] = N then Exit(K);
  Result := ltkExe;
end;

function LedToolKindToString(AKind: TLedToolKind): string;
begin
  Result := KindNames[AKind];
end;

function LedToolInputFromString(const S: string): TLedToolInput;
var
  I: TLedToolInput;
  N: string;
begin
  N := LowerCase(Trim(S));
  for I := Low(TLedToolInput) to High(TLedToolInput) do
    if InputNames[I] = N then Exit(I);
  Result := ltiNone;
end;

function LedToolInputToString(AInput: TLedToolInput): string;
begin
  Result := InputNames[AInput];
end;

function LedToolOutputFromString(const S: string): TLedToolOutput;
var
  O: TLedToolOutput;
  N: string;
begin
  N := LowerCase(Trim(S));
  { medit had a Windows-only "console" mode; a pane is the portable answer. }
  if N = 'console' then N := 'pane';
  for O := Low(TLedToolOutput) to High(TLedToolOutput) do
    if OutputNames[O] = N then Exit(O);
  Result := ltoNoOutput;
end;

function LedToolOutputToString(AOutput: TLedToolOutput): string;
begin
  Result := OutputNames[AOutput];
end;

{ TLedTool }

constructor TLedTool.Create;
begin
  inherited Create;
  Enabled := True;
  Kind := ltkExe;
  Input := ltiNone;
  Output := ltoPane;
  Place := ltpMenu;
  Filter := 'default';
end;

function TLedTool.LoadFromFile(const APath: string): Boolean;
var
  All, Header, Body: TStringList;
  i, CodeAt: Integer;
  Ini: TMemIniFile;
begin
  Result := False;
  All := TStringList.Create;
  Header := TStringList.Create;
  Body := TStringList.Create;
  Ini := TMemIniFile.Create('');
  try
    try
      All.LoadFromFile(APath);
    except
      Exit;
    end;

    { Split at the [code] marker.  Done by hand rather than with TIniFile
      because the body is arbitrary text -- semicolons, brackets and all --
      and must survive untouched. }
    CodeAt := -1;
    for i := 0 to All.Count - 1 do
      if SameText(Trim(All[i]), '[code]') then
      begin
        CodeAt := i;
        Break;
      end;

    if CodeAt < 0 then
      Header.Assign(All)
    else
    begin
      for i := 0 to CodeAt - 1 do Header.Add(All[i]);
      for i := CodeAt + 1 to All.Count - 1 do Body.Add(All[i]);
    end;

    Ini.SetStrings(Header);
    Name := Ini.ReadString('tool', 'name', '');
    if Name = '' then Exit;

    Id := Ini.ReadString('tool', 'id', ChangeFileExt(ExtractFileName(APath), ''));
    if SameText(Ini.ReadString('tool', 'place', 'menu'), 'context') then
      Place := ltpContext
    else
      Place := ltpMenu;
    Options := LedToolOptionsFromString(Ini.ReadString('tool', 'options', ''));
    Kind := LedToolKindFromString(Ini.ReadString('tool', 'type', 'exe'));
    Input := LedToolInputFromString(Ini.ReadString('tool', 'input', 'none'));
    Output := LedToolOutputFromString(Ini.ReadString('tool', 'output', 'pane'));
    Filter := Ini.ReadString('tool', 'filter', 'default');
    Langs := Ini.ReadString('tool', 'langs', '');
    FileFilter := Ini.ReadString('tool', 'files', '');
    Accel := Ini.ReadString('tool', 'accel', '');
    Enabled := Ini.ReadBool('tool', 'enabled', True);
    Code := Body.Text;
    FileName := APath;
    Result := True;
  finally
    Ini.Free;
    Body.Free;
    Header.Free;
    All.Free;
  end;
end;

procedure TLedTool.SaveToFile(const APath: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add('[tool]');
    L.Add('id=' + Id);
    L.Add('name=' + Name);
    if Place = ltpContext then L.Add('place=context') else L.Add('place=menu');
    L.Add('options=' + LedToolOptionsToString(Options));
    L.Add('type=' + LedToolKindToString(Kind));
    L.Add('input=' + LedToolInputToString(Input));
    L.Add('output=' + LedToolOutputToString(Output));
    L.Add('filter=' + Filter);
    L.Add('langs=' + Langs);
    L.Add('files=' + FileFilter);
    L.Add('accel=' + Accel);
    if Enabled then L.Add('enabled=1') else L.Add('enabled=0');
    L.Add('[code]');
    L.Add(TrimRight(Code));
    L.SaveToFile(APath);
    FileName := APath;
  finally
    L.Free;
  end;
end;

function TLedTool.AppliesTo(const ALangId, AFileName: string): Boolean;
var
  Parts: TStringArray;
  i: Integer;
  Matched: Boolean;
begin
  Result := False;
  if not Enabled then Exit;

  if Langs <> '' then
  begin
    Matched := False;
    Parts := Langs.Split([',', ';']);
    for i := 0 to High(Parts) do
      if SameText(Trim(Parts[i]), ALangId) then Matched := True;
    if not Matched then Exit;
  end;

  if FileFilter <> '' then
  begin
    Matched := False;
    Parts := FileFilter.Split([';', ',']);
    for i := 0 to High(Parts) do
      if (Trim(Parts[i]) <> '') and
         MatchesMask(ExtractFileName(AFileName), Trim(Parts[i])) then
        Matched := True;
    if not Matched then Exit;
  end;

  Result := True;
end;

{ TLedTools }

constructor TLedTools.Create;
begin
  inherited Create;
  FItems := TFPList.Create;
end;

destructor TLedTools.Destroy;
begin
  Clear;
  FItems.Free;
  inherited Destroy;
end;

procedure TLedTools.Clear;
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    TLedTool(FItems[i]).Free;
  FItems.Clear;
end;

function TLedTools.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TLedTools.GetItem(AIndex: Integer): TLedTool;
begin
  Result := TLedTool(FItems[AIndex]);
end;

function TLedTools.Add: TLedTool;
begin
  Result := TLedTool.Create;
  FItems.Add(Result);
end;

function TLedTools.FindById(const AId: string): TLedTool;
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    if SameText(Items[i].Id, AId) then Exit(Items[i]);
  Result := nil;
end;

function TLedTools.LoadDirectory(const ADirectory: string): Integer;
var
  Search: TSearchRec;
  Dir: string;
  Tool: TLedTool;
  Names: TStringList;
  i: Integer;
begin
  Result := 0;
  Dir := IncludeTrailingPathDelimiter(ADirectory);
  if not DirectoryExists(Dir) then Exit;

  { Sorted, so the menu order does not depend on the order the filesystem
    happens to hand back. }
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    if FindFirst(Dir + '*.ini', faAnyFile, Search) = 0 then
    begin
      repeat
        if (Search.Attr and faDirectory) = 0 then
          Names.Add(Search.Name);
      until FindNext(Search) <> 0;
      FindClose(Search);
    end;

    for i := 0 to Names.Count - 1 do
    begin
      Tool := TLedTool.Create;
      if Tool.LoadFromFile(Dir + Names[i]) and (FindById(Tool.Id) = nil) then
      begin
        FItems.Add(Tool);
        Inc(Result);
      end
      else
        Tool.Free;
    end;
  finally
    Names.Free;
  end;
end;

end.
