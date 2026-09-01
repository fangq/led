{ led - a light editor.  Headless tests for the layered config and modelines. }
unit Led.Core.Tests.Config;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.Types, Led.Core.Config, Led.Core.Modeline;

type
  TTestPrecedence = class(TTestCase)
  private
    FCfg: TLedDocConfig;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure DefaultsApplyWhenNothingIsSet;
    procedure MoreSpecificSourceWins;
    procedure LessSpecificSourceIsIgnored;
    procedure SameSourceOverwrites;
    procedure UnsetBySourceClearsOnlyThatLayer;
    procedure UnsetRevealsTheLayerBelowNothing;
    procedure ParentSuppliesUnsetValues;
    procedure ChildOverridesParent;
    procedure ChangeNotificationFires;
  private
    FChanges: Integer;
    procedure OnCfgChanged(Sender: TObject; AId: Integer);
  end;

  TTestParsing = class(TTestCase)
  private
    FCfg: TLedDocConfig;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AliasesResolve;
    procedure BoolSpellings;
    procedure UnknownNameIsIgnored;
    procedure UnparsableIntIsIgnored;
    procedure ParseStringAcceptsColonAndEquals;
  end;

  TTestModeline = class(TTestCase)
  private
    FCfg: TLedDocConfig;
    function IsLanguage(const AName: string): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure EmacsVariableList;
    procedure EmacsBareLanguage;
    procedure EmacsBareUnknownIsRejected;
    procedure EmacsIndentTabsModeNilMeansSpaces;
    procedure KateSpaceIndentIsInverted;
    procedure KateVariables;
    procedure OwnMarker;
    procedure UnterminatedMarkerIsIgnored;
    procedure PlainTextIsIgnored;
    procedure ScansFirstSecondAndLastLine;
    procedure ShortDocumentIsNotScannedTwice;
    procedure ModelineLosesToAGlobRule;
  end;

implementation

{ TTestPrecedence }

procedure TTestPrecedence.SetUp;
begin
  FCfg := TLedDocConfig.Create;
  FChanges := 0;
end;

procedure TTestPrecedence.TearDown;
begin
  FCfg.Free;
end;

procedure TTestPrecedence.OnCfgChanged(Sender: TObject; AId: Integer);
begin
  Inc(FChanges);
end;

procedure TTestPrecedence.DefaultsApplyWhenNothingIsSet;
begin
  AssertEquals(8, FCfg.GetInt(LedSetTabWidth));
  AssertEquals(4, FCfg.GetInt(LedSetIndentWidth));
  AssertFalse(FCfg.HasValue(LedSetTabWidth));
end;

procedure TTestPrecedence.MoreSpecificSourceWins;
begin
  FCfg.SetInt(LedSetTabWidth, 2, lcsUser);
  FCfg.SetInt(LedSetTabWidth, 4, lcsFile);
  AssertEquals('modeline beats preferences', 4, FCfg.GetInt(LedSetTabWidth));
end;

procedure TTestPrecedence.LessSpecificSourceIsIgnored;
begin
  FCfg.SetInt(LedSetTabWidth, 4, lcsLang);
  FCfg.SetInt(LedSetTabWidth, 2, lcsUser);
  AssertEquals('preferences do not override the language', 4,
    FCfg.GetInt(LedSetTabWidth));
end;

procedure TTestPrecedence.SameSourceOverwrites;
begin
  FCfg.SetInt(LedSetTabWidth, 2, lcsFile);
  FCfg.SetInt(LedSetTabWidth, 7, lcsFile);
  AssertEquals(7, FCfg.GetInt(LedSetTabWidth));
end;

procedure TTestPrecedence.UnsetBySourceClearsOnlyThatLayer;
begin
  FCfg.SetInt(LedSetTabWidth, 2, lcsUser);
  FCfg.SetInt(LedSetIndentWidth, 3, lcsFilename);
  FCfg.UnsetBySource(lcsFilename);
  AssertEquals('the user layer survives', 2, FCfg.GetInt(LedSetTabWidth));
  AssertFalse('the glob layer is gone', FCfg.HasValue(LedSetIndentWidth));
end;

procedure TTestPrecedence.UnsetRevealsTheLayerBelowNothing;
begin
  { Layers do not stack: clearing a source drops the value entirely rather
    than restoring what a weaker source once said.  This matches medit and is
    why the config is rebuilt from scratch after Save As. }
  FCfg.SetInt(LedSetTabWidth, 2, lcsUser);
  FCfg.SetInt(LedSetTabWidth, 4, lcsFilename);
  FCfg.UnsetBySource(lcsFilename);
  AssertFalse(FCfg.HasValue(LedSetTabWidth));
  AssertEquals('falls back to the default', 8, FCfg.GetInt(LedSetTabWidth));
