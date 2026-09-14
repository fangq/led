{ LED - a lightweight editor.  Colouring the BJData structure view.

  A highlighter that does not read the text.

  SynEdit gets its colours from a highlighter and from nowhere else, so there
  has to be one -- but a highlighter is only obliged to answer "what is the
  token at this position", not to work the answer out by scanning.  The walk
  that rendered these lines already knew: this record is a string, that one
  is a float, this column is a key and that one is the count LED wrote
  because the file does not carry it.  Led.Core.BJDView hands that over as
  spans, and this walks the spans.

  The alternative was a grammar -- a .lang converted like the other hundred
  and twenty-seven -- and it worked, but it was reading back what LED had
  just written.  Everything ambiguous to a reader of the line is unambiguous
  here: a key with two spaces in it, a string whose contents look like one of
  LED's summaries, an angle bracket inside a value.  And a grammar cannot
  tell an elided integer from an elided string, because by then both are the
  same sentence about bytes nobody is showing.

  The attributes are named for the theme scopes LED already uses -- the same
  'def.identifier', 'def.type', 'def.string' a converted grammar emits -- so
  every scheme colours this view by the rules it already has for every other
  language, including the readability floor.  Nothing here picks a colour. }
unit Led.Syn.BJData;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, SynEditHighlighter, SynEditTypes,
  Led.Core.BJDView;

type

  { TLedBJHighlighter }

  TLedBJHighlighter = class(TSynCustomHighlighter)
  private
    FRows: TLedBJRows;
    FLine: string;
    FLineNumber: Integer;
    FFields: TLedBJFields;
    FField: Integer;          { which span the cursor is on, -1 past the end }
    FTokenStart: Integer;     { 0-based, as SynEdit counts }
    FTokenLen: Integer;
    FTokenKind: TLedBJFieldKind;
    FAttrs: array[TLedBJFieldKind] of TSynHighlighterAttributes;
    FSpace: TSynHighlighterAttributes;
    procedure StepTo(AStart: Integer);
  protected
    function GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes;
      override;
  public
    constructor Create(AOwner: TComponent); override;

    procedure SetLine(const NewValue: string; LineNumber: Integer); override;
    procedure Next; override;
    function GetEol: Boolean; override;
    function GetToken: string; override;
    procedure GetTokenEx(out TokenStart: PChar; out TokenLength: integer);
      override;
    function GetTokenAttribute: TSynHighlighterAttributes; override;
    function GetTokenKind: Integer; override;
    function GetTokenPos: Integer; override;

    { The rows the view was rendered from.  Set once per load; a row's spans
      are computed as each line is asked about, which costs an array walk per
      line and no parsing at all. }
    procedure SetRows(const ARows: TLedBJRows);

    class function GetLanguageName: string; override;
  end;

implementation

{ The scope each field is coloured as.  These are theme scope names, not
  colours: 'def.identifier' is what a converted grammar would have emitted for
  the same thing, and Led.Syn.Factory turns it into the theme's def:identifier
  on its way to a colour.

  What the file says is data -- a key, a marker, a value.  What LED says about
  it is a remark, and remarks recede: the offsets it prints down the left, the
  counts it worked out, the summaries of payloads it is not showing.  That
  distinction is the whole point of colouring this view, because it is what
  tells a number the file contains from a number LED counted. }
const
  FieldScope: array[TLedBJFieldKind] of string = (
    'def.comment',           { bjfOffset   }
    'def.identifier',        { bjfKey      }
    'def.type',              { bjfMarker   }
    'def.string',            { bjfString   }
    'def.decimal',           { bjfNumber   }
    'def.floating-point',    { bjfFloat    }
    'def.special-constant',  { bjfConstant }
    'def.comment');          { bjfSummary  }

constructor TLedBJHighlighter.Create(AOwner: TComponent);
var
  K, J: TLedBJFieldKind;
  Existing: TSynHighlighterAttributes;
