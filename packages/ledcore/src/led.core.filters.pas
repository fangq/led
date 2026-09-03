{ led - a light editor.  Filename-based configuration rules.

  Ported from medit's mooeditfiltersettings.cpp.  A rule pairs a filter with a
  config string, and every rule whose filter matches the document is applied
  at lcsFilename precedence -- above a modeline, below the language default.
  That ordering is deliberate and is the reason the feature exists: a Makefile
  needs real tabs whatever the file itself claims.

  Filter syntax, unchanged from medit:

      globs:Makefile*;*.mk     match the file name against any of the globs
      langs:c,cpp              match the detected language id
      regex:^/etc/             match the full path against a regex
      Makefile*                bare text means globs

  medit read a bare filter as a regex for config rules and as globs for action
  rules.  led always reads it as globs, because that is what people write and
  the regex reading silently mis-parsed "*.c" for anyone who tried it.

  No LCL dependency. }
unit Led.Core.Filters;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Masks, RegExpr, Led.Core.Types, Led.Core.Config;

type
  TLedFilterKind = (lfkGlobs, lfkLangs, lfkRegex);

  TLedEditFilter = class
  private
    FKind: TLedFilterKind;
    FSource: string;
    FTerms: TStringList;      // globs or language ids
    FRegex: TRegExpr;
    FValid: Boolean;
  public
    constructor Create(const ADefinition: string);
    destructor Destroy; override;
    function Matches(const AFileName, ALangId: string): Boolean;
    property Kind: TLedFilterKind read FKind;
    property Source: string read FSource;
    property Valid: Boolean read FValid;
  end;

  TLedFilterRule = class
  private
    FFilter: TLedEditFilter;
    FConfig: string;
    FDefinition: string;
  public
    constructor Create(const AFilter, AConfig: string);
    destructor Destroy; override;
    property Filter: TLedEditFilter read FFilter;
    property Config: string read FConfig;
    { Exactly the text the rule was written as, so the preferences page can
      show it back rather than reconstructing it from the parsed form. }
    property Definition: string read FDefinition;
  end;

  TLedFilterSettings = class
  private
    FRules: TFPList;          // of TLedFilterRule, owned
    function GetCount: Integer;
    function GetRule(AIndex: Integer): TLedFilterRule;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Add(const AFilter, AConfig: string): TLedFilterRule;
    procedure LoadDefaults;

    { Stored in prefs.ini as a numbered list under [FilterSettings]:

        count=2
        1.filter=globs:Makefile*
        1.config=indent-use-tabs: true

      Two keys per rule rather than one delimited line, because a regex
      filter can contain any separator character you might pick. }
    procedure LoadFromPrefs;
    procedure SaveToPrefs;

    { Applies every matching rule to AConfig.  The caller is expected to have
      cleared the lcsFilename layer first, so that rules are re-evaluated
      cleanly after a Save As. }
    function ApplyTo(AConfig: TLedDocConfig;
      const AFileName, ALangId: string): Integer;

    property Count: Integer read GetCount;
    { The rule written exactly as ADefinition, or nil. }
    function FindByDefinition(const ADefinition: string): TLedFilterRule;
    property Rules[AIndex: Integer]: TLedFilterRule read GetRule; default;
  end;

{ The process-wide filter settings, loaded from prefs on first use.  It lives
  here rather than beside the documents so that the preferences page can edit
  it without depending on the document layer. }
function LedFilters: TLedFilterSettings;

implementation

uses
  Led.Core.Prefs;

{ TLedEditFilter }

constructor TLedEditFilter.Create(const ADefinition: string);
var
  Body: string;
begin
  inherited Create;
  FSource := ADefinition;
  FTerms := TStringList.Create;
  FTerms.CaseSensitive := False;
  FValid := True;

  if Copy(ADefinition, 1, 6) = 'globs:' then
  begin
    FKind := lfkGlobs;
    Body := Copy(ADefinition, 7, MaxInt);
  end
  else if Copy(ADefinition, 1, 6) = 'langs:' then
  begin
    FKind := lfkLangs;
    Body := Copy(ADefinition, 7, MaxInt);
  end
  else if Copy(ADefinition, 1, 6) = 'regex:' then
  begin
    FKind := lfkRegex;
    Body := Copy(ADefinition, 7, MaxInt);
  end
  else
  begin
    FKind := lfkGlobs;
    Body := ADefinition;
  end;

  case FKind of
    lfkRegex:
      begin
        FRegex := TRegExpr.Create;
        FRegex.Expression := Body;
        try
          FRegex.Compile;
        except
          { A rule with a broken pattern is inert rather than fatal. }
          FValid := False;
        end;
      end;
  else
    { Both ';' and ',' separate terms; medit used ';' for globs and ',' for
      languages, and people mix them up. }
    FTerms.Delimiter := ';';
    FTerms.StrictDelimiter := True;
    FTerms.DelimitedText := StringReplace(Body, ',', ';', [rfReplaceAll]);
    FValid := FTerms.Count > 0;
  end;
end;

destructor TLedEditFilter.Destroy;
begin
  FTerms.Free;
  FRegex.Free;
  inherited Destroy;
end;

function TLedEditFilter.Matches(const AFileName, ALangId: string): Boolean;
var
  i: Integer;
  Base: string;
