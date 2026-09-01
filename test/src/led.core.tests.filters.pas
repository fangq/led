{ led - a light editor.  Headless tests for filename-based config rules. }
unit Led.Core.Tests.Filters;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.Types, Led.Core.Config, Led.Core.Filters;

type
  TTestFilterMatching = class(TTestCase)
  published
    procedure BareTextIsGlobs;
    procedure ExplicitGlobs;
    procedure SeveralGlobs;
    procedure CommaSeparatorAlsoWorks;
    procedure LangsMatchById;
    procedure LangsDoNotMatchAFileName;
    procedure RegexMatchesTheWholePath;
    procedure BrokenRegexIsInertNotFatal;
    procedure GlobsIgnoreTheDirectory;
  end;

  TTestFilterRules = class(TTestCase)
  private
    FCfg: TLedDocConfig;
    FSet: TLedFilterSettings;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure MatchingRuleIsApplied;
    procedure NonMatchingRuleIsNot;
    procedure SeveralRulesAccumulate;
    procedure AppliedAboveAModeline;
    procedure BelowTheLanguageLayer;
    procedure ClearedLayerIsRebuilt;
    procedure DefaultsGiveMakefilesTabs;
    procedure DefaultsSelectPythonByLanguage;
  end;

implementation

{ TTestFilterMatching }

procedure TTestFilterMatching.BareTextIsGlobs;
var
  F: TLedEditFilter;
begin
  { medit read a bare filter as a regex, which quietly mis-parsed "*.c".
    led reads it as globs, which is what people write. }
  F := TLedEditFilter.Create('*.c');
  try
    AssertTrue(F.Kind = lfkGlobs);
    AssertTrue(F.Matches('/tmp/hello.c', ''));
    AssertFalse(F.Matches('/tmp/hello.h', ''));
  finally
    F.Free;
  end;
end;

procedure TTestFilterMatching.ExplicitGlobs;
var
  F: TLedEditFilter;
begin
  F := TLedEditFilter.Create('globs:Makefile*');
  try
    AssertTrue(F.Matches('/src/Makefile', ''));
    AssertTrue(F.Matches('/src/Makefile.am', ''));
    AssertFalse(F.Matches('/src/main.c', ''));
  finally
    F.Free;
  end;
end;

procedure TTestFilterMatching.SeveralGlobs;
var
  F: TLedEditFilter;
begin
  F := TLedEditFilter.Create('globs:*.diff;*.patch');
  try
    AssertTrue(F.Matches('a.diff', ''));
    AssertTrue(F.Matches('a.patch', ''));
    AssertFalse(F.Matches('a.txt', ''));
  finally
    F.Free;
  end;
end;

procedure TTestFilterMatching.CommaSeparatorAlsoWorks;
var
  F: TLedEditFilter;
begin
  { medit used ';' for globs and ',' for languages; people mix them. }
  F := TLedEditFilter.Create('globs:*.diff,*.patch');
  try
    AssertTrue(F.Matches('a.patch', ''));
  finally
    F.Free;
  end;
end;

procedure TTestFilterMatching.LangsMatchById;
var
  F: TLedEditFilter;
begin
  F := TLedEditFilter.Create('langs:c,cpp');
  try
    AssertTrue(F.Kind = lfkLangs);
    AssertTrue(F.Matches('anything', 'cpp'));
    AssertFalse(F.Matches('anything', 'python'));
  finally
    F.Free;
  end;
end;

procedure TTestFilterMatching.LangsDoNotMatchAFileName;
var
  F: TLedEditFilter;
begin
  F := TLedEditFilter.Create('langs:c');
  try
    AssertFalse('a .c file with no detected language does not match',
      F.Matches('hello.c', ''));
  finally
    F.Free;
  end;
end;

procedure TTestFilterMatching.RegexMatchesTheWholePath;
var
  F: TLedEditFilter;
begin
  { Globs see only the base name; a regex is how you select on location. }
  F := TLedEditFilter.Create('regex:^/etc/');
  try
    AssertTrue(F.Kind = lfkRegex);
    AssertTrue(F.Matches('/etc/fstab', ''));
    AssertFalse(F.Matches('/home/me/fstab', ''));
  finally
    F.Free;
  end;
end;

procedure TTestFilterMatching.BrokenRegexIsInertNotFatal;
var
  F: TLedEditFilter;
