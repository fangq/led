{ led - a light editor.  Toolbar and menu icons, drawn rather than shipped.

  medit used the desktop's stock GTK icon theme, which does not exist on
  Windows or macOS, and bundling a PNG set means artwork to license, scale
  for HiDPI and keep in step with the actions.  So the icons are drawn here
  from a handful of primitives instead: nothing to install, they follow the
  requested size exactly, and adding one is a short case branch rather than
  a trip to an image editor.

  Every icon is designed on a nominal 16x16 grid and scaled to the size the
  image list asks for, so the same code serves 16, 24 and 32 pixel toolbars. }
unit Led.UI.Icons;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, ImgList;

const
  LedWindowIconRes = 'LEDICONPNG';   { see packaging/windows/led.rc }

type
  { The names are the action ids they belong to, lower-cased, so a caller can
    ask for an icon by action name and get nil-safe behaviour when there is
    none. }
  TLedIconName = string;

{ Fills AImages with one bitmap per name in ANames, in that order, so the
  index of a name is its index in the list.  Returns the list for chaining. }
function LedBuildIconList(AImages: TImageList; const ANames: array of string;
  AColour: TColor): TImageList;

{ Index of ANAme in the list built by LedBuildIconList, or -1. }
function LedIconIndex(const AName: string): Integer;

{ Every icon this unit can draw, in the canonical order used by the image
  list the application builds at startup. }
function LedIconNames: TStringArray;

{ Puts the application's own logo on the window and the task bar entry.

  It reads the PNG copy of the artwork that packaging/windows/led.rc embeds,
  rather than the MAINICON in the same binary.  MAINICON is the same picture
  and the LCL reads it back correctly in process -- all seven sizes -- but
  what reaches the window manager from it has its colour channels striped
  and its alpha forced opaque.  A PNG assigned to Application.Icon arrives
  intact.  Does nothing if the resource is missing, because a build without
  it should start with no icon rather than not start. }
procedure LedApplyWindowIcon;

{ Draws one icon into ABitmap, which must already be sized. }
procedure LedDrawIcon(ABitmap: TBitmap; const AName: string; AColour: TColor);

{ One icon as a 16x16 bitmap with a transparent background, for the controls
  that take a Glyph rather than an image list index.  The caller owns the
  result only through the control it assigns it to -- TSpeedButton.Glyph
  copies, so the bitmap is freed here. }
function LedIconBitmap(const AName: string; AColour: TColor): TBitmap;

implementation

uses
  Forms, LCLType;

const
  { The background the icons are drawn on and then masked out.  Magenta
    because nothing in an icon is ever legitimately this colour. }
  MaskColour = TColor($00FF00FF);

  { Kept in one place so the toolbar, the menus and the tab headers all agree
    on what index means what. }
  IconNames: array[0..50] of string = (
    'new', 'open', 'save', 'saveas', 'close', 'reload', 'print', 'quit',
    'undo', 'redo', 'cut', 'copy', 'paste', 'delete', 'selectall',
    'indent', 'unindent', 'comment', 'uncomment',
    'find', 'findnext', 'findprev', 'replace', 'gotoline',
    'bookmark', 'prefs', 'shortcuts', 'stop', 'run', 'terminal',
    'browser', 'symbols', 'splith', 'splitv', 'wrap', 'linenumbers',
    'help', 'about',
    { The tab headers: a plain document, and one with unsaved changes. }
    'doc', 'docmodified',
    { File-browser navigation. }
    'back', 'forward', 'up', 'home',
    { The debugger.  Appended rather than inserted: an ImageIndex in the form
      file is an absolute position, so inserting here would silently move
      every icon after it. }
    'debug', 'stepover', 'stepinto', 'stepout', 'pause',
    'breakpoint', 'debugline'
  );

procedure LedApplyWindowIcon;
var
  Stream: TResourceStream;
  Png: TPortableNetworkGraphic;
begin
  Stream := nil;
  Png := nil;
  try
    try
      Stream := TResourceStream.Create(HInstance, LedWindowIconRes, RT_RCDATA);
      Png := TPortableNetworkGraphic.Create;
      Png.LoadFromStream(Stream);
      Application.Icon.Assign(Png);
    except
      { A missing or unreadable resource is not worth failing startup over. }
    end;
  finally
    Png.Free;
    Stream.Free;
  end;
