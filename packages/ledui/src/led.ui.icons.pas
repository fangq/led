{ LED - a lightweight editor.  Toolbar and menu icons, drawn rather than shipped.

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
  Classes, SysUtils, Graphics, Controls, ImgList, ComCtrls, Buttons,
  IntfGraphics, GraphType, FPimage;

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

{ The colour a file-type icon is drawn in, or clNone for the icons that have
  no colour of their own and take whatever the caller asks for.

  Only the file kinds are coloured.  A toolbar wants one ink -- a row of
  differently-tinted buttons reads as decoration -- but a file tree is
  scanned rather than read, and colour is what makes a C file findable among
  forty others at a glance.  The same picture and colour appear on the tab
  header, so a file looks the same wherever it is shown. }
function LedIconAccent(const AName: string): TColor;

{ The file-type icon name for AFileName, by extension -- 'filesource',
  'filemarkdown' and so on, or 'doc' for anything unrecognised.  One rule, so
  the browser tree and the tab headers cannot drift apart. }
function LedIconForFile(const AFileName: string): string;

{ The artwork file for AName, or '' when there is none and the icon is
  drawn instead.

  **Both kinds live in one list and that is deliberate.**  The drawn icons
  answer a real problem -- they need no artwork to license, they follow the
  requested size exactly, and adding one is a case branch -- and they are
  still what the file tree and the odd corner of the menus use.  What they
  are not is a match for a modern toolbar, so the two dozen actions a reader
  actually looks at came from a drawn set, and the rest still come from
  here. }
function LedIconArtwork(const AName: string): string;

{ Index of ANAme in the list built by LedBuildIconList, or -1. }
function LedIconIndex(const AName: string): Integer;

{ Every icon this unit can draw, in the canonical order used by the image
  list the application builds at startup. }
function LedIconNames: TStringArray;

{ Every icon that comes from a file in data/icons rather than from a case
  branch.  Readable so that the two lists can be checked against each
  other: a name in this one and not in LedIconNames is an icon nothing can
  ask for, and a file in data/icons that is in neither is dead weight. }
function LedArtworkNames: TStringArray;

{ Puts the application's own logo on the window and the task bar entry.

  It reads the PNG copy of the artwork that packaging/windows/led.rc embeds,
  rather than the MAINICON in the same binary.  MAINICON is the same picture
  and the LCL reads it back correctly in process -- all seven sizes -- but
  what reaches the window manager from it has its colour channels striped
  and its alpha forced opaque.  A PNG assigned to Application.Icon arrives
  intact.  Does nothing if the resource is missing, because a build without
  it should start with no icon rather than not start. }
procedure LedApplyWindowIcon;

{ The same, from a file, for a program whose artwork is not the one compiled
  into led.res.

  The fork ships its picture in the data directory rather than rebuilding
  the resource: one .res is embedded in both binaries -- they are one
  project with two project files -- so replacing what is in it would change
  the editor's icon as well.  Falls back to the resource when the file is
  not there. }
procedure LedApplyWindowIconFile(const AFileName: string);

{ Gives ABar LED's own button painting: a wash under the pointer, a stronger
  one while a button is held or checked, and hairline separators.

  Needed because gtk2 asks for ttbButtonHot and draws nothing for it, so a
  toolbar of flat glyphs gives no sign which button a click would reach.  One
  call rather than a handler per toolbar, because LED has four of them -- the
  main bar, the debugger's, the breakpoint pane's -- and they should not each
  answer the pointer differently. }
procedure LedStyleToolBar(ABar: TToolBar);

type
  { A speed button that answers the pointer the way a toolbar button does.

    The toolbars LED builds by hand are not TToolBars: the file browser's nav
    row, its crumbs and the dock's edge rails are all TSpeedButtons, which
    OnPaintButton does not reach.  They went on drawing nothing under the
    pointer after the main bar started to, which made them look disabled next
    to it.

    PaintBackground is the hook, rather than Paint: everything a speed button
    draws on top -- the glyph, the caption, their positions, the shifted
    content while it is held -- stays the widget's own job, as it should. }
  TLedSpeedButton = class(TSpeedButton)
  protected
    procedure PaintBackground(var PaintRect: TRect); override;
  end;

{ Draws one icon into ABitmap, which must already be sized. }
procedure LedDrawIcon(ABitmap: TBitmap; const AName: string; AColour: TColor);

{ One icon as a 16x16 bitmap with a transparent background, for the controls
  that take a Glyph rather than an image list index.  The caller owns the
  result only through the control it assigns it to -- TSpeedButton.Glyph
  copies, so the bitmap is freed here. }
function LedIconBitmap(const AName: string; AColour: TColor;
  ASize: Integer = 16): TBitmap;

{ One shipped icon as a bitmap of its own, with its alpha, at ASize -- or
  nil where that name has no artwork.  **The caller owns it**, unlike
  LedIconBitmap's shared buffer, because this is for the places that build
  an image list of their own: the App Designer's toolbar has four of LED's
  icons and three of its own, and the three were drawn while the four were
  painted. }
function LedIconArtworkBitmap(const AName: string; ASize: Integer): TBitmap;

implementation

uses
  Forms, LCLType, Led.Core.Paths;

{ ---- the drawn set and the shipped one ---------------------------------- }

{ The actions whose picture is a file in data/icons rather than a case
  branch below.  Listed rather than probed so that a data directory the
  reader has half-deleted shows the drawn icon instead of an empty square,
  and so that "which of these is artwork" is answerable by reading.
  The MATLAB logo is the MATLAB fork's (Mima) alone: its file ships there,
  and LED draws a page with an M for the name instead. }
const
  ArtworkNames: array[0..{$IFDEF MIMA}103{$ELSE}102{$ENDIF}] of string = (
    'assistant', 'back', 'breakpoint', 'browser', 'codeform', 'copy',
    'cut', 'debug', 'files', 'find', 'forward', 'help', 'home',
    {$IFDEF MIMA}'matlab', {$ENDIF}'new', 'newfile', 'newfolder', 'notebook', 'open',
    'output', 'paste', 'pause', 'preview', 'project', 'python',
    'redo', 'reload', 'replace', 'run', 'runcell', 'save', 'saveas',
    'stepinto', 'stepout', 'stepover', 'stop', 'symbols', 'terminal',
    'theme', 'undo', 'up', 'watch',
    { the visual editor's toolbar }
    'accept', 'addcomment', 'aligncenter', 'alignjustify', 'alignleft', 'alignright',
    'bookmark', 'borders', 'bullets', 'caption', 'clearformat', 'columns',
    'crossref', 'distribute', 'fmtbold', 'fmtitalic', 'fmtstrike', 'fmtsub',
    'fmtsuper', 'fmtunderline', 'fontgrow', 'fontshrink', 'footer', 'formatmarks',
    'header', 'headerrow', 'highlight', 'host', 'indent', 'insertbreak',
    'insertequation', 'insertfield', 'insertlink', 'insertnote', 'insertpicture', 'insertsymbol',
    'inserttable', 'join', 'linenumbers', 'linespacing', 'margins', 'navigation',
    'nextchange', 'numbering', 'orientation', 'pagenumbers', 'pagesize', 'prevchange',
    'reject', 'shading', 'share', 'tbldelete', 'tblinsert', 'tblmerge',
    'textcolor', 'toc', 'trackchanges', 'unindent', 'zoomin', 'zoomout',
    'formatpainter', 'insertform');

function LedIconArtwork(const AName: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(ArtworkNames) do
    if ArtworkNames[i] = AName then
    begin
      Result := LedDataFile('icons' + PathDelim + AName + '.png');
      if not FileExists(Result) then Result := '';
      Exit;
    end;
end;

{ Reads an icon file and resamples it to ASize, keeping its alpha.

  The resampling is here rather than left to the widget set because a
  toolbar icon is a twentieth of the artwork's area: StretchDraw on gtk2
  point-samples, which on a 64-pixel drawing reduced to 20 throws away four
  pixels in five and turns a smooth curve into a stack of steps.  Averaging
  the whole source box per destination pixel costs a few thousand
  multiplications once, at startup.

  Alpha is weighted in and out again -- the sum is of colour times coverage,
  divided by the coverage -- or a pixel next to a transparent one would be
  dragged towards whatever colour happened to be stored under the
  transparency. }
function LoadIconArtwork(const AFile: string; ASize: Integer): TBitmap;
{ **Cubic, not a box average.**

  The artwork is drawn at 128 and shown at whatever the toolbar's buttons
  come to -- 26 on an ordinary display, 78 on a 3x one -- so every icon in
  the program goes through this on the way to the screen.  It used to take
  the mean of the source pixels that fall in each destination pixel, which
  is correct and soft: a box filter passes everything above the sampling
  rate straight through as blur, and what that blurs most is exactly the
  edge of a glyph against nothing.

  Catmull-Rom instead -- the interpolating cubic, B=0 and C=1/2 -- with its
  support widened by the scale factor, which is what keeps a 5:1 reduction
  from aliasing while still being a cubic rather than an average.  Its
  slightly negative lobes are what sharpen the border: they pull the pixel
  just outside an edge away from the colour just inside it.

  On premultiplied alpha, and unpremultiplied again at the end.  Weighting
  colour by coverage is the whole reason the old code multiplied by Alpha
  before summing; a cubic has to do the same or the half-covered pixels
  around a glyph drag the colour of the transparent side into it. }

  { A cubic overshoots at an edge -- which is the point of it -- so every
    channel comes back through here. }
  function ClampWord(AValue: Double): Word;
  begin
    if AValue <= 0 then Result := 0
    else if AValue >= 65535 then Result := 65535
    else Result := Round(AValue);
  end;

  { Catmull-Rom, written out for the two intervals of |t|. }
  function Cubic(t: Double): Double;
  begin
    t := Abs(t);
    if t < 1 then
      Result := 1.5 * t * t * t - 2.5 * t * t + 1
    else if t < 2 then
      Result := -0.5 * t * t * t + 2.5 * t * t - 4 * t + 2
    else
      Result := 0;
  end;

var
  Png: TPortableNetworkGraphic;
  Src, Dst: TLazIntfImage;
  Desc: TRawImageDescription;
  x, y, sx, sy, x0, x1, y0, y1: Integer;
  ScaleX, ScaleY, SupX, SupY, Cx, Cy, W, Wy, Sum: Double;
  AccR, AccG, AccB, AccA: Double;
  C: TFPColor;
begin
  Result := nil;
  Png := TPortableNetworkGraphic.Create;
  Src := nil;
  Dst := nil;
  try
    try
      Png.LoadFromFile(AFile);
    except
      { A file that is not a picture is not worth failing to start over:
        the caller falls back to the drawn icon. }
      Exit;
    end;
    Src := Png.CreateIntfImage;
    if (Src = nil) or (Src.Width = 0) or (Src.Height = 0) then Exit;

    Desc.Init_BPP32_B8G8R8A8_BIO_TTB(ASize, ASize);
    Dst := TLazIntfImage.Create(0, 0);
    Dst.DataDescription := Desc;
    Dst.SetSize(ASize, ASize);

    { How many source pixels to a destination one, and how far the kernel
      has to reach to cover them.  Never less than one: enlarging is
      interpolation and the kernel keeps its own width. }
    ScaleX := Src.Width / ASize;
    ScaleY := Src.Height / ASize;
    SupX := 2 * ScaleX;
    SupY := 2 * ScaleY;
    if SupX < 2 then SupX := 2;
    if SupY < 2 then SupY := 2;

    for y := 0 to ASize - 1 do
    begin
      Cy := (y + 0.5) * ScaleY - 0.5;
      y0 := Trunc(Cy - SupY); if y0 < 0 then y0 := 0;
      y1 := Trunc(Cy + SupY) + 1; if y1 > Src.Height - 1 then y1 := Src.Height - 1;
      for x := 0 to ASize - 1 do
      begin
        Cx := (x + 0.5) * ScaleX - 0.5;
        x0 := Trunc(Cx - SupX); if x0 < 0 then x0 := 0;
        x1 := Trunc(Cx + SupX) + 1; if x1 > Src.Width - 1 then x1 := Src.Width - 1;

        AccR := 0; AccG := 0; AccB := 0; AccA := 0; Sum := 0;
        for sy := y0 to y1 do
        begin
          Wy := Cubic((sy - Cy) / (SupY / 2));
          if Wy = 0 then Continue;
          for sx := x0 to x1 do
          begin
            W := Wy * Cubic((sx - Cx) / (SupX / 2));
            if W = 0 then Continue;
            C := Src.Colors[sx, sy];
            { premultiplied: colour counts for as much as it covers }
            AccR := AccR + W * C.Red * C.Alpha;
            AccG := AccG + W * C.Green * C.Alpha;
            AccB := AccB + W * C.Blue * C.Alpha;
            AccA := AccA + W * C.Alpha;
            Sum := Sum + W;
          end;
        end;

        if (Sum <= 0) or (AccA <= 0) then
          C := FPColor(0, 0, 0, 0)
        else
        begin
          { Unpremultiply by the weighted alpha, not by the weight: that is
            what divides out the coverage again. }
          C.Red   := ClampWord(AccR / AccA);
          C.Green := ClampWord(AccG / AccA);
          C.Blue  := ClampWord(AccB / AccA);
          { A cubic overshoots -- that is where the sharpening comes from --
            so alpha is clamped rather than trusted. }
          C.Alpha := ClampWord(AccA / Sum);
        end;
        Dst.Colors[x, y] := C;
      end;
    end;

    Result := TBitmap.Create;
    Result.LoadFromIntfImage(Dst);
  finally
    Dst.Free;
    Src.Free;
    Png.Free;
  end;
end;

const
  { The background the icons are drawn on and then masked out.  Magenta
    because nothing in an icon is ever legitimately this colour. }
  MaskColour = TColor($00FF00FF);

  { Kept in one place so the toolbar, the menus and the tab headers all agree
    on what index means what. }
  IconNames: array[0..131] of string = (
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
    'breakpoint', 'debugline',
    { The file browser's tree, one per kind of file it can recognise.  A page
      with a mark on it, except the folder, so a row reads as "a file, of this
      sort" rather than as an unrelated picture. }
    'folder', 'filesource', 'filetext', 'filemarkdown', 'filepdf',
    'fileimage', 'filebinary',
    { The browser's two making-things buttons.  The same folder and page as
      above with a plus badge on the corner, so the pair reads as "a new one
      of these" rather than as two more ways to look at what is there. }
    'newfolder', 'newfile',
    { The toolbar's theme chooser. }
    'theme',
    { The AI pane.  Appended, like everything else here: an ImageIndex in
      the form file is an absolute position. }
    'assistant',
    { Four panes that had been making do with 'doc' or 'run' and now have a
      picture of their own.  Appended for the same reason as everything
      above: a position in this list is an ImageIndex in a form file. }
    'preview', 'notebook', 'output', 'project',
    { The notebook's cell buttons: a pencil for editing a text cell, and an
      eraser for clearing a code cell's output.  Appended, as above. }
    'edit', 'clearoutput', 'runcell',

    { What the second icon set added that nothing here had a name for: the
      two languages a file list can tell apart at a glance, the debugger's
      watches, the designer's switch between a form and its code, and the
      painted page the editor pane shows on its rail -- which is *not*
      'doc', the drawn page a file list puts against a name it does not
      recognise.  One name was doing both jobs, and painting it put a
      coloured page in among the drawn ones in the tree.

      Appended, like everything above it: a position in this list is an
      ImageIndex in a form file, so the list only ever grows at the end. }
    'python', 'matlab', 'watch', 'codeform', 'files',
    { The visual editor's toolbar, painted (tools/visual_icons.py).  Appended:
      a position here is an ImageIndex in a form file. }
    'accept', 'addcomment', 'aligncenter', 'alignjustify', 'alignleft', 'alignright',
    'borders', 'bullets', 'caption', 'clearformat', 'columns', 'crossref',
    'distribute', 'fmtbold', 'fmtitalic', 'fmtstrike', 'fmtsub', 'fmtsuper',
    'fmtunderline', 'fontgrow', 'fontshrink', 'footer', 'formatmarks', 'header',
    'headerrow', 'highlight', 'host', 'insertbreak', 'insertequation', 'insertfield',
    'insertlink', 'insertnote', 'insertpicture', 'insertsymbol', 'inserttable', 'join',
    'linespacing', 'margins', 'navigation', 'nextchange', 'numbering', 'orientation',
    'pagenumbers', 'pagesize', 'prevchange', 'reject', 'shading', 'share',
    'tbldelete', 'tblinsert', 'tblmerge', 'textcolor', 'toc', 'trackchanges',
    'zoomin', 'zoomout',
    'formatpainter', 'insertform'
  );


type
  { OnPaintButton is a method pointer, so the shared painter needs an object
    to hang off.  One instance for the process, created on first use. }
  TLedToolPainter = class
    procedure Paint(Sender: TToolButton; State: Integer);
  end;

  { TToolButton.Canvas is protected, and a button LED paints itself has to be
    drawn on something. }
  TLedToolButtonAccess = class(TToolButton);

var
  GToolPainter: TLedToolPainter = nil;

{ ANum parts of A to ADen-ANum parts of B. }
function Blend(A, B: TColor; ANum, ADen: Integer): TColor;
var
  Ra, Ga, Ba, Rb, Gb, Bb: Integer;
begin
  A := ColorToRGB(A);
  B := ColorToRGB(B);
  Ra := A and $FF;  Ga := (A shr 8) and $FF;  Ba := (A shr 16) and $FF;
  Rb := B and $FF;  Gb := (B shr 8) and $FF;  Bb := (B shr 16) and $FF;
  Result := TColor(
    (((Ra * ANum + Rb * (ADen - ANum)) div ADen) and $FF)
    or ((((Ga * ANum + Gb * (ADen - ANum)) div ADen) and $FF) shl 8)
    or ((((Ba * ANum + Bb * (ADen - ANum)) div ADen) and $FF) shl 16));
end;

{ The same three washes the toolbar painter uses, so a hand-built row of
  speed buttons and a real toolbar react to the pointer identically. }
procedure TLedSpeedButton.PaintBackground(var PaintRect: TRect);
var
  Bg, Wash: TColor;
begin
  Bg := clNone;
  if Parent <> nil then Bg := Parent.Brush.Color;
  if Bg = clNone then Bg := Color;
  if Bg = clNone then Bg := clBtnFace;

  Wash := clNone;
  if Enabled then
  begin
    if FState in [bsDown, bsExclusive] then
      Wash := Blend(clHighlight, Bg, 2, 5)
    else if Down then
      Wash := Blend(clHighlight, Bg, 3, 10)
    else if MouseInControl then
      Wash := Blend(clHighlight, Bg, 1, 5);
  end;

  if not Transparent then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Bg;
    Canvas.FillRect(PaintRect);
  end;
  if Wash <> clNone then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Wash;
    Canvas.FillRect(PaintRect);
  end;
end;

procedure TLedToolPainter.Paint(Sender: TToolButton; State: Integer);
var
  Bar: TToolBar;
  C: TCanvas;
  R: TRect;
  Bg, Wash: TColor;
  X, Y, Mid: Integer;
begin
  Bar := Sender.Parent as TToolBar;
  C := TLedToolButtonAccess(Sender).Canvas;
  R := Sender.ClientRect;
  Bg := Bar.Color;
  if Bg = clNone then Bg := clBtnFace;

  C.Brush.Style := bsSolid;
  C.Brush.Color := Bg;
  C.FillRect(R);

  if Sender.Style in [tbsSeparator, tbsDivider] then
  begin
    Mid := (R.Left + R.Right) div 2;
    C.Pen.Color := Blend(clBtnShadow, Bg, 1, 2);
    C.Pen.Width := 1;
    C.Line(Mid, R.Top + 4, Mid, R.Bottom - 4);
    Exit;
  end;

  { 1 normal, 2 hot, 3 pressed, 4 disabled, 5 checked, 6 checked and hot. }
  Wash := clNone;
  case State of
    2:    Wash := Blend(clHighlight, Bg, 1, 5);
    3:    Wash := Blend(clHighlight, Bg, 2, 5);
    5, 6: Wash := Blend(clHighlight, Bg, 3, 10);
  end;
  if Wash <> clNone then
  begin
    C.Brush.Color := Wash;
    C.FillRect(R);
  end;

  if (Bar.Images <> nil) and (Sender.ImageIndex >= 0) and
     (Sender.ImageIndex < Bar.Images.Count) then
  begin
    X := R.Left + (R.Right - R.Left - Bar.Images.Width) div 2;
    Y := R.Top + (R.Bottom - R.Top - Bar.Images.Height) div 2;
    { A caption, where the toolbar shows one, goes beside the glyph rather
      than under it -- which is what TToolButton does with both, and what
      cropped the breakpoint pane's labels. }
    if Bar.ShowCaptions and (Sender.Caption <> '') then
    begin
      X := R.Left + 4;
      Y := R.Top + (R.Bottom - R.Top - Bar.Images.Height) div 2;
      Bar.Images.Draw(C, X, Y, Sender.ImageIndex, Sender.Enabled);
      C.Brush.Style := bsClear;
      C.Font.Color := clBtnText;
      if not Sender.Enabled then C.Font.Color := clGrayText;
      C.TextOut(X + Bar.Images.Width + 4,
        R.Top + (R.Bottom - R.Top - C.TextHeight('Ag')) div 2, Sender.Caption);
      Exit;
    end;
    Bar.Images.Draw(C, X, Y, Sender.ImageIndex, Sender.Enabled);
    { A button that opens a menu says so.  TToolButton would have drawn this
      arrow; assigning OnPaintButton takes the whole job, including the parts
      one did not mean to take over. }
    if Sender.Style in [tbsDropDown, tbsButtonDrop] then
    begin
      C.Brush.Style := bsSolid;
      C.Brush.Color := clBtnText;
      C.Pen.Color := clBtnText;
      Mid := R.Right - 7;
      Y := (R.Top + R.Bottom) div 2 + 3;
      C.Polygon([Point(Mid - 3, Y - 2), Point(Mid + 3, Y - 2),
                 Point(Mid, Y + 2)]);
    end;
  end
  else if Bar.ShowCaptions and (Sender.Caption <> '') then
  begin
    C.Brush.Style := bsClear;
    C.Font.Color := clBtnText;
    if not Sender.Enabled then C.Font.Color := clGrayText;
    C.TextOut(R.Left + 4,
      R.Top + (R.Bottom - R.Top - C.TextHeight('Ag')) div 2, Sender.Caption);
  end;
end;

procedure LedStyleToolBar(ABar: TToolBar);
begin
  if ABar = nil then Exit;
  if GToolPainter = nil then GToolPainter := TLedToolPainter.Create;
  ABar.OnPaintButton := @GToolPainter.Paint;
end;

procedure LedApplyWindowIconFile(const AFileName: string);
var
  Png: TPortableNetworkGraphic;
begin
  if (AFileName <> '') and FileExists(AFileName) then
  begin
    Png := TPortableNetworkGraphic.Create;
    try
      try
        Png.LoadFromFile(AFileName);
        Application.Icon.Assign(Png);
        Exit;
      except
        { Not a picture after all; the resource below is the better answer
          to that than no icon. }
      end;
    finally
      Png.Free;
    end;
  end;
  LedApplyWindowIcon;
end;

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

function LedArtworkNames: TStringArray;
var
  i: Integer;
begin
  SetLength(Result, Length(ArtworkNames));
  for i := 0 to High(ArtworkNames) do Result[i] := ArtworkNames[i];
end;

function LedIconAccent(const AName: string): TColor;
begin
  { The toolbar, in the Tango palette medit's stock GTK icons came from.

    This reverses an earlier judgement of mine, and the reason is worth
    keeping: I had argued that a row of differently tinted buttons reads as
    decoration and that one ink was calmer.  Set beside medit it is not --
    its toolbar is easier to scan precisely because Save is blue and Cut is
    steel and Stop is red, so the eye goes to a colour rather than reading a
    row of identical grey shapes.

    Colour by what the action does rather than by which menu it is on:
    making things green, file traffic blue, editing steel, destructive red,
    search amber. }
  if (AName = 'new') or (AName = 'newfile') or (AName = 'newfolder') then
    Exit(RGBToColor( 78, 154,  60));                       { green }
  if (AName = 'open') or (AName = 'reload') then
    Exit(RGBToColor(233, 165,  40));                       { manila }
  if (AName = 'save') or (AName = 'saveas') or (AName = 'print') then
    Exit(RGBToColor( 52, 101, 164));                       { blue }
  if (AName = 'undo') or (AName = 'redo') then
    Exit(RGBToColor(117,  80, 123));                       { plum }
  if (AName = 'cut') or (AName = 'copy') or (AName = 'paste') then
    Exit(RGBToColor(100, 116, 132));                       { steel }
  if (AName = 'delete') or (AName = 'stop') or (AName = 'quit') then
    Exit(RGBToColor(190,  60,  50));                       { red }
  if (AName = 'find') or (AName = 'findnext') or (AName = 'findprev') or
     (AName = 'replace') or (AName = 'gotoline') then
    Exit(RGBToColor(196, 143,  30));                       { amber }
  if (AName = 'run') or (AName = 'debug') then
    Exit(RGBToColor( 78, 154,  60));                       { green }
  if AName = 'breakpoint' then Exit(RGBToColor(190, 60, 50));
  if AName = 'bookmark' then Exit(RGBToColor(196, 143, 30));
  if AName = 'terminal' then Exit(RGBToColor(85, 87, 83));

  { Written as RGB and converted, because a TColor is $00BBGGRR and the
    numbers are unreadable the other way round.  Muted rather than saturated:
    these sit in a list of text, not on a toolbar. }
  if AName = 'filesource'   then Exit(RGBToColor( 70, 135, 205));  { blue }
  if AName = 'filemarkdown' then Exit(RGBToColor( 80, 160, 185));  { teal }
  if AName = 'filetext'     then Exit(RGBToColor(130, 145, 160));  { slate }
  if AName = 'filepdf'      then Exit(RGBToColor(200,  75,  65));  { red }
  if AName = 'fileimage'    then Exit(RGBToColor( 95, 165, 100));  { green }
  if AName = 'filebinary'   then Exit(RGBToColor(175, 135,  75));  { amber }
  if AName = 'folder'       then Exit(RGBToColor(215, 175,  95));  { manila }
  { The fallback page, for a file whose kind LED does not recognise.  It has
    a colour of its own for the same reason the others do, and a mid grey
    rather than the ink: drawn in the ink it was black, which on a dark file
    tree is a page-shaped hole. }
  if AName = 'doc'          then Exit(RGBToColor(128, 134, 143));  { grey }
  Result := clNone;
end;

function LedIconForFile(const AFileName: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  { The two with a logo of their own in the set.  A file list in a MATLAB
    environment is mostly .m files, and telling them from the rest at a
    glance is worth more than the uniformity of a row of blue pages. }
  {$IFDEF MIMA}
  if (Ext = '.m') or (Ext = '.mex') then Exit('matlab');
  {$ENDIF}
  if Ext = '.py' then Exit('python');
  if (Ext = '.c') or (Ext = '.h') or (Ext = '.cpp') or (Ext = '.hpp') or
     (Ext = '.cc') or (Ext = '.cxx') or (Ext = '.m') or (Ext = '.mm') or
     (Ext = '.pas') or (Ext = '.pp') or (Ext = '.inc') or (Ext = '.lpr') or
     (Ext = '.py') or (Ext = '.js') or (Ext = '.ts') or (Ext = '.java') or
     (Ext = '.go') or (Ext = '.rs') or (Ext = '.rb') or (Ext = '.sh') or
     (Ext = '.pl') or (Ext = '.lua') or (Ext = '.sql') or (Ext = '.php') or
     (Ext = '.html') or (Ext = '.xml') or (Ext = '.json') or (Ext = '.yml') or
     (Ext = '.yaml') or (Ext = '.css') or (Ext = '.tex') then
    Exit('filesource');
  if (Ext = '.md') or (Ext = '.markdown') or (Ext = '.wiki') or
     (Ext = '.usemod') or (Ext = '.wp') then Exit('filemarkdown');
  if (Ext = '.txt') or (Ext = '.log') or (Ext = '.ini') or (Ext = '.cfg') or
     (Ext = '.conf') or (Ext = '.csv') then Exit('filetext');
  if Ext = '.pdf' then Exit('filepdf');
  if (Ext = '.png') or (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.gif') or
     (Ext = '.bmp') or (Ext = '.svg') or (Ext = '.ico') or (Ext = '.webp') then
    Exit('fileimage');
  if (Ext = '.o') or (Ext = '.a') or (Ext = '.so') or (Ext = '.dll') or
     (Ext = '.exe') or (Ext = '.bin') or (Ext = '.zip') or (Ext = '.gz') or
     (Ext = '.tar') or (Ext = '.ppu') or (Ext = '.obj') or (Ext = '.class') then
    Exit('filebinary');
  Result := 'doc';
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
{ A plus in the lower-right corner, which is how every toolkit says "a new
  one of these".  Drawn heavier than the outline it sits on so it reads at
  sixteen pixels, where a hairline cross disappears. }
procedure DrawPlusBadge(var P: TPen16);
begin
  P.Width(2);
  P.Line(12.5, 11.5, 12.5, 15.5);
  P.Line(10.5, 13.5, 14.5, 13.5);
  P.Width(1.2);
end;

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
    { a pencil, point down at the lower left }
    'edit':
      begin
        P.Poly([2.5, 13.5, 3, 10.5, 11, 2.5, 13.5, 5, 5.5, 13, 2.5, 13.5]);
        P.Line(9.5, 4, 12, 6.5);
        P.Poly([2.5, 13.5, 3, 10.5, 5.5, 13, 2.5, 13.5], True);
      end;
    { an eraser on the line it has just cleared }
    { Run, in the notebook: an outline, in the one ink its neighbours -- the
      pencil and the eraser -- are drawn in, rather than the toolbar's green }
    'runcell':
      P.Poly([4, 2.5, 13.5, 8, 4, 13.5, 4, 2.5]);
    'clearoutput':
      begin
        P.Poly([1.5, 10, 8, 3.5, 13.5, 9, 8, 14.5, 5, 14.5, 1.5, 11, 1.5, 10]);
        P.Line(4.5, 7, 10.5, 12.5);
        P.Line(9.5, 14.5, 14.5, 14.5);
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
    { The same speech balloon as 'comment', with a spark instead of a plus.
      Drawn rather than borrowed: that glyph already means "comment out
      these lines" in the toolbar and in the Edit menu, and one picture for
      two unrelated commands is how a toolbar stops being readable. }
    'assistant':
      begin
        P.Poly([1.5, 2.5, 14.5, 2.5, 14.5, 10.5, 6, 10.5, 3, 14, 3, 10.5,
                1.5, 10.5, 1.5, 2.5]);
        P.Line(8, 4, 8, 9);
        P.Line(5.5, 6.5, 10.5, 6.5);
        P.Line(6.2, 4.7, 9.8, 8.3);
        P.Line(9.8, 4.7, 6.2, 8.3);
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
    'folder':
      begin
        { A tab and a body, which is the one shape everybody reads as a
          folder.  Narrower than the 'browser' icon beside it on the rail,
          because this one sits in a row of text. }
        P.Poly([1.5, 13, 1.5, 3.5, 6, 3.5, 7.5, 5.5, 14.5, 5.5, 14.5, 13,
                1.5, 13]);
      end;
    'filesource':
      begin
        { A page with angle brackets on it: the mark every editor uses for
          "this one is code". }
        DrawPage(P);
        P.Poly([7, 7.5, 5.5, 9.5, 7, 11.5]);
        P.Poly([9.5, 7.5, 11, 9.5, 9.5, 11.5]);
      end;
    'filetext':
      begin
        { A page with lines of writing. }
        DrawPage(P);
        P.Line(5.5, 7.5, 10.5, 7.5);
        P.Line(5.5, 9.5, 10.5, 9.5);
        P.Line(5.5, 11.5, 8.5, 11.5);
      end;
    'filemarkdown':
      begin
        { A page with the two strokes of an M and the arrow beneath, which is
          what the Markdown mark is. }
        DrawPage(P);
        P.Poly([5.5, 11.5, 5.5, 7.5, 7.5, 9.5, 9.5, 7.5, 9.5, 11.5]);
      end;
    'filepdf':
      begin
        { A page with a band across it, as a printed sheet is shown. }
        DrawPage(P);
        P.Box(5, 8, 11, 11.5, True);
      end;
    'fileimage':
      begin
        { A frame with a horizon and a sun: a picture rather than a page. }
        P.Box(1.5, 3, 14.5, 13);
        P.Ellipse(4, 5, 6.5, 7.5, True);
        P.Poly([1.5, 13, 6, 8.5, 9, 11, 11.5, 8.5, 14.5, 13]);
      end;
    'theme':
      begin
        { A painter's palette: a rounded shape with a thumb hole and three
          wells in it.  Colour is what a theme changes, and a palette is the
          one picture that says so without words. }
        P.Ellipse(1.5, 2.5, 14.5, 13.5);
        P.Ellipse(9.5, 8.5, 12.5, 11.5);
        P.Ellipse(3.6, 5.2, 5.4, 7.0, True);
        P.Ellipse(6.6, 3.9, 8.4, 5.7, True);
        P.Ellipse(3.4, 8.6, 5.2, 10.4, True);
      end;
    'newfolder':
      begin
        { The folder, shortened on the right to leave the badge room. }
        P.Poly([1.5, 13, 1.5, 3.5, 6, 3.5, 7.5, 5.5, 12, 5.5, 12, 13, 1.5, 13]);
        DrawPlusBadge(P);
      end;
    'newfile':
      begin
        { A page, likewise, with the same badge. }
        P.Poly([2.5, 1.5, 8, 1.5, 10.5, 4, 10.5, 12.5, 2.5, 12.5, 2.5, 1.5]);
        P.Line(8, 1.5, 8, 4);
        P.Line(8, 4, 10.5, 4);
        DrawPlusBadge(P);
      end;
    'filebinary':
      begin
        { A gear, not a page.  A binary is a thing that runs, and a page with
          a one and a nought on it read as a document about binary rather
          than as a program.  Eight teeth, because at sixteen pixels more
          become a blur and fewer stop looking like a gear. }
        P.Ellipse(3.2, 3.2, 12.8, 12.8);
        P.Ellipse(6.4, 6.4, 9.6, 9.6, True);
        P.Width(1.6);
        { The teeth, at the four sides and the four diagonals. }
        P.Line(8, 1.6, 8, 3.4);
        P.Line(8, 12.6, 8, 14.4);
        P.Line(1.6, 8, 3.4, 8);
        P.Line(12.6, 8, 14.4, 8);
        P.Line(3.6, 3.6, 4.8, 4.8);
        P.Line(11.2, 11.2, 12.4, 12.4);
        P.Line(12.4, 3.6, 11.2, 4.8);
        P.Line(4.8, 11.2, 3.6, 12.4);
        P.Width(1.2);
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
        { The question mark is drawn, not typed.  TextOut goes through the
          font renderer, which antialiases whatever the canvas is told about
          shapes -- so the glyph's edges came out as blends of the ink and
          the mask colour, and a masked bitmap is transparent only where a
          pixel matches the mask exactly.  The leftovers are the purple
          fringe that shows in a menu. }
        P.Ellipse(1.5, 1.5, 14.5, 14.5);
        P.Width(1.6);
        { The hook: up over the top and back down to the stem. }
        P.Poly([5.6, 6.1, 6.6, 4.4, 9.4, 4.4, 10.4, 6.1, 9.6, 7.6, 8, 8.6,
                8, 10]);
        P.Ellipse(7.2, 11.2, 8.9, 12.9, True);
        P.Width(1.2);
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
        { Drawn rather than typed, for the reason 'help' gives. }
        P.Ellipse(1.5, 1.5, 14.5, 14.5);
        P.Ellipse(7.2, 3.6, 8.9, 5.3, True);
        P.Width(1.8);
        P.Line(8, 7, 8, 11.8);
        P.Width(1.2);
      end;
    { The visual editor's paragraph buttons: lines of text as the alignment
      would set them, a list's marks, the spacing between lines. }
    'alignleft', 'aligncenter', 'alignright', 'alignjustify':
      for i := 0 to 4 do
      begin
        if (N = 'alignjustify') or not Odd(i) then
          P.Line(1.5, 2.5 + i * 2.75, 14.5, 2.5 + i * 2.75)
        else if N = 'alignleft' then
          P.Line(1.5, 2.5 + i * 2.75, 9.5, 2.5 + i * 2.75)
        else if N = 'alignright' then
          P.Line(6.5, 2.5 + i * 2.75, 14.5, 2.5 + i * 2.75)
        else
          P.Line(4, 2.5 + i * 2.75, 12, 2.5 + i * 2.75);
      end;
    'bullets':
      for i := 0 to 2 do
      begin
        P.Ellipse(1.5, 2 + i * 4.5, 4.5, 5 + i * 4.5, True);
        P.Line(7, 3.5 + i * 4.5, 14.5, 3.5 + i * 4.5);
      end;
    'numbering':
      begin
        { 1, 2, 3 in strokes: a numeral is all a reader needs to see }
        P.Width(1);
        P.Line(3, 1.5, 3, 5.5);
        P.Poly([1.5, 7, 4.5, 7, 4.5, 8.5, 1.5, 10, 1.5, 11, 4.5, 11]);
        P.Poly([1.5, 12, 4.5, 12, 4.5, 15, 1.5, 15]);
        P.Line(2, 13.5, 4.5, 13.5);
        P.Width(1.2);
        for i := 0 to 2 do
          P.Line(7, 3.5 + i * 4.5, 14.5, 3.5 + i * 4.5);
      end;
    'linespacing':
      begin
        for i := 0 to 3 do
          P.Line(7, 2.5 + i * 3.6, 14.5, 2.5 + i * 3.6);
        P.Line(3, 2.5, 3, 13.5);
        P.Poly([1, 4.5, 3, 1.5, 5, 4.5], True);
        P.Poly([1, 11.5, 3, 14.5, 5, 11.5], True);
      end;
    'clearformat':
      begin
        P.Poly([1.5, 13, 5.5, 2, 9.5, 13]);
        P.Line(3, 9, 8, 9);
        P.Colour(clRed);
        P.Width(1.6);
        P.Line(9, 9, 14.5, 14.5);
        P.Line(14.5, 9, 9, 14.5);
        P.Width(1.2);
        P.Colour(AColour);
      end;
    'fontgrow', 'fontshrink':
      begin
        P.Poly([1.5, 14.5, 5.5, 3, 9.5, 14.5]);
        P.Line(3, 10.5, 8, 10.5);
        if N = 'fontgrow' then
          P.Poly([10.5, 6, 12.5, 2.5, 14.5, 6], True)
        else
          P.Poly([10.5, 2.5, 12.5, 6, 14.5, 2.5], True);
      end;
    'textcolor':
      begin
        P.Poly([3, 11, 8, 1.5, 13, 11]);
        P.Line(4.8, 7.5, 11.2, 7.5);
        P.Colour(clRed);
        P.Box(1.5, 12.5, 14.5, 15, True);
        P.Colour(AColour);
      end;
    'matlab':
      begin   { where the logo is not shipped (LED): a source page with an M on it }
        DrawPage(P);
        P.Poly([5, 12.5, 5, 7, 8, 10, 11, 7, 11, 12.5]);
      end;
    { the Insert tab }
    'insertpicture':
      begin
        P.Box(1.5, 2.5, 14.5, 13.5);
        P.Poly([1.5, 12, 6, 7, 9, 10, 11, 8, 14.5, 11.5]);
        P.Ellipse(9.5, 4, 12.5, 7, True);
      end;
    'inserttable':
      begin
        P.Box(1.5, 2.5, 14.5, 13.5);
        P.Line(1.5, 6.2, 14.5, 6.2);
        P.Line(1.5, 9.8, 14.5, 9.8);
        P.Line(5.8, 2.5, 5.8, 13.5);
        P.Line(10.2, 2.5, 10.2, 13.5);
      end;
    'insertlink':
      begin
        { two links of a chain }
        P.Width(1.6);
        P.Poly([7, 5, 4, 2, 1.5, 4.5, 4.5, 7.5]);
        P.Poly([9, 11, 12, 14, 14.5, 11.5, 11.5, 8.5]);
        P.Line(5.5, 10.5, 10.5, 5.5);
        P.Width(1.2);
      end;
    'insertbreak':
      begin
        P.Poly([3.5, 1.5, 12.5, 1.5, 12.5, 5.5]);
        P.Line(3.5, 1.5, 3.5, 5.5);
        P.C.Pen.Style := psDot;
        P.Line(1, 8, 15, 8);
        P.C.Pen.Style := psSolid;
        P.Poly([3.5, 10.5, 3.5, 14.5, 12.5, 14.5, 12.5, 10.5]);
      end;
    'insertequation':
      { a summation sign }
      P.Poly([12.5, 3.5, 12.5, 1.5, 3, 1.5, 8.5, 8, 3, 14.5, 12.5, 14.5, 12.5, 12.5]);
    'insertnote':
      begin
        for i := 0 to 2 do
          P.Line(1.5, 2.5 + i * 3, 14.5, 2.5 + i * 3);
        P.Line(1.5, 11, 7, 11);
        P.Width(1);
        P.Line(2.5, 13, 2.5, 15.5);
        P.Line(5, 13.5, 13, 13.5);
        P.Width(1.2);
      end;
    'insertfield':
      begin
        P.Line(5.5, 2, 4, 14);
        P.Line(11.5, 2, 10, 14);
        P.Line(2, 5.5, 14, 5.5);
        P.Line(1.5, 10.5, 13.5, 10.5);
      end;
    'insertsymbol':
      { an omega }
      P.Poly([2, 14, 5.5, 14, 5.5, 12, 3, 9.5, 3, 5.5, 5.5, 2.5, 10.5, 2.5, 13, 5.5, 13, 9.5, 10.5, 12, 10.5, 14,
        14, 14]);
    'highlight':
      begin
        P.Poly([4, 10, 10, 2, 13.5, 5, 7.5, 12.5, 4, 10]);
        P.Line(4, 10, 3, 12);
        P.Colour(clYellow);
        P.Box(1.5, 12.5, 14.5, 15, True);
        P.Colour(AColour);
      end;
  end;
end;

var
  FGlyph: TBitmap = nil;

function LedIconArtworkBitmap(const AName: string; ASize: Integer): TBitmap;
var
  Art: string;
begin
  Result := nil;
  if ASize < 1 then ASize := 16;
  Art := LedIconArtwork(AName);
  if Art <> '' then
    Result := LoadIconArtwork(Art, ASize);
end;

function LedIconBitmap(const AName: string; AColour: TColor;
  ASize: Integer): TBitmap;
var
  Art: string;
  Bmp: TBitmap;
begin
  if ASize < 1 then ASize := 16;

  { **Artwork first, here as well as in the image list.**

    This is what a TSpeedButton's Glyph is made from -- the file browser's
    navigation row, the rail buttons -- and it used to draw the line
    version whatever was in data/icons.  So the toolbar showed the painted
    Back arrow and the file list, an inch below it, showed a drawn one:
    two programs in one window.  The set now has every one of those
    glyphs, so there is nothing left to be gained by the difference. }
  Art := LedIconArtwork(AName);
  if Art <> '' then
  begin
    Bmp := LoadIconArtwork(Art, ASize);
    if Bmp <> nil then
    begin
      { The one-bitmap rule the drawn path below keeps: the caller copies
        out of what it is handed, so only one is alive at a time. }
      FGlyph.Free;
      FGlyph := Bmp;
      Exit(FGlyph);
    end;
  end;
  { One bitmap reused for every call: Glyph.Assign copies, so nothing outside
    keeps a reference, and this avoids leaking one per button.  Resized when
    the caller asks for a different size, which on a scaled display it does.
    This was fixed at sixteen, so the file browser's navigation buttons grew
    with the rest of the pane and kept a sixteen-pixel glyph rattling about
    inside them. }
  { A buffer left over from the artwork path above is 32-bit with an alpha
    channel; the masked drawing below wants a plain 24-bit one. }
  if (FGlyph <> nil) and (FGlyph.PixelFormat <> pf24bit) then
    FreeAndNil(FGlyph);
  if FGlyph = nil then
  begin
    FGlyph := TBitmap.Create;
    FGlyph.PixelFormat := pf24bit;
  end;
  if (FGlyph.Width <> ASize) or (FGlyph.Height <> ASize) then
    FGlyph.SetSize(ASize, ASize);
  FGlyph.Canvas.Brush.Color := MaskColour;
  FGlyph.Canvas.Brush.Style := bsSolid;
  FGlyph.Canvas.FillRect(0, 0, ASize, ASize);
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
  Art: string;
  i: Integer;
begin
  Result := AImages;
  AImages.Clear;
  for i := 0 to High(ANames) do
  begin
    { Artwork first, where there is any: it carries its own colours and its
      own alpha, so it goes in whole rather than through the mask below. }
    Art := LedIconArtwork(ANames[i]);
    if Art <> '' then
    begin
      Bmp := LoadIconArtwork(Art, AImages.Width);
      if Bmp <> nil then
        try
          AImages.Add(Bmp, nil);
          Continue;
        finally
          Bmp.Free;
        end;
    end;

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

      { A file kind is drawn in its own colour; everything else takes the
        one the caller asked for, so a toolbar stays one ink. }
      if LedIconAccent(ANames[i]) <> clNone then
        LedDrawIcon(Bmp, ANames[i], LedIconAccent(ANames[i]))
      else
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
