{ led - a light editor.  Grammar loader check.

  Loads every generated TextMate grammar through the same engine the editor
  uses and reports the ones that do not compile.  A converter that emits
  plausible-looking JSON which the engine then rejects is worse than one that
  fails loudly, so this runs in CI as a gate. }
program langcheck;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, fpjson, jsonparser, TextMateGrammar;

var
  Dir: string;
  Search: TSearchRec;
  Total, Bad, Missing: Integer;
  Names: TStringList;

function CheckOne(const APath: string; out AError: string): Boolean;
var
  Src: TStringList;
  G: TTextMateGrammar;
begin
  Result := False;
  AError := '';
  Src := TStringList.Create;
  G := nil;
  try
    try
      Src.LoadFromFile(APath);
    except
      on E: Exception do
      begin
        AError := 'unreadable: ' + E.Message;
        Exit;
      end;
    end;
    try
      G := TTextMateGrammar.Create;
      G.ParseGrammar(Src.Text);
      if G.ParserError <> '' then
        AError := G.ParserError
      else if G.MissingIncludes <> '' then
        { Not fatal -- a grammar may reference another that is loaded
          alongside it -- but worth surfacing, since a typo looks the same. }
        AError := 'missing includes: ' + G.MissingIncludes
      else
        Result := True;
    except
      on E: Exception do
        AError := E.ClassName + ': ' + E.Message;
    end;
  finally
    G.Free;
    Src.Free;
  end;
end;

var
  i: Integer;
  Err: string;
begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: langcheck <grammar-dir>');
    Halt(2);
  end;
  Dir := IncludeTrailingPathDelimiter(ParamStr(1));

  Names := TStringList.Create;
  try
    Names.Sorted := True;
    if FindFirst(Dir + '*.tmLanguage.json', faAnyFile, Search) = 0 then
    begin
      repeat
        Names.Add(Search.Name);
      until FindNext(Search) <> 0;
      FindClose(Search);
    end;

    Total := 0;
    Bad := 0;
    Missing := 0;
    for i := 0 to Names.Count - 1 do
    begin
      Inc(Total);
      if not CheckOne(Dir + Names[i], Err) then
      begin
        Inc(Bad);
        WriteLn(Format('  FAIL %-28s %s', [Names[i], Err]));
      end;
    end;

    WriteLn(Format('%d grammars, %d rejected, %d missing', [Total, Bad, Missing]));
    if Bad > 0 then
      ExitCode := 1;
  finally
    Names.Free;
  end;
end.
