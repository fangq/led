{ LED - a lightweight editor.  The pictures a rendered document points at.

  Two panes render HTML -- the notebook's cells and the Markdown and wiki
  preview -- and the renderer asks both of them the same three questions
  about every picture on the page: is it in hand, how big is it, and give it
  to me.  Each had its own answer, which is to say the same forty lines
  twice, and every fix to them was made twice as well: resolving a file://
  path, converting an SVG, asking the kept picture for its size instead of
  decoding it again.  One of those fixes landed in one pane and not the
  other for a whole afternoon.

  So the answers live here, once.  What is left in each pane is the part that
  really does differ: what to do when a picture that was fetched arrives,
  which is "redraw the cells that name it" for one and "lay the page out
  again" for the other.

  Where a picture comes from, in the order they are tried:

    the web       fetched on a thread and kept for the session, so what
                  this does is look in the cache; see Led.Core.NBFetch
    the document  a data: URI or an attachment, which only the caller can
                  reach -- a notebook knows its cells and a Markdown file
                  has no such thing -- so that is a callback
    the disk      beside the document, an absolute path, or a file:// URL,
                  which the renderer does not resolve itself

  An SVG or a WebP from any of those is converted on the way through, and a
  picture too wide for the page it is on is scaled once, here, rather than
  by the renderer on every paint. }

unit Led.UI.Pictures;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics,
  Led.Core.NBImage, Led.Core.NBFetch, Led.Core.NBConvert;

