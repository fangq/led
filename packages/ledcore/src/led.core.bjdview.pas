// led - a lightweight editor.  Binary JData as a readable structure.
//
// A BJData file is JSON with the punctuation replaced by one-byte type markers
// and the numbers stored raw.  Its keys and markers are plain ASCII, so a hex
// dump of one is *almost* readable -- which is worse than useless, because it
// invites you to squint at it.  This renders the structure instead: one line
// per record, indented by container depth, each line carrying the type marker,
// the length where there is one, and the value.
//
//        0  {                     object, 1 item
//        1    SNIRFData  {         object, 8 items
//       13      formatVersion  S #3    "1.0"
//      154      TimeUnit  C            's'
//      201      dataTimeSeries  Z      null
//      755      data  [$U#[837597]     <837597 values, 837597 bytes>
//
// The walk is over TBJValue, the library's cursor, not over a parsed tree.
// That matters at the sizes these files reach: a cursor is two pointers into
// the buffer led already holds, so rendering a 50 MB file allocates nothing
// but the rows it shows, and every row knows the bytes it came from -- which
// is what makes editing in place possible later.
//
// Big payloads are elided rather than printed.  The files this exists for are
// scientific ones: a mesh here has typed arrays of 837,597 and 656,162
// elements, and a converted-JSON file has millions of small records.  Neither
// is readable in full and neither should be turned into text.  An elided row
// says what it is hiding, and knows how to produce it on request.
//
// Only Classes, SysUtils and the vendored bjdata unit: this is on ledcore's
// path and the nogui CI job keeps it honest.

unit Led.Core.BJDView;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, bjdata;

type
  { One rendered record.  Value is the cursor it came from, so a caller that
    wants to edit has what TryPatch needs without looking the row up again. }
  TLedBJRow = record
    Offset: PtrUInt;      // where the record starts in the file
    Depth: Integer;       // container nesting, 0 at the root
    Key: string;          // the object key, or '' inside an array
    Marker: string;       // 'S U 3', '[$U#24', '{' -- what the bytes say
    Text: string;         // the payload, rendered, possibly elided
    Elided: Boolean;      // Text is a summary; the whole value is larger
    Value: TBJValue;      // the cursor, for editing
  end;
  TLedBJRows = array of TLedBJRow;

const
  { Above these a value is summarised rather than printed.  The reference
    viewers in the bjdata repository use the same two numbers, so a file reads
    about the same here as it does through njv. }
  LedBJMaxElements = 100;
  LedBJMaxStringLen = 200;

  { How far a row's columns are apart.  Fixed, so the markers line up down the
    page and the eye can run along one column. }
  LedBJOffsetWidth = 8;
  LedBJIndentWidth = 2;

{ Whether ARaw could be BJData at all: a cheap look at the first byte, for
  deciding which view to open a file in.  It answers for the shape, not the
  contents -- a file that starts plausibly and is rubbish afterwards is caught
  by the parse, not here. }
function LedBJLooksBJData(const ARaw: string): Boolean;

{ Whether AFileName's extension is one of the binary JData ones.  Note .jdat
  is *not* among them: that is text JData, i.e. JSON, and belongs in the text
  view. }
function LedBJIsBJDataName(const AFileName: string): Boolean;

{ Walks ARaw and fills ARows.  Raises EBJData with a byte offset when the
  bytes are not BJData. }
procedure LedBJWalk(const ARaw: string; out ARows: TLedBJRows);

{ One row as it appears in the buffer. }
function LedBJRowText(const ARow: TLedBJRow): string;

{ Every row, LF-separated, no trailing newline -- the same contract
  LedHexDump keeps, so the buffer does not gain a phantom last line. }
function LedBJRender(const ARaw: string; out ARows: TLedBJRows): string;

{ The same walk, but it never raises -- this is what decides how a file opens.

  True means the bytes are BJData the whole way down and ARows is the view.
  False means they stop being BJData somewhere, and then AError is the
  parser's own complaint and AErrorOffset is the byte to look at: the first
  one that could not be read.  The caller opens such a file as a hex dump
  with the caret there, because a half-parsed structure view invites the
  reader to trust rows that may only look right.

  Finding that offset is the reason the walk records failures rather than
  raising them.  An exception unwinds to the top and takes the position with
  it; worse, a container's child count is obtained by walking the container,
  so the root row alone traverses the whole file and one bad byte anywhere
  used to surface as a failure at byte 0. }
