{ led - a light editor.  Reading a tags file.

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
  Result := Length(FItems);
end;

function TLedTags.GetItem(AIndex: Integer): TLedTag;
begin
  Result := FItems[AIndex];
end;

procedure TLedTags.Clear;
begin
  SetLength(FItems, 0);
end;

procedure TLedTags.Add(const ATag: TLedTag);
begin
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)] := ATag;
end;

function TLedTags.KindName(const AKind: string): string;
begin
  { The one-letter kinds that turn up most; anything else is shown as-is
    rather than guessed at. }
  if AKind = 'f' then Result := 'Functions'
  else if AKind = 'c' then Result := 'Classes'
  else if AKind = 's' then Result := 'Structs'
  else if AKind = 'v' then Result := 'Variables'
  else if AKind = 'm' then Result := 'Members'
  else if AKind = 'd' then Result := 'Macros'
  else if AKind = 't' then Result := 'Types'
  else if AKind = 'e' then Result := 'Enumerators'
  else if AKind = 'g' then Result := 'Enums'
  else if AKind = 'p' then Result := 'Prototypes'
  else if AKind = 'n' then Result := 'Namespaces'
  else if AKind = 'i' then Result := 'Interfaces'
  else if AKind = '' then Result := 'Other'
  else Result := AKind;
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
        else if (Length(Field) = 1) and (Tag.Kind = '') then
          Tag.Kind := Field
        else if Pos(':', Field) > 0 then
        begin
          Rest := Copy(Field, 1, Pos(':', Field) - 1);
          if (Rest = 'class') or (Rest = 'struct') or (Rest = 'namespace') or
             (Rest = 'union') or (Rest = 'enum') then
            Tag.Scope := Copy(Field, Pos(':', Field) + 1, MaxInt);
        end;
      end;

      if Tag.Name <> '' then
        Add(Tag);
    end;
  finally
    Lines.Free;
  end;
  Result := Length(FItems);
end;

function TLedTags.RunOn(const AFileName: string): Boolean;
var
  P: TProcess;
  Output: TStringList;
begin
  Result := False;
  Clear;
  if not FileExists(AFileName) then Exit;
  if not LedCtagsAvailable then Exit;

  P := TProcess.Create(nil);
  Output := TStringList.Create;
  try
    P.Executable := FCtagsPath;
    { -f - writes to stdout, which avoids a temporary file entirely. }
    P.Parameters.Add('-f');
    P.Parameters.Add('-');
    P.Parameters.Add('--fields=+nKs');
    P.Parameters.Add('--excmd=number');
    P.Parameters.Add(AFileName);
    P.Options := [poUsePipes, poNoConsole, poWaitOnExit];
    try
      P.Execute;
      Output.LoadFromStream(P.Output);
    except
      Exit;
    end;
    ParseText(Output.Text);
    Result := True;
  finally
    Output.Free;
    P.Free;
  end;
end;

end.
