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
  Classes, SysUtils, base64, fpjson,
  Led.Core.NBFormat;

{ The bytes of one picture: the mime type it was stored as comes back in
  AMime, which is what tells a TPicture how to read them.  False when the
  output holds no picture this can show. }
function LedNBImageOf(ANotebook: TLedNotebook; ACell, AOutput: Integer;
  out ABytes: string; out AMime: string): Boolean;

{ Whether a mime type is a picture LED can draw. }
function LedNBIsImageMime(const AMime: string): Boolean;

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

function LedNBImageOf(ANotebook: TLedNotebook; ACell, AOutput: Integer;
  out ABytes: string; out AMime: string): Boolean;
var
  Outs: TJSONArray;
  Data: TJSONData;
  Obj: TJSONObject;
  Coded: string;
  i: Integer;
  Src, Dest: TStringStream;
  Decoder: TBase64DecodingStream;
  Buf: array[0..8191] of Byte;
  Got: Integer;
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

  { The newlines are left in: the decoder steps over whitespace, which is
    what MIME base64 is. }
  Src := TStringStream.Create(Coded);
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
      { A picture that will not decode is a picture that is not shown, not a
        reason to refuse the cell it was in. }
      Result := False;
    end;
  finally
    Decoder.Free;
    Dest.Free;
    Src.Free;
  end;
end;

end.
