// led - a lightweight editor.  Tests for fetching a notebook's pictures.
//
// The fetching itself is checked against a server started here, on the
// loopback, rather than against somebody's website: a test that needs the
// internet fails on a train, and one that needs a particular site fails the
// day that site changes.  A server of our own answers in milliseconds and
// answers the same way every time -- including the awkward ways, which is
// most of what is worth checking: a picture that is not a picture, a link
// that is not there, a body too large to keep.

unit Led.Core.Tests.NBFetch;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, fphttpserver,
  Led.Core.NBFetch, Led.Core.NBImage, Led.Core.Prefs;

type
  { The server, on a thread, answering the few paths the tests ask for. }
  TTestServer = class(TThread)
  private
    FServer: TFPHttpServer;
    FPort: Word;
    procedure Request(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
  protected
    procedure Execute; override;
  public
    constructor Create(APort: Word);
    destructor Destroy; override;
    { Closes the listening socket.  Not a Free: a thread sitting in accept
      does not always come back, and waiting for one that will not is how a
      test run stops answering. }
    procedure Stop;
    property Port: Word read FPort;
  end;

  TTestNBFetch = class(TTestCase)
  private
    FServer: TTestServer;
    FArrived: Integer;
    FLastURL: string;
    { Drains the queue of pictures that have arrived, the way the pane's own
      timer does. }
    procedure Drain;
    function Base: string;
    { Pumps the main thread until AURL is in hand or the time is up.  The
      fetch finishes on a thread and hands over through Synchronize, so
      something has to run the main thread's queue. }
    function WaitFor(const AURL: string; ASeconds: Integer): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { what a picture is, from its bytes }
    procedure APngIsRecognisedByItsBytes;
    procedure AWebpIsNotSomethingThisCanDraw;
    procedure RubbishIsNotAPicture;
    { the page }
    procedure APictureAlreadyHereIsLeftInThePage;
    procedure APictureThatIsNotSaysWhyInItsPlace;
    procedure WithNoAnswerAtAllEveryRemotePictureIsReplaced;
    { fetching }
    procedure APictureIsFetchedAndKept;
    procedure ASecondAskIsAnsweredFromWhatWasKept;
    procedure ALinkThatIsNotThereFailsAndStaysFailed;
    procedure SomethingThatIsNotAPictureIsRefusedAfterFetching;
    procedure NothingIsFetchedWhenTheReaderHasSaidNot;
    procedure APageOfPicturesIsFetchedOneAtATime;
    procedure AWebpSaysWhatItIs;
    procedure AWebPageInsteadOfAPictureSaysSo;
  end;

implementation

uses
  base64;

var
  { The one server the tests fetch from.  Freed when the unit goes, and only
    then: see SetUp. }
  GServer: TTestServer = nil;

const
  { A 3 by 2 PNG, as bytes.  Small enough to write out, real enough to be
    recognised. }
  PngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAADZebicAAAAFklEQVQI12P8//8/' +
    'AzJgYkAD9BEAAG4bAwLSjz0eAAAAAElFTkSuQmCC';

function PngBytes: string;
var
  Src: TStringStream;
  Dest: TStringStream;
  Decoder: TBase64DecodingStream;
  Buf: array[0..1023] of Byte;
  Got: Integer;
begin
  Result := '';
  Src := TStringStream.Create(PngBase64);
  Dest := TStringStream.Create('');
  Decoder := TBase64DecodingStream.Create(Src, bdmMIME);
  try
    repeat
      Got := Decoder.Read(Buf, SizeOf(Buf));
      if Got > 0 then Dest.Write(Buf, Got);
    until Got <= 0;
    Result := Dest.DataString;
  finally
    Decoder.Free;
    Dest.Free;
    Src.Free;
  end;
end;

{ ---- the server ---- }

constructor TTestServer.Create(APort: Word);
begin
  FPort := APort;
  FreeOnTerminate := False;
  inherited Create(True);
  FServer := TFPHttpServer.Create(nil);
  FServer.Port := APort;
  FServer.Threaded := True;
  FServer.OnRequest := @Request;
  Start;
end;

procedure TTestServer.Stop;
begin
  Terminate;
  if FServer <> nil then
    try
      FServer.Active := False;
    except
      { Stopping a server that never started is not an error worth having. }
    end;
end;

destructor TTestServer.Destroy;
begin
  Stop;
  inherited Destroy;
end;

procedure TTestServer.Execute;
begin
  try
    FServer.Active := True;
  except
    { The port was taken, or the socket would not listen.  The tests that
      need it say so by failing to fetch, which is the honest answer. }
  end;
end;

procedure TTestServer.Request(Sender: TObject;
  var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
begin
  { Sent as a stream rather than as Content.  A PNG's own signature carries
    a carriage return and a newline, and handing binary to a text property is
    how a picture arrives with its signature rewritten -- which is what made
    the first version of these tests report a picture that could not be
    drawn. }
  if (ARequest.URI = '/one.png') or (ARequest.URI = '/two.png') or
     (Pos('/many/', ARequest.URI) = 1) then
  begin
    AResponse.ContentType := 'image/png';
    AResponse.ContentStream := TStringStream.Create(PngBytes);
    AResponse.FreeContentStream := True;
    AResponse.ContentLength := AResponse.ContentStream.Size;
  end
  else if ARequest.URI = '/lying.png' then
  begin
    { Served as a picture and not one, which is the web all over. }
    AResponse.ContentType := 'image/png';
    AResponse.Content := 'this is not a picture at all';
  end
  else
  begin
    AResponse.Code := 404;
    AResponse.Content := 'no';
  end;
  AResponse.SendResponse;
end;

{ ---- the tests ---- }

procedure TTestNBFetch.SetUp;
begin
  inherited SetUp;
  FArrived := 0;
  FLastURL := '';
  LedNBImages.Clear;
  LedPrefs.SetBool(LedPrefNotebookImages, True);
  { One server for the whole unit, started on first use.  Started and
    stopped per test it was not: the accept loop does not always come back
    when the socket closes, and eleven of those in a row hung the run. }
  if GServer = nil then GServer := TTestServer.Create(18642);
  FServer := GServer;
end;

procedure TTestNBFetch.TearDown;
begin
  FServer := nil;      { the unit owns it }
  inherited TearDown;
end;

procedure TTestNBFetch.Drain;
var
  URL: string;
begin
  while LedNBImages.TakeArrived(URL) do
  begin
    Inc(FArrived);
    FLastURL := URL;
  end;
end;

function TTestNBFetch.Base: string;
begin
  Result := Format('http://127.0.0.1:%d', [FServer.Port]);
end;

function TTestNBFetch.WaitFor(const AURL: string; ASeconds: Integer): Boolean;
var
  Deadline: TDateTime;
  Bytes: string;
begin
  Deadline := Now + ASeconds / 86400.0;
  repeat
    Sleep(20);
    Drain;
    Result := LedNBImages.Lookup(AURL, Bytes);
    if Result then Exit;
    if LedNBImages.Failure(AURL) <> '' then Exit(False);
  until Now > Deadline;
  Result := False;
end;

procedure TTestNBFetch.APngIsRecognisedByItsBytes;
begin
  AssertEquals('png', LedNBSniffImage(PngBytes));
  AssertEquals('jpg', LedNBSniffImage(#$FF#$D8#$FF#$E0 + 'JFIF and the rest'));
  AssertEquals('gif', LedNBSniffImage('GIF89a and the rest of it'));
  AssertEquals('bmp', LedNBSniffImage('BM' + StringOfChar(#0, 20)));
end;

procedure TTestNBFetch.AWebpIsNotSomethingThisCanDraw;
begin
  { Fetched happily and useless: the LCL draws no webp, and notebooks are
    full of them.  Better to say so than to draw half a picture. }
  AssertEquals('', LedNBSniffImage('RIFF' + #4#0#0#0 + 'WEBPVP8 '));
end;

procedure TTestNBFetch.RubbishIsNotAPicture;
begin
  AssertEquals('', LedNBSniffImage('<html><body>404</body></html>'));
  AssertEquals('', LedNBSniffImage(''));
  AssertEquals('', LedNBSniffImage('short'));
end;

{ ---- what the page is given ---- }

type
  { Stands in for the pane, which is what decides whether a picture is in
    hand; the renderer has no opinion about connections. }
  TSaysYes = class
  public
    Asked: string;
    Answer: Boolean;
    Why: string;
    function Have(const AURL: string; out AWhy: string): Boolean;
  end;

function TSaysYes.Have(const AURL: string; out AWhy: string): Boolean;
begin
  Asked := Asked + AURL + '|';
  AWhy := Why;
  Result := Answer;
end;

procedure TTestNBFetch.APictureAlreadyHereIsLeftInThePage;
var
  Says: TSaysYes;
  Page: string;
begin
  Says := TSaysYes.Create;
  try
    Says.Answer := True;
    Page := LedNBHideRemoteImages(
      '<p><img src="http://example.com/a.png"></p>', @Says.Have);
    AssertTrue('the tag stays for the renderer to ask about: ' + Page,
      Pos('<img src="http://example.com/a.png">', Page) > 0);
    AssertEquals('and the page was asked about that picture',
      'http://example.com/a.png|', Says.Asked);
  finally
    Says.Free;
  end;
end;

procedure TTestNBFetch.APictureThatIsNotSaysWhyInItsPlace;
var
  Says: TSaysYes;
  Page: string;
begin
  Says := TSaysYes.Create;
  try
    Says.Answer := False;
    Says.Why := 'fetching';
    Page := LedNBHideRemoteImages(
      '<p><img src="https://img.example.com/cat.png"></p>', @Says.Have);
    AssertTrue('the tag is gone', Pos('<img', Page) = 0);
    AssertTrue('the host is named: ' + Page,
      Pos('img.example.com', Page) > 0);
    AssertTrue('and so is what became of it', Pos('fetching', Page) > 0);
  finally
    Says.Free;
  end;
end;

procedure TTestNBFetch.WithNoAnswerAtAllEveryRemotePictureIsReplaced;
var
  Page: string;
begin
  { A caller that does not fetch -- the plain markdown preview -- passes
    nothing and gets the old behaviour. }
  Page := LedNBHideRemoteImages('<img src="https://a.example/1.png">', nil);
  AssertTrue('replaced', Pos('<img', Page) = 0);
  AssertTrue('and named', Pos('a.example', Page) > 0);
  { What is in the file is never touched, whoever is asked. }
  Page := LedNBHideRemoteImages('<img src="data:image/png;base64,AAAA">', nil);
  AssertTrue('a data URI is left alone', Pos('<img', Page) > 0);
end;

{ ---- fetching ---- }

procedure TTestNBFetch.APictureIsFetchedAndKept;
var
  URL, Bytes: string;
begin
  URL := Base + '/one.png';
  AssertFalse('nothing is here to start with', LedNBImages.Want(URL));
  AssertTrue('it arrives: ' + LedNBImages.Failure(URL), WaitFor(URL, 20));
  AssertTrue('and is kept', LedNBImages.Lookup(URL, Bytes));
  AssertEquals('byte for byte what the server sent',
    Length(PngBytes), Length(Bytes));
  AssertEquals('and it is a png', 'png', LedNBSniffImage(Bytes));
  AssertTrue('the page it belongs to can find out', FArrived > 0);
  AssertEquals('by name', URL, FLastURL);
end;

procedure TTestNBFetch.ASecondAskIsAnsweredFromWhatWasKept;
var
  URL: string;
  Before: Integer;
begin
  URL := Base + '/two.png';
  LedNBImages.Want(URL);
  AssertTrue('it arrives', WaitFor(URL, 20));
  Before := FArrived;

  { The pane lays a page out again on every scroll, so asking twice must not
    fetch twice. }
  AssertTrue('the second ask is answered at once', LedNBImages.Want(URL));
  Sleep(50);
  Drain;
  AssertEquals('and nothing was fetched for it', Before, FArrived);
end;

procedure TTestNBFetch.ALinkThatIsNotThereFailsAndStaysFailed;
var
  URL, Bytes: string;
  Before: Integer;
begin
  URL := Base + '/missing.png';
  LedNBImages.Want(URL);
  AssertFalse('it does not arrive', WaitFor(URL, 20));
  AssertFalse('there is nothing to draw', LedNBImages.Lookup(URL, Bytes));
  AssertTrue('and the reason is kept: ' + LedNBImages.Failure(URL),
    LedNBImages.Failure(URL) <> '');

  { A dead link on a page that is laid out on every scroll would otherwise be
    asked for for ever. }
  Before := FArrived;
  LedNBImages.Want(URL);
  Sleep(50);
  Drain;
  AssertEquals('asking again fetches nothing', Before, FArrived);
end;

procedure TTestNBFetch.SomethingThatIsNotAPictureIsRefusedAfterFetching;
var
  URL, Bytes: string;
begin
  { Served as image/png and plainly not one.  The bytes decide, not the
    header, because the header is somebody else's claim. }
  URL := Base + '/lying.png';
  LedNBImages.Want(URL);
  AssertFalse('it is not offered as a picture', WaitFor(URL, 20));
  AssertFalse('and there is nothing to draw', LedNBImages.Lookup(URL, Bytes));
  AssertTrue('the reason says what was wrong with it: ' +
    LedNBImages.Failure(URL),
    Pos('picture', LedNBImages.Failure(URL)) > 0);
end;

{ A page of a notebook names a dozen pictures and asks for them all in the
  same layout, which is how this went wrong: a thread each, all starting at
  once, and the TLS library cannot be brought up from several threads at the
  same time.  Measured over https, seven of ten came back "Could not
  initialize OpenSSL library" -- and a failure is remembered, so those seven
  were never asked for again.

  The loopback server here speaks plain HTTP and so cannot reproduce that
  failure; what it can check is the property that prevents it, which is that
  there is one fetching thread however many pictures are asked for, and that
  every one of them still arrives. }
procedure TTestNBFetch.APageOfPicturesIsFetchedOneAtATime;
const
  Count = 12;
var
  i, Most, Waited: Integer;
  URLs: array[0..Count - 1] of string;
  Bytes: string;
begin
  for i := 0 to Count - 1 do
  begin
    URLs[i] := Base + '/many/' + IntToStr(i) + '.png';
    AssertFalse('nothing is here yet', LedNBImages.Want(URLs[i]));
  end;
  AssertEquals('all of them are waiting', Count, LedNBImages.Pending);

  Most := 0;
  Waited := 0;
  while (LedNBImages.Pending > 0) and (Waited < 400) do
  begin
    if LedNBImages.Workers > Most then Most := LedNBImages.Workers;
    Drain;
    Sleep(25);
    Inc(Waited);
  end;
  Drain;

  AssertEquals('one thread fetched the lot', 1, Most);
  for i := 0 to Count - 1 do
    AssertTrue('picture ' + IntToStr(i) + ' arrived: ' +
      LedNBImages.Failure(URLs[i]), LedNBImages.Lookup(URLs[i], Bytes));
  AssertEquals('and the thread was let go at the end', 0, LedNBImages.Workers);
end;

{ ---- what the line in a picture's place says ---- }

procedure TTestNBFetch.AWebpSaysWhatItIs;
begin
  { WebP and SVG are both common in notebooks and the LCL draws neither, so
    the reader is told which it was rather than "not a picture", which reads
    like the fetch failed. }
  AssertTrue('a webp is named: ' + LedNBWhatItIs('RIFF' + #0#0#0#0 + 'WEBPVP8 '),
    Pos('WebP', LedNBWhatItIs('RIFF' + #0#0#0#0 + 'WEBPVP8 ')) > 0);
  AssertTrue('and an svg',
    Pos('SVG', LedNBWhatItIs('<?xml version="1.0"?><svg width="1"></svg>')) > 0);
end;

procedure TTestNBFetch.AWebPageInsteadOfAPictureSaysSo;
begin
  { What a server that refuses the request sends in the picture's place. }
  AssertTrue('an error page is named as one',
    Pos('web page', LedNBWhatItIs('<!DOCTYPE html><html><body>no</body>')) > 0);
  AssertEquals('and rubbish is not named at all', '',
    LedNBWhatItIs('just some bytes'));
end;

procedure TTestNBFetch.NothingIsFetchedWhenTheReaderHasSaidNot;
var
  URL, Bytes: string;
begin
  LedPrefs.SetBool(LedPrefNotebookImages, False);
  try
    AssertFalse('fetching is off', LedNBImages.Enabled);
    URL := Base + '/one.png';
    AssertFalse('so nothing is here', LedNBImages.Want(URL));
    Sleep(200);
    Drain;
    AssertFalse('and nothing was fetched', LedNBImages.Lookup(URL, Bytes));
    AssertEquals('nothing arrived at all', 0, FArrived);
  finally
    LedPrefs.SetBool(LedPrefNotebookImages, True);
  end;
end;

initialization
  RegisterTest(TTestNBFetch);

finalization
  { Best effort.  The socket is closed so nothing is left listening; whether
    the accept loop notices before the process ends does not matter, because
    the process is ending. }
  if GServer <> nil then GServer.Stop;

end.
