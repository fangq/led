// led - a lightweight editor.  The headings of a document, in order.
//
// What the Outline pane shows for a Markdown file, a wiki page or a notebook:
// the sections and subsections, nested, in the order they appear.  ctags can
// list the headings of a Markdown file too, but it reports them as a flat set
// of tags grouped by kind, which is the wrong shape for a document -- a
// reader of a lecture wants the table of contents, not "chapters: 7,
// sections: 19" with each one scoped by the file it came from.
//
// Levels, not indentation: a heading's level is what nests it, and the pane
// turns levels into a tree.  A document that starts at "##" and never uses
// "#" nests from there, because what matters is the order the levels come in
// and not their absolute number.

unit Led.Core.Outline;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TLedOutlineItem = record
    Level: Integer;    { 1 for a top-level heading, 2 for one inside it }
    Title: string;     { the heading's text, with its markers taken off }
    Line: Integer;     { 1-based, in the text it was read from }
  end;
  TLedOutline = array of TLedOutlineItem;

{ The headings of a Markdown document.

  Both spellings: "## Section", and a line underlined with === or ---, which
  is what a heading written by hand in an older style looks like.  A line
  inside a fenced code block is not a heading however many hashes it starts
  with -- "#!/bin/sh" in a shell example, "# a remark" in Python -- and that
  is the one thing an outline has to get right about code. }
function LedOutlineOfMarkdown(const AText: string): TLedOutline;

{ The same for a wiki page, in the dialect Led.Core.Wiki reads: "= Title =",
  "== Section ==", with the level given by how many equals signs. }
function LedOutlineOfWiki(const AText: string): TLedOutline;

{ The sectioning of a LaTeX document, in its order: \part, \chapter,
  \section, \subsection, \subsubsection, \paragraph, \subparagraph, and a
  beamer frame's title.  Numbered as LaTeX numbers them (chapters, when there
  are any, above sections; \appendix letters from there on; a starred one
  not numbered), its short title ([...]) when it has one, as a table of
  contents would show it.  Not in a comment or a verbatim block.  The line is
  the command's. }
function LedOutlineOfLatex(const AText: string): TLedOutline;
{ a LaTeX file by its name: .tex, .ltx, .latex }
function LedIsLatexName(const AFileName: string): Boolean;

{ Appends one item.  Public because a notebook's outline is built cell by
  cell, by a caller that knows which buffer line each cell starts on. }
procedure LedOutlineAdd(var AOutline: TLedOutline; ALevel: Integer;
  const ATitle: string; ALine: Integer);

implementation

procedure LedOutlineAdd(var AOutline: TLedOutline; ALevel: Integer;
  const ATitle: string; ALine: Integer);
begin
  SetLength(AOutline, Length(AOutline) + 1);
  AOutline[High(AOutline)].Level := ALevel;
  AOutline[High(AOutline)].Title := ATitle;
  AOutline[High(AOutline)].Line := ALine;
end;

{ A fence is three or more backticks or tildes, and it ends with the same
  character it opened with: a ``` block may contain ~~~ and the other way
  round. }
function FenceChar(const ALine: string): Char;
var
  T: string;
begin
  Result := #0;
  T := TrimLeft(ALine);
  if Length(T) < 3 then Exit;
  if (Copy(T, 1, 3) = '```') or (Copy(T, 1, 3) = '~~~') then Result := T[1];
end;

function LedOutlineOfMarkdown(const AText: string): TLedOutline;
var
  Lines: TStringList;
  i, Level: Integer;
  Line, Title, Next: string;
  Fence: Char;
begin
  SetLength(Result, 0);
  Lines := TStringList.Create;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    Lines.Text := AText;
    Fence := #0;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];

      { Inside a fenced block nothing is a heading.  A hash is a comment in
        half the languages a notebook holds. }
      if Fence <> #0 then
      begin
        if FenceChar(Line) = Fence then Fence := #0;
        Continue;
      end;
      if FenceChar(Line) <> #0 then
      begin
        Fence := FenceChar(Line);
        Continue;
      end;

      Title := TrimLeft(Line);
      if (Title <> '') and (Title[1] = '#') then
      begin
        Level := 0;
        while (Level < Length(Title)) and (Title[Level + 1] = '#') do
          Inc(Level);
        { Seven hashes is not a heading, and "#tag" is not one either: a
          heading has a space after its hashes. }
        if (Level >= 1) and (Level <= 6) and
           ((Level >= Length(Title)) or (Title[Level + 1] = ' ')) then
        begin
          Title := Trim(Copy(Title, Level + 1, MaxInt));
          { The closing hashes of "## Section ##", which are decoration. }
          while (Title <> '') and (Title[Length(Title)] = '#') do
            SetLength(Title, Length(Title) - 1);
          LedOutlineAdd(Result, Level, Trim(Title), i + 1);
        end;
        Continue;
      end;

      { The underlined spelling: the text is this line and the level comes
        from what underlines it. }
      if (Trim(Line) <> '') and (i + 1 < Lines.Count) then
      begin
        Next := Trim(Lines[i + 1]);
        if (Next <> '') and
           ((Next = StringOfChar('=', Length(Next))) or
            (Next = StringOfChar('-', Length(Next)))) and
           (Length(Next) >= 2) then
        begin
          if Next[1] = '=' then Level := 1 else Level := 2;
          LedOutlineAdd(Result, Level, Trim(Line), i + 1);
        end;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- LaTeX ---- }

function LedIsLatexName(const AFileName: string): Boolean;
var
  E: string;
begin
  E := LowerCase(ExtractFileExt(AFileName));
  Result := (E = '.tex') or (E = '.ltx') or (E = '.latex');
end;

(* a title's LaTeX as text: \emph{x} as x, \label and \footnote left out, ~ a space, the blanks run together *)
function LatexTitleText(const S: string): string;
var
  i, j, D: Integer;
  Name: string;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] = '\' then
    begin
      j := i + 1;
      while (j <= Length(S)) and (S[j] in ['a'..'z', 'A'..'Z']) do Inc(j);
      Name := Copy(S, i + 1, j - i - 1);
      if Name = '' then
      begin   (* \& \% \_ \$ \# \{ \}: the character; \\: a space *)
        if (j <= Length(S)) and (S[j] in ['&', '%', '_', '$', '#', '{', '}']) then Result := Result + S[j]
        else Result := Result + ' ';
        i := j + 1;
        Continue;
      end;
      i := j;
      if (Name = 'label') or (Name = 'footnote') or (Name = 'thanks') or (Name = 'index') or (Name = 'cite') or
         (Name = 'protect') or (Name = 'texorpdfstring') then
      begin
        while (i <= Length(S)) and (S[i] = ' ') do Inc(i);
        if (Name = 'texorpdfstring') and (i <= Length(S)) and (S[i] = '{') then
        begin   { its first argument is for the page; the second, the bookmark's, is plain text: kept }
          D := 0;
          repeat
            if S[i] = '{' then Inc(D) else if S[i] = '}' then Dec(D);
            Inc(i);
          until (i > Length(S)) or (D = 0);
          Continue;
        end;
        if (Name <> 'protect') and (i <= Length(S)) and (S[i] = '{') then
        begin
          D := 0;
          repeat
            if S[i] = '{' then Inc(D) else if S[i] = '}' then Dec(D);
            Inc(i);
          until (i > Length(S)) or (D = 0);
          if Name = 'cite' then Result := Result + '[ ]';
        end;
        Continue;
      end;
      if Name = 'LaTeX' then Result := Result + 'LaTeX'
      else if Name = 'TeX' then Result := Result + 'TeX';
      Continue;
    end;
    if S[i] in ['{', '}', '$'] then
    begin
      Inc(i);
      Continue;
    end;
    if (S[i] = '~') or (S[i] < ' ') then Result := Result + ' ' else Result := Result + S[i];
    Inc(i);
  end;
  { the blanks run together }
  Result := Trim(Result);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
end;

function LedOutlineOfLatex(const AText: string): TLedOutline;
const
  Cmds: array[0..7] of string = ('part', 'chapter', 'section', 'subsection', 'subsubsection', 'paragraph',
    'subparagraph', 'frametitle');
var
  i, j, k, D, Line, CmdLine, Level, Lev: Integer;
  N: array[0..7] of Integer;
  Name, Title, Short, Num, VerbEnd: string;
  Star, HasChapter, Appendix: Boolean;

  (* from i, at an opening brace or bracket: its content (to the matching close), i past it; '' if it does not close *)
  function Group(AOpen, AClose: Char): string;
  var
    St: Integer;
  begin
    Result := '';
    if (i > Length(AText)) or (AText[i] <> AOpen) then Exit;
    St := i;
    D := 0;
    while i <= Length(AText) do
    begin
      if AText[i] = '\' then
      begin
        if (i < Length(AText)) and (AText[i + 1] = #10) then Inc(Line);
        Inc(i, 2);
        Continue;
      end;
      if AText[i] = #10 then Inc(Line);
      if AText[i] = AOpen then Inc(D)
      else if (AText[i] = AClose) then
      begin
        Dec(D);
        if D = 0 then
        begin
          Result := Copy(AText, St + 1, i - St - 1);
          Inc(i);
          Exit;
        end;
      end;
      Inc(i);
    end;
  end;

  procedure SkipBlank;
  begin
    while (i <= Length(AText)) and (AText[i] in [' ', #9, #13, #10]) do
    begin
      if AText[i] = #10 then Inc(Line);
      Inc(i);
    end;
  end;

begin
  SetLength(Result, 0);
  HasChapter := Pos('\chapter', AText) > 0;
  Appendix := False;
  for k := 0 to High(N) do N[k] := 0;
  VerbEnd := '';
  Line := 1;
  i := 1;
  while i <= Length(AText) do
  begin
    case AText[i] of
      #10:
        begin
          Inc(Line);
          Inc(i);
          Continue;
        end;
      '%':
        begin   { a comment: to the end of the line }
          while (i <= Length(AText)) and (AText[i] <> #10) do Inc(i);
          Continue;
        end;
      '\':
        ;
    else
      Inc(i);
      Continue;
    end;
    { verbatim, and what is like it: nothing in it is a command }
    if VerbEnd <> '' then
    begin
      if Copy(AText, i, Length(VerbEnd)) = VerbEnd then
      begin
        Inc(i, Length(VerbEnd));
        VerbEnd := '';
      end
      else
        Inc(i);
      Continue;
    end;
    j := i + 1;
    while (j <= Length(AText)) and (AText[j] in ['a'..'z', 'A'..'Z']) do Inc(j);
    Name := Copy(AText, i + 1, j - i - 1);
    if Name = '' then
    begin
      if (j <= Length(AText)) and (AText[j] = #10) then Inc(Line);
      Inc(i, 2);    (* \% \\ \{ ...: not a comment, not a command *)
      Continue;
    end;
    CmdLine := Line;
    i := j;
    if Name = 'begin' then
    begin
      Title := Group('{', '}');
      if (Title = 'verbatim') or (Title = 'verbatim*') or (Title = 'lstlisting') or (Title = 'minted') or
         (Title = 'comment') or (Title = 'Verbatim') then
        VerbEnd := '\end{' + Title + '}'
      else if Title = 'frame' then
      begin   (* beamer: \begin{frame}{Title} (an option before it passed over) *)
        SkipBlank;
        if (i <= Length(AText)) and (AText[i] = '[') then Group('[', ']');
        SkipBlank;
        Title := LatexTitleText(Group('{', '}'));
        if Title <> '' then LedOutlineAdd(Result, 8, Title, CmdLine);
      end;
      Continue;
    end;
    if Name = 'appendix' then
    begin
      Appendix := True;
      if HasChapter then N[1] := 0 else N[2] := 0;
      Continue;
    end;
    Lev := -1;
    for k := 0 to High(Cmds) do
      if Name = Cmds[k] then Lev := k;
    if Lev < 0 then Continue;
    Star := (i <= Length(AText)) and (AText[i] = '*');
    if Star then Inc(i);
    SkipBlank;
    Short := '';
    if (i <= Length(AText)) and (AText[i] = '[') then Short := Group('[', ']');
    SkipBlank;
    Title := Group('{', '}');
    if Short <> '' then Title := Short;
    (* \section{#1} in a macro's definition: not a section *)
    if Pos('#', Title) > 0 then Continue;
    Title := LatexTitleText(Title);
    if Title = '' then Continue;
    Level := Lev + 1;
    { its number: chapters (when there are any) then sections; a subsubsection numbered in an article only }
    Num := '';
    if not Star and (Lev >= 1) and (Lev <= 4) and ((Lev >= 2) or HasChapter) and not ((Lev = 4) and HasChapter) then
    begin
      Inc(N[Lev]);
      for k := Lev + 1 to 4 do N[k] := 0;
      for k := 1 to Lev do
      begin
        if (k = 1) and not HasChapter then Continue;
        if Num <> '' then Num := Num + '.';
        if Appendix and (k = 1 + Ord(not HasChapter)) then
          Num := Num + Chr(Ord('A') + (N[k] - 1) mod 26)
        else
          Num := Num + IntToStr(N[k]);
      end;
      Title := Num + '  ' + Title;
    end;
    if Lev = 7 then Level := 8;
    LedOutlineAdd(Result, Level, Title, CmdLine);
  end;
end;

function LedOutlineOfWiki(const AText: string): TLedOutline;
var
  Lines: TStringList;
  i, Level: Integer;
  Line, Title: string;
begin
  SetLength(Result, 0);
  Lines := TStringList.Create;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    Lines.Text := AText;
    for i := 0 to Lines.Count - 1 do
    begin
      Title := Trim(Lines[i]);
      if (Title = '') or (Title[1] <> '=') then Continue;
      Level := 0;
      while (Level < Length(Title)) and (Title[Level + 1] = '=') do Inc(Level);
      if (Level < 1) or (Level > 6) or (Level >= Length(Title)) then Continue;
      Title := Trim(Copy(Title, Level + 1, MaxInt));
      { The closing equals signs, which a wiki heading repeats. }
      while (Title <> '') and (Title[Length(Title)] = '=') do
        SetLength(Title, Length(Title) - 1);
      Title := Trim(Title);
      if Title = '' then Continue;
      LedOutlineAdd(Result, Level, Title, i + 1);
    end;
  finally
    Lines.Free;
  end;
end;

end.