end;

function LedIconNames: TStringArray;
var
  i: Integer;
begin
  SetLength(Result, Length(IconNames));
  for i := 0 to High(IconNames) do Result[i] := IconNames[i];
end;

function LedIconIndex(const AName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(IconNames) do
    if SameText(IconNames[i], AName) then Exit(i);
  Result := -1;
end;

type
  { A tiny drawing context that takes coordinates on the 16x16 design grid and
    puts them where they belong at the real size.  Everything below is written
    against this, so no icon has to know how big it is being drawn. }
  TPen16 = object
    C: TCanvas;
    S: Double;          // pixels per design unit
    procedure Init(ACanvas: TCanvas; ASize: Integer; AColour: TColor);
    function X(V: Double): Integer;
    procedure Line(X1, Y1, X2, Y2: Double);
    procedure Box(X1, Y1, X2, Y2: Double; AFill: Boolean = False);
    procedure Ellipse(X1, Y1, X2, Y2: Double; AFill: Boolean = False);
    procedure Poly(const APts: array of Double; AFill: Boolean = False);
    procedure Colour(AColour: TColor);
    procedure Width(AUnits: Double);
  end;

procedure TPen16.Init(ACanvas: TCanvas; ASize: Integer; AColour: TColor);
begin
  C := ACanvas;
  S := ASize / 16;
  C.Pen.Color := AColour;
  C.Pen.Width := Round(S * 1.2);
  if C.Pen.Width < 1 then C.Pen.Width := 1;
  C.Pen.EndCap := pecSquare;
  C.Brush.Color := AColour;
  C.Brush.Style := bsClear;
end;

function TPen16.X(V: Double): Integer;
begin
  Result := Round(V * S);
end;

procedure TPen16.Colour(AColour: TColor);
begin
  C.Pen.Color := AColour;
  C.Brush.Color := AColour;
end;

procedure TPen16.Width(AUnits: Double);
begin
  C.Pen.Width := Round(AUnits * S);
  if C.Pen.Width < 1 then C.Pen.Width := 1;
end;

procedure TPen16.Line(X1, Y1, X2, Y2: Double);
begin
  C.Line(X(X1), X(Y1), X(X2), X(Y2));
end;

procedure TPen16.Box(X1, Y1, X2, Y2: Double; AFill: Boolean);
begin
  if AFill then C.Brush.Style := bsSolid else C.Brush.Style := bsClear;
  C.Rectangle(X(X1), X(Y1), X(X2), X(Y2));
  C.Brush.Style := bsClear;
end;

procedure TPen16.Ellipse(X1, Y1, X2, Y2: Double; AFill: Boolean);
begin
  if AFill then C.Brush.Style := bsSolid else C.Brush.Style := bsClear;
  C.Ellipse(X(X1), X(Y1), X(X2), X(Y2));
  C.Brush.Style := bsClear;
end;

procedure TPen16.Poly(const APts: array of Double; AFill: Boolean);
var
  P: array of TPoint;
  i: Integer;
begin
  SetLength(P, Length(APts) div 2);
  for i := 0 to High(P) do
    P[i] := Point(X(APts[i * 2]), X(APts[i * 2 + 1]));
  if AFill then
  begin
    C.Brush.Style := bsSolid;
    C.Polygon(P);
    C.Brush.Style := bsClear;
  end
  else
    C.Polyline(P);
end;

{ A sheet of paper with a folded corner, the base of the file icons. }
procedure DrawPage(var P: TPen16);
begin
  P.Poly([3.5, 1.5, 9.5, 1.5, 12.5, 4.5, 12.5, 14.5, 3.5, 14.5, 3.5, 1.5]);
  P.Line(9.5, 1.5, 9.5, 4.5);
  P.Line(9.5, 4.5, 12.5, 4.5);
end;

procedure DrawMagnifier(var P: TPen16);
begin
  P.Ellipse(2, 2, 11, 11);
  P.Width(2);
  P.Line(10, 10, 14.5, 14.5);
  P.Width(1.2);
end;

procedure LedDrawIcon(ABitmap: TBitmap; const AName: string; AColour: TColor);
var
  P: TPen16;
  N: string;
  i: Integer;
begin
  P.Init(ABitmap.Canvas, ABitmap.Width, AColour);
  N := LowerCase(AName);

  case N of
    'new':
      DrawPage(P);
    'open':
      begin
        P.Poly([1.5, 13.5, 1.5, 3.5, 6, 3.5, 7.5, 5.5, 12.5, 5.5, 12.5, 7.5]);
        P.Poly([1.5, 13.5, 4.5, 7.5, 15, 7.5, 12, 13.5, 1.5, 13.5]);
      end;
    'save':
      begin
        { A floppy disk: still the only universally read save glyph. }
        P.Box(2, 2, 14, 14);
        P.Box(5, 2, 11, 6, True);
        P.Box(4, 9, 12, 14);
      end;
    'saveas':
      begin
        P.Box(2, 2, 12, 12);
        P.Box(4.5, 2, 9.5, 5.5, True);
        P.Line(10, 15, 15, 10);
        P.Poly([13.5, 8.5, 15.5, 10.5, 14.5, 11.5, 12.5, 9.5], True);
      end;
    'close':
      begin
        P.Width(2);
        P.Line(3.5, 3.5, 12.5, 12.5);
        P.Line(12.5, 3.5, 3.5, 12.5);
        P.Width(1.2);
      end;
    'reload':
      begin
        P.C.Brush.Style := bsClear;
        P.C.Arc(P.X(2), P.X(2), P.X(14), P.X(14), P.X(2), P.X(7), P.X(14), P.X(6));
        P.Poly([11, 1.5, 14.5, 4.5, 10.5, 6.5], True);
      end;
    'print':
      begin
        P.Box(4, 2, 12, 6);
        P.Box(2, 6, 14, 11);
        P.Box(4.5, 9, 11.5, 14.5);
      end;
    'quit':
      begin
        { A door with an arrow leaving through it. }
        P.Poly([2, 1.5, 8, 1.5, 8, 14.5, 2, 14.5, 2, 1.5]);
        P.Line(7, 8, 14.5, 8);
        P.Poly([11.5, 5, 15, 8, 11.5, 11], True);
      end;
    'undo', 'redo':
      begin
        if N = 'undo' then
        begin
          P.C.Arc(P.X(3), P.X(4), P.X(13), P.X(12), P.X(13), P.X(6), P.X(3), P.X(6));
          P.Poly([2, 2.5, 6.5, 6.5, 1.5, 7.5], True);
        end
        else
        begin
          P.C.Arc(P.X(3), P.X(4), P.X(13), P.X(12), P.X(3), P.X(6), P.X(13), P.X(6));
          P.Poly([14, 2.5, 14.5, 7.5, 9.5, 6.5], True);
        end;
      end;
    'cut':
      begin
        P.Line(4.5, 1.5, 10, 10);
        P.Line(11.5, 1.5, 6, 10);
        P.Ellipse(2.5, 10, 7, 14.5);
        P.Ellipse(9, 10, 13.5, 14.5);
      end;
    'copy':
      begin
        P.Box(2, 1.5, 10, 11.5);
        P.Box(5.5, 4.5, 13.5, 14.5);
      end;
    'paste':
      begin
        P.Box(2.5, 2.5, 13.5, 14.5);
        P.Box(5.5, 1, 10.5, 4, True);
        P.Line(5, 8, 11, 8);
        P.Line(5, 11, 11, 11);
      end;
    'delete':
      begin
        P.Box(4, 4, 12, 14.5);
        P.Line(2.5, 4, 13.5, 4);
        P.Line(6.5, 2, 9.5, 2);
        P.Line(6.5, 6.5, 6.5, 12);
        P.Line(9.5, 6.5, 9.5, 12);
      end;
    'selectall':
      begin
        P.C.Pen.Style := psDot;
        P.Box(1.5, 1.5, 14.5, 14.5);
        P.C.Pen.Style := psSolid;
        for i := 0 to 2 do
          P.Line(4, 5 + i * 3, 12, 5 + i * 3);
      end;
    'indent', 'unindent':
      begin
        for i := 0 to 3 do
          P.Line(7, 2.5 + i * 3.5, 14.5, 2.5 + i * 3.5);
        if N = 'indent' then
          P.Poly([1.5, 5, 5, 8, 1.5, 11], True)
        else
          P.Poly([5, 5, 1.5, 8, 5, 11], True);
      end;
    'comment', 'uncomment':
      begin
        P.Poly([1.5, 2.5, 14.5, 2.5, 14.5, 10.5, 6, 10.5, 3, 14, 3, 10.5, 1.5, 10.5, 1.5, 2.5]);
        if N = 'comment' then
        begin
          P.Line(8, 4.5, 8, 8.5);
          P.Line(6, 6.5, 10, 6.5);
        end
        else
          P.Line(5, 6.5, 11, 6.5);
      end;
    'find':
      DrawMagnifier(P);
    'findnext', 'findprev':
      begin
        P.Ellipse(1.5, 1.5, 9.5, 9.5);
        P.Line(8.5, 8.5, 11.5, 11.5);
        if N = 'findnext' then
          P.Poly([12, 8.5, 15.5, 12, 12, 15.5], True)
        else
          P.Poly([15.5, 8.5, 12, 12, 15.5, 15.5], True);
      end;
    'replace':
      begin
        DrawMagnifier(P);
        P.Line(9, 4, 14, 4);
        P.Poly([12, 2, 14.5, 4, 12, 6], True);
      end;
    'gotoline':
      begin
        for i := 0 to 3 do
          P.Line(6, 2.5 + i * 3.5, 14.5, 2.5 + i * 3.5);
        P.Poly([1, 6, 4.5, 9.5, 1, 13], True);
      end;
    'bookmark':
      P.Poly([4, 1.5, 12, 1.5, 12, 14.5, 8, 10.5, 4, 14.5, 4, 1.5], True);
    'prefs':
      begin
        P.Ellipse(5, 5, 11, 11);
        for i := 0 to 3 do
          P.Line(8 + 6 * Cos(i * Pi / 4), 8 + 6 * Sin(i * Pi / 4),
                 8 - 6 * Cos(i * Pi / 4), 8 - 6 * Sin(i * Pi / 4));
        P.Ellipse(6.5, 6.5, 9.5, 9.5, True);
      end;
    'shortcuts':
      begin
        P.Box(1, 4, 15, 12);
        for i := 0 to 3 do
          P.Box(2.5 + i * 3, 5.5, 4.5 + i * 3, 7.5, True);
        P.Box(4, 9, 12, 10.5, True);
      end;
    'stop':
      begin
        P.Colour(clRed);
        P.Poly([5, 2, 11, 2, 14, 5, 14, 11, 11, 14, 5, 14, 2, 11, 2, 5, 5, 2], True);
        P.Colour(AColour);
      end;
    'run':
      begin
        { Drawn in the same ink as everything else.  It was green, which made
          it the one coloured mark on an otherwise monochrome toolbar and
          drew the eye to Run for no reason anyone chose. }
        P.Poly([3.5, 1.5, 14, 8, 3.5, 14.5], True);
      end;
    'debug':
      begin
        { A bug: a body, a head, and legs.  The one glyph in this set that is
          a picture of its name rather than of its action, because every
          debugger in thirty years has used it and nothing else reads. }
        P.Ellipse(5, 5.5, 11, 13, True);
        P.Ellipse(6.5, 2.5, 9.5, 5.5);
        P.Line(2, 7, 5, 8.5);
        P.Line(2, 12, 5, 11);
        P.Line(14, 7, 11, 8.5);
        P.Line(14, 12, 11, 11);
      end;
    'stepover':
      begin
        { An arrow that arcs over a dot: the call is skipped, not entered. }
        P.Poly([3, 9, 5, 5.5, 8, 4, 11, 5.5, 13, 9]);
        P.Poly([13, 9, 10, 8.5, 11.5, 11.5], True);
        P.Ellipse(6.5, 11, 9.5, 14, True);
      end;
    'stepinto':
      begin
        { An arrow down into a dot. }
        P.Line(8, 2, 8, 8.5);
        P.Poly([8, 11, 5.5, 7, 10.5, 7], True);
        P.Ellipse(6.5, 11.5, 9.5, 14.5, True);
      end;
    'stepout':
      begin
        { And back up out of it. }
        P.Line(8, 11.5, 8, 5);
        P.Poly([8, 2.5, 5.5, 6.5, 10.5, 6.5], True);
        P.Ellipse(6.5, 12, 9.5, 15, True);
      end;
    'pause':
      begin
        P.Box(4.5, 3, 6.8, 13, True);
        P.Box(9.2, 3, 11.5, 13, True);
      end;
    'breakpoint':
      begin
        { A stop sign.  The margin gets a filled disc, which is what every
          debugger draws there -- but on a monochrome toolbar a disc and the
          filled triangle of Run are two solid blobs of the same weight, and
          they were being mistaken for each other.  An octagon is the one
          shape that reads as "stop" with no colour to help it. }
        { An outlined octagon with a bar across it.  A filled shape was the
          problem: at sixteen pixels a solid disc and the solid triangle of
          Run are two blobs of the same weight, and they were being taken
          for each other.  This is hollow, so it cannot be. }
        P.Poly([5.5, 2, 10.5, 2, 14, 5.5, 14, 10.5,
                10.5, 14, 5.5, 14, 2, 10.5, 2, 5.5, 5.5, 2]);
        P.Box(5, 7.2, 11, 8.8, True);
      end;
    'debugline':
      begin
        { The arrow that says "execution is here". }
        P.Poly([3, 4.5, 9, 8, 3, 11.5], True);
        P.Line(10.5, 8, 13.5, 8);
      end;
    'terminal':
      begin
        P.Box(1, 2.5, 15, 13.5);
        { A shell prompt: a chevron and a cursor bar. }
        P.Poly([3.5, 6, 6, 8, 3.5, 10]);
        P.Line(7.5, 10.5, 12, 10.5);
      end;
    'browser':
      begin
        P.Poly([1.5, 13.5, 1.5, 3.5, 6, 3.5, 7.5, 5.5, 14.5, 5.5, 14.5, 13.5, 1.5, 13.5]);
        P.Line(1.5, 8, 14.5, 8);
      end;
    'symbols':
      begin
        P.Line(2, 3.5, 5, 3.5);
        P.Line(2, 8, 5, 8);
        P.Line(2, 12.5, 5, 12.5);
        P.Box(6.5, 2, 14.5, 5, True);
        P.Box(6.5, 6.5, 14.5, 9.5, True);
        P.Box(6.5, 11, 14.5, 14, True);
      end;
    'splith':
      begin
        P.Box(1.5, 1.5, 14.5, 14.5);
        P.Width(1.6);
        P.Line(8, 1.5, 8, 14.5);
        P.Width(1.2);
      end;
    'splitv':
      begin
        P.Box(1.5, 1.5, 14.5, 14.5);
        P.Width(1.6);
        P.Line(1.5, 8, 14.5, 8);
        P.Width(1.2);
      end;
    'wrap':
      begin
        P.Line(2, 3.5, 14, 3.5);
        P.Line(2, 8, 11.5, 8);
        P.C.Arc(P.X(9), P.X(8), P.X(14), P.X(13), P.X(9), P.X(10.5), P.X(14), P.X(10.5));
        P.Line(4, 12.5, 11.5, 12.5);
        P.Poly([6, 10.5, 3.5, 12.5, 6, 14.5], True);
      end;
    'linenumbers':
      begin
        P.Box(1.5, 1.5, 5, 14.5);
        for i := 0 to 3 do
          P.Line(6.5, 3 + i * 3.5, 14.5, 3 + i * 3.5);
        for i := 0 to 3 do
          P.Line(2.5, 3 + i * 3.5, 4, 3 + i * 3.5);
      end;
    'help':
      begin
        P.Ellipse(1.5, 1.5, 14.5, 14.5);
        P.C.Font.Height := P.X(11);
        P.C.Font.Color := AColour;
        P.C.Brush.Style := bsClear;
        P.C.TextOut(P.X(5.5), P.X(2.5), '?');
      end;
    'back', 'forward', 'up':
      begin
        { One arrow, drawn in the direction asked for. }
        P.Width(1.8);
        if N = 'up' then
        begin
          P.Line(8, 14, 8, 4);
          P.Poly([3.5, 8.5, 8, 3.5, 12.5, 8.5], True);
        end
        else if N = 'back' then
        begin
          P.Line(14, 8, 4, 8);
          P.Poly([8.5, 3.5, 3.5, 8, 8.5, 12.5], True);
        end
        else
        begin
          P.Line(2, 8, 12, 8);
          P.Poly([7.5, 3.5, 12.5, 8, 7.5, 12.5], True);
        end;
        P.Width(1.2);
      end;
    'home':
      begin
        P.Poly([1.5, 8, 8, 2, 14.5, 8]);
        P.Poly([3.5, 7.5, 3.5, 14, 12.5, 14, 12.5, 7.5]);
        P.Box(6.5, 9.5, 9.5, 14);
      end;
    'doc', 'docmodified':
      begin
        DrawPage(P);
        if N = 'docmodified' then
        begin
          { A filled dot, the same mark the caption carries. }
          P.Colour(clRed);
          P.Ellipse(7, 8, 12, 13, True);
          P.Colour(AColour);
        end;
      end;
    'about':
      begin
        P.Ellipse(1.5, 1.5, 14.5, 14.5);
        P.C.Font.Height := P.X(11);
        P.C.Font.Color := AColour;
        P.C.Brush.Style := bsClear;
        P.C.TextOut(P.X(6.5), P.X(2.5), 'i');
      end;
  end;
end;

var
  FGlyph: TBitmap = nil;

function LedIconBitmap(const AName: string; AColour: TColor): TBitmap;
begin
  { One bitmap reused for every call: Glyph.Assign copies, so nothing outside
    keeps a reference, and this avoids leaking one per button. }
  if FGlyph = nil then
  begin
    FGlyph := TBitmap.Create;
    FGlyph.PixelFormat := pf24bit;
    FGlyph.SetSize(16, 16);
  end;
  FGlyph.Canvas.Brush.Color := MaskColour;
  FGlyph.Canvas.Brush.Style := bsSolid;
  FGlyph.Canvas.FillRect(0, 0, 16, 16);
  FGlyph.Canvas.AntialiasingMode := amOff;
  LedDrawIcon(FGlyph, AName, AColour);
  FGlyph.TransparentColor := MaskColour;
  FGlyph.Transparent := True;
  Result := FGlyph;
end;

function LedBuildIconList(AImages: TImageList; const ANames: array of string;
  AColour: TColor): TImageList;
var
  Bmp: TBitmap;
  i: Integer;
begin
  Result := AImages;
  AImages.Clear;
  for i := 0 to High(ANames) do
  begin
    Bmp := TBitmap.Create;
    try
      { 24-bit, not 32.  AddMasked compares whole pixels, and a 32-bit
        bitmap carries an alpha byte that the canvas leaves at zero while
        the mask colour is spelled with alpha 255, so nothing ever matches
        and every icon keeps a solid magenta square behind it. }
      Bmp.PixelFormat := pf24bit;
      Bmp.SetSize(AImages.Width, AImages.Height);
      Bmp.Canvas.Brush.Color := MaskColour;
      Bmp.Canvas.Brush.Style := bsSolid;
      Bmp.Canvas.FillRect(0, 0, Bmp.Width, Bmp.Height);

      { Antialiasing has to stay off for the same reason.  A masked bitmap
        is transparent only where the pixel matches exactly, so smoothed
        edges would blend the icon into the mask colour and leave a magenta
        fringe around every glyph.  At 16 pixels crisp is the better
        trade anyway. }
      Bmp.Canvas.AntialiasingMode := amOff;

      LedDrawIcon(Bmp, ANames[i], AColour);
      AImages.AddMasked(Bmp, MaskColour);
    finally
      Bmp.Free;
    end;
  end;
end;

finalization
  FGlyph.Free;

end.
