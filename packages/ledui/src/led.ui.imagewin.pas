{ LED - a lightweight editor.  A picture, in a window of its own.

  Double-clicking a .png in the file list used to open it the way a text
  editor opens anything it cannot read: as bytes, in the structure view,
  which answers a question nobody asked.  A picture file is not a document
  to edit here -- there is nothing in this program that edits one -- so it
  is shown.

  Which pictures are "pictures" is asked of the LCL rather than listed: a
  build with more image units linked in reads more formats, and a list
  written here would be wrong on exactly those builds.  TPicture keeps the
  register of formats and answers both questions -- is this one of mine, and
  what filter should an Open dialog show -- so it is the one asked.

  The window is modeless and there may be several: comparing two figures
  saved an hour apart is the obvious thing to want, and a modal viewer makes
  it impossible.  Closing one frees it; closing the program frees the rest.

  What it does with the picture is fit it: scaled down to the window with
  its proportions kept, never scaled up past its own size, and redone on
  every resize.  A picture smaller than the window sits in the middle of it
  at its own size, which is what makes a 16x16 icon readable rather than a
  blurred rectangle four hundred pixels wide. }
unit Led.UI.ImageWin;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, StdCtrls, Math,
  Led.UI.Dpi;

type
  TLedImageWindow = class(TForm)
  private
    FImage: TImage;
    FStatus: TLabel;
    FFileName: string;
    FNatural: TPoint;               // the picture's own size
    { The picture as it was read.  Kept apart from the one on screen,
      because what is on screen is a scaled copy and scaling a copy of a
      copy is how a picture turns to mush after three resizes. }
    FOriginal: TPicture;
    FShownAt: TPoint;               // the size the copy was drawn at
    procedure Fit;
  protected
    procedure Resize; override;
    procedure DoClose(var ACloseAction: TCloseAction); override;
  public
    constructor CreateNew(AOwner: TComponent; Dummy: Integer = 0); override;
    destructor Destroy; override;

    { Shows AFileName, or answers why it could not.  True means a window is
      up and the caller has nothing left to do with the file. }
    function Show(const AFileName: string; out AWhy: string): Boolean;

    { For the checks: what is on screen, and how big the picture is. }
    property FileName: string read FFileName;
    property Natural: TPoint read FNatural;
    property Picture: TImage read FImage;
  end;

