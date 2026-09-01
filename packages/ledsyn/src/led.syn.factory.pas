{ led - a light editor.  Highlighter selection and theming.

  Two jobs, kept together because they share one table:

    * pick a SynEdit highlighter for a language id;
    * colour it, and the editor chrome around it, from a theme.

  The bridge between the two is a scope name.  medit's grammars and themes
  speak a shared vocabulary of 35 "def:" style names -- def:comment,
  def:string, def:keyword and so on -- and every grammar maps its local
  styles onto them.  SynEdit's highlighters instead label their attributes
  with human-readable stored names, 'Comment', 'Reserved word', 'Number'.
  So one table maps those stored names onto def: scopes, and from then on a
  single theme drives every highlighter.

  That table is also what will let grammar-driven highlighting drop in later
  without touching the themes: a TextMate grammar already carries scope names,
  so it can skip the table entirely and look its scopes up directly. }
unit Led.Syn.Factory;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, SynEdit, SynEditHighlighter,
  Led.Syn.Theme, Led.Syn.Languages;

{ A shared highlighter for ALangId, or nil when nothing suitable exists.
  Instances are cached and shared between documents, which is safe because a
  highlighter holds no per-document state.

  A bundled SynEdit highlighter is preferred where there is one: it is a
  hand-written scanner and faster than any regex engine.  Otherwise a
  converted grammar is loaded, which covers the rest of the 128. }
function LedHighlighterFor(const ALangId: string): TSynCustomHighlighter;

{ True when led can highlight this language today. }
function LedHasHighlighter(const ALangId: string): Boolean;

{ Where the converted grammar for a language would be, whether or not it
  exists. }
function LedGrammarFile(const ALangId: string): string;

