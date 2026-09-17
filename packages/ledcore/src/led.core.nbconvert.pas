// led - a lightweight editor.  Pictures the LCL cannot draw, turned into ones
// it can.
//
// Two formats keep turning up in notebooks and the LCL draws neither.  SVG:
// every badge at the top of a README is one, and matplotlib writes SVG when
// the notebook asks it to.  WebP: the format the picture-hosting sites now
// serve.  Both were fetched, recognised as undrawable, and replaced by a line
// saying so -- which is the truth but not much use to somebody reading a page
// of a lecture.
//
// A decoder for either in Pascal is a large piece of work.  Every desktop
// that can show them already has a program that converts them, though --
// rsvg-convert, dwebp, ImageMagick -- so LED asks whichever one is there, the
// same arrangement it uses for a Jupyter kernel and for gdb.  Where the
// machine has none, nothing happens and the reader gets the line saying what
// the picture is, exactly as before.
//
// Through files rather than pipes.  Feeding a converter on stdin and reading
// the result from stdout works, and deadlocks the day the output is bigger
// than a pipe buffer while the input still has not all been written.
// Temporary files cost a few milliseconds and cannot do that.

unit Led.Core.NBConvert;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, process;

{ What the bytes are, if they are something LED could have converted: 'svg',
  'webp', or '' for anything else -- including a picture the LCL can already
  draw, which does not come through here. }
function LedNBConvertKind(const ABytes: string): string;

{ The program LED would use for that kind, or '' when this machine has none.
  The full path, so a caller can say what it found. }
function LedNBConverterFor(const AKind: string): string;

{ ABytes as PNG.  False when the bytes are not a kind this converts, when the
  machine has no converter for them, or when the converter failed -- in every
  case the caller is no worse off than before. }
function LedNBToPng(const ABytes: string; out APng: string): Boolean;

{ ABytes as something the LCL can draw, converted only if it has to be.

  True when what is left is worth handing to a TPicture: either it never
  needed converting -- a PNG, a JPEG, anything this does not recognise -- or
  it has been converted, in which case ABytes and AMime are both replaced.
  False only for a picture that needed converting and could not be.

  For the pictures inside a notebook as well as the ones fetched for it: a
  cell that asked matplotlib for SVG has SVG in its outputs, and an
  attachment pasted into a prose cell can be anything at all. }
function LedNBMakeDrawable(var ABytes, AMime: string): Boolean;

