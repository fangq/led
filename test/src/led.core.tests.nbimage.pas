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
    function MarkdownCell(const ASource, AAttachments: string): TLedNotebook;
  published
    procedure APictureStoredAsOneStringDecodes;
    procedure APictureSplitAcrossLinesDecodes;
    procedure TheMimeTypeComesBackAsAFileExtension;
    procedure AnOutputWithNoPictureSaysSo;
    procedure TextIsNotAPicture;
    { the pictures a prose cell points at }
    procedure ADataURIIsAPicture;
    procedure AnAttachmentIsAPicture;
    procedure SomethingElseIsNotEmbedded;
    procedure APictureOnTheWebIsNotFetched;
    procedure APictureInTheFileIsLeftInThePage;
    { what a reference resolves to }
    procedure AWebAddressIsRemote;
    procedure AFileURLIsNot;
    procedure ARelativeNameIsResolvedAgainstTheDocument;
    procedure AnAbsolutePathIsLeftAlone;
    procedure AFileURLBecomesAPath;
    procedure APercentEscapeIsUndone;
    procedure SomethingWithNoFileBehindItResolvesToNothing;
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

{ ---- the pictures a prose cell points at ---- }

const
  { A 12 by 7 PNG, so a decode can be checked against a size and a length
    rather than against "something came back". }
  TinyPNG = 'iVBORw0KGgoAAAANSUhEUgAAAAwAAAAHCAIAAACz0DtzAAAAEUlEQVR4nGPgOhFFEDEMa0UAtUpicQeGsj0AAAAASUVORK5CYII=';
  TinyBytes = 74;

{ A notebook of one markdown cell whose source is ASource and whose
  attachments are AAttachments, both as JSON. }
function TTestNBImage.MarkdownCell(const ASource,
  AAttachments: string): TLedNotebook;
var
  Err, Att: string;
begin
  Att := '';
  if AAttachments <> '' then Att := ',"attachments":' + AAttachments;
  Result := TLedNotebook.Create;
  AssertTrue('the fixture is a notebook: ' + Err, Result.LoadFromText(
    '{"cells":[{"cell_type":"markdown","metadata":{}' + Att +
    ',"source":["' + ASource + '"]}],' +
    '"metadata":{},"nbformat":4,"nbformat_minor":5}', Err));
end;

procedure TTestNBImage.ADataURIIsAPicture;
var
  NB: TLedNotebook;
  Bytes, Mime: string;
