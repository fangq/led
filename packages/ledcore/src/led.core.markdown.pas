{ led - a lightweight editor.  Markdown to HTML.

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
  LedMarkdownToPage for a whole document with a stylesheet. }
function LedMarkdownToHTML(const AText: string): string;
function LedMarkdownToPage(const AText, ATitle: string): string;
function LedHtmlEscape(const AText: string): string;

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

implementation

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
  and breaking the span would break the line. }
function IsFontOnlyTag(const AName: string): Boolean;
begin
  case AName of
    'b', 'strong', 'i', 'em', 'code', 'tt', 'kbd', 'samp', 'var', 'cite',
    'dfn', 'big', 'small': Result := True;
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

function InlineSpans(const AText: string): string;
var
  i, n, Close, Bar, Paren: Integer;
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
      Emit(LedHtmlEscape(AText[i + 1]));
      Inc(i, 2);
      Continue;
    end;

    { Code spans come first: nothing inside them is markup. }
    if AText[i] = '`' then
    begin
      Close := FindClose(AText, '`', i + 1);
      if Close > 0 then
      begin
        Emit('<code>' + LedHtmlEscape(Copy(AText, i + 1, Close - i - 1)) +
             '</code>');
        i := Close + 1;
        Continue;
      end;
    end;

    { Images before links, since ![ ] ( ) starts with a bang. }
    if (AText[i] = '!') and (i < n) and (AText[i + 1] = '[') then
    begin
      Bar := FindClose(AText, ']', i + 2);
      if (Bar > 0) and (Bar < n) and (AText[Bar + 1] = '(') then
      begin
        Paren := FindClose(AText, ')', Bar + 2);
        if Paren > 0 then
        begin
          Text := Copy(AText, i + 2, Bar - i - 2);
          Url := Copy(AText, Bar + 2, Paren - Bar - 2);
          Emit(Format('<img src="%s" alt="%s">',
            [LedHtmlEscape(Url), LedHtmlEscape(Text)]));
          i := Paren + 1;
          Continue;
        end;
      end;
    end;

    if AText[i] = '[' then
    begin
      Bar := FindClose(AText, ']', i + 1);
      if (Bar > 0) and (Bar < n) and (AText[Bar + 1] = '(') then
      begin
        Paren := FindClose(AText, ')', Bar + 2);
        if Paren > 0 then
        begin
          Text := Copy(AText, i + 1, Bar - i - 1);
          Url := Copy(AText, Bar + 2, Paren - Bar - 2);
          Emit(Format('<a href="%s">%s</a>',
            [LedHtmlEscape(Url), InlineSpans(Text)]));
          i := Paren + 1;
          Continue;
        end;
      end;
    end;

    if (Copy(AText, i, 2) = '**') or (Copy(AText, i, 2) = '__') then
    begin
      Close := FindClose(AText, Copy(AText, i, 2), i + 2);
      if Close > 0 then
      begin
        Emit('<b>' + InlineSpans(Copy(AText, i + 2, Close - i - 2)) + '</b>');
        i := Close + 2;
        Continue;
      end;
    end;

    if (AText[i] = '*') or (AText[i] = '_') then
    begin
      Close := FindClose(AText, AText[i], i + 1);
      if Close > i + 1 then
      begin
        Emit('<i>' + InlineSpans(Copy(AText, i + 1, Close - i - 1)) + '</i>');
        i := Close + 1;
        Continue;
      end;
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
  T := StringReplace(Trim(S), ' ', '', [rfReplaceAll]);
  Result := False;
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

function BulletAt(const S: string; out AContent: string): Boolean;
var
  T: string;
begin
  T := TrimLeft(S);
  Result := (Length(T) > 1) and (T[1] in ['-', '*', '+']) and (T[2] = ' ');
  if Result then AContent := Copy(T, 3, MaxInt);
end;

function OrderedAt(const S: string; out AContent: string): Boolean;
var
  T: string;
  i: Integer;
begin
  Result := False;
  T := TrimLeft(S);
  i := 1;
  while (i <= Length(T)) and (T[i] in ['0'..'9']) do Inc(i);
  if (i = 1) or (i > Length(T)) then Exit;
  if not (T[i] in ['.', ')']) then Exit;
  if (i + 1 > Length(T)) or (T[i + 1] <> ' ') then Exit;
  AContent := Copy(T, i + 2, MaxInt);
  Result := True;
end;

