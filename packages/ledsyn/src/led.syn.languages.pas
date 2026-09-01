{ led - a light editor.  The language registry.

  medit ships 128 GtkSourceView grammars.  Their <metadata> blocks carry
  everything the editor needs long before any highlighting happens: the
  display name, the menu section, the filename globs and mime types used to
  recognise a file, and the comment markers that drive comment/uncomment.

  So this unit reads only the metadata, by scanning for it rather than
  parsing the whole grammar -- 1.8 MB of XML at every startup would be a
  waste when a few hundred bytes per file is all that is wanted.

  Depends on LazUtils (for Masks) but on nothing visual. }
unit Led.Syn.Languages;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Masks;

type
  TLedLangInfo = class
  private
    FId: string;
    FName: string;
    FSection: string;
    FHidden: Boolean;
    FFileName: string;
    FGlobs: TStringList;
    FMimeTypes: TStringList;
    FLineComment: string;
    FBlockCommentStart: string;
    FBlockCommentEnd: string;
  public
    constructor Create;
    destructor Destroy; override;
    function MatchesFileName(const AName: string): Boolean;
    function MatchesMimeType(const AMime: string): Boolean;
    function HasComments: Boolean;

    property Id: string read FId;
    property Name: string read FName;
    property Section: string read FSection;
    property Hidden: Boolean read FHidden;
    property FileName: string read FFileName;
    property Globs: TStringList read FGlobs;
    property MimeTypes: TStringList read FMimeTypes;
    { The same two lists as one semicolon-separated string, which is how the
      preferences page shows them and how an override is stored. }
    function GlobsText: string;
    function MimeTypesText: string;
    procedure SetGlobsText(const AValue: string);
    procedure SetMimeTypesText(const AValue: string);
    property LineComment: string read FLineComment;
    property BlockCommentStart: string read FBlockCommentStart;
    property BlockCommentEnd: string read FBlockCommentEnd;
  end;

  TLedLangRegistry = class
  private
    FItems: TStringList;        // id -> TLedLangInfo, owns the objects
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TLedLangInfo;
  public
    constructor Create;
    destructor Destroy; override;

    { Reads every *.lang in ADirectory.  Returns how many were understood. }
    function ScanDirectory(const ADirectory: string): Integer;
    procedure Clear;

    function FindById(const AId: string): TLedLangInfo;

    { Best guess for a file: an exact glob match first, then the mime type,
      then the interpreter named on a shebang line.  Returns nil when nothing
      matches, which means "plain text". }
    function FindForFile(const AFileName: string;
      const AFirstLine: string = ''): TLedLangInfo;

    { Ids grouped for a menu: sorted by section, then by display name. }
    procedure ListForMenu(AResult: TStrings);

    { Re-reads the per-language globs and mime types the user has overridden
      in prefs.ini, so a change on the Languages preferences page takes
      effect without a restart. }
    procedure ApplyOverrides;

    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TLedLangInfo read GetItem; default;
  end;

{ The process-wide registry, populated from the data directory on first use. }
function LedLanguages: TLedLangRegistry;

implementation

uses
  Led.Core.Paths, Led.Core.Prefs;

{ Pulls the value of attribute AName out of a start tag. }
function TagAttr(const ATag, AName: string): string;
var
  P, Q: Integer;
begin
  Result := '';
  P := Pos(AName + '="', ATag);
  if P = 0 then Exit;
  Inc(P, Length(AName) + 2);
  Q := P;
  while (Q <= Length(ATag)) and (ATag[Q] <> '"') do Inc(Q);
  Result := Copy(ATag, P, Q - P);
end;

{ XML entity references do turn up in comment markers -- &lt; in a few markup
  grammars -- so they are resolved rather than shown literally. }
