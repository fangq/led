{ LED - a lightweight editor.  Colouring a notebook.

  A notebook's buffer is two kinds of line mixed together, and they want
  opposite treatment.  The headers, the output labels and the output are
  LED's own words about the file, and they are coloured from what the
  document knows -- the same trick as the BJData structure view, where
  nothing is scanned because nothing needs to be.  The source lines are
  somebody's Python, and they want a Python highlighter: not an approximation
  of one, the real one, so that a notebook reads exactly like the same code
  in a .py file.

  So this highlighter delegates.  For a source line it hands the line to the
  language highlighter for that cell and passes its tokens straight through;
  for anything else it answers for itself.  Markdown cells go to the markdown
  highlighter the same way, which is why there are two inner highlighters and
  not one.

  The state that has to be carried is what makes this more than a lookup.  A
  docstring runs over several lines, and a highlighter knows that only
  because it is told where the previous line left off.

  The way to give it that is to give it a document.  A highlighter keeps its
  per-line state in a range list belonging to the text it is attached to --
  a grammar-driven one also keeps a side table there, and reads it by line
  number -- so one driven by hand with no text behind it reads whatever
  happens to be at that index.  On a real notebook that came out as an
  assertion inside the grammar engine, over and over, because its pattern
  state had a parent chain from nowhere.
 
  So a cell is copied into a little document of its own and the language
  highlighter is attached to that.  Then everything is as the highlighter
  expects: it scans the cell, keeps its state per line of it, and this unit
  asks it for the tokens of one line.  The copy is rebuilt when the cell
  changes, which the buffer says by way of a change handler rather than by
  being compared line against line.

  Which line is which comes from the document, live, through OnLineKind.  It
  cannot be a table here: the reader is typing, and lines move. }

unit Led.Syn.Notebook;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, SynEditHighlighter, SynEditHighlighterFoldBase,
  SynEditTypes, SynEditTextBuffer,
  Led.Syn.Factory;

