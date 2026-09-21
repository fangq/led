{ LED - a lightweight editor.  Colouring YAML.

  The same two complaints as JSON, and the same answer: read the line rather
  than run a regular-expression engine over it.  Measured on a 28 MB YAML of
  615,393 lines, which is what a large JSON looks like once it has been
  converted.

  YAML is line-oriented, which makes this simpler than it sounds.  What a
  line means is decided by how far it is indented and by what its first
  non-blank character is, and the only thing that outlives a line is a block
  scalar -- the text under a `|` or a `>`, which runs on until something is
  indented no further than the line that introduced it.  That one fact is
  what the range carries.

  Folding is by indentation, which is the only structure YAML has.  A line
  whose successor is indented further opens a block; a line closes every
  block indented at least as far as itself.  The successor is read from the
  buffer -- a highlighter is allowed to look at CurrentLines, and one line
  ahead is all it takes to know whether the line being scanned has a body
  under it.

  The scopes are the ones medit's yaml.lang asks for, with two changes, both
  because no scheme LED ships defines the scope it names: a map key is
  def:identifier rather than def:keyword, and a boolean or a null is
  def:statement rather than the yaml-specific names.  See Led.Syn.JSON for
  the same argument in full. }
unit Led.Syn.YAML;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, SynEditHighlighter, SynEditHighlighterFoldBase,
  SynEditTypes;

type
  TLedYAMLTok = (ytNone, ytSpace, ytPunct, ytComment, ytKey, ytString,
                 ytEscape, ytInt, ytFloat, ytLiteral, ytAnchor, ytTag,
                 ytDirective);

  { TLedYAMLSyn }

  TLedYAMLSyn = class(TSynCustomFoldHighlighter)
  private
    FLineStr: string;
    FLine: PChar;
    FLineLen: Integer;
    FRun: Integer;
    FTokenPos: Integer;
    FTok: TLedYAMLTok;
    { The indentation of the line that introduced the block scalar being
      read, plus one; zero when there is no block scalar open.  The only
      state that crosses a line, and so the only thing in the range besides
      the fold stack. }
    FBlockPlus1: Integer;
    { Set while the rest of this line is the text of a block scalar or a
      comment: both run to the end of the line whatever is in them. }
    FRestIsString: Boolean;
    FRestIsComment: Boolean;
    { Nothing on this line so far but indentation and sequence dashes, so
      the next word may be a key. }
    FAtKeyPos: Boolean;
    { The quote a scalar was opened with, while the scan is between one
      piece of it and the next; #0 outside a quoted scalar.  An escape is a
      token of its own, so a double-quoted scalar comes back in pieces and
      something has to remember that the pieces are one string. }
    FQuote: Char;
    FIndent: Integer;
    FFoldDone: Boolean;
    FAttrs: array[TLedYAMLTok] of TSynHighlighterAttributes;
    function IndentOf(const S: string): Integer;
    function BlankOrComment(const S: string): Boolean;
    function KeyEndsAt: Integer;
    procedure ApplyFold;
    procedure ScanQuoted(AQuote: Char);
    procedure ScanPlain;
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

const
  TokScope: array[TLedYAMLTok] of string = (
    '',                      { ytNone      }
    'Space',                 { ytSpace     }
    'Symbol',                { ytPunct     -- dashes, colons, brackets }
    'def.comment',           { ytComment   }
    'def.identifier',        { ytKey       }
    'def.string',            { ytString    -- quoted, and block scalars }
    'def.special-char',      { ytEscape    }
    'def.decimal',           { ytInt       }
    'def.floating-point',    { ytFloat     }
    'def.statement',         { ytLiteral   -- true, false, null, ~ }
    'def.type',              { ytAnchor    -- &anchor and *alias }
    'def.preprocessor',      { ytTag       -- !tag, --- and ... }
    'def.shebang');          { ytDirective -- %YAML }

constructor TLedYAMLSyn.Create(AOwner: TComponent);
var
  K, J: TLedYAMLTok;
  Existing: TSynHighlighterAttributes;
begin
  inherited Create(AOwner);
  { One attribute per scope: a highlighter keeps its attributes in a list
    keyed by name and will not take the same name twice, so kinds that share
    a scope share the object. }
  for K := Low(TLedYAMLTok) to High(TLedYAMLTok) do
  begin
    if TokScope[K] = '' then Continue;
    Existing := nil;
    for J := Low(TLedYAMLTok) to Pred(K) do
      if TokScope[J] = TokScope[K] then
      begin
        Existing := FAttrs[J];
        Break;
      end;
    if Existing <> nil then
    begin
      FAttrs[K] := Existing;
      Continue;
    end;
    FAttrs[K] := TSynHighlighterAttributes.Create(TokScope[K], TokScope[K]);
    AddAttribute(FAttrs[K]);
  end;
  FTok := ytNone;
