{ led - a light editor.  Modeline parsing.

  medit reads three dialects, from the first, second and last line of the
  document (mooedit.cpp:1188 update_config_from_mode_lines):

    kate:  "kate: space-indent on; indent-width 4;"     name value, ';'
    emacs: "-*- mode: python; tab-width: 4 -*-"          name: value, ';'
           "-*- python -*-"                              bare language name
    led:   "-%- lang: c; indent-width = 2 -%-"           name: value or name=value

  Ported here as pure string handling so it can be tested without a document.
  No LCL dependency. }
unit Led.Core.Modeline;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Led.Core.Types, Led.Core.Config;

type
  { Asked whether a bare word in an emacs modeline names a language, so
    "-*- python -*-" can be told apart from a malformed variable list. }
  TLedIsLanguageFunc = function(const AName: string): Boolean of object;

{ Applies any modeline found in ALine to AConfig at source lcsFile. }
procedure LedApplyModeline(const ALine: string; AConfig: TLedDocConfig;
  AIsLanguage: TLedIsLanguageFunc = nil);

{ Applies the modelines of a whole document, looking at the first, second and
  last lines -- the same three medit looks at. }
procedure LedApplyModelines(ALines: TStrings; AConfig: TLedDocConfig;
  AIsLanguage: TLedIsLanguageFunc = nil);

const
  LedKateMarker  = 'kate:';
  LedEmacsMarker = '-*-';
  LedOwnMarker   = '-%-';

implementation

{ kate writes "name value", space-separated, entries divided by ';'. }
procedure ApplyKate(const ABody: string; AConfig: TLedDocConfig);
var
  Entries: TStringArray;
  i, SpacePos: Integer;
  Entry, Name, Value: string;
  B: Boolean;
begin
  Entries := ABody.Split([';']);
  for i := 0 to High(Entries) do
  begin
    Entry := Trim(Entries[i]);
    SpacePos := Pos(' ', Entry);
    if SpacePos <= 1 then Continue;
    Name := Trim(Copy(Entry, 1, SpacePos - 1));
    Value := Trim(Copy(Entry, SpacePos + 1, MaxInt));
    if (Name = '') or (Value = '') then Continue;

    { kate states the inverse of what led stores. }
    if SameText(Name, 'space-indent') then
    begin
      if LedParseBool(Value, B) then
        AConfig.SetBool(LedSetIndentUseTabs, not B, lcsFile);
    end
    else
      AConfig.SetFromString(Name, Value, lcsFile);
  end;
end;

procedure ApplyEmacs(const ABody: string; AConfig: TLedDocConfig;
  AIsLanguage: TLedIsLanguageFunc);
var
  Body: string;
  Entries: TStringArray;
  i, SepPos: Integer;
  Entry, Name, Value: string;
  B: Boolean;
begin
  Body := Trim(ABody);
  if Body = '' then Exit;

  { "-*- python -*-" names a language outright. }
  if (Pos(':', Body) = 0) and (Pos(';', Body) = 0) then
  begin
    if (not Assigned(AIsLanguage)) or AIsLanguage(Body) then
      AConfig.SetStr(LedSetLang, LowerCase(Body), lcsFile);
    Exit;
  end;

  Entries := Body.Split([';']);
  for i := 0 to High(Entries) do
  begin
    Entry := Trim(Entries[i]);
    SepPos := Pos(':', Entry);
    if SepPos <= 1 then Continue;
    Name := Trim(Copy(Entry, 1, SepPos - 1));
    Value := Trim(Copy(Entry, SepPos + 1, MaxInt));
    if (Name = '') or (Value = '') then Continue;

    { emacs spells this one backwards relative to its name: nil means spaces. }
    if SameText(Name, 'indent-tabs-mode') then
    begin
      B := not SameText(Trim(Value), 'nil');
      AConfig.SetBool(LedSetIndentUseTabs, B, lcsFile);
    end
    else
      AConfig.SetFromString(Name, Value, lcsFile);
  end;
end;

{ Returns the text between the first and second occurrence of AMarker, or ''
  when the line does not carry a complete pair. }
function Between(const ALine, AMarker: string; out ABody: string): Boolean;
var
  StartPos, EndPos: Integer;
begin
  ABody := '';
  StartPos := Pos(AMarker, ALine);
  if StartPos = 0 then Exit(False);
  Inc(StartPos, Length(AMarker));
  EndPos := PosEx(AMarker, ALine, StartPos);
  if EndPos <= StartPos then Exit(False);
  ABody := Copy(ALine, StartPos, EndPos - StartPos);
  Result := True;
end;

procedure LedApplyModeline(const ALine: string; AConfig: TLedDocConfig;
  AIsLanguage: TLedIsLanguageFunc);
var
  P: Integer;
  Body: string;
begin
  if ALine = '' then Exit;

  { kate's marker opens but does not close, so it runs to end of line. }
  P := Pos(LedKateMarker, ALine);
  if P > 0 then
  begin
    ApplyKate(Copy(ALine, P + Length(LedKateMarker), MaxInt), AConfig);
    Exit;
  end;

  if Between(ALine, LedEmacsMarker, Body) then
  begin
    ApplyEmacs(Body, AConfig, AIsLanguage);
    Exit;
  end;

  if Between(ALine, LedOwnMarker, Body) then
    AConfig.ParseString(Body, lcsFile);
end;

procedure LedApplyModelines(ALines: TStrings; AConfig: TLedDocConfig;
  AIsLanguage: TLedIsLanguageFunc);
var
  Last: Integer;
begin
  if (ALines = nil) or (ALines.Count = 0) then Exit;

  LedApplyModeline(ALines[0], AConfig, AIsLanguage);
  if ALines.Count > 1 then
    LedApplyModeline(ALines[1], AConfig, AIsLanguage);

  { The last line too -- but not when it is one of the two already read. }
  Last := ALines.Count - 1;
  if Last > 1 then
    LedApplyModeline(ALines[Last], AConfig, AIsLanguage);
end;

end.
