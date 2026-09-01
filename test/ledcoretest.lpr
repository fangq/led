{ led - a light editor.  Headless test runner for the ledcore package. }
program ledcoretest;

{$mode objfpc}{$H+}

uses
  Classes, consoletestrunner,
  Led.Core.Tests.FileIO, Led.Core.Tests.Encodings, Led.Core.Tests.Config,
  Led.Core.Tests.Settings, Led.Core.Tests.Filters, Led.Syn.Tests.Languages,
  Led.Syn.Tests.Theme,
  Led.Core.Tests.CLI;

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
