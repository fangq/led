{ led - a light editor.  Project discovery, launch.json and tasks.json. }
unit Led.Core.Tests.Project;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, fpcunit, testregistry, Led.Core.Project;

type
  TTestProject = class(TTestCase)
  private
    FDir: string;                 // a throwaway tree, removed in TearDown
    procedure Put(const ARelPath, AContent: string);
    function Sub(const ARelPath: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure NoProjectIsNotAnError;
    procedure FindsLaunchInDotLed;
    procedure FindsLaunchInDotVscode;
    procedure DotLedWinsOverDotVscode;
    procedure WalksUpFromANestedFile;
    procedure WalksUpFromADirectory;
    procedure ReadsNameAndProgram;
    procedure AcceptsTargetAsWellAsProgram;
    procedure ReadsArgs;
    procedure ReadsEnvironmentArray;
    procedure ReadsEnvironmentObject;
    procedure SkipsForeignDebuggers;
    procedure KeepsUntypedConfigs;
    procedure ToleratesCommentsAndTrailingCommas;
    procedure BrokenJsonLeavesARootAndNoConfigs;
    procedure ResolvesWorkspaceFolder;
    procedure ResolvesFileVariables;
    procedure ResolvesEnvVariables;
    procedure LeavesUnknownVariablesAlone;
    procedure LeavesUnterminatedVariableAlone;
    procedure BuildCommandFromTasks;
    procedure BuildCommandJoinsArgsQuoted;
    procedure BuildCommandPrefersExplicitBuild;
    procedure MissingTasksFileIsFine;
    procedure ShellQuoting;
  end;

implementation

procedure TTestProject.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) +
          Format('led-projtest-%d', [GetProcessID]);
  ForceDirectories(FDir + PathDelim + 'src' + PathDelim + 'deep');
end;

procedure TTestProject.TearDown;
begin
  if (FDir <> '') and DirectoryExists(FDir) then
    DeleteDirectory(FDir, False);
end;

function TTestProject.Sub(const ARelPath: string): string;
begin
  Result := IncludeTrailingPathDelimiter(FDir) +
            StringReplace(ARelPath, '/', PathDelim, [rfReplaceAll]);
end;

procedure TTestProject.Put(const ARelPath, AContent: string);
var
  L: TStringList;
  Full: string;
begin
  Full := Sub(ARelPath);
  ForceDirectories(ExtractFileDir(Full));
  L := TStringList.Create;
  try
    L.Text := AContent;
    L.SaveToFile(Full);
  finally
    L.Free;
  end;
end;

{ --- discovery ------------------------------------------------------------- }

procedure TTestProject.NoProjectIsNotAnError;
var P: TLedProject;
begin
  P := TLedProject.Create;
  try
    AssertFalse('a tree with no configuration is simply not a project',
      P.LoadFrom(Sub('src/deep')));
    AssertEquals('and has no root', '', P.Root);
    AssertEquals('and no configurations', 0, P.ConfigCount);
  finally P.Free; end;
end;

procedure TTestProject.FindsLaunchInDotLed;
var P: TLedProject;
begin
  Put('.led/launch.json', '{"configurations":[{"name":"Debug"}]}');
  P := TLedProject.Create;
  try
    AssertTrue('found', P.LoadFrom(Sub('src/deep')));
    AssertEquals('the root is the folder holding .led',
      ExcludeTrailingPathDelimiter(FDir),
      ExcludeTrailingPathDelimiter(P.Root));
    AssertEquals('one configuration', 1, P.ConfigCount);
  finally P.Free; end;
end;

procedure TTestProject.FindsLaunchInDotVscode;
var P: TLedProject;
begin
  Put('.vscode/launch.json', '{"configurations":[{"name":"FromVSCode"}]}');
  P := TLedProject.Create;
  try
    AssertTrue('a project''s existing VS Code folder counts',
      P.LoadFrom(Sub('src/deep')));
    AssertEquals('FromVSCode', 'FromVSCode', P[0].Name);
  finally P.Free; end;
end;

procedure TTestProject.DotLedWinsOverDotVscode;
var P: TLedProject;
begin
  { So a led-tuned configuration can shadow the project's own without
    editing a file that belongs to everybody. }
  Put('.vscode/launch.json', '{"configurations":[{"name":"FromVSCode"}]}');
  Put('.led/launch.json',    '{"configurations":[{"name":"FromLed"}]}');
  P := TLedProject.Create;
  try
    AssertTrue('found', P.LoadFrom(Sub('src/deep')));
    AssertEquals('.led shadows .vscode', 'FromLed', P[0].Name);
  finally P.Free; end;
end;

procedure TTestProject.WalksUpFromANestedFile;
var P: TLedProject;
begin
  Put('.led/launch.json', '{"configurations":[{"name":"Debug"}]}');
  Put('src/deep/main.c', 'int main(void){return 0;}');
  P := TLedProject.Create;
  try
    AssertTrue('a file three levels down still finds it',
      P.LoadFrom(Sub('src/deep/main.c')));
  finally P.Free; end;
