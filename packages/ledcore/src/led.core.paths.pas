{ led - a light editor.  Where things live on disk.

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

{ ~/.config/led, %APPDATA%\led, ~/Library/Application Support/led.
  Created on first use. }
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
  file led rewrites on a timer or at exit. }
procedure LedWriteFileAtomic(const APath, AContent: string);

implementation

var
  FConfigDir: string = '';
  FDataDir: string = '';

procedure LedForceConfigDir(const ADirectory: string);
begin
  FConfigDir := IncludeTrailingPathDelimiter(ADirectory);
end;

function LedConfigDir: string;
var
  Base: string;
begin
  if FConfigDir <> '' then Exit(FConfigDir);

  Base := GetEnvironmentVariable(LedConfigDirEnv);
  if Base = '' then
  begin
    {$IFDEF WINDOWS}
    Base := IncludeTrailingPathDelimiter(GetEnvironmentVariable('APPDATA')) + 'led';
    {$ELSE}
      {$IFDEF DARWIN}
      Base := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) +
        'Library/Application Support/led';
      {$ELSE}
      Base := GetEnvironmentVariable('XDG_CONFIG_HOME');
      if Base = '' then
        Base := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + '.config';
      Base := IncludeTrailingPathDelimiter(Base) + 'led';
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
