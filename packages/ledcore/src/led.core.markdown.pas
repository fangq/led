{ led - a light editor.  Markdown to HTML.

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
  Classes, SysUtils;

{ Converts Markdown to an HTML fragment.  Wrap it yourself, or use
  LedMarkdownToPage for a whole document with a stylesheet. }
function LedMarkdownToHTML(const AText: string): string;
function LedMarkdownToPage(const AText, ATitle: string): string;
function LedHtmlEscape(const AText: string): string;

implementation

function LedHtmlEscape(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
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
