{ led - a lightweight editor.  Reading a file that is not text.

  Opening a binary in a text editor has two failure modes and led had both.
  The harmless one is that it looks like rubbish.  The one that matters is
  that saving it writes the rubbish back: the text path normalises every line
  ending and re-encodes the whole buffer, so a CR that happened to sit inside
  a binary comes back as CRLF, or the other way about, and the file is broken
  in a way nothing announces.

  So a file that does not look like text is shown as a hex dump instead, in
  the layout hexedit and xxd use -- offset, the bytes, and the printable ones
  again on the right:

    00000000  7f 45 4c 46 02 01 01 00  00 00 00 00 00 00 00 00  |.ELF............|

  This unit is the part of that with no screen in it: deciding what is
  binary, and turning bytes into those lines.  It is also where the byte
  buffer will go when the dump becomes editable, which is why the dump is
  described here by its geometry rather than only by its text -- a caret has
  to be able to find its way from a column back to a byte. }
unit Led.Core.Hex;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  { The row width every other measurement here follows from.  Sixteen is what
    hexedit, xxd and od all settled on: it divides the offsets into something
    a reader can do in their head, and the line still fits an eighty-column
    terminal, which is where the convention came from. }
  LedHexBytesPerLine = 16;

  { The dump is grouped in eights with a wider gap between, again as xxd does
    -- sixteen unbroken pairs is a wall. }
  LedHexGroup = 8;

{ True when ARaw looks like a binary rather than text.

  A NUL byte in the first few kilobytes, which is the rule grep has always
  used here and the same one file(1) leans on: text encodings in the wild do
  not contain NUL, and every common binary format does, early.  Deliberately
  not a survey of how many bytes are printable -- that misreads UTF-8 text as
  binary, and misreading a source file as binary is the expensive mistake. }
function LedLooksBinary(const ARaw: string): Boolean;

{ ARaw as a hex dump, LF-separated, with no trailing newline.

  Every line is the same width whatever the data, so the columns line up and
  a caret can be mapped back to a byte by arithmetic rather than by parsing.
  A short final row is padded with spaces for the same reason. }
function LedHexDump(const ARaw: string): string;

{ The column, counting from one as an editor does, where the bytes and the
  text of a row begin.  Exposed so a view can put a caret on a byte without
  knowing how the line was assembled. }
function LedHexByteColumn(AIndexInLine: Integer): Integer;
function LedHexTextColumn(AIndexInLine: Integer): Integer;

{ The byte a column falls on, or -1 for the punctuation between them.  The
  inverse of the two above, and the reason they exist. }
function LedHexColumnToIndex(AColumn: Integer): Integer;

implementation

const
  { Lower case, and so is the offset: it is what xxd and od produce, which
    is what a hex dump pasted into a bug report is expected to look like. }
  HexDigits = '0123456789abcdef';

  { "00000000  " -- eight digits and the two spaces that follow. }
  OffsetWidth = 10;

function LedLooksBinary(const ARaw: string): Boolean;
var
  i, Limit: Integer;
begin
  Limit := Length(ARaw);
  { Enough to catch a header without reading a hundred megabytes of video to
    decide.  A file whose first eight kilobytes are clean text is text as far
    as anyone opening it is concerned. }
  if Limit > 8192 then Limit := 8192;
  for i := 1 to Limit do
    if ARaw[i] = #0 then Exit(True);
  Result := False;
end;

function LedHexByteColumn(AIndexInLine: Integer): Integer;
begin
  { Three columns per byte -- two digits and a space -- plus the extra space
    that separates the two groups of eight. }
  Result := OffsetWidth + AIndexInLine * 3 + 1;
  if AIndexInLine >= LedHexGroup then Inc(Result);
end;

function LedHexTextColumn(AIndexInLine: Integer): Integer;
begin
  { From the last byte's first digit: its second digit, the space after it,
    the wider gap before the bar, and the bar. }
  Result := LedHexByteColumn(LedHexBytesPerLine - 1) + 1 + 1 + 1 + 1 + 1;
  Inc(Result, AIndexInLine);
end;

function LedHexColumnToIndex(AColumn: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to LedHexBytesPerLine - 1 do
  begin
    { Either digit of the pair counts as the byte; the space after it does
      not, so that arrowing off the end of a row does not silently land on
      the next byte. }
    if (AColumn = LedHexByteColumn(i)) or (AColumn = LedHexByteColumn(i) + 1) then
      Exit(i);
    if AColumn = LedHexTextColumn(i) then
      Exit(i);
  end;
  Result := -1;
end;

function LedHexDump(const ARaw: string): string;
var
  Rows, Row, i, Index: Integer;
  Line: string;
  B: Byte;
  Out_: TStringList;
begin
  if ARaw = '' then Exit('');

  Out_ := TStringList.Create;
  try
    Out_.LineBreak := #10;
    { A partial last row still counts. }
    Rows := (Length(ARaw) + LedHexBytesPerLine - 1) div LedHexBytesPerLine;
    for Row := 0 to Rows - 1 do
    begin
      Line := LowerCase(IntToHex(Row * LedHexBytesPerLine, 8)) + '  ';

      for i := 0 to LedHexBytesPerLine - 1 do
      begin
        Index := Row * LedHexBytesPerLine + i + 1;
        if Index <= Length(ARaw) then
        begin
          B := Byte(ARaw[Index]);
          Line := Line + HexDigits[(B shr 4) + 1] + HexDigits[(B and $0F) + 1];
        end
        else
          { Padded, not omitted: the text column of a short last row has to
            start where every other row's does. }
          Line := Line + '  ';
        Line := Line + ' ';
        if i = LedHexGroup - 1 then Line := Line + ' ';
      end;

      Line := Line + ' |';
      for i := 0 to LedHexBytesPerLine - 1 do
      begin
        Index := Row * LedHexBytesPerLine + i + 1;
        if Index > Length(ARaw) then
          Line := Line + ' '
        else
        begin
          B := Byte(ARaw[Index]);
          { The printable ASCII range and nothing else.  A dot for the rest,
            including the high half: what a byte above 127 looks like depends
            on an encoding, and the whole point here is that there is not
            one. }
          if (B >= 32) and (B < 127) then
            Line := Line + Chr(B)
          else
            Line := Line + '.';
        end;
      end;
      Line := Line + '|';

      Out_.Add(Line);
    end;
    Result := Out_.Text;
    { TStringList.Text ends every line, including the last; the buffer this
      feeds counts that as an extra empty line. }
    if (Result <> '') and (Result[Length(Result)] = #10) then
      SetLength(Result, Length(Result) - 1);
  finally
    Out_.Free;
  end;
end;

end.
