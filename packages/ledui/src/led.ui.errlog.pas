// led - a lightweight editor.  Writing down what went wrong, before saying so.
//
// The LCL answers an unhandled exception with a dialog: the message, and a
// choice between carrying on and killing the program.  That is the right
// thing to show a reader, and it is almost useless to whoever has to fix it
// -- "List index (0) out of bounds" names neither the list nor the code that
// asked it for an item, and by the time the reader has read it the stack is
// gone.
//
// So the exception is written down first: what it was, when, and the stack
// it came out of, appended to errors.log beside the preferences.  Then the
// dialog is shown exactly as before, because a reader deciding whether to
// trust the editor with their unsaved work should not have that decision
// changed by a logging feature.
//
// The log is the only evidence a fault that happens once a week is ever
// going to leave.  It is plain text, it is small -- each entry is a few
// lines and old ones are dropped past a cap -- and it says where it is in
// the dialog, so a report can carry it.

unit Led.UI.ErrLog;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms,
  Led.Core.Paths;

{ Installs the handler.  Called once at startup, before the first form. }
procedure LedInstallErrorLog;

{ Where the entries go. }
function LedErrorLogFile: string;

{ One entry, as it would be written.  Public because a check should be able
  to read what the log says without arranging for a real crash. }
function LedFormatError(const AWhen: TDateTime; const AClass, AMessage,
  ABackTrace: string): string;

{ Appends one entry, trimming the file when it has grown past what anybody
  will read.  Public for the same reason. }
procedure LedNoteError(const AClass, AMessage, ABackTrace: string);

implementation

const
  { Enough to hold the last few faults with their stacks, small enough that
    nobody has to manage it. }
  MostBytes = 256 * 1024;

var
  GInstalled: Boolean = False;

function LedErrorLogFile: string;
begin
  Result := LedConfigFile('errors.log');
end;

function LedFormatError(const AWhen: TDateTime; const AClass, AMessage,
  ABackTrace: string): string;
begin
  Result := '--- ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', AWhen) +
    LineEnding + AClass + ': ' + AMessage + LineEnding;
  if ABackTrace <> '' then
    Result := Result + ABackTrace + LineEnding;
end;

{ Keeps the tail.  A log that grows without limit is a log somebody deletes,
  and the newest fault is the one being asked about. }
procedure TrimToTail(const AFileName: string);
var
  All: string;
  F: TFileStream;
  Cut: Integer;
begin
  if not FileExists(AFileName) then Exit;
  F := nil;
  try
    F := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    if F.Size <= MostBytes then Exit;
    F.Position := F.Size - MostBytes;
    SetLength(All, MostBytes);
    F.ReadBuffer(All[1], MostBytes);
  finally
    F.Free;
  end;
  { From the next whole entry, so the file never starts mid-stack. }
  Cut := Pos('--- ', All);
  if Cut > 1 then All := Copy(All, Cut, Length(All) - Cut + 1);
  F := TFileStream.Create(AFileName, fmCreate);
  try
    if All <> '' then F.WriteBuffer(All[1], Length(All));
  finally
    F.Free;
  end;
end;

procedure LedNoteError(const AClass, AMessage, ABackTrace: string);
var
  F: TFileStream;
  Entry: string;
  Name_: string;
begin
  Name_ := LedErrorLogFile;
  Entry := LedFormatError(Now, AClass, AMessage, ABackTrace);
  try
    TrimToTail(Name_);
    if FileExists(Name_) then
      F := TFileStream.Create(Name_, fmOpenWrite or fmShareDenyNone)
    else
      F := TFileStream.Create(Name_, fmCreate);
    try
      F.Position := F.Size;
      F.WriteBuffer(Entry[1], Length(Entry));
    finally
      F.Free;
    end;
  except
    { A log that cannot be written is not worth a second exception on top of
      the one being reported. }
  end;
end;

type
  { OnException is a method pointer and there is no object to hang it on. }
  TLedErrorSink = class
    procedure Caught(Sender: TObject; E: Exception);
  end;

var
  GSink: TLedErrorSink = nil;

procedure TLedErrorSink.Caught(Sender: TObject; E: Exception);
var
  Trace: string;
begin
  Trace := BackTraceStrFunc(ExceptAddr);
  if ExceptFrameCount > 0 then
    Trace := Trace + LineEnding + BackTraceStrFunc(ExceptFrames[0]);
  LedNoteError(E.ClassName, E.Message, Trace);
  { And then the dialog the reader would have seen anyway.  Deciding what to
    do about a fault is theirs; this only made sure it left a trace. }
  Application.ShowException(E);
end;

procedure LedInstallErrorLog;
begin
  if GInstalled then Exit;
  GInstalled := True;
  GSink := TLedErrorSink.Create;
  Application.OnException := @GSink.Caught;
end;

end.
