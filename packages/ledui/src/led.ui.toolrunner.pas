{ led - a light editor.  Running user tools.

  Takes a tool and a document and does what the tool says: assembles the
  input, sets the environment, runs the command, and puts the output where
  the tool asked for it.

  The environment contract is medit's, verbatim, because that is what tool
  bodies reference:

      DOC DOC_DIR DOC_BASE DOC_EXT DOC_PATH LINE0 LINE DATA_DIR TEMP_DIR
      INPUT_FILE

  Output is read as it arrives rather than after the process exits, so a long
  build shows progress instead of appearing to hang.  The reading is driven by
  a timer rather than by TAsyncProcess.OnTerminate: that callback depends on
  the async child-process plumbing being serviced, and does not fire reliably
  when the editor is being driven from a script instead of from
  Application.Run.  Polling every 50 ms is deterministic and costs nothing. }
unit Led.UI.ToolRunner;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, ExtCtrls, Forms, Dialogs, Types,
  {$IFNDEF WINDOWS}BaseUnix,{$ENDIF}
  Led.Core.Tools, Led.Core.Paths,
  Led.UI.Document, Led.UI.Edit, Led.UI.Output;

type
  TLedToolFinished = procedure(ATool: TLedTool; AExitCode: Integer;
    const ACollected: string) of object;

  TLedToolRunner = class(TComponent)
  private
    FProcess: TProcess;
    FTimer: TTimer;
    FTool: TLedTool;
    FDoc: TLedDocument;
    FView: TLedEdit;
    FOutput: TLedOutputPane;
    FCollected: string;
    FInputFile: string;
    FOnFinished: TLedToolFinished;
    procedure Poll(Sender: TObject);
    procedure DeferredCleanup(Data: PtrInt);
    procedure DrainOutput;
    procedure Finish;
    procedure Cleanup;
    function BuildInput: string;
    procedure ApplyEnvironment;
    procedure DeliverOutput;
  public
    destructor Destroy; override;
    function Running: Boolean;
    procedure Stop;

    { Runs ATool against ADoc.  AOutput may be nil for tools that do not use
      the pane.  Returns False when the tool could not be started, having
      already reported why. }
    { AWorkDir overrides the folder the command runs in.  Empty keeps the
      old rule -- the active document's folder -- which is right for a tool
      acting on a file.  A project build wants the project root instead, and
      is the reason this exists. }
    function Run(ATool: TLedTool; ADoc: TLedDocument; AView: TLedEdit;
      AOutput: TLedOutputPane; const AWorkDir: string = ''): Boolean;

    property OnFinished: TLedToolFinished read FOnFinished write FOnFinished;
    property Tool: TLedTool read FTool;
  end;

{ True when the document satisfies the tool's requirements.  Used to grey out
  the menu entry rather than let it fail once it is too late. }
function LedToolCanRun(ATool: TLedTool; ADoc: TLedDocument): Boolean;

implementation

function LedToolCanRun(ATool: TLedTool; ADoc: TLedDocument): Boolean;
begin
  Result := False;
  if ATool = nil then Exit;
  if (ltoNeedDoc in ATool.Options) and (ADoc = nil) then Exit;
  if (ltoNeedFile in ATool.Options) and
     ((ADoc = nil) or ADoc.IsUntitled) then Exit;
  Result := True;
end;

destructor TLedToolRunner.Destroy;
begin
  Stop;
  Cleanup;
  inherited Destroy;
end;

function TLedToolRunner.Running: Boolean;
begin
  Result := (FProcess <> nil) and (FTimer <> nil) and FTimer.Enabled;
end;

procedure TLedToolRunner.Stop;
begin
  if (FProcess <> nil) and FProcess.Running then
    try
      FProcess.Terminate(1);
    except
      { Already gone. }
    end;
end;

procedure TLedToolRunner.Cleanup;
begin
  FreeAndNil(FTimer);
  FreeAndNil(FProcess);
  if (FInputFile <> '') and FileExists(FInputFile) then
    DeleteFile(FInputFile);
  FInputFile := '';
end;

function TLedToolRunner.BuildInput: string;
var
  First, Last, i: Integer;