begin
  { The form a picture takes when it is written into the text itself. }
  NB := MarkdownCell('see this', '');
  try
    AssertTrue('it decodes', LedNBEmbeddedImage(NB, 0,
      'data:image/png;base64,' + TinyPNG, Bytes, Mime));
    AssertEquals('every byte of it', TinyBytes, Length(Bytes));
    AssertEquals('image/png', Mime);
    AssertEquals('and it is a PNG', #$89 + 'PNG', Copy(Bytes, 1, 4));

    AssertFalse('a data URI that is not a picture is not one',
      LedNBEmbeddedImage(NB, 0, 'data:text/plain;base64,aGk=', Bytes, Mime));
    AssertFalse('nor is one with no comma',
      LedNBEmbeddedImage(NB, 0, 'data:image/png;base64', Bytes, Mime));
  finally
    NB.Free;
  end;
end;

procedure TTestNBImage.AnAttachmentIsAPicture;
var
  NB: TLedNotebook;
  Bytes, Mime: string;
begin
  { A picture pasted into a cell: the text says attachment:name and the
    cell's own attachments hold it. }
  NB := MarkdownCell('![a picture](attachment:shot.png)',
    '{"shot.png":{"image/png":"' + TinyPNG + '"}}');
  try
    AssertTrue('it decodes', LedNBEmbeddedImage(NB, 0,
      'attachment:shot.png', Bytes, Mime));
    AssertEquals(TinyBytes, Length(Bytes));
    AssertEquals('image/png', Mime);
    { The name on its own, which is how some writers refer to one. }
    AssertTrue('and the bare name finds it too',
      LedNBEmbeddedImage(NB, 0, 'shot.png', Bytes, Mime));
    AssertFalse('a name the cell does not carry is not found',
      LedNBEmbeddedImage(NB, 0, 'attachment:other.png', Bytes, Mime));
  finally
    NB.Free;
  end;
end;

procedure TTestNBImage.SomethingElseIsNotEmbedded;
var
  NB: TLedNotebook;
  Bytes, Mime: string;
begin
  NB := MarkdownCell('nothing here', '');
  try
    AssertFalse('a file beside the notebook is not embedded',
      LedNBEmbeddedImage(NB, 0, 'plot.png', Bytes, Mime));
    AssertFalse('nor is something on the web',
      LedNBEmbeddedImage(NB, 0, 'https://example.com/a.png', Bytes, Mime));
    AssertFalse('nor is nothing at all',
      LedNBEmbeddedImage(NB, 0, '', Bytes, Mime));
  finally
    NB.Free;
  end;
end;

procedure TTestNBImage.APictureOnTheWebIsNotFetched;
var
  Page: string;
begin
  { Opening a notebook must not make the editor call on other people's
    servers, so the tag comes out and a line saying what is missing goes in.
    The host is named, because "an image is missing" is less use than which
    one. }
  Page := LedNBHideRemoteImages(
    '<p>before <img src="https://img.example.com/cat.png" alt="a cat"> after</p>');
  AssertTrue('the tag is gone: ' + Page, Pos('<img', Page) = 0);
  AssertTrue('the host is named', Pos('img.example.com', Page) > 0);
  AssertTrue('and the prose around it is untouched',
    (Pos('before', Page) > 0) and (Pos('after', Page) > 0));

  { Two of them, which is where a rewrite that walks the string wrongly
    loops for ever or eats the text between. }
  Page := LedNBHideRemoteImages(
    '<img src="http://a.example/1.png"> middle <img src="http://b.example/2.png">');
  AssertTrue('both are gone', Pos('<img', Page) = 0);
  AssertTrue('the first host is named', Pos('a.example', Page) > 0);
  AssertTrue('and the second', Pos('b.example', Page) > 0);
  AssertTrue('and what was between them is still there',
    Pos('middle', Page) > 0);
end;

procedure TTestNBImage.APictureInTheFileIsLeftInThePage;
var
  Page: string;
begin
  { These the renderer may ask about, because answering them tells nobody
    anything: the picture is in the file or beside it. }
  Page := LedNBHideRemoteImages('<img src="data:image/png;base64,AAAA">');
  AssertTrue('a data URI stays: ' + Page, Pos('<img', Page) > 0);
  Page := LedNBHideRemoteImages('<img src="attachment:shot.png">');
  AssertTrue('so does an attachment', Pos('<img', Page) > 0);
  Page := LedNBHideRemoteImages('<img src="plot.png">');
  AssertTrue('and so does a file beside the notebook', Pos('<img', Page) > 0);
  AssertEquals('a page with no pictures is returned as it was',
    '<p>hello</p>', LedNBHideRemoteImages('<p>hello</p>'));
end;

{ ---- what a reference resolves to ----

  The renderer resolves nothing itself: it hands over the text of the src
  attribute and expects a picture back, so every form a notebook writes one
  in has to be understood here.  file:// is the one that reads like a URL and
  is not: nothing is fetched for it, the file is simply opened. }

procedure TTestNBImage.AWebAddressIsRemote;
begin
  AssertTrue('http', LedNBIsRemote('http://example.com/a.png'));
  AssertTrue('https', LedNBIsRemote('https://example.com/a.png'));
end;

procedure TTestNBImage.AFileURLIsNot;
begin
  AssertFalse('file://', LedNBIsRemote('file:///tmp/a.png'));
  AssertFalse('a bare name', LedNBIsRemote('a.png'));
  AssertFalse('a path', LedNBIsRemote('/tmp/a.png'));
end;

procedure TTestNBImage.ARelativeNameIsResolvedAgainstTheDocument;
begin
  { Against the notebook's own folder and not the working directory, which
    is where a picture beside a notebook opened from elsewhere went missing. }
  AssertEquals('/home/me/nb/fig.png',
    LedNBLocalPath('fig.png', '/home/me/nb'));
  AssertEquals('/home/me/nb/img/fig.png',
    LedNBLocalPath('img/fig.png', '/home/me/nb/'));
end;

procedure TTestNBImage.AnAbsolutePathIsLeftAlone;
begin
  AssertEquals('/tmp/fig.png', LedNBLocalPath('/tmp/fig.png', '/home/me/nb'));
end;

procedure TTestNBImage.AFileURLBecomesAPath;
begin
  AssertEquals('/tmp/fig.png', LedNBLocalPath('file:///tmp/fig.png', ''));
  { file://localhost/path names the same file as file:///path. }
  AssertEquals('/tmp/fig.png',
    LedNBLocalPath('file://localhost/tmp/fig.png', ''));
end;

procedure TTestNBImage.APercentEscapeIsUndone;
begin
  AssertEquals('/tmp/my fig.png',
    LedNBLocalPath('file:///tmp/my%20fig.png', ''));
  AssertEquals('/home/me/nb/my fig.png',
    LedNBLocalPath('my%20fig.png', '/home/me/nb'));
end;

procedure TTestNBImage.SomethingWithNoFileBehindItResolvesToNothing;
begin
  AssertEquals('', LedNBLocalPath('', '/home/me/nb'));
  AssertEquals('', LedNBLocalPath('https://example.com/a.png', '/home/me/nb'));
  AssertEquals('', LedNBLocalPath('data:image/png;base64,AAAA', '/home/me/nb'));
end;

initialization
  RegisterTest(TTestNBImage);

end.
