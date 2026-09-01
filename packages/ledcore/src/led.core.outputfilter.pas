{ led - a light editor.  Output filters.

  Turns a line of compiler or tool output into a place in a file, so that
  clicking it goes there.  Ported from medit's moooutputfilterregex.cpp,
  including the part people forget: make announces when it changes directory,
  and the file names it prints afterwards are relative to that directory, not
  to where make was started.  Without the directory stack, half the errors in
  a recursive build point nowhere.

  No LCL dependency, so the whole thing is testable against captured build
  logs. }
unit Led.Core.OutputFilter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, RegExpr, LazFileUtils;

type
  TLedMatchKind = (lmkNone, lmkError, lmkWarning, lmkInfo);

  TLedOutputMatch = record
    Kind: TLedMatchKind;
    FileName: string;     // absolute where the directory stack allows
    Line: Integer;
    Column: Integer;
    Message: string;
  end;

  TLedFilterAction = (lfaNone, lfaPushDir, lfaPopDir);

  TLedFilterRule = class
  private
    FRegex: TRegExpr;
    FValid: Boolean;
  public
    Kind: TLedMatchKind;
    Action: TLedFilterAction;
    FileGroup: Integer;
    LineGroup: Integer;
    ColumnGroup: Integer;
    MessageGroup: Integer;
    DirGroup: Integer;
    constructor Create(const APattern: string);
    destructor Destroy; override;
    function Match(const ALine: string): Boolean;
    function Group(AIndex: Integer): string;
    property Valid: Boolean read FValid;
  end;

  TLedOutputFilter = class
  private
    FId: string;
    FRules: TFPList;
    FDirStack: TStringList;
    FBaseDir: string;
    function Resolve(const AFileName: string): string;
  public
    constructor Create(const AId: string);
    destructor Destroy; override;
    function AddRule(const APattern: string): TLedFilterRule;
    procedure Reset(const ABaseDir: string);
    { Feeds one line of output.  Returns the place it names, if any. }
    function Process(const ALine: string): TLedOutputMatch;
    property Id: string read FId;
    property CurrentDir: string read FBaseDir;
  end;

  TLedFilterRegistry = class
  private
    FItems: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    function Find(const AId: string): TLedOutputFilter;
    procedure LoadDefaults;
  end;

function LedFilters: TLedFilterRegistry;

implementation

{ TLedFilterRule }

constructor TLedFilterRule.Create(const APattern: string);
begin
  inherited Create;
  FileGroup := -1;
  LineGroup := -1;
  ColumnGroup := -1;
  MessageGroup := -1;
  DirGroup := -1;
  FRegex := TRegExpr.Create;
  FRegex.Expression := APattern;
  FValid := True;
  try
    FRegex.Compile;
  except
    FValid := False;
  end;
end;

destructor TLedFilterRule.Destroy;
begin
  FRegex.Free;
  inherited Destroy;
end;

function TLedFilterRule.Match(const ALine: string): Boolean;
begin
  Result := False;
  if not FValid then Exit;
  try
    Result := FRegex.Exec(ALine);
  except
    Result := False;
  end;
end;

function TLedFilterRule.Group(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex < 0) or not FValid then Exit;
  try
    Result := FRegex.Match[AIndex];
  except
    Result := '';
  end;
end;

{ TLedOutputFilter }

constructor TLedOutputFilter.Create(const AId: string);
begin
  inherited Create;
  FId := AId;
  FRules := TFPList.Create;
  FDirStack := TStringList.Create;
end;

destructor TLedOutputFilter.Destroy;
var
  i: Integer;
begin
  for i := 0 to FRules.Count - 1 do
    TLedFilterRule(FRules[i]).Free;
  FRules.Free;
  FDirStack.Free;
  inherited Destroy;
end;

function TLedOutputFilter.AddRule(const APattern: string): TLedFilterRule;
begin
  Result := TLedFilterRule.Create(APattern);
  FRules.Add(Result);
end;

procedure TLedOutputFilter.Reset(const ABaseDir: string);
begin
  FDirStack.Clear;
  FBaseDir := ABaseDir;
end;

function TLedOutputFilter.Resolve(const AFileName: string): string;
begin
  Result := AFileName;
  if Result = '' then Exit;
  if FilenameIsAbsolute(Result) then Exit;
  if FBaseDir <> '' then
    Result := ExpandFileName(IncludeTrailingPathDelimiter(FBaseDir) + Result);
end;

function TLedOutputFilter.Process(const ALine: string): TLedOutputMatch;
var
  i: Integer;
  Rule: TLedFilterRule;
  Dir: string;
begin
  Result := Default(TLedOutputMatch);
  Result.Kind := lmkNone;

  for i := 0 to FRules.Count - 1 do
  begin
    Rule := TLedFilterRule(FRules[i]);
    if not Rule.Match(ALine) then Continue;

    case Rule.Action of
      lfaPushDir:
        begin
          Dir := Rule.Group(Rule.DirGroup);
          if Dir <> '' then
          begin
            FDirStack.Add(FBaseDir);
            FBaseDir := Dir;
          end;
          Exit;
        end;
      lfaPopDir:
        begin
          if FDirStack.Count > 0 then
          begin
            FBaseDir := FDirStack[FDirStack.Count - 1];
            FDirStack.Delete(FDirStack.Count - 1);
          end;
          Exit;
        end;
    end;

    Result.Kind := Rule.Kind;
    Result.FileName := Resolve(Rule.Group(Rule.FileGroup));
    Result.Line := StrToIntDef(Rule.Group(Rule.LineGroup), 0);
    Result.Column := StrToIntDef(Rule.Group(Rule.ColumnGroup), 0);
    Result.Message := Rule.Group(Rule.MessageGroup);
    Exit;
  end;