end;

procedure TTestProject.WalksUpFromADirectory;
var P: TLedProject;
begin
  Put('.led/launch.json', '{"configurations":[{"name":"Debug"}]}');
  P := TLedProject.Create;
  try
    AssertTrue('a directory works as a starting point too',
      P.LoadFrom(Sub('src')));
  finally P.Free; end;
end;

{ --- launch.json ----------------------------------------------------------- }

procedure TTestProject.ReadsNameAndProgram;
var P: TLedProject;
begin
  Put('.led/launch.json',
    '{"configurations":[{"name":"Debug","program":"./a.out","cwd":"/tmp"}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('Debug', 'Debug', P[0].Name);
    AssertEquals('./a.out', './a.out', P[0].Program_);
    AssertEquals('/tmp', '/tmp', P[0].Cwd);
  finally P.Free; end;
end;

procedure TTestProject.AcceptsTargetAsWellAsProgram;
var P: TLedProject;
begin
  Put('.led/launch.json', '{"configurations":[{"name":"D","target":"./x"}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('"target" is led''s own spelling', './x', P[0].Program_);
  finally P.Free; end;
end;

procedure TTestProject.ReadsArgs;
var P: TLedProject;
begin
  Put('.led/launch.json',
    '{"configurations":[{"name":"D","args":["-v","in put.txt"]}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('two arguments', 2, P[0].Args.Count);
    AssertEquals('-v', '-v', P[0].Args[0]);
    AssertEquals('a space does not split one', 'in put.txt', P[0].Args[1]);
  finally P.Free; end;
end;

procedure TTestProject.ReadsEnvironmentArray;
var P: TLedProject;
begin
  Put('.led/launch.json',
    '{"configurations":[{"name":"D","environment":' +
    '[{"name":"LANG","value":"C"},{"name":"N","value":"1"}]}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('two variables', 2, P[0].Environment.Count);
    AssertEquals('C', 'C', P[0].Environment.Values['LANG']);
    AssertEquals('1', '1', P[0].Environment.Values['N']);
  finally P.Free; end;
end;

procedure TTestProject.ReadsEnvironmentObject;
var P: TLedProject;
begin
  { medit's header documents this shape and its code ignores it, so a file
    that reads correctly to a person does nothing.  Accepted here. }
  Put('.led/launch.json',
    '{"configurations":[{"name":"D","environment":{"LANG":"C","N":"1"}}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('the object form is read too', 2, P[0].Environment.Count);
    AssertEquals('C', 'C', P[0].Environment.Values['LANG']);
  finally P.Free; end;
end;

procedure TTestProject.SkipsForeignDebuggers;
var P: TLedProject;
begin
  Put('.led/launch.json',
    '{"configurations":[{"name":"Web","type":"pwa-chrome"},' +
    '{"name":"Py","type":"python"},{"name":"C","type":"cppdbg"}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('only the gdb-compatible one is offered', 1, P.ConfigCount);
    AssertEquals('C', 'C', P[0].Name);
  finally P.Free; end;
end;

procedure TTestProject.KeepsUntypedConfigs;
var P: TLedProject;
begin
  { No "type" means a hand-written file, which is for us. }
  Put('.led/launch.json', '{"configurations":[{"name":"Mine"}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('kept', 1, P.ConfigCount);
  finally P.Free; end;
end;

procedure TTestProject.ToleratesCommentsAndTrailingCommas;
var P: TLedProject;
begin
  { What a real .vscode/launch.json looks like.  GetJSON refuses both. }
  Put('.led/launch.json',
    '{' + LineEnding +
    '  // the debug build' + LineEnding +
    '  "configurations": [' + LineEnding +
    '    {' + LineEnding +
    '      "name": "Debug",   /* block comment */' + LineEnding +
    '      "program": "./a.out",' + LineEnding +
    '    },' + LineEnding +
    '  ],' + LineEnding +
    '}');
  P := TLedProject.Create;
  try
    AssertTrue('loaded', P.LoadFrom(FDir));
    AssertEquals('one configuration', 1, P.ConfigCount);
    AssertEquals('Debug', 'Debug', P[0].Name);
    AssertEquals('./a.out', './a.out', P[0].Program_);
  finally P.Free; end;
end;

procedure TTestProject.BrokenJsonLeavesARootAndNoConfigs;
var P: TLedProject;
begin
  { The UI needs to be able to say "this project's launch.json is broken",
    which it cannot do if a bad file looks like no project at all. }
  Put('.led/launch.json', '{"configurations": [ this is not json');
  P := TLedProject.Create;
  try
    AssertTrue('still a project', P.LoadFrom(FDir));
    AssertEquals('with nothing in it', 0, P.ConfigCount);
    AssertTrue('and a launch path to open', P.LaunchPath <> '');
  finally P.Free; end;
end;

{ --- variables ------------------------------------------------------------- }

procedure TTestProject.ResolvesWorkspaceFolder;
var P: TLedProject;
begin
  Put('.led/launch.json', '{"configurations":[{"name":"D"}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('the root',
      ExcludeTrailingPathDelimiter(FDir) + '/build/app',
      P.Resolve('${workspaceFolder}/build/app', ''));
  finally P.Free; end;
end;

procedure TTestProject.ResolvesFileVariables;
var P: TLedProject; F: string;
begin
  Put('.led/launch.json', '{"configurations":[{"name":"D"}]}');
  F := Sub('src/deep/main.c');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('${file}', F, P.Resolve('${file}', F));
    AssertEquals('${fileBasename}', 'main.c', P.Resolve('${fileBasename}', F));
    AssertEquals('${fileBasenameNoExtension}', 'main',
      P.Resolve('${fileBasenameNoExtension}', F));
    AssertEquals('${fileDirname}', ExcludeTrailingPathDelimiter(
      ExtractFileDir(F)), P.Resolve('${fileDirname}', F));
  finally P.Free; end;
end;

procedure TTestProject.ResolvesEnvVariables;
var P: TLedProject;
begin
  Put('.led/launch.json', '{"configurations":[{"name":"D"}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('an environment variable', GetEnvironmentVariable('HOME'),
      P.Resolve('${env:HOME}', ''));
    AssertEquals('an unset one is empty', '',
      P.Resolve('${env:LED_DEFINITELY_NOT_SET_XYZ}', ''));
  finally P.Free; end;
end;

procedure TTestProject.LeavesUnknownVariablesAlone;
var P: TLedProject;
begin
  Put('.led/launch.json', '{"configurations":[{"name":"D"}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    { Swallowing it would turn a typo into an empty string and an error
      message that names neither. }
    AssertEquals('kept verbatim', 'a/${noSuchThing}/b',
      P.Resolve('a/${noSuchThing}/b', ''));
  finally P.Free; end;
end;

procedure TTestProject.LeavesUnterminatedVariableAlone;
var P: TLedProject;
begin
  Put('.led/launch.json', '{"configurations":[{"name":"D"}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('an unclosed brace is emitted as written', 'a/${oops',
      P.Resolve('a/${oops', ''));
  finally P.Free; end;
end;

{ --- tasks ----------------------------------------------------------------- }

procedure TTestProject.BuildCommandFromTasks;
var P: TLedProject;
begin
  Put('.led/launch.json',
    '{"configurations":[{"name":"D","preLaunchTask":"build"}]}');
  Put('.led/tasks.json',
    '{"tasks":[{"label":"build","command":"make -j8"}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('the label resolves to its command', 'make -j8',
      P.BuildCommandFor(P[0]));
  finally P.Free; end;
end;

procedure TTestProject.BuildCommandJoinsArgsQuoted;
var P: TLedProject;
begin
  Put('.led/launch.json',
    '{"configurations":[{"name":"D","preLaunchTask":"b"}]}');
  Put('.led/tasks.json',
    '{"tasks":[{"label":"b","command":"gcc","args":["-g","my file.c",' +
    '"-o","out"]}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('a space in an argument survives the join',
      'gcc -g ''my file.c'' -o out', P.BuildCommandFor(P[0]));
  finally P.Free; end;
end;

procedure TTestProject.BuildCommandPrefersExplicitBuild;
var P: TLedProject;
begin
  Put('.led/launch.json',
    '{"configurations":[{"name":"D","build":"ninja","preLaunchTask":"b"}]}');
  Put('.led/tasks.json', '{"tasks":[{"label":"b","command":"make"}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('"build" wins over the task label', 'ninja',
      P.BuildCommandFor(P[0]));
  finally P.Free; end;
end;

procedure TTestProject.MissingTasksFileIsFine;
var P: TLedProject;
begin
  Put('.led/launch.json',
    '{"configurations":[{"name":"D","preLaunchTask":"nope"}]}');
  P := TLedProject.Create;
  try
    P.LoadFrom(FDir);
    AssertEquals('an unresolvable label is simply no build command', '',
      P.BuildCommandFor(P[0]));
  finally P.Free; end;
end;

procedure TTestProject.ShellQuoting;
begin
  AssertEquals('a plain word is left alone', 'make', LedShellQuote('make'));
  AssertEquals('a path too', '/usr/bin/gcc', LedShellQuote('/usr/bin/gcc'));
  AssertEquals('a space is quoted', '''my file.c''',
    LedShellQuote('my file.c'));
  AssertEquals('a quote is escaped', '''it''\''''s''', LedShellQuote('it''s'));
  AssertEquals('a semicolon cannot leak into the shell', '''a;rm -rf /''',
    LedShellQuote('a;rm -rf /'));
end;

initialization
  RegisterTest(TTestProject);

end.