type
  { A picture the document carries itself: a data: URI, or an attachment
    pasted into a notebook cell.  Only the caller can answer this -- it is
    the one that knows what kind of document it is showing. }
  TLedEmbeddedPicture = function(const AURL: string;
    out ABytes, AMime: string): Boolean of object;

  { Pictures already decoded, kept so that a page laid out again -- which is
    what scrolling a notebook does, once per cell arriving on screen -- does
    not decode them again.

    Decoding is what that used to cost: a 700 by 1034 photograph is twenty
    milliseconds of PNG, and the renderer asks for every picture again every
    time the page it is on is built.  Measured on twenty-four cells of one
    picture each, a two-hundred-notch scroll spent 190 of its 393
    milliseconds decoding pictures it had already decoded; with them kept it
    spends 2.

    What is handed out is a copy, because the renderer frees the picture it
    is given (TIpHtmlNodeIMG.UnloadImage), and a copy of a decoded bitmap is
    a memory move rather than a decode.

    Kept at the size the page draws it at, not at the size the file holds:
    the page writes a width into the tag for a picture too wide for it, so
    the scaling may as well happen once here instead of on every paint -- and
    a photograph three thousand pixels wide then costs what the pane shows
    rather than what the file has.

    Bounded by what it holds rather than by how many, because a lecture
    notebook has eighty pictures in it and their sizes are not alike: a
    budget in pixels is the same promise about memory whether they are
    thumbnails or plots.  The least recently wanted goes first. }
  TLedPictureCache = class
  private
    FKeys: TStringList;      { key -> TPicture, most recently used last }
    FBudget: Int64;          { in pixels }
    FDecodes: Integer;
    function Pixels: Int64;
    function Find(const AKey: string): TPicture;
    function Add(const AKey: string; APicture: TPicture): TPicture;
  public
    constructor Create(ABudgetPixels: Int64 = 8 * 1000 * 1000);
    destructor Destroy; override;

    { A picture for the caller to hand to the renderer: ABytes decoded, or
      the bitmap already kept for AKey, and always a fresh TPicture --
      because the renderer frees what it is given.

      AFitWidth is the width the page draws it at: anything wider is scaled
      down on the way in.

      The decoding lives here rather than in the caller so that the count
      below is a count of decodes.  It was a count of insertions at first,
      and the mutation that stopped consulting the cache at all still passed
      the check that read it. }
    function Get(const AKey, ABytes, AExt: string;
      AFitWidth: Integer): TPicture;
    { The size of the picture kept under AKey, and the picture itself so a
      caller can tell "nothing kept" from "kept and empty".  Does not count
      as wanting it: asking how big something is is not drawing it. }
    function SizeOf_(const AKey: string; out AW, AH: Integer): TPicture;
    procedure Clear;
    function Count: Integer;
    { How many pictures have actually been decoded.  For a check: "decoded
      once and drawn twice" cannot be seen from outside otherwise, and a
      timing would be a flaky way to ask it. }
    property Decodes: Integer read FDecodes;
  end;

  { The three answers the renderer wants, for one document. }
  TLedPictureSource = class
  private
    FCache: TLedPictureCache;
    FOwnCache: Boolean;
    FBaseDir: string;
    FFitWidth: Integer;
    FOnEmbedded: TLedEmbeddedPicture;
    { The bytes behind a reference, and the extension they should be read as.
      AHeaderOnly asks for as little as will say how big the picture is: a
      picture on disk may be enormous and a size is the first few bytes. }
    function Bytes(const AURL: string; AHeaderOnly: Boolean;
      out ABytes, AExt: string): Boolean;
  public
    { Passed a cache, several sources share it -- which is what the cells of
      a notebook do, so that scrolling a cell out of view does not throw away
      what scrolling it back needs.  Passed none, it keeps its own. }
    constructor Create(ACache: TLedPictureCache = nil);
    destructor Destroy; override;

    { A picture to hand the renderer, or nil.  Never raises: the renderer
      asks for this in the middle of laying a page out, and an exception
      there takes the whole page with it -- which a notebook referring to a
      picture by a bare name managed on the first try. }
    function Provide(const AURL: string): TPicture;

    { Whether a picture on the web is in hand, and if not, why the page
      should say so in its place.  Asking for one starts the fetch.

      AFetching says a fetch is now running, so the caller knows to start
      looking for the answer; it has no way to be told. }
    function Have(const AURL: string; out AWhy: string;
      out AFetching: Boolean): Boolean;

    { How big the picture is, for a page that has to write a width into the
      tag before it is laid out.  From the picture's own header rather than
      by decoding it, and from the kept bitmap when there is one -- which
      skips a copy of half a megabyte of PNG per picture per page build, and
      for an SVG a converter run, which is a process. }
    function SizeOf_(const AURL: string; out AW, AH: Integer): Boolean;

    { Where a relative name resolves: the folder the document is in. }
    property BaseDir: string read FBaseDir write FBaseDir;
    { The width the page draws a picture at, or 0 for "as it comes". }
    property FitWidth: Integer read FFitWidth write FFitWidth;
    { Asked before the disk, for the pictures the document carries. }
    property OnEmbedded: TLedEmbeddedPicture
      read FOnEmbedded write FOnEmbedded;
    property Cache: TLedPictureCache read FCache;
  end;

implementation

{ ---- pictures already decoded ---- }

constructor TLedPictureCache.Create(ABudgetPixels: Int64);
begin
  inherited Create;
  FBudget := ABudgetPixels;
  FKeys := TStringList.Create;
  FKeys.OwnsObjects := True;
end;

destructor TLedPictureCache.Destroy;
begin
  FKeys.Free;
  inherited Destroy;
end;

function TLedPictureCache.Pixels: Int64;
var
  i: Integer;
  P: TPicture;
begin
  Result := 0;
  for i := 0 to FKeys.Count - 1 do
  begin
    P := TPicture(FKeys.Objects[i]);
    if (P <> nil) and (P.Graphic <> nil) then
      Inc(Result, Int64(P.Width) * P.Height);
  end;
end;

{ The kept bitmap for a key, or nil, moved to the end of the list because it
  has just been wanted: what falls off the front is what nobody has looked at
  for longest. }
function TLedPictureCache.Find(const AKey: string): TPicture;
var
  i: Integer;
begin
  Result := nil;
  i := FKeys.IndexOf(AKey);
  if i < 0 then Exit;
  Result := TPicture(FKeys.Objects[i]);
  FKeys.Move(i, FKeys.Count - 1);
end;