function LedBJTryWalk(const ARaw: string; out ARows: TLedBJRows;
  out AError: string; out AErrorOffset: PtrUInt): Boolean;

implementation

const
  BJDataExts: array[0..6] of string =
    ('.bjd', '.bnii', '.bmsh', '.bnirs', '.beeg', '.bmeg', '.jdb');

function LedBJIsBJDataName(const AFileName: string): Boolean;
var
  Ext: string;
  i: Integer;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  for i := Low(BJDataExts) to High(BJDataExts) do
    if Ext = BJDataExts[i] then Exit(True);
  Result := False;
end;

function LedBJLooksBJData(const ARaw: string): Boolean;
begin
  { Every BJData document opens with a type marker, and in practice always a
    container.  A text JData file opens with an object marker too, so this
    cannot be the whole test -- the caller pairs it with the extension and, failing that,
    with whether the parse succeeds. }
  Result := (ARaw <> '') and
            (ARaw[1] in ['{', '[', 'Z', 'T', 'F', 'i', 'U', 'I', 'u',
                         'l', 'm', 'L', 'M', 'h', 'd', 'D', 'S', 'C',
                         'H', 'B', 'N', 'E']);
end;

{ The marker column: what the bytes actually say, in the spec's own notation
  so it can be compared against a hex dump or the specification by eye. }
function MarkerText(const AValue: TBJValue): string;
var
  m: AnsiChar;
  i: Integer;
begin
  m := AValue.Marker;
  { Kind calls an SoA record an object, so it has to be asked about first or
    it would print a bare object marker and lose the one thing that matters
    about it. }
  if AValue.IsSoA then
    Exit(m + '${...}#');
  case AValue.Kind of
    bjkArray, bjkObject:
      { Just the marker.  The child count goes in the value column, because
        Count is derived -- a container written plainly has no count byte, and
        printing one here would claim the file says something it does not. }
      Result := m;
    bjkNDArray:
      begin
        Result := Format('[$%s#[', [AValue.ElemMarker]);
        for i := 0 to AValue.DimCount - 1 do
        begin
          if i > 0 then Result := Result + ' ';
          Result := Result + IntToStr(AValue.Dim[i]);
        end;
        Result := Result + ']';
        if AValue.ColumnMajor then Result := Result + ' col';
      end;
    bjkString:
      { m, not a literal 'S': a char is kind bjkString with marker 'C', and
        saying 'S' for it would misreport the byte that is actually there. }
      Result := Format('%s #%d', [m, AValue.TextLength]);
  else
    Result := m;
  end;
end;

function Ellipsis(const AText: string; AMax: Integer): string;
begin
  { Both ends kept, because the interesting part of a long string is as often
    its tail -- a path, a URL, a units suffix -- as its head. }
  if Length(AText) <= AMax then Exit(AText);
  Result := Copy(AText, 1, AMax div 2) + ' ... ' +
            Copy(AText, Length(AText) - AMax div 2 + 1, AMax div 2);
end;

function QuoteText(const AText: string): string;
begin
  Result := '"' + Ellipsis(AText, LedBJMaxStringLen) + '"';
end;

{ The value column for something that is not a container. }
function ScalarText(const AValue: TBJValue; out AElided: Boolean): string;
begin
  AElided := False;
  case AValue.Kind of
    bjkNull:    Result := 'null';
    bjkNoOp:    Result := 'no-op';
    bjkBoolean: if AValue.AsBoolean then Result := 'true' else Result := 'false';
    bjkInt:     Result := IntToStr(AValue.AsInt64);
    bjkUInt:    Result := IntToStr(AValue.AsQWord);
    bjkFloat:   Result := BJFloatToStr(AValue.AsDouble);
    bjkString:
      begin
        AElided := AValue.TextLength > LedBJMaxStringLen;
        if AValue.Marker = 'C' then
          Result := '''' + AValue.AsString + ''''
        else
          Result := QuoteText(AValue.AsString);
      end;
    bjkExtension:
      { The type id lives on the tree, not on the cursor, and a walk that
        materialised a node just to name it would defeat the point. }
      Result := '<extension>';
  else
    Result := '';
  end;
end;

