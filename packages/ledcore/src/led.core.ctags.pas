{ LED - a lightweight editor.  Reading a tags file.

  medit bundled a copy of universal-ctags' readtags.c.  The format is simple
  enough that parsing it directly is smaller than carrying the C:

      name<TAB>file<TAB>address;"<TAB>kind:f<TAB>line:42

  The address is either a line number or a /pattern/; both are handled,
  because different ctags builds emit different ones.

  No LCL dependency. }
unit Led.Core.Ctags;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, LazFileUtils, FileUtil;

type
  TLedTag = record
    Name: string;
    FileName: string;
    Line: Integer;
    Kind: string;        // ctags kind letter: f, c, v, m, ...
    Scope: string;       // class or namespace it belongs to, when given
  end;

  TLedTags = class
  private
    FItems: array of TLedTag;
    { How many of them are real: the array is grown in blocks, so its length
      is not the answer. }
    FCount: Integer;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TLedTag;
  public
    procedure Clear;
    procedure Add(const ATag: TLedTag);
    { Parses tags-file content.  Returns how many tags were understood. }
    function ParseText(const AText: string): Integer;
    { Runs ctags over one file and parses the result.  Returns False when
      ctags is not installed, which is not an error worth a dialog. }
    function RunOn(const AFileName: string): Boolean;
    function KindName(const AKind: string): string;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TLedTag read GetItem; default;
  end;

function LedCtagsAvailable: Boolean;

implementation

var
  FChecked: Boolean = False;
  FAvailable: Boolean = False;
  FCtagsPath: string = '';

{ Looked up on PATH rather than probed by running it.  Running a program that
  is not there, with pipes and poWaitOnExit, can block indefinitely -- which
  is exactly what it did the first time. }
function LedCtagsAvailable: Boolean;
begin
  if FChecked then Exit(FAvailable);
  FChecked := True;
  FCtagsPath := FindDefaultExecutablePath('ctags');
  if FCtagsPath = '' then
    FCtagsPath := FindDefaultExecutablePath('universal-ctags');
  if FCtagsPath = '' then
    FCtagsPath := FindDefaultExecutablePath('exuberant-ctags');
  FAvailable := FCtagsPath <> '';
  Result := FAvailable;
end;

function TLedTags.GetCount: Integer;
begin
  Result := FCount;
end;

function TLedTags.GetItem(AIndex: Integer): TLedTag;
begin
  Result := FItems[AIndex];
end;

procedure TLedTags.Clear;
begin
  FCount := 0;
  SetLength(FItems, 0);
end;

procedure TLedTags.Add(const ATag: TLedTag);
begin
  { Grown in blocks and trimmed at the end, rather than one at a time: a
    large C++ file has thirty thousand tags, and reallocating the array for
    each of them copies it thirty thousand times. }
  if FCount >= Length(FItems) then
    SetLength(FItems, Length(FItems) * 2 + 256);
  FItems[FCount] := ATag;
  Inc(FCount);
end;

function TLedTags.KindName(const AKind: string): string;
var
  K: string;
begin
  { Two spellings, because both turn up.  A plain tags file carries the
    one-letter kind; --fields=+K, which is what LED asks for, carries the
    whole word -- 'function', 'chapter' -- and a reader that knew only the
    letters put every symbol in a group called Other. }
  K := LowerCase(AKind);
  if (K = 'f') or (K = 'function') or (K = 'func') then Result := 'Functions'
  else if (K = 'c') or (K = 'class') then Result := 'Classes'
  else if (K = 's') or (K = 'struct') then Result := 'Structs'
  else if (K = 'v') or (K = 'variable') or (K = 'var') then Result := 'Variables'
  else if (K = 'm') or (K = 'member') or (K = 'method') then Result := 'Members'
  else if (K = 'd') or (K = 'macro') or (K = 'define') then Result := 'Macros'
  else if (K = 't') or (K = 'typedef') or (K = 'type') then Result := 'Types'
  else if (K = 'e') or (K = 'enumerator') then Result := 'Enumerators'
  else if (K = 'g') or (K = 'enum') then Result := 'Enums'
  else if (K = 'p') or (K = 'prototype') then Result := 'Prototypes'
  else if (K = 'n') or (K = 'namespace') then Result := 'Namespaces'
  else if (K = 'i') or (K = 'interface') then Result := 'Interfaces'
  else if K = 'field' then Result := 'Fields'
  else if K = 'property' then Result := 'Properties'
  else if K = 'constant' then Result := 'Constants'
  else if K = 'module' then Result := 'Modules'
  else if K = 'package' then Result := 'Packages'
  else if K = 'union' then Result := 'Unions'
  else if K = 'label' then Result := 'Labels'
  else if K = 'anchor' then Result := 'Anchors'
  { A Markdown file is an outline, and these are what its headings come back
    as.  The pane is at its most useful on exactly this kind of file. }
  else if K = 'chapter' then Result := 'Headings'
  else if K = 'section' then Result := 'Sections'
  else if K = 'subsection' then Result := 'Subsections'
  else if K = 'subsubsection' then Result := 'Sub-subsections'
  else if K = '' then Result := 'Other'
  else
  begin
    { Unknown, so shown as it came, with a capital and an s: ctags kinds are
      lower-case singular nouns and these are group headings. }
    Result := UpCase(AKind[1]) + Copy(AKind, 2, MaxInt);
    if (Length(Result) > 0) and (Result[Length(Result)] <> 's') then
      Result := Result + 's';
  end;