end;

procedure TTestPrecedence.ParentSuppliesUnsetValues;
var
  Child: TLedDocConfig;
begin
  FCfg.SetInt(LedSetTabWidth, 2, lcsUser);
  Child := TLedDocConfig.Create(FCfg);
  try
    AssertEquals(2, Child.GetInt(LedSetTabWidth));
  finally
    Child.Free;
  end;
end;

procedure TTestPrecedence.ChildOverridesParent;
var
  Child: TLedDocConfig;
begin
  FCfg.SetInt(LedSetTabWidth, 2, lcsUser);
  Child := TLedDocConfig.Create(FCfg);
  try
    Child.SetInt(LedSetTabWidth, 5, lcsUser);
    AssertEquals(5, Child.GetInt(LedSetTabWidth));
    AssertEquals('the parent is untouched', 2, FCfg.GetInt(LedSetTabWidth));
  finally
    Child.Free;
  end;
end;

procedure TTestPrecedence.ChangeNotificationFires;
begin
  FCfg.OnChanged := @OnCfgChanged;
  FCfg.SetInt(LedSetTabWidth, 2, lcsUser);
  AssertEquals(1, FChanges);
  FCfg.SetInt(LedSetTabWidth, 3, lcsUser);
  AssertEquals(2, FChanges);
  FCfg.UnsetBySource(lcsUser);
  AssertEquals(3, FChanges);
end;

{ TTestParsing }

procedure TTestParsing.SetUp;
begin
  FCfg := TLedDocConfig.Create;
end;

procedure TTestParsing.TearDown;
begin
  FCfg.Free;
end;

procedure TTestParsing.AliasesResolve;
begin
  AssertTrue(FCfg.SetFromString('tab_width', '3', lcsFile));
  AssertEquals(3, FCfg.GetInt(LedSetTabWidth));
  AssertTrue(FCfg.SetFromString('c-basic-offset', '6', lcsFile));
  AssertEquals(6, FCfg.GetInt(LedSetIndentWidth));
  AssertTrue(FCfg.SetFromString('mode', 'python', lcsFile));
  AssertEquals('python', FCfg.GetStr(LedSetLang));
end;

procedure TTestParsing.BoolSpellings;
var
  B: Boolean;
begin
  AssertTrue(LedParseBool('true', B) and B);
  AssertTrue(LedParseBool('YES', B) and B);
  AssertTrue(LedParseBool('1', B) and B);
  AssertTrue(LedParseBool('on', B) and B);
  AssertTrue(LedParseBool('false', B) and not B);
  AssertTrue(LedParseBool('nil', B) and not B);
  AssertTrue(LedParseBool('0', B) and not B);
  AssertFalse('gibberish is rejected', LedParseBool('maybe', B));
end;

procedure TTestParsing.UnknownNameIsIgnored;
begin
  AssertFalse(FCfg.SetFromString('no-such-setting', '1', lcsFile));
end;

procedure TTestParsing.UnparsableIntIsIgnored;
begin
  { A typo must not silently mean zero. }
  AssertFalse(FCfg.SetFromString('tab-width', 'wide', lcsFile));
  AssertFalse(FCfg.HasValue(LedSetTabWidth));
  AssertEquals(8, FCfg.GetInt(LedSetTabWidth));
end;

procedure TTestParsing.ParseStringAcceptsColonAndEquals;
begin
  FCfg.ParseString('tab-width: 3; indent-width = 5; strip: true', lcsFile);
  AssertEquals(3, FCfg.GetInt(LedSetTabWidth));
  AssertEquals(5, FCfg.GetInt(LedSetIndentWidth));
  AssertTrue(FCfg.GetBool(LedSetStripTrailing));
end;

{ TTestModeline }

procedure TTestModeline.SetUp;
begin
  FCfg := TLedDocConfig.Create;
end;

procedure TTestModeline.TearDown;
begin
  FCfg.Free;
end;

function TTestModeline.IsLanguage(const AName: string): Boolean;
begin
  Result := (LowerCase(AName) = 'python') or (LowerCase(AName) = 'c');
end;

procedure TTestModeline.EmacsVariableList;
begin
  LedApplyModeline('# -*- mode: python; tab-width: 4 -*-', FCfg, @IsLanguage);
  AssertEquals('python', FCfg.GetStr(LedSetLang));
  AssertEquals(4, FCfg.GetInt(LedSetTabWidth));
