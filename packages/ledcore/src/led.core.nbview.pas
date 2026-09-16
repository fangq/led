// led - a lightweight editor.  A notebook, rendered as lines.
//
// The structure view for BJData turned a file into rows and let SynEdit show
// them; this does the same for a notebook, and for the same reason: there is
// no editable rich-text or HTML control on this toolkit, and the thing LED
// does have is a very good text editor.  So a notebook becomes one buffer of
// lines, each of which knows what it is.
//
//   [1] python ---------------------------
//   import numpy as np
//   x = np.arange(5)
//   out ----------------------------------
//     array([0, 1, 2, 3, 4])
//
//   [2] markdown -------------------------
//   ## Results
//
// A source line is the cell's own line with nothing added to it.  That is
// deliberate and it is the whole reason this layout works: what is in the
// buffer on a source row is exactly what is in the file, so typing is
// typing, a selection is the code, and syncing a cell back to the notebook
// is reading the lines between two headers.  Indenting the code would mean
// adding and removing two spaces on every edit, paste and copy, and getting
// that wrong in one place would put the indent into somebody's Python.
//
// Headers, the output label and output lines are decoration: the document
// keeps the caret out of them and refuses edits there, the way the hex view
// keeps the caret out of the offset column.
//
// Outputs are rendered, not run: a stream is its text, a result is its
// text/plain, an error is its traceback with the terminal colour escapes
// taken out, and an image is a line saying how big it is.  Anything past
// LedNBMaxOutputLines is summarised, because a cell that printed a hundred
// thousand lines should not make the file unopenable.

unit Led.Core.NBView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, Led.Core.NBFormat;

const
  { How wide the rule after a header is drawn.  Fixed rather than the width
    of the window: the buffer is text, and text that reflows when the window
    is resized is text that cannot be searched or diffed. }
  LedNBRuleWidth = 52;
  { Output lines are indented so that they read as the cell's answer rather
    than as more of its code.  Output is never edited, so the indent costs
    nothing -- unlike on a source line, where it would have to be added and
    taken off again on every edit. }
  LedNBOutIndent = 2;
  { Above this many lines an output is summarised.  A cell that printed a
    progress bar for an hour is not worth rendering in full. }
  LedNBMaxOutputLines = 40;

type
  { What one line of the buffer is. }
  TLedNBRowKind = (
    nbrHeader,     // [1] python ------
    nbrSource,     // a line of the cell's source, exactly as the file has it
    nbrOutLabel,   // out ------
    nbrOutput,     // a line of rendered output
    nbrBlank);     // the gap between cells

  TLedNBRow = record
    Kind: TLedNBRowKind;
    Cell: Integer;         // which cell, or -1 for a row between cells
    SourceLine: Integer;   // 0-based line within the cell, for nbrSource
    CellKind: TLedNBCellKind;
    { An output row that came from a traceback, so the view can colour it
      like an error rather than like an answer. }
    IsError: Boolean;
    Text: string;          // the line as the buffer holds it
  end;
  TLedNBRows = array of TLedNBRow;

  { One flag per rendered output line: whether it came from a traceback. }
  TLedNBFlags = array of Boolean;

{ Renders ANotebook and returns the buffer text; ARows comes back with one
  entry per line of it. }
function LedNBRender(ANotebook: TLedNotebook; out ARows: TLedNBRows): string;

{ The same text from rows already walked. }
function LedNBRowsText(const ARows: TLedNBRows): string;

{ The header line for a cell: its execution count, what it is, and a rule. }
function LedNBHeaderText(ANotebook: TLedNotebook; ACell: Integer): string;

{ Every line a cell's outputs render to, in order.  AIsError comes back with
  one flag per line.  Empty for a cell with no outputs. }
procedure LedNBOutputLines(ANotebook: TLedNotebook; ACell: Integer;
  AInto: TStrings; out AIsError: TLedNBFlags);

{ Terminal colour escapes, taken out.  Tracebacks are full of them: ipykernel
  colours its own output, and a buffer that showed the escapes would be
  unreadable where it matters most. }
function LedNBStripAnsi(const AText: string): string;

{ The first buffer row of a cell's source, or -1 when it has none.  A cell
  with an empty source still has one row, so this is where the caret goes
  when the reader asks for a cell. }