{ The value column for an ND array: never its contents.  A packed array is the
  reason these files are big, and printing 837,597 numbers helps nobody. }
{ A packed array is summarised by shape, with one exception: a short
  one-dimensional one is a vector, and a vector is a single fact.  A NIfTI
  Dim of [50, 53, 44] read as "3 values, 3 bytes" tells the reader nothing
  they came for, and it is the same uniform, non-container array that the
  inline rule already applies to when it is written the unpacked way.

  Only 1-D: the elements of a matrix do not mean anything laid end to end,
  and there the shape really is the point.  Above the element cap it goes
  back to a summary, because that is where these files get their size. }
function NDArrayText(const AValue: TBJValue): string;
var
  i, n: Int64;
  Packed_: Boolean;
begin
  n := AValue.ElementCount;
  if (AValue.DimCount = 1) and (n <= LedBJMaxElements) then
  begin
    Packed_ := BJKindOf(AValue.ElemMarker) = bjkFloat;
    Result := '[';
    for i := 0 to n - 1 do
    begin
      if i > 0 then Result := Result + ', ';
      if Packed_ then
        Result := Result + BJFloatToStr(AValue.ElemAsDouble(i))
      else
        Result := Result + IntToStr(AValue.ElemAsInt64(i));
    end;
    Exit(Result + ']');
  end;

  Result := Format('<%d values, %d bytes>',
    [AValue.ElementCount, AValue.DataSize]);
end;

{ An array of scalars is one line, not one line per element.

  [2, 3, 4] as three indented rows is noise: the reader wants the vector, and
  a dimension triple or an RGB colour is a single fact.  So an array whose
  elements are all non-containers is folded into its own row and its children
  are not walked at all.  A mixed or nested array keeps the row-per-element
  form, because there the structure is the point.

  Returns False when a container turns up, and the caller then walks it
  normally -- the enumerator is two pointers, so starting again costs nothing. }
function TryInlineArray(const AValue: TBJValue; out AText: string;
  out AElided: Boolean): Boolean;
var
  It: TBJIterator;
  Parts: string;
  n: Integer;
  Ignored: Boolean;
begin
  Result := False;
  AText := '';
  AElided := False;
  if AValue.Kind <> bjkArray then Exit;

  Parts := '';
  n := 0;
  It := AValue.GetEnumerator;
  while It.MoveNext do
  begin
    if It.Current.IsContainer or It.Current.IsNDArray then Exit;
    if n >= LedBJMaxElements then
    begin
      { Past the point of reading.  The count is already on the row, so this
        only has to say that it stops rather than ends. }
      AElided := True;
      Parts := Parts + ', ...';
      Break;
    end;
    if n > 0 then Parts := Parts + ', ';
    Parts := Parts + ScalarText(It.Current, Ignored);
    Inc(n);
  end;

  AText := '[' + Parts + ']';
  Result := True;
end;

type
  { The walk records a failure rather than raising it.

    An exception thrown from the bottom of the recursion unwinds every frame
    above it, and the rows already gathered come back with no indication of
    where they stopped being trustworthy.  Worse, the child count of a
    container is obtained by walking that container, so the very first thing
    the root row does is traverse the whole file -- one bad byte anywhere and
    the root itself raises, before a single child has been rendered.  That is
    why a truncated file used to show two rows.

    So Failed is set, the walk unwinds by returning, and every complete row
    below the break is kept.  LedBJWalk turns Failed back into an exception
    for the callers that want one. }
  TWalker = record
    Base: PByte;
    Rows: TLedBJRows;
    Count: Integer;
    Depth: Integer;       // where the walk stopped, for the error row
    Failed: Boolean;
    ErrMsg: string;
    procedure Add(const AKey: string; ADepth: Integer; const AValue: TBJValue);
    procedure Fail(E: Exception; ADepth: Integer);
    function StopOffset: PtrUInt;
    procedure Walk(const AKey: string; ADepth: Integer; const AValue: TBJValue);
  end;

{ The first byte that could not be read.

  The last row is the deepest record that came out whole, so the damage
  starts where that record ends -- except when the last row is itself the
  record that failed, and then asking its size fails too and its own offset
  is the answer.  Both cases are what the reader wants the caret on. }
function TWalker.StopOffset: PtrUInt;
var
  Last: Integer;
begin
  Result := 0;
  if Count = 0 then Exit;
  Last := Count - 1;
  Result := Rows[Last].Offset;
  try
    Result := Result + Rows[Last].Value.Size;
  except
    on E: Exception do ;   // the last row is the unreadable one
  end;
end;

procedure TWalker.Fail(E: Exception; ADepth: Integer);
begin
  if Failed then Exit;          // the first break is the informative one
  Failed := True;
  ErrMsg := E.Message;
  Depth := ADepth;