{ Takes ownership of APicture and hands back what is in the cache under AKey
  afterwards -- which is APicture, unless something was already there, in
  which case APicture is freed and the one already there comes back.  Handing
  it back rather than nothing is what stops a caller holding a pointer to
  what it has just given away: the first version freed the duplicate and left
  the caller reading it. }
function TLedPictureCache.Add(const AKey: string;
  APicture: TPicture): TPicture;
var
  i: Integer;
begin
  Result := APicture;
  if APicture = nil then Exit;
  i := FKeys.IndexOf(AKey);
  if i >= 0 then
  begin
    APicture.Free;
    Exit(TPicture(FKeys.Objects[i]));
  end;
  FKeys.AddObject(AKey, APicture);
  Inc(FDecodes);
  { One is always kept, however big it is: a reader looking at a single
    enormous picture still wants it not to be decoded twice. }
  while (FKeys.Count > 1) and (Pixels > FBudget) do FKeys.Delete(0);
end;

function TLedPictureCache.Get(const AKey, ABytes, AExt: string;
  AFitWidth: Integer): TPicture;
var
  Kept, Scaled: TPicture;
  Stream: TStringStream;
  W, H: Integer;
begin
  Result := nil;
  if ABytes = '' then Exit;

  Kept := Find(AKey);
  if Kept = nil then
  begin
    Kept := TPicture.Create;
    Stream := TStringStream.Create(ABytes);
    try
      try
        Kept.LoadFromStreamWithFileExt(Stream, AExt);
      except
        FreeAndNil(Kept);
      end;
    finally
      Stream.Free;
    end;
    if Kept = nil then Exit;
    if Kept.Graphic = nil then
    begin
      Kept.Free;
      Exit;
    end;

    { Down to the width the page draws it at, if that is smaller. }
    if (AFitWidth > 0) and (Kept.Width > AFitWidth) then
    begin
      W := AFitWidth;
      H := Round(Kept.Height * (AFitWidth / Kept.Width));
      if H < 1 then H := 1;
      Scaled := TPicture.Create;
      try
        Scaled.Bitmap.SetSize(W, H);
        Scaled.Bitmap.Canvas.AntialiasingMode := amOn;
        Scaled.Bitmap.Canvas.StretchDraw(Rect(0, 0, W, H), Kept.Graphic);
        Kept.Free;
        Kept := Scaled;
      except
        { Scaling is an improvement, not a requirement: the unscaled
          picture is still a picture. }
        Scaled.Free;
      end;
    end;

    Kept := Add(AKey, Kept);
  end;

  { A copy, because the renderer frees the picture it is given -- see
    TIpHtmlNodeIMG.UnloadImage -- and a copy of a decoded bitmap is a memory
    move rather than a decode. }
  Result := TPicture.Create;
  try
    Result.Assign(Kept);
  except
    FreeAndNil(Result);
  end;
end;

function TLedPictureCache.SizeOf_(const AKey: string;
  out AW, AH: Integer): TPicture;
var
  i: Integer;
begin
  Result := nil;
  AW := 0;
  AH := 0;
  i := FKeys.IndexOf(AKey);
  if i < 0 then Exit;
  Result := TPicture(FKeys.Objects[i]);
  if (Result = nil) or (Result.Graphic = nil) then Exit(nil);
  AW := Result.Width;
  AH := Result.Height;
end;

procedure TLedPictureCache.Clear;
begin
  FKeys.Clear;
end;

function TLedPictureCache.Count: Integer;
begin
  Result := FKeys.Count;
end;

{ ---- where a picture comes from ---- }

constructor TLedPictureSource.Create(ACache: TLedPictureCache);
begin
  inherited Create;
  FOwnCache := ACache = nil;
  if FOwnCache then
    FCache := TLedPictureCache.Create
  else
    FCache := ACache;
end;

destructor TLedPictureSource.Destroy;
begin
  if FOwnCache then FCache.Free;
  inherited Destroy;
end;

function TLedPictureSource.Bytes(const AURL: string; AHeaderOnly: Boolean;
  out ABytes, AExt: string): Boolean;
