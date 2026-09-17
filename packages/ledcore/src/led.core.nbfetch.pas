// led - a lightweight editor.  Pictures a notebook points at on the web.
//
// Notebooks are full of them: a diagram on somebody's server, a meme in a
// lecture note, a badge at the top of a README cell.  Jupyter and Colab show
// them, and a preview that does not is a preview with holes in it.
//
// Fetched on a thread, never on the one drawing the page.  The renderer asks
// for a picture in the middle of laying a cell out, and answering that by
// opening a socket would stop the editor for as long as somebody else's
// server felt like taking.  So the page is laid out with what is already
// here, the fetch happens behind it, and the cell is drawn again when the
// bytes arrive.
//
// One thread, with a queue, and not one thread per picture.  A page of a
// teaching notebook names a dozen pictures and the first version started a
// dozen fetches at once, which failed: the TLS library is initialised on
// first use and initialising it from several threads at the same time does
// not work.  Measured on ten pictures over https, seven came back "Could
// not initialize OpenSSL library" and the three that were left were the
// ones that happened to start after it had finished.  Worse, a failure is
// remembered for the session, so those seven were never asked for again --
// a notebook of missing pictures from one bad moment at the start.
//
// With one thread the library is loaded once, before the first fetch, and
// every picture arrives.  It is also kinder to the server: a dozen
// simultaneous requests from one reader looks like something it should
// refuse.
//
// Everything fetched is kept for the life of the session, because the pane
// rebuilds cells as the reader scrolls and a cache is the difference between
// fetching a picture once and fetching it on every wheel notch.
//
// A word about what this costs the reader, since it is their connection and
// their privacy: nothing is fetched until a notebook that names a picture is
// shown in the pane, nothing is fetched twice, and the whole thing is off
// with one preference.  A reader who would rather not tell a stranger's
// server that they are reading a file can say so.

unit Led.Core.NBFetch;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, fphttpclient, opensslsockets, openssl,
  Led.Core.Prefs;

const
  { On by default: a notebook that names a picture means to show one, and a
    reader looking at a preview has asked to see the page.  Off is one
    setting away. }
  LedPrefNotebookImages = 'Notebook/fetch_images';
  { Big enough for any diagram, small enough that a file named .png which is
    really a video does not eat the session. }
  LedNBMaxImageBytes = 16 * 1024 * 1024;

