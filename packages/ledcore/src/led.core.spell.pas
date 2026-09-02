{ led - a light editor.  Spell checking, over a shipped word list.

  Deliberately not Hunspell.  Hunspell is C++, so using it means shipping
  libhunspell.dll on Windows and a .dylib inside the macOS bundle -- and on
  macOS that second binary has to be signed and notarized alongside the app.
  That is more ongoing work than this file, on every release, forever.  A
  word list is data: it goes in data/, which all four package formats already
  carry, and the code is identical on every platform.

  What is lost is morphology.  Hunspell derives forms from affix rules, so it
  knows words nobody listed; this knows exactly the 104,334 forms in the
  list.  For an editor -- code, comments, commit messages, Markdown -- that
  is a small loss, and it is the honest trade for a single self-contained
  binary.

  The list is SCOWL (Spell Checker Oriented Word Lists), Kevin Atkinson's
  collective work, under terms that permit redistribution and sale; see
  data/dict/en_US.COPYRIGHT, which ships beside it and must keep doing so.

  No LCL dependency: this is in ledcore so it can be tested headlessly. }
unit Led.Core.Spell;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TLedSpell = class
  private
    { Sorted for binary search.  One allocation per word is wasteful in
      principle, but 104k short strings cost a few megabytes and load in
      well under a tenth of a second, which is cheaper than any scheme that
      would need its own file format. }
    FWords: TStringList;
    FUser: TStringList;        // the user's own additions, persisted
    FIgnored: TStringList;     // this session only
    FUserFile: string;
    FLoaded: Boolean;
    function Known(const AWord: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    { Reads the shipped list.  Returns False when it is missing, in which
      case Check says everything is spelled correctly -- a spell checker with
      no dictionary must not underline the whole document. }
    function LoadDictionary(const AFileName: string): Boolean;

    { The user's additions.  Created on first Add. }
    procedure LoadUserDictionary(const AFileName: string);
    procedure SaveUserDictionary;

    { True when AWord is spelled correctly, or is not the kind of token worth
      checking at all. }
    function Check(const AWord: string): Boolean;

    { True when AWord is a word rather than a number, a hex literal, an
      identifier with digits in it, and so on.  Public because the markup
      needs the same rule when it decides what to underline. }
    class function Checkable(const AWord: string): Boolean;

    { Up to AMax corrections, nearest first. }
    procedure Suggest(const AWord: string; AResult: TStrings;
      AMax: Integer = 8);

    procedure Add(const AWord: string);      // to the user dictionary
    procedure Ignore(const AWord: string);   // for this session

    property Loaded: Boolean read FLoaded;
    function WordCount: Integer;
  end;

{ The process-wide checker, loaded on first use. }
function LedSpell: TLedSpell;

implementation

uses
  Led.Core.Paths;

constructor TLedSpell.Create;
begin
  inherited Create;
  FWords := TStringList.Create;
  FWords.Sorted := True;
  FWords.Duplicates := dupIgnore;
  { Case-sensitive on purpose: the list distinguishes "Paris" from "paris",
    and Check below decides deliberately which of those to accept. }
  FWords.CaseSensitive := True;

  FUser := TStringList.Create;
  FUser.Sorted := True;
  FUser.Duplicates := dupIgnore;
  FUser.CaseSensitive := True;

  FIgnored := TStringList.Create;
  FIgnored.Sorted := True;
  FIgnored.Duplicates := dupIgnore;
  FIgnored.CaseSensitive := True;
end;

destructor TLedSpell.Destroy;
begin
  FWords.Free;
  FUser.Free;
  FIgnored.Free;
  inherited Destroy;
end;

function TLedSpell.WordCount: Integer;
begin
  Result := FWords.Count;
end;

function TLedSpell.LoadDictionary(const AFileName: string): Boolean;
begin
  Result := False;
  FLoaded := False;
  if not FileExists(AFileName) then Exit;
  try
    { The file is already sorted, but Sorted := True on a populated list
      re-sorts it, and LoadFromFile on a sorted list inserts one at a time.
      Filling it unsorted and sorting once is markedly faster. }
    FWords.Sorted := False;
    FWords.LoadFromFile(AFileName);
    FWords.Sorted := True;
  except
    FWords.Clear;
    FWords.Sorted := True;
    Exit;
  end;
  FLoaded := FWords.Count > 0;
  Result := FLoaded;
end;

procedure TLedSpell.LoadUserDictionary(const AFileName: string);
begin
  FUserFile := AFileName;
  FUser.Clear;
  if not FileExists(AFileName) then Exit;
  try
    FUser.Sorted := False;
    FUser.LoadFromFile(AFileName);
    FUser.Sorted := True;
  except
    FUser.Clear;
    FUser.Sorted := True;
  end;
end;

procedure TLedSpell.SaveUserDictionary;
begin
  if FUserFile = '' then Exit;
  try
    LedWriteFileAtomic(FUserFile, FUser.Text);
  except
    { A dictionary that cannot be written is not worth an error dialog in
      the middle of typing; the words survive for the session. }
  end;
end;

class function TLedSpell.Checkable(const AWord: string): Boolean;
var
  i: Integer;
  HasLetter: Boolean;
begin
  Result := False;
  { One and two letter words carry no information about spelling and are
    mostly initials and units. }
  if Length(AWord) < 3 then Exit;

  HasLetter := False;
  for i := 1 to Length(AWord) do
  begin
    case AWord[i] of
      'a'..'z', 'A'..'Z': HasLetter := True;
      '0'..'9': Exit;          // 3rd, x86, sha1 -- not prose
      '''': ;                  // possessives and contractions are words
    else
      { Anything else -- underscores, dots, slashes -- means this is an
        identifier or a path, not a word.  Non-ASCII letters land here too,
        which is a limitation of an ASCII list and is why they are skipped
        rather than reported as errors. }
      Exit;
    end;
  end;
  Result := HasLetter;
end;

function TLedSpell.Known(const AWord: string): Boolean;
begin
  Result := (FWords.IndexOf(AWord) >= 0) or (FUser.IndexOf(AWord) >= 0) or
            (FIgnored.IndexOf(AWord) >= 0);
end;

function TLedSpell.Check(const AWord: string): Boolean;
var
  Lower: string;
begin
  { With no dictionary, everything is correct.  Underlining an entire
    document because a data file is missing would be worse than not
    checking. }
  if not FLoaded then Exit(True);
  if not Checkable(AWord) then Exit(True);

  if Known(AWord) then Exit(True);

  { "The" at the start of a sentence, or "HOUSE" in a heading, are both the
    listed lower-case word.  The reverse is not true: "paris" is not
    accepted just because "Paris" is listed, because that is exactly the
    mistake worth catching. }
  Lower := LowerCase(AWord);
  if Lower <> AWord then
    if Known(Lower) then Exit(True);

  Result := False;
end;

{ Damerau-Levenshtein, bounded.  Returns AMax + 1 as soon as the answer is
  known to exceed AMax, which is what makes scanning a hundred thousand words
  affordable. }
function EditDistance(const A, B: string; AMax: Integer): Integer;
var
  Prev, Curr, Prev2: array of Integer;
  i, j, Cost, Best, BestPrev: Integer;
begin
  if Abs(Length(A) - Length(B)) > AMax then Exit(AMax + 1);
  SetLength(Prev, Length(B) + 1);
  SetLength(Curr, Length(B) + 1);
  SetLength(Prev2, Length(B) + 1);

  for j := 0 to Length(B) do Prev[j] := j;
  BestPrev := 0;

  for i := 1 to Length(A) do
  begin
    Curr[0] := i;
    Best := Curr[0];
    for j := 1 to Length(B) do
    begin
      if A[i] = B[j] then Cost := 0 else Cost := 1;
      Curr[j] := Prev[j] + 1;
      if Curr[j - 1] + 1 < Curr[j] then Curr[j] := Curr[j - 1] + 1;
      if Prev[j - 1] + Cost < Curr[j] then Curr[j] := Prev[j - 1] + Cost;
      { The transposition case: "teh" -> "the" is one edit, not two. }
      if (i > 1) and (j > 1) and (A[i] = B[j - 1]) and (A[i - 1] = B[j]) then
        if Prev2[j - 2] + 1 < Curr[j] then Curr[j] := Prev2[j - 2] + 1;
      if Curr[j] < Best then Best := Curr[j];
    end;
    { Abandoning as soon as one row exceeds AMax is the usual pruning, and it
      is wrong here: a transposition reaches back two rows, so a row can be
      entirely above the bound while the answer is still under it.  "teh" ->
      "the" is exactly that -- row 2 has minimum 2, and the distance is 1.
      Both of the last two rows have to exceed the bound before there is no
      way back. }
    if (Best > AMax) and (BestPrev > AMax) then Exit(AMax + 1);
    BestPrev := Best;
    Prev2 := Copy(Prev, 0, Length(Prev));
    Prev := Copy(Curr, 0, Length(Curr));
  end;
  Result := Prev[Length(B)];
end;

procedure TLedSpell.Suggest(const AWord: string; AResult: TStrings;
  AMax: Integer);
var
  Lower, Cand: string;
  i, D, Limit: Integer;
  Found: TStringList;

  procedure Consider(AList: TStringList);
  var
    k, Dist, Rank: Integer;
    W: string;
  begin
    for k := 0 to AList.Count - 1 do
    begin
      W := AList[k];
      if Abs(Length(W) - Length(Lower)) > Limit then Continue;
      { The cheapest useful filter: a correction almost never changes the
        first letter, and this removes 96% of the list before any distance
        is computed. }
      if (W <> '') and (LowerCase(W[1]) <> Lower[1]) then Continue;
      Dist := EditDistance(Lower, LowerCase(W), Limit);
      if Dist > Limit then Continue;

      { Rank: nearest first; then ordinary words ahead of proper nouns,
        because a lower-case typo is far more often a lower-case word than a
        name; then the closest length; then alphabetically so the order is
        reproducible.  An earlier version tie-broke on the word's index in
        the list, which is arbitrary -- and with only eight suggestions kept,
        arbitrary meant "the" lost its place to "Ted", "TeX" and "Tet". }
      if (W <> '') and (W[1] >= 'A') and (W[1] <= 'Z') then Rank := 1
      else Rank := 0;
      Found.Add(Format('%d%d%.3d%s',
        [Dist, Rank, Abs(Length(W) - Length(Lower)), W]));
    end;
  end;

begin
  AResult.Clear;
  if (not FLoaded) or (AWord = '') then Exit;
  Lower := LowerCase(AWord);
  { One edit for short words, two for longer ones: at distance two a
    four-letter word can become almost anything. }
  if Length(Lower) <= 4 then Limit := 1 else Limit := 2;

  Found := TStringList.Create;
  try
    Found.Sorted := True;         // sorts by the distance prefix
    Found.Duplicates := dupIgnore;
    Consider(FWords);
    Consider(FUser);
    for i := 0 to Found.Count - 1 do
    begin
      if AResult.Count >= AMax then Break;
      Cand := Copy(Found[i], 6, MaxInt);
      { Give back a suggestion shaped like what was typed. }
      if (AWord[1] >= 'A') and (AWord[1] <= 'Z') and (Cand <> '') then
        Cand[1] := UpCase(Cand[1]);
      if AResult.IndexOf(Cand) < 0 then AResult.Add(Cand);
    end;
  finally
    Found.Free;
  end;
end;

procedure TLedSpell.Add(const AWord: string);
begin
  if AWord = '' then Exit;
  FUser.Add(AWord);
  SaveUserDictionary;
end;

procedure TLedSpell.Ignore(const AWord: string);
begin
  if AWord <> '' then FIgnored.Add(AWord);
end;

var
  FSpell: TLedSpell = nil;

function LedSpell: TLedSpell;
begin
  if FSpell = nil then
  begin
    FSpell := TLedSpell.Create;
    FSpell.LoadDictionary(LedDataDir + 'dict' + PathDelim + 'en_US.txt');
    FSpell.LoadUserDictionary(LedConfigFile('user-dictionary.txt'));
  end;
  Result := FSpell;
end;

finalization
  FSpell.Free;

end.
