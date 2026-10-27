{ LED - a lightweight editor.  Markdown to HTML.

  medit converted Markdown with md4c, a C library.  Linking C into an FPC
  build reintroduces a C toolchain on every platform, which is the coupling
  this rewrite exists to remove, so this is a Pascal implementation of the
  subset that matters for a preview pane: headings, paragraphs, lists,
  block quotes, fenced and indented code, thematic breaks, pipe tables, and
  the usual inline spans.

  Not CommonMark-complete, and does not pretend to be.  What it must be is
  predictable and safe: the output goes to an HTML control, so anything that
  is not markup gets escaped.

  No LCL dependency. }
unit Led.Core.Markdown;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils;

{ Converts Markdown to an HTML fragment.  Wrap it yourself, or use
  LedMarkdownToPage for a whole document with a stylesheet.

  With ALineIds, every block carries the source line it came from as
  id="L<n>" -- a heading, a paragraph, a list item, a table row.  That is all
  a preview needs to scroll with the text beside it and to send a click back
  to the line it came from, and it is deliberately all: the mapping is per
  block, not per character, which is the same choice VS Code makes with its
  data-line attributes.  Anything finer would mean a document model with
  source spans, and the preview would still only be able to use the block. }
function LedMarkdownToHTML(const AText: string; ALineIds: Boolean = False): string;
function LedMarkdownToPage(const AText, ATitle: string;
  ALineIds: Boolean = False): string;
function LedIsLanguageWord(const AWord: string): Boolean;
function LedHtmlEscape(const AText: string): string;

{ As much of a document as is worth laying out, cut at a line boundary.

  ALimitBytes <= 0 means all of it.  ACut says whether anything was left off,
  so the caller can say so on the page.

  This exists because laying out a page costs more than the square of its
  size.  Measured through IpHtmlPanel on plain prose: 8 KiB takes 140 ms,
  32 KiB 1.9 seconds, 256 KiB two minutes -- and a 2 MB document the best
  part of an hour, which is what "the preview never appears" was.  On the
  shape of document a reader actually previews -- lecture notes, a table and
  a code sample per section -- it is three times worse again, measured end
  to end from the pane opening:

    8 KB    406 ms      32 KB   4.9 s
    16 KB   1.3 s       96 KB   39.9 s

  None of that is LED's own time: building the page from a 512 KiB document
  is 200 ms, and the rest is spent inside the renderer after the page is
  handed over.

  The cut has to fall at a newline.  Half a fence leaves the rest of the page
  preformatted and half a table row leaves a broken table; ending on a line
  boundary at worst drops a paragraph early. }
function LedPreviewCut(const AText: string; ALimitBytes: Integer;
  out ACut: Boolean): string;

{ Breaks the lines inside <pre> blocks so none is wider than AColumns
  characters.  AColumns <= 0 leaves AHtml alone.

  A preformatted block is the one thing on an HTML page that refuses to
  narrow: its minimum width is its longest line, and a renderer that cannot
  scroll a block on its own -- IpHtmlPanel cannot -- lays the whole document
  out at that width instead.  One eighty-column code sample in a preview pane
  half that wide therefore pushes every paragraph past the right edge, where
  a preview pane has nowhere to put them.  Wrapping the code is the only
  lever that does not cost the rest of the page.

  Breaks fall at a space where the line has one to spare, and mid-token
  otherwise, because a path or a URL with no spaces in it still has to fit.
  Markup and entities inside the block are stepped over rather than counted:
  a tag takes no columns and "&amp;" takes one, and neither may be split. }
function LedWrapPreLines(const AHtml: string; AColumns: Integer): string;

{ Breaks a multi-word inline span into one span per word:

    <b>two words</b>   ->   <b>two</b> <b>words</b>

  Same page, drawn the same, and between forty and a hundred times cheaper to
  lay out in IpHtmlPanel.  A space inside a span is measured against that
  span's own font, which IPro does not manage to reuse between spans: the
  measurement is repeated for every one, and the cost climbs faster than the
  document does.  Outside the span the space is the paragraph's own, measured
  once for the whole page.  Measured, 400 paragraphs: <b>bold words</b> 2700
  ms, <b>bold</b> <b>words</b> 22 ms.

  Only the tags that change the font are broken -- bold, italic, the
  monospaced ones -- because for those a space inside the span and a space
  outside it are the same ink.  An underline or a strikethrough would show
  the difference, so those are left whole. }
function LedSplitInlineRuns(const AHtml: string): string;

{ Headings, in the elements this renderer can afford.

  Reported as: the preview stops after 15 KB, which is too little.  It stops
  because laying a page out was expensive, and what made it expensive was
  mostly the headings.

  Measured on 32 KB of identical prose, one paragraph repeated, varying only
  how many headings were between the paragraphs: none 17 ms, sixteen 232 ms,
  a hundred and fifty-one 2,049 ms.  That is about 13 ms per heading, and it
  is the <hN> element itself: the same document with every <h2> rewritten as
  <p><b><font size="4"> laid out in 24 ms -- eighty-six times faster, same
  text, same size, same weight, same style sheet.  A font size on its own is
  not the cost, and neither is the bold: <font size> and a CSS font-size both
  come out at 25 ms.  It is TIpHtmlNodeHeader.

  So a heading is written as the paragraph it looks like.  The size is the
  one the renderer would have used itself -- its own table is
  (8,10,12,14,18,24,36) and a header of level N picks index abs(N-6), which
  is exactly what <font size="abs(N-6)"> selects -- so nothing about the page
  changes except how long it takes to appear.

  Attributes are carried over, the id above all: it is what the preview
  scrolls to when it follows the text.

  For the renderer, not for the document: anything that writes HTML out for
  somebody else -- printing, export -- wants real headings, and gets them,
  because this is applied where the page is handed to IPro and nowhere
  else. }
function LedFlattenHeadings(const AHtml: string): string;

implementation

function LedPreviewCut(const AText: string; ALimitBytes: Integer;
  out ACut: Boolean): string;
var
  Stop: Integer;