end;

{ TLedFilterRegistry }

constructor TLedFilterRegistry.Create;
begin
  inherited Create;
  FItems := TStringList.Create;
  FItems.CaseSensitive := False;
  FItems.OwnsObjects := True;
end;

destructor TLedFilterRegistry.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TLedFilterRegistry.Find(const AId: string): TLedOutputFilter;
var
  i: Integer;
begin
  i := FItems.IndexOf(AId);
  if i < 0 then Result := nil else Result := TLedOutputFilter(FItems.Objects[i]);
end;

procedure TLedFilterRegistry.LoadDefaults;
var
  F: TLedOutputFilter;
  R: TLedFilterRule;
begin
  FItems.Clear;

  { "none" exists so a tool can say it wants no interpretation at all. }
  FItems.AddObject('none', TLedOutputFilter.Create('none'));

  { The general gcc/clang shape, which most build tools imitate:
        path/file.c:12:5: error: something
    Column is optional; the severity word decides how it is shown. }
  F := TLedOutputFilter.Create('default');
  R := F.AddRule('^([^:\n]+):(\d+):(?:(\d+):)?\s*(?:fatal\s+)?error\s*:\s*(.*)$');
  R.Kind := lmkError; R.FileGroup := 1; R.LineGroup := 2;
  R.ColumnGroup := 3; R.MessageGroup := 4;
  R := F.AddRule('^([^:\n]+):(\d+):(?:(\d+):)?\s*warning\s*:\s*(.*)$');
  R.Kind := lmkWarning; R.FileGroup := 1; R.LineGroup := 2;
  R.ColumnGroup := 3; R.MessageGroup := 4;
  { A bare file:line with no severity still names a place worth jumping to --
    grep -n and many linters print exactly this. }
  R := F.AddRule('^([^:\n]+):(\d+):\s*(.*)$');
  R.Kind := lmkInfo; R.FileGroup := 1; R.LineGroup := 2; R.MessageGroup := 3;
  FItems.AddObject('default', F);

  { make, which is "default" plus the directory bookkeeping.  The push and
    pop rules come first so they are seen before the generic patterns. }
  F := TLedOutputFilter.Create('make');
  R := F.AddRule('^g?make(?:\[\d+\])?: Entering directory [`'']?([^'']*)''?');
  R.Action := lfaPushDir; R.DirGroup := 1;
  R := F.AddRule('^g?make(?:\[\d+\])?: Leaving directory');
  R.Action := lfaPopDir;
  R := F.AddRule('^([^:\n]+):(\d+):(?:(\d+):)?\s*(?:fatal\s+)?error\s*:\s*(.*)$');
  R.Kind := lmkError; R.FileGroup := 1; R.LineGroup := 2;
  R.ColumnGroup := 3; R.MessageGroup := 4;
  R := F.AddRule('^([^:\n]+):(\d+):(?:(\d+):)?\s*warning\s*:\s*(.*)$');
  R.Kind := lmkWarning; R.FileGroup := 1; R.LineGroup := 2;
  R.ColumnGroup := 3; R.MessageGroup := 4;
  R := F.AddRule('^([^:\n]+):(\d+):\s*(.*)$');
  R.Kind := lmkInfo; R.FileGroup := 1; R.LineGroup := 2; R.MessageGroup := 3;
  FItems.AddObject('make', F);

  { Python tracebacks name the file on one line and the message later, so
    only the location is extracted here. }
  F := TLedOutputFilter.Create('python');
  R := F.AddRule('^\s*File "([^"]+)", line (\d+)');
  R.Kind := lmkError; R.FileGroup := 1; R.LineGroup := 2;
  FItems.AddObject('python', F);

  { LaTeX puts the line number on its own after the file. }
  F := TLedOutputFilter.Create('latex');
  R := F.AddRule('^([^:\n]+):(\d+):\s*(.*)$');
  R.Kind := lmkError; R.FileGroup := 1; R.LineGroup := 2; R.MessageGroup := 3;
  R := F.AddRule('^l\.(\d+)\s*(.*)$');
  R.Kind := lmkError; R.LineGroup := 1; R.MessageGroup := 2;
  FItems.AddObject('latex', F);

  { bison and friends: file:line.col-line.col: message }
  F := TLedOutputFilter.Create('bison');
  R := F.AddRule('^([^:\n]+):(\d+)\.(\d+)[^:]*:\s*(.*)$');
  R.Kind := lmkError; R.FileGroup := 1; R.LineGroup := 2;
  R.ColumnGroup := 3; R.MessageGroup := 4;
  FItems.AddObject('bison', F);
end;

var
  FRegistry: TLedFilterRegistry = nil;

function LedFilters: TLedFilterRegistry;
begin
  if FRegistry = nil then
  begin
    FRegistry := TLedFilterRegistry.Create;
    FRegistry.LoadDefaults;
  end;
  Result := FRegistry;
end;

finalization
  FRegistry.Free;

end.
