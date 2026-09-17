{ LED - a lightweight editor.  Styling a rendered page.

  Two panes in LED render HTML: the notebook's cells, and the Markdown and
  wiki preview.  They had the same three faults and only the notebook's had
  been mended, which is the argument for this unit existing.

  The renderer draws in its own colours unless it is told otherwise, so a
  page on a dark theme came out as black text on a black background, tables
  worst of all.  A fenced block that named its language was not coloured,
  though LED has the highlighter for it.  And monospaced text came out
  proportional -- see LedPageColourCode, which is the least guessable of the
  three.

  Nothing here knows about notebooks or about wiki files: it is handed a page
  and the colours to draw it in. }

unit Led.UI.PageStyle;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Graphics, SynEditHighlighter,
  Led.Core.Markdown, Led.Syn.Factory, Led.Syn.Theme, Led.UI.Document;

type
  { The colours a page is drawn in, all of them derived from the theme. }
  TLedPageColours = record
    Page, Text, Muted, CodeBg, Border, Link: TColor;
  end;

{ The current theme's colours, for a page.

  Only two are read -- the page and the text -- and the rest are mixed from
  those, which is what makes this work for a scheme nobody has seen: a code
  block a few per cent away from the page is a code block on a light theme
  and on a dark one, where a fixed grey is right on one and wrong on the
  other. }
function LedPageColours: TLedPageColours;

{ A colour as HTML says it.  TColor is $00BBGGRR and HTML wants RRGGBB, so
  this is not a hex dump of the number. }
function LedHtmlColour(AColour: TColor): string;

{ Colours the code in a rendered page, and gives its tables the page's own
  text colour.

  Every stretch of code is given the page's text colour, and the contents of
  a fence that named a language LED can colour are run through that
  language's highlighter and written out a token at a time.

  Deliberately no font is named.  The renderer resolves a face through
  FindFontName, which parses the value with CommaText -- and CommaText splits
  on spaces, so "Fira Code" is read as a font called "Fira", not found, and
  quietly replaced by the menu font.  That is what made every monospaced
  stretch of a page come out proportional.  A <code> takes FixedTypeface
  straight from the panel with no such parsing, and a nested <font> that
  names no face inherits it, so the block carries the face and the tokens
  carry the colours.

  A fenced block comes out as a <code> with a <br> at the end of each line
  rather than as the <pre> the Markdown writer produced, because this
  renderer cannot show code in a <pre> at all.  Inside one it takes the text
  as already-decoded and escapes it again, so "&lt;" is drawn as those four
  characters -- which is what a C notebook full of "i &lt; count" looked
  like.  Writing the "<" raw instead does not help: the tokeniser reads "<"
  followed by a letter as a tag whatever it is inside, so "#include
  <stdio.h>" simply vanished.  Outside a <pre> the escapes are read properly,
  and what a <pre> was doing for the layout is done here instead: a line ends
  with a <br>, and a space that carries alignment is written as a
  non-breaking one.  Single spaces between words are left ordinary, so a long
  line can still be broken where a reader would break it. }
function LedPageColourCode(const AHtml: string;
  ATextColour, ABackColour: TColor): string;

{ The two halves of a page in a theme's colours, for a caller to put its own
  body between.  AMargin is the body's own margin: none for a notebook cell,
  which is already inside a box with its own padding, and a little for a
  whole document, where text against the edge of the pane is hard to read. }
function LedPageHead(const ATitle: string;
  const AColours: TLedPageColours; AMargin: Integer = 0): string;
function LedPageTail: string;

implementation

function LedPageColours: TLedPageColours;
var
  Style: TLedStyle;
begin
  Result.Page := clWindow;
  Result.Text := clWindowText;
  if LedCurrentTheme <> nil then
    if LedCurrentTheme.Find(LedStyleText, Style) then
    begin
      if lsfBackground in Style.Flags then
        Result.Page := LedColourToTColor(Style.Background);
      if lsfForeground in Style.Flags then
        Result.Text := LedColourToTColor(Style.Foreground);
    end;
  if Result.Page = clNone then Result.Page := clWindow;
  if Result.Text = clNone then Result.Text := clWindowText;

  { A code block sits a little away from the page, the way it does in a
    notebook front end; the label beside it recedes.

    LedMixColours takes the percentage of its *first* colour, so "mostly the
    page" is a high number.  Getting that backwards put the code block at 93
    per cent of the text colour -- a near-white slab on a dark theme. }
  Result.CodeBg := LedMixColours(Result.Page, Result.Text, 93);
  Result.Border := LedMixColours(Result.Page, Result.Text, 78);
  Result.Muted := LedEnsureReadable(
    LedMixColours(Result.Text, Result.Page, 62), Result.Page, 3.0);
  { Links have to be readable on the page as well as look like links. }
  Result.Link := LedEnsureReadable($00D08040, Result.Page, 4.0);
end;

function LedHtmlColour(AColour: TColor): string;
begin
  AColour := ColorToRGB(AColour);
  Result := Format('#%.2x%.2x%.2x',
    [AColour and $FF, (AColour shr 8) and $FF, (AColour shr 16) and $FF]);
