// led - a lightweight editor.  Tests for what language a notebook cell is in.
//
// A cell that opens with %%shell is a shell script however the file's
// metadata describes the notebook, and a teaching notebook is full of them.
// What is checked here is the reading of the magic, the mapping of the two
// vocabularies onto each other -- a kernel says "bash" and LED says "sh" --
// and the fall back to Python, which is what a notebook that says nothing
// nearly always is.

unit Led.Core.Tests.NBMagic;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Led.Core.NBMagic;

type
  TTestNBMagic = class(TTestCase)
  published
    procedure ACellMagicNamesItsLanguage;
    procedure ArgumentsAfterTheMagicAreNotPartOfTheName;
    procedure AMagicOnALaterLineIsNotACellMagic;
    procedure ACellWithNoMagicNamesNothing;
    procedure TheKernelsNameIsMappedOntoLEDs;
    procedure AnUnknownNameMapsToNothing;
    procedure TheCellsOwnMagicBeatsTheNotebook;
    procedure WithoutAMagicTheNotebookDecides;
    procedure WithNothingAtAllItIsPython;
    procedure AMeasuringMagicLeavesTheLanguageAlone;
    procedure ANameLEDMayKnowIsPassedOn;
    procedure ACellMagicLineIsAMagic;
    procedure ALineMagicAndAShellEscapeAre;
    procedure ButNotInACellHandedToAnotherLanguage;
    procedure OrdinaryCodeIsNot;
    { what is sent to a kernel }
    procedure ColabsShellMagicBecomesBash;
    procedure ArgumentsAfterItGoWithIt;
    procedure NothingElseIsTouched;
  end;

implementation