begin
  inherited Create(AOwner);
  { One attribute per scope, shared by the kinds that use it -- the offsets
    and the summaries are both remarks and both def.comment, and a
    highlighter keeps its attributes in a list keyed by name that will not
    take the same name twice. }
  for K := Low(TLedBJFieldKind) to High(TLedBJFieldKind) do
  begin
    Existing := nil;
    for J := Low(TLedBJFieldKind) to Pred(K) do
      if FieldScope[J] = FieldScope[K] then
      begin
        Existing := FAttrs[J];
        Break;
      end;
    if Existing <> nil then
    begin
      FAttrs[K] := Existing;
      Continue;
    end;
    FAttrs[K] := TSynHighlighterAttributes.Create(FieldScope[K], FieldScope[K]);
    AddAttribute(FAttrs[K]);
  end;
  { The gaps between fields.  A token of its own rather than part of the
    field beside it, so that a field's span is exactly the field. }
  FSpace := TSynHighlighterAttributes.Create('Space', 'Space');
  AddAttribute(FSpace);
  FField := -1;
end;

class function TLedBJHighlighter.GetLanguageName: string;
begin
  Result := 'BJData structure';
end;

procedure TLedBJHighlighter.SetRows(const ARows: TLedBJRows);
begin
  FRows := ARows;
end;

function TLedBJHighlighter.GetDefaultAttribute(
  Index: Integer): TSynHighlighterAttributes;
begin
  { The generic requests SynEdit makes of any highlighter.  Whitespace is the
    only one this view has an opinion about; the rest have no counterpart in
    a rendered structure. }
  case Index of
    SYN_ATTR_WHITESPACE: Result := FSpace;
    SYN_ATTR_IDENTIFIER: Result := FAttrs[bjfKey];
    SYN_ATTR_KEYWORD:    Result := FAttrs[bjfMarker];
    SYN_ATTR_STRING:     Result := FAttrs[bjfString];
    SYN_ATTR_NUMBER:     Result := FAttrs[bjfNumber];
    SYN_ATTR_COMMENT:    Result := FAttrs[bjfSummary];
  else
    Result := nil;
  end;
end;

procedure TLedBJHighlighter.SetLine(const NewValue: string;
  LineNumber: Integer);
begin
  FLine := NewValue;
  FLineNumber := LineNumber;
  SetLength(FFields, 0);
  { LineNumber is 0-based and the rows are in the order they were rendered,
    so the row for a line is the line's own index.  A line past the rows --
    an error message appended to the view, or a buffer out of step for an
    instant during a reload -- simply has no fields and is left plain. }
  if (LineNumber >= 0) and (LineNumber <= High(FRows)) then
    FFields := LedBJRowFields(FRows[LineNumber]);
  FTokenStart := 0;
  FTokenLen := 0;
  FField := -1;
  StepTo(1);
end;

{ Positions the cursor on whatever begins at the 1-based column AStart: the
  span that starts there, or the gap between spans. }
procedure TLedBJHighlighter.StepTo(AStart: Integer);
var
  i, NextStart: Integer;
begin
  FTokenStart := AStart - 1;
  if AStart > Length(FLine) then
  begin
    FTokenLen := 0;
    FField := -1;
    Exit;
  end;

  for i := 0 to High(FFields) do
    if FFields[i].Start = AStart then
    begin
      FField := i;
      FTokenKind := FFields[i].Kind;
      FTokenLen := FFields[i].Len;
      { A span that runs past the end of the line -- which should not happen,
        but a truncated buffer is not worth a crash. }
      if FTokenStart + FTokenLen > Length(FLine) then
        FTokenLen := Length(FLine) - FTokenStart;
      Exit;
    end;

  { Between spans: run to the next one, or to the end of the line. }
  FField := -1;
  NextStart := Length(FLine) + 1;
  for i := 0 to High(FFields) do
    if (FFields[i].Start > AStart) and (FFields[i].Start < NextStart) then
      NextStart := FFields[i].Start;
  FTokenLen := NextStart - AStart;
end;

procedure TLedBJHighlighter.Next;
begin
  if FTokenLen <= 0 then
  begin
    FTokenStart := Length(FLine);
    Exit;
  end;
  StepTo(FTokenStart + FTokenLen + 1);
end;

function TLedBJHighlighter.GetEol: Boolean;
begin
  Result := FTokenStart >= Length(FLine);
end;

function TLedBJHighlighter.GetToken: string;
begin
  Result := Copy(FLine, FTokenStart + 1, FTokenLen);
end;

procedure TLedBJHighlighter.GetTokenEx(out TokenStart: PChar;
  out TokenLength: integer);
begin
  TokenLength := FTokenLen;
  if FLine = '' then
    TokenStart := nil
  else
    TokenStart := @FLine[FTokenStart + 1];
end;

function TLedBJHighlighter.GetTokenAttribute: TSynHighlighterAttributes;
begin
  if FField < 0 then
    Result := FSpace
  else
    Result := FAttrs[FTokenKind];
end;

function TLedBJHighlighter.GetTokenKind: Integer;
begin
  if FField < 0 then
    Result := -1
  else
    Result := Ord(FTokenKind);
end;

function TLedBJHighlighter.GetTokenPos: Integer;
begin
  Result := FTokenStart;
end;

end.