begin
  F := TLedEditFilter.Create('regex:([unclosed');
  try
    AssertFalse('a broken rule is invalid', F.Valid);
    AssertFalse('and simply never matches', F.Matches('/anything', ''));
  finally
    F.Free;
  end;
end;

procedure TTestFilterMatching.GlobsIgnoreTheDirectory;
var
  F: TLedEditFilter;
begin
  F := TLedEditFilter.Create('globs:*.c');
  try
    AssertTrue(F.Matches('/very/deep/path/x.c', ''));
  finally
    F.Free;
  end;
end;

{ TTestFilterRules }

procedure TTestFilterRules.SetUp;
begin
  FCfg := TLedDocConfig.Create;
  FSet := TLedFilterSettings.Create;
end;

procedure TTestFilterRules.TearDown;
begin
  FSet.Free;
  FCfg.Free;
end;

procedure TTestFilterRules.MatchingRuleIsApplied;
begin
  FSet.Add('globs:Makefile*', 'indent-use-tabs: true; tab-width: 8');
  AssertEquals(1, FSet.ApplyTo(FCfg, '/src/Makefile', ''));
  AssertTrue(FCfg.GetBool(LedSetIndentUseTabs));
  AssertEquals(8, FCfg.GetInt(LedSetTabWidth));
end;

procedure TTestFilterRules.NonMatchingRuleIsNot;
begin
  FSet.Add('globs:Makefile*', 'tab-width: 8');
  AssertEquals(0, FSet.ApplyTo(FCfg, '/src/main.c', ''));
  AssertFalse(FCfg.HasValue(LedSetTabWidth));
end;

procedure TTestFilterRules.SeveralRulesAccumulate;
begin
  FSet.Add('globs:*.c', 'tab-width: 4');
  FSet.Add('langs:c', 'indent-width: 2');
  AssertEquals(2, FSet.ApplyTo(FCfg, 'main.c', 'c'));
  AssertEquals(4, FCfg.GetInt(LedSetTabWidth));
  AssertEquals(2, FCfg.GetInt(LedSetIndentWidth));
end;

procedure TTestFilterRules.AppliedAboveAModeline;
begin
  { The whole point of the feature: a Makefile needs real tabs whatever the
    file itself claims. }
  FCfg.SetBool(LedSetIndentUseTabs, False, lcsFile);
  FSet.Add('globs:Makefile*', 'indent-use-tabs: true');
  FSet.ApplyTo(FCfg, 'Makefile', '');
  AssertTrue(FCfg.GetBool(LedSetIndentUseTabs));
end;

procedure TTestFilterRules.BelowTheLanguageLayer;
begin
  FCfg.SetInt(LedSetTabWidth, 2, lcsLang);
  FSet.Add('globs:*.c', 'tab-width: 8');
  FSet.ApplyTo(FCfg, 'main.c', 'c');
  AssertEquals('the language default still wins', 2, FCfg.GetInt(LedSetTabWidth));
end;

procedure TTestFilterRules.ClearedLayerIsRebuilt;
begin
  { Save As has to re-evaluate the rules for the new name without leaving the
    old name's rule behind. }
  FSet.Add('globs:Makefile*', 'indent-use-tabs: true');
  FSet.ApplyTo(FCfg, 'Makefile', '');
  AssertTrue(FCfg.GetBool(LedSetIndentUseTabs));

  FCfg.UnsetBySource(lcsFilename);
  FSet.ApplyTo(FCfg, 'notes.txt', '');
  AssertFalse('the Makefile rule is gone', FCfg.HasValue(LedSetIndentUseTabs));
end;

procedure TTestFilterRules.DefaultsGiveMakefilesTabs;
begin
  FSet.LoadDefaults;
  FSet.ApplyTo(FCfg, '/src/Makefile', '');
  AssertTrue('tabs', FCfg.GetBool(LedSetIndentUseTabs));
  AssertEquals(8, FCfg.GetInt(LedSetTabWidth));
end;

procedure TTestFilterRules.DefaultsSelectPythonByLanguage;
begin
  FSet.LoadDefaults;
  FSet.ApplyTo(FCfg, 'script.py', 'python');
  AssertFalse('python uses spaces', FCfg.GetBool(LedSetIndentUseTabs));
  AssertEquals(4, FCfg.GetInt(LedSetIndentWidth));
end;

initialization
  RegisterTest(TTestFilterMatching);
  RegisterTest(TTestFilterRules);

end.