end;

{ The text of an HTML-escaped run, back as it was written.  The page carries
  code escaped, and a highlighter wants the code. }
function Unescaped(const AText: string): string;
begin
  Result := StringReplace(AText, '&lt;', '<', [rfReplaceAll]);
  Result := StringReplace(Result, '&gt;', '>', [rfReplaceAll]);
  Result := StringReplace(Result, '&quot;', '"', [rfReplaceAll]);
  Result := StringReplace(Result, '&#39;', '''', [rfReplaceAll]);
  { Last, so that an escaped ampersand does not turn the text after it into
    another escape. }
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll]);
end;

{ Which of a line's spaces have to be written as non-breaking ones.

  Outside a <pre> a run of spaces is one space and a leading run is nothing
  at all, and a code block is very largely its alignment: indentation, and
  the columns people line their comments up in.  So a leading run and any run
  of two or more are marked, and a single space between two words is left
  alone -- an ordinary space is the only place the renderer may break a long
  line, and a block of nothing but non-breaking spaces makes the whole page
  as wide as its longest line. }
function NbspMask(const ALine: string): string;
var
  i, n: Integer;
begin
  Result := StringOfChar('0', Length(ALine));
  i := 1;
  while i <= Length(ALine) do
    if ALine[i] = ' ' then
    begin
      n := 0;
      while (i + n <= Length(ALine)) and (ALine[i + n] = ' ') do Inc(n);
      if (i = 1) or (n > 1) then
        FillChar(Result[i], n, '1');
      Inc(i, n);
    end
    else
      Inc(i);
end;

{ One token of a line, escaped, with the spaces the mask marked kept.
  AStart is the token's column, counting from one, so the mask is read at the
  place the token actually came from. }
function CodeText(const AText: string; AStart: Integer;
  const AMask: string): string;
var
  i, Col: Integer;
begin
  Result := '';
  for i := 1 to Length(AText) do
  begin
    Col := AStart + i - 1;
    if (AText[i] = ' ') and (Col >= 1) and (Col <= Length(AMask)) and
       (AMask[Col] = '1') then
      Result := Result + '&nbsp;'
    else
      Result := Result + LedHtmlEscape(AText[i]);
  end;
end;

{ One block of code, tokenised by ALang's highlighter and written out as
  coloured spans, one <br>-terminated line at a time.  A language LED cannot
  colour comes back as plain text in the page's own colour, which is what a
  file of that language would get in the editor too. }
function ColouredCode(const ACode, ALang: string;
  ATextColour, ABackColour: TColor): string;
var
  HL: TSynCustomHighlighter;
  Lines: TStringList;
  i: Integer;
  Attr: TSynHighlighterAttributes;
  Colour: TColor;
  Painted, Mask, Line: string;
begin
  Result := '';
  HL := nil;
  if ALang <> '' then HL := LedCreateHighlighter(ALang);

  Lines := TStringList.Create;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    Lines.Text := ACode;
    { The blank line the fence itself left at either end is not part of the
      code, and with the block's own <br>s it would be drawn as one. }
    while (Lines.Count > 0) and (Lines[Lines.Count - 1] = '') do
      Lines.Delete(Lines.Count - 1);
    while (Lines.Count > 0) and (Lines[0] = '') do Lines.Delete(0);

    if HL = nil then
    begin
      for i := 0 to Lines.Count - 1 do
      begin
        Line := Lines[i];
        if i > 0 then Result := Result + '<br>' + #10;
        Result := Result + CodeText(Line, 1, NbspMask(Line));
      end;
      Exit;
    end;

    LedApplyThemeToHighlighter(LedCurrentTheme, HL);
    HL.ResetRange;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      Mask := NbspMask(Line);
      { In order and without resetting between lines: that is what carries a
        string or a comment from one line of the block to the next. }
      HL.SetLine(Line, i);
      Painted := '';
      while not HL.GetEol do
      begin
        Attr := HL.GetTokenAttribute;
        Colour := ATextColour;
        if (Attr <> nil) and (Attr.Foreground <> clNone) then
          Colour := Attr.Foreground;
        { Against the block's own background rather than the page's: a colour
          chosen to be read on one is not always readable on the other. }
        Colour := LedEnsureReadable(Colour, ABackColour, 3.0);
        Painted := Painted + '<font color="' + LedHtmlColour(Colour) + '">' +
          CodeText(HL.GetToken, HL.GetTokenPos + 1, Mask) + '</font>';
        HL.Next;
      end;
      if i > 0 then Result := Result + '<br>' + #10;
      Result := Result + Painted;
    end;
  finally
    Lines.Free;
    HL.Free;
  end;
end;

{ Wraps what is inside every AOpen..AClose in the page's text colour.  Used
  for table cells, which the renderer otherwise draws in black whatever the
  page says -- unreadable on a dark theme beside prose that is fine. }
function ColourCells(const AHtml, AOpen, AClose: string;
  ATextColour: TColor): string;
var
  At, Start, Stop, Close_: Integer;
  Body, Replacement, Lower: string;
begin
  Result := AHtml;
  At := 1;
  while True do
  begin
    Lower := LowerCase(Result);
    Start := PosEx(AOpen, Lower, At);
    if Start = 0 then Break;
    Close_ := PosEx('>', Result, Start);
    if Close_ = 0 then Break;
    Stop := PosEx(AClose, Lower, Close_);
    if Stop = 0 then Break;

    Body := Copy(Result, Close_ + 1, Stop - Close_ - 1);
    { Already coloured -- a cell holding code, say -- and left alone. }
    if Pos('<font', LowerCase(Body)) = 1 then
    begin
      At := Stop + Length(AClose);
      Continue;
    end;
    Replacement := Copy(Result, Start, Close_ - Start + 1) +
      '<font color="' + LedHtmlColour(ATextColour) + '">' + Body + '</font>';
    Result := Copy(Result, 1, Start - 1) + Replacement +
      Copy(Result, Stop, MaxInt);
    At := Start + Length(Replacement);
  end;
end;

function LedPageColourCode(const AHtml: string;
  ATextColour, ABackColour: TColor): string;
var
  At, Start, Stop, Close_, Quote: Integer;
  Head, Lang, Body, Replacement, Lower: string;
begin
  Result := AHtml;

  { ---- inline code ----

    Before the fenced blocks, because those are rewritten into <code> as
    well and this pass would then find them and wrap them a second time. }
  At := 1;
  while True do
  begin
    Lower := LowerCase(Result);
    Start := PosEx('<code>', Lower, At);
    if Start = 0 then Break;
    Stop := PosEx('</code>', Lower, Start);
    if Stop = 0 then Break;
    Body := Copy(Result, Start + 6, Stop - Start - 6);
    Replacement := '<code><font color="' + LedHtmlColour(ATextColour) + '">' +
      Body + '</font></code>';
    Result := Copy(Result, 1, Start - 1) + Replacement +
      Copy(Result, Stop + Length('</code>'), MaxInt);
    At := Start + Length(Replacement);
  end;

  { ---- table cells ---- }
  Result := ColourCells(Result, '<td', '</td>', ATextColour);
  Result := ColourCells(Result, '<th', '</th>', ATextColour);

  { ---- fenced blocks ---- }
  At := 1;
  while True do
  begin
    Lower := LowerCase(Result);
    Start := PosEx('<pre', Lower, At);
    if Start = 0 then Break;
    Close_ := PosEx('>', Result, Start);
    if Close_ = 0 then Break;
    Stop := PosEx('</pre>', Lower, Close_);
    if Stop = 0 then Break;

    Head := Copy(Result, Start, Close_ - Start + 1);
    Lang := '';
    Quote := Pos('class="language-', LowerCase(Head));
    if Quote > 0 then
    begin
      Lang := Copy(Head, Quote + Length('class="language-'), MaxInt);
      Quote := Pos('"', Lang);
      if Quote > 0 then Lang := Copy(Lang, 1, Quote - 1);
    end;

    Body := Copy(Result, Close_ + 1, Stop - Close_ - 1);
    { The language it named is carried over onto the <code>, so that what
      the page says about itself survives the rewrite. }
    Replacement := '<p><code';
    if Lang <> '' then Replacement := Replacement + ' class="language-' +
      Lang + '"';
    Replacement := Replacement + '><font color="' +
      LedHtmlColour(ATextColour) + '">' +
      ColouredCode(Unescaped(Body), Lang, ATextColour, ABackColour) +
      '</font></code></p>';
    Result := Copy(Result, 1, Start - 1) + Replacement +
      Copy(Result, Stop + Length('</pre>'), MaxInt);
    At := Start + Length(Replacement);
  end;
end;

function LedPageHead(const ATitle: string;
  const AColours: TLedPageColours; AMargin: Integer): string;
begin
  { The colours are set as body attributes as well as in the style sheet,
    because this renderer reads rather little CSS and the attributes are the
    ones that decide the background. }
  Result :=
    '<html><head><title>' + LedHtmlEscape(ATitle) + '</title><style>' +
    'body { margin: ' + IntToStr(AMargin) +
      'px; font-family: sans-serif; color: ' +
      LedHtmlColour(AColours.Text) + '; }' +
    'h1, h2, h3, h4 { margin: 6px 0 4px 0; }' +
    'p { margin: 4px 0 8px 0; }' +
    'pre, code { background: ' + LedHtmlColour(AColours.CodeBg) + '; }' +
    'blockquote { border-left: 3px solid ' + LedHtmlColour(AColours.Border) +
      '; padding-left: 8px; }' +
    'a { color: ' + LedHtmlColour(AColours.Link) + '; }' +
    'table { border-collapse: collapse; }' +
    '</style></head>' +
    '<body bgcolor="' + LedHtmlColour(AColours.Page) + '" text="' +
      LedHtmlColour(AColours.Text) + '" link="' +
      LedHtmlColour(AColours.Link) + '" vlink="' +
      LedHtmlColour(AColours.Link) + '">';
end;

function LedPageTail: string;
begin
  Result := '</body></html>';
end;

end.
