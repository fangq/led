{ LED - a lightweight editor.  Colouring JSON.

  Reported as: a 26 MB .json takes half a minute to open, and what comes back
  is not coloured like medit's.

  Both had one cause.  JSON was coloured by the converted grammar, which
  drives a backtracking regular-expression engine over every line, and that
  grammar ends with

      { "match": "\\S", "name": "def.error" }

  -- so every brace, comma and colon in the file is matched one character at
  a time, each one after the whole pattern list has been tried and failed.
  Measured on the reported file: 1.9 MB a second, 27.6 s to open, and the
  same work again on every repaint, which is why scrolling cost three
  seconds a page.

  What it produced was not worth the wait either.  The commas and colons it
  matched came back as errors, drawn in the theme's error red; the strings
  were scoped 'js.string', which no scheme LED ships defines, so they were
  not coloured at all; and an object's keys were the same scope as its
  values, so the one distinction a reader of JSON actually wants was the one
  thing missing.

  This reads the line instead.  One pass, no regular expressions, no
  backtracking: a character at the front of a token says what the token is,
  and the only lookahead is over a string, to see whether a colon follows it
  -- which is what makes a key a key.  The scopes are the ones medit's
  json.lang asks for, mapped to the def: entries LED's schemes actually
  define, so a key, a string, an integer, a float, an escape and a literal
  each look different from the others.

  Folding is by bracket depth, counted per line rather than per bracket: a
  structure that opens and closes on one line is not something anybody folds,
  and JSON that has been written out on one line has hundreds of thousands
  of them.  See ApplyFold. }
unit Led.Syn.JSON;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, SynEditHighlighter, SynEditHighlighterFoldBase,
  SynEditTypes;

type
  { What a token is.  jtNone is the end of the line and nothing else. }
  TLedJSONTok = (jtNone, jtSpace, jtPunct, jtKey, jtString, jtEscape,
                 jtInt, jtFloat, jtLiteral);

  { TLedJSONSyn }

  TLedJSONSyn = class(TSynCustomFoldHighlighter)
  private
    FLineStr: string;
    FLine: PChar;
    FLineLen: Integer;
    FRun: Integer;              { 0-based, as SynEdit counts }
    FTokenPos: Integer;
    FTok: TLedJSONTok;
    { Inside a pair of quotes, between one piece of a string and the next.
      A JSON string cannot span lines -- medit's json.lang ends one at the
      line end too -- so this never has to survive into the next line, and
      the only thing the range carries is the fold depth. }
    FInString: Boolean;
    FStringTok: TLedJSONTok;    { jtKey or jtString, for every piece of it }
    FNet: Integer;              { brackets opened on this line, less closed }
    FFoldDone: Boolean;
    FAttrs: array[TLedJSONTok] of TSynHighlighterAttributes;
    procedure ApplyFold;
    function LooksLikeKey: Boolean;
    procedure ScanString;
    procedure ScanNumber;
    procedure ScanWord;
  protected
    function GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes;
      override;
  public
    constructor Create(AOwner: TComponent); override;

    procedure SetLine(const NewValue: string; LineNumber: Integer); override;
    procedure Next; override;
    function GetEol: Boolean; override;
    function GetToken: string; override;
    procedure GetTokenEx(out TokenStart: PChar; out TokenLength: Integer);
      override;
    function GetTokenAttribute: TSynHighlighterAttributes; override;
    function GetTokenKind: Integer; override;
    function GetTokenPos: Integer; override;

    function GetRange: Pointer; override;
    procedure SetRange(Value: Pointer); override;
    procedure ResetRange; override;

    class function GetLanguageName: string; override;
  end;

implementation

{ The theme scope each kind is coloured as.

  Names, not colours: 'def.string' is what a converted grammar emits, and
  Led.Syn.Factory turns it into the scheme's def:string on the way to a
  colour, through the same contrast floor every other language goes through.

  medit's json.lang asks for keyname -> def:constant and string -> js:string.
  The second is not a scope any scheme LED ships defines, which is the
  uncoloured-strings half of the report; the first is dark red in the medit
  scheme, which is very nearly the red its strings are, so following it would
  have put a key and its value in almost the same colour.  So keys are
  def:identifier -- dark blue there, distinct in every scheme, and what LED's
  own structure view already uses for the same idea.

  true, false and null are def:statement rather than the js:boolean and
  js:null-value json.lang names, for the same reason: no scheme defines
  those. }
const
  TokScope: array[TLedJSONTok] of string = (
    '',                      { jtNone    -- the end of the line }
    'Space',                 { jtSpace   }
    'Symbol',                { jtPunct   -- brackets, commas, colons }
    'def.identifier',        { jtKey     }
    'def.string',            { jtString  }
    'def.special-char',      { jtEscape  }
    'def.decimal',           { jtInt     }
    'def.floating-point',    { jtFloat   }
    'def.statement');        { jtLiteral -- true, false, null }

