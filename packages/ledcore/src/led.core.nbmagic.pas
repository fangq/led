{ LED - a lightweight editor.  What language a notebook cell is written in.

  A notebook says what its kernel is once, at the top, and most cells are in
  that language.  But a cell that opens with a cell magic is not: %%shell is
  a shell script, %%octave is Octave, %%perl is Perl, and colouring any of
  them as Python is wrong for every line.  Jupyter and Colab both read the
  magic and so does this.

  The names do not line up by themselves.  A kernel calls itself "bash" and a
  magic calls itself "%%shell" while LED's shell grammar is "sh"; the R
  kernel is "ir"; "c++" is "cpp" here.  So there is a table, and it is the
  one place that knows about both vocabularies.

  A magic that is not a language at all -- %%time, %%capture, %%writefile --
  comes back as nothing, and the cell keeps the notebook's own language.
  That is the same answer an unknown magic gets, which is the right one for
  both: a cell magic this does not recognise is far more likely to be a
  measurement than a language.

  And where nothing is known at all, Python.  It is what the great majority of
  notebooks are, and a guess that is right most of the time beats a cell with
  no colouring in it. }

unit Led.Core.NBMagic;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  { What a notebook is when it does not say: see the unit comment. }
  LedNBDefaultLanguage = 'python';

{ The word a cell magic on the first line of ASource names, in lower case, or
  '' when the cell does not open with one.  '%%shell' gives 'shell'. }
function LedNBCellMagic(const ASource: string): string;

{ A kernel name or a magic name as one of LED's language ids, or '' for a
  name this does not know.  Case does not matter. }
function LedNBLanguageId(const AName: string): string;

{ The language to colour a cell in: what its own cell magic says, else what
  the notebook says, else Python. }
function LedNBCellLanguage(const ASource, ANotebookLanguage: string): string;

{ Whether a line of a code cell is a magic rather than code.

  AFirstLine says whether this is the cell's opening line, because a cell
  magic is only a cell magic there.  AIPython says whether the cell is still
  the notebook's own language: a line magic and a shell escape are IPython's
  own, and inside a cell that %%bash has handed to another language a '!' is
  just a '!'. }
function LedNBIsMagicLine(const ALine: string; AFirstLine, AIPython: Boolean): Boolean;

implementation

type
  TLedNBLangAlias = record
    Name: string;      { what a kernel or a magic calls it }
    LangId: string;    { what LED calls it }
  end;

