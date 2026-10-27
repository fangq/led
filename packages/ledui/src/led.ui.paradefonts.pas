{ LED - a lightweight editor.  The fonts a Parade view is given.

  Parade reads font files itself rather than asking the desktop, so every
  view built on it has to be told where this system keeps its faces.  Two
  views now need that -- the visual editor and the Markdown preview -- and
  the list of places to look is the part that differs between distributions
  and between platforms, which makes it exactly the part that must not be
  kept twice.

  Built without Parade, nothing here is compiled and nothing refers to it;
  see Led.UI.Visual for what the stub include does. }
unit Led.UI.ParadeFonts;

{$mode objfpc}{$H+}
{$I led.parade.inc}

interface

{$IFDEF LED_PARADE}
uses
  Classes, SysUtils, paradeedit;

{ Registers the text, code and maths faces this system has with AEdit.

  AWithSystemFamilies adds every other installed family by name as well,
  which is what a font list is picked from.  A view with no font list
  does not want them: Parade resolves a family by walking the faces it
  has been given, once per run of text, so a few hundred registered
  families are paid for on every layout.  Measured on a 110 KB document
  at a 800 pixel pane, one width change: 12 ms with the faces below, 34
  with every family this machine has. }
procedure LedParadeAddFonts(AEdit: TParadeEdit;
  AWithSystemFamilies: Boolean = True);

{ The faces to fall back to for a character the text's own font does not
  have -- a superscript, an arrow, a Chinese character -- as files, in
  the order to try them.  Parade has a list of families it looks for
  (TParadeEdit.UseFallbackFonts) but builds its chain once, before a
  view has registered anything, and only AddSystemFonts makes it look
  again; a view that does not want that list hands the chain to its
  document itself.  Empty on a system whose fonts are not where this
  knows to look. }
procedure LedParadeFallbackFiles(AList: TStrings);
{$ENDIF}

implementation

{$IFDEF LED_PARADE}

procedure LedParadeFallbackFiles(AList: TStrings);

  { the first of these that is on this system, under the name Parade's
    own chain looks for }
  procedure Face(const AFamily: string; const APaths: array of string);
  var
    i: Integer;
  begin
    for i := 0 to High(APaths) do
      if FileExists(APaths[i]) then
      begin
        AList.Add(AFamily + '=' + APaths[i]);
        Exit;
      end;
  end;

begin
  AList.Clear;
  {$IF DEFINED(WINDOWS) OR DEFINED(DARWIN)}
  { Nothing named here yet: these two keep their coverage fonts under
    names of their own, so a view on them registers the whole system
    list instead and takes Parade's own chain. }
  {$ELSE}
  Face('DejaVu Sans',
    ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
     '/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf',
     '/usr/share/fonts/dejavu/DejaVuSans.ttf']);
  Face('Noto Sans Symbols2',
    ['/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf',
     '/usr/share/fonts/google-noto/NotoSansSymbols2-Regular.ttf']);
  Face('Noto Sans Symbols',
    ['/usr/share/fonts/truetype/noto/NotoSansSymbols-Regular.ttf',
     '/usr/share/fonts/google-noto/NotoSansSymbols-Regular.ttf']);
  Face('Noto Sans CJK SC',
    ['/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
     '/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf',
     '/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc']);
  Face('WenQuanYi Micro Hei',
    ['/usr/share/fonts/truetype/wqy/wqy-microhei.ttc',
     '/usr/share/fonts/wenquanyi/wqy-microhei/wqy-microhei.ttc']);
  Face('Droid Sans Fallback',
    ['/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf',
     '/usr/share/fonts/truetype/droid/DroidSansFallback.ttf']);
  Face('FreeSerif',
    ['/usr/share/fonts/truetype/freefont/FreeSerif.ttf',
     '/usr/share/fonts/gnu-free/FreeSerif.ttf']);
  {$ENDIF}
end;