constructor TLedJSONSyn.Create(AOwner: TComponent);
var
  K: TLedJSONTok;
begin
  inherited Create(AOwner);
  for K := Low(TLedJSONTok) to High(TLedJSONTok) do
  begin
    if TokScope[K] = '' then Continue;
    FAttrs[K] := TSynHighlighterAttributes.Create(TokScope[K], TokScope[K]);
    AddAttribute(FAttrs[K]);
  end;
  FTok := jtNone;
end;

class function TLedJSONSyn.GetLanguageName: string;
begin
  { The scheme may say something about this language in particular --
    'json:string' outranks 'def:string' -- and this is the name it is looked
    up under. }
  Result := 'JSON';
end;

function TLedJSONSyn.GetDefaultAttribute(
  Index: Integer): TSynHighlighterAttributes;
begin
  case Index of
    SYN_ATTR_WHITESPACE: Result := FAttrs[jtSpace];
    SYN_ATTR_SYMBOL:     Result := FAttrs[jtPunct];
    SYN_ATTR_IDENTIFIER: Result := FAttrs[jtKey];
    SYN_ATTR_STRING:     Result := FAttrs[jtString];
    SYN_ATTR_NUMBER:     Result := FAttrs[jtInt];
    SYN_ATTR_KEYWORD:    Result := FAttrs[jtLiteral];
  else
    Result := nil;
  end;
end;

{ --- the fold depth ------------------------------------------------------- }

{ Opens or closes as many blocks as the line's brackets came out ahead or
  behind, once, at the end of the line.

  Per line and not per bracket on purpose.  A fold block is a node in a tree
  the base class keeps, and JSON written out without line breaks -- which is
  most of the JSON anybody opens a 26 MB file of -- has hundreds of matched
  pairs on a single line.  Opening and closing a block for each of them would
  build and tear down that many nodes per line for folds nobody can use: a
  block that opens and closes on one line folds nothing away.

  What is left is what a reader means by folding a JSON file: the brace that
  is still open when the line ends is the one with a body under it. }
procedure TLedJSONSyn.ApplyFold;
var
  i, Level: Integer;
begin
  FFoldDone := True;
  if FNet > 0 then
    for i := 1 to FNet do
      StartCodeFoldBlock(nil)
  else if FNet < 0 then
  begin
    { Never past the bottom: a file with one closing bracket too many in
      it, or one being typed from the middle out, would otherwise close a
      block that was never opened. }
    Level := CurrentCodeFoldBlockLevel;
    for i := 1 to -FNet do
    begin
      if Level <= 0 then Break;
      EndCodeFoldBlock;
      Dec(Level);
    end;
  end;
end;

{ --- scanning ------------------------------------------------------------- }

{ Whether the string starting at FRun is an object's key: the next thing
  after its closing quote, skipping blanks, is a colon.

  This is the whole of the lookahead in this highlighter, and it is what the
  grammar never did -- it gave a key and a value the same scope, so the one
  distinction a reader of JSON wants was the one it did not draw.

  A string whose colon is on the following line reads as a value.  JSON is
  written by machines that put the two together, so the case is rare, and
  guessing across a line boundary would need state that nothing else here
  needs. }
function TLedJSONSyn.LooksLikeKey: Boolean;
var
  i: Integer;