begin
  ACut := False;
  Result := AText;
  if ALimitBytes <= 0 then Exit;
  if Length(AText) <= ALimitBytes then Exit;

  Stop := ALimitBytes;
  while (Stop > 1) and (AText[Stop] <> #10) do Dec(Stop);
  { A document with no newline in its first ALimitBytes -- one very long
    generated line, say -- has no boundary to cut at, so cut where asked. }
  if Stop <= 1 then Stop := ALimitBytes;
  Result := Copy(AText, 1, Stop);
  ACut := True;
end;

function LedHtmlEscape(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

{ --- splitting inline runs ------------------------------------------------- }

{ The tags whose spaces are indistinguishable inside and out.  Deliberately
  not <u>, <s>, <strike>, <ins> or <del>: their line runs through the space,
  and breaking the span would break the line.

  <font> is one of them, and has to be: LedFlattenHeadings writes a heading
  as <b><font size=..>, and with only the <b> closed and reopened at each
  space the <font> was left inside a closed <b>, which the renderer ended
  there -- the heading's first word came out at its size and the rest at the
  prose's. }
function IsFontOnlyTag(const AName: string): Boolean;
begin
  case AName of
    'b', 'strong', 'i', 'em', 'code', 'tt', 'kbd', 'samp', 'var', 'cite',
    'dfn', 'big', 'small', 'font': Result := True;
  else
    Result := False;
  end;
end;

{ The tag name of the markup starting at APos, lowercased, with ASlash set
  when it is a closing tag. }
function TagNameAt(const AHtml: string; APos, AEnd: Integer;
  out ASlash: Boolean): string;
var
  i: Integer;
begin
  Result := '';
  i := APos + 1;
  ASlash := (i <= AEnd) and (AHtml[i] = '/');
  if ASlash then Inc(i);
  while (i <= AEnd) and (AHtml[i] in ['a'..'z', 'A'..'Z', '0'..'9']) do
  begin
    Result := Result + AHtml[i];
    Inc(i);
  end;
  Result := LowerCase(Result);
end;

function LedFlattenHeadings(const AHtml: string): string;
var
  i, TagEnd, Level: Integer;
  Name_, Attrs: string;
  Slash: Boolean;
begin
  Result := '';
  i := 1;
  while i <= Length(AHtml) do
  begin
    if AHtml[i] <> '<' then
    begin
      Result := Result + AHtml[i];
      Inc(i);
      Continue;
    end;

    TagEnd := i;
    while (TagEnd <= Length(AHtml)) and (AHtml[TagEnd] <> '>') do Inc(TagEnd);
    if TagEnd > Length(AHtml) then TagEnd := Length(AHtml);
    Name_ := TagNameAt(AHtml, i, TagEnd, Slash);

    if (Length(Name_) = 2) and (Name_[1] = 'h') and
       (Name_[2] in ['1'..'6']) then
    begin
      Level := Ord(Name_[2]) - Ord('0');
      if Slash then
        Result := Result + '</font></b></p>'
      else
      begin
        { Whatever the heading carried -- in practice the line id. }
        Attrs := Copy(AHtml, i + 1 + Length(Name_),
                      TagEnd - i - 1 - Length(Name_));
        Result := Result + '<p' + Attrs + '><b><font size="' +
          IntToStr(Abs(Level - 6)) + '">';
      end;
      i := TagEnd + 1;
      Continue;
    end;

    Result := Result + Copy(AHtml, i, TagEnd - i + 1);
    i := TagEnd + 1;
  end;
end;

function LedSplitInlineRuns(const AHtml: string): string;
var
  Open_: array of string;   { the opening tags still in force, verbatim }
  Names: array of string;
  Depth, i, TagEnd, k, Run: Integer;
  Name_: string;
  Slash, InPre: Boolean;
begin
  Result := '';
  Depth := 0;
  InPre := False;
  Open_ := nil;
  Names := nil;
  SetLength(Open_, 8);
  SetLength(Names, 8);
  i := 1;
  while i <= Length(AHtml) do
  begin
    if AHtml[i] = '<' then
    begin
      TagEnd := i;
      while (TagEnd <= Length(AHtml)) and (AHtml[TagEnd] <> '>') do Inc(TagEnd);
      if TagEnd > Length(AHtml) then TagEnd := Length(AHtml);
      Name_ := TagNameAt(AHtml, i, TagEnd, Slash);
      if Name_ = 'pre' then
        InPre := not Slash
      else if (not InPre) and IsFontOnlyTag(Name_) then
      begin
        if Slash then
        begin
          { Unbalanced markup is left alone rather than guessed at. }
          if (Depth > 0) and (Names[Depth - 1] = Name_) then Dec(Depth);
        end
        else
        begin
          if Depth >= Length(Open_) then
          begin
            SetLength(Open_, Depth * 2);
            SetLength(Names, Depth * 2);
          end;
          Open_[Depth] := Copy(AHtml, i, TagEnd - i + 1);
          Names[Depth] := Name_;
          Inc(Depth);
        end;
      end;
      Result := Result + Copy(AHtml, i, TagEnd - i + 1);
      i := TagEnd + 1;
      Continue;
    end;

    if (Depth > 0) and (not InPre) and (AHtml[i] = ' ') then
    begin
      { The whole run of spaces goes outside, so the reopened span starts at
        the next word rather than at the last space. }
      Run := i;
      while (Run <= Length(AHtml)) and (AHtml[Run] = ' ') do Inc(Run);
      for k := Depth - 1 downto 0 do
        Result := Result + '</' + Names[k] + '>';
      Result := Result + Copy(AHtml, i, Run - i);
      for k := 0 to Depth - 1 do
        Result := Result + Open_[k];
      i := Run;
      Continue;
    end;

    Result := Result + AHtml[i];
    Inc(i);
  end;
end;

{ --- wrapping preformatted text -------------------------------------------- }

type
  { One indivisible piece of a line: a character, an entity, or a tag.  Cols
    is what it costs across the page -- nothing for a tag, and for an entity
    its own length, because IpHtmlPanel does not decode entities inside a
    <pre> and draws "&quot;" as those six characters.  Sp marks the spaces,
    which are where a break is preferred. }
  TLedPreUnit = record
    Pos, Len, Cols: Integer;
    Sp: Boolean;
  end;
  TLedPreUnits = array of TLedPreUnit;

{ ALine split into units.  Cheap enough to redo per line: a code line is
  short and the alternative is counting columns backwards through entities. }
function SplitPreUnits(const ALine: string): TLedPreUnits;
var
  i, j, N: Integer;
begin
  Result := nil;
  SetLength(Result, Length(ALine));
  N := 0;
  i := 1;
  while i <= Length(ALine) do
  begin
    Result[N].Pos := i;
    Result[N].Sp := False;
    if ALine[i] = '<' then
    begin
      j := i;
      while (j <= Length(ALine)) and (ALine[j] <> '>') do Inc(j);
      if j > Length(ALine) then j := Length(ALine);
      Result[N].Len := j - i + 1;
      Result[N].Cols := 0;
    end
    else if ALine[i] = '&' then
    begin
      j := i + 1;
      { A bare ampersand in text that was never escaped is not an entity; the
        limit keeps it from swallowing the rest of the line. }
      while (j <= Length(ALine)) and (j - i <= 8) and (ALine[j] <> ';') do Inc(j);
      if (j <= Length(ALine)) and (ALine[j] = ';') then
        Result[N].Len := j - i + 1
      else
        Result[N].Len := 1;
      { Wide, but still one piece: cutting an entity in half is the one break
        that could turn text into markup. }
      Result[N].Cols := Result[N].Len;
    end
    else
    begin
      Result[N].Len := 1;
      Result[N].Sp := (ALine[i] = ' ') or (ALine[i] = #9);
      { A CR left on the end of a CRLF line is not a column. }
      if ALine[i] = #13 then Result[N].Cols := 0 else Result[N].Cols := 1;
    end;
    Inc(i, Result[N].Len);
    Inc(N);
  end;
  SetLength(Result, N);
end;

function WrapPreLine(const ALine: string; AColumns: Integer): string;
var
  U: TLedPreUnits;
  i, k, Col, Seg, LastSp, Brk: Integer;
begin
  U := SplitPreUnits(ALine);
  Result := '';
  Seg := 0;
  Col := 0;
  LastSp := -1;
  i := 0;
  while i < Length(U) do
  begin
    { Never before a space: a space that overruns the width is invisible at
      the end of a line, and breaking in front of one would start the next
      line with it. }
    if (U[i].Cols > 0) and (not U[i].Sp) and (Col >= AColumns) then
    begin
      { At a space if this line has one, so that a command keeps its words
        together; otherwise wherever we stand, because the alternative to a
        broken token is a document laid out to its width. }
      if LastSp >= Seg then Brk := LastSp + 1 else Brk := i;
      if Brk <= Seg then Brk := i;
      Result := Result + Copy(ALine, U[Seg].Pos, U[Brk].Pos - U[Seg].Pos) + #10;
      Seg := Brk;
      { What has already been carried onto the new line -- at most a word. }
      Col := 0;
      LastSp := -1;
      for k := Seg to i - 1 do
      begin
        Inc(Col, U[k].Cols);
        if U[k].Sp then LastSp := k;
      end;
    end;
    Inc(Col, U[i].Cols);
    if U[i].Sp then LastSp := i;
    Inc(i);
  end;
  if Length(U) > 0 then
    Result := Result + Copy(ALine, U[Seg].Pos, MaxInt);
end;

{ Every line of ABlock wrapped, with the line breaks it came with left
  exactly as they were: a preformatted block is whitespace, and a round trip
  through a string list would quietly drop the last break. }
function WrapPreBlock(const ABlock: string; AColumns: Integer): string;
var
  i, Start: Integer;
begin
  Result := '';
  Start := 1;
  i := 1;
  while i <= Length(ABlock) do
  begin
    if ABlock[i] = #10 then
    begin
      Result := Result + WrapPreLine(Copy(ABlock, Start, i - Start), AColumns) + #10;
      Start := i + 1;
    end;
    Inc(i);
  end;
  Result := Result + WrapPreLine(Copy(ABlock, Start, MaxInt), AColumns);
end;

function LedWrapPreLines(const AHtml: string; AColumns: Integer): string;
var
  Lower_, Block: string;
  i, OpenAt, BodyAt, CloseAt: Integer;
begin
  if AColumns <= 0 then Exit(AHtml);
  Lower_ := LowerCase(AHtml);
  Result := '';
  i := 1;
  repeat
    OpenAt := PosEx('<pre', Lower_, i);
    if OpenAt = 0 then Break;
    BodyAt := PosEx('>', AHtml, OpenAt);
    if BodyAt = 0 then Break;
    CloseAt := PosEx('</pre', Lower_, BodyAt);
    if CloseAt = 0 then Break;
    Block := Copy(AHtml, BodyAt + 1, CloseAt - BodyAt - 1);
    Result := Result + Copy(AHtml, i, BodyAt - i + 1) +
              WrapPreBlock(Block, AColumns);
    i := CloseAt;
  until False;
  Result := Result + Copy(AHtml, i, MaxInt);
end;

{ --- inline spans ---------------------------------------------------------- }

function InlineSpans(const AText: string): string; forward;
{ Declared here because the inline pass needs it too: a link definition is
  one only while it is not four spaces in. }
function IndentOf(const S: string): Integer; forward;

{ Whether AWord is a plausible language name for a fence: letters, digits,
  and the few punctuation marks language names use.  Not a list of the
  languages LED knows -- that is the renderer's business, and a fence naming
  something it cannot colour is still a fence. }
function LedIsLanguageWord(const AWord: string): Boolean;
var
  i: Integer;
begin
  Result := (AWord <> '') and (Length(AWord) <= 24);
  if not Result then Exit;
  for i := 1 to Length(AWord) do
    if not (AWord[i] in ['a'..'z', '0'..'9', '+', '-', '#', '_', '.']) then
      Exit(False);
end;

{ The tags a markdown cell may carry through to the page as they stand.

  Markdown has always allowed inline HTML, and notebooks are full of it --
  <font color=...> most of all, which is how people colour a word in a cell
  that Jupyter and Colab both render.  Escaping it, which is what this used
  to do, showed the reader the tag instead of the effect.

  A list rather than everything: what is here changes how the page looks and
  nothing else.  Anything that would load or run something -- a script, a
  frame, an object, a form -- is escaped and shown, which is both safer and
  more honest than pretending to support it. }
function AllowedTag(const AName: string): Boolean;
const
  Tags: array[0..31] of string = (
    'b', 'i', 'u', 's', 'em', 'strong', 'small', 'big', 'sub', 'sup',
    'br', 'hr', 'font', 'span', 'div', 'center', 'p', 'code', 'tt', 'pre',
    'a', 'img', 'blockquote', 'ul', 'ol', 'li', 'table', 'tr', 'td', 'th',
    'thead', 'tbody');
var
  i: Integer;
begin
  Result := False;
  for i := Low(Tags) to High(Tags) do
    if SameText(AName, Tags[i]) then Exit(True);
end;

{ An HTML tag starting at AAt, if what is there is one of the tags above.
  AStop comes back as the closing angle bracket. }
function RawTagAt(const AText: string; AAt: Integer;
  out AStop: Integer): Boolean;
var
  i, NameFrom: Integer;
  Name_: string;
  Quote: Char;
begin
  Result := False;
  AStop := AAt;
  i := AAt + 1;
  if i > Length(AText) then Exit;
  if AText[i] = '/' then Inc(i);
  NameFrom := i;
  while (i <= Length(AText)) and (AText[i] in ['a'..'z', 'A'..'Z', '0'..'9']) do
    Inc(i);
  Name_ := Copy(AText, NameFrom, i - NameFrom);
  if not AllowedTag(Name_) then Exit;

  { Past the attributes to the closing bracket, stepping over quoted values
    so that a > inside one does not end the tag early. }
  while i <= Length(AText) do
  begin
    if AText[i] = '>' then
    begin
      AStop := i;
      Exit(True);
    end;
    if AText[i] in ['"', ''''] then
    begin
      Quote := AText[i];
      Inc(i);
      while (i <= Length(AText)) and (AText[i] <> Quote) do Inc(i);
    end;
    Inc(i);
  end;
end;

{ Finds the closing run of ADelim starting at AFrom, ignoring one inside a
  code span. }
function FindClose(const S, ADelim: string; AFrom: Integer): Integer;
var
  i: Integer;
begin
  i := AFrom;
  while i <= Length(S) - Length(ADelim) + 1 do
  begin
    if (S[i] = '\') then
    begin
      Inc(i, 2);
      Continue;
    end;
    if Copy(S, i, Length(ADelim)) = ADelim then Exit(i);
    Inc(i);
  end;
  Result := 0;
end;

{ Where the run of exactly ARun backticks that closes a code span begins, or
  0 if the span is never closed.

  Exactly ARun: a longer run inside is content, which is how a span that has
  backticks in it is written -- ``a ` b`` -- and the reason this cannot be
  the ordinary "find the next delimiter". }
function CodeSpanEnd(const S: string; AFrom, ARun: Integer): Integer;
var
  i, k: Integer;
begin
  Result := 0;
  i := AFrom;
  while i <= Length(S) do
  begin
    if S[i] = '`' then
    begin
      k := 0;
      while (i + k <= Length(S)) and (S[i + k] = '`') do Inc(k);
      if k = ARun then Exit(i);
      Inc(i, k);
    end
    else
      Inc(i);
  end;
end;

{ The destination and the title out of what stands between a link's
  parentheses.  False when it is neither, which is what makes
  "[link](/my uri)" the text it is and not a link to "/my uri".

  The destination may be wrapped in angle brackets, which is how a path with
  a space in it is written, and the title follows it in quotes or in
  parentheses.  Without this the whole of it went into the href, so every
  link written with a title -- [text](/url "what it is") -- pointed at a URL
  with the title inside it and went nowhere. }
function SplitTarget(const S: string; out AUrl, ATitle: string): Boolean;
var
  T: string;
  i: Integer;
  Q: Char;
begin
  Result := False;
  AUrl := '';
  ATitle := '';
  T := Trim(S);
  if (T <> '') and (T[1] = '<') then
  begin
    i := Pos('>', T);
    if i = 0 then Exit;
    AUrl := Copy(T, 2, i - 2);
    T := Trim(Copy(T, i + 1, MaxInt));
  end
  else
  begin
    i := 1;
    while (i <= Length(T)) and not (T[i] in [' ', #9]) do Inc(i);
    AUrl := Copy(T, 1, i - 1);
    T := Trim(Copy(T, i, MaxInt));
  end;
  { A space in a destination is written as one and sent as %20, or the
    attribute ends early in anything strict about its quoting. }
  AUrl := StringReplace(AUrl, ' ', '%20', [rfReplaceAll]);
  if T = '' then Exit(True);
  if Length(T) < 2 then Exit;
  Q := T[1];
  if ((Q = '"') and (T[Length(T)] = '"')) or
     ((Q = '''') and (T[Length(T)] = '''')) or
     ((Q = '(') and (T[Length(T)] = ')')) then
  begin
    ATitle := Copy(T, 2, Length(T) - 2);
    Result := True;
  end;
end;

{ A label holds no bracket of its own unless it is escaped, so "[foo][ref[]"
  names nothing and is the text it looks like. }
function LabelIsPlain(const S: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '\') and (i < Length(S)) then
      Inc(i, 2)
    else if S[i] in ['[', ']'] then
      Exit
    else
      Inc(i);
  end;
  Result := True;
end;

{ A line that is a link definition -- [label]: /url "title" -- rather than
  anything to show.  The destination and title are read the same way a
  link's own are, so a definition is wrong in the same places a link is and
  in no others. }
function DefinitionAt(const S: string;
  out ALabel, AUrl, ATitle: string): Boolean;
var
  T: string;
  Close: Integer;
begin
  Result := False;
  if IndentOf(S) >= 4 then Exit;
  T := Trim(S);
  if (T = '') or (T[1] <> '[') then Exit;
  Close := FindClose(T, ']', 2);
  if (Close < 3) or (Close >= Length(T)) or (T[Close + 1] <> ':') then Exit;
  ALabel := Copy(T, 2, Close - 2);
  if (Trim(ALabel) = '') or not LabelIsPlain(ALabel) then Exit;
  Result := SplitTarget(Copy(T, Close + 2, MaxInt), AUrl, ATitle) and
            (AUrl <> '');
end;

{ A link written in angle brackets -- <https://example.com>, <me@example.com>
  -- which is how a URL is put in a document that should show it as it is.
  AHref comes back with the mailto: an address needs. }
function AutolinkAt(const S: string; AAt: Integer; out AStop: Integer;
  out AHref, AText: string): Boolean;
var
  i, Colon, At_: Integer;
  Body: string;
begin
  Result := False;
  i := AAt + 1;
  while (i <= Length(S)) and not (S[i] in ['>', '<', ' ', #9]) do Inc(i);
  if (i > Length(S)) or (S[i] <> '>') then Exit;
  Body := Copy(S, AAt + 1, i - AAt - 1);
  { No escapes inside one: a backslash means this was never an autolink. }
  if (Body = '') or (Pos('\', Body) > 0) then Exit;
  AStop := i;
  AText := Body;
  Colon := Pos(':', Body);
  At_ := Pos('@', Body);
  { A scheme and something after it, or an address: anything else in angle
    brackets is left to the raw-tag reader below. }
  { A scheme is two characters at least -- "<m:abc>" is text, not a link. }
  if (Colon > 2) and (Colon <= 33) and (Colon < Length(Body)) then
  begin
    for i := 1 to Colon - 1 do
      if not (Body[i] in ['a'..'z', 'A'..'Z', '0'..'9', '+', '-', '.']) then Exit;
    AHref := Body;
    Result := True;
  end
  else if (At_ > 1) and (At_ < Length(Body)) and (Pos('.', Copy(Body, At_, MaxInt)) > 0) then
  begin
    AHref := 'mailto:' + Body;
    Result := True;
  end;
end;

{ Punctuation and whitespace, as the flanking rules below count them. }
function IsMdPunct(C: Char): Boolean;
begin
  Result := C in ['!'..'/', ':'..'@', '['..'`', '{'..'~'];
end;

function IsMdSpace(C: Char): Boolean;
begin
  Result := C in [' ', #9, #10, #13];
end;

{ Whether a run of * or _ can open emphasis, can close it, both or neither.

  Which side a delimiter faces is decided by what stands either side of it,
  not by how many have been seen -- CommonMark calls a run left-flanking
  when it is not followed by space and right-flanking when it is not
  preceded by space, with punctuation on the far side settling the cases
  where it is both.

  This is what keeps the asterisks in "2 * 3 * 4" as multiplication signs
  instead of turning the line italic, and it is why _ has a rule of its own:
  it may not open or close inside a word, so my_var_name is a name and not a
  name with var in italics.  An asterisk may, because **a**b is deliberate
  and a_b almost never is. }
procedure RunFlanks(const S: string; AFrom, ATo: Integer;
  out ACanOpen, ACanClose: Boolean);
var
  Prev, Next: Char;
  Left, Right: Boolean;
begin
  if AFrom > 1 then Prev := S[AFrom - 1] else Prev := ' ';
  if ATo < Length(S) then Next := S[ATo + 1] else Next := ' ';
  Left := (not IsMdSpace(Next)) and
          ((not IsMdPunct(Next)) or IsMdSpace(Prev) or IsMdPunct(Prev));
  Right := (not IsMdSpace(Prev)) and
           ((not IsMdPunct(Prev)) or IsMdSpace(Next) or IsMdPunct(Next));
  if S[AFrom] = '_' then
  begin
    ACanOpen := Left and ((not Right) or IsMdPunct(Prev));
    ACanClose := Right and ((not Left) or IsMdPunct(Next));
  end
  else
  begin
    ACanOpen := Left;
    ACanClose := Right;
  end;
end;

{ Where the run that closes emphasis opened with ACount of ACh begins, or 0.

  A run of another length is stepped over rather than taken, which is what
  lets *foo **bar** baz* close on the last asterisk and keep the pair in the
  middle for the inner pass -- it used to close on the first and leave three
  italics in a row.  Code spans are stepped over whole: a delimiter inside
  one is text. }
function EmphClose(const S: string; AFrom: Integer; ACh: Char;
  ACount: Integer): Integer;
var
  i, k, j: Integer;
  CanOpen, CanClose: Boolean;
begin
  Result := 0;
  i := AFrom;
  while i <= Length(S) do
  begin
    if (S[i] = '\') and (i < Length(S)) then
    begin
      Inc(i, 2);
      Continue;
    end;
    if S[i] = '`' then
    begin
      k := 0;
      while (i + k <= Length(S)) and (S[i + k] = '`') do Inc(k);
      j := CodeSpanEnd(S, i + k, k);
      if j > 0 then i := j + k else Inc(i, k);
      Continue;
    end;
    if S[i] = ACh then
    begin
      k := 0;
      while (i + k <= Length(S)) and (S[i + k] = ACh) do Inc(k);
      RunFlanks(S, i, i + k - 1, CanOpen, CanClose);
      if (k = ACount) and CanClose then Exit(i);
      Inc(i, k);
      Continue;
    end;
    Inc(i);
  end;
end;

{ The label a link to a definition uses, and where the whole of it ends.
  ABar is the ] that closes the link's text and AText what was inside it:
  [text][label] uses the label, [text][] and the bare [label] use the text
  itself.  False where what follows is an inline link's parenthesis, which
  belongs to the branch below, or a [ that is never closed. }
function RefTargetAt(const S: string; ABar: Integer; out AStop: Integer;
  out ALabel: string; const AText: string): Boolean;
var
  Close: Integer;
begin
  Result := False;
  ALabel := AText;
  AStop := ABar + 1;
  if ABar < Length(S) then
  begin
    if S[ABar + 1] = '(' then Exit;
    if S[ABar + 1] = '[' then
    begin
      Close := FindClose(S, ']', ABar + 2);
      if Close = 0 then Exit;
      if Close > ABar + 2 then
        ALabel := Copy(S, ABar + 2, Close - ABar - 2);
      AStop := Close + 1;
    end;
  end;
  Result := (Trim(ALabel) <> '') and LabelIsPlain(ALabel);
end;

{ The link definitions of the document being converted, as label=url, with
  the title after a #1 where there is one.

  A unit variable because the inline pass is a plain function called from a
  dozen places and from itself, and threading a table through all of it buys
  nothing: one document is converted at a time, on the thread that asked for
  it.  A quote converts its own contents by calling the converter again, and
  that call shares this table rather than making one -- a definition at the
  foot of a document is reachable from inside a quote in it. }
var
  MdDefs: TStringList = nil;

{ Labels match whatever their spacing and case: "[Foo Bar]" and "[foo  bar]"
  are the same label. }
function DefKey(const ALabel: string): string;
var
  i: Integer;
  Last: Char;
begin
  Result := '';
  Last := ' ';
  for i := 1 to Length(ALabel) do
    if ALabel[i] in [' ', #9, #10, #13] then
    begin
      if Last <> ' ' then Result := Result + ' ';
      Last := ' ';
    end
    else
    begin
      Result := Result + UpCase(ALabel[i]);
      Last := ALabel[i];
    end;
  Result := Trim(Result);
end;

function MdDefLookup(const ALabel: string; out AUrl, ATitle: string): Boolean;
var
  V: string;
  At_: Integer;
begin
  Result := False;
  AUrl := '';
  ATitle := '';
  if MdDefs = nil then Exit;
  if MdDefs.IndexOfName(DefKey(ALabel)) < 0 then Exit;
  V := MdDefs.Values[DefKey(ALabel)];
  At_ := Pos(#1, V);
  if At_ > 0 then
  begin
    AUrl := Copy(V, 1, At_ - 1);
    ATitle := Copy(V, At_ + 1, MaxInt);
  end
  else
    AUrl := V;
  Result := True;
end;

function InlineSpans(const AText: string): string;
var
  i, n, Close, Bar, Paren, Run, Next: Integer;
  Label_: string;
  Delim: Char;
  CanOpen, CanClose: Boolean;
  Title, Href, Shown: string;
  Out_: string;
  Url, Text: string;

  procedure Emit(const S: string);
  begin
    Out_ := Out_ + S;
  end;

begin
  Out_ := '';
  i := 1;
  n := Length(AText);
  while i <= n do
  begin
    { A backslash escapes the next character, which is how you write a
      literal asterisk. }
    if (AText[i] = '\') and (i < n) then
    begin
      { Before the end of a line it is the hard break; before anything else
        it is the escape that lets a literal asterisk be written. }
      if AText[i + 1] = #10 then
        Emit('<br>')
      else
        Emit(LedHtmlEscape(AText[i + 1]));
      Inc(i, 2);
      Continue;
    end;

    { Code spans come first: nothing inside them is markup.

      The opening run can be any number of backticks and is closed by a run
      of the same length, so a span can hold backticks of its own.  One space
      at each end is dropped where both are there, which is what lets a span
      start or end with a backtick: `` ` ``. }
    if AText[i] = '`' then
    begin
      Run := 0;
      while (i + Run <= n) and (AText[i + Run] = '`') do Inc(Run);
      Close := CodeSpanEnd(AText, i + Run, Run);
      if Close > 0 then
      begin
        Text := Copy(AText, i + Run, Close - i - Run);
        Text := StringReplace(Text, #10, ' ', [rfReplaceAll]);
        if (Length(Text) >= 2) and (Text[1] = ' ') and
           (Text[Length(Text)] = ' ') and (Trim(Text) <> '') then
          Text := Copy(Text, 2, Length(Text) - 2);
        Emit('<code>' + LedHtmlEscape(Text) + '</code>');
        i := Close + Run;
        Continue;
      end;
      { Never closed, so they are backticks and nothing more. }
      Emit(StringOfChar('`', Run));
      Inc(i, Run);
      Continue;
    end;

    { Images before links, since ![ ] ( ) starts with a bang. }
    if (AText[i] = '!') and (i < n) and (AText[i + 1] = '[') then
    begin
      Bar := FindClose(AText, ']', i + 2);
      if (Bar > 0) and RefTargetAt(AText, Bar, Next, Label_,
                                   Copy(AText, i + 2, Bar - i - 2)) and
         MdDefLookup(Label_, Url, Title) then
      begin
        if Title <> '' then
          Title := ' title="' + LedHtmlEscape(Title) + '"';
        Emit(Format('<img src="%s" alt="%s"%s>',
          [LedHtmlEscape(Url),
           LedHtmlEscape(Copy(AText, i + 2, Bar - i - 2)), Title]));
        i := Next;
        Continue;
      end;
      if (Bar > 0) and (Bar < n) and (AText[Bar + 1] = '(') then
      begin
        Paren := FindClose(AText, ')', Bar + 2);
        if (Paren > 0) and
           SplitTarget(Copy(AText, Bar + 2, Paren - Bar - 2), Url, Title) then
        begin
          Text := Copy(AText, i + 2, Bar - i - 2);
          if Title <> '' then
            Title := ' title="' + LedHtmlEscape(Title) + '"';
          Emit(Format('<img src="%s" alt="%s"%s>',
            [LedHtmlEscape(Url), LedHtmlEscape(Text), Title]));
          i := Paren + 1;
          Continue;
        end;
      end;
    end;

    if AText[i] = '[' then
    begin
      Bar := FindClose(AText, ']', i + 1);
      { A link to a definition further down -- [text][label], [text][] or
        just [label] -- which is how a document that uses a URL in several
        places writes it once.  Left as the text it is when no definition
        answers to the label, which is what "[see note]" in prose relies
        on. }
      if (Bar > 0) and RefTargetAt(AText, Bar, Next, Label_,
                                   Copy(AText, i + 1, Bar - i - 1)) and
         MdDefLookup(Label_, Url, Title) then
      begin
        if Title <> '' then
          Title := ' title="' + LedHtmlEscape(Title) + '"';
        Emit(Format('<a href="%s"%s>%s</a>',
          [LedHtmlEscape(Url), Title,
           InlineSpans(Copy(AText, i + 1, Bar - i - 1))]));
        i := Next;
        Continue;
      end;
      if (Bar > 0) and (Bar < n) and (AText[Bar + 1] = '(') then
      begin
        Paren := FindClose(AText, ')', Bar + 2);
        if (Paren > 0) and
           SplitTarget(Copy(AText, Bar + 2, Paren - Bar - 2), Url, Title) then
        begin
          Text := Copy(AText, i + 1, Bar - i - 1);
          if Title <> '' then
            Title := ' title="' + LedHtmlEscape(Title) + '"';
          Emit(Format('<a href="%s"%s>%s</a>',
            [LedHtmlEscape(Url), Title, InlineSpans(Text)]));
          i := Paren + 1;
          Continue;
        end;
      end;
    end;

    { Emphasis: one delimiter for <i>, two for <b>, three for both.  The run
      has to be able to open where it stands and the run that ends it has to
      be able to close where it stands, or the characters are characters. }
    if (AText[i] = '*') or (AText[i] = '_') then
    begin
      Delim := AText[i];
      Run := 0;
      while (i + Run <= n) and (AText[i + Run] = Delim) do Inc(Run);
      RunFlanks(AText, i, i + Run - 1, CanOpen, CanClose);
      if CanOpen then
      begin
        Close := EmphClose(AText, i + Run, Delim, Run);
        if Close > 0 then
        begin
          Text := InlineSpans(Copy(AText, i + Run, Close - i - Run));
          if Run = 1 then
            Emit('<i>' + Text + '</i>')
          else if Run = 2 then
            Emit('<b>' + Text + '</b>')
          else
            Emit('<b><i>' + Text + '</i></b>');
          i := Close + Run;
          Continue;
        end;
      end;
      Emit(StringOfChar(Delim, Run));
      Inc(i, Run);
      Continue;
    end;

    { A bare URL is a link.  People write them constantly and expect them to
      work. }
    if (Copy(AText, i, 7) = 'http://') or (Copy(AText, i, 8) = 'https://') then
    begin
      Close := i;
      while (Close <= n) and not (AText[Close] in [' ', #9, ')', '<', '>']) do
        Inc(Close);
      Url := Copy(AText, i, Close - i);
      Emit(Format('<a href="%s">%s</a>', [LedHtmlEscape(Url),
        LedHtmlEscape(Url)]));
      i := Close;
      Continue;
    end;

    if (AText[i] = '<') and AutolinkAt(AText, i, Close, Href, Shown) then
    begin
      Emit(Format('<a href="%s">%s</a>',
        [LedHtmlEscape(Href), LedHtmlEscape(Shown)]));
      i := Close + 1;
      Continue;
    end;

    { Raw HTML, which markdown allows and a notebook cell often carries. }
    if (AText[i] = '<') and RawTagAt(AText, i, Close) then
    begin
      Emit(Copy(AText, i, Close - i + 1));
      i := Close + 1;
      Continue;
    end;

    { The line ending a hard break left behind.  Code spans and raw tags are
      above this and keep theirs, which is why it is carried this far rather
      than written as a <br> when the lines were joined. }
    if AText[i] = #10 then
    begin
      Emit('<br>');
      Inc(i);
      Continue;
    end;

    Emit(LedHtmlEscape(AText[i]));
    Inc(i);
  end;
  Result := Out_;
end;

{ --- block structure ------------------------------------------------------- }

function IndentOf(const S: string): Integer;
begin
  Result := 0;
  while (Result < Length(S)) and (S[Result + 1] in [' ', #9]) do Inc(Result);
end;

function IsThematicBreak(const S: string): Boolean;
var
  T: string;
  C: Char;
  i, Count: Integer;
begin
  Result := False;
  { Four spaces in, a row of hyphens is not a rule: it is the text of the
    paragraph it sits under, or a line of code.  Given the whole line and not
    the trimmed one for exactly this reason. }
  if IndentOf(S) >= 4 then Exit;
  T := StringReplace(Trim(S), ' ', '', [rfReplaceAll]);
  if Length(T) < 3 then Exit;
  C := T[1];
  if not (C in ['-', '*', '_']) then Exit;
  Count := 0;
  for i := 1 to Length(T) do
  begin
    if T[i] <> C then Exit;
    Inc(Count);
  end;
  Result := Count >= 3;
end;

{ The level of the heading a line of = or - underneath a paragraph makes:
  1 for =, 2 for -, 0 for anything else.

  Markdown's older heading syntax, and still the one people type for a title
  and its first section, because it reads as a heading in the source.  It
  takes nothing but the one character, any number of them, with space allowed
  at either end -- "== ==" is a paragraph.

  Four spaces in is not an underline: that far in, the line is code.  The
  caller is the other half of the rule, and the harder half: only a line with
  a paragraph already open can be an underline, which is what keeps a row of
  hyphens with nothing above it the thematic break it has always been. }
function SetextLevel(const S: string): Integer;
var
  T: string;
  C: Char;
  i: Integer;
begin
  Result := 0;
  if IndentOf(S) >= 4 then Exit;
  T := Trim(S);
  if T = '' then Exit;
  C := T[1];
  if not (C in ['=', '-']) then Exit;
  for i := 2 to Length(T) do
    if T[i] <> C then Exit;
  if C = '=' then Result := 1 else Result := 2;
end;

function BulletAt(const S: string; out AContent: string;
  out AMarker: Char): Boolean;
var
  T: string;
begin
  AMarker := '-';
  T := TrimLeft(S);
  Result := (Length(T) > 1) and (T[1] in ['-', '*', '+']) and (T[2] = ' ');
  if Result then
  begin
    AContent := Copy(T, 3, MaxInt);
    AMarker := T[1];
  end;
end;

{ The column an item's own text starts in, which is the column the lines
  that carry it on line up with: the marker's own indent, the marker, and the
  spaces after it.  The spec counts one to four of those spaces; with five or
  more the text is indented code inside the item, and the item's content
  begins one space after the marker instead.

  It is measured per item and not assumed, because "-    foo" starts its text
  in column five and a line two spaces in is then not part of it at all. }
function ContentIndent(const S: string): Integer;
var
  T: string;
  k, n: Integer;
begin
  T := TrimLeft(S);
  k := 1;
  if (Length(T) > 0) and (T[1] in ['0'..'9']) then
  begin
    k := 0;
    while (k < Length(T)) and (T[k + 1] in ['0'..'9']) do Inc(k);
    Inc(k);                       { the . or ) that closes the marker }
  end;
  n := 0;
  while (k + n < Length(T)) and (T[k + n + 1] = ' ') do Inc(n);
  if (n < 1) or (n > 4) then n := 1;
  Result := IndentOf(S) + k + n;
end;

function OrderedAt(const S: string; out AContent: string;
  out ADelim: Char): Boolean;
var
  T: string;
  i: Integer;
begin
  Result := False;
  ADelim := '.';
  T := TrimLeft(S);
  i := 1;
  while (i <= Length(T)) and (T[i] in ['0'..'9']) do Inc(i);
  if (i = 1) or (i > Length(T)) then Exit;
  if not (T[i] in ['.', ')']) then Exit;
  if (i + 1 > Length(T)) or (T[i + 1] <> ' ') then Exit;
  AContent := Copy(T, i + 2, MaxInt);
  ADelim := T[i];
  Result := True;
end;

{ Whether a line opens a block of its own, which is what laziness turns on:
  a plain line of prose carries the paragraph above it on, and a heading or a
  list or a fence does not. }
function StartsABlock(const S: string): Boolean;
var
  T, Dummy: string;
  C: Char;
  Level: Integer;
begin
  Result := True;
  T := Trim(S);
  if T = '' then Exit;
  if T[1] = '>' then Exit;
  if IsThematicBreak(S) then Exit;
  if (Copy(T, 1, 3) = '```') or (Copy(T, 1, 3) = '~~~') then Exit;
  if BulletAt(S, Dummy, C) or OrderedAt(S, Dummy, C) then Exit;
  if T[1] = '#' then
  begin
    Level := 0;
    while (Level < Length(T)) and (T[Level + 1] = '#') do Inc(Level);
    if (Level <= 6) and (Level < Length(T)) and (T[Level + 1] = ' ') then Exit;
  end;
  Result := False;
end;

{ Whether a line ends in a break the author asked for: two spaces, which is
  how it has always been written, or the backslash CommonMark added because
  trailing spaces are invisible and editors eat them.

  An even number of backslashes is not one: the last of them is an escaped
  backslash, and the line ends in a character rather than a request. }
function EndsHard(const S: string): Boolean;
var
  T: string;
  k: Integer;
begin
  Result := False;
  if Length(S) < 2 then Exit;
  if (S[Length(S)] = ' ') and (S[Length(S) - 1] = ' ') then Exit(True);
  T := TrimRight(S);
  k := 0;
  while (k < Length(T)) and (T[Length(T) - k] = '\') do Inc(k);
  Result := Odd(k);
end;

function LedMarkdownToHTML(const AText: string; ALineIds: Boolean): string;
var
  Lines: TStringList;
  Out_: TStringList;
  i, Level: Integer;
  Line, Trimmed, Content, Fence, Lang: string;
  InCode: Boolean;
  Item, Code, Blanks, Quote: string;
  CodeLine, QuoteLine: Integer;
  Hard, ParaHard: Boolean;
  Marker: Char;
  ItemIndent: Integer;         { the text column of the item last emitted }
  { A blank line was read with a list still open, and -- once the line after
    it has been seen -- that line stands across the gap from its item. }
  BlankInList, ItemGap: Boolean;
  Para: string;
  ParaLine: Integer;           { where the paragraph being gathered began }
  ListStack: TStringList;      { open list tags, innermost last }

  { The id for a block that starts on ALine, counting from one as an editor
    does, or nothing at all when the caller did not ask for them. }
  function Anchor(ALine: Integer): string;
  begin
    if ALineIds then
      Result := ' id="L' + IntToStr(ALine) + '"'
    else
      Result := '';
  end;

  { A fragment that is already HTML, kept as the lines it came in: Out_ is a
    list of lines and the passes that run over the result -- the <pre>
    wrapper, the heading flattener -- read it that way. }
  procedure AddLines(const AHtml: string);
  var
    L: TStringList;
    k: Integer;
  begin
    L := TStringList.Create;
    try
      L.Text := AHtml;
      for k := 0 to L.Count - 1 do
        Out_.Add(L[k]);
    finally
      L.Free;
    end;
  end;

  { Link definitions, out of the document before it is read as blocks: a line
    saying where [label] points is not a line to show.  Blanked rather than
    deleted, so that the line a block reports as its own stays the line it is
    on in the editor -- the ids are what the preview scrolls by.

    Only where a block could start, because a definition cannot interrupt a
    paragraph: "[see 1]: that was the plan" under a line of prose is prose. }
  procedure CollectDefs;
  var
    k: Integer;
    InFence_: Boolean;
    Fence_, Lab, U, T, Trim_: string;
    CanStart: Boolean;
  begin
    InFence_ := False;
    Fence_ := '';
    CanStart := True;
    for k := 0 to Lines.Count - 1 do
    begin
      Trim_ := Trim(Lines[k]);
      if InFence_ then
      begin
        if Copy(Trim_, 1, Length(Fence_)) = Fence_ then InFence_ := False;
        CanStart := False;
        Continue;
      end;
      if (Copy(Trim_, 1, 3) = '```') or (Copy(Trim_, 1, 3) = '~~~') then
      begin
        InFence_ := True;
        Fence_ := Copy(Trim_, 1, 3);
        CanStart := False;
        Continue;
      end;
      if CanStart and DefinitionAt(Lines[k], Lab, U, T) then
      begin
        if MdDefs.IndexOfName(DefKey(Lab)) < 0 then
        begin
          { The first of a repeated label wins, as the spec has it. }
          if T <> '' then U := U + #1 + T;
          MdDefs.Add(DefKey(Lab) + '=' + U);
        end;
        Lines[k] := '';
        CanStart := True;
        Continue;
      end;
      CanStart := Trim_ = '';
    end;
  end;

  procedure FlushPara;
  begin
    if Para <> '' then
    begin
      Out_.Add('<p' + Anchor(ParaLine) + '>' + InlineSpans(Para) + '</p>');
      Para := '';
    end;
  end;

  { Each entry is the tag and then the marker the list was opened with --
    "ul-", "ol." -- because a list is its own marker: the spec ends one and
    starts another where the bullet or the delimiter changes, and that has to
    be noticed now that a blank line between items leaves the list open. }
  procedure CloseLists(ToDepth: Integer);
  begin
    while ListStack.Count > ToDepth do
    begin
      Out_.Add('</' + Copy(ListStack[ListStack.Count - 1], 1, 2) + '>');
      ListStack.Delete(ListStack.Count - 1);
    end;
  end;

  { Opens the list this item belongs in, closing one of another kind that is
    open at the same depth.  Without this an ordered item went on inside the
    <ul> above it, as an <li> with no list of its own. }
  procedure OpenList(ADepth: Integer; const AKind: string);
  begin
    while ListStack.Count > ADepth + 1 do CloseLists(ListStack.Count - 1);
    if (ListStack.Count = ADepth + 1) and (ListStack[ADepth] <> AKind) then
      CloseLists(ADepth);
    if ListStack.Count < ADepth + 1 then
    begin
      Out_.Add('<' + Copy(AKind, 1, 2) + '>');
      ListStack.Add(AKind);
    end;
  end;

  { A table row's cells.

    The separator is a pipe, and a pipe written "\|" is a pipe in the text.
    That escape has to be honoured here, before anything else looks at the
    line, because this is where the cells are decided -- and it holds inside
    a code span as well, which is the one place the ordinary escapes do not
    reach.  It is how a table of operators is written at all: a row saying
    "`expr1 \|\| expr2`  | `\|\|` for logical OR" is four cells and a
    row of stray backslashes otherwise. }
  function SplitCells(const ARow: string): TStringArray;
  var
    i, n: Integer;
    Cur: string;

    procedure Take;
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Cur;
      Cur := '';
    end;

  begin
    SetLength(Result, 0);
    Cur := '';
    i := 1;
    n := Length(ARow);
    while i <= n do
    begin
      if (ARow[i] = '\') and (i < n) and (ARow[i + 1] = '|') then
      begin
        { The pipe, without the backslash that let it through. }
        Cur := Cur + '|';
        Inc(i, 2);
        Continue;
      end;
      { A backslash before anything else is left alone: the inline pass
        reads those, and eating one here would turn "\*" into "*". }
      if (ARow[i] = '\') and (i < n) then
      begin
        Cur := Cur + ARow[i] + ARow[i + 1];
        Inc(i, 2);
        Continue;
      end;
      if ARow[i] = '|' then
      begin
        Take;
        Inc(i);
        Continue;
      end;
      Cur := Cur + ARow[i];
      Inc(i);
    end;
    Take;
  end;

  procedure EmitTableRow(const ARow: string; AHeader: Boolean; ALine: Integer);
  var
    Cells: TStringArray;
    c: Integer;
    Cell, Tag: string;
  begin
    Cell := Trim(ARow);
    if (Cell <> '') and (Cell[1] = '|') then Delete(Cell, 1, 1);
    { The pipe that closes the row, if it is one: a row may end with an
      escaped pipe instead, and that one is text. }
    if (Length(Cell) > 1) and (Cell[Length(Cell)] = '|') and
       (Cell[Length(Cell) - 1] <> '\') then
      SetLength(Cell, Length(Cell) - 1)
    else if Cell = '|' then
      Cell := '';
    Cells := SplitCells(Cell);
    if AHeader then Tag := 'th' else Tag := 'td';
    Out_.Add('<tr' + Anchor(ALine) + '>');
    for c := 0 to High(Cells) do
      Out_.Add(Format('<%s>%s</%s>', [Tag, InlineSpans(Trim(Cells[c])), Tag]));
    Out_.Add('</tr>');
  end;

  function IsTableDivider(const S: string): Boolean;
  var
    T: string;
    k: Integer;
  begin
    T := StringReplace(Trim(S), ' ', '', [rfReplaceAll]);
    Result := (Pos('|', T) > 0) and (Pos('-', T) > 0);
    if not Result then Exit;
    for k := 1 to Length(T) do
      if not (T[k] in ['|', '-', ':']) then Exit(False);
  end;

var
  InTable: Boolean;
  OwnDefs: Boolean;
begin
  { The outermost call owns the definitions; a quote converting its own
    contents shares them. }
  OwnDefs := MdDefs = nil;
  if OwnDefs then MdDefs := TStringList.Create;
  Lines := TStringList.Create;
  Out_ := TStringList.Create;
  ListStack := TStringList.Create;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    Lines.Text := StringReplace(
      StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
    InCode := False;
    InTable := False;
    BlankInList := False;
    ItemGap := False;
    ParaHard := False;
    ItemIndent := 2;
    Para := '';
    ParaLine := 1;
    Fence := '';

    CollectDefs;

    i := 0;
    while i < Lines.Count do
    begin
      Line := Lines[i];
      Trimmed := Trim(Line);

      { A fenced block swallows everything until its closing fence, markup
        and all. }
      if InCode then
      begin
        if (Copy(Trimmed, 1, Length(Fence)) = Fence) and
           (Trim(Copy(Trimmed, Length(Fence) + 1, MaxInt)) = '') then
        begin
          Out_.Add('</pre>');
          InCode := False;
        end
        else
          Out_.Add(LedHtmlEscape(Line));
        Inc(i);
        Continue;
      end;

      if (Copy(Trimmed, 1, 3) = '```') or (Copy(Trimmed, 1, 3) = '~~~') then
      begin
        FlushPara;
        CloseLists(0);
        Fence := Copy(Trimmed, 1, 3);
        { The word after the fence is the language it is in, and it is worth
          keeping: a renderer that can colour C can only do it if it is told
          the block is C.  Carried the way every other tool carries it, as a
          class on the tag, which a renderer that does not care ignores. }
        Lang := LowerCase(Trim(Copy(Trimmed, 4, MaxInt)));
        if Pos(' ', Lang) > 0 then Lang := Copy(Lang, 1, Pos(' ', Lang) - 1);
        if LedIsLanguageWord(Lang) then
          Out_.Add('<pre class="language-' + Lang + '"' + Anchor(i + 1) + '>')
        else
          Out_.Add('<pre' + Anchor(i + 1) + '>');
        InCode := True;
        Inc(i);
        Continue;
      end;

      if Trimmed = '' then
      begin
        FlushPara;
        { A blank line does not end a list on its own.  An item holds blocks,
          not a line -- "a sequence of lines Ls constitute a sequence of
          blocks Bs" -- so a gap inside one is a paragraph break in the item,
          and only what comes after the gap says whether the list is over.
          Held here, and answered by the next line that is not blank. }
        if ListStack.Count > 0 then
          BlankInList := True
        else
          CloseLists(0);
        if InTable then
        begin
          Out_.Add('</table>');
          InTable := False;
        end;
        Inc(i);
        Continue;
      end;

      { What follows that gap, now that there is a line to look at.  Another
        item, or text indented into the item above, and the list carries on;
        anything else, and it ended at the blank line.  No laziness here: an
        unindented line after a gap is a new paragraph, because the item's
        paragraph closed with the blank line and there is nothing left to
        continue. }
      ItemGap := False;
      if BlankInList then
      begin
        BlankInList := False;
        if not (BulletAt(Line, Content, Marker) or
                OrderedAt(Line, Content, Marker)) then
        begin
          { Not a further item, so it is either indented into the item above
            -- another paragraph of it -- or the list ended at the gap.  The
            item's own text column decides which, not a fixed depth. }
          if IndentOf(Line) >= ItemIndent then
            ItemGap := True
          else
            CloseLists(0);
        end;
      end;

      { Before the thematic break, which a row of hyphens otherwise is.  With
        a paragraph open the row is that paragraph's underline and the two
        together are a heading -- that order is the whole of the rule, and
        reversing it is what rendered a section title as a paragraph with a
        line drawn under it. }
      Level := SetextLevel(Line);
      if (Level > 0) and (Para <> '') then
      begin
        { Anchored to where the text is, not to the underline: a click in the
          preview should land on the title the reader can see. }
        Out_.Add(Format('<h%d%s>%s</h%d>',
          [Level, Anchor(ParaLine), InlineSpans(Para), Level]));
        Para := '';
        Inc(i);
        Continue;
      end;

      if IsThematicBreak(Line) then
      begin
        FlushPara;
        CloseLists(0);
        Out_.Add('<hr' + Anchor(i + 1) + '>');
        Inc(i);
        Continue;
      end;

      if Trimmed[1] = '#' then
      begin
        Level := 0;
        while (Level < Length(Trimmed)) and (Trimmed[Level + 1] = '#') do
          Inc(Level);
        if (Level >= 1) and (Level <= 6) and
           (Level < Length(Trimmed)) and (Trimmed[Level + 1] = ' ') then
        begin
          FlushPara;
          CloseLists(0);
          Out_.Add(Format('<h%d%s>%s</h%d>',
            [Level, Anchor(i + 1),
             InlineSpans(Trim(Copy(Trimmed, Level + 1, MaxInt))), Level]));
          Inc(i);
          Continue;
        end;
      end;

      { A quote is every line of it, not one line each.

        "> a" over "> b" was two quotes of one line, and a heading or a list
        inside a quote was the text of it with the hashes showing.  The lines
        are gathered, the markers taken off, and the result converted the way
        the document itself is -- so a quote holds whatever a document holds,
        for the cost of the call.  Line ids stop at the quote, which carries
        the one for its first line: the ids are a scroll map, and the map
        only has to be able to find the block. }
      { Four spaces in it is code and not a quote -- and the test has to be
        made here as well as in the loop below, because the loop takes the
        line this branch was entered on: a branch that consumes nothing
        leaves the outer loop reading the same line for ever. }
      if (Trimmed[1] = '>') and (IndentOf(Line) < 4) then
      begin
        FlushPara;
        CloseLists(0);
        Quote := '';
        QuoteLine := i + 1;
        while i < Lines.Count do
        begin
          Line := Lines[i];
          Trimmed := Trim(Line);
          if (IndentOf(Line) < 4) and (Trimmed <> '') and (Trimmed[1] = '>') then
          begin
            { the marker, and the one space that may follow it }
            Content := Copy(Trimmed, 2, MaxInt);
            if (Content <> '') and (Content[1] = ' ') then
              Delete(Content, 1, 1);
            Quote := Quote + Content + LineEnding;
          end
          { Laziness again: a plain line under a quoted paragraph is quoted
            too, as long as it starts nothing of its own. }
          else if (Trimmed <> '') and (Quote <> '') and not StartsABlock(Line) then
            Quote := Quote + Trimmed + LineEnding
          else
            Break;
          Inc(i);
        end;
        Out_.Add('<blockquote' + Anchor(QuoteLine) + '>');
        AddLines(LedMarkdownToHTML(Quote, False));
        Out_.Add('</blockquote>');
        Continue;
      end;

      { A pipe table is recognised by its divider row, which is the only
        thing that distinguishes it from a paragraph containing bars. }
      if (Pos('|', Line) > 0) and (i + 1 < Lines.Count) and
         IsTableDivider(Lines[i + 1]) and not InTable then
      begin
        FlushPara;
        CloseLists(0);
        Out_.Add('<table border="1" cellspacing="0" cellpadding="3"' +
          Anchor(i + 1) + '>');
        EmitTableRow(Line, True, i + 1);
        InTable := True;
        Inc(i, 2);
        Continue;
      end;
      if InTable then
      begin
        if Pos('|', Line) > 0 then
        begin
          EmitTableRow(Line, False, i + 1);
          Inc(i);
          Continue;
        end;
        Out_.Add('</table>');
        InTable := False;
      end;

      if BulletAt(Line, Content, Marker) then
      begin
        FlushPara;
        ItemIndent := ContentIndent(Line);
        OpenList(IndentOf(Line) div 2, 'ul' + Marker);
        Out_.Add('<li' + Anchor(i + 1) + '>' + InlineSpans(Content) + '</li>');
        Inc(i);
        Continue;
      end;

      if OrderedAt(Line, Content, Marker) then
      begin
        FlushPara;
        ItemIndent := ContentIndent(Line);
        OpenList(IndentOf(Line) div 2, 'ol' + Marker);
        Out_.Add('<li' + Anchor(i + 1) + '>' + InlineSpans(Content) + '</li>');
        Inc(i);
        Continue;
      end;

      { More of the item above.

        CommonMark gives a list item its text two ways.  Under "Basic case"
        the continuation is indented to where the item's own text starts, and
        under "Laziness" that indentation may be partly or entirely left off:
        a plain line of prose under an item is the item's, however far in it
        begins.  Both arrive here, because every line that starts a block of
        its own -- a fence, a heading, a quote, a rule, a table, a further
        item -- has been dealt with above, and what is left is what the spec
        calls paragraph continuation text.

        Appended to the item rather than written after it: the item was
        closed when it was emitted, and the text belongs inside it.  Joined
        with a space, as this renderer joins the lines of a paragraph.

        After a blank line it is a second paragraph of the item instead,
        which is the one case that is not just more of the same sentence. }
      if (ListStack.Count > 0) and (Out_.Count > 0) and
         (RightStr(Out_[Out_.Count - 1], 5) = '</li>') then
      begin
        Item := Copy(Out_[Out_.Count - 1], 1,
                     Length(Out_[Out_.Count - 1]) - 5);
        { Four spaces past the item's own text is code inside the item, and
          has to stay code: it is how a command or a snippet is written under
          the step that runs it.  Carried on by the lines after it at the
          same depth, blank line or not, so a block of several lines is one
          <pre> and not one apiece. }
        if (IndentOf(Line) >= ItemIndent + 4) and
           (ItemGap or (RightStr(Item, 6) = '</pre>')) then
        begin
          Code := LedHtmlEscape(Copy(Line, ItemIndent + 5, MaxInt));
          if RightStr(Item, 6) = '</pre>' then
            Item := Copy(Item, 1, Length(Item) - 6) + LineEnding + Code +
                    '</pre>'
          else
            Item := Item + '<pre>' + Code + '</pre>';
        end
        else if ItemGap then
          Item := Item + '<p>' + InlineSpans(Trimmed) + '</p>'
        { Inside the paragraph the item already ended with, not after it:
          the second line of a second paragraph is still that paragraph. }
        else if RightStr(Item, 4) = '</p>' then
          Item := Copy(Item, 1, Length(Item) - 4) + ' ' +
                  InlineSpans(Trimmed) + '</p>'
        else
          Item := Item + ' ' + InlineSpans(Trimmed);
        Out_[Out_.Count - 1] := Item + '</li>';
        Inc(i);
        Continue;
      end;

      { An indented block with no list open is a code block -- all of it, and
        the blank lines inside it.  A <pre> per line put every line of a
        sample in a box of its own. }
      if (IndentOf(Line) >= 4) and (ListStack.Count = 0) and (Para = '') then
      begin
        Code := '';
        Blanks := '';
        CodeLine := i + 1;
        while i < Lines.Count do
        begin
          Line := Lines[i];
          if Trim(Line) = '' then
            { Held rather than written: a blank line after the last indented
              line is the one that ends the block, and is not part of it. }
            Blanks := Blanks + LineEnding
          else if IndentOf(Line) >= 4 then
          begin
            if Code <> '' then Code := Code + LineEnding;
            Code := Code + Blanks + LedHtmlEscape(Copy(Line, 5, MaxInt));
            Blanks := '';
          end
          else
            Break;
          Inc(i);
        end;
        Out_.Add('<pre' + Anchor(CodeLine) + '>' + Code + '</pre>');
        Continue;
      end;

      CloseLists(0);
      { A line ending in two spaces, or in a backslash, is a break the author
        asked for -- an address, a verse, a line that has to stand alone --
        and the lines were simply run together.  The marker is read off the
        line before the trim takes it away, and acted on when the next line
        is added. }
      Hard := EndsHard(Line);
      if Para = '' then
      begin
        Para := Trimmed;
        { The line the paragraph starts on, not the one it ends on: a
          hard-wrapped paragraph is one block and belongs to its first line. }
        ParaLine := i + 1;
      end
      else if ParaHard then
      begin
        { Kept as the line ending it was, for the inline pass to make a <br>
          of.  Written in here as one it would be a <br> inside a code span
          and inside the attribute of a tag as well -- and the backslash that
          asked for it is left in place for the same reason: inside a code
          span it is a backslash and not a request. }
        Para := Para + #10 + Trimmed;
      end
      else
        Para := Para + ' ' + Trimmed;
      ParaHard := Hard;
      Inc(i);
    end;

    FlushPara;
    CloseLists(0);
    if InCode then Out_.Add('</pre>');
    if InTable then Out_.Add('</table>');
    Result := Out_.Text;
  finally
    ListStack.Free;
    Out_.Free;
    Lines.Free;
    if OwnDefs then FreeAndNil(MdDefs);
  end;
end;

function LedMarkdownToPage(const AText, ATitle: string;
  ALineIds: Boolean): string;
begin
  Result :=
    '<html><head><title>' + LedHtmlEscape(ATitle) + '</title>' +
    '<style>' +
    'body { font-family: sans-serif; margin: 12px; }' +
    'pre { background: #f4f4f4; padding: 6px; }' +
    'code { background: #f4f4f4; }' +
    'blockquote { color: #555; border-left: 3px solid #ccc; padding-left: 8px; }' +
    'table { border-collapse: collapse; }' +
    '</style></head><body>' + LedMarkdownToHTML(AText, ALineIds) +
    '</body></html>';
end;

end.
