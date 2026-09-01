{ led - a light editor.  Headless tests for command-line parsing.

  Argument handling is exactly the sort of code that mis-handles one case
  forever without anyone noticing, so the grammar is pinned here. }
unit Led.Core.Tests.CLI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Led.Core.CLI, Led.Core.Instance;

type
  TTestCLI = class(TTestCase)
  private
    FCmd: TLedCommandLine;
    procedure ParseStr(const AArgs: array of string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure PlainFiles;
    procedure LineSuffix;
    procedure LineSuffixNeedsAllDigits;
    procedure ColonWithNoDigitsIsPartOfTheName;
    procedure ExplicitLineBeatsTheSuffix;
    procedure LineAppliesToFollowingFilesOnly;
    procedure EncodingApplies;
    procedure ShortAndLongForms;
    procedure ValueAsSeparateArgument;
    procedure DoubleDashEndsOptions;
    procedure UnknownOptionIsReported;
    procedure MissingValueIsReported;
    procedure JSONRoundTrip;
  end;

  TTestInstanceId = class(TTestCase)
  published
    procedure IdIsScopedToTheUser;
    procedure NamedInstanceDiffers;
    procedure OddCharactersAreSanitised;
  end;

implementation

procedure TTestCLI.SetUp;
begin
  FCmd := TLedCommandLine.Create;
end;

procedure TTestCLI.TearDown;
begin
  FCmd.Free;
end;

procedure TTestCLI.ParseStr(const AArgs: array of string);
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    for i := Low(AArgs) to High(AArgs) do
      L.Add(AArgs[i]);
    FCmd.Parse(L);
  finally
    L.Free;
  end;
end;

procedure TTestCLI.PlainFiles;
begin
  ParseStr(['a.txt', 'b.txt']);
  AssertEquals(2, FCmd.FileCount);
  AssertEquals('a.txt', FCmd.Files[0].Path);
  AssertEquals(0, FCmd.Files[0].Line);
end;

procedure TTestCLI.LineSuffix;
begin
  ParseStr(['main.c:42']);
  AssertEquals('main.c', FCmd.Files[0].Path);
  AssertEquals(42, FCmd.Files[0].Line);
end;

procedure TTestCLI.LineSuffixNeedsAllDigits;
begin
  { "notes:2024-01" is a file name, not line "2024-01". }
  ParseStr(['notes:2024-01']);
  AssertEquals('notes:2024-01', FCmd.Files[0].Path);
  AssertEquals(0, FCmd.Files[0].Line);
end;

procedure TTestCLI.ColonWithNoDigitsIsPartOfTheName;
begin
  ParseStr(['weird:name']);
  AssertEquals('weird:name', FCmd.Files[0].Path);
end;

procedure TTestCLI.ExplicitLineBeatsTheSuffix;
begin
  ParseStr(['--line', '7', 'main.c:42']);
  AssertEquals(7, FCmd.Files[0].Line);
end;

procedure TTestCLI.LineAppliesToFollowingFilesOnly;
begin
  ParseStr(['first.c', '--line=9', 'second.c']);
  AssertEquals('the file before the option is untouched', 0, FCmd.Files[0].Line);
  AssertEquals(9, FCmd.Files[1].Line);
end;

procedure TTestCLI.EncodingApplies;
begin
  ParseStr(['-e', 'cp1251', 'russian.txt']);
  AssertEquals('cp1251', FCmd.Files[0].Encoding);
end;

procedure TTestCLI.ShortAndLongForms;
begin
  ParseStr(['-n', '-w', '-t', '-r']);
  AssertTrue(FCmd.NewApp);
  AssertTrue(FCmd.NewWindow);
  AssertTrue(FCmd.NewTab);
  AssertTrue(FCmd.Reload);

  FCmd.NewApp := False;
  ParseStr(['--new-app']);
  AssertTrue(FCmd.NewApp);
end;

procedure TTestCLI.ValueAsSeparateArgument;
begin
  ParseStr(['--app-name', 'scratch']);
  AssertEquals('scratch', FCmd.AppName);
  ParseStr(['--app-name=scratch2']);
  AssertEquals('scratch2', FCmd.AppName);
end;

procedure TTestCLI.DoubleDashEndsOptions;
begin
  { The only way to open a file whose name begins with a dash. }
  ParseStr(['--', '-weird-name.txt', '--also-a-file']);
  AssertEquals(2, FCmd.FileCount);
  AssertEquals('-weird-name.txt', FCmd.Files[0].Path);
  AssertEquals(0, FCmd.Errors.Count);
end;

procedure TTestCLI.UnknownOptionIsReported;
begin
  { Reported, not silently ignored: a typo should not look like a file that
    failed to open. }
  ParseStr(['--not-an-option']);
  AssertEquals(1, FCmd.Errors.Count);
  AssertEquals(0, FCmd.FileCount);
end;

procedure TTestCLI.MissingValueIsReported;
begin
  ParseStr(['--line']);
  AssertEquals(1, FCmd.Errors.Count);
end;

procedure TTestCLI.JSONRoundTrip;
var
  JSON, Cwd: string;
  Other: TLedCommandLine;
begin
  ParseStr(['-w', '--line=5', 'x.c', 'y.c:9']);
  JSON := FCmd.ToJSON('/home/me/src');

  Other := TLedCommandLine.Create;
  try
    Other.FromJSON(JSON, Cwd);
    AssertEquals('/home/me/src', Cwd);
    AssertTrue(Other.NewWindow);
    AssertEquals(2, Other.FileCount);
    AssertEquals('x.c', Other.Files[0].Path);
    AssertEquals(5, Other.Files[0].Line);
    AssertEquals(5, Other.Files[1].Line);
  finally
    Other.Free;
  end;
end;

{ TTestInstanceId }

procedure TTestInstanceId.IdIsScopedToTheUser;
begin
  AssertTrue(Pos('led_', LedInstanceId('')) = 1);
end;

procedure TTestInstanceId.NamedInstanceDiffers;
begin
  AssertTrue(LedInstanceId('') <> LedInstanceId('scratch'));
end;

procedure TTestInstanceId.OddCharactersAreSanitised;
var
  Id: string;
  i: Integer;
begin
  { advancedipc rejects anything but letters, digits and underscores -- not
    even a hyphen -- so the whole id has to stay inside that set. }
  Id := LedInstanceId('a/b c:d-e');
  for i := 1 to Length(Id) do
    AssertTrue('safe character: ' + Id[i],
      Id[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

initialization
  RegisterTest(TTestCLI);
  RegisterTest(TTestInstanceId);

end.
