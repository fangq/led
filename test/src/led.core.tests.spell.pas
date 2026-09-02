unit Led.Core.Tests.Spell;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Led.Core.Spell;

type
  TTestSpell = class(TTestCase)
  private
    FSpell: TLedSpell;
    function DictPath: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure DictionaryLoads;
    procedure KnownWordsPass;
    procedure MisspellingsFail;
    procedure SentenceCaseIsAccepted;
    procedure LowercasedProperNounIsNot;
    procedure NonWordsAreSkipped;
    procedure ContractionsAreWords;
    procedure SuggestsTheObviousCorrection;
    procedure SuggestsForATransposition;
    procedure UserWordsAreAccepted;
    procedure IgnoredWordsAreAccepted;
    procedure NoDictionaryMeansNoComplaints;
  end;

implementation

uses
  Led.Core.Paths;

function TTestSpell.DictPath: string;
begin
  Result := LedDataDir + 'dict' + PathDelim + 'en_US.txt';
end;

procedure TTestSpell.SetUp;
begin
  FSpell := TLedSpell.Create;
  FSpell.LoadDictionary(DictPath);
end;

procedure TTestSpell.TearDown;
begin
  FSpell.Free;
end;

procedure TTestSpell.DictionaryLoads;
begin
  AssertTrue('the shipped dictionary was found at ' + DictPath, FSpell.Loaded);
  AssertTrue('and holds a plausible number of words',
    FSpell.WordCount > 50000);
end;

procedure TTestSpell.KnownWordsPass;
begin
  AssertTrue('the', FSpell.Check('the'));
  AssertTrue('editor', FSpell.Check('editor'));
  AssertTrue('pseudo', FSpell.Check('pseudo'));
  AssertTrue('Paris', FSpell.Check('Paris'));
end;

procedure TTestSpell.MisspellingsFail;
begin
  AssertFalse('teh', FSpell.Check('teh'));
  AssertFalse('recieve', FSpell.Check('recieve'));
  AssertFalse('seperate', FSpell.Check('seperate'));
end;

procedure TTestSpell.SentenceCaseIsAccepted;
begin
  { "The" at the start of a sentence, "HOUSE" in a heading. }
  AssertTrue('The', FSpell.Check('The'));
  AssertTrue('HOUSE', FSpell.Check('HOUSE'));
end;

procedure TTestSpell.LowercasedProperNounIsNot;
begin
  { The reverse of the rule above, and the reason it is not symmetric:
    lower-casing a proper noun is exactly the mistake worth catching. }
  AssertFalse('paris', FSpell.Check('paris'));
end;

procedure TTestSpell.NonWordsAreSkipped;
begin
  { An editor is full of tokens that are not prose.  Complaining about them
    would make the feature unusable in code. }
  AssertTrue('x86', FSpell.Check('x86'));
  AssertTrue('sha1', FSpell.Check('sha1'));
  AssertTrue('foo_bar', FSpell.Check('foo_bar'));
  AssertTrue('a.b', FSpell.Check('a.b'));
  AssertTrue('short words', FSpell.Check('qq'));
end;

procedure TTestSpell.ContractionsAreWords;
begin
  AssertTrue('don''t is checkable', TLedSpell.Checkable('don''t'));
  AssertTrue('and known', FSpell.Check('don''t'));
end;

procedure TTestSpell.SuggestsTheObviousCorrection;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    FSpell.Suggest('recieve', L);
    AssertTrue('something was suggested for recieve', L.Count > 0);
    AssertTrue('and "receive" is among it', L.IndexOf('receive') >= 0);
  finally
    L.Free;
  end;
end;

procedure TTestSpell.SuggestsForATransposition;
var
  L: TStringList;
begin
  { "teh" -> "the" is one edit only if transposition counts as one, which is
    the difference between Damerau-Levenshtein and plain Levenshtein. }
  L := TStringList.Create;
  try
    FSpell.Suggest('teh', L);
    AssertTrue('"the" is suggested for "teh"; got [' +
      StringReplace(Trim(L.Text), LineEnding, ' ', [rfReplaceAll]) +
      '] count=' + IntToStr(L.Count), L.IndexOf('the') >= 0);
  finally
    L.Free;
  end;
end;

procedure TTestSpell.UserWordsAreAccepted;
begin
  AssertFalse('not known to begin with', FSpell.Check('Qianqian'));
  FSpell.Add('Qianqian');
  AssertTrue('known after being added', FSpell.Check('Qianqian'));
end;

procedure TTestSpell.IgnoredWordsAreAccepted;
begin
  AssertFalse('not known to begin with', FSpell.Check('lazbuild'));
  FSpell.Ignore('lazbuild');
  AssertTrue('accepted once ignored', FSpell.Check('lazbuild'));
end;

procedure TTestSpell.NoDictionaryMeansNoComplaints;
var
  Empty: TLedSpell;
begin
  { A missing data file must not underline the entire document. }
  Empty := TLedSpell.Create;
  try
    AssertFalse('nothing loaded', Empty.Loaded);
    AssertTrue('so everything passes', Empty.Check('recieve'));
  finally
    Empty.Free;
  end;
end;

initialization
  RegisterTest(TTestSpell);

end.