procedure TTestNBMagic.ACellMagicNamesItsLanguage;
begin
  AssertEquals('shell', LedNBCellMagic('%%shell' + #10 + 'ls -l' + #10));
  AssertEquals('octave', LedNBCellMagic('%%octave' + #10 + 'a = [1 2];'));
  { Written with carriage returns, which is how a notebook from Windows
    arrives. }
  AssertEquals('perl', LedNBCellMagic('%%perl'#13#10'print 1;'#13#10));
end;

procedure TTestNBMagic.ArgumentsAfterTheMagicAreNotPartOfTheName;
begin
  AssertEquals('bash', LedNBCellMagic('%%bash -s 3' + #10 + 'echo $1'));
  AssertEquals('writefile', LedNBCellMagic('%%writefile out.txt' + #10 + 'x'));
end;

procedure TTestNBMagic.AMagicOnALaterLineIsNotACellMagic;
begin
  { IPython only reads a cell magic as the first thing in the cell, and so
    does this: a %% further down is a syntax error, not a language. }
  AssertEquals('', LedNBCellMagic('x = 1' + #10 + '%%bash' + #10 + 'ls'));
end;

procedure TTestNBMagic.ACellWithNoMagicNamesNothing;
begin
  AssertEquals('', LedNBCellMagic('print(1)' + #10));
  AssertEquals('', LedNBCellMagic(''));
  { One % is a line magic, which names no language. }
  AssertEquals('', LedNBCellMagic('%load_ext autoreload' + #10));
end;

procedure TTestNBMagic.TheKernelsNameIsMappedOntoLEDs;
begin
  { The two vocabularies do not line up by themselves, which is the whole
    reason the table exists. }
  AssertEquals('sh', LedNBLanguageId('bash'));
  AssertEquals('sh', LedNBLanguageId('shell'));
  AssertEquals('r', LedNBLanguageId('ir'));
  AssertEquals('cpp', LedNBLanguageId('c++'));
  AssertEquals('js', LedNBLanguageId('javascript'));
  AssertEquals('octave', LedNBLanguageId('Octave'));
end;

procedure TTestNBMagic.AnUnknownNameMapsToNothing;
begin
  AssertEquals('', LedNBLanguageId('brainfuck'));
  AssertEquals('', LedNBLanguageId(''));
end;

procedure TTestNBMagic.TheCellsOwnMagicBeatsTheNotebook;
begin
  AssertEquals('sh',
    LedNBCellLanguage('%%shell' + #10 + 'ls -l', 'python'));
  AssertEquals('octave',
    LedNBCellLanguage('%%octave' + #10 + 'disp(1)', 'python'));
end;

procedure TTestNBMagic.WithoutAMagicTheNotebookDecides;
begin
  AssertEquals('r', LedNBCellLanguage('plot(x)', 'ir'));
  AssertEquals('python', LedNBCellLanguage('print(1)', 'python'));
end;

procedure TTestNBMagic.WithNothingAtAllItIsPython;
begin
  { A notebook with no kernel metadata, which is most of the ones written by
    hand or by a converter. }
  AssertEquals('python', LedNBCellLanguage('print(1)', ''));
  AssertEquals('python', LedNBCellLanguage('', ''));
end;

procedure TTestNBMagic.AMeasuringMagicLeavesTheLanguageAlone;
begin
  { %%time and its friends are not languages: the cell under one is still
    the notebook's own. }
  AssertEquals('python', LedNBCellLanguage('%%time' + #10 + 'f()', 'python'));
  AssertEquals('r', LedNBCellLanguage('%%capture' + #10 + 'f()', 'ir'));
end;

procedure TTestNBMagic.ANameLEDMayKnowIsPassedOn;
begin
  { Not in the table, but LED may have a grammar under that very name, so it
    goes through rather than being replaced by the guess. }
  AssertEquals('haskell', LedNBCellLanguage('main = print 1', 'haskell'));
end;

procedure TTestNBMagic.ACellMagicLineIsAMagic;
begin
  AssertTrue('the opening %%shell',
    LedNBIsMagicLine('%%shell', True, False));
  AssertFalse('but not the same line further down',
    LedNBIsMagicLine('%%shell', False, False));
end;

procedure TTestNBMagic.ALineMagicAndAShellEscapeAre;
begin
  AssertTrue('a line magic', LedNBIsMagicLine('%load_ext x', False, True));
  AssertTrue('a shell escape', LedNBIsMagicLine('!pip install x', False, True));
  AssertTrue('indented, which IPython allows',
    LedNBIsMagicLine('  !ls', False, True));
end;

procedure TTestNBMagic.ButNotInACellHandedToAnotherLanguage;
begin
  { Inside a %%bash cell a '!' is a '!' -- history expansion, or a negation
    -- and drawing it as a comment would be a lie about the code. }
  AssertFalse('a bang in a shell cell',
    LedNBIsMagicLine('!ls', False, False));
  AssertFalse('a per cent in a shell cell',
    LedNBIsMagicLine('%x', False, False));
end;

procedure TTestNBMagic.OrdinaryCodeIsNot;
begin
  AssertFalse('code', LedNBIsMagicLine('print(1)', True, True));
  AssertFalse('nothing', LedNBIsMagicLine('', True, True));
  AssertFalse('a remainder, which is not at the start of the line',
    LedNBIsMagicLine('x = a % b', False, True));
end;

{ ---- what is sent to a kernel ----

  %%shell is Colab's and no other front end has it.  An ordinary IPython
  kernel answers "UsageError: Cell magic `%%shell` not found" -- on stderr,
  with the run reported as a success, so a notebook of twenty such cells
  looks as though every one of them did nothing.  IPython's %%bash means the
  same thing. }

procedure TTestNBMagic.ColabsShellMagicBecomesBash;
begin
  AssertEquals('%%bash' + #10 + 'echo hi' + #10,
    LedNBRunnableSource('%%shell' + #10 + 'echo hi' + #10));
  { Carriage returns kept: the line ending is the reader's. }
  AssertEquals('%%bash'#13#10'echo hi'#13#10,
    LedNBRunnableSource('%%shell'#13#10'echo hi'#13#10));
end;

procedure TTestNBMagic.ArgumentsAfterItGoWithIt;
begin
  AssertEquals('%%bash -s 3' + #10 + 'echo $1',
    LedNBRunnableSource('%%shell -s 3' + #10 + 'echo $1'));
end;

procedure TTestNBMagic.NothingElseIsTouched;
begin
  { Another magic, a shell escape, plain code, and a %%shell that is not the
    first line and so is not a cell magic at all. }
  AssertEquals('%%bash' + #10 + 'ls',
    LedNBRunnableSource('%%bash' + #10 + 'ls'));
  AssertEquals('!pip install numpy',
    LedNBRunnableSource('!pip install numpy'));
  AssertEquals('print(1)', LedNBRunnableSource('print(1)'));
  AssertEquals('x = 1' + #10 + '%%shell',
    LedNBRunnableSource('x = 1' + #10 + '%%shell'));
  AssertEquals('', LedNBRunnableSource(''));
end;

initialization
  RegisterTest(TTestNBMagic);

end.