end;

procedure TWalker.Add(const AKey: string; ADepth: Integer;
  const AValue: TBJValue);
begin
  if Count >= Length(Rows) then
    SetLength(Rows, Length(Rows) * 2 + 64);
  Rows[Count].Offset := AValue.BytePos(Base);
  Rows[Count].Depth := ADepth;
  Rows[Count].Key := AKey;
  Rows[Count].Marker := MarkerText(AValue);
  Rows[Count].Value := AValue;
  Rows[Count].Elided := False;
  Rows[Count].Text := '';
  Inc(Count);
end;

procedure TWalker.Walk(const AKey: string; ADepth: Integer;
  const AValue: TBJValue);
var
  Here: Integer;
  Elided, Known: Boolean;
  It: TBJIterator;
  Inline_: string;
  n: SizeInt;
  Taken: Integer;
begin
  Here := Count;
  Depth := ADepth;
  Add(AKey, ADepth, AValue);

  { A structure-of-arrays record stores its fields as parallel columns, so
    there are no elements to walk -- the cursor refuses Count and Item and
    says to use ToData, which would materialise the whole thing.  These are
    the largest records in the corpus (one here is 52 MB), so it is summarised
    like a packed array and left alone.

    Its field names are not shown: the schema is readable only through the
    library's own reader, and hand-parsing it here would duplicate logic that
    is free to change underneath us.  Size is public and true, so that is what
    is reported. }
  if AValue.IsSoA then
  begin
    try
      Rows[Here].Text := Format('structure of arrays, %d bytes, not expanded',
                                [AValue.Size]);
    except
      on E: Exception do begin Fail(E, ADepth); Exit; end;
    end;
    Rows[Here].Elided := True;
    Exit;
  end;

  case AValue.Kind of
    bjkNDArray:
      try
        Rows[Here].Text := NDArrayText(AValue);
      except
        on E: Exception do begin Fail(E, ADepth); Exit; end;
      end;

    bjkArray, bjkObject:
      begin
        { A flat array is its own row and has no children of its own. }
        try
          if TryInlineArray(AValue, Inline_, Elided) then
          begin
            Rows[Here].Text := Inline_;
            Rows[Here].Elided := Elided;
            Exit;
          end;
        except
          on E: Exception do begin Fail(E, ADepth); Exit; end;
        end;

        { Counting means walking, so this is the first thing that can fail on
          a damaged file -- and it must not stop the children being shown.
          An uncounted container still gets its rows; it just cannot say how
          many there will be. }
        Known := True;
        try
          n := AValue.Count;
        except
          on E: Exception do begin Known := False; n := 0; end;
        end;

        if not Known then
          Rows[Here].Text := '? items'
        else if n = 1 then
          Rows[Here].Text := '1 item'
        else
          Rows[Here].Text := Format('%d items', [n]);

        { Elided containers are not walked at all -- that is the whole point
          at these sizes.  The row keeps its cursor, so expanding one later is
          a walk from here rather than a re-parse of the file. }
        if Known and (n > LedBJMaxElements) then
        begin
          Rows[Here].Elided := True;
          Rows[Here].Text := Rows[Here].Text + ', not shown';
          Exit;
        end;

        { The iterator, not Count + Item(i): a cursor has no index, so Item
          walks from the front and the loop would be quadratic.  It also hands
          back the key and the value together, which is what an object needs.

          MoveNext is what reads the next record, so it is where damage shows
          up; guarding it is what lets the good children before it survive. }
        It := AValue.GetEnumerator;
        Taken := 0;
        while True do
        begin
          try
            if not It.MoveNext then Break;
          except
            on E: Exception do begin Fail(E, ADepth + 1); Exit; end;
          end;

          { A container whose count could not be read has no ceiling from
            Count, so it needs one here or a corrupt length could spin. }
          if not Known then
          begin
            if Taken >= LedBJMaxElements then
            begin
              Rows[Here].Elided := True;
              Rows[Here].Text := Rows[Here].Text + ', not all shown';
              Break;
            end;
            Inc(Taken);
          end;

          if AValue.Kind = bjkObject then
            Walk(It.Key, ADepth + 1, It.Current)
          else
            Walk('', ADepth + 1, It.Current);
          if Failed then Exit;
        end;
      end;
  else
    try
      Rows[Here].Text := ScalarText(AValue, Elided);
      Rows[Here].Elided := Elided;
    except
      on E: Exception do begin Fail(E, ADepth); Exit; end;
    end;
  end;