begin
  Result := False;
  if not FValid then Exit;

  case FKind of
    lfkGlobs:
      begin
        if AFileName = '' then Exit;
        Base := ExtractFileName(AFileName);
        for i := 0 to FTerms.Count - 1 do
          if Trim(FTerms[i]) <> '' then
            if MatchesMask(Base, Trim(FTerms[i]),
               {$IFDEF WINDOWS}False{$ELSE}True{$ENDIF}) then
              Exit(True);
      end;
    lfkLangs:
      begin
        if ALangId = '' then Exit;
        for i := 0 to FTerms.Count - 1 do
          if SameText(Trim(FTerms[i]), ALangId) then
            Exit(True);
      end;
    lfkRegex:
      begin
        if AFileName = '' then Exit;
        try
          Result := FRegex.Exec(AFileName);
        except
          Result := False;
        end;
      end;
  end;
end;

{ TLedFilterRule }

constructor TLedFilterRule.Create(const AFilter, AConfig: string);
begin
  inherited Create;
  FFilter := TLedEditFilter.Create(AFilter);
  FConfig := AConfig;
  FDefinition := AFilter;
end;

destructor TLedFilterRule.Destroy;
begin
  FFilter.Free;
  inherited Destroy;
end;

{ TLedFilterSettings }

constructor TLedFilterSettings.Create;
begin
  inherited Create;
  FRules := TFPList.Create;
end;

destructor TLedFilterSettings.Destroy;
begin
  Clear;
  FRules.Free;
  inherited Destroy;
end;

procedure TLedFilterSettings.Clear;
var
  i: Integer;
begin
  for i := 0 to FRules.Count - 1 do
    TLedFilterRule(FRules[i]).Free;
  FRules.Clear;
end;

function TLedFilterSettings.GetCount: Integer;
begin
  Result := FRules.Count;
end;

function TLedFilterSettings.GetRule(AIndex: Integer): TLedFilterRule;
begin
  Result := TLedFilterRule(FRules[AIndex]);
end;

function TLedFilterSettings.Add(const AFilter, AConfig: string): TLedFilterRule;
begin
  Result := TLedFilterRule.Create(AFilter, AConfig);
  FRules.Add(Result);
end;

procedure TLedFilterSettings.LoadDefaults;
begin
  Clear;
  { Makefiles are the classic case: the format requires a literal tab, so the
    rule has to outrank both the user's preference and any modeline. }
  Add('globs:Makefile*;makefile*;GNUmakefile;*.mk',
      'indent-use-tabs: true; tab-width: 8');
  { Patches are read, not edited; showing them with the author's own spacing
    matters more than the local preference. }
  Add('globs:*.diff;*.patch', 'indent-use-tabs: true; strip: false');
  Add('langs:python;python3', 'indent-use-tabs: false; indent-width: 4');
  Add('langs:makefile', 'indent-use-tabs: true');
end;

procedure TLedFilterSettings.LoadFromPrefs;
var
  N, i: Integer;
  Filter, Cfg: string;
  Seen: TStringList;
begin
  Clear;
  N := LedPrefs.GetInt('FilterSettings/count', -1);
  if N < 0 then
  begin
    { No section at all means a fresh profile, not "the user deleted every
      rule", so the built-in rules apply. }
    LoadDefaults;
    Exit;
  end;

  { An identical rule twice does nothing a single one does not, so drop the
    repeats.  This is not tidiness: the self-test used to append its scratch
    rule to the real prefs.ini on every run, and one profile had a hundred
    copies of it filling the filters page.  Reading the file heals it; the
    next save writes the short list back. }
  Seen := TStringList.Create;
  try
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    for i := 1 to N do
    begin
      Filter := LedPrefs.GetStr(Format('FilterSettings/%d.filter', [i]), '');
      Cfg := LedPrefs.GetStr(Format('FilterSettings/%d.config', [i]), '');
      if (Filter = '') or (Cfg = '') then Continue;
      if Seen.IndexOf(Filter + #1 + Cfg) >= 0 then Continue;
      Seen.Add(Filter + #1 + Cfg);
      Add(Filter, Cfg);
    end;
  finally
    Seen.Free;
  end;
end;

procedure TLedFilterSettings.SaveToPrefs;
var
  i, Old: Integer;
begin
  Old := LedPrefs.GetInt('FilterSettings/count', 0);
  for i := 1 to Old do
  begin
    LedPrefs.Remove(Format('FilterSettings/%d.filter', [i]));
    LedPrefs.Remove(Format('FilterSettings/%d.config', [i]));
  end;

  LedPrefs.SetInt('FilterSettings/count', FRules.Count);
  for i := 0 to FRules.Count - 1 do
  begin
    LedPrefs.SetStr(Format('FilterSettings/%d.filter', [i + 1]),
      Rules[i].Filter.Source);
    LedPrefs.SetStr(Format('FilterSettings/%d.config', [i + 1]),
      Rules[i].Config);
  end;
end;

function TLedFilterSettings.ApplyTo(AConfig: TLedDocConfig;
  const AFileName, ALangId: string): Integer;
var
  i: Integer;
  Rule: TLedFilterRule;
begin
  Result := 0;
  for i := 0 to FRules.Count - 1 do
  begin
    Rule := TLedFilterRule(FRules[i]);
    if Rule.Filter.Matches(AFileName, ALangId) then
    begin
      AConfig.ParseString(Rule.Config, lcsFilename);
      Inc(Result);
    end;
  end;
end;

var
  FFilters: TLedFilterSettings = nil;

function TLedFilterSettings.FindByDefinition(
  const ADefinition: string): TLedFilterRule;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
    if Rules[i].Definition = ADefinition then Exit(Rules[i]);
  Result := nil;
end;

function LedFilters: TLedFilterSettings;
begin
  if FFilters = nil then
  begin
    FFilters := TLedFilterSettings.Create;
    FFilters.LoadFromPrefs;
  end;
  Result := FFilters;
end;

finalization
  FFilters.Free;

end.