{ Colours AHighlighter's attributes from ATheme. }
procedure LedApplyThemeToHighlighter(ATheme: TLedTheme;
  AHighlighter: TSynCustomHighlighter);

{ Colours the editor itself -- background, selection, caret line, gutter,
  right margin, bracket match. }
procedure LedApplyThemeToEditor(ATheme: TLedTheme; AEdit: TSynEdit);

{ Re-themes every cached highlighter; call after the theme changes. }
procedure LedRetheme(ATheme: TLedTheme);

function LedColourToTColor(AColour: TLedColour): TColor;

implementation

uses
  SynTextMateSyn, Led.Core.Paths,
  SynHighlighterPas, SynHighlighterCpp, SynHighlighterPython,
  SynHighlighterXML, SynHighlighterHTML, SynHighlighterCss,
  SynHighlighterJScript, SynHighlighterJava, SynHighlighterPHP,
  SynHighlighterPerl, SynHighlighterSQL, SynHighlighterUNIXShellScript,
  SynHighlighterIni, SynHighlighterDiff, SynHighlighterBat,
  SynHighlighterTeX, SynHighlighterVB, SynHighlighterPo,
  SynHighlighterLFM, SynHighlighterAny;

type
  TLangMap = record
    LangId: string;
    Cls: TSynCustomHighlighterClass;
  end;

  TScopeMap = record
    StoredName: string;
    Scope: string;
  end;

const
  { medit grammar id -> the SynEdit highlighter that comes closest.  Only the
    languages Lazarus actually ships are here; everything else waits for the
    grammar converter. }
  LangMap: array[0..27] of TLangMap = (
    (LangId: 'pascal';      Cls: TSynPasSyn),
    (LangId: 'objc';        Cls: TSynCppSyn),
    (LangId: 'c';           Cls: TSynCppSyn),
    (LangId: 'chdr';        Cls: TSynCppSyn),
    (LangId: 'cpp';         Cls: TSynCppSyn),
    (LangId: 'cpphdr';      Cls: TSynCppSyn),
    (LangId: 'cuda';        Cls: TSynCppSyn),
    (LangId: 'csharp';      Cls: TSynCppSyn),
    (LangId: 'python';      Cls: TSynPythonSyn),
    (LangId: 'python3';     Cls: TSynPythonSyn),
    (LangId: 'xml';         Cls: TSynXMLSyn),
    (LangId: 'xslt';        Cls: TSynXMLSyn),
    (LangId: 'docbook';     Cls: TSynXMLSyn),
    (LangId: 'html';        Cls: TSynHTMLSyn),
    (LangId: 'xhtml';       Cls: TSynHTMLSyn),
    (LangId: 'css';         Cls: TSynCssSyn),
    (LangId: 'js';          Cls: TSynJScriptSyn),
    (LangId: 'java';        Cls: TSynJavaSyn),
    (LangId: 'php';         Cls: TSynPHPSyn),
    (LangId: 'perl';        Cls: TSynPerlSyn),
    (LangId: 'sql';         Cls: TSynSQLSyn),
    (LangId: 'sh';          Cls: TSynUNIXShellScriptSyn),
    (LangId: 'ini';         Cls: TSynIniSyn),
    (LangId: 'diff';        Cls: TSynDiffSyn),
    (LangId: 'dosbatch';    Cls: TSynBatSyn),
    (LangId: 'latex';       Cls: TSynTeXSyn),
    (LangId: 'gettext-translation'; Cls: TSynPoSyn),
    (LangId: 'lfm';         Cls: TSynLFMSyn)
  );

  { SynEdit attribute stored name -> the shared def: scope a theme colours.
    Names come from syneditstrconst.pp; anything not listed falls through to
    the theme's own longest-prefix lookup, which usually still finds
    something sensible. }
  ScopeMap: array[0..29] of TScopeMap = (
    (StoredName: 'Comment';           Scope: 'def:comment'),
    (StoredName: 'Documentation';     Scope: 'def:doc-comment'),
    (StoredName: 'String';            Scope: 'def:string'),
    (StoredName: 'Character';         Scope: 'def:character'),
    (StoredName: 'Number';            Scope: 'def:decimal'),
    (StoredName: 'Float';             Scope: 'def:floating-point'),
    (StoredName: 'Hexadecimal';       Scope: 'def:base-n-integer'),
    (StoredName: 'Octal';             Scope: 'def:base-n-integer'),
    (StoredName: 'Reserved word';     Scope: 'def:keyword'),
    (StoredName: 'Key';               Scope: 'def:keyword'),
    (StoredName: 'Keyword';           Scope: 'def:keyword'),
    (StoredName: 'Data type';         Scope: 'def:type'),
    (StoredName: 'Directive';         Scope: 'def:preprocessor'),
    (StoredName: 'Preprocessor';      Scope: 'def:preprocessor'),
    (StoredName: 'Assembler';         Scope: 'def:preprocessor'),
    (StoredName: 'Identifier';        Scope: 'def:identifier'),
    (StoredName: 'Function';          Scope: 'def:function'),
    (StoredName: 'Internal function'; Scope: 'def:builtin'),
    (StoredName: 'Variable';          Scope: 'def:identifier'),
    (StoredName: 'Symbol';            Scope: 'def:operator'),
    (StoredName: 'Brackets';          Scope: 'def:operator'),
    (StoredName: 'Illegal char';      Scope: 'def:error'),
    (StoredName: 'Invalid symbol';    Scope: 'def:error'),
    (StoredName: 'Unknown word';      Scope: 'def:error'),
    (StoredName: 'Section';           Scope: 'def:statement'),
    (StoredName: 'Attribute Name';    Scope: 'def:identifier'),
    (StoredName: 'Attribute Value';   Scope: 'def:string'),
    (StoredName: 'Element Name';      Scope: 'def:keyword'),
    (StoredName: 'Entity Reference';  Scope: 'def:special-char'),
    (StoredName: 'Escape ampersand';  Scope: 'def:special-char')
  );

var
  FCache: TStringList = nil;    // lang id -> highlighter, owns the objects

function LedColourToTColor(AColour: TLedColour): TColor;
begin
  { The theme stores $00RRGGBB; TColor wants $00BBGGRR. }
  if AColour = LedNoColour then
    Exit(clNone);
  Result := TColor(((AColour and $FF) shl 16) or (AColour and $FF00) or
    ((AColour shr 16) and $FF));
end;

function ClassFor(const ALangId: string): TSynCustomHighlighterClass;
var
  i: Integer;
begin
  for i := Low(LangMap) to High(LangMap) do
    if SameText(LangMap[i].LangId, ALangId) then
      Exit(LangMap[i].Cls);
  Result := nil;
end;

function LedGrammarFile(const ALangId: string): string;
begin
  Result := LedDataDir + 'grammars' + PathDelim + ALangId + '.tmLanguage.json';
end;

function LedHasHighlighter(const ALangId: string): Boolean;
begin
  Result := (ClassFor(ALangId) <> nil) or FileExists(LedGrammarFile(ALangId));
end;

function Cache: TStringList;
begin
  if FCache = nil then
  begin
    FCache := TStringList.Create;
    FCache.CaseSensitive := False;
    FCache.Sorted := True;
    FCache.OwnsObjects := True;
  end;
  Result := FCache;
end;

function LedHighlighterFor(const ALangId: string): TSynCustomHighlighter;
var
  Cls: TSynCustomHighlighterClass;
  i: Integer;
  Grammar: string;
  TM: TSynTextMateSyn;
begin
  Result := nil;
  if ALangId = '' then Exit;

  i := Cache.IndexOf(ALangId);
  if i >= 0 then
    Exit(TSynCustomHighlighter(Cache.Objects[i]));

  Cls := ClassFor(ALangId);
  if Cls <> nil then
  begin
    Result := Cls.Create(nil);
    Cache.AddObject(ALangId, Result);
    Exit;
  end;

  Grammar := LedGrammarFile(ALangId);
  if not FileExists(Grammar) then Exit;

  TM := TSynTextMateSyn.Create(nil);
  try
    { The first argument is a bare file name; the second is the directory
      it lives in.  Passing a full path for both concatenates them. }
    TM.LoadGrammar(ExtractFileName(Grammar), ExtractFilePath(Grammar));
    if TM.ParserError <> '' then
    begin
      { A grammar that does not compile is worse than none: it would colour
        the file wrongly and hide the fact.  Drop it silently and leave the
        document as plain text. }
      TM.Free;
      Exit;
    end;
  except
    TM.Free;
    Exit;
  end;
  Result := TM;
  Cache.AddObject(ALangId, Result);
end;

function ScopeForAttribute(const AStoredName: string): string;
var
  i: Integer;
begin
  for i := Low(ScopeMap) to High(ScopeMap) do
    if SameText(ScopeMap[i].StoredName, AStoredName) then
      Exit(ScopeMap[i].Scope);
  { Not in the table: hand the theme the lower-cased name and let its
    prefix lookup try.  Dots rather than spaces, to match scope syntax. }
  Result := 'def:' + LowerCase(StringReplace(AStoredName, ' ', '-', [rfReplaceAll]));
end;

procedure ApplyStyle(const AStyle: TLedStyle; AAttr: TSynHighlighterAttributes);
var
  St: TFontStyles;
begin
  if lsfForeground in AStyle.Flags then
    AAttr.Foreground := LedColourToTColor(AStyle.Foreground);
  if lsfBackground in AStyle.Flags then
    AAttr.Background := LedColourToTColor(AStyle.Background);

  St := AAttr.Style;
  if lsfBold in AStyle.Flags then
    if AStyle.Bold then Include(St, fsBold) else Exclude(St, fsBold);
  if lsfItalic in AStyle.Flags then
    if AStyle.Italic then Include(St, fsItalic) else Exclude(St, fsItalic);
  if lsfUnderline in AStyle.Flags then
    if AStyle.Underline then Include(St, fsUnderline) else Exclude(St, fsUnderline);
  if lsfStrikeOut in AStyle.Flags then
    if AStyle.StrikeOut then Include(St, fsStrikeOut) else Exclude(St, fsStrikeOut);
  AAttr.Style := St;
end;

procedure LedApplyThemeToHighlighter(ATheme: TLedTheme;
  AHighlighter: TSynCustomHighlighter);
var
  i: Integer;
  Attr: TSynHighlighterAttributes;
  Style: TLedStyle;
  LangScope, Scope: string;
begin
  if (ATheme = nil) or (AHighlighter = nil) then Exit;

  for i := 0 to AHighlighter.AttrCount - 1 do
  begin
    Attr := AHighlighter.Attribute[i];
    if Attr = nil then Continue;

    Scope := ScopeForAttribute(Attr.StoredName);

    { A scheme may say something specific about this language -- "c:comment"
      -- which outranks the shared def: entry. }
    LangScope := LowerCase(AHighlighter.LanguageName) + ':' +
      Copy(Scope, Pos(':', Scope) + 1, MaxInt);
    if ATheme.Find(LangScope, Style) then
      ApplyStyle(Style, Attr)
    else if ATheme.Find(Scope, Style) then
      ApplyStyle(Style, Attr);
  end;
end;

procedure LedApplyThemeToEditor(ATheme: TLedTheme; AEdit: TSynEdit);
var
  S: TLedStyle;
begin
  if (ATheme = nil) or (AEdit = nil) then Exit;

  if ATheme.Find(LedStyleText, S) then
  begin
    if lsfForeground in S.Flags then AEdit.Font.Color := LedColourToTColor(S.Foreground);
    if lsfBackground in S.Flags then AEdit.Color := LedColourToTColor(S.Background);
  end;

  if ATheme.Find(LedStyleSelection, S) then
  begin
    if lsfForeground in S.Flags then
      AEdit.SelectedColor.Foreground := LedColourToTColor(S.Foreground);
    if lsfBackground in S.Flags then
      AEdit.SelectedColor.Background := LedColourToTColor(S.Background);
  end;

  if ATheme.Find(LedStyleCurrentLine, S) and (lsfBackground in S.Flags) then
    AEdit.LineHighlightColor.Background := LedColourToTColor(S.Background);

  if ATheme.Find(LedStyleLineNumbers, S) then
  begin
    if lsfForeground in S.Flags then
      AEdit.Gutter.LineNumberPart.MarkupInfo.Foreground :=
        LedColourToTColor(S.Foreground);
    if lsfBackground in S.Flags then
    begin
      AEdit.Gutter.LineNumberPart.MarkupInfo.Background :=
        LedColourToTColor(S.Background);
      AEdit.Gutter.Color := LedColourToTColor(S.Background);
    end;
  end;

  if ATheme.Find(LedStyleBracketMatch, S) then
  begin
    if lsfForeground in S.Flags then
      AEdit.BracketMatchColor.Foreground := LedColourToTColor(S.Foreground);
    if lsfBackground in S.Flags then
      AEdit.BracketMatchColor.Background := LedColourToTColor(S.Background);
  end;

  if ATheme.Find(LedStyleRightMargin, S) and (lsfForeground in S.Flags) then
    AEdit.RightEdgeColor := LedColourToTColor(S.Foreground);
end;

procedure LedRetheme(ATheme: TLedTheme);
var
  i: Integer;
begin
  for i := 0 to Cache.Count - 1 do
    LedApplyThemeToHighlighter(ATheme,
      TSynCustomHighlighter(Cache.Objects[i]));
end;

finalization
  FCache.Free;

end.