{ How many times a converter has actually been run.

  A conversion is a process, and starting one costs more than the conversion
  itself -- measured on this machine, 41 milliseconds against the four the
  drawing takes -- so the answers are kept: the same picture is asked for
  again every time the cell holding it is drawn.  This is how a check can
  tell "converted once and drawn twenty times" from "converted twenty
  times", which a timing would only guess at. }
function LedNBConversions: Integer;

implementation

{ ---- conversions already done ----

  A converter is a process, and starting one costs more than the conversion:
  measured on this machine, about a seventh of a second for a badge that
  ImageMagick's own renderer turns round in four milliseconds.  That would be
  paid again every time the cell holding the picture came back on screen,
  which is what scrolling a notebook of SVG plots does.

  Keyed by a fingerprint of the bytes rather than by a name, because the
  callers have bytes: an attachment, a data: URI and an output all arrive
  without a file behind them.  The fingerprint is over the whole buffer, so
  two different pictures cannot share an entry.

  Bounded by what it holds, and cleared by nobody: a session's worth of
  converted pictures is a few megabytes, and the alternative -- working out
  when a picture can no longer be wanted -- is a harder question than it is
  worth. }
const
  ConvertCacheBytes = 32 * 1024 * 1024;

type
  { One converted picture.  An object hanging off the list rather than the
    value half of a name=value line: a PNG carries newlines, equals signs
    and NULs, and LED has already had one cache where putting binary in a
    value meant it could never be found again. }
  TLedNBBlob = class
  public
    Data: string;
  end;

var
  GDone: TStringList = nil;    { fingerprint -> TLedNBBlob }

function Fingerprint(const ABytes: string): string;
var
  i: Integer;
  H: QWord;
begin
  { FNV-1a over the whole buffer: half a millisecond for half a megabyte,
    against a seventh of a second for the process it saves. }
  H := QWord(14695981039346656037);
  for i := 1 to Length(ABytes) do
  begin
    H := H xor QWord(Ord(ABytes[i]));
    H := H * QWord(1099511628211);
  end;
  Result := IntToStr(Length(ABytes)) + ':' + IntToHex(H, 16);
end;

function CacheFind(const AKey: string; out APng: string): Boolean;
var
  i: Integer;
begin
  APng := '';
  Result := False;
  if GDone = nil then Exit;
  i := GDone.IndexOf(AKey);
  if i < 0 then Exit;
  APng := TLedNBBlob(GDone.Objects[i]).Data;
  Result := APng <> '';
end;

procedure CacheAdd(const AKey, APng: string);
var
  Held: Int64;
  i: Integer;
  Blob: TLedNBBlob;
begin
  if (AKey = '') or (APng = '') then Exit;
  if GDone = nil then
  begin
    GDone := TStringList.Create;
    GDone.OwnsObjects := True;
  end;
  if GDone.IndexOf(AKey) >= 0 then Exit;
  Blob := TLedNBBlob.Create;
  Blob.Data := APng;
  GDone.AddObject(AKey, Blob);

  Held := 0;
  for i := 0 to GDone.Count - 1 do
    Inc(Held, Length(TLedNBBlob(GDone.Objects[i]).Data));
  { The oldest go first, and one is always kept however big it is. }
  while (GDone.Count > 1) and (Held > ConvertCacheBytes) do
  begin
    Dec(Held, Length(TLedNBBlob(GDone.Objects[0]).Data));
    GDone.Delete(0);
  end;
end;

{ How long a converter is given.  A drawing that takes longer than this is
  one the reader is better off without: the fetching thread is waiting on it,
  and behind that the picture of the next cell.  Generous against what these
  actually cost -- milliseconds -- because the thing it is really protecting
  against is a converter that has decided to wait for something. }
const
  ConvertTimeoutMs = 10000;

var
  GRuns: Integer = 0;

function LedNBConversions: Integer;
begin
  Result := GRuns;
end;

function LedNBConvertKind(const ABytes: string): string;
var
  Head: string;
begin
  Result := '';
  if Length(ABytes) < 12 then Exit;
  if (Copy(ABytes, 1, 4) = 'RIFF') and (Copy(ABytes, 9, 4) = 'WEBP') then
    Exit('webp');
  { An SVG may open with the XML declaration, with a comment, or with the tag
    itself, so the tag is looked for in the first few hundred bytes rather
    than at the front. }
  Head := LowerCase(Copy(ABytes, 1, 400));
  if (Pos('<svg', Head) > 0) and (Pos('<html', Head) = 0) then Exit('svg');
end;

type
  TConverter = record
    Kind: string;        { what it converts }
    Tool: string;        { the program }
    Args: string;        { its arguments, with %in and %out standing in }
  end;

const
  { In the order they are tried: the single-purpose ones first, because they
    are smaller, faster and likelier to be right about their own format, and
    ImageMagick after them because it can do both.

    "msvg:" matters, and is the least obvious thing here.  Handed an SVG with
    no prefix, ImageMagick passes it to whatever it has configured as its SVG
    delegate -- on the machine this was written on, Inkscape, which took
    sixteen seconds to turn an eight-pixel square into a PNG and made the
    first version of this time out and give up.  "msvg:" is ImageMagick's own
    renderer: four milliseconds for the same drawing, and a badge or a plot
    is exactly what it does well.  rsvg-convert, where it is installed, is
    both quick and better, which is why it is first. }
  Converters: array[0..5] of TConverter = (
    (Kind: 'svg';  Tool: 'rsvg-convert'; Args: '-o|%out|%in'),
    (Kind: 'webp'; Tool: 'dwebp';        Args: '%in|-o|%out'),
    (Kind: 'svg';  Tool: 'convert';      Args: 'msvg:%in|png:%out'),
    (Kind: 'webp'; Tool: 'convert';      Args: '%in|png:%out'),
    { ImageMagick 7 renamed its own front end. }
    (Kind: 'svg';  Tool: 'magick';       Args: 'msvg:%in|png:%out'),
    (Kind: 'webp'; Tool: 'magick';       Args: '%in|png:%out')
  );

function Which(const ATool: string): string;
begin
  Result := ExeSearch(ATool, GetEnvironmentVariable('PATH'));
end;

function LedNBConverterFor(const AKind: string): string;
var
  i: Integer;
begin
  Result := '';
  if AKind = '' then Exit;
  for i := Low(Converters) to High(Converters) do
    if (Converters[i].Kind = AKind) or (Converters[i].Kind = '') then
    begin
      Result := Which(Converters[i].Tool);
      if Result <> '' then Exit;
    end;
end;

{ The arguments for the converter that was found, with the two file names
  put in. }
function ArgsFor(const APath, AKind, AIn, AOut: string): TStringList;
var
  i: Integer;
  Spec: string;
begin
  Result := TStringList.Create;
  Spec := '';
  for i := Low(Converters) to High(Converters) do
    if ((Converters[i].Kind = AKind) or (Converters[i].Kind = '')) and
       SameText(ExtractFileName(APath), Converters[i].Tool) then
    begin
      Spec := Converters[i].Args;
      Break;
    end;
  if Spec = '' then Exit;
  Result.Delimiter := '|';
  Result.StrictDelimiter := True;
  Result.DelimitedText := Spec;
  for i := 0 to Result.Count - 1 do
  begin
    Result[i] := StringReplace(Result[i], '%in', AIn, [rfReplaceAll]);
    Result[i] := StringReplace(Result[i], '%out', AOut, [rfReplaceAll]);
  end;
end;

procedure WriteAll(const APath, AContent: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(APath, fmCreate);
  try
    if AContent <> '' then F.Write(AContent[1], Length(AContent));
  finally
    F.Free;
  end;
end;

function ReadAll(const APath: string): string;
var
  F: TFileStream;
begin
  Result := '';
  F := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.Read(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

function LedNBMakeDrawable(var ABytes, AMime: string): Boolean;
var
  Png: string;
begin
  Result := True;
  if LedNBConvertKind(ABytes) = '' then Exit;
  Result := LedNBToPng(ABytes, Png);
  if Result then
  begin
    ABytes := Png;
    AMime := 'image/png';
  end;
end;

function LedNBToPng(const ABytes: string; out APng: string): Boolean;
var
  Kind, Tool, InName, OutName, Key: string;
  Args: TStringList;
  P: TProcess;
  Waited: Integer;
begin
  Result := False;
  APng := '';
  Kind := LedNBConvertKind(ABytes);
  if Kind = '' then Exit;
  Tool := LedNBConverterFor(Kind);
  if Tool = '' then Exit;

  { Done before, most likely: the same picture is asked for again every time
    the cell holding it is drawn. }
  Key := Fingerprint(ABytes);
  if CacheFind(Key, APng) then Exit(True);

  InName := GetTempFileName('', 'led-pic-');
  { Named for what it is: ImageMagick reads the extension before it reads the
    bytes, and given none it has been known to guess wrongly. }
  RenameFile(InName, InName + '.' + Kind);
  InName := InName + '.' + Kind;
  OutName := InName + '.png';

  Args := ArgsFor(Tool, Kind, InName, OutName);
  P := TProcess.Create(nil);
  try
    if Args.Count = 0 then Exit;
    try
      WriteAll(InName, ABytes);
      P.Executable := Tool;
      P.Parameters.Assign(Args);
      { No window, no console, and nothing inherited: a converter that decided
        to ask a question would otherwise ask it of whatever the editor's own
        standard input happens to be. }
      P.Options := [poNoConsole, poUsePipes];
      Inc(GRuns);
      P.Execute;
      Waited := 0;
      while P.Running and (Waited < ConvertTimeoutMs) do
      begin
        Sleep(20);
        Inc(Waited, 20);
      end;
      if P.Running then
      begin
        P.Terminate(1);
        Exit;
      end;
      if P.ExitStatus <> 0 then Exit;
      if not FileExists(OutName) then Exit;
      APng := ReadAll(OutName);
      { Checked rather than trusted: a converter that writes an empty file or
        something that is not a PNG has not converted anything -- and is not
        worth keeping either. }
      Result := Copy(APng, 1, 8) = #$89'PNG'#13#10#26#10;
      if not Result then
        APng := ''
      else
        CacheAdd(Key, APng);
    except
      { A converter that is not there any more, a disk with nothing left on
        it: the picture is not shown and nothing else goes wrong. }
      on E: Exception do
      begin
        APng := '';
        Result := False;
      end;
    end;
  finally
    P.Free;
    Args.Free;
    DeleteFile(InName);
    DeleteFile(OutName);
  end;
end;

finalization
  GDone.Free;

end.
