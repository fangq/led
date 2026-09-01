{ led - a light editor.  Headless tests for the colour-theme reader.

  Run against the eight schemes vendored from medit, so they also check that
  the theme data is intact. }
unit Led.Syn.Tests.Theme;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Led.Syn.Theme;

type
  TTestTheme = class(TTestCase)
  private
    FReg: TLedThemeRegistry;
    function DataDir: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AllShippedThemesLoad;
    procedure NameAndIdAreRead;
    procedure NamedColoursResolve;
    procedure DirectHexColoursResolve;
    procedure BooleanAttributesAreRead;
    procedure UseStyleFollowsTheAlias;
    procedure LongestPrefixFallback;
    procedure UnknownStyleIsReportedMissing;
    procedure EditorChromeIsPresent;
    procedure LanguageSpecificStylesSurvive;
    procedure ColourParsing;
  end;

implementation

function TTestTheme.DataDir: string;
begin
  Result := ExpandFileName(ExtractFilePath(ExpandFileName(ParamStr(0))) +
    '..' + PathDelim + 'data' + PathDelim + 'themes');
end;

procedure TTestTheme.SetUp;
begin
  FReg := TLedThemeRegistry.Create;
  FReg.ScanDirectory(DataDir);
end;

procedure TTestTheme.TearDown;
begin
  FReg.Free;
end;

procedure TTestTheme.AllShippedThemesLoad;
begin
  AssertEquals('all eight schemes load', 8, FReg.Count);
  AssertNotNull(FReg.FindById('oblivion'));
  AssertNotNull(FReg.FindById('solarized-dark'));
  AssertNotNull(FReg.FindById('medit'));
end;

procedure TTestTheme.NameAndIdAreRead;
var
  T: TLedTheme;
begin
  T := FReg.FindById('oblivion');
  AssertEquals('oblivion', T.Id);
  AssertEquals('Oblivion', T.Name);
end;

procedure TTestTheme.NamedColoursResolve;
var
  T: TLedTheme;
  S: TLedStyle;
begin
  { Oblivion writes def:comment as a palette name, not a hex literal. }
  T := FReg.FindById('oblivion');
  AssertTrue(T.Find('def:comment', S));
  AssertTrue('foreground was stated', lsfForeground in S.Flags);
  AssertTrue('and resolved to a real colour', S.Foreground <> LedNoColour);
end;

procedure TTestTheme.DirectHexColoursResolve;
var
  T: TLedTheme;
  S: TLedStyle;
begin
  { classic states draw-spaces as a hex literal rather than a palette name. }
  T := FReg.FindById('classic');
  AssertTrue(T.Find('draw-spaces', S));
  AssertEquals($BABDB6, S.Foreground);
end;

procedure TTestTheme.BooleanAttributesAreRead;
var
  T: TLedTheme;
  S: TLedStyle;
begin
  { medit's own scheme states both italic and bold on def:comment, so it
    exercises a true and a false in the same element. }
  T := FReg.FindById('medit');
  AssertTrue(T.Find('def:comment', S));
  AssertTrue('italic was stated', lsfItalic in S.Flags);
  AssertTrue(S.Italic);
  AssertTrue('bold was stated', lsfBold in S.Flags);
  AssertFalse('and it is false', S.Bold);
end;

procedure TTestTheme.UseStyleFollowsTheAlias;
var
  T: TLedTheme;
  S, Target: TLedStyle;
  i: Integer;
  Found: Boolean;
begin
  { At least one scheme aliases a style; whichever it is, the alias must end
    up with the target's attributes rather than nothing. }
  Found := False;
  for i := 0 to FReg.Count - 1 do
  begin
    T := FReg[i];
    if T.Find('def:complex', S) and T.Find('def:base-n-integer', Target) then
      if S.Flags = Target.Flags then
      begin
        Found := True;
        Break;
      end;
  end;
  AssertTrue('an aliased style resolves to its target', Found);
end;

procedure TTestTheme.LongestPrefixFallback;
var
  T: TLedTheme;
  S, Base: TLedStyle;
begin
  { A dotted name that the scheme has never heard of must fall back to the
    longest prefix it does know.  This is what will make real TextMate scope
    names work later without touching the themes. }
  T := FReg.FindById('oblivion');
  AssertTrue(T.Find('def:comment', Base));
  AssertTrue('a longer dotted name still resolves',
    T.Find('def:comment.line.double-slash.c', S));
  AssertEquals('to the same colour', Base.Foreground, S.Foreground);
end;

procedure TTestTheme.UnknownStyleIsReportedMissing;
var
  T: TLedTheme;
  S: TLedStyle;
begin
  T := FReg.FindById('oblivion');
  AssertFalse(T.Find('no:such:style', S));
  AssertFalse(T.Has('nonsense'));
end;

procedure TTestTheme.EditorChromeIsPresent;
var
  T: TLedTheme;
  S: TLedStyle;
begin
  { The chrome names are what the editor itself needs, as distinct from the
    syntax styles the highlighter needs. }
  { Not every scheme states every chrome style -- medit leaves "text" to the
    widget default -- so check one that does. }
  T := FReg.FindById('oblivion');
  AssertTrue('text', T.Find(LedStyleText, S));
  AssertTrue('selection', T.Find(LedStyleSelection, S));
  AssertTrue('current-line', T.Find(LedStyleCurrentLine, S));
  AssertTrue('line-numbers', T.Find(LedStyleLineNumbers, S));
  AssertTrue('bracket-match', T.Find(LedStyleBracketMatch, S));
end;

procedure TTestTheme.LanguageSpecificStylesSurvive;
var
  T: TLedTheme;
  S: TLedStyle;
begin
  { The schemes carry 200-odd language-specific entries beyond the shared
    def: names; losing them would quietly flatten diff and LaTeX colouring. }
  T := FReg.FindById('oblivion');
  AssertTrue('diff styles are kept', T.Find('diff:added-line', S));
  AssertTrue('latex styles are kept', T.Find('latex:command', S));
end;

procedure TTestTheme.ColourParsing;
begin
  AssertEquals($FF8800, LedParseColour('#ff8800'));
  AssertEquals($AABBCC, LedParseColour('#AABBCC'));
  AssertEquals('shorthand expands', $FFAA00, LedParseColour('#fa0'));
  AssertEquals(LedNoColour, LedParseColour('not a colour'));
  AssertEquals(LedNoColour, LedParseColour(''));
end;

initialization
  RegisterTest(TTestTheme);

end.
