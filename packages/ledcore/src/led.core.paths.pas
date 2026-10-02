{ LED - a lightweight editor.  Where things live on disk.

  Config is per-user and writable; data is installed alongside the binary and
  read-only.  Both are resolved once and can be overridden by environment
  variables, which is what makes running from a build tree work without
  installing anything.

  No LCL dependency. }
unit Led.Core.Paths;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  LedConfigDirEnv = 'LED_CONFIG_DIR';
  LedDataDirEnv   = 'LED_DATA_DIR';

{ Which application these paths belong to: 'led' here, 'mima' in the fork.

  One binary's settings must not be another's.  The fork adds a command
  window, a workspace browser and a docked layout of its own, and LED knows
  nothing about any of them -- so a shared prefs.ini would have each writing
  keys the other drops on its next save, and a shared layout would restore
  panes that do not exist.  Both are installed on the same machine here, and
  a user running one should not find the other rearranged.

  Set once, before anything reads a path, because LedConfigDir resolves its
  answer on first use and caches it.  The environment variable that overrides
  it is derived from the same name, so the fork reads MIMA_CONFIG_DIR and LED
  reads LED_CONFIG_DIR without either having to know about the other. }
function LedAppId: string;
procedure LedSetAppId(const AId: string);

{ The environment variable that overrides LedConfigDir, named after the app:
  LED_CONFIG_DIR here, MIMA_CONFIG_DIR in the fork. }
function LedConfigDirEnvName: string;

{ ~/.config/<appid>, %APPDATA%\<appid>,
  ~/Library/Application Support/<appid>.  Created on first use. }
function LedConfigDir: string;
function LedConfigFile(const AName: string): string;

{ Where grammars, themes and default tools live.  Search order: $LED_DATA_DIR,
  then <exedir>/data (a build tree or a portable install), then the platform
  install prefix. }
function LedDataDir: string;
function LedDataFile(const AName: string): string;

{ Points the configuration at ADirectory for the rest of the process.  Only
  the self-test uses this, so it can run against a known-empty configuration
  rather than against whatever the person running it happens to prefer. }
procedure LedForceConfigDir(const ADirectory: string);

{ Writes AContent to APath without leaving a truncated file behind if the
  machine dies mid-write, keeping one generation of backup.  Used for every
  file LED rewrites on a timer or at exit. }
procedure LedWriteFileAtomic(const APath, AContent: string);

implementation

var
  FConfigDir: string = '';
  FDataDir: string = '';
  FAppId: string = 'led';

function LedAppId: string;
begin
  Result := FAppId;
end;

procedure LedSetAppId(const AId: string);
begin
  if AId <> '' then
    FAppId := AId;
end;

function LedConfigDirEnvName: string;
begin
  Result := UpperCase(FAppId) + '_CONFIG_DIR';
end;

procedure LedForceConfigDir(const ADirectory: string);
begin
  FConfigDir := IncludeTrailingPathDelimiter(ADirectory);
end;

function LedConfigDir: string;
var
  Base: string;
begin
  if FConfigDir <> '' then Exit(FConfigDir);

  { UpperCase of the app id, so 'mima' reads MIMA_CONFIG_DIR: one rule rather
    than a constant per application, and a fork that forgets to add one still
    gets a variable of its own rather than LED's. }
  Base := GetEnvironmentVariable(LedConfigDirEnvName);
  if Base = '' then
  begin
    {$IFDEF WINDOWS}
    Base := IncludeTrailingPathDelimiter(GetEnvironmentVariable('APPDATA')) + FAppId;
    {$ELSE}
      {$IFDEF DARWIN}
      Base := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) +
        'Library/Application Support/' + FAppId;
      {$ELSE}
      Base := GetEnvironmentVariable('XDG_CONFIG_HOME');
      if Base = '' then
        Base := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + '.config';
      Base := IncludeTrailingPathDelimiter(Base) + FAppId;
      {$ENDIF}
    {$ENDIF}
  end;

  FConfigDir := IncludeTrailingPathDelimiter(Base);
  ForceDirectories(FConfigDir);
  Result := FConfigDir;
end;

function LedConfigFile(const AName: string): string;
begin
  Result := LedConfigDir + AName;
end;

function LedDataDir: string;
var
  Candidate: string;
begin
  if FDataDir <> '' then Exit(FDataDir);

  Candidate := GetEnvironmentVariable(LedDataDirEnv);
  if (Candidate <> '') and DirectoryExists(Candidate) then
    FDataDir := IncludeTrailingPathDelimiter(Candidate)
  else
  begin
    {$IFDEF DARWIN}
    { Inside an application bundle the executable is at
      led.app/Contents/MacOS/led and everything it ships with belongs in
      Contents/Resources.  Checked first, because the generic rule below
      would otherwise resolve to Contents/data. }
    Candidate := IncludeTrailingPathDelimiter(
      ExtractFilePath(ExpandFileName(ParamStr(0)))) +
      '..' + PathDelim + 'Resources' + PathDelim + 'data';
    if DirectoryExists(Candidate) then
    begin
      FDataDir := IncludeTrailingPathDelimiter(ExpandFileName(Candidate));
      Exit(FDataDir);
    end;
    {$ENDIF}

    { A build tree keeps data/ one level up from bin/. }
    Candidate := IncludeTrailingPathDelimiter(
      ExtractFilePath(ExpandFileName(ParamStr(0)))) + '..' + PathDelim + 'data';
    if DirectoryExists(Candidate) then
      FDataDir := IncludeTrailingPathDelimiter(ExpandFileName(Candidate))
    else
    begin
      {$IFDEF WINDOWS}
      FDataDir := IncludeTrailingPathDelimiter(
        ExtractFilePath(ExpandFileName(ParamStr(0)))) + 'data' + PathDelim;
      {$ELSE}
      { An install puts the data under <prefix>/share/led, which is one level
        up from <prefix>/bin.  Checked before the system prefix so a local
        install is found without setting anything. }
      Candidate := IncludeTrailingPathDelimiter(
        ExtractFilePath(ExpandFileName(ParamStr(0)))) +
        '..' + PathDelim + 'share' + PathDelim + 'led';
      if DirectoryExists(Candidate) then
        FDataDir := IncludeTrailingPathDelimiter(ExpandFileName(Candidate))
      else
        FDataDir := '/usr/share/led/';
      {$ENDIF}
    end;
  end;
  Result := FDataDir;
end;

function LedDataFile(const AName: string): string;
begin
  Result := LedDataDir + AName;
end;

procedure LedWriteFileAtomic(const APath, AContent: string);
var
  Tmp: string;
  Stream: TFileStream;
begin
  Tmp := APath + '.tmp';
  Stream := TFileStream.Create(Tmp, fmCreate);
  try
    if AContent <> '' then
      Stream.WriteBuffer(AContent[1], Length(AContent));
  finally
    Stream.Free;
  end;

  if FileExists(APath) then
  begin
    DeleteFile(APath + '.bak');
    RenameFile(APath, APath + '.bak');
  end;
  if not RenameFile(Tmp, APath) then
  begin
    { Rename can fail across filesystems; fall back to a plain rewrite rather
      than losing the content that was just produced. }
    Stream := TFileStream.Create(APath, fmCreate);
    try
      if AContent <> '' then
        Stream.WriteBuffer(AContent[1], Length(AContent));
    finally
      Stream.Free;
    end;
    DeleteFile(Tmp);
  end;
end;

end.