{ A serif and a sans for the text, a monospace for code, a math font for
  equations -- wherever this system keeps them.  Parade reads TrueType and
  OpenType files itself rather than asking the desktop, so it has to be told
  where they are.

  The serif comes first: it is what a document that names no font is set
  in.  A document that names a font this does not have -- Arial, Times New
  Roman -- gets a registered face of the same kind (pd_font_family_class),
  and the Liberation faces are the metric twins of those two, so the lines
  break where Word broke them.  Calibri and Cambria, the Office defaults,
  have twins of their own, Carlito and Caladea, registered under the names
  documents ask for. }
procedure LedParadeAddFonts(AEdit: TParadeEdit;
  AWithSystemFamilies: Boolean);
type
  TFace = record
    Group, Family, Dir, Regular, Bold, Italic, BoldItalic: string;
  end;

const
  Groups: array[0..3] of string = ('serif', 'sans', 'calibri', 'cambria');
var
  Faces: array of TFace;
  Monos, Maths: array of string;
  g, i: Integer;

  procedure Face(const AGroup, AFamily, ADir, AR, AB, AI, ABI: string);
  begin
    SetLength(Faces, Length(Faces) + 1);
    with Faces[High(Faces)] do
    begin
      Group := AGroup;
      Family := AFamily;
      Dir := IncludeTrailingPathDelimiter(ADir);
      Regular := AR;
      Bold := AB;
      Italic := AI;
      BoldItalic := ABI;
    end;
  end;

  procedure Add(const AFamily, AFile: string; AWeight: Integer; AItalic: Boolean);
  begin
    if FileExists(AFile) then
      AEdit.AddFont(AFamily, AFile, AWeight, AItalic);
  end;

var
  Win: string;
  Covered: Integer;
  Cover: TStringList;