type
  { What a line of a notebook buffer is, as far as colouring cares. }
  TLedNBLine = (
    nblGap,        // the blank line between cells: nothing to say
    nblHeader,     // [1] python ------
    nblOutLabel,   // out ------
    nblOutput,     // a line of output
    nblError,      // a line of output that came from a traceback
    nblSource);    // a line of a cell's own text

  { Asked about every line as it is painted.  ACell comes back as the cell
    the line belongs to and ALang as the language to colour it in: the
    notebook's own for a code cell, 'markdown' for a prose one, and whatever
    a cell magic says for a cell that opens with one.  A cell beginning
    %%octave is Octave however the file's metadata describes the notebook,
    and colouring it as Python would be wrong for every line of it. }
  TLedNBLineQuery = function(ALine: Integer; out ACell: Integer;
    out ALang: string): TLedNBLine of object;

  { Asked for the text of a line of the buffer, so that a cell can be rewound
    and run forward without a copy of the buffer being kept in here. }
  TLedNBTextQuery = function(ALine: Integer): string of object;

  TLedNBHighlighter = class(TSynCustomFoldHighlighter)
  private
    { One highlighter per language the file turns out to use, made on first
      sight and owned here.  Not the shared cached ones: the note of where a
      cell's scan got to would be invalidated by any other document
      tokenising in between. }
    FInners: TStringList;
    FOnLineKind: TLedNBLineQuery;
    FOnLineText: TLedNBTextQuery;

    { The line being tokenised and what it turned out to be. }
    FLine: string;
    FLineNumber: Integer;
    FKind: TLedNBLine;
    FCell: Integer;
    FInner: TSynCustomHighlighter;   // nil for a line LED answers for itself
    FDone: Boolean;                  // decoration: one token, then the end

    { The cell being coloured, as a document of its own, and which cell and
      which highlighter are in it.  FCellFirst is the line of the real buffer
      its first line came from, which is what maps one to the other. }
    FCellBuf: TSynEditStringList;
    FCellNo: Integer;
    FCellFirst: Integer;
    FCellHigh: TSynCustomHighlighter;

    FAttrs: array[TLedNBLine] of TSynHighlighterAttributes;
    function LineKind(ALine: Integer; out ACell: Integer;
      out ALang: string): TLedNBLine;
    function InnerFor(const ALang: string): TSynCustomHighlighter;
    function EnsureCell(ACell, ALine: Integer): Integer;
    function DepthOf(ALine: Integer): Integer;
  protected
    function GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes;
      override;
    function FoldBlockMinLevel(ALineIndex: TLineIdx;
      const AFilter: TSynFoldBlockFilter): integer; override; overload;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure SetLine(const NewValue: string; LineNumber: Integer); override;
    procedure Next; override;
    function GetEol: Boolean; override;
    function GetToken: string; override;
    procedure GetTokenEx(out TokenStart: PChar; out TokenLength: integer);
      override;
    function GetTokenAttribute: TSynHighlighterAttributes; override;
    function GetTokenKind: Integer; override;
    function GetTokenPos: Integer; override;

    { Asked what each line is.  Required: without it every line is plain. }
    property OnLineKind: TLedNBLineQuery read FOnLineKind write FOnLineKind;
    { Asked for the text of a line, so that a cell can be rewound and run
      forward without the buffer being copied in here. }
    property OnLineText: TLedNBTextQuery read FOnLineText write FOnLineText;

    { The language highlighters in use, so that the theme reaches them: they
      are this document's own instances, so nothing else re-themes them. }
    function InnerCount: Integer;
    function Inner(AIndex: Integer): TSynCustomHighlighter;

    class function GetLanguageName: string; override;
  end;

implementation

{ The scope each kind of line is coloured as -- theme scope names, not
  colours, so every scheme colours a notebook by the rules it already has.

  The header is a declaration: it says what follows and what it is.  The
  output label and the output are what the file says came back, and a
  traceback is an error, which every theme has a colour for and usually a
  loud one. }
const
  LineScope: array[TLedNBLine] of string = (
    'def.comment',           { nblGap      }
    'def.type',              { nblHeader   }
    'def.comment',           { nblOutLabel }
    'def.doc-comment',       { nblOutput   }
    'def.error',             { nblError    }
    'def.comment');          { nblSource -- never used: the inner answers }

constructor TLedNBHighlighter.Create(AOwner: TComponent);
var
  K, J: TLedNBLine;
  Existing: TSynHighlighterAttributes;
begin
  inherited Create(AOwner);
  { One attribute per distinct scope: a highlighter keeps its attributes in a
    list keyed by name and will not take the same name twice. }
  for K := Low(TLedNBLine) to High(TLedNBLine) do
  begin
    Existing := nil;
    for J := Low(TLedNBLine) to Pred(K) do
      if LineScope[J] = LineScope[K] then
      begin
        Existing := FAttrs[J];
        Break;
      end;
    if Existing <> nil then
    begin
      FAttrs[K] := Existing;
      Continue;
    end;
    FAttrs[K] := TSynHighlighterAttributes.Create(LineScope[K], LineScope[K]);
    AddAttribute(FAttrs[K]);
  end;
  FInners := TStringList.Create;
  FInners.OwnsObjects := True;
  FCellBuf := TSynEditStringList.Create;
  FCellNo := -1;
  FCellFirst := -1;
end;

destructor TLedNBHighlighter.Destroy;
begin
  if (FCellHigh <> nil) and (FCellBuf <> nil) then
    FCellHigh.DetachFromLines(FCellBuf);
  FInners.Free;
  FCellBuf.Free;
  inherited Destroy;
end;

{ The highlighter for a language, made once.  A language LED cannot colour is
  remembered as nothing rather than looked up again for every line, and its
  source then stays plain -- which is what a file of that language would get
  outside a notebook too. }
function TLedNBHighlighter.InnerFor(const ALang: string): TSynCustomHighlighter;
var
  i: Integer;
begin
  Result := nil;
  if ALang = '' then Exit;
  i := FInners.IndexOf(ALang);
  if i >= 0 then Exit(TSynCustomHighlighter(FInners.Objects[i]));
  Result := LedCreateHighlighter(ALang);
  FInners.AddObject(ALang, Result);
end;

function TLedNBHighlighter.InnerCount: Integer;
begin
  Result := FInners.Count;
end;

function TLedNBHighlighter.Inner(AIndex: Integer): TSynCustomHighlighter;
begin
  Result := TSynCustomHighlighter(FInners.Objects[AIndex]);
end;

class function TLedNBHighlighter.GetLanguageName: string;
begin
  Result := 'Jupyter notebook';
end;

function TLedNBHighlighter.LineKind(ALine: Integer; out ACell: Integer;
  out ALang: string): TLedNBLine;
begin
  ACell := -1;
  ALang := '';
  if Assigned(FOnLineKind) then
    Result := FOnLineKind(ALine, ACell, ALang)
  else
    Result := nblGap;
end;

{ How deeply a line is nested, which is all the folding needs.

  A cell is a block: it opens after its header and closes at the end of the
  cell, so the reader can shut a cell they are done with and see the shape of
  the notebook.  Its output is a block inside that one, because output is the
  part most worth hiding -- a cell that printed four hundred lines is four
  hundred lines between the reader and the next piece of code. }
function TLedNBHighlighter.DepthOf(ALine: Integer): Integer;
var
  Cell: Integer;
  Lang: string;
begin
  case LineKind(ALine, Cell, Lang) of
    nblHeader:   Result := 0;
    nblSource:   Result := 1;
    nblOutLabel: Result := 1;
    nblOutput,
    nblError:    Result := 2;
  else
    Result := 0;
  end;
end;

function TLedNBHighlighter.FoldBlockMinLevel(ALineIndex: TLineIdx;
  const AFilter: TSynFoldBlockFilter): integer;
begin
  { Worked out rather than looked up, for the reason the structure view's
    highlighter gives: SynEdit stores a line's fold levels as the state the
    next line starts from, and the last line has no next line. }
  Result := DepthOf(ALineIndex);
end;

{ Makes sure the little document holds the cell that ALine is in, with the
  right language highlighter attached to it, and answers which of its lines
  ALine is.  -1 when there is nothing to colour with.

  Rebuilt only when what it holds is not what is wanted, so painting down a
  cell costs one copy for the cell and a string comparison per line. }
function TLedNBHighlighter.EnsureCell(ACell, ALine: Integer): Integer;
var
  First, Last, i, Cell, Stop: Integer;
  Lang: string;
  Kind: TLedNBLine;
begin
  Result := -1;
  if (FInner = nil) or (not Assigned(FOnLineText)) then Exit;

  { The copy is reused while it is still the same cell, the same language and
    still says what the buffer says on the line being asked about.

    That last test is what notices an edit.  It is enough because SynEdit
    re-tokenises a changed line before it re-tokenises the lines after it:
    whichever line was typed into is the first one to arrive here with text
    that the copy disagrees with, and the copy is taken again then -- for
    that line and for every line below it. }
  if (FCellNo = ACell) and (FCellHigh = FInner) and (FCellFirst >= 0) then
  begin
    Result := ALine - FCellFirst;
    if (Result >= 0) and (Result < FCellBuf.Count) and
       (FCellBuf[Result] = FOnLineText(ALine)) then Exit;
    Result := -1;
  end;

  { How far the cell's own lines run, either side of the line asked about. }
  First := ALine;
  i := ALine - 1;
  while i >= 0 do
  begin
    Kind := LineKind(i, Cell, Lang);
    if (Kind <> nblSource) or (Cell <> ACell) then Break;
    First := i;
    Dec(i);
  end;
  { Bounded by the text as well as by the answers.  Asking past the end of
    the buffer is how this loop ran away once already, and a scan that trusts
    only what it is told has no way to stop if it is told wrongly. }
  Stop := MaxInt;
  if CurrentLines <> nil then Stop := CurrentLines.Count;
  Last := ALine;
  i := ALine + 1;
  while i < Stop do
  begin
    Kind := LineKind(i, Cell, Lang);
    if (Kind <> nblSource) or (Cell <> ACell) then Break;
    Last := i;
    Inc(i);
  end;

  { The highlighter is attached to the little document rather than to the
    notebook: this is the text it is being asked about, and a highlighter
    keeps its state per line of the text it is attached to. }
  if FCellHigh <> FInner then
  begin
    if FCellHigh <> nil then FCellHigh.DetachFromLines(FCellBuf);
    FCellHigh := FInner;
    FCellHigh.AttachToLines(FCellBuf);
  end;

  FCellBuf.BeginUpdate;
  try
    FCellBuf.Clear;
    for i := First to Last do
      FCellBuf.Add(FOnLineText(i));
  finally
    FCellBuf.EndUpdate;
  end;

  FCellNo := ACell;
  FCellFirst := First;

  { Scanned in one go, which is what carries a docstring from its first line
    to its last. }
  FInner.CurrentLines := FCellBuf;
  FInner.ScanAllRanges;

  Result := ALine - First;
  if (Result < 0) or (Result >= FCellBuf.Count) then Result := -1;
end;

procedure TLedNBHighlighter.SetLine(const NewValue: string;
  LineNumber: Integer);
var
  Here, Next_, Mapped: Integer;
  Lang: string;
begin
  inherited SetLine(NewValue, LineNumber);
  FLine := NewValue;
  FLineNumber := LineNumber;
  FDone := False;
  FKind := LineKind(LineNumber, FCell, Lang);

  FInner := nil;
  if FKind = nblSource then
  begin
    FInner := InnerFor(Lang);
    if FInner <> nil then
    begin
      Mapped := EnsureCell(FCell, LineNumber);
      if Mapped < 0 then
        FInner := nil
      else
      begin
        FInner.CurrentLines := FCellBuf;
        { Positioned through SynEdit's own entry point, which sets the range
          from the line before it in the little document -- the thing that
          could not be done while the highlighter had no document. }
        FInner.StartAtLineIndex(Mapped);
      end;
    end;
  end;

  { The fold blocks, from the depths either side of this line -- the same
    shape as the structure view's, because the nesting is known rather than
    scanned for. }
  Here := DepthOf(LineNumber);
  while CodeFoldRange.CodeFoldStackSize > Here do EndCodeFoldBlock;
  Next_ := DepthOf(LineNumber + 1);
  while Next_ > CodeFoldRange.CodeFoldStackSize do StartCodeFoldBlock(nil);
end;

procedure TLedNBHighlighter.Next;
begin
  if FInner <> nil then
  begin
    FInner.Next;
    Exit;
  end;
  FDone := True;
end;

function TLedNBHighlighter.GetEol: Boolean;
begin
  if FInner <> nil then Exit(FInner.GetEol);
  Result := FDone or (FLine = '');
end;

function TLedNBHighlighter.GetToken: string;
begin
  if FInner <> nil then Exit(FInner.GetToken);
  Result := FLine;
end;

procedure TLedNBHighlighter.GetTokenEx(out TokenStart: PChar;
  out TokenLength: integer);
begin
  if FInner <> nil then
  begin
    FInner.GetTokenEx(TokenStart, TokenLength);
    Exit;
  end;
  TokenStart := PChar(FLine);
  TokenLength := Length(FLine);
end;

function TLedNBHighlighter.GetTokenAttribute: TSynHighlighterAttributes;
begin
  if FInner <> nil then Exit(FInner.GetTokenAttribute);
  Result := FAttrs[FKind];
end;

function TLedNBHighlighter.GetTokenKind: Integer;
begin
  if FInner <> nil then Exit(FInner.GetTokenKind);
  Result := Ord(FKind);
end;

function TLedNBHighlighter.GetTokenPos: Integer;
begin
  if FInner <> nil then Exit(FInner.GetTokenPos);
  Result := 0;
end;

function TLedNBHighlighter.GetDefaultAttribute(
  Index: Integer): TSynHighlighterAttributes;
begin
  case Index of
    SYN_ATTR_COMMENT: Result := FAttrs[nblOutLabel];
    SYN_ATTR_KEYWORD: Result := FAttrs[nblHeader];
  else
    Result := nil;
  end;
end;

end.