begin
  Result := False;
  i := FRun + 1;                       { past the opening quote }
  while i < FLineLen do
  begin
    if FLine[i] = '\' then
    begin
      Inc(i, 2);                       { an escape, whatever it escapes }
      Continue;
    end;
    if FLine[i] = '"' then Break;
    Inc(i);
  end;
  if (i >= FLineLen) or (FLine[i] <> '"') then Exit;   { unterminated }
  Inc(i);
  while (i < FLineLen) and (FLine[i] in [' ', #9]) do Inc(i);
  Result := (i < FLineLen) and (FLine[i] = ':');
end;

{ One piece of a string: the quoted text up to the next escape, the closing
  quote, or the end of the line.  The escape itself is a token of its own, so
  that it can be drawn in its own colour the way medit draws it. }
procedure TLedJSONSyn.ScanString;
begin
  if not FInString then
  begin
    if LooksLikeKey then FStringTok := jtKey else FStringTok := jtString;
    FInString := True;
    Inc(FRun);                         { the opening quote }
  end;

  FTok := FStringTok;
  while FRun < FLineLen do
  begin
    if FLine[FRun] = '\' then Exit;    { the escape is the next token }
    if FLine[FRun] = '"' then
    begin
      Inc(FRun);                       { the closing quote belongs to it }
      FInString := False;
      Exit;
    end;
    Inc(FRun);
  end;
  { Ran off the end.  A JSON string does not span lines, so it ends here
    rather than colouring the rest of the file. }
  FInString := False;
end;

procedure TLedJSONSyn.ScanNumber;
var
  Float: Boolean;
begin
  Float := False;
  if (FRun < FLineLen) and (FLine[FRun] = '-') then Inc(FRun);
  while (FRun < FLineLen) and (FLine[FRun] in ['0'..'9']) do Inc(FRun);
  if (FRun < FLineLen) and (FLine[FRun] = '.') and
     (FRun + 1 < FLineLen) and (FLine[FRun + 1] in ['0'..'9']) then
  begin
    Float := True;
    Inc(FRun);
    while (FRun < FLineLen) and (FLine[FRun] in ['0'..'9']) do Inc(FRun);
  end;
  if (FRun < FLineLen) and (FLine[FRun] in ['e', 'E']) then
  begin
    Float := True;
    Inc(FRun);
    if (FRun < FLineLen) and (FLine[FRun] in ['+', '-']) then Inc(FRun);
    while (FRun < FLineLen) and (FLine[FRun] in ['0'..'9']) do Inc(FRun);
  end;
  if Float then FTok := jtFloat else FTok := jtInt;
end;

{ A bare word.  In valid JSON it is true, false or null; anything else is
  something the file should not contain.

  It is not marked as an error.  The grammar marked every unmatched
  character as one, which is how a file of perfectly good JSON came to be
  drawn with red commas -- and an editor that cries wolf about punctuation
  is not one whose red anybody reads. }
procedure TLedJSONSyn.ScanWord;
var
  Start: Integer;
  W: string;
begin
  Start := FRun;
  while (FRun < FLineLen) and
        (FLine[FRun] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do Inc(FRun);
  W := Copy(FLineStr, Start + 1, FRun - Start);
  if (W = 'true') or (W = 'false') or (W = 'null') then
    FTok := jtLiteral
  else
    FTok := jtPunct;
end;

procedure TLedJSONSyn.SetLine(const NewValue: string; LineNumber: Integer);
begin
  inherited SetLine(NewValue, LineNumber);
  FLineStr := NewValue;
  FLine := PChar(FLineStr);
  FLineLen := Length(FLineStr);
  FRun := 0;
  FNet := 0;
  FFoldDone := False;
  FInString := False;
  Next;
end;

procedure TLedJSONSyn.Next;
begin
  FTokenPos := FRun;

  if FRun >= FLineLen then
  begin
    if not FFoldDone then ApplyFold;
    FTok := jtNone;
    Exit;
  end;

  if FInString then
  begin
    { Mid-string: either the escape that stopped the last piece, or the rest
      of the text after it. }
    if FLine[FRun] = '\' then
    begin
      FTok := jtEscape;
      Inc(FRun);
      if (FRun < FLineLen) and (FLine[FRun] = 'u') then
      begin
        Inc(FRun);
        while (FRun < FLineLen) and (FRun < FTokenPos + 6) and
              (FLine[FRun] in ['0'..'9', 'a'..'f', 'A'..'F']) do Inc(FRun);
      end
      else if FRun < FLineLen then
        Inc(FRun);
      Exit;
    end;
    ScanString;
    Exit;
  end;

  case FLine[FRun] of
    ' ', #9:
      begin
        FTok := jtSpace;
        while (FRun < FLineLen) and (FLine[FRun] in [' ', #9]) do Inc(FRun);
      end;
    '"':
      ScanString;
    '-', '0'..'9':
      ScanNumber;
    'a'..'z', 'A'..'Z', '_':
      ScanWord;
    '{', '[':
      begin
        FTok := jtPunct;
        Inc(FNet);
        Inc(FRun);
      end;
    '}', ']':
      begin
        FTok := jtPunct;
        Dec(FNet);
        Inc(FRun);
      end;
  else
    begin
      FTok := jtPunct;
      Inc(FRun);
    end;
  end;
end;

function TLedJSONSyn.GetEol: Boolean;
begin
  Result := FTok = jtNone;
end;

function TLedJSONSyn.GetToken: string;
begin
  Result := Copy(FLineStr, FTokenPos + 1, FRun - FTokenPos);
end;

procedure TLedJSONSyn.GetTokenEx(out TokenStart: PChar;
  out TokenLength: Integer);
begin
  TokenStart := FLine + FTokenPos;
  TokenLength := FRun - FTokenPos;
end;

function TLedJSONSyn.GetTokenAttribute: TSynHighlighterAttributes;
begin
  Result := FAttrs[FTok];
end;

function TLedJSONSyn.GetTokenKind: Integer;
begin
  Result := Ord(FTok);
end;

function TLedJSONSyn.GetTokenPos: Integer;
begin
  Result := FTokenPos;
end;

{ The range is the fold stack and nothing else: no scanner state outlives a
  line here, because no JSON token does. }
function TLedJSONSyn.GetRange: Pointer;
begin
  Result := inherited GetRange;
end;

procedure TLedJSONSyn.SetRange(Value: Pointer);
begin
  inherited SetRange(Value);
  FInString := False;
end;

procedure TLedJSONSyn.ResetRange;
begin
  inherited ResetRange;
  FInString := False;
end;

end.