end;

{ Fields that are not a scope, though they are spelled key:value like one.
  Everything else with a colon is: ctags names a symbol's container by the
  container's own kind, so the key is 'class' in C++, 'chapter' in Markdown,
  and anything at all in a language nobody here has thought about. }
function IsScopeField(const AKey: string): Boolean;
const
  NotScope: array[0..12] of string = (
    'line', 'kind', 'typeref', 'file', 'signature', 'access', 'inherits',
    'implementation', 'language', 'roles', 'extras', 'end', 'nth');
var
  i: Integer;
begin
  for i := Low(NotScope) to High(NotScope) do
    if AKey = NotScope[i] then Exit(False);
  Result := True;
end;

function TLedTags.ParseText(const AText: string): Integer;
var
  Lines: TStringList;
  i, j, TabAt: Integer;
  Line, Rest, Field, Addr: string;
  Tag: TLedTag;
  Parts: TStringArray;
begin
  Clear;
  Lines := TStringList.Create;
  try
    Lines.TextLineBreakStyle := tlbsLF;
    Lines.Text := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      { Lines beginning !_TAG_ are the file's own metadata. }
      if (Line = '') or (Copy(Line, 1, 2) = '!_') then Continue;

      Parts := Line.Split([#9]);
      if Length(Parts) < 3 then Continue;

      Tag := Default(TLedTag);
      Tag.Name := Parts[0];
      Tag.FileName := Parts[1];
      Addr := Parts[2];

      { The address is a line number or a search pattern.  Only the number
        is useful for jumping; a pattern means the line has to be found
        later, so it is recorded as unknown rather than guessed. }
      TabAt := Pos(';"', Addr);
      if TabAt > 0 then Addr := Copy(Addr, 1, TabAt - 1);
      Tag.Line := StrToIntDef(Trim(Addr), 0);

      for j := 3 to High(Parts) do
      begin
        Field := Parts[j];
        if Copy(Field, 1, 5) = 'line:' then
          Tag.Line := StrToIntDef(Copy(Field, 6, MaxInt), Tag.Line)
        else if Copy(Field, 1, 5) = 'kind:' then
          Tag.Kind := Copy(Field, 6, MaxInt)
        { No colon: the kind, whether that is the letter 'f' or the word
          'function'.  Only the length-one case was accepted before, so with
          --fields=+K -- which is what LED asks ctags for -- the kind was
          never read at all and every symbol landed in Other. }
        else if (Field <> '') and (Pos(':', Field) = 0) and (Tag.Kind = '') then
          Tag.Kind := Field
        else if Pos(':', Field) > 0 then
        begin
          Rest := LowerCase(Copy(Field, 1, Pos(':', Field) - 1));
          if Rest = 'scope' then
            Tag.Scope := Copy(Field, Pos(':', Field) + 1, MaxInt)
          else if IsScopeField(Rest) then
            Tag.Scope := Copy(Field, Pos(':', Field) + 1, MaxInt);
        end;
      end;

      if Tag.Name <> '' then
        Add(Tag);
    end;
  finally
    Lines.Free;
  end;
  Result := FCount;
end;

function TLedTags.RunOn(const AFileName: string): Boolean;
const
  { A pipe holds 64 KiB on Linux; reading in chunks of that size means one
    read per bufferful rather than one per line. }
  ChunkSize = 64 * 1024;
var
  P: TProcess;
  Chunk: array[0..ChunkSize - 1] of Byte;
  Got: Integer;
  Text: string;
  Held: Int64;
begin
  Result := False;
  Clear;
  if not FileExists(AFileName) then Exit;
  if not LedCtagsAvailable then Exit;

  P := TProcess.Create(nil);
  try
    P.Executable := FCtagsPath;
    { -f - writes to stdout, which avoids a temporary file entirely. }
    P.Parameters.Add('-f');
    P.Parameters.Add('-');
    P.Parameters.Add('--fields=+nKs');
    P.Parameters.Add('--excmd=number');
    P.Parameters.Add(AFileName);
    { Read while it runs, and waited for afterwards.

      Not poWaitOnExit with the reading after it, which is what this did and
      is a deadlock waiting for a big enough file: a pipe holds 64 KiB, and
      when ctags fills it the child blocks on the write while the parent
      blocks on the exit.  Neither ever moves.  Measured, it took about six
      hundred tags -- an ordinary large C file -- and the reader saw the
      editor stop dead the moment the Outline pane was opened on one.

      Errors go into the same pipe rather than into one nobody reads, which
      would deadlock the same way for a file ctags complains about at
      length.  ParseText skips anything that is not a tag line. }
    P.Options := [poUsePipes, poNoConsole, poStderrToOutPut];
    Text := '';
    Held := 0;
    try
      P.Execute;
      repeat
        { Blocks until there is something or the child closes the pipe,
          which is what makes this a loop and not a poll. }
        Got := P.Output.Read(Chunk, ChunkSize);
        if Got > 0 then
        begin
          if Held + Got > Length(Text) then
            SetLength(Text, (Held + Got) * 2 + ChunkSize);
          Move(Chunk[0], Text[Held + 1], Got);
          Inc(Held, Got);
        end;
      until Got <= 0;
      SetLength(Text, Held);
      P.WaitOnExit;
    except
      Exit;
    end;
    ParseText(Text);
    Result := True;
  finally
    P.Free;
  end;
end;

end.