var
  FN, Mime: string;
  F: TFileStream;
  Want: Integer;
begin
  Result := False;
  ABytes := '';
  AExt := '';
  if AURL = '' then Exit;

  { One from the web.  What it is comes from its own first bytes rather than
    from the name it was served under: servers lie about content types and
    people name a JPEG .png. }
  if LedNBIsRemote(AURL) then
  begin
    if not LedNBImages.Lookup(AURL, ABytes) then Exit;
    AExt := LedNBSniffImage(ABytes);
    Exit(ABytes <> '');
  end;

  { One the document carries: a data: URI, or an attachment. }
  if Assigned(FOnEmbedded) and FOnEmbedded(AURL, ABytes, Mime) then
  begin
    AExt := LedNBImageExt(Mime);
    Exit(ABytes <> '');
  end;

  { Otherwise a file: beside the document, an absolute path, or a file://
    URL -- which the renderer does not resolve itself, its provider dealing
    in paths rather than URLs. }
  FN := LedNBLocalPath(AURL, FBaseDir);
  if (FN = '') or (not FileExists(FN)) then Exit;
  try
    F := TFileStream.Create(FN, fmOpenRead or fmShareDenyNone);
    try
      if AHeaderOnly then Want := 4096 else Want := F.Size;
      if Want > F.Size then Want := F.Size;
      SetLength(ABytes, Want);
      if Want > 0 then SetLength(ABytes, F.Read(ABytes[1], Want));
    finally
      F.Free;
    end;
  except
    ABytes := '';
  end;
  AExt := LowerCase(Copy(ExtractFileExt(FN), 2, MaxInt));
  Result := ABytes <> '';
end;

function TLedPictureSource.Provide(const AURL: string): TPicture;
var
  Raw, Ext, Mime: string;
begin
  Result := nil;
  if not Bytes(AURL, False, Raw, Ext) then Exit;
  { An SVG or a WebP is turned into a PNG first, if the machine has anything
    to turn it with; see Led.Core.NBConvert. }
  if LedNBConvertKind(Raw) <> '' then
  begin
    Mime := '';
    if not LedNBMakeDrawable(Raw, Mime) then Exit;
    Ext := 'png';
  end;
  if Ext = '' then Ext := LedNBSniffImage(Raw);
  if Ext = '' then Exit;
  Result := FCache.Get(IntToStr(FFitWidth) + '|' + AURL, Raw, Ext, FFitWidth);
end;

function TLedPictureSource.Have(const AURL: string; out AWhy: string;
  out AFetching: Boolean): Boolean;
begin
  AWhy := '';
  AFetching := False;
  Result := LedNBImages.Want(AURL);
  if Result then Exit;
  AFetching := LedNBImages.Pending > 0;
  AWhy := LedNBImages.Failure(AURL);
  if AWhy <> '' then Exit;
  if LedNBImages.Enabled then AWhy := 'fetching' else AWhy := 'not fetched';
end;

function TLedPictureSource.SizeOf_(const AURL: string;
  out AW, AH: Integer): Boolean;
var
  Raw, Ext, Mime: string;
begin
  Result := False;
  AW := 0;
  AH := 0;
  if AURL = '' then Exit;

  { A picture already decoded answers for itself, and answering that way
    skips everything below.  The kept picture is the size the page draws it
    at rather than the size the file holds, and that is the right answer
    here too: the page is asking "does this need narrowing", and something
    already narrowed does not. }
  if FCache.SizeOf_(IntToStr(FFitWidth) + '|' + AURL, AW, AH) <> nil then
    Exit(True);

  if not Bytes(AURL, True, Raw, Ext) then Exit;
  { Measured after converting: an SVG says its size in its markup, in units
    this does not read. }
  if LedNBConvertKind(Raw) <> '' then
  begin
    Mime := '';
    if not LedNBMakeDrawable(Raw, Mime) then Exit;
  end;
  Result := LedNBPictureSize(Raw, AW, AH);
end;

end.