function LedNBSourceRowOf(const ARows: TLedNBRows; ACell: Integer): Integer;

{ The cell a buffer row belongs to, or -1.  Rows between cells belong to no
  cell, which is what keeps a caret in the gap from editing one. }
function LedNBCellOf(const ARows: TLedNBRows; ARow: Integer): Integer;

{ Whether a row is one the reader may type into.  Only source rows are. }
function LedNBIsEditable(const ARows: TLedNBRows; ARow: Integer): Boolean;

{ The source of the cell ACell as the buffer currently holds it, gathered
  from ARows.  This is what a document hands back to the notebook after an
  edit: the rows are the truth about what is on screen, and the cell is the
  lines of it between the header and whatever follows. }
function LedNBSourceFromRows(const ARows: TLedNBRows; ACell: Integer): string;

implementation

function LedNBStripAnsi(const AText: string): string;
var
  i, n: Integer;
begin
  Result := '';
  i := 1;
  n := Length(AText);
  while i <= n do
  begin
    { ESC [ ... final-byte.  The parameter bytes are digits and semicolons
      and the sequence ends at the first letter, which is the whole of what
      a traceback uses. }
    if (AText[i] = #27) and (i < n) and (AText[i + 1] = '[') then
    begin
      Inc(i, 2);
      while (i <= n) and (AText[i] in ['0'..'9', ';', ':', '?']) do Inc(i);
      if i <= n then Inc(i);       // the final letter
      Continue;
    end;
    { A lone escape is not a colour sequence and is not text either; it comes
      out rather than being shown as a gap. }
    if AText[i] = #27 then
    begin
      Inc(i);
      Continue;
    end;
    Result := Result + AText[i];
    Inc(i);
  end;
end;

{ A rule of the given total width, less what is already on the line. }
function RuleAfter(const AText: string): string;
var
  n: Integer;
begin
  n := LedNBRuleWidth - Length(AText) - 1;
  if n < 3 then n := 3;
  Result := AText + ' ' + StringOfChar('-', n);
end;

function LedNBHeaderText(ANotebook: TLedNotebook; ACell: Integer): string;
var
  Count: Integer;
  Left: string;
begin
  case ANotebook.CellKind(ACell) of
    nbkCode:
      begin
        Count := ANotebook.CellExecutionCount(ACell);
        if Count >= 0 then
          Left := Format('[%d]', [Count])
        else
          { Never run, or run and then cleared.  Jupyter shows the same
            thing, and the reader is owed the distinction: a cell with no
            count has not contributed to what the kernel currently holds. }
          Left := '[ ]';
        Left := Left + ' ' + ANotebook.LanguageName;
        if ANotebook.LanguageName = '' then Left := Left + 'code';
      end;
    nbkMarkdown: Left := '[ ] markdown';
  else
    Left := '[ ] raw';
  end;
  Result := RuleAfter(Left);
end;

{ How big a piece of base64 is, as bytes.  Four characters carry three, and
  the padding on the end carries less; near enough for a line that says an
  image is here and roughly how heavy it is. }
function Base64Bytes(const AText: string): Int64;
var
  Pad: Integer;
begin
  Pad := 0;
  if (Length(AText) >= 1) and (AText[Length(AText)] = '=') then Inc(Pad);
  if (Length(AText) >= 2) and (AText[Length(AText) - 1] = '=') then Inc(Pad);
  Result := (Int64(Length(AText)) div 4) * 3 - Pad;
  if Result < 0 then Result := 0;
end;

function SizeText(ABytes: Int64): string;
begin
  if ABytes >= 1024 * 1024 then
    Result := Format('%.1f MB', [ABytes / (1024 * 1024)])
  else if ABytes >= 1024 then
    Result := Format('%.1f KB', [ABytes / 1024])
  else
    Result := Format('%d bytes', [ABytes]);
end;

{ The text of one output, as lines appended to AInto. }
procedure RenderOutput(AOutput: TJSONObject; AInto: TStrings;
  var AIsError: TLedNBFlags);
var
  Kind, Text: string;
  Data: TJSONData;
  Obj: TJSONObject;
  Lines: TStringList;
  i, j: Integer;
  Error: Boolean;

  { A list of strings, joined with ASep between them.

    Which separator depends on what the field is, and the two are not the
    same thing.  A source or a stream is stored as lines with their newlines
    already on the end, so they are concatenated with nothing: putting a
    newline between them would double every line break.  A traceback is
    stored as frames, each of them several lines with no newline at the end,
    so they are joined with one -- without which the exception name, the
    "Traceback (most recent call last)" banner and the first frame all end up
    on one line. }
  function Joined(AValue: TJSONData; const ASep: string = ''): string;
  var
    k: Integer;
  begin
    Result := '';
    if AValue = nil then Exit;
    if AValue.JSONType = jtString then Exit(AValue.AsString);
    if AValue.JSONType <> jtArray then Exit;
    for k := 0 to TJSONArray(AValue).Count - 1 do
      if TJSONArray(AValue).Items[k].JSONType = jtString then
      begin
        if (Result <> '') and (ASep <> '') then Result := Result + ASep;
        Result := Result + TJSONArray(AValue).Items[k].AsString;
      end;
  end;

  procedure Emit(const ALine: string);
  begin
    AInto.Add(ALine);
    SetLength(AIsError, Length(AIsError) + 1);
    AIsError[High(AIsError)] := Error;
  end;

begin
  Kind := '';
  Data := AOutput.Find('output_type');
  if (Data <> nil) and (Data.JSONType = jtString) then Kind := Data.AsString;
  Error := Kind = 'error';

  Text := '';
  if Kind = 'stream' then
    Text := Joined(AOutput.Find('text'))
  else if Kind = 'error' then
  begin
    { The traceback already carries the exception line at its end, so the
      name and value are only printed when there is no traceback -- which
      happens when a kernel reports an error it did not raise. }
    Text := Joined(AOutput.Find('traceback'), #10);
    if Trim(Text) = '' then
      Text := Trim(Joined(AOutput.Find('ename')) + ': ' +
                   Joined(AOutput.Find('evalue')));
  end
  else
  begin
    Data := AOutput.Find('data');
    if (Data <> nil) and (Data.JSONType = jtObject) then
    begin
      Obj := TJSONObject(Data);
      if Obj.Find('text/plain') <> nil then
        Text := Joined(Obj.Find('text/plain'))
      else
        { A picture, or a widget, or something else this view cannot show.
          Saying what it is and how big beats saying nothing: the reader can
          see that the cell produced something. }
        for i := 0 to Obj.Count - 1 do
          Text := Text + Format('[%s, %s]', [Obj.Names[i],
            SizeText(Base64Bytes(Joined(Obj.Items[i])))]) + #10;
    end;
  end;

  Text := LedNBStripAnsi(Text);
  if Text = '' then Exit;

  Lines := TStringList.Create;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    Lines.Text := Text;
    { TStringList.Text adds a line for a trailing newline; an output that
      ends with one does not have an empty last line to show. }
    while (Lines.Count > 0) and (Lines[Lines.Count - 1] = '') do
      Lines.Delete(Lines.Count - 1);

    if Lines.Count > LedNBMaxOutputLines then
    begin
      for i := 0 to LedNBMaxOutputLines - 1 do Emit(Lines[i]);
      j := Lines.Count - LedNBMaxOutputLines;
      Emit(Format('... %d more line%s not shown', [j, Copy('s', 1, Ord(j > 1))]));
    end
    else
      for i := 0 to Lines.Count - 1 do Emit(Lines[i]);
  finally
    Lines.Free;
  end;
end;

procedure LedNBOutputLines(ANotebook: TLedNotebook; ACell: Integer;
  AInto: TStrings; out AIsError: TLedNBFlags);
var
  Outs: TJSONArray;
  i: Integer;
begin
  AIsError := nil;
  Outs := ANotebook.CellOutputs(ACell);
  if Outs = nil then Exit;
  for i := 0 to Outs.Count - 1 do
    if Outs.Items[i].JSONType = jtObject then
      RenderOutput(TJSONObject(Outs.Items[i]), AInto, AIsError);
end;

function LedNBRender(ANotebook: TLedNotebook; out ARows: TLedNBRows): string;
var
  Cell, i, Used: Integer;
  Source: string;
  Lines, Outs: TStringList;
  Errors: TLedNBFlags;

  procedure Add(AKind: TLedNBRowKind; ACell: Integer; const AText: string;
    ASourceLine: Integer = -1; AIsError: Boolean = False);
  begin
    if Used >= Length(ARows) then SetLength(ARows, Length(ARows) * 2 + 64);
    ARows[Used].Kind := AKind;
    ARows[Used].Cell := ACell;
    ARows[Used].SourceLine := ASourceLine;
    ARows[Used].IsError := AIsError;
    ARows[Used].Text := AText;
    if ACell >= 0 then
      ARows[Used].CellKind := ANotebook.CellKind(ACell)
    else
      ARows[Used].CellKind := nbkRaw;
    Inc(Used);
  end;

begin
  ARows := nil;
  Used := 0;
  Lines := TStringList.Create;
  Outs := TStringList.Create;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    Outs.TextLineBreakStyle := tlbsLF;

    for Cell := 0 to ANotebook.CellCount - 1 do
    begin
      if Cell > 0 then Add(nbrBlank, -1, '');
      Add(nbrHeader, Cell, LedNBHeaderText(ANotebook, Cell));

      { A cell with no source still gets one row: it is where the caret goes
        and where the typing starts, and a cell that cannot be typed into is
        a cell that can never stop being empty. }
      Source := ANotebook.CellSource(Cell);
      Lines.Clear;
      if Source = '' then
        Lines.Add('')
      else
        Lines.Text := Source;
      if (Lines.Count > 1) and (Lines[Lines.Count - 1] = '') and
         (Source[Length(Source)] <> #10) then
        Lines.Delete(Lines.Count - 1);
      for i := 0 to Lines.Count - 1 do
        Add(nbrSource, Cell, Lines[i], i);

      Outs.Clear;
      LedNBOutputLines(ANotebook, Cell, Outs, Errors);
      if Outs.Count > 0 then
      begin
        Add(nbrOutLabel, Cell, RuleAfter('out'));
        for i := 0 to Outs.Count - 1 do
          Add(nbrOutput, Cell, StringOfChar(' ', LedNBOutIndent) + Outs[i],
            -1, (i <= High(Errors)) and Errors[i]);
      end;
    end;
  finally
    Outs.Free;
    Lines.Free;
  end;
  SetLength(ARows, Used);
  Result := LedNBRowsText(ARows);
end;

function LedNBRowsText(const ARows: TLedNBRows): string;
var
  i, Len: Integer;
  At: Integer;
begin
  Len := 0;
  for i := 0 to High(ARows) do Inc(Len, Length(ARows[i].Text) + 1);
  if Len > 0 then Dec(Len);          // no newline after the last row
  SetLength(Result, Len);
  At := 1;
  for i := 0 to High(ARows) do
  begin
    if ARows[i].Text <> '' then
    begin
      Move(ARows[i].Text[1], Result[At], Length(ARows[i].Text));
      Inc(At, Length(ARows[i].Text));
    end;
    if i < High(ARows) then
    begin
      Result[At] := #10;
      Inc(At);
    end;
  end;
end;

function LedNBSourceRowOf(const ARows: TLedNBRows; ACell: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(ARows) do
    if (ARows[i].Cell = ACell) and (ARows[i].Kind = nbrSource) then Exit(i);
  Result := -1;
end;

function LedNBCellOf(const ARows: TLedNBRows; ARow: Integer): Integer;
begin
  if (ARow < 0) or (ARow > High(ARows)) then Exit(-1);
  Result := ARows[ARow].Cell;
end;

function LedNBIsEditable(const ARows: TLedNBRows; ARow: Integer): Boolean;
begin
  Result := (ARow >= 0) and (ARow <= High(ARows)) and
            (ARows[ARow].Kind = nbrSource);
end;

function LedNBSourceFromRows(const ARows: TLedNBRows; ACell: Integer): string;
var
  i: Integer;
  First: Boolean;
begin
  Result := '';
  First := True;
  for i := 0 to High(ARows) do
    if (ARows[i].Cell = ACell) and (ARows[i].Kind = nbrSource) then
    begin
      if not First then Result := Result + #10;
      Result := Result + ARows[i].Text;
      First := False;
    end;
end;

end.