begin
  Result := '';
  if FView = nil then Exit;

  case FTool.Input of
    ltiSelection:
      if FView.SelAvail then Result := FView.SelText;
    ltiLines:
      begin
        { Whole lines covering the selection -- a tool like sort wants lines,
          not a fragment starting mid-word. }
        if FView.SelAvail then
        begin
          First := FView.BlockBegin.Y;
          Last := FView.BlockEnd.Y;
          if (Last > First) and (FView.BlockEnd.X = 1) then Dec(Last);
        end
        else
        begin
          First := FView.CaretY;
          Last := First;
        end;
        for i := First to Last do
          Result := Result + FView.Lines[i - 1] + LineEnding;
      end;
    ltiDoc:
      Result := FView.Lines.Text;
    ltiDocCopy:
      begin
        { A copy on disk, named in INPUT_FILE, for tools that insist on a
          file rather than a stream. }
        FInputFile := IncludeTrailingPathDelimiter(GetTempDir) +
          Format('led-input-%d.txt', [GetProcessID]);
        FView.Lines.SaveToFile(FInputFile);
      end;
  end;
end;

procedure TLedToolRunner.ApplyEnvironment;
var
  DocPath, DocDir, DocName, DocBase, DocExt: string;
  i: Integer;

  procedure PutEnv(const AName, AValue: string);
  begin
    FProcess.Environment.Add(AName + '=' + AValue);
  end;

begin
  { Start from the real environment, then add.  A tool that runs a compiler
    needs PATH more than it needs a clean slate. }
  FProcess.Environment.Clear;
  for i := 1 to GetEnvironmentVariableCount do
    FProcess.Environment.Add(GetEnvironmentString(i));

  DocPath := '';
  if (FDoc <> nil) and not FDoc.IsUntitled then DocPath := FDoc.FileName;
  DocDir := ExtractFileDir(DocPath);
  DocName := ExtractFileName(DocPath);
  DocExt := ExtractFileExt(DocName);
  DocBase := ChangeFileExt(DocName, '');

  PutEnv('DOC', DocName);
  PutEnv('DOC_DIR', DocDir);
  PutEnv('DOC_BASE', DocBase);
  PutEnv('DOC_EXT', DocExt);
  PutEnv('DOC_PATH', DocPath);
  if FView <> nil then
  begin
    PutEnv('LINE', IntToStr(FView.CaretY));
    PutEnv('LINE0', IntToStr(FView.CaretY - 1));
  end
  else
  begin
    PutEnv('LINE', '0');
    PutEnv('LINE0', '0');
  end;
  PutEnv('DATA_DIR', LedDataDir);
  PutEnv('TEMP_DIR', GetTempDir);
  if FInputFile <> '' then
    PutEnv('INPUT_FILE', FInputFile);
end;

function TLedToolRunner.Run(ATool: TLedTool; ADoc: TLedDocument;
  AView: TLedEdit; AOutput: TLedOutputPane; const AWorkDir: string): Boolean;
var
  Input, ScriptPath, WorkDir: string;
  L: TStringList;
begin
  Result := False;
  if Running then Exit;
  Cleanup;

  FTool := ATool;
  FDoc := ADoc;
  FView := AView;
  FOutput := AOutput;
  FCollected := '';

  Input := BuildInput;

  { The body is written to a script file rather than passed with -c: it keeps
    quoting out of the picture entirely, and a multi-line body then behaves
    exactly as it reads. }
  ScriptPath := IncludeTrailingPathDelimiter(GetTempDir) +
    Format('led-tool-%d%s', [GetProcessID,
      {$IFDEF WINDOWS}'.bat'{$ELSE}'.sh'{$ENDIF}]);
  L := TStringList.Create;
  try
    {$IFNDEF WINDOWS}
    L.Add('#!/bin/sh');
    {$ENDIF}
    L.Add(ATool.Code);
    L.SaveToFile(ScriptPath);
  finally
    L.Free;
  end;
  {$IFNDEF WINDOWS}
  { The script is run as an argument to /bin/sh, so it need not be executable;
    the mode is tightened anyway because it can hold anything the user typed. }
  FpChmod(ScriptPath, &600);
  {$ENDIF}

  FProcess := TProcess.Create(nil);
  FProcess.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
  {$IFDEF WINDOWS}
  FProcess.Executable := GetEnvironmentVariable('COMSPEC');
  if FProcess.Executable = '' then FProcess.Executable := 'cmd.exe';
  FProcess.Parameters.Add('/c');
  FProcess.Parameters.Add(ScriptPath);
  {$ELSE}
  FProcess.Executable := '/bin/sh';
  FProcess.Parameters.Add(ScriptPath);
  {$ENDIF}

  { The caller's folder wins; otherwise the document's, as it always did. }
  WorkDir := AWorkDir;
  if (WorkDir = '') and (FDoc <> nil) and (not FDoc.IsUntitled) then
    WorkDir := ExtractFileDir(FDoc.FileName);
  if WorkDir = '' then WorkDir := GetCurrentDir;
  FProcess.CurrentDirectory := WorkDir;

  ApplyEnvironment;

  if FOutput <> nil then
    FOutput.BeginRun(ATool.Filter, WorkDir);

  try
    FProcess.Execute;
  except
    on E: Exception do
    begin
      if FOutput <> nil then
        FOutput.AddNote(Format('led: could not run "%s": %s',
          [ATool.Name, E.Message]));
      Cleanup;
      Exit;
    end;
  end;

  { Input is written and the pipe closed straight away.  A tool reading more
    than a pipe buffer would deadlock if we waited, but tool input is a
    selection or a document, and the child is already draining it. }
  if (Input <> '') and (FTool.Input in [ltiLines, ltiSelection, ltiDoc]) then
    FProcess.Input.Write(Input[1], Length(Input));
  FProcess.CloseInput;

  FTimer := TTimer.Create(nil);
  FTimer.Interval := 50;
  FTimer.OnTimer := @Poll;
  FTimer.Enabled := True;

  Result := True;
