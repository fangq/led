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
