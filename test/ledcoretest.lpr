{ led - a light editor.  Headless test runner for the ledcore package. }
program ledcoretest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  { The grep tests start a worker thread, which needs the threading driver
    pulled in before anything else. }
  cthreads,
  {$ENDIF}
  Classes, consoletestrunner,
  Led.Core.Tests.Spell,
  Led.Core.Tests.FileIO, Led.Core.Tests.Encodings, Led.Core.Tests.Config,
  Led.Core.Tests.Settings, Led.Core.Tests.Filters, Led.Syn.Tests.Languages,
  Led.Syn.Tests.Theme,
  Led.Core.Tests.CLI, Led.Core.Tests.Tools, Led.Core.Tests.Grep, Led.Term.Tests.Screen, Led.Core.Tests.Ctags, Led.Core.Tests.Markdown, Led.Core.Tests.Recovery,
  Led.Core.Tests.Wiki, Led.Core.Tests.Scripts;

type
  TLedTestRunner = class(TTestRunner)
  end;

var
  App: TLedTestRunner;
begin
  App := TLedTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'ledcore tests';
    App.Run;
  finally
    App.Free;
  end;
end.
