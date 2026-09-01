{ led - a light editor.  User preferences.

  medit stored these as XML under a hand-rolled DOM; led uses an INI file,
  because the settings model is flat dotted keys and that is exactly what INI
  sections express:

      Editor/tab_width            ->  [Editor]         tab_width=4
      Plugins/Terminal/font       ->  [Plugins.Terminal] font=...

  Keeping the medit key names means the settings vocabulary carries over even
  though the file format does not.

  No LCL dependency. }
unit Led.Core.Prefs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, Led.Core.Types, Led.Core.Paths, Led.Core.Config;

type
  TLedPrefs = class
  private
    FIni: TMemIniFile;
    FFileName: string;
    FDirty: Boolean;
    procedure Split(const AKey: string; out ASection, AName: string);
  public
    constructor Create(const AFileName: string = '');
    destructor Destroy; override;

    function GetStr(const AKey, ADefault: string): string;
    function GetInt(const AKey: string; ADefault: Int64): Int64;
    function GetBool(const AKey: string; ADefault: Boolean): Boolean;

    procedure SetStr(const AKey, AValue: string);
    procedure SetInt(const AKey: string; AValue: Int64);
    procedure SetBool(const AKey: string; AValue: Boolean);

    function HasKey(const AKey: string): Boolean;
    procedure Remove(const AKey: string);

    procedure Load;
    procedure Save;

    { Copies the Editor/* keys that correspond to registered settings into
      AConfig at source lcsUser.  This is the bridge between "what the user
      configured" and the per-document precedence chain. }
    procedure ApplyToConfig(AConfig: TLedDocConfig);

    property FileName: string read FFileName;
    property Dirty: Boolean read FDirty;
  end;

{ The process-wide preferences, loaded on first use. }
function LedPrefs: TLedPrefs;

const
  { Key names carried over from medit so the vocabulary is unchanged. }
  LedPrefFont            = 'Editor/font';
  LedPrefColorScheme     = 'Editor/color_scheme';
  LedPrefTabWidth        = 'Editor/tab_width';
  LedPrefIndentWidth     = 'Editor/indent_width';
  LedPrefSpacesNotTabs   = 'Editor/spaces_instead_of_tabs';
  LedPrefAutoIndent      = 'Editor/auto_indent';
  LedPrefStripTrailing   = 'Editor/strip';
  LedPrefAddNewline      = 'Editor/add_newline';
  LedPrefMakeBackups     = 'Editor/make_backups';
  LedPrefShowLineNumbers = 'Editor/show_line_numbers';
  LedPrefHighlightLine   = 'Editor/highlight_current_line';
  LedPrefRightMargin     = 'Editor/draw_right_margin';
  LedPrefRightMarginAt   = 'Editor/right_margin_offset';
  LedPrefWrapEnable      = 'Editor/wrapping_enable';
  LedPrefEncodings       = 'Editor/encodings';
  LedPrefSaveSession     = 'Editor/save_session';

  { Crash recovery.  New keys rather than medit's auto_save/auto_save_interval,
    which mean something different: those write the user's actual file behind
    their back, this keeps a private journal and never touches it. }
  LedPrefShowPaneButtons  = 'Editor/show_pane_buttons';
  LedPrefLockPanes        = 'Editor/lock_pane_layout';
  LedPrefRecoveryEnabled  = 'Editor/recovery_enabled';
  LedPrefRecoveryInterval = 'Editor/recovery_interval';

implementation

var
  FInstance: TLedPrefs = nil;

function LedPrefs: TLedPrefs;
begin
  if FInstance = nil then
  begin
    FInstance := TLedPrefs.Create;
    FInstance.Load;
  end;
  Result := FInstance;
end;

constructor TLedPrefs.Create(const AFileName: string);
begin
  inherited Create;
  if AFileName <> '' then
    FFileName := AFileName
  else
    FFileName := LedConfigFile('prefs.ini');
  FIni := TMemIniFile.Create('');
end;

destructor TLedPrefs.Destroy;
begin
  FIni.Free;
  inherited Destroy;
end;

{ "Plugins/Terminal/font" -> section "Plugins.Terminal", name "font".
  Only the last component is the key; everything before it is the section,
  which keeps deeply namespaced plugin keys readable in the file. }
procedure TLedPrefs.Split(const AKey: string; out ASection, AName: string);
var
  P: Integer;
begin
  P := LastDelimiter('/', AKey);
  if P = 0 then
  begin
    ASection := 'General';
    AName := AKey;
  end
  else
  begin
    ASection := StringReplace(Copy(AKey, 1, P - 1), '/', '.', [rfReplaceAll]);
    AName := Copy(AKey, P + 1, MaxInt);
  end;
end;

function TLedPrefs.GetStr(const AKey, ADefault: string): string;
var
  S, N: string;
begin
  Split(AKey, S, N);
  Result := FIni.ReadString(S, N, ADefault);
end;

function TLedPrefs.GetInt(const AKey: string; ADefault: Int64): Int64;
var
  S, N, V: string;
begin
  Split(AKey, S, N);
  V := FIni.ReadString(S, N, '');
  if not TryStrToInt64(Trim(V), Result) then
    Result := ADefault;
end;

function TLedPrefs.GetBool(const AKey: string; ADefault: Boolean): Boolean;
var
  S, N, V: string;
begin
  Split(AKey, S, N);
  V := FIni.ReadString(S, N, '');
  if not LedParseBool(V, Result) then
    Result := ADefault;
end;

procedure TLedPrefs.SetStr(const AKey, AValue: string);
var
  S, N: string;
begin
  Split(AKey, S, N);
  FIni.WriteString(S, N, AValue);
  FDirty := True;
end;

procedure TLedPrefs.SetInt(const AKey: string; AValue: Int64);
begin
  SetStr(AKey, IntToStr(AValue));
end;

procedure TLedPrefs.SetBool(const AKey: string; AValue: Boolean);
begin
  if AValue then SetStr(AKey, '1') else SetStr(AKey, '0');
end;

function TLedPrefs.HasKey(const AKey: string): Boolean;
var
  S, N: string;
begin
  Split(AKey, S, N);
  Result := FIni.ValueExists(S, N);
end;

procedure TLedPrefs.Remove(const AKey: string);
var
  S, N: string;
begin
  Split(AKey, S, N);
  FIni.DeleteKey(S, N);
  FDirty := True;
end;

procedure TLedPrefs.Load;
var
  L: TStringList;
begin
  FIni.Clear;
  if not FileExists(FFileName) then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(FFileName);
    FIni.SetStrings(L);
  finally
    L.Free;
  end;
  FDirty := False;
end;

procedure TLedPrefs.Save;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    FIni.GetStrings(L);
    LedWriteFileAtomic(FFileName, L.Text);
  finally
    L.Free;
  end;
  FDirty := False;
end;

procedure TLedPrefs.ApplyToConfig(AConfig: TLedDocConfig);
begin
  AConfig.SetInt(LedSetTabWidth, GetInt(LedPrefTabWidth, 8), lcsUser);
  AConfig.SetInt(LedSetIndentWidth, GetInt(LedPrefIndentWidth, 4), lcsUser);
  { The preference is phrased as "spaces instead of tabs"; the setting is
    phrased as "use tabs".  Invert once, here, rather than at every use. }
  AConfig.SetBool(LedSetIndentUseTabs,
    not GetBool(LedPrefSpacesNotTabs, False), lcsUser);
  AConfig.SetBool(LedSetStripTrailing, GetBool(LedPrefStripTrailing, False), lcsUser);
  AConfig.SetBool(LedSetAddNewline, GetBool(LedPrefAddNewline, True), lcsUser);
  AConfig.SetBool(LedSetShowLineNumbers,
    GetBool(LedPrefShowLineNumbers, True), lcsUser);
  if GetBool(LedPrefWrapEnable, False) then
    AConfig.SetStr(LedSetWrapMode, 'word', lcsUser)
  else
    AConfig.SetStr(LedSetWrapMode, 'none', lcsUser);
end;

finalization
  FInstance.Free;

end.