function LedMarkdownToHTML(const AText: string): string;
var
  Lines: TStringList;
  Out_: TStringList;
  i, Level, Ind: Integer;
  Line, Trimmed, Content, Fence: string;
  InCode: Boolean;
  Para: string;
  ListStack: TStringList;      { open list tags, innermost last }

  procedure FlushPara;
  begin
    if Para <> '' then
    begin
      Out_.Add('<p>' + InlineSpans(Para) + '</p>');
      Para := '';
    end;
  end;

  procedure CloseLists(ToDepth: Integer);
  begin
    while ListStack.Count > ToDepth do
    begin
      Out_.Add('</' + ListStack[ListStack.Count - 1] + '>');
      ListStack.Delete(ListStack.Count - 1);
    end;
  end;

  procedure EmitTableRow(const ARow: string; AHeader: Boolean);
  var
    Cells: TStringArray;
    c: Integer;
    Cell, Tag: string;
  begin
    Cell := Trim(ARow);
    if (Cell <> '') and (Cell[1] = '|') then Delete(Cell, 1, 1);
    if (Cell <> '') and (Cell[Length(Cell)] = '|') then
      SetLength(Cell, Length(Cell) - 1);
    Cells := Cell.Split(['|']);
    if AHeader then Tag := 'th' else Tag := 'td';
    Out_.Add('<tr>');
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
begin
  Lines := TStringList.Create;
  Out_ := TStringList.Create;
  ListStack := TStringList.Create;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    Lines.Text := StringReplace(
      StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
    InCode := False;
    InTable := False;
    Para := '';
    Fence := '';

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
        Out_.Add('<pre>');
        InCode := True;
        Inc(i);
        Continue;
      end;

      if Trimmed = '' then
      begin
        FlushPara;
        CloseLists(0);
        if InTable then
        begin
          Out_.Add('</table>');
          InTable := False;
        end;
        Inc(i);
        Continue;
      end;

      if IsThematicBreak(Trimmed) then
      begin
        FlushPara;
        CloseLists(0);
        Out_.Add('<hr>');
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
          Out_.Add(Format('<h%d>%s</h%d>',
            [Level, InlineSpans(Trim(Copy(Trimmed, Level + 1, MaxInt))), Level]));
          Inc(i);
          Continue;
        end;
      end;

      if Trimmed[1] = '>' then
      begin
        FlushPara;
        CloseLists(0);
        Out_.Add('<blockquote>' +
          InlineSpans(Trim(Copy(Trimmed, 2, MaxInt))) + '</blockquote>');
        Inc(i);
        Continue;
      end;

      { A pipe table is recognised by its divider row, which is the only
        thing that distinguishes it from a paragraph containing bars. }
      if (Pos('|', Line) > 0) and (i + 1 < Lines.Count) and
         IsTableDivider(Lines[i + 1]) and not InTable then
      begin
        FlushPara;
        CloseLists(0);
        Out_.Add('<table border="1" cellspacing="0" cellpadding="3">');
        EmitTableRow(Line, True);
        InTable := True;
        Inc(i, 2);
        Continue;
      end;
      if InTable then
      begin
        if Pos('|', Line) > 0 then
        begin
          EmitTableRow(Line, False);
          Inc(i);
          Continue;
        end;
        Out_.Add('</table>');
        InTable := False;
      end;

      if BulletAt(Line, Content) then
      begin
        FlushPara;
        Ind := IndentOf(Line) div 2;
        while ListStack.Count > Ind + 1 do CloseLists(ListStack.Count - 1);
        if ListStack.Count < Ind + 1 then
        begin
          Out_.Add('<ul>');
          ListStack.Add('ul');
        end;
        Out_.Add('<li>' + InlineSpans(Content) + '</li>');
        Inc(i);
        Continue;
      end;

      if OrderedAt(Line, Content) then
      begin
        FlushPara;
        Ind := IndentOf(Line) div 2;
        while ListStack.Count > Ind + 1 do CloseLists(ListStack.Count - 1);
        if ListStack.Count < Ind + 1 then
        begin
          Out_.Add('<ol>');
          ListStack.Add('ol');
        end;
        Out_.Add('<li>' + InlineSpans(Content) + '</li>');
        Inc(i);
        Continue;
      end;

      { An indented block with no list open is a code block. }
      if (IndentOf(Line) >= 4) and (ListStack.Count = 0) and (Para = '') then
      begin
        Out_.Add('<pre>' + LedHtmlEscape(Copy(Line, 5, MaxInt)) + '</pre>');
        Inc(i);
        Continue;
      end;

      CloseLists(0);
      if Para = '' then Para := Trimmed else Para := Para + ' ' + Trimmed;
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
  end;
end;

function LedMarkdownToPage(const AText, ATitle: string): string;
begin
  Result :=
    '<html><head><title>' + LedHtmlEscape(ATitle) + '</title>' +
    '<style>' +
    'body { font-family: sans-serif; margin: 12px; }' +
    'pre { background: #f4f4f4; padding: 6px; }' +
    'code { background: #f4f4f4; }' +
    'blockquote { color: #555; border-left: 3px solid #ccc; padding-left: 8px; }' +
    'table { border-collapse: collapse; }' +
    '</style></head><body>' + LedMarkdownToHTML(AText) + '</body></html>';
end;

end.