const
  { Both vocabularies in one table: on the left the names notebooks use, on
    the right the ids LED's highlighters are registered under.  A name that
    is already an id is still listed, because the caller cannot tell the two
    apart and this way it does not have to. }
  Aliases: array[0..58] of TLedNBLangAlias = (
    { the shells, all of which get LED's sh grammar }
    (Name: 'sh';          LangId: 'sh'),
    (Name: 'bash';        LangId: 'sh'),
    (Name: 'shell';       LangId: 'sh'),
    (Name: 'zsh';         LangId: 'sh'),
    (Name: 'ksh';         LangId: 'sh'),
    (Name: 'fish';        LangId: 'sh'),
    (Name: 'script';      LangId: 'sh'),
    (Name: 'system';      LangId: 'sh'),

    (Name: 'python';      LangId: 'python'),
    (Name: 'python2';     LangId: 'python'),
    (Name: 'python3';     LangId: 'python3'),
    (Name: 'py';          LangId: 'python'),
    (Name: 'ipython';     LangId: 'python'),
    (Name: 'pypy';        LangId: 'python'),

    (Name: 'perl';        LangId: 'perl'),
    (Name: 'perl5';       LangId: 'perl'),
    (Name: 'ruby';        LangId: 'ruby'),
    (Name: 'rb';          LangId: 'ruby'),
    (Name: 'lua';         LangId: 'lua'),
    (Name: 'tcl';         LangId: 'tcl'),
    (Name: 'awk';         LangId: 'awk'),

    (Name: 'javascript';  LangId: 'js'),
    (Name: 'js';          LangId: 'js'),
    (Name: 'node';        LangId: 'js'),
    (Name: 'nodejs';      LangId: 'js'),
    { No TypeScript grammar here, and JavaScript is close enough to read. }
    (Name: 'typescript';  LangId: 'js'),
    (Name: 'ts';          LangId: 'js'),

    (Name: 'html';        LangId: 'html'),
    (Name: 'xml';         LangId: 'xml'),
    (Name: 'svg';         LangId: 'xml'),
    (Name: 'css';         LangId: 'css'),
    (Name: 'json';        LangId: 'json'),
    (Name: 'yaml';        LangId: 'yaml'),
    (Name: 'markdown';    LangId: 'markdown'),
    (Name: 'md';          LangId: 'markdown'),
    (Name: 'latex';       LangId: 'latex'),
    (Name: 'tex';         LangId: 'latex'),

    { the numerical ones, which is what a teaching notebook is full of }
    (Name: 'octave';      LangId: 'octave'),
    (Name: 'matlab';      LangId: 'matlab'),
    (Name: 'scilab';      LangId: 'scilab'),
    (Name: 'maxima';      LangId: 'maxima'),
    (Name: 'julia';       LangId: 'julia'),
    { IRkernel calls itself ir; the magic calls itself R. }
    (Name: 'r';           LangId: 'r'),
    (Name: 'ir';          LangId: 'r'),
    (Name: 'rscript';     LangId: 'r'),

    (Name: 'sql';         LangId: 'sql'),
    (Name: 'sqlite';      LangId: 'sql'),
    (Name: 'bigquery';    LangId: 'sql'),

    (Name: 'c';           LangId: 'c'),
    (Name: 'cpp';         LangId: 'cpp'),
    (Name: 'c++';         LangId: 'cpp'),
    (Name: 'cxx';         LangId: 'cpp'),
    (Name: 'csharp';      LangId: 'csharp'),
    (Name: 'c#';          LangId: 'csharp'),
    (Name: 'java';        LangId: 'java'),
    (Name: 'go';          LangId: 'go'),
    (Name: 'golang';      LangId: 'go'),
    (Name: 'rust';        LangId: 'rust'),
    (Name: 'fortran';     LangId: 'fortran')
  );

function LedNBLanguageId(const AName: string): string;
var
  i: Integer;
begin
  Result := '';
  if AName = '' then Exit;
  for i := Low(Aliases) to High(Aliases) do
    if SameText(Aliases[i].Name, AName) then
      Exit(Aliases[i].LangId);
end;

function LedNBCellMagic(const ASource: string): string;
var
  First: string;
  i, Stop: Integer;
begin
  Result := '';
  { The first line, however the cell's lines are separated. }
  Stop := 0;
  for i := 1 to Length(ASource) do
    if ASource[i] in [#10, #13] then
    begin
      Stop := i - 1;
      Break;
    end;
  if Stop = 0 then Stop := Length(ASource);
  First := TrimLeft(Copy(ASource, 1, Stop));
  if Copy(First, 1, 2) <> '%%' then Exit;

  { The word after the marker, and only the word: "%%bash -s 3" is bash. }
  for i := 3 to Length(First) do
    if First[i] in ['a'..'z', 'A'..'Z', '0'..'9', '_', '+', '-', '#'] then
      Result := Result + First[i]
    else
      Break;
  Result := LowerCase(Result);
end;

function LedNBCellLanguage(const ASource, ANotebookLanguage: string): string;
begin
  { What the cell says about itself comes first: a %%octave cell is Octave
    whatever the file's metadata says the notebook is. }
  Result := LedNBLanguageId(LedNBCellMagic(ASource));
  if Result <> '' then Exit;
  Result := LedNBLanguageId(ANotebookLanguage);
  if Result <> '' then Exit;
  { A name this does not know is still worth passing on -- LED may have a
    grammar under that very name -- and only then is it a guess. }
  if ANotebookLanguage <> '' then Exit(LowerCase(ANotebookLanguage));
  Result := LedNBDefaultLanguage;
end;

function LedNBIsMagicLine(const ALine: string;
  AFirstLine, AIPython: Boolean): Boolean;
var
  T: string;
begin
  Result := False;
  T := TrimLeft(ALine);
  if T = '' then Exit;
  if Copy(T, 1, 2) = '%%' then Exit(AFirstLine);
  if AIPython then Result := T[1] in ['%', '!'];
end;

end.
