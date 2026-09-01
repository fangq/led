{ led - a light editor.  Colour themes.

  Reads GtkSourceView <style-scheme> files unchanged, which is what lets the
  eight schemes medit ships carry over intact.  A scheme is a flat map from a
  style name to a set of attributes:

      <color name="aluminium4" value="#888a85"/>
      <style name="def:comment" foreground="aluminium4" italic="true"/>
      <style name="current-line" background="#2e3436"/>
      <style name="def:complex" use-style="def:base-n-integer"/>

  Two kinds of name appear: editor chrome (text, selection, cursor,
  current-line, line-numbers, bracket-match, right-margin, search-match) and
  syntax styles, which are the 35 shared "def:" names from def.lang plus
  language-specific ones like "c:preprocessor".

  Lookup is longest-dotted-prefix, so a request for "comment.line.double-slash"
  finds a rule written as "comment".  That costs nothing now and is what will
  let real TextMate scope names work when grammar-driven highlighting arrives.

  Colours are stored as plain RGB longs rather than TColor so this unit stays
  free of any LCL dependency and can be tested headlessly. }
unit Led.Syn.Theme;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Laz2_DOM, Laz2_XMLRead;

const
  LedNoColour = -1;

type
  TLedColour = LongInt;         // $00RRGGBB, or LedNoColour

  TLedStyleFlag = (lsfForeground, lsfBackground, lsfBold, lsfItalic,
                   lsfUnderline, lsfStrikeOut);
  TLedStyleFlags = set of TLedStyleFlag;

  TLedStyle = record
    Flags: TLedStyleFlags;      // which of the below were actually stated
    Foreground: TLedColour;
    Background: TLedColour;
    Bold, Italic, Underline, StrikeOut: Boolean;
  end;
  PLedStyle = ^TLedStyle;

  TLedTheme = class
  private
    FId: string;
    FName: string;
    FColours: TStringList;      // named palette entry -> '#rrggbb'
    FStyles: TStringList;       // style name -> ^TLedStyle
    FAliases: TStringList;      // style name -> style name (use-style)
    procedure ParseStyle(ANode: TDOMElement);
    function ResolveColour(const AValue: string): TLedColour;
  public
    constructor Create;
    destructor Destroy; override;

    function LoadFromFile(const AFileName: string): Boolean;

    { Looks up AName, following use-style aliases and falling back to
      successively shorter dotted prefixes.  Returns False when the theme
      says nothing about it, so the caller can leave the default alone. }
    function Find(const AName: string; out AStyle: TLedStyle): Boolean;
    function Has(const AName: string): Boolean;

    property Id: string read FId;
    property Name: string read FName;
  end;

  TLedThemeRegistry = class
  private
    FItems: TStringList;        // id -> TLedTheme, owns them
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TLedTheme;
  public
    constructor Create;
    destructor Destroy; override;
    function ScanDirectory(const ADirectory: string): Integer;
    function FindById(const AId: string): TLedTheme;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TLedTheme read GetItem; default;
  end;

{ Editor chrome style names, spelled as the scheme files spell them. }
const
  LedStyleText         = 'text';
  LedStyleSelection    = 'selection';
  LedStyleCursor       = 'cursor';
  LedStyleCurrentLine  = 'current-line';
  LedStyleLineNumbers  = 'line-numbers';
  LedStyleBracketMatch = 'bracket-match';
  LedStyleBracketBad   = 'bracket-mismatch';
  LedStyleRightMargin  = 'right-margin';
  LedStyleSearchMatch  = 'search-match';
  LedStyleDrawSpaces   = 'draw-spaces';

function LedParseColour(const AValue: string): TLedColour;

{ The process-wide theme list, populated from the data directory. }
function LedThemes: TLedThemeRegistry;

implementation

uses
  Led.Core.Paths;

function LedParseColour(const AValue: string): TLedColour;
var
  S: string;
  V: Int64;
