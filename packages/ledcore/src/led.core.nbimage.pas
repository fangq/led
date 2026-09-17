// led - a lightweight editor.  The pictures inside a notebook.
//
// An output that is a plot is base64 in a JSON field, and the notebook pane
// shows it as a picture.  This is the piece in between.
//
// Nothing is written to a temporary file.  A picture is named by where it
// lives -- cell, output, mime type -- and decoded straight out of the
// notebook when the pane builds that cell, so there is nothing to clean up
// afterwards and nothing left in /tmp after a plot has been looked at.

unit Led.Core.NBImage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, base64, fpjson,
  Led.Core.NBFormat, Led.Core.Markdown, Led.Core.NBConvert;

{ The bytes of one picture: the mime type it was stored as comes back in
  AMime, which is what tells a TPicture how to read them.  False when the
  output holds no picture this can show. }
function LedNBImageOf(ANotebook: TLedNotebook; ACell, AOutput: Integer;
  out ABytes: string; out AMime: string): Boolean;

{ Whether a mime type is a picture LED can draw. }
function LedNBIsImageMime(const AMime: string): Boolean;

{ The file a picture reference names, or '' when it does not name one.

  Handles what a notebook actually carries: a plain relative name beside the
  file, an absolute path, and a file:// URL -- which the renderer does not
  resolve itself, its provider dealing in paths rather than URLs.  Percent
  escapes are undone, because a file:// URL writes a space as %20 and the
  filesystem does not.

  Empty for anything on the web and for a data: URI, which are somebody
  else's business. }
function LedNBLocalPath(const AURL, ABaseDir: string): string;

{ Whether a reference points at another machine -- which is to say, whether
  it needs fetching.  file:// does not, despite having a scheme. }
function LedNBIsRemote(const AURL: string): Boolean;

{ The bytes behind a picture a markdown cell refers to, whatever form the
  reference takes: a data: URI with the picture in it, or an attachment
  pasted into the cell.  False for a name that is neither -- a file beside
  the notebook, or something on the web -- which the caller resolves its own
  way or declines to.

  These are the two forms where the picture is inside the file, which is
  what makes them answerable here at all. }
function LedNBEmbeddedImage(ANotebook: TLedNotebook; ACell: Integer;
  const AURL: string; out ABytes: string; out AMime: string): Boolean;

{ Base64, decoded.  Public because both kinds of embedded picture are stored
  that way and so is every output. }
function LedNBBase64(const ACoded: string; out ABytes: string): Boolean;

{ Sorts the <img> tags in AHtml into the ones the renderer may ask about and
  the ones it may not.

  A picture in the file -- a data: URI, an attachment -- or beside it on disk
  is always left in the page.  One on the web is left in only if AHave says
  it is already here; otherwise the tag is replaced by a line saying what is
  there and why it is not being shown.

  AHave is where fetching is decided, and it is deliberately not decided
  here: this unit knows about pictures and nothing about connections.  Passed
  nil, every remote picture is replaced, which is what a caller that does not
  fetch wants. }
type
  TLedNBHaveImage = function(const AURL: string; out AWhy: string): Boolean
    of object;

function LedNBHideRemoteImages(const AHtml: string;
  AHave: TLedNBHaveImage = nil): string;

{ The file extension a TPicture wants for a mime type: 'png', 'jpg'. }
function LedNBImageExt(const AMime: string): string;

implementation

function LedNBIsRemote(const AURL: string): Boolean;
begin
  Result := (Pos('://', AURL) > 0) and
            (Pos('file://', LowerCase(AURL)) <> 1);
end;

{ %20 and its friends, undone. }
function Unpercent(const AText: string): string;
var
  i, V: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(AText) do
  begin
    if (AText[i] = '%') and (i + 2 <= Length(AText)) and
       TryStrToInt('$' + Copy(AText, i + 1, 2), V) then
    begin
      Result := Result + Chr(V);
      Inc(i, 3);
    end
    else
    begin
      Result := Result + AText[i];
      Inc(i);
    end;
  end;
end;

function LedNBLocalPath(const AURL, ABaseDir: string): string;
var
  Path: string;
begin
  Result := '';
  if AURL = '' then Exit;
  if Pos('data:', LowerCase(AURL)) = 1 then Exit;
  if LedNBIsRemote(AURL) then Exit;

  Path := AURL;
  if Pos('file://', LowerCase(Path)) = 1 then
  begin
    Path := Copy(Path, Length('file://') + 1, MaxInt);
    { file://localhost/path and file:///path both name the same file. }
    if Pos('localhost/', LowerCase(Path)) = 1 then
      Path := Copy(Path, Length('localhost') + 1, MaxInt);
    if Path = '' then Exit;
  end;
  Path := Unpercent(Path);
  if Path = '' then Exit;

  { A drive letter or a leading separator is already absolute; anything else
    is beside the notebook. }
  if (Path[1] = '/') or (Path[1] = '\\') or
     ((Length(Path) > 1) and (Path[2] = ':')) then
    Result := Path
  else if ABaseDir <> '' then
    Result := IncludeTrailingPathDelimiter(ABaseDir) + Path
  else
    Result := Path;
end;

function LedNBIsImageMime(const AMime: string): Boolean;
begin
  { What the LCL's image readers cover. }
  Result := (AMime = 'image/png') or (AMime = 'image/jpeg') or
            (AMime = 'image/jpg') or (AMime = 'image/gif') or
            (AMime = 'image/bmp');
  if Result then Exit;
  { And the two it does not, when this machine has something to convert them
    with -- a cell that asked matplotlib for SVG is the common one.  Asked
    rather than assumed, because on a machine with no converter the honest
    answer is no, and the cell then falls back to whatever text came with
    it rather than showing a gap. }
  if (AMime = 'image/svg+xml') or (AMime = 'image/svg') then
    Result := LedNBConverterFor('svg') <> ''
  else if AMime = 'image/webp' then
    Result := LedNBConverterFor('webp') <> '';
end;

function LedNBImageExt(const AMime: string): string;
begin
  if (AMime = 'image/jpeg') or (AMime = 'image/jpg') then Exit('jpg');
  if AMime = 'image/gif' then Exit('gif');
  if AMime = 'image/bmp' then Exit('bmp');
  Result := 'png';
end;

{ A JSON string or list of strings, joined.  Base64 in a notebook is usually
  split across lines, and text always is. }
function Joined(AValue: TJSONData): string;
var
  i: Integer;
begin
  Result := '';
  if AValue = nil then Exit;
  if AValue.JSONType = jtString then Exit(AValue.AsString);
  if AValue.JSONType <> jtArray then Exit;
  for i := 0 to TJSONArray(AValue).Count - 1 do
    if TJSONArray(AValue).Items[i].JSONType = jtString then
      Result := Result + TJSONArray(AValue).Items[i].AsString;
end;

function LedNBBase64(const ACoded: string; out ABytes: string): Boolean;
var
  Src, Dest: TStringStream;
  Decoder: TBase64DecodingStream;
  Buf: array[0..8191] of Byte;
  Got: Integer;
begin
  Result := False;
  ABytes := '';
  if Trim(ACoded) = '' then Exit;

  { The newlines are left in: the decoder steps over whitespace, which is
    what MIME base64 is. }
  Src := TStringStream.Create(ACoded);
  Dest := TStringStream.Create('');
  Decoder := TBase64DecodingStream.Create(Src, bdmMIME);
  try
    try
      { Read until it stops giving, rather than CopyFrom: a decoding stream
        cannot say how long it is before it has decoded itself, and asking
        it -- which is what CopyFrom with a count of nothing does -- comes
        back with nothing at all. }
      repeat
        Got := Decoder.Read(Buf, SizeOf(Buf));
        if Got > 0 then Dest.Write(Buf, Got);
      until Got <= 0;
      ABytes := Dest.DataString;
      Result := ABytes <> '';
    except
      Result := False;
    end;
  finally
    Decoder.Free;
    Dest.Free;
    Src.Free;
  end;
end;

{ A data: URI -- data:image/png;base64,iVBORw0... -- which is how a picture
  gets into a markdown cell that was written by hand or by a converter. }
{ Whether a picture of this kind is stored as base64 or as itself.

  nbformat and data: URIs agree about this and it is easy to miss: a PNG is
  base64 because it is bytes, and an SVG is the markup itself because it is
  text.  Decoding the markup as base64 gives nothing, which is how a cell
  whose plot was SVG came back with an empty picture. }
function IsCoded(const AMime: string): Boolean;
begin
  Result := (AMime <> 'image/svg+xml') and (AMime <> 'image/svg');
end;

{ The value of a data entry as bytes, decoded if it is stored encoded. }
function Payload(const AText, AMime: string; out ABytes: string): Boolean;
begin
  if IsCoded(AMime) then Exit(LedNBBase64(AText, ABytes));
  ABytes := AText;
  Result := ABytes <> '';
end;

function DataURI(const AURL: string; out ABytes, AMime: string): Boolean;
var
  Head, Body: string;
  Semi, Comma: Integer;
begin
  Result := False;
  ABytes := '';
  AMime := '';
  if Pos('data:', LowerCase(AURL)) <> 1 then Exit;
  Comma := Pos(',', AURL);
  if Comma = 0 then Exit;
  Head := Copy(AURL, 6, Comma - 6);
  Body := Copy(AURL, Comma + 1, MaxInt);

  Semi := Pos(';', Head);
  if Semi > 0 then AMime := Copy(Head, 1, Semi - 1) else AMime := Head;
  AMime := LowerCase(Trim(AMime));
  if not LedNBIsImageMime(AMime) then Exit;
  { A bitmap is always base64 here: a data: URI may carry its payload
    percent-encoded instead and a picture never does.  An SVG is text and is
    written either way, so it is taken as it comes. }
  if IsCoded(AMime) and (Pos('base64', LowerCase(Head)) = 0) then Exit;
  if Pos('base64', LowerCase(Head)) > 0 then
    Result := LedNBBase64(Body, ABytes)
  else
    Result := Payload(Unpercent(Body), AMime, ABytes);
end;

function LedNBHideRemoteImages(const AHtml: string;
  AHave: TLedNBHaveImage): string;
var
  At, Start, Stop, Quote: Integer;
  Img, URL, Host, Why: string;
begin
  Result := AHtml;
  At := 1;
  while True do
  begin
    Start := PosEx('<img', LowerCase(Result), At);
    if Start = 0 then Break;
    Stop := PosEx('>', Result, Start);
    if Stop = 0 then Break;
    Img := Copy(Result, Start, Stop - Start + 1);

    URL := '';
    Quote := Pos('src="', LowerCase(Img));
    if Quote > 0 then
    begin
      URL := Copy(Img, Quote + 5, MaxInt);
      Quote := Pos('"', URL);
      if Quote > 0 then URL := Copy(URL, 1, Quote - 1);
    end;

    { Somewhere else, which is to say something that has to be fetched.
      data: has a scheme and is not somewhere else -- the picture is right
      there in the text -- and neither is file://, which is a file. }
    if (URL <> '') and LedNBIsRemote(URL) then
    begin
      Why := '';
      if Assigned(AHave) and AHave(URL, Why) then
      begin
        { Here already: the renderer may have it. }
        At := Stop + 1;
        Continue;
      end;
      Host := Copy(URL, Pos('://', URL) + 3, MaxInt);
      if Pos('/', Host) > 0 then Host := Copy(Host, 1, Pos('/', Host) - 1);
      if Why = '' then Why := 'not fetched';
      Img := '<i>[image from ' + LedHtmlEscape(Host) + ', ' +
        LedHtmlEscape(Why) + ']</i>';
      Result := Copy(Result, 1, Start - 1) + Img +
        Copy(Result, Stop + 1, MaxInt);
      At := Start + Length(Img);
    end
    else
      At := Stop + 1;
  end;
end;

function LedNBEmbeddedImage(ANotebook: TLedNotebook; ACell: Integer;
  const AURL: string; out ABytes: string; out AMime: string): Boolean;
var
  Att: TJSONObject;
  Name_: string;
  Entry: TJSONData;
  i: Integer;
begin
  ABytes := '';
  AMime := '';
  Result := False;
  if AURL = '' then Exit;

  if DataURI(AURL, ABytes, AMime) then Exit(True);

  { attachment:something.png is how nbformat names a picture pasted into the
    cell; the cell's own attachments hold it. }
  Name_ := AURL;
  if Pos('attachment:', LowerCase(Name_)) = 1 then
    Name_ := Copy(Name_, Length('attachment:') + 1, MaxInt);

  Att := ANotebook.CellAttachments(ACell);
  if Att = nil then Exit;
  Entry := Att.Find(Name_);
  if (Entry = nil) or (Entry.JSONType <> jtObject) then Exit;

  for i := 0 to TJSONObject(Entry).Count - 1 do
    if LedNBIsImageMime(TJSONObject(Entry).Names[i]) then
    begin
      AMime := TJSONObject(Entry).Names[i];
      Exit(Payload(Joined(TJSONObject(Entry).Items[i]), AMime, ABytes));
    end;
end;

function LedNBImageOf(ANotebook: TLedNotebook; ACell, AOutput: Integer;
  out ABytes: string; out AMime: string): Boolean;
var
  Outs: TJSONArray;
  Data: TJSONData;
  Obj: TJSONObject;
  Coded: string;
  i: Integer;
begin
  Result := False;
  ABytes := '';
  AMime := '';

  Outs := ANotebook.CellOutputs(ACell);
  if (Outs = nil) or (AOutput < 0) or (AOutput >= Outs.Count) then Exit;
  if Outs.Items[AOutput].JSONType <> jtObject then Exit;
  Data := TJSONObject(Outs.Items[AOutput]).Find('data');
  if (Data = nil) or (Data.JSONType <> jtObject) then Exit;
  Obj := TJSONObject(Data);

  Coded := '';
  for i := 0 to Obj.Count - 1 do
    if LedNBIsImageMime(Obj.Names[i]) then
    begin
      AMime := Obj.Names[i];
      Coded := Joined(Obj.Items[i]);
      Break;
    end;
  if Coded = '' then Exit;
  Result := Payload(Coded, AMime, ABytes);
end;

end.
