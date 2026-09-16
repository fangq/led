// led - a lightweight editor.  Tests for the pictures inside a notebook.
//
// A plot in a notebook is base64 in a JSON field, and the pane draws it.
// What is checked here is the decoding, against a picture whose bytes are
// known: a 24 by 9 PNG, which has a signature to look for and a length to
// count.  It is stored two ways, as one string and as a list of lines,
// because notebooks written by different tools do both.

unit Led.Core.Tests.NBImage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.NBFormat, Led.Core.NBImage;

type
  TTestNBImage = class(TTestCase)
  private
    function Notebook(const AData: string): TLedNotebook;
  published
    procedure APictureStoredAsOneStringDecodes;
    procedure APictureSplitAcrossLinesDecodes;
    procedure TheMimeTypeComesBackAsAFileExtension;
    procedure AnOutputWithNoPictureSaysSo;
    procedure TextIsNotAPicture;
  end;

implementation

const
  PNG64 = 'iVBORw0KGgoAAAANSUhEUgAAABgAAAAJCAIAAACnn3uRAAAAFUlEQVR4nGM4oaFBFcQwatCoQVRAAMNy7EEtcnPeAAAAAElFTkSuQmCC';
  PNGLines = '[' + '"iVBORw0KGgoAAAANSUhEUgAAABgAAAAJCAIAAACnn3uRAAAAFUlEQVR4nGM4oaFBFcQwatCoQVRA"' + ',' + '"AMNy7EEtcnPeAAAAAElFTkSuQmCC"' + ']';
  PNGBytes = 78;

function TTestNBImage.Notebook(const AData: string): TLedNotebook;
var
  Err: string;
begin
  Result := TLedNotebook.Create;
  AssertTrue('the fixture is a notebook: ' + Err, Result.LoadFromText(
    '{"cells":[{"cell_type":"code","execution_count":1,"metadata":{},' +
    '"outputs":[{"data":' + AData + ',"metadata":{},' +
    '"output_type":"display_data"}],"source":["plot()"]}],' +
    '"metadata":{},"nbformat":4,"nbformat_minor":5}', Err));
end;

procedure TTestNBImage.APictureStoredAsOneStringDecodes;
var
  NB: TLedNotebook;
  Bytes, Mime: string;
begin
  NB := Notebook('{"image/png":"' + PNG64 + '"}');
  try
    AssertTrue('it decodes', LedNBImageOf(NB, 0, 0, Bytes, Mime));
    AssertEquals('every byte of it', PNGBytes, Length(Bytes));
    AssertEquals('and it is a PNG', #$89 + 'PNG', Copy(Bytes, 1, 4));
    AssertEquals('image/png', Mime);
  finally
    NB.Free;
  end;
end;

procedure TTestNBImage.APictureSplitAcrossLinesDecodes;
var
  NB: TLedNotebook;
  Bytes, Mime: string;
begin
  { The shape nbformat writes: base64 broken into lines.  A decoder that
    does not step over the newlines gets nothing. }
  NB := Notebook('{"image/png":' + PNGLines + '}');
  try
    AssertTrue('it decodes', LedNBImageOf(NB, 0, 0, Bytes, Mime));
    AssertEquals('to the same bytes as the one-string form',
      PNGBytes, Length(Bytes));
  finally
    NB.Free;
  end;
end;

procedure TTestNBImage.TheMimeTypeComesBackAsAFileExtension;
begin
  AssertEquals('png', LedNBImageExt('image/png'));
  AssertEquals('jpg', LedNBImageExt('image/jpeg'));
  AssertEquals('gif', LedNBImageExt('image/gif'));
  AssertTrue('a picture is a picture', LedNBIsImageMime('image/png'));
  AssertFalse('and markup is not', LedNBIsImageMime('image/svg+xml'));
  AssertFalse('nor is text', LedNBIsImageMime('text/plain'));
end;

procedure TTestNBImage.AnOutputWithNoPictureSaysSo;
var
  NB: TLedNotebook;
  Bytes, Mime: string;
begin
  NB := Notebook('{"text/plain":["42"]}');
  try
    AssertFalse('there is nothing to draw',
      LedNBImageOf(NB, 0, 0, Bytes, Mime));
    AssertEquals('', Bytes);
    AssertFalse('and an output that is not there is not a picture either',
      LedNBImageOf(NB, 0, 7, Bytes, Mime));
    AssertFalse('nor is a cell that is not there',
      LedNBImageOf(NB, 9, 0, Bytes, Mime));
  finally
    NB.Free;
  end;
end;

procedure TTestNBImage.TextIsNotAPicture;
var
  NB: TLedNotebook;
  Bytes, Mime: string;
begin
  { An SVG is a picture to a person and markup to a bitmap reader, so it is
    left to the text beside it rather than half-drawn. }
  NB := Notebook('{"image/svg+xml":["<svg/>"],"text/plain":["<Figure>"]}');
  try
    AssertFalse('SVG is not offered as a bitmap',
      LedNBImageOf(NB, 0, 0, Bytes, Mime));
  finally
    NB.Free;
  end;
end;

initialization
  RegisterTest(TTestNBImage);

end.