function Unescape(const S: string): string;
begin
  Result := StringReplace(S, '&lt;', '<', [rfReplaceAll]);
  Result := StringReplace(Result, '&gt;', '>', [rfReplaceAll]);
  Result := StringReplace(Result, '&quot;', '"', [rfReplaceAll]);
  Result := StringReplace(Result, '&apos;', '''', [rfReplaceAll]);
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll]);
end;

{ TLedLangInfo }

constructor TLedLangInfo.Create;
begin
  inherited Create;
  FGlobs := TStringList.Create;
  FMimeTypes := TStringList.Create;
  FMimeTypes.CaseSensitive := False;
end;

destructor TLedLangInfo.Destroy;
begin
  FGlobs.Free;
  FMimeTypes.Free;
  inherited Destroy;
end;

function TLedLangInfo.MatchesFileName(const AName: string): Boolean;
var
  Base: string;
  i: Integer;
begin
  Base := ExtractFileName(AName);
  for i := 0 to FGlobs.Count - 1 do
    { Windows filenames are case-insensitive; elsewhere "[Mm]akefile" style
      globs already say what they mean, so respect the case. }
    if MatchesMask(Base, FGlobs[i], {$IFDEF WINDOWS}False{$ELSE}True{$ENDIF}) then
      Exit(True);
  Result := False;
end;

function TLedLangInfo.MatchesMimeType(const AMime: string): Boolean;
begin
  Result := (AMime <> '') and (FMimeTypes.IndexOf(AMime) >= 0);
end;

function TLedLangInfo.HasComments: Boolean;
begin
  Result := (FLineComment <> '') or (FBlockCommentStart <> '');
end;

{ TLedLangRegistry }

constructor TLedLangRegistry.Create;
begin
  inherited Create;
  FItems := TStringList.Create;
  FItems.OwnsObjects := True;
  FItems.CaseSensitive := False;
  FItems.Sorted := True;
  FItems.Duplicates := dupIgnore;
end;

destructor TLedLangRegistry.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TLedLangRegistry.Clear;
begin
  FItems.Clear;
end;

function TLedLangRegistry.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TLedLangRegistry.GetItem(AIndex: Integer): TLedLangInfo;
begin
  Result := TLedLangInfo(FItems.Objects[AIndex]);
end;

function TLedLangRegistry.FindById(const AId: string): TLedLangInfo;
var
  i: Integer;
begin
  i := FItems.IndexOf(AId);
  if i < 0 then Result := nil else Result := TLedLangInfo(FItems.Objects[i]);
end;

{ Reads one grammar's metadata.  Only the head of the file is examined: the
  <language> tag and the <metadata> block both appear before any of the
  grammar proper. }
function ParseLangFile(const APath: string): TLedLangInfo;
var
  Stream: TFileStream;
  Head: string;
  Len: Integer;
  TagStart, TagEnd, MetaEnd, P, Q, ValStart: Integer;
  Tag, PropName, PropValue: string;
  Info: TLedLangInfo;
begin
  Result := nil;

  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    { The licence header runs to about 1 KB; 8 KB comfortably covers the
      metadata of every grammar that ships. }
    Len := Stream.Size;
    if Len > 8192 then Len := 8192;
    SetLength(Head, Len);
    if Len > 0 then Stream.ReadBuffer(Head[1], Len);
  finally
    Stream.Free;
  end;

  TagStart := Pos('<language', Head);
  if TagStart = 0 then Exit;
  TagEnd := TagStart;
  while (TagEnd <= Length(Head)) and (Head[TagEnd] <> '>') do Inc(TagEnd);
  Tag := Copy(Head, TagStart, TagEnd - TagStart + 1);

  Info := TLedLangInfo.Create;
  Info.FId := TagAttr(Tag, 'id');
  if Info.FId = '' then
  begin
    Info.Free;
    Exit;
  end;
  Info.FName := TagAttr(Tag, 'name');
  if Info.FName = '' then Info.FName := TagAttr(Tag, '_name');
  if Info.FName = '' then Info.FName := Info.FId;
  Info.FSection := TagAttr(Tag, '_section');
  if Info.FSection = '' then Info.FSection := TagAttr(Tag, 'section');
  if Info.FSection = '' then Info.FSection := 'Other';
  Info.FHidden := TagAttr(Tag, 'hidden') = 'true';
  Info.FFileName := APath;

  MetaEnd := Pos('</metadata>', Head);
  if MetaEnd = 0 then MetaEnd := Length(Head);

  P := TagEnd;
  repeat
    P := PosEx('<property name="', Head, P);
    if (P = 0) or (P > MetaEnd) then Break;
    Inc(P, Length('<property name="'));
    Q := P;
    while (Q <= Length(Head)) and (Head[Q] <> '"') do Inc(Q);
    PropName := Copy(Head, P, Q - P);

    ValStart := Q;
    while (ValStart <= Length(Head)) and (Head[ValStart] <> '>') do Inc(ValStart);
    Inc(ValStart);
    Q := PosEx('</property>', Head, ValStart);
    if Q = 0 then Break;
    PropValue := Unescape(Copy(Head, ValStart, Q - ValStart));
    P := Q;

    if PropName = 'globs' then
      Info.FGlobs.Delimiter := ';'
    else if (PropName = 'mimetypes') or (PropName = 'mimetype') then
      Info.FMimeTypes.Delimiter := ';';

    if PropName = 'globs' then
    begin
      Info.FGlobs.StrictDelimiter := True;
      Info.FGlobs.DelimitedText := PropValue;
    end
    else if (PropName = 'mimetypes') or (PropName = 'mimetype') then
    begin
      Info.FMimeTypes.StrictDelimiter := True;
      Info.FMimeTypes.DelimitedText := PropValue;
    end
    else if PropName = 'line-comment-start' then
      Info.FLineComment := PropValue
    else if PropName = 'block-comment-start' then
      Info.FBlockCommentStart := PropValue
    else if PropName = 'block-comment-end' then
      Info.FBlockCommentEnd := PropValue;
  until False;

  Result := Info;
end;

function TLedLangRegistry.ScanDirectory(const ADirectory: string): Integer;
var
  Search: TSearchRec;
  Dir: string;
  Info: TLedLangInfo;
begin
  Result := 0;
  Dir := IncludeTrailingPathDelimiter(ADirectory);
  if not DirectoryExists(Dir) then Exit;

  if FindFirst(Dir + '*.lang', faAnyFile, Search) <> 0 then Exit;
  try
    repeat
      if (Search.Attr and faDirectory) <> 0 then Continue;
      Info := nil;
      try
        Info := ParseLangFile(Dir + Search.Name);
      except
        { One malformed grammar must not cost the other 127. }
        Info := nil;
      end;
      if Info = nil then Continue;
      if FItems.IndexOf(Info.Id) >= 0 then
        Info.Free                      // a user grammar already won
      else
      begin
        FItems.AddObject(Info.Id, Info);
        Inc(Result);
      end;
    until FindNext(Search) <> 0;
  finally
    FindClose(Search);
  end;
end;

{ "#!/usr/bin/env python3" -> "python3"; "#!/bin/sh -e" -> "sh". }
function ShebangInterpreter(const ALine: string): string;
var
  Parts: TStringArray;
  i: Integer;
  Word: string;
begin
  Result := '';
  if Copy(ALine, 1, 2) <> '#!' then Exit;
  Parts := Copy(ALine, 3, MaxInt).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  for i := 0 to High(Parts) do
  begin
    Word := ExtractFileName(Trim(Parts[i]));
    { Skip env and any options it was given. }
    if (Word = 'env') or (Word = '') or (Word[1] = '-') then Continue;
    Exit(LowerCase(Word));
  end;
end;

function TLedLangRegistry.FindForFile(const AFileName: string;
  const AFirstLine: string): TLedLangInfo;
var
  i: Integer;
  Interp, Trimmed: string;
begin
  if AFileName <> '' then
    for i := 0 to FItems.Count - 1 do
      if (not Items[i].Hidden) and Items[i].MatchesFileName(AFileName) then
        Exit(Items[i]);

  Interp := ShebangInterpreter(AFirstLine);
  if Interp <> '' then
  begin
    Result := FindById(Interp);
    if (Result <> nil) and not Result.Hidden then Exit;
    { python3 -> python, perl5 -> perl. }
    Trimmed := Interp;
    while (Trimmed <> '') and (Trimmed[Length(Trimmed)] in ['0'..'9', '.']) do
      SetLength(Trimmed, Length(Trimmed) - 1);
    if Trimmed <> Interp then
    begin
      Result := FindById(Trimmed);
      if (Result <> nil) and not Result.Hidden then Exit;
    end;
    { bash, dash, zsh and friends are all "sh" as far as highlighting goes. }
    if (Interp = 'bash') or (Interp = 'dash') or (Interp = 'zsh') or
       (Interp = 'ksh') then
    begin
      Result := FindById('sh');
      if Result <> nil then Exit;
    end;
  end;

  Result := nil;
end;

procedure TLedLangRegistry.ListForMenu(AResult: TStrings);
var
  Sorter: TStringList;
  i: Integer;
begin
  Sorter := TStringList.Create;
  try
    Sorter.Sorted := True;
    Sorter.Duplicates := dupAccept;
    for i := 0 to FItems.Count - 1 do
      if not Items[i].Hidden then
        Sorter.AddObject(Items[i].Section + #1 + Items[i].Name, Items[i]);
    AResult.Clear;
    for i := 0 to Sorter.Count - 1 do
      AResult.AddObject(Sorter[i], Sorter.Objects[i]);
  finally
    Sorter.Free;
  end;
end;

var
  FRegistry: TLedLangRegistry = nil;

function TLedLangInfo.GlobsText: string;
begin
  Result := StringReplace(Trim(FGlobs.Text), LineEnding, ';', [rfReplaceAll]);
end;

function TLedLangInfo.MimeTypesText: string;
begin
  Result := StringReplace(Trim(FMimeTypes.Text), LineEnding, ';', [rfReplaceAll]);
end;

procedure TLedLangInfo.SetGlobsText(const AValue: string);
begin
  FGlobs.Delimiter := ';';
  FGlobs.StrictDelimiter := True;
  FGlobs.DelimitedText := AValue;
end;

procedure TLedLangInfo.SetMimeTypesText(const AValue: string);
begin
  FMimeTypes.Delimiter := ';';
  FMimeTypes.StrictDelimiter := True;
  FMimeTypes.DelimitedText := AValue;
end;

procedure TLedLangRegistry.ApplyOverrides;
var
  i: Integer;
  Info: TLedLangInfo;
  S: string;
begin
  for i := 0 to Count - 1 do
  begin
    Info := Items[i];
    S := LedPrefs.GetStr('Languages/' + Info.Id + '/globs', '');
    if S <> '' then Info.SetGlobsText(S);
    S := LedPrefs.GetStr('Languages/' + Info.Id + '/mimetypes', '');
    if S <> '' then Info.SetMimeTypesText(S);
  end;
end;

function LedLanguages: TLedLangRegistry;
begin
  if FRegistry = nil then
  begin
    FRegistry := TLedLangRegistry.Create;
    { A user grammar directory is scanned first so it can shadow a shipped
      grammar of the same id. }
    FRegistry.ScanDirectory(LedConfigFile('langs'));
    FRegistry.ScanDirectory(LedDataFile('langs'));
  end;
  Result := FRegistry;
end;

finalization
  FRegistry.Free;

end.