begin
  Faces := nil;
  {$IFDEF WINDOWS}
  Win := GetEnvironmentVariable('WINDIR');
  if Win = '' then Win := 'C:\Windows';
  Win := Win + '\Fonts';
  Face('serif', 'Times New Roman', Win, 'times.ttf', 'timesbd.ttf', 'timesi.ttf', 'timesbi.ttf');
  Face('sans', 'Arial', Win, 'arial.ttf', 'arialbd.ttf', 'ariali.ttf', 'arialbi.ttf');
  Face('calibri', 'Calibri', Win, 'calibri.ttf', 'calibrib.ttf', 'calibrii.ttf', 'calibriz.ttf');
  Monos := [Win + '\consola.ttf', Win + '\cour.ttf'];
  Maths := [];
  {$ELSE}
  {$IFDEF DARWIN}
  Win := '/System/Library/Fonts/Supplemental';
  Face('serif', 'Times New Roman', Win, 'Times New Roman.ttf', 'Times New Roman Bold.ttf',
    'Times New Roman Italic.ttf', 'Times New Roman Bold Italic.ttf');
  Face('sans', 'Arial', Win, 'Arial.ttf', 'Arial Bold.ttf', 'Arial Italic.ttf',
    'Arial Bold Italic.ttf');
  Monos := [Win + '/Courier New.ttf'];
  Maths := [];
  {$ELSE}
  Win := '/usr/share/fonts/';
  Face('serif', 'Liberation Serif', Win + 'truetype/liberation', 'LiberationSerif-Regular.ttf',
    'LiberationSerif-Bold.ttf', 'LiberationSerif-Italic.ttf', 'LiberationSerif-BoldItalic.ttf');
  Face('serif', 'Liberation Serif', Win + 'liberation-serif', 'LiberationSerif-Regular.ttf',
    'LiberationSerif-Bold.ttf', 'LiberationSerif-Italic.ttf', 'LiberationSerif-BoldItalic.ttf');
  Face('serif', 'DejaVu Serif', Win + 'truetype/dejavu', 'DejaVuSerif.ttf',
    'DejaVuSerif-Bold.ttf', 'DejaVuSerif-Italic.ttf', 'DejaVuSerif-BoldItalic.ttf');
  Face('serif', 'DejaVu Serif', Win + 'dejavu-serif-fonts', 'DejaVuSerif.ttf',
    'DejaVuSerif-Bold.ttf', 'DejaVuSerif-Italic.ttf', 'DejaVuSerif-BoldItalic.ttf');
  Face('sans', 'Liberation Sans', Win + 'truetype/liberation', 'LiberationSans-Regular.ttf',
    'LiberationSans-Bold.ttf', 'LiberationSans-Italic.ttf', 'LiberationSans-BoldItalic.ttf');
  Face('sans', 'Liberation Sans', Win + 'liberation-sans', 'LiberationSans-Regular.ttf',
    'LiberationSans-Bold.ttf', 'LiberationSans-Italic.ttf', 'LiberationSans-BoldItalic.ttf');
  Face('sans', 'DejaVu Sans', Win + 'truetype/dejavu', 'DejaVuSans.ttf',
    'DejaVuSans-Bold.ttf', 'DejaVuSans-Oblique.ttf', 'DejaVuSans-BoldOblique.ttf');
  Face('calibri', 'Calibri', Win + 'truetype/crosextra', 'Carlito-Regular.ttf',
    'Carlito-Bold.ttf', 'Carlito-Italic.ttf', 'Carlito-BoldItalic.ttf');
  Face('cambria', 'Cambria', Win + 'truetype/crosextra', 'Caladea-Regular.ttf',
    'Caladea-Bold.ttf', 'Caladea-Italic.ttf', 'Caladea-BoldItalic.ttf');
  Monos := [Win + 'truetype/dejavu/DejaVuSansMono.ttf',
    Win + 'dejavu-sans-mono-fonts/DejaVuSansMono.ttf',
    Win + 'truetype/liberation/LiberationMono-Regular.ttf'];
  Maths := ['/usr/share/texmf/fonts/opentype/public/lm-math/latinmodern-math.otf',
    '/usr/share/fonts/opentype/lmodern/latinmodern-math.otf',
    '/usr/share/texlive/texmf-dist/fonts/opentype/public/lm-math/latinmodern-math.otf'];
  {$ENDIF}
  {$ENDIF}

  { One family per group: the first one that is there, serif first. }
  for g := Low(Groups) to High(Groups) do
    for i := 0 to High(Faces) do
      with Faces[i] do
        if (Group = Groups[g]) and FileExists(Dir + Regular) then
        begin
          Add(Family, Dir + Regular, 400, False);
          Add(Family, Dir + Bold, 700, False);
          Add(Family, Dir + Italic, 400, True);
          Add(Family, Dir + BoldItalic, 700, True);
          Break;
        end;
  { and the two text groups under the names a reader's preference uses
    for them -- Sans, Serif -- which are not families any font file
    carries.  Resolution is by name, so for Sans to mean the sans there
    has to be a family called that. }
  for g := Low(Groups) to High(Groups) do
    if (Groups[g] = 'serif') or (Groups[g] = 'sans') then
      for i := 0 to High(Faces) do
        with Faces[i] do
          if (Group = Groups[g]) and FileExists(Dir + Regular) then
          begin
            Add(Groups[g], Dir + Regular, 400, False);
            Add(Groups[g], Dir + Bold, 700, False);
            Add(Groups[g], Dir + Italic, 400, True);
            Add(Groups[g], Dir + BoldItalic, 700, True);
            Break;
          end;
  for i := 0 to High(Monos) do
    if FileExists(Monos[i]) then
    begin
      AEdit.AddFont('monospace', Monos[i]);
      Break;
    end;
  for i := 0 to High(Maths) do
    if FileExists(Maths[i]) then
    begin
      AEdit.SetMathFont(Maths[i]);
      Break;
    end;
  { The faces a character outside the body font falls back to, by the
    names Parade knows them by, so that a document naming one of them
    gets it as well.  The fallback chain itself is set from the same
    files -- see LedParadeFallbackFiles. }
  Cover := TStringList.Create;
  try
    LedParadeFallbackFiles(Cover);
    for i := 0 to Cover.Count - 1 do
      AEdit.AddFontFile(Cover.Names[i], Cover.ValueFromIndex[i]);
    Covered := Cover.Count;
  finally
    Cover.Free;
  end;

  { and every other font installed, for the font list: loaded when text
    first uses one.  Also when none of the fallback faces could be found
    by name -- a platform this does not know its way around is better
    slow than full of boxes. }
  if AWithSystemFamilies or (Covered = 0) then
    AEdit.AddSystemFonts;
end;
{$ENDIF}

end.
