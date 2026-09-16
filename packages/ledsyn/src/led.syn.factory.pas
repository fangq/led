{ LED - a lightweight editor.  Highlighter selection and theming.

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
  SynEditHighlighterFoldBase, SynEditMarkupHighAll,
  Led.Syn.Theme, Led.Syn.Languages;

{ A shared highlighter for ALangId, or nil when nothing suitable exists.
  Instances are cached and shared between documents, which is safe because a
  highlighter holds no per-document state.

  A bundled SynEdit highlighter is used only when it can fold.  Most of them
  cannot -- TSynCppSyn and TSynPythonSyn descend from TSynCustomHighlighter,
  not TSynCustomFoldHighlighter -- and they cover exactly the languages people
  most want to fold.  Preferring them for their speed silently cost folding in
  C, C++, Python and JavaScript, so the rule is now: fold-capable native
  highlighter if there is one, otherwise the converted grammar, which always
  folds and always speaks the same scope vocabulary as the themes. }
function LedHighlighterFor(const ALangId: string): TSynCustomHighlighter;

{ The same, but a fresh instance that the caller owns and must free.

  For the one case where sharing is not safe: the notebook view runs a
  language highlighter over the source lines inside each cell and has to
  carry its state from one line of a cell to the next, so it keeps a note of
  where that state got to.  A shared instance would have that note
  invalidated by any other document tokenising in between. }
function LedCreateHighlighter(const ALangId: string): TSynCustomHighlighter;

{ True when LED can highlight this language today. }
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

{ The colour for the vertical guides down an open block; see the
  implementation for why this is a function and not an apply-to-control. }
function LedThemeGuideColour(ATheme: TLedTheme;
  ADefaultFg, ADefaultBg: TColor): TColor;

{ The tint behind a line whose block is folded shut, mixed from the theme's
  own text and page colours. }
function LedThemeFoldedLineColour(ATheme: TLedTheme;
  ADefaultFg, ADefaultBg: TColor): TColor;

{ The colour of the rules above and below the caret's row.

  Not the theme's current-line colour as it stands.  That colour was chosen
  to fill a whole row, where a two per cent tint is plenty; LED draws two
  one-pixel rules with it, and at that width the same tint is invisible --
  which is what "the current line marker is very faint" was.  So it is taken
  from the theme and then pushed away from the page until it can be seen.  A
  theme that says nothing about the current line gets one mixed from its
  text colour rather than nothing at all. }
function LedThemeCurrentLineColour(ATheme: TLedTheme;
  ADefaultFg, ADefaultBg: TColor): TColor;

{ Perceived brightness, and a mix of two colours: the arithmetic every colour
  rule in LED ends up needing.  Published because the minimap needs the same
  mix to draw the page in miniature, and a second copy of it would drift. }
function LedColourLuma(AColour: TColor): Integer;
function LedMixColours(A, B: TColor; APercent: Integer): TColor;

{ The contrast ratio between two colours, as WCAG defines it: from 1 (the
  same colour) to 21 (black on white).

  Luma is not enough for this.  It answers "how bright" on a scale that takes
  no account of how the eye responds to each channel at low values, so a
  saturated green and a saturated blue of the same luma read very
  differently against a white page -- which is how a theme can look fine by
  the numbers and still be unreadable. }
function LedContrastRatio(AFore, ABack: TColor): Double;

{ AFore, moved toward black or away from it until it clears AMinRatio against
  ABack.  Returns AFore unchanged when it already does, which is what keeps
  this from repainting themes that are fine. }
function LedEnsureReadable(AFore, ABack: TColor; AMinRatio: Double): TColor;

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

const
  { Minimum luminance separation, 0..255, between a gutter element and the
    gutter background.  Line numbers are glyphs and read at less separation
    than the fold marks, which are one- or two-pixel strokes. }
  LedMinGutterContrast = 70;
  LedMinFoldContrast   = 90;

{ Perceived luminance, 0..255, on the usual Rec.601 weights.  Good enough to
  decide "is this readable on that", which is all it is used for. }
function Luma(AColour: TColor): Integer;
var
  R, G, B: Integer;
begin
  R := AColour and $FF;
  G := (AColour shr 8) and $FF;
  B := (AColour shr 16) and $FF;
  Result := (R * 299 + G * 587 + B * 114) div 1000;
end;

{ Push AFore away from ABack until the two differ by at least AMinDelta in
  luminance, keeping the hue.  Returns AFore unchanged when it is already
  legible, so a scheme that made a deliberate choice keeps it.

  This exists because several of the eight schemes set a gutter colour barely
  distinguishable from the gutter background -- readable in medit, which drew
  line numbers in the widget's text colour, but not once the scheme's own
  value is honoured.  Rather than override the schemes wholesale, only the
  unreadable cases are moved, and only far enough to be read. }
function EnsureContrast(AFore, ABack: TColor; AMinDelta: Integer): TColor;
var
  LF, LB, Want, i: Integer;
  R, G, B: Integer;
  Up: Boolean;
begin
  Result := AFore;
  if (AFore = clNone) or (ABack = clNone) then
    Exit;
  LF := Luma(AFore);
  LB := Luma(ABack);
  if Abs(LF - LB) >= AMinDelta then
    Exit;

  { Move away from the background: lighten on a dark gutter, darken on a
    light one.  Picking the direction from the background rather than from
    the foreground keeps the result on the readable side when the two start
    out nearly equal. }
  Up := LB < 128;
  if Up then
    Want := LB + AMinDelta
  else
    Want := LB - AMinDelta;
  if Want < 0 then Want := 0;
  if Want > 255 then Want := 255;

  R := AFore and $FF;
  G := (AFore shr 8) and $FF;
  B := (AFore shr 16) and $FF;

  { Walk the channels toward white or black until the luminance target is
    met.  A proportional scale would wash a saturated colour out to grey. }
  for i := 1 to 255 do
  begin
    if (Up and (Luma(TColor(R or (G shl 8) or (B shl 16))) >= Want)) or
       ((not Up) and (Luma(TColor(R or (G shl 8) or (B shl 16))) <= Want)) then
      Break;
    if Up then
    begin
      if R < 255 then Inc(R);
      if G < 255 then Inc(G);
      if B < 255 then Inc(B);
    end
    else
    begin
      if R > 0 then Dec(R);
      if G > 0 then Dec(G);
      if B > 0 then Dec(B);
    end;
  end;
  Result := TColor(R or (G shl 8) or (B shl 16));
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

function LedCreateHighlighter(const ALangId: string): TSynCustomHighlighter;
var
  Cls: TSynCustomHighlighterClass;
  Grammar: string;
  TM: TSynTextMateSyn;
begin
  Result := nil;
  if ALangId = '' then Exit;

  Grammar := LedGrammarFile(ALangId);
  Cls := ClassFor(ALangId);

  { A native highlighter is taken only if it folds, or if there is no
    converted grammar to fall back on. }
  if (Cls <> nil) and
     (Cls.InheritsFrom(TSynCustomFoldHighlighter) or not FileExists(Grammar)) then
    Exit(Cls.Create(nil));

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
end;

function LedHighlighterFor(const ALangId: string): TSynCustomHighlighter;
var
  i: Integer;
begin
  Result := nil;
  if ALangId = '' then Exit;
  i := Cache.IndexOf(ALangId);
  if i >= 0 then Exit(TSynCustomHighlighter(Cache.Objects[i]));
  Result := LedCreateHighlighter(ALangId);
  if Result <> nil then Cache.AddObject(ALangId, Result);
end;

function ScopeForAttribute(const AStoredName: string): string;
var
  i, Dot: Integer;
begin
  { A TextMate highlighter names each attribute after the grammar scope that
    created it, and the converter emits the theme's own style ids as scopes
    with a dot for the colon -- 'def.comment' for 'def:comment', because a
    colon is not legal in a TextMate scope.  Put the colon back and the
    theme lookup below finds it directly; without this every grammar-driven
    language came out uncoloured. }
  Dot := Pos('.', AStoredName);
  if Dot > 0 then
    Exit(Copy(AStoredName, 1, Dot - 1) + ':' + Copy(AStoredName, Dot + 1, MaxInt));

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

{ SynEdit reports a highlighter's language name differently depending on the
  Lazarus version: 2.x reads a class function, which cannot see a TextMate
  highlighter's grammar and raises for it, while 3.x and later read a
  per-instance virtual that TSynTextMateSyn overrides.  Asking the grammar
  itself gives the same answer on both, so the theme scope key does not
  depend on which Lazarus built the tree. }
function LedHighlighterLanguageName(AHighlighter: TSynCustomHighlighter): string;
begin
  if AHighlighter is TSynTextMateSyn then
  begin
    Result := '';
    if TSynTextMateSyn(AHighlighter).TextMateGrammar <> nil then
      Result := TSynTextMateSyn(AHighlighter).TextMateGrammar.LanguageName;
  end
  else
    Result := AHighlighter.LanguageName;
end;

{ What a highlighter's attributes looked like before any theme touched them.

  Applying a theme only overwrites the scopes that theme mentions, so the
  scopes it says nothing about keep whatever the *last* theme put there.
  Switching from kate to classic left strings red: kate colours def:string,
  classic does not, and nothing put it back.  SynEdit remembers each
  attribute's defaults internally and exposes no way to read them, so LED
  keeps its own copy -- taken the first time a highlighter is themed, which
  is before anything has changed it -- and restores from that first.

  Keyed by the highlighter's address.  The cache owns them for the life of
  the process, so the key stays valid as long as the entry is wanted. }
var
  FVirgin: TStringList = nil;      // highlighter address -> its own list

function VirginFor(AHighlighter: TSynCustomHighlighter): TStringList;
var
  Key: string;
  i, j: Integer;
  Attr: TSynHighlighterAttributes;
begin
  if FVirgin = nil then
  begin
    FVirgin := TStringList.Create;
    FVirgin.Sorted := True;
    FVirgin.OwnsObjects := True;
  end;
  Key := IntToHex(PtrUInt(AHighlighter), 16);
  i := FVirgin.IndexOf(Key);
  if i >= 0 then Exit(TStringList(FVirgin.Objects[i]));

  Result := TStringList.Create;
  for j := 0 to AHighlighter.AttrCount - 1 do
  begin
    Attr := AHighlighter.Attribute[j];
    if Attr = nil then Continue;
    Result.Values[Attr.StoredName] := Format('%d|%d|%d',
      [Attr.Foreground, Attr.Background, PWord(@Attr.Style)^]);
  end;
  FVirgin.AddObject(Key, Result);
end;

procedure RestoreVirgin(AHighlighter: TSynCustomHighlighter);
var
  Saved: TStringList;
  i: Integer;
  Attr: TSynHighlighterAttributes;
  Parts: TStringArray;
  V: string;
  StyleBits: Word;
  Sty: TFontStyles;
begin
  Saved := VirginFor(AHighlighter);
  for i := 0 to AHighlighter.AttrCount - 1 do
  begin
    Attr := AHighlighter.Attribute[i];
    if Attr = nil then Continue;
    V := Saved.Values[Attr.StoredName];
    if V = '' then Continue;
    Parts := V.Split(['|']);
    if Length(Parts) < 3 then Continue;
    Attr.Foreground := TColor(StrToIntDef(Parts[0], Integer(clNone)));
    Attr.Background := TColor(StrToIntDef(Parts[1], Integer(clNone)));
    { Through a variable of the set's own type: a TFontStyles is a set and
      cannot be cast from an integer, but its bits can be written into one. }
    StyleBits := Word(StrToIntDef(Parts[2], 0));
    Sty := [];
    Move(StyleBits, Sty, SizeOf(Sty));
    Attr.Style := Sty;
  end;
end;

procedure LedApplyThemeToHighlighter(ATheme: TLedTheme;
  AHighlighter: TSynCustomHighlighter);
var
  i: Integer;
  Attr: TSynHighlighterAttributes;
  Style: TLedStyle;
  LangScope, Scope: string;
  Page, Behind: TColor;
begin
  if (ATheme = nil) or (AHighlighter = nil) then Exit;

  { Back to the grammar's own colours, so what this theme does not mention is
    not left over from the theme before it. }
  RestoreVirgin(AHighlighter);

  Page := clNone;
  if ATheme.Find(LedStyleText, Style) and (lsfBackground in Style.Flags) then
    Page := LedColourToTColor(Style.Background);

  for i := 0 to AHighlighter.AttrCount - 1 do
  begin
    Attr := AHighlighter.Attribute[i];
    if Attr = nil then Continue;

    Scope := ScopeForAttribute(Attr.StoredName);

    { A scheme may say something specific about this language -- "c:comment"
      -- which outranks the shared def: entry. }
    LangScope := LowerCase(LedHighlighterLanguageName(AHighlighter)) + ':' +
      Copy(Scope, Pos(':', Scope) + 1, MaxInt);
    if ATheme.Find(LangScope, Style) then
      ApplyStyle(Style, Attr)
    else if ATheme.Find(Scope, Style) then
      ApplyStyle(Style, Attr);

    { And readable on the page it will be drawn on.

      A grammar's own colours were chosen for whatever background its author
      had in mind, and a scheme colours only the scopes it thinks about, so
      what is left over is a colour nobody picked for this page.  Measured
      cases on white: tango's strings at 1.5, its keywords at 2.1,
      solarized-light's strings at 1.4 -- a mustard yellow on white, which is
      the "the string colour has almost no contrast" report.

      Four to one, which is a little under the WCAG threshold for body text.
      Enough to fix what cannot be read, gentle enough to leave the schemes
      that were designed with low contrast -- solarized above all -- looking
      like themselves. }
    Behind := Attr.Background;
    if Behind = clNone then Behind := Page;
    Attr.Foreground := LedEnsureReadable(Attr.Foreground, Behind, 4.0);
  end;
end;

{ Perceived brightness, on the usual weights. }
function LedColourLuma(AColour: TColor): Integer;
begin
  AColour := ColorToRGB(AColour);
  Result := ((AColour and $FF) * 299 + ((AColour shr 8) and $FF) * 587
            + ((AColour shr 16) and $FF) * 114) div 1000;
end;

{ APercent parts of A to the rest of B.  One place for a mix that three of
  these colour rules were each doing with their own arithmetic. }
function LedMixColours(A, B: TColor; APercent: Integer): TColor;
var
  Ra, Ga, Ba, Rb, Gb, Bb: Integer;
begin
  A := ColorToRGB(A);
  B := ColorToRGB(B);
  Ra := A and $FF;  Ga := (A shr 8) and $FF;  Ba := (A shr 16) and $FF;
  Rb := B and $FF;  Gb := (B shr 8) and $FF;  Bb := (B shr 16) and $FF;
  Result := TColor(
    (((Ra * APercent + Rb * (100 - APercent)) div 100) and $FF)
    or ((((Ga * APercent + Gb * (100 - APercent)) div 100) and $FF) shl 8)
    or ((((Ba * APercent + Bb * (100 - APercent)) div 100) and $FF) shl 16));
end;

function ChannelLuminance(AValue: Integer): Double;
var
  C: Double;
begin
  C := AValue / 255;
  if C <= 0.03928 then
    Result := C / 12.92
  else
    Result := Exp(2.4 * Ln((C + 0.055) / 1.055));
end;

function RelativeLuminance(AColour: TColor): Double;
begin
  AColour := ColorToRGB(AColour);
  Result := 0.2126 * ChannelLuminance(AColour and $FF)
          + 0.7152 * ChannelLuminance((AColour shr 8) and $FF)
          + 0.0722 * ChannelLuminance((AColour shr 16) and $FF);
end;

function LedContrastRatio(AFore, ABack: TColor): Double;
var
  LF, LB, T: Double;
begin
  Result := 1;
  if (AFore = clNone) or (ABack = clNone) then Exit;
  LF := RelativeLuminance(AFore) + 0.05;
  LB := RelativeLuminance(ABack) + 0.05;
  if LF < LB then
  begin
    T := LF; LF := LB; LB := T;
  end;
  Result := LF / LB;
end;

function LedEnsureReadable(AFore, ABack: TColor; AMinRatio: Double): TColor;
var
  Step: Integer;
  Target: TColor;
begin
  Result := AFore;
  if (AFore = clNone) or (ABack = clNone) then Exit;
  if LedContrastRatio(AFore, ABack) >= AMinRatio then Exit;

  { Away from the page: darker on a light one, lighter on a dark one.  Taken
    from the background rather than from the foreground, so a colour that
    starts out close to the page is pushed to the readable side rather than
    further into it. }
  if RelativeLuminance(ABack) > 0.18 then
    Target := clBlack
  else
    Target := clWhite;

  { Toward that target in twentieths, stopping at the first step that clears
    the ratio.  Mixing rather than replacing keeps the hue: a green that has
    to be darkened stays green. }
  for Step := 1 to 20 do
  begin
    Result := LedMixColours(Target, AFore, Step * 5);
    if LedContrastRatio(Result, ABack) >= AMinRatio then Exit;
  end;
  Result := Target;
end;

function LedThemeCurrentLineColour(ATheme: TLedTheme;
  ADefaultFg, ADefaultBg: TColor): TColor;
var
  S: TLedStyle;
  Guard: Integer;
begin
  Result := clNone;
  if ADefaultBg = clNone then Exit;

  if (ATheme <> nil) and ATheme.Find(LedStyleCurrentLine, S) and
     (lsfBackground in S.Flags) then
    Result := LedColourToTColor(S.Background)
  else
    Result := LedMixColours(ADefaultFg, ADefaultBg, 12);

  { Far enough from the page to be seen as a line.  The shipped themes' own
    current-line tints are two to nine points of luma off the page, which is
    plenty behind a whole row and nothing at all in a one-pixel rule; thirty
    reads as a hairline without competing with the text. }
  Guard := 0;
  while (Abs(LedColourLuma(Result) - LedColourLuma(ADefaultBg)) < 30) and
        (Guard < 40) do
  begin
    Inc(Guard);
    Result := LedMixColours(ADefaultFg, Result, 8);
  end;
end;

procedure LedApplyThemeToEditor(ATheme: TLedTheme; AEdit: TSynEdit);
var
  S: TLedStyle;
  GutterBack: TColor;
  Edge: TColor;
  Guard: Integer;
  Caret: TSynEditMarkupHighlightAllCaret;
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

  { Every other appearance of the word the caret is in, shaded in whatever
    the theme uses for a search match -- the same idea, and defined by all
    eight of the shipped schemes.

    On the caret markup, and this is the whole of the bug the first version
    had: TSynEdit keeps two highlight-all markups, one fed by Find and one
    that follows the caret, and the published HighlightAllColor is the
    *search* one --

      function TCustomSynEdit.GetHighlightAllColor: TSynSelectedColor;
      begin result := fMarkupHighAll.MarkupInfo; end;

    -- so colouring it woke nothing.  The caret markup stayed at clNone,
    which is what keeps it asleep, and clicking a word did nothing at all. }
  Caret := TSynEditMarkupHighlightAllCaret(
    AEdit.MarkupByClass[TSynEditMarkupHighlightAllCaret]);
  if (Caret <> nil) and ATheme.Find(LedStyleSearchMatch, S) then
  begin
    if lsfBackground in S.Flags then
      Caret.MarkupInfo.Background := LedColourToTColor(S.Background);
    if lsfForeground in S.Flags then
      Caret.MarkupInfo.Foreground := LedColourToTColor(S.Foreground);

    { And a foreground that can be read on it, whether or not the scheme
      thought to give one.

      Left unset, the highlighted word keeps whatever colour it already had
      -- which on a double-click is the selection's, white in kate and in
      SynEdit's own default.  White on the search-match yellow, over a white
      page, was the reported "nearly unreadable".  The highlight paints its
      background over the selection's, so it has to answer for the text on
      it as well. }
    if Caret.MarkupInfo.Background <> clNone then
    begin
      if Caret.MarkupInfo.Foreground = clNone then
        Caret.MarkupInfo.Foreground := AEdit.Font.Color;
      Caret.MarkupInfo.Foreground := LedEnsureReadable(
        Caret.MarkupInfo.Foreground, Caret.MarkupInfo.Background, 4.5);
    end;
  end;

  { Three of the eight shipped schemes -- classic, medit, tango -- say
    nothing about line-numbers.  GtkSourceView then draws them in the
    widget's ordinary text colours, whereas SynEdit falls back to a pale
    grey that is barely legible on a light background.  So fall back the way
    medit does, to the text style. }
  if not ATheme.Find(LedStyleLineNumbers, S) then
    if not ATheme.Find(LedStyleText, S) then
      S := Default(TLedStyle);

  GutterBack := clNone;
  if lsfBackground in S.Flags then
    GutterBack := LedColourToTColor(S.Background)
  else if AEdit.Color <> clNone then
    GutterBack := AEdit.Color;

  if lsfForeground in S.Flags then
    AEdit.Gutter.LineNumberPart.MarkupInfo.Foreground :=
      EnsureContrast(LedColourToTColor(S.Foreground), GutterBack,
        LedMinGutterContrast);
  if lsfBackground in S.Flags then
  begin
    AEdit.Gutter.LineNumberPart.MarkupInfo.Background :=
      LedColourToTColor(S.Background);
    AEdit.Gutter.Color := LedColourToTColor(S.Background);
    AEdit.Gutter.MarksPart.MarkupInfo.Background := LedColourToTColor(S.Background);
    AEdit.Gutter.CodeFoldPart.MarkupInfo.Background := LedColourToTColor(S.Background);
    AEdit.Gutter.SeparatorPart.MarkupInfo.Background := LedColourToTColor(S.Background);
  end;
  { The fold boxes and the vertical rule joining a block to its end are drawn
    in the gutter's own foreground, so they inherit the same legibility
    problem as the line numbers -- and they are thin strokes rather than
    glyphs, so they need more separation, not less. }
  if lsfForeground in S.Flags then
    AEdit.Gutter.CodeFoldPart.MarkupInfo.Foreground :=
      EnsureContrast(LedColourToTColor(S.Foreground), GutterBack,
        LedMinFoldContrast);

  if ATheme.Find(LedStyleBracketMatch, S) then
  begin
    if lsfForeground in S.Flags then
      AEdit.BracketMatchColor.Foreground := LedColourToTColor(S.Foreground);
    if lsfBackground in S.Flags then
      AEdit.BracketMatchColor.Background := LedColourToTColor(S.Background);
  end;

  { The right margin, mixed down towards the page.

    It marks a soft limit, and a soft limit drawn at full strength is louder
    than the code it is a note about -- on oblivion the style's foreground is
    aluminium1, very nearly white, so a solid line of it on a dark page was
    the brightest thing in the window.  GtkSourceView draws this as a faint
    overlay rather than a line in the style's own colour; a third of the way
    from the page is the same idea arrived at with what SynEdit offers, which
    is one colour and no alpha.

    The foreground where the scheme has one, its background otherwise --
    three of the eight give only a background for this style. }
  Edge := clNone;
  if ATheme.Find(LedStyleRightMargin, S) then
  begin
    if lsfForeground in S.Flags then
      Edge := LedColourToTColor(S.Foreground)
    else if lsfBackground in S.Flags then
      Edge := LedColourToTColor(S.Background);
  end;
  if (Edge <> clNone) and (AEdit.Color <> clNone) then
  begin
    Edge := LedMixColours(Edge, AEdit.Color, 33);
    { With a floor, because a scheme whose right-margin colour is already
      close to its page mixes down to the page exactly and the margin
      disappears -- which the check caught: the mix came out with no
      difference from the page at all.  Stepped back away from the page until
      it can be seen. }
    Guard := 0;
    while (Abs(LedColourLuma(Edge) - LedColourLuma(AEdit.Color)) < 14) and
          (Guard < 20) do
    begin
      if LedColourLuma(AEdit.Color) < 128 then
        Edge := LedMixColours(clWhite, Edge, 12)
      else
        Edge := LedMixColours(clBlack, Edge, 12);
      Inc(Guard);
    end;
    AEdit.RightEdgeColor := Edge;
  end
  else if Edge <> clNone then
    AEdit.RightEdgeColor := Edge;
end;

{ The colour for the vertical guides down an open block.  medit draws these
  in a dedicated fold_guide_color, quieter than the text: they are structure,
  and at full strength they compete with the code they are meant to organise.
  No such entry exists in the eight schemes, so it is derived -- a quarter of
  the way from the background toward the text colour, which lands somewhere
  legible on both the light and the dark schemes without a table of special
  cases.

  A function rather than something that applies itself, because the control it
  would apply to lives in ledui and ledui depends on ledsyn, not the other way
  round. }
function LedThemeGuideColour(ATheme: TLedTheme;
  ADefaultFg, ADefaultBg: TColor): TColor;
var
  S: TLedStyle;
  Fg, Bg: TColor;
begin
  Fg := clNone;
  Bg := clNone;
  if (ATheme <> nil) and ATheme.Find(LedStyleText, S) then
  begin
    if lsfForeground in S.Flags then Fg := LedColourToTColor(S.Foreground);
    if lsfBackground in S.Flags then Bg := LedColourToTColor(S.Background);
  end;
  if Fg = clNone then Fg := ADefaultFg;
  if Bg = clNone then Bg := ADefaultBg;
  if (Fg = clNone) or (Bg = clNone) then Exit(clNone);

  Fg := ColorToRGB(Fg);
  Bg := ColorToRGB(Bg);
  { Two fifths of the way to the text colour.  A quarter was the first
    attempt and was invisible on screen -- a guide nobody can see is not a
    quiet guide, it is a missing one. }
  Result := TColor(
    ((((2 * (Fg and $FF)) + 3 * (Bg and $FF)) div 5) and $FF)
    or ((((2 * ((Fg shr 8) and $FF)) + 3 * ((Bg shr 8) and $FF)) div 5) shl 8)
    or ((((2 * ((Fg shr 16) and $FF)) + 3 * ((Bg shr 16) and $FF)) div 5) shl 16));
end;

{ The tint behind a line whose block is folded shut.

  One part text to nine parts page: enough to say "there is more here than
  is showing" without competing with the syntax colouring on the line, and
  mixed from the theme's own two colours so it works on the four dark
  schemes as well as the four light ones. }
function LedThemeFoldedLineColour(ATheme: TLedTheme;
  ADefaultFg, ADefaultBg: TColor): TColor;
var
  S: TLedStyle;
  Fg, Bg, Tint: TColor;
begin
  Fg := clNone;
  Bg := clNone;
  if (ATheme <> nil) and ATheme.Find(LedStyleText, S) then
  begin
    if lsfForeground in S.Flags then Fg := LedColourToTColor(S.Foreground);
    if lsfBackground in S.Flags then Bg := LedColourToTColor(S.Background);
  end;
  if Fg = clNone then Fg := ADefaultFg;
  if Bg = clNone then Bg := ADefaultBg;
  if (Fg = clNone) or (Bg = clNone) then Exit(clNone);

  { Mixed towards the theme's selection rather than towards its text.  Text
    over page is a grey whatever the scheme, and a grey band behind a folded
    line reads as the line being disabled rather than as the line having more
    behind it.  The selection colour is already the one this scheme uses to
    say "something is here", so a weak wash of it says the same thing
    quietly. }
  Tint := clNone;
  if (ATheme <> nil) and ATheme.Find(LedStyleSelection, S) and
     (lsfBackground in S.Flags) then
    Tint := LedColourToTColor(S.Background);
  if Tint = clNone then Tint := Fg;    { no selection colour: the old mix }

  Fg := ColorToRGB(Tint);
  Bg := ColorToRGB(Bg);
  Result := TColor(
    (((3 * (Fg and $FF) + 7 * (Bg and $FF)) div 10) and $FF)
    or ((((3 * ((Fg shr 8) and $FF) + 7 * ((Bg shr 8) and $FF)) div 10) and $FF) shl 8)
    or ((((3 * ((Fg shr 16) and $FF) + 7 * ((Bg shr 16) and $FF)) div 10) and $FF) shl 16));
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
  FVirgin.Free;

end.
