// led - a lightweight editor.  Turning a pipe or a socket back into lines.
//
// Three things LED talks to answer in lines: gdb over its Machine Interface,
// the notebook kernel helper, and a model streaming a reply.  None of them
// gets to choose where a read ends.  A 16 kB read lands wherever the other
// side happened to flush, so it holds two whole lines and the first eleven
// bytes of a third, and the eleven bytes are not a message -- they are the
// start of one.  Handing them to a JSON parser produces an error about a
// document that was never wrong.
//
// So the tail waits for its newline.  That is a short piece of code and it
// was written twice: once in Led.Core.Kernel and once in Led.Core.Gdb, near
// enough identically that the second is plainly a copy of the first, and the
// copies have already drifted -- gdb guards an empty buffer where the kernel
// does not.  Neither copy has a test, because neither can be driven without
// a subprocess to hand.  This one can: Feed takes bytes, Next hands back
// lines, and a test can cut the same stream at every offset in it.
//
// Both copies split with TStringList.DelimitedText, and that is worse than
// duplication.  StrictDelimiter is documented as "split on the delimiter and
// nothing else", and it does stop spaces being treated as separators -- but
// in FPC 3.2.2 it does not turn quoting off.  DoSetDelimitedText calls
// CheckQuoted regardless (rtl/objpas/classes/stringl.inc:558), so a line that
// *begins* with a double quote is read as a quoted string: doubled quotes are
// collapsed to single ones, and everything after the closing quote is thrown
// away.  JSON objects begin with a brace, which is the only reason the kernel
// and gdb have got away with it; a line of JSON that is a bare string, or any
// protocol that quotes its first field, would be silently mangled.  This
// scans for the newline itself and copies the bytes between, so what comes
// out is what went in.
//
// Reading is from a cursor rather than by cutting the front off the buffer.
// The buffer is only compacted once its consumed half is the larger one, so
// a long reply arriving in small pieces costs the length of the reply and not
// the square of it.  The same mistake on the same shape of loop is what made
// the Markdown preview take sixteen seconds for half a megabyte.

unit Led.Core.LineSplit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { Bytes in, lines out.

    A class rather than a record: it lives for as long as the connection it
    reassembles, it is held by reference in the thing doing the reading, and
    there is one of them per stream rather than one per loop. }
  TLedLineSplitter = class
  private
    FBuf: string;
    FScan: Integer;       // 1-based; the first byte not yet handed out
    FLines: Integer;      // how many complete lines have been handed out
    procedure Compact;
  public
    constructor Create;

    { Bytes as they came off the pipe.  A chunk may end anywhere: in the
      middle of a line, between a carriage return and its newline, or
      between the two halves of a UTF-8 character.  None of those is
      special here -- only the newline is looked for, and everything else
      is carried forward untouched. }
    procedure Feed(const AChunk: string);

    { The next complete line, without its line ending, or False when what is
      left has no newline in it yet.  A line that ended CRLF loses the
      carriage return too; an empty line is a line, and comes back as one. }
    function Next(out ALine: string): Boolean;

    { What is left when the other side has finished and there will be no
      more newline.  True when there was something, and it is handed over
      exactly as it stands.

      At the end of the stream, after Next has stopped giving lines -- not
      in the read loop, where it would parse every partial line as a whole
      one, which is the bug this unit exists to prevent.  Taking the lines
      first is the caller's job: what is left here is handed over whole,
      newlines and all, rather than quietly dropping a line nobody took. }
    function Flush(out ALine: string): Boolean;

    procedure Reset;

    { The bytes that cannot be a line yet: whatever follows the last
      newline still in hand.  Published so a check can watch the holding
      back happen rather than infer it from what came out. }
    function Pending: string;
    { How many lines have been handed out since the last Reset. }
    property LineCount: Integer read FLines;
  end;

implementation

constructor TLedLineSplitter.Create;
begin
  inherited Create;
  Reset;
end;

procedure TLedLineSplitter.Reset;
begin
  FBuf := '';
  FScan := 1;
  FLines := 0;
end;

{ Drops what has already been handed out.  Only when it is worth doing: a
  move costs the length of what is kept, so doing it after every line would
  turn a buffer holding one long line into a copy per line. }
procedure TLedLineSplitter.Compact;
begin
  if FScan <= 1 then Exit;
  if (FScan - 1) * 2 < Length(FBuf) then Exit;
  FBuf := Copy(FBuf, FScan, Length(FBuf) - FScan + 1);
  FScan := 1;
end;

procedure TLedLineSplitter.Feed(const AChunk: string);
begin
  if AChunk = '' then Exit;
  Compact;
  FBuf := FBuf + AChunk;
end;

function TLedLineSplitter.Next(out ALine: string): Boolean;
var
  i, Stop: Integer;
begin
  ALine := '';
  Result := False;
  i := FScan;
  while i <= Length(FBuf) do
  begin
    if FBuf[i] = #10 then
    begin
      { The newline is not part of the line, and neither is the carriage
        return in front of it -- which is how the same code reads a stream
        from a Windows child and one from a Unix one without being told
        which it is. }
      Stop := i - 1;
      if (Stop >= FScan) and (FBuf[Stop] = #13) then Dec(Stop);
      ALine := Copy(FBuf, FScan, Stop - FScan + 1);
      FScan := i + 1;
      Inc(FLines);
      Exit(True);
    end;
    Inc(i);
  end;
end;

function TLedLineSplitter.Flush(out ALine: string): Boolean;
begin
  ALine := Copy(FBuf, FScan, Length(FBuf) - FScan + 1);
  Result := ALine <> '';
  if Result then
  begin
    FScan := Length(FBuf) + 1;
    Inc(FLines);
  end;
end;

function TLedLineSplitter.Pending: string;
var
  i, From: Integer;
begin
  { After the last newline, not from the read cursor: a complete line that
    nobody has taken yet is a line, and calling it a held-back tail would
    make this read True at moments when nothing is being held at all. }
  From := FScan;
  for i := Length(FBuf) downto FScan do
    if FBuf[i] = #10 then
    begin
      From := i + 1;
      Break;
    end;
  Result := Copy(FBuf, From, Length(FBuf) - From + 1);
end;

end.