{ Whether AFileName names a picture this build can draw.  Asked of the
  LCL's register of graphic classes, so it follows what is linked in. }
function LedIsPictureFile(const AFileName: string): Boolean;

{ Opens AFileName in a window of its own.  False, with a reason, when the
  file is not a picture or will not decode -- the caller then falls back to
  whatever it would have done with it. }
function LedShowPicture(const AFileName: string; out AWhy: string): Boolean;

implementation

function LedIsPictureFile(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := ExtractFileExt(AFileName);
  if (Length(Ext) < 2) or (Ext[1] <> '.') then
    Exit(False);
  { Delete the dot: the register is keyed on the extension without it. }
  Delete(Ext, 1, 1);
  Result := TPicture.FindGraphicClassWithFileExt(Ext, False) <> nil;
end;

function LedShowPicture(const AFileName: string; out AWhy: string): Boolean;
var
  Win: TLedImageWindow;
begin
  AWhy := '';
  Result := False;
  if not LedIsPictureFile(AFileName) then
  begin
    AWhy := 'not a picture this build can read';
    Exit;
  end;
  Win := TLedImageWindow.CreateNew(Application);
  Result := Win.Show(AFileName, AWhy);
  if not Result then
    Win.Free;
end;

constructor TLedImageWindow.CreateNew(AOwner: TComponent; Dummy: Integer);
begin
  inherited CreateNew(AOwner, Dummy);
  Width := LedScale96(640);
  Height := LedScale96(480);
  Position := poScreenCenter;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.BorderSpacing.Around := LedScale96(4);

  FImage := TImage.Create(Self);
  FImage.Parent := Self;
  FImage.Align := alClient;
  { Centre and do not stretch: the scaling is done once, into the bitmap
    that is shown, rather than by the painter on every expose -- Stretch
    with a large picture repaints the whole thing through the LCL's
    smoothing on every move of the window over it. }
  FImage.Center := True;
  FImage.Stretch := False;
  FImage.Proportional := False;

  FOriginal := TPicture.Create;
end;

destructor TLedImageWindow.Destroy;
begin
  FOriginal.Free;
  inherited Destroy;
end;

procedure TLedImageWindow.DoClose(var ACloseAction: TCloseAction);
begin
  inherited DoClose(ACloseAction);
  { Modeless and several at a time, so a closed one goes rather than
    staying hidden in the owner's list for the rest of the session. }
  ACloseAction := caFree;
end;

function TLedImageWindow.Show(const AFileName: string;
  out AWhy: string): Boolean;
begin
  AWhy := '';
  Result := False;
  FFileName := AFileName;

  try
    FOriginal.LoadFromFile(AFileName);
  except
    on E: Exception do
    begin
      AWhy := E.Message;
      Exit;
    end;
  end;
  FNatural := Point(FOriginal.Width, FOriginal.Height);
  if (FNatural.X <= 0) or (FNatural.Y <= 0) then
  begin
    AWhy := 'the picture has no size';
    Exit;
  end;

  Caption := ExtractFileName(AFileName);
  FStatus.Caption := Format('%s  -  %d x %d',
    [AFileName, FNatural.X, FNatural.Y]);

  { Opened at the picture's size where that fits on the screen, so a
    screenshot opens at one pixel to one pixel and a photograph opens as
    large as the desktop allows. }
  ClientWidth := Max(LedScale96(240),
    Min(FNatural.X, Screen.WorkAreaWidth - LedScale96(80)));
  ClientHeight := Max(LedScale96(160),
    Min(FNatural.Y + FStatus.Height, Screen.WorkAreaHeight - LedScale96(80)));

  Fit;
  inherited Show;
  Result := True;
end;

procedure TLedImageWindow.Resize;
begin
  inherited Resize;
  Fit;
end;

{ Scales the picture into the room there is, keeping its proportions and
  never making it bigger than it is.  A drawn copy rather than the control's
  own Stretch so that the smoothing is paid for once per resize. }
procedure TLedImageWindow.Fit;
var
  Room: TPoint;
  Scale: Double;
  Shown: TBitmap;
  W, H: Integer;
begin
  if (FImage = nil) or (FOriginal.Graphic = nil) then
    Exit;
  if (FNatural.X <= 0) or (FNatural.Y <= 0) then
    Exit;

  Room := Point(FImage.Width, FImage.Height);
  if (Room.X <= 0) or (Room.Y <= 0) then
    Exit;

  Scale := Min(Room.X / FNatural.X, Room.Y / FNatural.Y);
  if Scale >= 1 then
  begin
    { It fits as it is: the original goes up, nothing is resampled, and
      Center puts it in the middle.  That is the case a 16x16 icon is in,
      and a blurred rectangle four hundred pixels wide is not a better
      answer than a small sharp one. }
    W := FNatural.X;
    H := FNatural.Y;
    if (FShownAt.X = W) and (FShownAt.Y = H) then
      Exit;
    FImage.Picture.Assign(FOriginal);
    FShownAt := Point(W, H);
    Exit;
  end;

  W := Max(1, Round(FNatural.X * Scale));
  H := Max(1, Round(FNatural.Y * Scale));
  if (FShownAt.X = W) and (FShownAt.Y = H) then
    Exit;

  Shown := TBitmap.Create;
  try
    Shown.SetSize(W, H);
    Shown.Canvas.AntialiasingMode := amOn;
    Shown.Canvas.StretchDraw(Rect(0, 0, W, H), FOriginal.Graphic);
    FImage.Picture.Assign(Shown);
    FShownAt := Point(W, H);
  finally
    Shown.Free;
  end;
end;

end.