end;

procedure TTestModeline.EmacsBareLanguage;
begin
  LedApplyModeline('/* -*- C -*- */', FCfg, @IsLanguage);
  AssertEquals('c', FCfg.GetStr(LedSetLang));
end;

procedure TTestModeline.EmacsBareUnknownIsRejected;
begin
  LedApplyModeline('-*- notalanguage -*-', FCfg, @IsLanguage);
  AssertFalse(FCfg.HasValue(LedSetLang));
end;

procedure TTestModeline.EmacsIndentTabsModeNilMeansSpaces;
begin
  { The name says "tabs", the value nil means spaces.  Getting this backwards
    silently retabs people's files. }
  LedApplyModeline('-*- indent-tabs-mode: nil -*-', FCfg, @IsLanguage);
  AssertTrue(FCfg.HasValue(LedSetIndentUseTabs));
  AssertFalse(FCfg.GetBool(LedSetIndentUseTabs));

  FCfg.UnsetBySource(lcsFile);
  LedApplyModeline('-*- indent-tabs-mode: t -*-', FCfg, @IsLanguage);
  AssertTrue(FCfg.GetBool(LedSetIndentUseTabs));
end;

procedure TTestModeline.KateSpaceIndentIsInverted;
begin
  LedApplyModeline('// kate: space-indent on;', FCfg);
  AssertTrue(FCfg.HasValue(LedSetIndentUseTabs));
  AssertFalse('space-indent on means do not use tabs',
    FCfg.GetBool(LedSetIndentUseTabs));
end;

procedure TTestModeline.KateVariables;
begin
  LedApplyModeline('// kate: indent-width 2; tab-width 8;', FCfg);
  AssertEquals(2, FCfg.GetInt(LedSetIndentWidth));
  AssertEquals(8, FCfg.GetInt(LedSetTabWidth));
end;

procedure TTestModeline.OwnMarker;
begin
  LedApplyModeline('# -%- lang: c; indent-width = 2 -%-', FCfg);
  AssertEquals('c', FCfg.GetStr(LedSetLang));
  AssertEquals(2, FCfg.GetInt(LedSetIndentWidth));
end;

procedure TTestModeline.UnterminatedMarkerIsIgnored;
begin
  LedApplyModeline('-*- mode: python', FCfg, @IsLanguage);
  AssertFalse('an unclosed emacs marker is not a modeline',
    FCfg.HasValue(LedSetLang));
end;

procedure TTestModeline.PlainTextIsIgnored;
begin
  LedApplyModeline('int main(void) { return 0; }', FCfg);
  AssertFalse(FCfg.HasValue(LedSetLang));
  AssertFalse(FCfg.HasValue(LedSetTabWidth));
end;

procedure TTestModeline.ScansFirstSecondAndLastLine;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add('#!/usr/bin/env python');
    L.Add('# -*- tab-width: 2 -*-');
    L.Add('body');
    L.Add('# -%- indent-width: 7 -%-');
    LedApplyModelines(L, FCfg, @IsLanguage);
    AssertEquals('second line was read', 2, FCfg.GetInt(LedSetTabWidth));
    AssertEquals('last line was read', 7, FCfg.GetInt(LedSetIndentWidth));
  finally
    L.Free;
  end;
end;

procedure TTestModeline.ShortDocumentIsNotScannedTwice;
var
  L: TStringList;
begin
  { With two lines, the "last" line is the second one; reading it again would
    be harmless here but wrong for a marker that toggles. }
  L := TStringList.Create;
  try
    L.Add('# -%- tab-width: 3 -%-');
    L.Add('body');
    LedApplyModelines(L, FCfg);
    AssertEquals(3, FCfg.GetInt(LedSetTabWidth));
  finally
    L.Free;
  end;
end;

procedure TTestModeline.ModelineLosesToAGlobRule;
begin
  { A Makefile rule saying "use tabs" must beat a modeline that says
    otherwise, because the file format demands it. }
  LedApplyModeline('# -*- indent-tabs-mode: nil -*-', FCfg, @IsLanguage);
  FCfg.SetBool(LedSetIndentUseTabs, True, lcsFilename);
  AssertTrue(FCfg.GetBool(LedSetIndentUseTabs));
end;

initialization
  RegisterTest(TTestPrecedence);
  RegisterTest(TTestParsing);
  RegisterTest(TTestModeline);

end.