end;

class function TLedYAMLSyn.GetLanguageName: string;
begin
  Result := 'YAML';
end;

function TLedYAMLSyn.GetDefaultAttribute(
  Index: Integer): TSynHighlighterAttributes;
begin
  case Index of
    SYN_ATTR_WHITESPACE: Result := FAttrs[ytSpace];
    SYN_ATTR_SYMBOL:     Result := FAttrs[ytPunct];
    SYN_ATTR_COMMENT:    Result := FAttrs[ytComment];
    SYN_ATTR_IDENTIFIER: Result := FAttrs[ytKey];
    SYN_ATTR_STRING:     Result := FAttrs[ytString];
    SYN_ATTR_NUMBER:     Result := FAttrs[ytInt];
    SYN_ATTR_KEYWORD:    Result := FAttrs[ytLiteral];
  else
    Result := nil;
  end;
end;

{ --- reading the shape of a line ------------------------------------------ }

function TLedYAMLSyn.IndentOf(const S: string): Integer;
begin
  Result := 0;
  while (Result < Length(S)) and (S[Result + 1] in [' ', #9]) do Inc(Result);
end;

function TLedYAMLSyn.BlankOrComment(const S: string): Boolean;
var
  i: Integer;
begin
  i := IndentOf(S) + 1;
  Result := (i > Length(S)) or (S[i] = '#');
end;

{ Where the colon that makes this a key is, counting from FRun, or -1.

  A key is what stands before a colon that is followed by a space or the end
  of the line -- "a: 1" is a key and a value, "http://x" is not, and that
  rule is the whole of YAML's ambiguity here.  Quotes are stepped over so
  that a colon inside them does not count, and a '#' that starts a comment
  ends the search: what follows it is not a key. }
function TLedYAMLSyn.KeyEndsAt: Integer;
var
  i: Integer;
  Q: Char;
begin
  Result := -1;
  i := FRun;
  while i < FLineLen do
  begin
    case FLine[i] of
      '"', '''':
        begin
          Q := FLine[i];
          Inc(i);
          while (i < FLineLen) and (FLine[i] <> Q) do
          begin
            if (Q = '"') and (FLine[i] = '\') then Inc(i);
            Inc(i);
          end;
          Inc(i);
        end;
      '#':
        { Only a '#' after a blank starts a comment; one inside a word is
          part of it. }
        if (i = 0) or (FLine[i - 1] in [' ', #9]) then
          Exit
        else
          Inc(i);
      ':':
        begin
          if (i + 1 >= FLineLen) or (FLine[i + 1] in [' ', #9]) then
            Exit(i);
          Inc(i);
        end;
    else
      Inc(i);
    end;
  end;
end;

{ --- folding -------------------------------------------------------------- }

{ Closes the blocks this line has left behind, and opens one when the line
  below is indented further.

  The indentation of an open block is kept as the block's own type -- the
  pointer TSynCustomFoldHighlighter stores with it -- so the stack of
  indentations is the fold stack, and it comes back with the range on a
  rescan rather than having to be rebuilt.

  Blank lines and comment-only lines change nothing.  A comment written hard
  against the left margin inside a deeply indented block is ordinary in YAML,
  and closing eleven blocks because of it would fold away the rest of the
  document. }
procedure TLedYAMLSyn.ApplyFold;
var
  Next_: string;
begin
  FFoldDone := True;
  if BlankOrComment(FLineStr) then Exit;

  while (CurrentCodeFoldBlockLevel > 0) and
        (PtrInt(TopCodeFoldBlockType) >= FIndent) do
    EndCodeFoldBlock;

  { One line ahead, from the buffer the scan is running over.  A line with
    nothing under it opens nothing, which is what keeps a leaf from getting
    a chevron that folds no lines away. }
  if (CurrentLines = nil) or (LineIndex < 0) or
     (LineIndex + 1 >= CurrentLines.Count) then Exit;
  Next_ := CurrentLines[LineIndex + 1];
  if BlankOrComment(Next_) then Exit;
  if IndentOf(Next_) > FIndent then
    StartCodeFoldBlock(Pointer(PtrInt(FIndent)));
end;

{ --- scanning ------------------------------------------------------------- }

{ One piece of a quoted scalar: the opening quote and the text up to the
  first escape, an escape on its own, or the text up to the closing quote.
  Called again for each piece until the quote closes. }
procedure TLedYAMLSyn.ScanQuoted(AQuote: Char);
begin
  if FQuote = #0 then
  begin
    FQuote := AQuote;
    Inc(FRun);                                { the opening quote }
  end
  else if (FQuote = '"') and (FRun < FLineLen) and (FLine[FRun] = '\') then
  begin
    { An escape, drawn in its own colour the way medit draws it. }
    FTok := ytEscape;
    Inc(FRun);
    if FRun < FLineLen then Inc(FRun);
    Exit;
  end;

  FTok := ytString;
  while FRun < FLineLen do
  begin
    if (FQuote = '"') and (FLine[FRun] = '\') then Exit;   { next token }
    if FLine[FRun] = FQuote then
    begin
      Inc(FRun);
      FQuote := #0;
      Exit;
    end;
    Inc(FRun);
  end;
  { A quoted scalar may run on to the next line in YAML.  It is ended here
    anyway: carrying it would colour the rest of the file as a string on one
    unbalanced quote, which is a worse answer far more often. }
  FQuote := #0;
end;

{ A word that is not quoted: a number, one of YAML's literals, or plain
  text that is coloured as nothing at all -- which is what medit does with
  it too. }
procedure TLedYAMLSyn.ScanPlain;
var
  Start, Digits, Dots: Integer;
  W: string;
  AllNum: Boolean;
begin
  Start := FRun;
  while (FRun < FLineLen) and not (FLine[FRun] in [' ', #9, ',', '[', ']',
        '{', '}']) do
  begin
    { A '#' after a blank starts a comment, so it ends the word before it. }
    if (FLine[FRun] = '#') and (FRun > Start) and
       (FLine[FRun - 1] in [' ', #9]) then Break;
    Inc(FRun);
  end;
  W := Copy(FLineStr, Start + 1, FRun - Start);

  if (W = 'true') or (W = 'false') or (W = 'null') or (W = '~') or
     (W = 'True') or (W = 'False') or (W = 'Null') or
     (W = 'TRUE') or (W = 'FALSE') or (W = 'NULL') or
     (W = 'yes') or (W = 'no') or (W = 'on') or (W = 'off') or
     (W = 'Yes') or (W = 'No') or (W = 'On') or (W = 'Off') then
  begin
    FTok := ytLiteral;
    Exit;
  end;

  { A number, and which kind.  Worked out from the characters rather than by
    a conversion, because a conversion would accept things YAML does not and
    cost more than the scan it is part of. }
  Digits := 0;
  Dots := 0;
  AllNum := Length(W) > 0;
  for Start := 1 to Length(W) do
    case W[Start] of
      '0'..'9': Inc(Digits);
      '.': Inc(Dots);
      'e', 'E', '+', '-': ;
    else
      AllNum := False;
    end;
  if AllNum and (Digits > 0) and (Dots <= 1) then
  begin
    if (Dots = 1) or (Pos('e', LowerCase(W)) > 0) then
      FTok := ytFloat
    else
      FTok := ytInt;
    Exit;
  end;

  FTok := ytPunct;                            { plain text, left uncoloured }
end;

procedure TLedYAMLSyn.SetLine(const NewValue: string; LineNumber: Integer);
begin
  inherited SetLine(NewValue, LineNumber);
  FLineStr := NewValue;
  FLine := PChar(FLineStr);
  FLineLen := Length(FLineStr);
  FRun := 0;
  FTokenPos := 0;
  FFoldDone := False;
  FRestIsString := False;
  FRestIsComment := False;
  FQuote := #0;
  FIndent := IndentOf(FLineStr);

  { Still inside a block scalar?  Its text is everything indented further
    than the line that introduced it; a blank line is part of it too. }
  if FBlockPlus1 > 0 then
  begin
    if (FIndent >= FLineLen) or (FIndent > FBlockPlus1 - 1) then
      FRestIsString := True
    else
      FBlockPlus1 := 0;
  end;

  FAtKeyPos := not FRestIsString;
  Next;
end;

procedure TLedYAMLSyn.Next;
var
  Colon: Integer;
begin
  FTokenPos := FRun;

  if FRun >= FLineLen then
  begin
    if not FFoldDone then ApplyFold;
    FTok := ytNone;
    Exit;
  end;

  { Part way through a quoted scalar: the escape that stopped the last
    piece, or the text after it. }
  if FQuote <> #0 then
  begin
    ScanQuoted(FQuote);
    Exit;
  end;

  { Everything to the end of the line, for the two things that claim it. }
  if FRestIsComment or FRestIsString then
  begin
    if FRestIsComment then FTok := ytComment else FTok := ytString;
    FRun := FLineLen;
    Exit;
  end;

  case FLine[FRun] of
    ' ', #9:
      begin
        FTok := ytSpace;
        while (FRun < FLineLen) and (FLine[FRun] in [' ', #9]) do Inc(FRun);
        Exit;
      end;
    '#':
      begin
        FTok := ytComment;
        FRestIsComment := True;
        FRun := FLineLen;
        Exit;
      end;
    '%':
      if FTokenPos = 0 then
      begin
        FTok := ytDirective;
        FRun := FLineLen;
        Exit;
      end;
    '-':
      begin
        { A document marker, a sequence dash, or the start of a number. }
        if (FTokenPos = 0) and (FLineLen >= 3) and (FLine[1] = '-') and
           (FLine[2] = '-') then
        begin
          FTok := ytTag;
          Inc(FRun, 3);
          Exit;
        end;
        if (FRun + 1 >= FLineLen) or (FLine[FRun + 1] in [' ', #9]) then
        begin
          { A sequence entry.  What follows it may be a key of its own --
            "- name: x" -- so this does not end the key position. }
          FTok := ytPunct;
          Inc(FRun);
          Exit;
        end;
      end;
    '.':
      if (FTokenPos = 0) and (FLineLen >= 3) and (FLine[1] = '.') and
         (FLine[2] = '.') then
      begin
        FTok := ytTag;
        Inc(FRun, 3);
        Exit;
      end;
    '&', '*':
      begin
        FTok := ytAnchor;
        Inc(FRun);
        while (FRun < FLineLen) and not (FLine[FRun] in [' ', #9]) do Inc(FRun);
        FAtKeyPos := False;
        Exit;
      end;
    '!':
      begin
        FTok := ytTag;
        while (FRun < FLineLen) and not (FLine[FRun] in [' ', #9]) do Inc(FRun);
        FAtKeyPos := False;
        Exit;
      end;
    '|', '>':
      begin
        { A block scalar: the rest of this line is its header, and the lines
          under it are its text. }
        FTok := ytPunct;
        FRun := FLineLen;
        FBlockPlus1 := FIndent + 1;
        FAtKeyPos := False;
        Exit;
      end;
    ':', ',', '[', ']', '{', '}':
      begin
        FTok := ytPunct;
        Inc(FRun);
        { Past the colon is a value, never a key. }
        if FLine[FTokenPos] = ':' then FAtKeyPos := False;
        Exit;
      end;
  end;

  { A word.  At the head of a line it may be a key, and what says so is a
    colon further along followed by a blank. }
  if FAtKeyPos then
  begin
    Colon := KeyEndsAt;
    if Colon > FRun then
    begin
      FTok := ytKey;
      FRun := Colon;
      FAtKeyPos := False;
      Exit;
    end;
  end;

  if FLine[FRun] in ['"', ''''] then
  begin
    ScanQuoted(FLine[FRun]);
    FAtKeyPos := False;
    Exit;
  end;

  ScanPlain;
  FAtKeyPos := False;
end;

function TLedYAMLSyn.GetEol: Boolean;
begin
  Result := FTok = ytNone;
end;

function TLedYAMLSyn.GetToken: string;
begin
  Result := Copy(FLineStr, FTokenPos + 1, FRun - FTokenPos);
end;

procedure TLedYAMLSyn.GetTokenEx(out TokenStart: PChar;
  out TokenLength: Integer);
begin
  TokenStart := FLine + FTokenPos;
  TokenLength := FRun - FTokenPos;
end;

function TLedYAMLSyn.GetTokenAttribute: TSynHighlighterAttributes;
begin
  Result := FAttrs[FTok];
end;

function TLedYAMLSyn.GetTokenKind: Integer;
begin
  Result := Ord(FTok);
end;

function TLedYAMLSyn.GetTokenPos: Integer;
begin
  Result := FTokenPos;
end;

function TLedYAMLSyn.GetRange: Pointer;
begin
  CodeFoldRange.RangeType := Pointer(PtrUInt(FBlockPlus1));
  Result := inherited GetRange;
end;

procedure TLedYAMLSyn.SetRange(Value: Pointer);
begin
  inherited SetRange(Value);
  FBlockPlus1 := Integer(PtrUInt(CodeFoldRange.RangeType));
  FQuote := #0;
end;

procedure TLedYAMLSyn.ResetRange;
begin
  inherited ResetRange;
  FBlockPlus1 := 0;
  FQuote := #0;
end;

end.