end;

{ Pin the failure to an exact byte.

  The cursor walk can only say where the last record that read cleanly ended,
  which on a damaged file is the boundary *before* the bad bytes rather than
  the bad byte itself.  The tree reader keeps a running position and puts it
  in its message -- "... at byte offset 669" -- so a second pass over a file
  already known to be broken buys a caret that lands on the byte the parser
  actually choked on.

  Only broken files pay for it, and the parse stops where the damage is, so
  the work is bounded by the good prefix.  If anything about that second pass
  disagrees -- a different message, no offset, a position past the end -- the
  walk's own answer stands, because a caret in roughly the right place beats
  one in confidently the wrong place. }
procedure PreciseOffset(const ARaw: string; var AError: string;
  var AOffset: PtrUInt);
const
  Tail = ' at byte offset ';
var
  Node: TBJData;
  Msg: string;
  p: Integer;
  n: Int64;
begin
  Msg := '';
  Node := nil;
  try
    try
      Node := TBJData.Parse(ARaw[1], Length(ARaw));
    except
      on E: Exception do Msg := E.Message;
    end;
  finally
    Node.Free;
  end;
  if Msg = '' then Exit;

  p := Pos(Tail, Msg);
  if p = 0 then Exit;

  n := StrToInt64Def(Copy(Msg, p + Length(Tail), Length(Msg)), -1);
  if (n < 0) or (n > Length(ARaw)) then Exit;

  AOffset := n;
  AError := Msg;
end;

function LedBJTryWalk(const ARaw: string; out ARows: TLedBJRows;
  out AError: string; out AErrorOffset: PtrUInt): Boolean;
var
  W: TWalker;
  Root: TBJValue;
begin
  ARows := nil;
  AError := '';
  AErrorOffset := 0;
  Result := True;
  if ARaw = '' then Exit;

  W.Base := PByte(@ARaw[1]);
  W.Rows := nil;
  W.Count := 0;
  W.Depth := 0;
  W.Failed := False;
  W.ErrMsg := '';
  Root := TBJValue.Create(W.Base, Length(ARaw));

  { Walk records its own failures, so the only thing left to catch here is a
    fault it did not anticipate. }
  try
    W.Walk('', 0, Root);
  except
    on E: Exception do W.Fail(E, W.Depth);
  end;

  SetLength(W.Rows, W.Count);
  ARows := W.Rows;
  if not W.Failed then Exit;

  AError := W.ErrMsg;
  AErrorOffset := W.StopOffset;
  Result := False;
  PreciseOffset(ARaw, AError, AErrorOffset);
end;

procedure LedBJWalk(const ARaw: string; out ARows: TLedBJRows);
var
  Err: string;
  Where: PtrUInt;
begin
  { One walk, two faces.  Callers that want an exception -- the tests, and
    anything treating "is this BJData" as a yes or no -- get the library's own
    message, because that is the one that says what is wrong with the bytes. }
  if not LedBJTryWalk(ARaw, ARows, Err, Where) then
  begin
    ARows := nil;
    raise EBJData.Create(Err);
  end;
end;

function LedBJRowText(const ARow: TLedBJRow): string;
var
  Left: string;
begin
  Left := StringOfChar(' ', ARow.Depth * LedBJIndentWidth);
  if ARow.Key <> '' then
    Left := Left + ARow.Key + '  ';
  Result := Format('%*d  %s%s', [LedBJOffsetWidth, ARow.Offset, Left,
                                 ARow.Marker]);
  if ARow.Text <> '' then
    Result := Result + '  ' + ARow.Text;
end;

function RowsToText(const ARows: TLedBJRows): string;
var
  L: TStringList;
  i: Integer;
begin
  Result := '';
  if Length(ARows) = 0 then Exit;

  L := TStringList.Create;
  try
    L.LineBreak := #10;
    for i := 0 to High(ARows) do
      L.Add(LedBJRowText(ARows[i]));
    Result := L.Text;
  finally
    L.Free;
  end;
  { Same as LedHexDump: the buffer would count a trailing LF as another line. }
  if (Result <> '') and (Result[Length(Result)] = #10) then
    SetLength(Result, Length(Result) - 1);
end;

function LedBJRender(const ARaw: string; out ARows: TLedBJRows): string;
begin
  LedBJWalk(ARaw, ARows);
  Result := RowsToText(ARows);
end;

end.
