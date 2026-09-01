{ led - a light editor.  Layered per-document settings.

  Ported from medit's mooeditconfig.cpp, minus the GObject property machinery.
  The idea worth keeping is the precedence chain: the same setting can be
  stated by the user's preferences, by a modeline in the file, by a
  filename-glob rule, by the language, or by detection, and the more specific
  source wins.

    user (0) < file/modeline (10) < filename glob (20) < language (30) < auto (40)

  A write at source S lands only if the slot is unset or was last written by a
  source no more specific than S.  UnsetBySource clears one layer, which is
  how glob rules are re-evaluated after Save As without disturbing anything
  the user typed.

  No LCL dependency. }
unit Led.Core.Config;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Led.Core.Types;

type
  TLedSettingKind = (skBool, skInt, skString);

  TLedSettingDef = record
    Name: string;
    Aliases: string;        // comma-separated alternative spellings
    Kind: TLedSettingKind;
    DefInt: Int64;
    DefStr: string;
  end;

  { Process-global list of what settings exist.  Registered once at startup;
    ids are stable for the life of the process so a config is a flat array. }
  TLedSettingRegistry = class
  private
    FDefs: array of TLedSettingDef;
    FIndex: TStringList;    // name or alias -> id
    function GetDef(AId: Integer): TLedSettingDef;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function Install(const ADef: TLedSettingDef): Integer;
    function InstallBool(const AName, AAliases: string; ADefault: Boolean): Integer;
    function InstallInt(const AName, AAliases: string; ADefault: Int64): Integer;
    function InstallStr(const AName, AAliases: string; const ADefault: string): Integer;
    { -1 when the name is not a known setting. }
    function IdOf(const AName: string): Integer;
    property Defs[AId: Integer]: TLedSettingDef read GetDef;
    property Count: Integer read GetCount;
  end;

  TLedConfigChangedEvent = procedure(Sender: TObject; AId: Integer) of object;

  TLedDocConfig = class
  private
    FSlots: array of record
      HasValue: Boolean;
      Source: TLedConfigSource;
      IntVal: Int64;
      StrVal: string;
    end;
    FParent: TLedDocConfig;
    FOnChanged: TLedConfigChangedEvent;
    procedure Grow;
    function Accepts(AId: Integer; ASource: TLedConfigSource): Boolean;
    procedure Changed(AId: Integer);
  public
    { AParent supplies values for slots this config has not set; the global
      preferences config is everything's parent. }
    constructor Create(AParent: TLedDocConfig = nil);

    procedure SetInt(AId: Integer; AValue: Int64; ASource: TLedConfigSource);
    procedure SetBool(AId: Integer; AValue: Boolean; ASource: TLedConfigSource);
    procedure SetStr(AId: Integer; const AValue: string; ASource: TLedConfigSource);

    { Parses AValue according to the setting's kind.  Returns False for an
      unknown name or an unparsable value, so a typo in a modeline is ignored
      rather than silently meaning zero. }
    function SetFromString(const AName, AValue: string;
      ASource: TLedConfigSource): Boolean;

    { Parses "name: value; name = value; ..." -- the -%- modeline body and
      the same syntax medit accepted. }
    procedure ParseString(const AString: string; ASource: TLedConfigSource);

    procedure UnsetBySource(ASource: TLedConfigSource);
    function HasValue(AId: Integer): Boolean;
    function SourceOf(AId: Integer): TLedConfigSource;

    function GetInt(AId: Integer): Int64;
    function GetBool(AId: Integer): Boolean;
    function GetStr(AId: Integer): string;

    property Parent: TLedDocConfig read FParent write FParent;
    property OnChanged: TLedConfigChangedEvent read FOnChanged write FOnChanged;
  end;

function LedParseBool(const AValue: string; out AResult: Boolean): Boolean;

var
  { The registry, and the ids of the settings led itself knows about. }
  LedSettings: TLedSettingRegistry = nil;

  LedSetLang: Integer;
  LedSetTabWidth: Integer;
  LedSetIndentWidth: Integer;
  LedSetIndentUseTabs: Integer;
  LedSetStripTrailing: Integer;
  LedSetAddNewline: Integer;
  LedSetWrapMode: Integer;
  LedSetShowLineNumbers: Integer;
  LedSetWordChars: Integer;
  LedSetEncoding: Integer;
  LedSetLineEnd: Integer;
  LedSetEnableBookmarks: Integer;

implementation

function LedParseBool(const AValue: string; out AResult: Boolean): Boolean;
var
  V: string;
begin
  V := LowerCase(Trim(AValue));
  Result := True;
  if (V = 'true') or (V = 'yes') or (V = '1') or (V = 'on') or (V = 't') then
    AResult := True
  else if (V = 'false') or (V = 'no') or (V = '0') or (V = 'off') or (V = 'nil') then
    AResult := False
  else
  begin
    AResult := False;
    Result := False;
  end;
end;

{ TLedSettingRegistry }

constructor TLedSettingRegistry.Create;
begin
  inherited Create;
  FIndex := TStringList.Create;
  FIndex.CaseSensitive := False;
  FIndex.Sorted := True;
  FIndex.Duplicates := dupIgnore;
end;

destructor TLedSettingRegistry.Destroy;
begin
  FIndex.Free;
  inherited Destroy;
end;

function TLedSettingRegistry.GetCount: Integer;
begin
  Result := Length(FDefs);
end;

function TLedSettingRegistry.GetDef(AId: Integer): TLedSettingDef;
begin
  Result := FDefs[AId];
end;

function TLedSettingRegistry.Install(const ADef: TLedSettingDef): Integer;
var
  Parts: TStringArray;
  i: Integer;
begin
  Result := Length(FDefs);
  SetLength(FDefs, Result + 1);
  FDefs[Result] := ADef;

  FIndex.AddObject(ADef.Name, TObject(PtrInt(Result)));
  if ADef.Aliases <> '' then
  begin
    Parts := ADef.Aliases.Split([',']);
    for i := 0 to High(Parts) do
      if Trim(Parts[i]) <> '' then
        FIndex.AddObject(Trim(Parts[i]), TObject(PtrInt(Result)));
  end;
end;

function TLedSettingRegistry.InstallBool(const AName, AAliases: string;
  ADefault: Boolean): Integer;
var
  D: TLedSettingDef;
begin
  D.Name := AName; D.Aliases := AAliases; D.Kind := skBool;
  D.DefInt := Ord(ADefault); D.DefStr := '';
  Result := Install(D);
end;

function TLedSettingRegistry.InstallInt(const AName, AAliases: string;
  ADefault: Int64): Integer;
var
  D: TLedSettingDef;
begin
  D.Name := AName; D.Aliases := AAliases; D.Kind := skInt;
  D.DefInt := ADefault; D.DefStr := '';
  Result := Install(D);
end;

function TLedSettingRegistry.InstallStr(const AName, AAliases: string;
  const ADefault: string): Integer;
var
  D: TLedSettingDef;
begin
  D.Name := AName; D.Aliases := AAliases; D.Kind := skString;
  D.DefInt := 0; D.DefStr := ADefault;
  Result := Install(D);
end;

function TLedSettingRegistry.IdOf(const AName: string): Integer;
var
  i: Integer;
begin
  i := FIndex.IndexOf(Trim(AName));
  if i < 0 then
    Result := -1
  else
    Result := PtrInt(FIndex.Objects[i]);
end;

{ TLedDocConfig }

constructor TLedDocConfig.Create(AParent: TLedDocConfig);
begin
  inherited Create;
  FParent := AParent;
  Grow;
end;

procedure TLedDocConfig.Grow;
begin
  if Length(FSlots) < LedSettings.Count then
    SetLength(FSlots, LedSettings.Count);
end;

{ The whole precedence rule, in one place. }
function TLedDocConfig.Accepts(AId: Integer; ASource: TLedConfigSource): Boolean;
begin
  Grow;
  Result := (not FSlots[AId].HasValue) or (FSlots[AId].Source <= ASource);
end;

procedure TLedDocConfig.Changed(AId: Integer);
begin
  if Assigned(FOnChanged) then FOnChanged(Self, AId);
end;

procedure TLedDocConfig.SetInt(AId: Integer; AValue: Int64;
  ASource: TLedConfigSource);
begin
  if not Accepts(AId, ASource) then Exit;
  FSlots[AId].HasValue := True;
  FSlots[AId].Source := ASource;
  FSlots[AId].IntVal := AValue;
  Changed(AId);
end;

procedure TLedDocConfig.SetBool(AId: Integer; AValue: Boolean;
  ASource: TLedConfigSource);
begin
  SetInt(AId, Ord(AValue), ASource);
end;

procedure TLedDocConfig.SetStr(AId: Integer; const AValue: string;
  ASource: TLedConfigSource);
begin
  if not Accepts(AId, ASource) then Exit;
  FSlots[AId].HasValue := True;
  FSlots[AId].Source := ASource;
  FSlots[AId].StrVal := AValue;
  Changed(AId);
end;

function TLedDocConfig.SetFromString(const AName, AValue: string;
  ASource: TLedConfigSource): Boolean;
var
  Id: Integer;
  B: Boolean;
  I: Int64;
begin
  Id := LedSettings.IdOf(AName);
  if Id < 0 then Exit(False);

  case LedSettings.Defs[Id].Kind of
    skBool:
      begin
        Result := LedParseBool(AValue, B);
        if Result then SetBool(Id, B, ASource);
      end;
    skInt:
      begin
        Result := TryStrToInt64(Trim(AValue), I);
        if Result then SetInt(Id, I, ASource);
      end;
  else
    SetStr(Id, Trim(AValue), ASource);
    Result := True;
  end;
end;

procedure TLedDocConfig.ParseString(const AString: string;
  ASource: TLedConfigSource);
var
  Entries: TStringArray;
  i, SepPos, ColonPos, AssignPos: Integer;
  Entry, Name, Value: string;
begin
  Entries := AString.Split([';']);
  for i := 0 to High(Entries) do
  begin
    Entry := Trim(Entries[i]);
    if Entry = '' then Continue;

    { Either separator is accepted, whichever comes first, matching
      moo_edit_config_parse. }
    ColonPos := Pos(':', Entry);
    AssignPos := Pos('=', Entry);
    if (ColonPos = 0) or ((AssignPos > 0) and (AssignPos < ColonPos)) then
      SepPos := AssignPos
    else
      SepPos := ColonPos;
    if SepPos <= 1 then Continue;

    Name := Trim(Copy(Entry, 1, SepPos - 1));
    Value := Trim(Copy(Entry, SepPos + 1, MaxInt));
    if (Name = '') or (Value = '') then Continue;

    SetFromString(Name, Value, ASource);
  end;
end;

procedure TLedDocConfig.UnsetBySource(ASource: TLedConfigSource);
var
  i: Integer;
begin
  Grow;
  for i := 0 to High(FSlots) do
    if FSlots[i].HasValue and (FSlots[i].Source = ASource) then
    begin
      FSlots[i].HasValue := False;
      FSlots[i].StrVal := '';
      FSlots[i].IntVal := 0;
      Changed(i);
    end;
end;

function TLedDocConfig.HasValue(AId: Integer): Boolean;
begin
  Grow;
  Result := FSlots[AId].HasValue;
end;

function TLedDocConfig.SourceOf(AId: Integer): TLedConfigSource;
begin
  Grow;
  Result := FSlots[AId].Source;
end;

function TLedDocConfig.GetInt(AId: Integer): Int64;
begin
  Grow;
  if FSlots[AId].HasValue then
    Result := FSlots[AId].IntVal
  else if FParent <> nil then
    Result := FParent.GetInt(AId)
  else
    Result := LedSettings.Defs[AId].DefInt;
end;

function TLedDocConfig.GetBool(AId: Integer): Boolean;
begin
  Result := GetInt(AId) <> 0;
end;

function TLedDocConfig.GetStr(AId: Integer): string;
begin
  Grow;
  if FSlots[AId].HasValue then
    Result := FSlots[AId].StrVal
  else if FParent <> nil then
    Result := FParent.GetStr(AId)
  else
    Result := LedSettings.Defs[AId].DefStr;
end;

procedure RegisterBuiltinSettings;
begin
  LedSettings := TLedSettingRegistry.Create;
  { Aliases carry the spellings other editors' modelines use, so a kate or
    emacs line lands on the same slot as led's own. }
  LedSetLang            := LedSettings.InstallStr ('lang', 'mode,syntax,hl', '');
  LedSetTabWidth        := LedSettings.InstallInt ('tab-width', 'tab_width,tabwidth,ts,tab-widths', 8);
  LedSetIndentWidth     := LedSettings.InstallInt ('indent-width', 'indent_width,indentwidth,c-basic-offset,sw,shiftwidth', 4);
  LedSetIndentUseTabs   := LedSettings.InstallBool('indent-use-tabs', 'use-tabs,indent_use_tabs,indent-tabs-mode,et', True);
  LedSetStripTrailing   := LedSettings.InstallBool('strip', 'strip-trailing-space', False);
  LedSetAddNewline      := LedSettings.InstallBool('add-newline', 'add-final-newline', True);
  LedSetWrapMode        := LedSettings.InstallStr ('wrap-mode', 'wrap', 'none');
  LedSetShowLineNumbers := LedSettings.InstallBool('show-line-numbers', 'line-numbers,nu', True);
  LedSetWordChars       := LedSettings.InstallStr ('word-chars', '', '');
  LedSetEncoding        := LedSettings.InstallStr ('encoding', 'enc,fileencoding,fenc', '');
  LedSetLineEnd         := LedSettings.InstallStr ('line-end-type', 'line-end,fileformat,ff', '');
  LedSetEnableBookmarks := LedSettings.InstallBool('enable-bookmarks', '', True);
end;

initialization
  RegisterBuiltinSettings;

finalization
  LedSettings.Free;

end.
