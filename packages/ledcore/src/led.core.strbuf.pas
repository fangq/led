// led - a lightweight editor.  Building a long string without building it
// again for every piece.
//
// Pascal's "Result := Result + X" allocates a new string of the whole length
// each time, so a loop that appends a thousand pieces copies the whole thing
// a thousand times.  On the short strings most of LED handles that is
// invisible.  On a document it is not: the Markdown preview's page builder
// worked that way and took 16 seconds for half a megabyte, four times as
// long for each doubling -- 32 KiB in a tenth of a second, 2 MB in four
// minutes, which is what "the preview never appears on a big file" was.
//
// The same shape of mistake, in the same function, was scanning: it lowered
// the case of the entire document once per match to search it
// case-insensitively.  LedFindCI answers the same question without
// allocating anything, which is why it is here too.

unit Led.Core.StrBuf;

{$mode objfpc}{$H+}{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils;

type
  { An append-only string with room to grow.

    A record rather than a class: it is used in tight loops inside one
    function, and an object to allocate and free would be the kind of cost
    this exists to avoid. }
  TLedStrBuf = record
  private
    FData: string;
    FLen: Integer;
    procedure Need(AMore: Integer);
  public
    { ACapacity is a guess at the final size; getting it wrong costs a
      doubling or two, not correctness.  For a page built from a document,
      the document's own length is a good guess. }
    procedure Init(ACapacity: Integer = 0);
    procedure Add(const AText: string);
    procedure AddChar(AChar: AnsiChar);
    { ALen characters of ASource from AFrom, without the intermediate string
      a Copy would make. }
    procedure AddSlice(const ASource: string; AFrom, ALen: Integer);
    { What has been built.  Trims the spare room, so the result is an
      ordinary string of exactly the right length. }
    function Text: string;
    function Len: Integer;
  end;

{ Where ANeedle appears in AHaystack at or after AFrom, ignoring case, or 0.

  ANeedle must be lower case.  Nothing is allocated: the alternative --
  lowering the case of the haystack to search it -- copies the whole
  haystack, and doing that once per match is how a linear pass becomes a
  quadratic one. }
function LedFindCI(const AHaystack, ANeedle: string; AFrom: Integer): Integer;

{ Whether AHaystack has ANeedle (lower case) at exactly AAt, ignoring case. }
function LedSameCI(const AHaystack: string; AAt: Integer;
  const ANeedle: string): Boolean;

implementation

procedure TLedStrBuf.Need(AMore: Integer);
var
  Want: Integer;
begin
  Want := FLen + AMore;
  if Want <= Length(FData) then Exit;
  { Doubling, so a string built in n pieces is copied log(n) times rather
    than n times. }
  Want := Want * 2;
  if Want < 256 then Want := 256;
  SetLength(FData, Want);
end;

procedure TLedStrBuf.Init(ACapacity: Integer);
begin
  FLen := 0;
  FData := '';
  if ACapacity > 0 then SetLength(FData, ACapacity);
end;

procedure TLedStrBuf.Add(const AText: string);
begin
  if AText = '' then Exit;
  Need(Length(AText));
  Move(AText[1], FData[FLen + 1], Length(AText));
  Inc(FLen, Length(AText));
end;

procedure TLedStrBuf.AddChar(AChar: AnsiChar);
begin
  Need(1);
  FData[FLen + 1] := AChar;
  Inc(FLen);
end;

procedure TLedStrBuf.AddSlice(const ASource: string; AFrom, ALen: Integer);
begin
  if ALen <= 0 then Exit;
  if AFrom < 1 then Exit;
  if AFrom + ALen - 1 > Length(ASource) then
    ALen := Length(ASource) - AFrom + 1;
  if ALen <= 0 then Exit;
  Need(ALen);
  Move(ASource[AFrom], FData[FLen + 1], ALen);
  Inc(FLen, ALen);
end;

function TLedStrBuf.Len: Integer;
begin
  Result := FLen;
end;

function TLedStrBuf.Text: string;
begin
  SetLength(FData, FLen);
  Result := FData;
end;

function LedSameCI(const AHaystack: string; AAt: Integer;
  const ANeedle: string): Boolean;
var
  i: Integer;
  C: AnsiChar;
begin
  Result := False;
  if AAt < 1 then Exit;
  if AAt + Length(ANeedle) - 1 > Length(AHaystack) then Exit;
  for i := 1 to Length(ANeedle) do
  begin
    C := AHaystack[AAt + i - 1];
    if (C >= 'A') and (C <= 'Z') then Inc(C, Ord('a') - Ord('A'));
    if C <> ANeedle[i] then Exit;
  end;
  Result := True;
end;

function LedFindCI(const AHaystack, ANeedle: string; AFrom: Integer): Integer;
var
  i, Last: Integer;
  First: AnsiChar;
  C: AnsiChar;
begin
  Result := 0;
  if (ANeedle = '') or (AHaystack = '') then Exit;
  if AFrom < 1 then AFrom := 1;
  Last := Length(AHaystack) - Length(ANeedle) + 1;
  First := ANeedle[1];
  for i := AFrom to Last do
  begin
    { The first character is checked here rather than in LedSameCI: it is the
      one that decides nearly every position, and a call per position is
      most of the work otherwise. }
    C := AHaystack[i];
    if (C >= 'A') and (C <= 'Z') then Inc(C, Ord('a') - Ord('A'));
    if C <> First then Continue;
    if LedSameCI(AHaystack, i, ANeedle) then Exit(i);
  end;
end;

end.