begin
  Result := LedNoColour;
  S := Trim(AValue);
  if (S = '') or (S[1] <> '#') then Exit;
  Delete(S, 1, 1);
  { #rgb is legal shorthand and does turn up. }
  if Length(S) = 3 then
    S := S[1] + S[1] + S[2] + S[2] + S[3] + S[3];
  if Length(S) <> 6 then Exit;
  if not TryStrToInt64('$' + S, V) then Exit;
  Result := LongInt(V);
end;

function ParseBool(const AValue: string): Boolean;
begin
  Result := SameText(Trim(AValue), 'true') or (Trim(AValue) = '1');
end;

{ TLedTheme }

constructor TLedTheme.Create;
begin
  inherited Create;
  FColours := TStringList.Create;
  FColours.CaseSensitive := False;
  FColours.Sorted := True;
  FColours.Duplicates := dupIgnore;

  FStyles := TStringList.Create;
  FStyles.CaseSensitive := False;
  FStyles.Sorted := True;
  FStyles.Duplicates := dupIgnore;
  FStyles.OwnsObjects := False;

  FAliases := TStringList.Create;
  FAliases.CaseSensitive := False;
  FAliases.Sorted := True;
  FAliases.Duplicates := dupIgnore;
end;

destructor TLedTheme.Destroy;
var
  i: Integer;
  P: PLedStyle;
begin
  for i := 0 to FStyles.Count - 1 do
  begin
    P := PLedStyle(FStyles.Objects[i]);
    Dispose(P);
  end;
  FStyles.Free;
  FColours.Free;
  FAliases.Free;
  inherited Destroy;
end;

function TLedTheme.ResolveColour(const AValue: string): TLedColour;
var
  i: Integer;
begin
  if AValue = '' then Exit(LedNoColour);
  if AValue[1] = '#' then Exit(LedParseColour(AValue));
  { Otherwise it names a palette entry declared earlier in the file.  Note
    IndexOfName, not IndexOf: the list holds "name=value" lines. }
  i := FColours.IndexOfName(AValue);
  if i < 0 then Exit(LedNoColour);
  Result := LedParseColour(FColours.ValueFromIndex[i]);
end;

procedure TLedTheme.ParseStyle(ANode: TDOMElement);
var
  StyleName, UseStyle, S: string;
  P: PLedStyle;
begin
  StyleName := ANode.GetAttribute('name');
  if StyleName = '' then Exit;

  UseStyle := ANode.GetAttribute('use-style');
  if UseStyle <> '' then
  begin
    FAliases.Values[StyleName] := UseStyle;
    Exit;
  end;

  New(P);
  FillChar(P^, SizeOf(P^), 0);
  P^.Foreground := LedNoColour;
  P^.Background := LedNoColour;

  S := ANode.GetAttribute('foreground');
  if S <> '' then
  begin
    P^.Foreground := ResolveColour(S);
    if P^.Foreground <> LedNoColour then Include(P^.Flags, lsfForeground);
  end;

  S := ANode.GetAttribute('background');
  if S <> '' then
  begin
    P^.Background := ResolveColour(S);
    if P^.Background <> LedNoColour then Include(P^.Flags, lsfBackground);
  end;

  S := ANode.GetAttribute('bold');
  if S <> '' then
  begin
    P^.Bold := ParseBool(S);
    Include(P^.Flags, lsfBold);
  end;

  S := ANode.GetAttribute('italic');
  if S <> '' then
  begin
    P^.Italic := ParseBool(S);
    Include(P^.Flags, lsfItalic);
  end;

  S := ANode.GetAttribute('underline');
  if S <> '' then
  begin
    { GtkSourceView 3 allows "single"/"double"/"none" here as well as a
      boolean; anything that is not a negative counts as underlined. }
    P^.Underline := not (SameText(S, 'false') or SameText(S, 'none') or (S = '0'));
    Include(P^.Flags, lsfUnderline);
  end;

  S := ANode.GetAttribute('strikethrough');
  if S <> '' then
  begin
    P^.StrikeOut := ParseBool(S);
    Include(P^.Flags, lsfStrikeOut);
  end;

  FStyles.AddObject(StyleName, TObject(P));
end;

function TLedTheme.LoadFromFile(const AFileName: string): Boolean;
var
  Doc: TXMLDocument;
  Root, Node: TDOMNode;
  Elem: TDOMElement;
begin
  Result := False;
  Doc := nil;
  try
    try
      ReadXMLFile(Doc, AFileName);
    except
      Exit;
    end;
    if Doc = nil then Exit;
    Root := Doc.DocumentElement;
    if (Root = nil) or (Root.NodeName <> 'style-scheme') then Exit;

    FId := TDOMElement(Root).GetAttribute('id');
    FName := TDOMElement(Root).GetAttribute('_name');
    if FName = '' then FName := TDOMElement(Root).GetAttribute('name');
    if FName = '' then FName := FId;
    if FId = '' then Exit;

    { Colours are declared before the styles that use them, so one pass in
      document order is enough. }
    Node := Root.FirstChild;
    while Node <> nil do
    begin
      if Node.NodeType = ELEMENT_NODE then
      begin
        Elem := TDOMElement(Node);
        if Elem.NodeName = 'color' then
          FColours.Values[Elem.GetAttribute('name')] := Elem.GetAttribute('value')
        else if Elem.NodeName = 'style' then
          ParseStyle(Elem);
      end;
      Node := Node.NextSibling;
    end;

    Result := True;
  finally
    Doc.Free;
  end;
end;

function TLedTheme.Find(const AName: string; out AStyle: TLedStyle): Boolean;
var
  Probe, Alias: string;
  i, Dot, Guard: Integer;
begin
  Result := False;
  FillChar(AStyle, SizeOf(AStyle), 0);
  AStyle.Foreground := LedNoColour;
  AStyle.Background := LedNoColour;

  Probe := AName;
  Guard := 0;
  while Probe <> '' do
  begin
    { Follow use-style, with a guard so a scheme that aliases in a circle
      cannot hang the editor. }
    Alias := FAliases.Values[Probe];
    Inc(Guard);
    if (Alias <> '') and (Guard < 16) then
    begin
      Probe := Alias;
      Continue;
    end;

    i := FStyles.IndexOf(Probe);
    if i >= 0 then
    begin
      AStyle := PLedStyle(FStyles.Objects[i])^;
      Exit(True);
    end;

    { Shorten by one dotted component and try again. }
    Dot := LastDelimiter('.', Probe);
    if Dot = 0 then Break;
    Probe := Copy(Probe, 1, Dot - 1);
  end;
end;

function TLedTheme.Has(const AName: string): Boolean;
var
  Dummy: TLedStyle;
begin
  Result := Find(AName, Dummy);
end;

{ TLedThemeRegistry }

constructor TLedThemeRegistry.Create;
begin
  inherited Create;
  FItems := TStringList.Create;
  FItems.OwnsObjects := True;
  FItems.CaseSensitive := False;
  FItems.Sorted := True;
  FItems.Duplicates := dupIgnore;
end;

destructor TLedThemeRegistry.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TLedThemeRegistry.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TLedThemeRegistry.GetItem(AIndex: Integer): TLedTheme;
begin
  Result := TLedTheme(FItems.Objects[AIndex]);
end;

function TLedThemeRegistry.FindById(const AId: string): TLedTheme;
var
  i: Integer;
begin
  i := FItems.IndexOf(AId);
  if i < 0 then Result := nil else Result := TLedTheme(FItems.Objects[i]);
end;

function TLedThemeRegistry.ScanDirectory(const ADirectory: string): Integer;
var
  Search: TSearchRec;
  Dir: string;
  Theme: TLedTheme;
begin
  Result := 0;
  Dir := IncludeTrailingPathDelimiter(ADirectory);
  if not DirectoryExists(Dir) then Exit;

  if FindFirst(Dir + '*.xml', faAnyFile, Search) <> 0 then Exit;
  try
    repeat
      if (Search.Attr and faDirectory) <> 0 then Continue;
      Theme := TLedTheme.Create;
      if Theme.LoadFromFile(Dir + Search.Name) and
         (FItems.IndexOf(Theme.Id) < 0) then
      begin
        FItems.AddObject(Theme.Id, Theme);
        Inc(Result);
      end
      else
        Theme.Free;
    until FindNext(Search) <> 0;
  finally
    FindClose(Search);
  end;
end;

var
  FThemes: TLedThemeRegistry = nil;

function LedThemes: TLedThemeRegistry;
begin
  if FThemes = nil then
  begin
    FThemes := TLedThemeRegistry.Create;
    FThemes.ScanDirectory(LedConfigFile('themes'));
    FThemes.ScanDirectory(LedDataFile('themes'));
  end;
  Result := FThemes;
end;

finalization
  FThemes.Free;

end.