end;

procedure TLedToolRunner.Poll(Sender: TObject);
begin
  DrainOutput;
  if (FProcess <> nil) and (not FProcess.Running) then
  begin
    { Once more after exit: the last write can land between the final read
      and the process ending. }
    DrainOutput;
    Finish;
  end;
end;

procedure TLedToolRunner.DrainOutput;
var
  Buf: array[0..8191] of Char;
  N: Integer;
  S: string;
begin
  while (FProcess <> nil) and (FProcess.Output <> nil) and
        (FProcess.Output.NumBytesAvailable > 0) do
  begin
    N := FProcess.Output.Read(Buf, SizeOf(Buf));
    if N <= 0 then Break;
    SetString(S, Buf, N);
    FCollected := FCollected + S;
    if (FOutput <> nil) and (FTool.Output = ltoPane) then
      FOutput.Append(S);
  end;
end;

procedure TLedToolRunner.Finish;
var
  Code: Integer;
begin
  if FTimer <> nil then FTimer.Enabled := False;
  Code := 0;
  if FProcess <> nil then Code := FProcess.ExitStatus;

  if (FOutput <> nil) and (FTool.Output = ltoPane) then
  begin
    FOutput.Flush;
    if Code <> 0 then
      FOutput.AddNote(Format('led: "%s" exited with %d', [FTool.Name, Code]));
  end;

  DeliverOutput;
  if Assigned(FOnFinished) then
    FOnFinished(FTool, Code, FCollected);
  { Cleanup frees the timer, and this runs inside that timer's own handler,
    so it is deferred to the next turn of the event loop. }
  Application.QueueAsyncCall(@DeferredCleanup, 0);
end;

procedure TLedToolRunner.DeferredCleanup(Data: PtrInt);
begin
  Cleanup;
end;

procedure TLedToolRunner.DeliverOutput;
var
  First, Last: Integer;
begin
  case FTool.Output of
    ltoInsert:
      begin
        if (FView = nil) or FView.ReadOnly then Exit;
        FView.BeginUndoBlock;
        try
          if FTool.Input = ltiLines then
          begin
            { Replace the lines that were fed in, so "sort" rewrites the
              block rather than appending a second copy of it. }
            if FView.SelAvail then
            begin
              First := FView.BlockBegin.Y;
              Last := FView.BlockEnd.Y;
              if (Last > First) and (FView.BlockEnd.X = 1) then Dec(Last);
            end
            else
            begin
              First := FView.CaretY;
              Last := First;
            end;
            FView.BlockBegin := Point(1, First);
            if Last < FView.Lines.Count then
              FView.BlockEnd := Point(1, Last + 1)
            else
              FView.BlockEnd :=
                Point(Length(FView.Lines[Last - 1]) + 1, Last);
          end;
          FView.SelText := FCollected;
        finally
          FView.EndUndoBlock;
        end;
      end;
  end;
end;

end.
