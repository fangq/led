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
  Classes, SysUtils, syncobjs, fphttpclient, opensslsockets,
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
    FBusy: TStringList;        // the fetches in flight
    FNews: TStringList;        // arrived, and not yet told to anybody
    function Entry(const AURL: string): TObject;
    procedure Arrived(const AURL, ABytes, AWhy: string);
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
    { How many fetches are in flight, so a caller can stop asking. }
    function Pending: Integer;
  end;

{ The session's own cache. }
function LedNBImages: TLedNBImages;

{ What a picture is, from its first bytes rather than from the name it was
  served under: 'png', 'jpg', 'gif', 'bmp', or '' for something the LCL
  cannot draw.  Servers lie about content types and people name a JPEG .png,
  and the bytes do not. }
function LedNBSniffImage(const ABytes: string): string;

implementation

type
  { What came back for one URL: the bytes, or why there are none. }
  TLedNBImage = class
  public
    Bytes: string;
    Why: string;
  end;

  { One fetch.  It touches nothing but its own copy of the URL until it is
    finished, and hands the result over through the cache's own lock. }
  TLedNBFetch = class(TThread)
  private
    FURL: string;
    FBytes: string;
    FWhy: string;
    FOwner: TLedNBImages;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TLedNBImages; const AURL: string);
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
  FNews := TStringList.Create;
end;

destructor TLedNBImages.Destroy;
begin
  FLock.Free;
  FDone.Free;
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
  Start: Boolean;
begin
  Result := Lookup(AURL, Bytes);
  if Result then Exit;
  if not Enabled then Exit;

  FLock.Acquire;
  try
    { Not twice, and not again after it failed: a page that is laid out on
      every scroll would otherwise ask for the same missing picture for ever. }
    Start := (FBusy.IndexOf(AURL) < 0) and (Entry(AURL) = nil);
    if Start then FBusy.Add(AURL);
  finally
    FLock.Release;
  end;
  if Start then TLedNBFetch.Create(Self, AURL);
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
    Result := FBusy.Count;
  finally
    FLock.Release;
  end;
end;

{ ---- one fetch ---- }

constructor TLedNBFetch.Create(AOwner: TLedNBImages; const AURL: string);
begin
  FOwner := AOwner;
  FURL := AURL;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TLedNBFetch.Execute;
var
  Client: TFPHTTPClient;
  Stream: TMemoryStream;
  Kind: string;
begin
  FBytes := '';
  FWhy := '';
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
      Client.Get(FURL, Stream);

      if Stream.Size > LedNBMaxImageBytes then
        FWhy := 'too large'
      else
      begin
        SetLength(FBytes, Stream.Size);
        if Stream.Size > 0 then
          Move(Stream.Memory^, FBytes[1], Stream.Size);
        Kind := LedNBSniffImage(FBytes);
        if Kind = '' then
        begin
          { Fetched and useless: webp and svg both turn up in notebooks and
            neither is something the LCL can draw. }
          FBytes := '';
          FWhy := 'not a picture this can draw';
        end;
      end;
    except
      on E: Exception do
      begin
        FBytes := '';
        FWhy := E.Message;
      end;
    end;
  finally
    Stream.Free;
    Client.Free;
  end;
  { Handed over here rather than through Synchronize: the cache takes its own
    lock, and nothing on the other side of it touches a control. }
  FOwner.Arrived(FURL, FBytes, FWhy);
end;

finalization
  GImages.Free;

end.
