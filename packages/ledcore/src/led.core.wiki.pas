{ led - a light editor.  Wiki markup to HTML.

  medit renders a UseMod / Habitat dialect of wiki markup in its preview
  pane, from an in-tree converter in moopagepreview.cpp.  led dropped it up
  front as "a niche format", which was a judgement about other people's
  files rather than about this one's users; it is back because it is used.

  The dialect is medit's, rule for rule, so a file that renders there renders
  here:

    ----            a horizontal rule; six or more dashes draws a thick one
    = Title =       headings, one to six leading '=' with a matching tail
    == # Title ==   the '#' also numbers the heading and lists it in <toc>
    <toc>           on a line of its own, expands to the table of contents
    * item          unordered list, one '*' per level
    # item          ordered list, one '#' per level
    ; term : def    definition list
    : text          indented block, one ':' per level
    ||a||b||        table row of cells, !!a!!b!! for header cells
    '''bold'''      and ''italic'', '''''both''''', `code`
    [[Page]]        a link, [[Page|shown as this]] to relabel it
    [url text]      an explicit link; a bare url is linked where it stands
    [#name]         a named anchor
    WikiWord        CamelCase is a link, as it is in every wiki of this line
    <nowiki>..      protected: nowiki, pre and code are passed through

  Anything that matches no rule is escaped and emitted as text, which is
  medit's choice too: unknown syntax should look wrong, not disappear.

  No LCL dependency, so the headless suite can cover it. }
unit Led.Core.Wiki;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Led.Core.Markdown;

{ Converts wiki markup to an HTML fragment. }
function LedWikiToHTML(const AText: string): string;
{ ...and to a whole page, with the same stylesheet the Markdown preview uses. }
function LedWikiToPage(const AText, ATitle: string): string;

{ True when this looks like a wiki file: the extensions medit claims, or a
  first line of "<!-- wiki -->". }
function LedIsWikiFile(const AFileName, AFirstLine: string): Boolean;

implementation

type
  TWikiHeading = record
    Level: Integer;
    Title: string;
    Anchor: string;
    Number: string;
  end;

  { The list state machine.  Held apart from the generic block stack because
    HTML wants a nested list inside the parent's <li>, not beside it, so an
    item's tag stays open until its children are done with it. }
  TWikiList = record
    Kind: Char;        { 'u' unordered, 'o' ordered, 'd' definition }
    ItemOpen: Boolean;
  end;

  TWikiCtx = record
    Out_: TStringList;
    Saved: TStringList;      { protected regions, by placeholder index }
    Lists: array of TWikiList;
    Headings: array of TWikiHeading;
    Counters: array[0..6] of Integer;
    AnchorSeq: Integer;
    LinkSeq: Integer;
    InPara: Boolean;
    InTable: Boolean;
    AnchorsSeen: TStringList;
  end;

const
  { Placeholders bracket a protected region's index.  medit uses #1 for this;
    here it has to be DEL, because FPC's Trim strips everything up to and
    including a space, so a #1-delimited marker on a line of its own came
    back from Trim as a bare "0" and the region was lost.  DEL is above the
    space, survives Trim, and no wiki file contains one. }
  PH = #127;

{ --- small helpers --------------------------------------------------------- }

function IsWordChar(C: Char): Boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9'];
end;

function Slugify(const AText: string): string;
var
  i: Integer;
  C: Char;
  Last: Boolean;
begin
  Result := '';
  Last := False;
  for i := 1 to Length(AText) do
  begin
    C := AText[i];
    if IsWordChar(C) then
    begin
      Result := Result + LowerCase(C);
      Last := False;
    end
    else if not Last then
    begin
      if Result <> '' then Result := Result + '-';
      Last := True;
    end;
  end;
  while (Result <> '') and (Result[Length(Result)] = '-') do
    Delete(Result, Length(Result), 1);
end;

function SaveRaw(var C: TWikiCtx; const AHtml: string): string;
begin
  C.Saved.Add(AHtml);
  Result := PH + IntToStr(C.Saved.Count - 1) + PH;
end;

procedure Emit(var C: TWikiCtx; const S: string);
begin
  C.Out_.Add(S);
end;

{ --- inline ---------------------------------------------------------------- }

{ How many characters of a URL start at position I, or 0. }
function MatchUrl(const S: string; I: Integer): Integer;
const
  Schemes: array[0..5] of string =
    ('http://', 'https://', 'ftp://', 'mailto:', 'file://', 'news:');
var
  k, J: Integer;
begin
  Result := 0;
  for k := 0 to High(Schemes) do
    if (Length(S) - I + 1 >= Length(Schemes[k])) and
       SameText(Copy(S, I, Length(Schemes[k])), Schemes[k]) then
    begin
      J := I + Length(Schemes[k]);
      while (J <= Length(S)) and not (S[J] in [' ', #9, '<', '>', '"', '''',
                                               ']', '}', '|']) do
        Inc(J);
      { Trailing punctuation belongs to the sentence, not the address. }
      while (J > I) and (S[J - 1] in ['.', ',', ';', ':', '!', '?', ')']) do
        Dec(J);
      Exit(J - I);
    end;
end;

{ A CamelCase word: an upper, some lowers, another upper, and no more
  uppercase runs than that pattern allows.  medit's wiki_match_wikiword. }
function MatchWikiWord(const S: string; I: Integer): Integer;
var
  J: Integer;
  Humps: Integer;
  SawLower: Boolean;
begin
  Result := 0;
  if (I > 1) and (IsWordChar(S[I - 1])) then Exit;
  if not (S[I] in ['A'..'Z']) then Exit;

  J := I;
  Humps := 0;
  SawLower := False;
  while (J <= Length(S)) and IsWordChar(S[J]) do
  begin
    if S[J] in ['a'..'z'] then
      SawLower := True
    else if (S[J] in ['A'..'Z']) and SawLower then
    begin
      Inc(Humps);
      SawLower := False;
    end;
    Inc(J);
  end;
  if Humps >= 1 then Result := J - I;
end;

{ Wraps every ADelim..ADelim pair.  The delimiters are identical, so this
  walks in pairs and leaves an unmatched trailing one alone. }
function ApplyPair(const S, ADelim, AOpen, AClose: string): string;
var
  I, J, D: Integer;
begin
  Result := '';
  D := Length(ADelim);
  I := 1;
  while I <= Length(S) do
  begin
    if (I + D - 1 <= Length(S)) and (Copy(S, I, D) = ADelim) then
    begin
      J := I + D;
      while (J + D - 1 <= Length(S)) and (Copy(S, J, D) <> ADelim) do Inc(J);
      if J + D - 1 <= Length(S) then
      begin
        Result := Result + AOpen + Copy(S, I + D, J - I - D) + AClose;
        I := J + D;
        Continue;
      end;
    end;
    Result := Result + S[I];
    Inc(I);
  end;
end;

function WikiInline(var C: TWikiCtx; const AText: string): string;
var
  I, L, Bar, Close_: Integer;
  Body, Href, Label_, Raw, Rest: string;
  S: string;
begin
  S := AText;
  Result := '';
  I := 1;

  { Links first, stashed as placeholders, so the emphasis pass below cannot
    reach inside an href and turn // into italics. }
  while I <= Length(S) do
  begin
    { [#name] -- a named anchor, invisible. }
    if (I + 1 <= Length(S)) and (S[I] = '[') and (S[I + 1] = '#') then
    begin
      Close_ := PosEx(']', S, I + 2);
      if Close_ > I + 2 then
      begin
        Body := Copy(S, I + 2, Close_ - I - 2);
        if C.AnchorsSeen.IndexOf(Body) < 0 then
        begin
          C.AnchorsSeen.Add(Body);
          Result := Result + SaveRaw(C,
            '<a name="' + LedHtmlEscape(Body) + '"></a>');
        end;
        I := Close_ + 1;
        Continue;
      end;
    end;

    { [[Page]] and [[Page|label]]. }
    if (I + 1 <= Length(S)) and (S[I] = '[') and (S[I + 1] = '[') then
    begin
      Close_ := Pos(']]', Copy(S, I + 2, Length(S)));
      if Close_ > 0 then
      begin
        Body := Copy(S, I + 2, Close_ - 1);
        Bar := Pos('|', Body);
        if Bar > 0 then
        begin
          Href := Copy(Body, 1, Bar - 1);
          Label_ := Copy(Body, Bar + 1, Length(Body));
        end
        else
        begin
          Href := Body;
          Label_ := Body;
        end;
        Result := Result + SaveRaw(C,
          '<a href="' + LedHtmlEscape(StringReplace(Trim(Href), ' ', '_',
            [rfReplaceAll])) + '">' + LedHtmlEscape(Trim(Label_)) + '</a>');
        I := I + 2 + Close_ + 1;
        Continue;
      end;
    end;

    { [url label] and [url]. }
    if (S[I] = '[') then
    begin
      L := MatchUrl(S, I + 1);
      if L > 0 then
      begin
        Close_ := PosEx(']', S, I + 1 + L);
        if Close_ > 0 then
        begin
          Href := Copy(S, I + 1, L);
          Rest := Trim(Copy(S, I + 1 + L, Close_ - I - 1 - L));
          if Rest = '' then
          begin
            Inc(C.LinkSeq);
            Rest := '[' + IntToStr(C.LinkSeq) + ']';
          end;
          Result := Result + SaveRaw(C,
            '<a href="' + LedHtmlEscape(Href) + '">' +
            LedHtmlEscape(Rest) + '</a>');
          I := Close_ + 1;
          Continue;
        end;
      end;
    end;

    { A bare address. }
    L := MatchUrl(S, I);
    if L > 0 then
    begin
      Href := Copy(S, I, L);
      Result := Result + SaveRaw(C,
        '<a href="' + LedHtmlEscape(Href) + '">' + LedHtmlEscape(Href) +
        '</a>');
      Inc(I, L);
      Continue;
    end;

    { CamelCase. }
    L := MatchWikiWord(S, I);
    if L > 0 then
    begin
      Raw := Copy(S, I, L);
      Result := Result + SaveRaw(C,
        '<a href="' + LedHtmlEscape(Raw) + '">' + LedHtmlEscape(Raw) +
        '</a>');
      Inc(I, L);
      Continue;
    end;

    Result := Result + S[I];
    Inc(I);
  end;

  { Escape what is left -- the placeholders are digits and #1, so escaping
    cannot damage them -- then the emphasis pairs, longest delimiter first so
    ''''' is not eaten by ''' plus ''. }
  Result := LedHtmlEscape(Result);
  Result := ApplyPair(Result, '''''''''''', '<strong><em>', '</em></strong>');
  Result := ApplyPair(Result, '''''''', '<strong>', '</strong>');
  Result := ApplyPair(Result, '''''', '<em>', '</em>');
  Result := ApplyPair(Result, '`', '<code>', '</code>');
end;

{ --- blocks ---------------------------------------------------------------- }

procedure CloseListsTo(var C: TWikiCtx; ATarget: Integer);
var
  K: Char;
begin
  while Length(C.Lists) > ATarget do
  begin
    K := C.Lists[High(C.Lists)].Kind;
    if C.Lists[High(C.Lists)].ItemOpen then
    begin
      if K = 'd' then Emit(C, '</dd>') else Emit(C, '</li>');
    end;
    if K = 'u' then Emit(C, '</ul>')
    else if K = 'o' then Emit(C, '</ol>')
    else Emit(C, '</dl>');
    SetLength(C.Lists, Length(C.Lists) - 1);
  end;
end;

procedure ClosePara(var C: TWikiCtx);
begin
  if C.InPara then
  begin
    Emit(C, '</p>');
    C.InPara := False;
  end;
end;

procedure CloseTable(var C: TWikiCtx);
begin
  if C.InTable then
  begin
    Emit(C, '</table>');
    C.InTable := False;
  end;
end;

procedure CloseAll(var C: TWikiCtx);
begin
  ClosePara(C);
  CloseTable(C);
  CloseListsTo(C, 0);
end;

{ ATerm is the <dt> of a definition item, and is emitted beside the <dd>
  rather than inside it -- "; term : def" first produced
  <dd><dt>term</dt>def</dd>, which no browser is obliged to lay out as a
  definition list because a dt is not allowed inside a dd. }
procedure ListItem(var C: TWikiCtx; AKind: Char; ADepth: Integer;
  const ATerm, AHtml: string);
var
  I: Integer;
begin
  ClosePara(C);
  CloseTable(C);

  { A change of kind at the same depth is a new list, not a continuation. }
  if (Length(C.Lists) >= ADepth) and (ADepth >= 1) and
     (C.Lists[ADepth - 1].Kind <> AKind) then
    CloseListsTo(C, ADepth - 1);

  CloseListsTo(C, ADepth);

  while Length(C.Lists) < ADepth do
  begin
    { A deeper list belongs inside the item above it, so that item's tag
      stays open while the child is written. }
    if AKind = 'u' then Emit(C, '<ul>')
    else if AKind = 'o' then Emit(C, '<ol>')
    else Emit(C, '<dl>');
    SetLength(C.Lists, Length(C.Lists) + 1);
    C.Lists[High(C.Lists)].Kind := AKind;
    C.Lists[High(C.Lists)].ItemOpen := False;
  end;

  I := High(C.Lists);
  if I < 0 then Exit;
  if C.Lists[I].ItemOpen then
  begin
    if AKind = 'd' then Emit(C, '</dd>') else Emit(C, '</li>');
    C.Lists[I].ItemOpen := False;
  end;
  if AKind = 'd' then
  begin
    if ATerm <> '' then Emit(C, '<dt>' + ATerm + '</dt>');
    Emit(C, '<dd>' + AHtml);
  end
  else
    Emit(C, '<li>' + AHtml);
  C.Lists[I].ItemOpen := True;
end;

{ ||a||b|| is a row of cells, !!a!!b!! a row of header cells. }
procedure TableRow(var C: TWikiCtx; const ALine: string);
var
  Sep, Tag: string;
  Parts: TStringList;
  Row: string;
  i: Integer;
  Body: string;
begin
  ClosePara(C);
  CloseListsTo(C, 0);
  if ALine[1] = '|' then begin Sep := '||'; Tag := 'td'; end
  else begin Sep := '!!'; Tag := 'th'; end;

  if not C.InTable then
  begin
    Emit(C, '<table class="wikitable">');
    C.InTable := True;
  end;

  Body := ALine;
  { Drop the leading and trailing separator so the split does not produce an
    empty cell at each end. }
  Delete(Body, 1, 2);
  if (Length(Body) >= 2) and (Copy(Body, Length(Body) - 1, 2) = Sep) then
    Delete(Body, Length(Body) - 1, 2);

  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Text := StringReplace(Body, Sep, LineEnding, [rfReplaceAll]);
    Row := '<tr>';
    for i := 0 to Parts.Count - 1 do
      Row := Row + '<' + Tag + '>' + WikiInline(C, Trim(Parts[i])) +
             '</' + Tag + '>';
    Row := Row + '</tr>';
    Emit(C, Row);
  finally
    Parts.Free;
  end;
end;

procedure Heading(var C: TWikiCtx; ALevel: Integer; const ATitle: string);
var
  Display, Anchor, Number: string;
  InToc: Boolean;
  i: Integer;
begin
  CloseAll(C);
  Display := ATitle;
  InToc := (Display <> '') and (Display[1] = '#') and
           ((Length(Display) = 1) or (Display[2] in [' ', #9]));
  Anchor := '';
  Number := '';
  if InToc then
  begin
    Delete(Display, 1, 1);
    Display := Trim(Display);
    Anchor := Slugify(Display);
    if Anchor = '' then Anchor := 'section-' + IntToStr(C.AnchorSeq);
    if C.AnchorsSeen.IndexOf(Anchor) >= 0 then
      Anchor := Anchor + '-' + IntToStr(C.AnchorSeq);
    C.AnchorsSeen.Add(Anchor);
    Inc(C.AnchorSeq);

    { Hierarchical "1.2.3": bump this level, clear the deeper ones. }
    Inc(C.Counters[ALevel]);
    for i := ALevel + 1 to 6 do C.Counters[i] := 0;
    for i := 1 to ALevel do
    begin
      if Number <> '' then Number := Number + '.';
      Number := Number + IntToStr(C.Counters[i]);
    end;

    SetLength(C.Headings, Length(C.Headings) + 1);
    C.Headings[High(C.Headings)].Level := ALevel;
    C.Headings[High(C.Headings)].Title := Display;
    C.Headings[High(C.Headings)].Anchor := Anchor;
    C.Headings[High(C.Headings)].Number := Number;
  end;

  if InToc then
    Emit(C, Format('<h%d id="%s">%s %s</h%d>',
      [ALevel, LedHtmlEscape(Anchor), LedHtmlEscape(Number),
       WikiInline(C, Display), ALevel]))
  else
    Emit(C, Format('<h%d>%s</h%d>',
      [ALevel, WikiInline(C, Display), ALevel]));
end;

procedure ParagraphLine(var C: TWikiCtx; const ALine: string);
begin
  CloseTable(C);
  CloseListsTo(C, 0);
  if not C.InPara then
  begin
    Emit(C, '<p>');
    C.InPara := True;
  end;
  Emit(C, WikiInline(C, ALine));
end;

{ --- the two passes -------------------------------------------------------- }

{ Pulls <nowiki>, <pre> and <code> out before anything else sees them, so
  their contents reach the output untouched. }
function ProtectRegions(var C: TWikiCtx; const AText: string): string;
const
  Tags: array[0..2] of string = ('nowiki', 'pre', 'code');
var
  S, Lower_, Open_, Close_: string;
  i, P1, P2, k: Integer;
  Inner: string;
begin
  S := AText;
  for k := 0 to High(Tags) do
  begin
    Open_ := '<' + Tags[k] + '>';
    Close_ := '</' + Tags[k] + '>';
    i := 1;
    repeat
      Lower_ := LowerCase(S);
      P1 := PosEx(Open_, Lower_, i);
      if P1 = 0 then Break;
      P2 := PosEx(Close_, Lower_, P1 + Length(Open_));
      if P2 = 0 then Break;
      Inner := Copy(S, P1 + Length(Open_), P2 - P1 - Length(Open_));
      if Tags[k] = 'nowiki' then
        Inner := LedHtmlEscape(Inner)
      else
        Inner := '<' + Tags[k] + '>' + LedHtmlEscape(Inner) + '</' +
                 Tags[k] + '>';
      S := Copy(S, 1, P1 - 1) + SaveRaw(C, Inner) +
           Copy(S, P2 + Length(Close_), Length(S));
      i := P1;
    until False;
  end;
  Result := S;
end;

function RestoreSaved(var C: TWikiCtx; const AText: string): string;
var
  i, P1, P2, Idx: Integer;
  S, Digits: string;
begin
  S := AText;
  i := 1;
  while i <= Length(S) do
  begin
    P1 := PosEx(PH, S, i);
    if P1 = 0 then Break;
    P2 := PosEx(PH, S, P1 + 1);
    if P2 = 0 then Break;
    Digits := Copy(S, P1 + 1, P2 - P1 - 1);
    if (Digits <> '') and TryStrToInt(Digits, Idx) and
       (Idx >= 0) and (Idx < C.Saved.Count) then
    begin
      S := Copy(S, 1, P1 - 1) + C.Saved[Idx] + Copy(S, P2 + 1, Length(S));
      i := P1 + Length(C.Saved[Idx]);
    end
    else
      i := P1 + 1;
  end;
  Result := S;
end;

function BuildToc(var C: TWikiCtx): string;
var
  i: Integer;
begin
  if Length(C.Headings) = 0 then Exit('');
  Result := '<div class="wikitoc"><ul>';
  for i := 0 to High(C.Headings) do
    Result := Result +
      Format('<li class="wikitoc-l%d"><a href="#%s">%s %s</a></li>',
        [C.Headings[i].Level, LedHtmlEscape(C.Headings[i].Anchor),
         LedHtmlEscape(C.Headings[i].Number),
         LedHtmlEscape(C.Headings[i].Title)]);
  Result := Result + '</ul></div>';
end;

function LedWikiToHTML(const AText: string): string;
var
  C: TWikiCtx;
  Lines: TStringList;
  i, Depth, Level, TailEq, Colon: Integer;
  Line, Trimmed, Body, Term, Def: string;
  p: Integer;
  AllDash: Boolean;
begin
  FillChar(C, SizeOf(C), 0);
  C.Out_ := TStringList.Create;
  C.Saved := TStringList.Create;
  C.AnchorsSeen := TStringList.Create;
  Lines := TStringList.Create;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    Lines.Text := ProtectRegions(C, AText);

    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      Trimmed := TrimRight(Line);

      if Trim(Trimmed) = '' then
      begin
        CloseAll(C);
        Continue;
      end;

      { <toc> on a line of its own. }
      if SameText(Trim(Trimmed), '<toc>') then
      begin
        CloseAll(C);
        Emit(C, PH + 'TOC' + PH);
        Continue;
      end;

      { A protected region that took up a whole line keeps its own block
        tag, so it must not be wrapped in a paragraph. }
      if (Length(Trim(Trimmed)) > 2) and (Trim(Trimmed)[1] = PH) and
         (Trim(Trimmed)[Length(Trim(Trimmed))] = PH) then
      begin
        CloseAll(C);
        Emit(C, Trim(Trimmed));
        Continue;
      end;

      { ---- rules. }
      if (Length(Trimmed) >= 4) and (Copy(Trimmed, 1, 4) = '----') then
      begin
        AllDash := True;
        for p := 1 to Length(TrimRight(Trimmed)) do
          if Trimmed[p] <> '-' then begin AllDash := False; Break; end;
        if AllDash then
        begin
          CloseAll(C);
          if Length(TrimRight(Trimmed)) >= 6 then
            Emit(C, '<hr class="wikiline-thick">')
          else
            Emit(C, '<hr>');
          Continue;
        end;
      end;

      { = Heading =. }
      if (Trimmed <> '') and (Trimmed[1] = '=') then
      begin
        Level := 0;
        p := 1;
        while (p <= Length(Trimmed)) and (Trimmed[p] = '=') and (Level < 6) do
        begin Inc(p); Inc(Level); end;
        if (Level >= 1) and (p <= Length(Trimmed)) and (Trimmed[p] = ' ') then
        begin
          Body := TrimRight(Copy(Trimmed, p + 1, Length(Trimmed)));
          TailEq := 0;
          while (Body <> '') and (Body[Length(Body)] = '=') and
                (TailEq < Level) do
          begin
            Delete(Body, Length(Body), 1);
            Inc(TailEq);
          end;
          if (TailEq = Level) and (Trim(Body) <> '') then
          begin
            Heading(C, Level, Trim(Body));
            Continue;
          end;
        end;
      end;

      { * and # lists. }
      if (Trimmed[1] = '*') or (Trimmed[1] = '#') then
      begin
        Depth := 0;
        p := 1;
        while (p <= Length(Trimmed)) and (Trimmed[p] = Trimmed[1]) do
        begin Inc(p); Inc(Depth); end;
        if (Depth >= 1) and
           ((p > Length(Trimmed)) or (Trimmed[p] in [' ', #9])) then
        begin
          Body := Trim(Copy(Trimmed, p, Length(Trimmed)));
          if Trimmed[1] = '*' then
            ListItem(C, 'u', Depth, '', WikiInline(C, Body))
          else
            ListItem(C, 'o', Depth, '', WikiInline(C, Body));
          Continue;
        end;
      end;

      { ; term : definition. }
      if Trimmed[1] = ';' then
      begin
        Depth := 0;
        p := 1;
        while (p <= Length(Trimmed)) and (Trimmed[p] = ';') do
        begin Inc(p); Inc(Depth); end;
        Body := Copy(Trimmed, p, Length(Trimmed));
        Colon := Pos(':', Body);
        if Colon > 0 then
        begin
          Term := Trim(Copy(Body, 1, Colon - 1));
          Def := Trim(Copy(Body, Colon + 1, Length(Body)));
          ListItem(C, 'd', Depth, WikiInline(C, Term), WikiInline(C, Def));
        end
        else
          ListItem(C, 'd', Depth, WikiInline(C, Trim(Body)), '');
        Continue;
      end;

      { : indented. }
      if Trimmed[1] = ':' then
      begin
        Depth := 0;
        p := 1;
        while (p <= Length(Trimmed)) and (Trimmed[p] = ':') do
        begin Inc(p); Inc(Depth); end;
        Body := Trim(Copy(Trimmed, p, Length(Trimmed)));
        ListItem(C, 'd', Depth, '', WikiInline(C, Body));
        Continue;
      end;

      { ||cells|| and !!cells!!. }
      if (Length(Trimmed) >= 4) and
         (((Trimmed[1] = '|') and (Trimmed[2] = '|')) or
          ((Trimmed[1] = '!') and (Trimmed[2] = '!'))) then
      begin
        TableRow(C, Trimmed);
        Continue;
      end;

      ParagraphLine(C, Trimmed);
    end;

    CloseAll(C);
    Result := C.Out_.Text;
    Result := StringReplace(Result, PH + 'TOC' + PH, BuildToc(C),
                            [rfReplaceAll]);
    Result := RestoreSaved(C, Result);
  finally
    Lines.Free;
    C.AnchorsSeen.Free;
    C.Saved.Free;
    C.Out_.Free;
  end;
end;

function LedWikiToPage(const AText, ATitle: string): string;
var
  Body: string;
begin
  { The Markdown page wrapper carries the stylesheet the preview pane
    expects, so a wiki page is that wrapper around this body -- rendered
    through a marker no document can contain. }
  Body := LedWikiToHTML(AText);
  Result := LedMarkdownToPage('%LEDWIKIBODY%', ATitle);
  Result := StringReplace(Result, '<p>%LEDWIKIBODY%</p>', Body, [rfReplaceAll]);
  Result := StringReplace(Result, '%LEDWIKIBODY%', Body, [rfReplaceAll]);
end;

function LedIsWikiFile(const AFileName, AFirstLine: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.wiki') or (Ext = '.wp') or (Ext = '.usemod');
  if not Result then
    Result := SameText(Trim(AFirstLine), '<!-- wiki -->');
end;

end.
