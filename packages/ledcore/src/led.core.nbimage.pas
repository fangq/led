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
  Led.Core.NBFormat, Led.Core.Markdown;

{ The bytes of one picture: the mime type it was stored as comes back in
  AMime, which is what tells a TPicture how to read them.  False when the
  output holds no picture this can show. }
function LedNBImageOf(ANotebook: TLedNotebook; ACell, AOutput: Integer;
  out ABytes: string; out AMime: string): Boolean;

{ Whether a mime type is a picture LED can draw. }
function LedNBIsImageMime(const AMime: string): Boolean;

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

{ Replaces every <img> in AHtml that points at the web with a line saying
  what is there and where it is from, and leaves the rest alone.

  Notebooks are full of pictures on other people's servers, and a preview
  that fetched them would mean the editor making requests because a file was
  opened -- which nobody asked for by opening a notebook, and which in a
  shared notebook would report every reader of it to whoever put the picture
  there.  So the reader is told that something is there rather than shown it.

  The pictures that are in the file -- a data: URI, an attachment -- and the
  ones beside it on disk are left in the page for the renderer to ask about,
  because showing those costs nothing and tells nobody. }
function LedNBHideRemoteImages(const AHtml: string): string;

{ The file extension a TPicture wants for a mime type: 'png', 'jpg'. }
function LedNBImageExt(const AMime: string): string;

implementation

function LedNBIsImageMime(const AMime: string): Boolean;
begin
  { What the LCL's image readers cover.  SVG is not among them -- it is
    markup, not a bitmap -- so a cell that produced only SVG falls back to
    whatever text came with it. }
  Result := (AMime = 'image/png') or (AMime = 'image/jpeg') or
            (AMime = 'image/jpg') or (AMime = 'image/gif') or
            (AMime = 'image/bmp');
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
function DataURI(const AURL: string; out ABytes, AMime: string): Boolean;
var
  Head, Payload: string;
  Semi, Comma: Integer;
begin
  Result := False;
  ABytes := '';
  AMime := '';
  if Pos('data:', LowerCase(AURL)) <> 1 then Exit;
  Comma := Pos(',', AURL);
  if Comma = 0 then Exit;
  Head := Copy(AURL, 6, Comma - 6);
  Payload := Copy(AURL, Comma + 1, MaxInt);

  Semi := Pos(';', Head);
  if Semi > 0 then AMime := Copy(Head, 1, Semi - 1) else AMime := Head;
  AMime := LowerCase(Trim(AMime));
  if not LedNBIsImageMime(AMime) then Exit;
  { Only base64: a data: URI may carry its payload percent-encoded instead,
    and a picture never does. }
  if Pos('base64', LowerCase(Head)) = 0 then Exit;
  Result := LedNBBase64(Payload, ABytes);
end;

function LedNBHideRemoteImages(const AHtml: string): string;
var
  At, Start, Stop, Quote: Integer;
  Img, URL, Host: string;
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

    { A scheme means somewhere else.  data: is a scheme too and is not
      somewhere else -- the picture is right there in the text. }
    if (URL <> '') and (Pos('://', URL) > 0) then
    begin
      Host := Copy(URL, Pos('://', URL) + 3, MaxInt);
      if Pos('/', Host) > 0 then Host := Copy(Host, 1, Pos('/', Host) - 1);
      Img := '<i>[image from ' + LedHtmlEscape(Host) + ', not fetched]</i>';
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
      Exit(LedNBBase64(Joined(TJSONObject(Entry).Items[i]), ABytes));
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
  Result := LedNBBase64(Coded, ABytes);
end;

end.