type
  { Every picture the session has fetched, and the ones it is fetching. }
  TLedNBImages = class
  private
    FLock: TCriticalSection;
    { Every URL that has been fetched, with what came back hanging off it.

      A list of URLs with an object each, rather than a list of name=value
      lines: a picture is binary and carries newlines, equals signs and NULs,
      and putting one in the value half of a name=value list means it can
      never be found again.  Which is exactly what happened -- the bytes
      arrived, went in, and Lookup said no, because IndexOf was comparing a
      URL against a whole 'url=<420 kB of PNG>' entry. }
    FDone: TStringList;
    FWant: TStringList;        // asked for, not started
    FBusy: TStringList;        // the one being fetched
    FNews: TStringList;        // arrived, and not yet told to anybody
    FWorker: TThread;          // nil when there is nothing to fetch
    FRunning: Integer;         // the threads that exist, which is 0 or 1
    FSSLTried: Boolean;        // the TLS library has been loaded, or tried
    FSSLWhy: string;           // and why it could not be, if it could not
    function Entry(const AURL: string): TObject;
    procedure Arrived(const AURL, ABytes, AWhy: string);
    { The next thing to fetch, or '' when the queue is empty -- in which case
      the worker is forgotten and the thread ends.

      One step under one lock, deliberately: forgetting the worker and
      finding the queue empty have to be the same instant, or a picture asked
      for in between would be queued with nobody left to fetch it. }
    function TakeWanted: string;
    { Loads the TLS library, once.  Called with the lock held, from the one
      fetching thread, which is what makes "once" true. }
    function SSLReady(out AWhy: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    { The bytes of a picture already fetched.  False when it has not arrived,
      whether because nobody has asked for it or because it failed. }
    function Lookup(const AURL: string; out ABytes: string): Boolean;
    { Why a picture is not being shown, for the line that stands in for it.
      Empty when it simply has not arrived yet. }
    function Failure(const AURL: string): string;
    { Asks for a picture.  Returns True when it is already here -- the caller
      can draw it now -- and False when it is not, having started a fetch if
      fetching is on and one is not already running. }
    function Want(const AURL: string): Boolean;
    { Whether fetching is on at all. }
    function Enabled: Boolean;
    procedure Clear;

    { The next picture to have arrived since this was last asked, or False
      when there is none.  A queue drained by whoever is drawing rather than
      an event raised from the fetching thread: an event would arrive on that
      thread, and a control may not be touched from there.  Synchronize would
      answer that too, but only where something is calling CheckSynchronize
      -- which is a fact about the caller, not about this. }
    function TakeArrived(out AURL: string): Boolean;
    { How many fetches are waiting or in flight, so a caller can stop asking. }
    function Pending: Integer;
    { How many fetching threads exist: one while there is anything to fetch
      and none otherwise.  Published because "one at a time" is the whole of
      what keeps the TLS library working, and a check can watch it.

      A count of the threads themselves rather than of the field that gates
      them -- the first version returned "one" whenever the field was set,
      which is what it says whether there is one thread or twenty, and the
      mutation that started a thread per picture passed it. }
    function Workers: Integer;
  end;

{ The session's own cache. }
function LedNBImages: TLedNBImages;

{ What a picture is, from its first bytes rather than from the name it was
  served under: 'png', 'jpg', 'gif', 'bmp', or '' for something the LCL
  cannot draw.  Servers lie about content types and people name a JPEG .png,
  and the bytes do not. }
function LedNBSniffImage(const ABytes: string): string;

{ What something that is not a drawable picture actually is, in words, for
  the line that stands in for it: a WebP or an SVG -- both common in
  notebooks and neither drawable by the LCL -- or a web page, which is what
  a server that refuses the request sends instead of the picture.  '' when
  the bytes say nothing recognisable. }
function LedNBWhatItIs(const ABytes: string): string;

implementation

type
  { What came back for one URL: the bytes, or why there are none. }
  TLedNBImage = class
  public
    Bytes: string;
    Why: string;
  end;

  { The one fetching thread.  It takes the next URL from the queue, fetches
    it, hands the result over through the cache's own lock, and goes back for
    the next one; when the queue is empty it ends. }
  TLedNBFetch = class(TThread)
  private
    FOwner: TLedNBImages;
    procedure FetchOne(const AURL: string);
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TLedNBImages);
  end;

var
  GImages: TLedNBImages = nil;

function LedNBImages: TLedNBImages;
begin
  if GImages = nil then GImages := TLedNBImages.Create;
  Result := GImages;
end;

function LedNBSniffImage(const ABytes: string): string;
begin
  Result := '';
  if Length(ABytes) < 12 then Exit;
  if Copy(ABytes, 1, 8) = #$89'PNG'#13#10#26#10 then Exit('png');
  if Copy(ABytes, 1, 2) = #$FF#$D8 then Exit('jpg');
  if (Copy(ABytes, 1, 6) = 'GIF87a') or (Copy(ABytes, 1, 6) = 'GIF89a') then
    Exit('gif');
  if Copy(ABytes, 1, 2) = 'BM' then Exit('bmp');
  { WebP and SVG both turn up in notebooks and the LCL draws neither, so
    they are named rather than half-drawn. }
  if (Copy(ABytes, 1, 4) = 'RIFF') and (Copy(ABytes, 9, 4) = 'WEBP') then
    Exit('');
end;

function LedNBWhatItIs(const ABytes: string): string;
var
  Head: string;
begin
  Result := '';
  if (Copy(ABytes, 1, 4) = 'RIFF') and (Copy(ABytes, 9, 4) = 'WEBP') then
    Exit('a WebP picture, which cannot be drawn here');
  Head := LowerCase(Copy(ABytes, 1, 400));
  { An SVG may open with the XML declaration, a comment, or the tag. }
  if (Pos('<svg', Head) > 0) and (Pos('<html', Head) = 0) then
    Exit('an SVG drawing, which cannot be drawn here');
  if (Pos('<!doctype html', Head) > 0) or (Pos('<html', Head) > 0) then
    Exit('a web page, not a picture: the server sent this instead');
end;

{ ---- the cache ---- }

constructor TLedNBImages.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FDone := TStringList.Create;
  FDone.OwnsObjects := True;
  FDone.Sorted := True;
  FBusy := TStringList.Create;
  FBusy.Sorted := True;
  FWant := TStringList.Create;
  FNews := TStringList.Create;
end;

destructor TLedNBImages.Destroy;
begin
  FLock.Free;
  FDone.Free;
  FWant.Free;
  FBusy.Free;
  FNews.Free;
  inherited Destroy;
end;

function TLedNBImages.Enabled: Boolean;
begin
  Result := LedPrefs.GetBool(LedPrefNotebookImages, True);
end;

procedure TLedNBImages.Clear;
begin
  FLock.Acquire;
  try
    FDone.Clear;
    FNews.Clear;
  finally
    FLock.Release;
  end;
end;

function TLedNBImages.Entry(const AURL: string): TObject;
var
  i: Integer;
begin
  Result := nil;
  i := FDone.IndexOf(AURL);
  if i >= 0 then Result := FDone.Objects[i];
end;

function TLedNBImages.Lookup(const AURL: string; out ABytes: string): Boolean;
var
  E: TObject;
begin
  ABytes := '';
  FLock.Acquire;
  try
    E := Entry(AURL);
    Result := (E <> nil) and (TLedNBImage(E).Bytes <> '');
    if Result then ABytes := TLedNBImage(E).Bytes;
  finally
    FLock.Release;
  end;
end;

function TLedNBImages.Failure(const AURL: string): string;
var
  E: TObject;
begin
  Result := '';
  FLock.Acquire;
  try
    E := Entry(AURL);
    if E <> nil then Result := TLedNBImage(E).Why;
  finally
    FLock.Release;
  end;
end;

function TLedNBImages.Want(const AURL: string): Boolean;
var
  Bytes: string;
  Queue: Boolean;
  Fresh: TThread;
begin
  Result := Lookup(AURL, Bytes);
  if Result then Exit;
  if not Enabled then Exit;

  Fresh := nil;
  FLock.Acquire;
  try
    { Not twice, and not again after it failed: a page that is laid out on
      every scroll would otherwise ask for the same missing picture for ever. }
    Queue := (FWant.IndexOf(AURL) < 0) and (FBusy.IndexOf(AURL) < 0) and
             (Entry(AURL) = nil);
    if Queue then FWant.Add(AURL);
    { One thread, made when there is something for it and forgotten when
      there is not.  Decided under the same lock the thread clears it under,
      so there is never a second one. }
    if (FWant.Count > 0) and (FWorker = nil) then
    begin
      Fresh := TLedNBFetch.Create(Self);
      FWorker := Fresh;
      Inc(FRunning);
    end;
  finally
    FLock.Release;
  end;
  { Started outside the lock, and through the local rather than the field:
    the thread frees itself when it ends, and by then the field may be nil. }
  if Fresh <> nil then Fresh.Start;
end;

function TLedNBImages.TakeWanted: string;
begin
  Result := '';
  FLock.Acquire;
  try
    if FWant.Count = 0 then
    begin
      { Nothing left: the thread is about to end, so the next Want makes a
        new one. }
      FWorker := nil;
      Dec(FRunning);
      Exit;
    end;
    Result := FWant[0];
    FWant.Delete(0);
    FBusy.Add(Result);
  finally
    FLock.Release;
  end;
end;

function TLedNBImages.SSLReady(out AWhy: string): Boolean;
begin
  AWhy := '';
  if not FSSLTried then
  begin
    FSSLTried := True;
    { Loaded here, on the one fetching thread, before the first connection.
      Left to the socket layer it happens on whichever thread gets there
      first, and from more than one at once it fails -- see the unit
      comment. }
    if not IsSSLloaded then
      if not InitSSLInterface then
        FSSLWhy := 'no TLS library on this machine';
  end;
  AWhy := FSSLWhy;
  Result := AWhy = '';
end;

{ A fetch has finished.  Called on the fetching thread, so it touches nothing
  but the lists under the lock: the bytes are kept whatever they are -- an
  empty string is a failure, and remembering that is what stops the same dead
  link being asked for again and again -- and the URL goes on the queue for
  whoever is drawing to pick up. }
procedure TLedNBImages.Arrived(const AURL, ABytes, AWhy: string);
var
  i: Integer;
  E: TLedNBImage;
begin
  FLock.Acquire;
  try
    i := FBusy.IndexOf(AURL);
    if i >= 0 then FBusy.Delete(i);
    E := TLedNBImage(Entry(AURL));
    if E = nil then
    begin
      E := TLedNBImage.Create;
      FDone.AddObject(AURL, E);
    end;
    E.Bytes := ABytes;
    E.Why := AWhy;
    if ABytes <> '' then FNews.Add(AURL);
  finally
    FLock.Release;
  end;
end;

function TLedNBImages.TakeArrived(out AURL: string): Boolean;
begin
  AURL := '';
  FLock.Acquire;
  try
    Result := FNews.Count > 0;
    if Result then
    begin
      AURL := FNews[0];
      FNews.Delete(0);
    end;
  finally
    FLock.Release;
  end;
end;

function TLedNBImages.Pending: Integer;
begin
  FLock.Acquire;
  try
    Result := FWant.Count + FBusy.Count;
  finally
    FLock.Release;
  end;
end;

function TLedNBImages.Workers: Integer;
begin
  FLock.Acquire;
  try
    Result := FRunning;
  finally
    FLock.Release;
  end;
end;

{ ---- one fetch ---- }

constructor TLedNBFetch.Create(AOwner: TLedNBImages);
begin
  FOwner := AOwner;
  FreeOnTerminate := True;
  { Suspended, and started by the caller after the lock is released: the
    thread's first act is to take the lock itself. }
  inherited Create(True);
end;

{ The queue, until it is empty.  The thread ends then, and the next picture
  asked for makes a new one. }
procedure TLedNBFetch.Execute;
var
  URL: string;
begin
  repeat
    URL := FOwner.TakeWanted;
    if URL = '' then Break;
    FetchOne(URL);
  until Terminated;
end;

procedure TLedNBFetch.FetchOne(const AURL: string);
var
  Client: TFPHTTPClient;
  Stream: TMemoryStream;
  Kind, Why, Bytes: string;
begin
  { No connection is attempted at all without the library to make it with,
    and the reason is the one the reader is shown. }
  if not FOwner.SSLReady(Why) then
    if Pos('https:', LowerCase(AURL)) = 1 then
    begin
      FOwner.Arrived(AURL, '', Why);
      Exit;
    end;

  Bytes := '';
  Why := '';
  Client := TFPHTTPClient.Create(nil);
  Stream := TMemoryStream.Create;
  try
    try
      { Short, because nothing waits on this but the picture itself: a server
        that will not answer in a few seconds is a picture the reader does
        without. }
      Client.ConnectTimeout := 8000;
      Client.IOTimeout := 8000;
      Client.AllowRedirect := True;
      { Named honestly.  A server that turns LED away may do so knowingly. }
      Client.AddHeader('User-Agent', 'led notebook preview');
      Client.Get(AURL, Stream);

      if Stream.Size > LedNBMaxImageBytes then
        Why := 'too large'
      else
      begin
        SetLength(Bytes, Stream.Size);
        if Stream.Size > 0 then
          Move(Stream.Memory^, Bytes[1], Stream.Size);
        Kind := LedNBSniffImage(Bytes);
        if Kind = '' then
        begin
          { Fetched and useless: webp and svg both turn up in notebooks and
            neither is something the LCL can draw.  Named where it can be
            named, because "not a picture" leaves the reader wondering
            whether it was the fetch or the format that failed. }
          Why := LedNBWhatItIs(Bytes);
          if Why = '' then Why := 'not a picture this can draw';
          Bytes := '';
        end;
      end;
    except
      on E: Exception do
      begin
        Bytes := '';
        Why := E.Message;
      end;
    end;
  finally
    Stream.Free;
    Client.Free;
  end;
  { Handed over here rather than through Synchronize: the cache takes its own
    lock, and nothing on the other side of it touches a control. }
  FOwner.Arrived(AURL, Bytes, Why);
end;

finalization
  GImages.Free;

end.
