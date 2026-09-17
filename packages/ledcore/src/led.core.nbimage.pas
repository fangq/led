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

{ How big a picture is, read from its header rather than by decoding it:
  PNG, JPEG, GIF and BMP.  False for anything else, and for bytes too short
  to say.

  Wanted because a page has to know before it is laid out: see
  LedNBFitImages. }
function LedNBPictureSize(const ABytes: string; out AW, AH: Integer): Boolean;

{ Asked how big the picture behind a reference is.  The caller has the
  pictures -- fetched, embedded, or beside the file -- and this unit has the
  page. }
type
  TLedNBImageSize = function(const AURL: string;
    out AW, AH: Integer): Boolean of object;

{ Gives every <img> in AHtml that is wider than AMaxWidth a width and a
  height that fit, in proportion.

  Because this renderer draws a picture at its natural size and cannot
  scroll a block sideways: a 700-pixel meme in a 600-pixel pane is drawn
  700 pixels wide and the last hundred of it are simply not there.  Browsers
  answer this with max-width, which IPro does not read; the attributes it
  does read are width and height, so the arithmetic is done here.

  A tag that already carries a width is left alone -- the document asked for
  that size -- and so is one whose picture cannot be measured, which is no
  worse than before.  AMaxWidth <= 0 leaves everything alone. }
function LedNBFitImages(const AHtml: string; AMaxWidth: Integer;
  ASizeOf: TLedNBImageSize): string;

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

function BigEndian32(const ABytes: string; AAt: Integer): Integer;
begin
  Result := (Ord(ABytes[AAt]) shl 24) or (Ord(ABytes[AAt + 1]) shl 16) or
            (Ord(ABytes[AAt + 2]) shl 8) or Ord(ABytes[AAt + 3]);
end;

function LittleEndian16(const ABytes: string; AAt: Integer): Integer;
begin
  Result := Ord(ABytes[AAt]) or (Ord(ABytes[AAt + 1]) shl 8);
end;

function LittleEndian32(const ABytes: string; AAt: Integer): Integer;
begin
  Result := Ord(ABytes[AAt]) or (Ord(ABytes[AAt + 1]) shl 8) or
            (Ord(ABytes[AAt + 2]) shl 16) or (Ord(ABytes[AAt + 3]) shl 24);
end;

function LedNBPictureSize(const ABytes: string; out AW, AH: Integer): Boolean;
var
  i, n, Len: Integer;
  Marker: Byte;
begin
  Result := False;
  AW := 0;
  AH := 0;
  n := Length(ABytes);
  if n < 16 then Exit;

  { PNG: the IHDR chunk is always first, and its two sizes are the eight
    bytes after the chunk's name. }
  if Copy(ABytes, 1, 8) = #$89'PNG'#13#10#26#10 then
  begin
    if n < 24 then Exit;
    AW := BigEndian32(ABytes, 17);
    AH := BigEndian32(ABytes, 21);
    Exit((AW > 0) and (AH > 0));
  end;

  { GIF: the screen descriptor, right after the six-byte signature. }
  if (Copy(ABytes, 1, 6) = 'GIF87a') or (Copy(ABytes, 1, 6) = 'GIF89a') then
  begin
    AW := LittleEndian16(ABytes, 7);
    AH := LittleEndian16(ABytes, 9);
    Exit((AW > 0) and (AH > 0));
  end;

  { BMP: the info header, which counts height upwards and so may be
    negative for a picture stored top down. }
  if Copy(ABytes, 1, 2) = 'BM' then
  begin
    if n < 26 then Exit;
    AW := LittleEndian32(ABytes, 19);
    AH := Abs(LittleEndian32(ABytes, 23));
    Exit((AW > 0) and (AH > 0));
  end;

  { JPEG: walked, because the size lives in a start-of-frame segment and
    what comes before it is not fixed. }
  if Copy(ABytes, 1, 2) = #$FF#$D8 then
  begin
    i := 3;
    while i + 8 < n do
    begin
      if Ord(ABytes[i]) <> $FF then
      begin
        Inc(i);
        Continue;
      end;
      Marker := Ord(ABytes[i + 1]);
      { Padding between segments, and the two markers that carry no length. }
      if (Marker = $FF) or (Marker = $01) or
         ((Marker >= $D0) and (Marker <= $D9)) then
      begin
        Inc(i);
        Continue;
      end;
      Len := (Ord(ABytes[i + 2]) shl 8) or Ord(ABytes[i + 3]);
      { Any start-of-frame: baseline, progressive, arithmetic, lossless.
        Not the four that are something else with a number in the range. }
      if (((Marker >= $C0) and (Marker <= $C3)) or
          ((Marker >= $C5) and (Marker <= $C7)) or
          ((Marker >= $C9) and (Marker <= $CB)) or
          ((Marker >= $CD) and (Marker <= $CF))) and (i + 8 <= n) then
      begin
        { After the marker and its two length bytes: one byte of sample
          precision, then the height and then the width.  That order, and
          that offset -- the first version read from one byte further on and
          gave a five-figure width for a forty-pixel picture. }
        AH := (Ord(ABytes[i + 5]) shl 8) or Ord(ABytes[i + 6]);
        AW := (Ord(ABytes[i + 7]) shl 8) or Ord(ABytes[i + 8]);
        Exit((AW > 0) and (AH > 0));
      end;
      if Len < 2 then Exit;
      Inc(i, Len + 2);
    end;
  end;
end;

function LedNBFitImages(const AHtml: string; AMaxWidth: Integer;
  ASizeOf: TLedNBImageSize): string;
var
  At, Start, Stop, Quote, W, H: Integer;
  Img, URL, Lower: string;
begin
  Result := AHtml;
  if (AMaxWidth <= 0) or (not Assigned(ASizeOf)) then Exit;
  At := 1;
  while True do
  begin
    Lower := LowerCase(Result);
    Start := PosEx('<img', Lower, At);
    if Start = 0 then Break;
    Stop := PosEx('>', Result, Start);
    if Stop = 0 then Break;
    Img := Copy(Result, Start, Stop - Start + 1);
    At := Stop + 1;

    { The document's own size wins. }
    if Pos('width=', LowerCase(Img)) > 0 then Continue;

    URL := '';
    Quote := Pos('src="', LowerCase(Img));
    if Quote > 0 then
    begin
      URL := Copy(Img, Quote + 5, MaxInt);
      Quote := Pos('"', URL);
      if Quote > 0 then URL := Copy(URL, 1, Quote - 1);
    end;
    if URL = '' then Continue;
    if not ASizeOf(URL, W, H) then Continue;
    if (W <= 0) or (H <= 0) or (W <= AMaxWidth) then Continue;

    { In proportion, and at least one pixel tall however wide the picture
      was. }
    H := Round(H * (AMaxWidth / W));
    if H < 1 then H := 1;
    Img := Copy(Img, 1, Length(Img) - 1) + ' width="' + IntToStr(AMaxWidth) +
      '" height="' + IntToStr(H) + '">';
    Result := Copy(Result, 1, Start - 1) + Img +
      Copy(Result, Stop + 1, MaxInt);
    At := Start + Length(Img);
  end;
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
