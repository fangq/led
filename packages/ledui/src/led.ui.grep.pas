{ led - a light editor.  The Find in Files dialog.

  Results are written into the ordinary output pane as "file:line: text",
  which the default output filter already knows how to turn into something
  clickable.  One mechanism, two uses. }
unit Led.UI.Grep;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  Led.Core.Grep, Led.UI.Output, Led.UI.Focus;

type
  TLedGrepStarted = procedure of object;

  TLedGrepDialog = class(TForm)
  private
    FOutput: TLedOutputPane;
    FThread: TLedGrepThread;
    FCboPattern: TComboBox;
    FCboDir: TComboBox;
    FCboMask: TComboBox;
    FChkCase: TCheckBox;
    FChkWord: TCheckBox;
    FChkRegex: TCheckBox;
    FChkRecurse: TCheckBox;
    FChkSkipVCS: TCheckBox;
    FBtnFind: TButton;
    FBtnStop: TButton;
    FOnStarted: TLedGrepStarted;
    procedure Build;
    procedure DoBrowse(Sender: TObject);
    procedure DoFind(Sender: TObject);
    procedure DoStop(Sender: TObject);
    procedure DoClose(Sender: TObject);
    procedure GotMatch(const AMatch: TLedGrepMatch);
    procedure Finished(AFilesSearched, AMatches: Integer; ACancelled: Boolean);
    procedure ReapThread(Data: PtrInt);
  public
    constructor CreateFor(AOwner: TComponent; AOutput: TLedOutputPane);
    destructor Destroy; override;
    procedure ShowFor(const ADirectory, APattern: string);
    property OnStarted: TLedGrepStarted read FOnStarted write FOnStarted;
  end;

implementation

constructor TLedGrepDialog.CreateFor(AOwner: TComponent;
  AOutput: TLedOutputPane);
begin
  inherited CreateNew(AOwner);
  FOutput := AOutput;
  Build;
end;

destructor TLedGrepDialog.Destroy;
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    FThread.Free;
  end;
  inherited Destroy;
end;

procedure TLedGrepDialog.Build;
var
  Y: Integer;
  B: TButton;

  procedure Lab(const S: string; ATop: Integer);
  var
    L: TLabel;
  begin
    L := TLabel.Create(Self);
    L.Parent := Self; L.Caption := S; L.Left := 12; L.Top := ATop + 4;
  end;

  function Combo(ATop, AWidth: Integer): TComboBox;
  begin
    Result := TComboBox.Create(Self);
    Result.Parent := Self;
    Result.Left := 110; Result.Top := ATop; Result.Width := AWidth;
  end;

  function Check(const S: string; ALeft, ATop: Integer): TCheckBox;
  begin
    Result := TCheckBox.Create(Self);
    Result.Parent := Self; Result.Caption := S;
    Result.Left := ALeft; Result.Top := ATop; Result.Width := 170;
  end;

begin
  Caption := 'Find in Files';
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  ClientWidth := 560;

  Y := 12;
  Lab('Find:', Y);
  FCboPattern := Combo(Y, 320);
  Y := Y + 32;

  Lab('In folder:', Y);
  FCboDir := Combo(Y, 320);
  B := TButton.Create(Self);
  B.Parent := Self; B.Caption := 'Browse...'; B.Left := 440; B.Top := Y;
  B.Width := 100; B.OnClick := @DoBrowse;
  Y := Y + 32;

  Lab('File names:', Y);
  FCboMask := Combo(Y, 320);
  FCboMask.Items.Add('');
  FCboMask.Items.Add('*.c;*.h;*.cpp;*.hpp');
  FCboMask.Items.Add('*.pas;*.pp;*.inc;*.lfm');
  FCboMask.Items.Add('*.py');
  FCboMask.Items.Add('*.md;*.txt');
  Y := Y + 36;

  FChkCase    := Check('Match &case', 12, Y);
  FChkWord    := Check('&Whole words only', 200, Y);
  Y := Y + 24;
  FChkRegex   := Check('Regular e&xpression', 12, Y);
  FChkRecurse := Check('Include su&bfolders', 200, Y);
  FChkRecurse.Checked := True;
  Y := Y + 24;
  { On by default: searching .git and node_modules turns a two-second search
    into a two-minute one and never finds what you wanted. }
  FChkSkipVCS := Check('Skip &version control and build folders', 12, Y);
  FChkSkipVCS.Checked := True;
  FChkSkipVCS.Width := 320;
  Y := Y + 36;

  FBtnFind := TButton.Create(Self);
  FBtnFind.Parent := Self; FBtnFind.Caption := '&Find'; FBtnFind.Left := 260;
  FBtnFind.Top := Y; FBtnFind.Width := 90; FBtnFind.OnClick := @DoFind;
  FBtnFind.Default := True;

  FBtnStop := TButton.Create(Self);
  FBtnStop.Parent := Self; FBtnStop.Caption := '&Stop'; FBtnStop.Left := 356;
  FBtnStop.Top := Y; FBtnStop.Width := 90; FBtnStop.OnClick := @DoStop;
  FBtnStop.Enabled := False;

  B := TButton.Create(Self);
  B.Parent := Self; B.Caption := 'Close'; B.Left := 452; B.Top := Y;
  B.Width := 90; B.OnClick := @DoClose; B.Cancel := True;

  ClientHeight := Y + 44;
end;

procedure TLedGrepDialog.DoBrowse(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
begin
  Dlg := TSelectDirectoryDialog.Create(Self);
  try
    Dlg.InitialDir := FCboDir.Text;
    if Dlg.Execute then FCboDir.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

procedure TLedGrepDialog.ShowFor(const ADirectory, APattern: string);
begin
  if APattern <> '' then FCboPattern.Text := APattern;
  if (FCboDir.Text = '') and (ADirectory <> '') then
    FCboDir.Text := ADirectory;
  Show;
  LedTryFocus(FCboPattern);
end;

procedure TLedGrepDialog.DoFind(Sender: TObject);
var
  O: TLedGrepOptions;

  procedure Remember(ACombo: TComboBox);
  begin
    if (ACombo.Text <> '') and (ACombo.Items.IndexOf(ACombo.Text) < 0) then
      ACombo.Items.Insert(0, ACombo.Text);
  end;

begin
  if FThread <> nil then Exit;
  if FCboPattern.Text = '' then Exit;
  if not DirectoryExists(FCboDir.Text) then
  begin
    MessageDlg('led', Format('"%s" is not a folder.', [FCboDir.Text]),
      mtError, [mbOK], 0);
    Exit;
  end;

  Remember(FCboPattern);
  Remember(FCboDir);
  Remember(FCboMask);

  O := LedDefaultGrepOptions;
  O.Pattern := FCboPattern.Text;
  O.Directory := FCboDir.Text;
  O.FileMask := FCboMask.Text;
  O.MatchCase := FChkCase.Checked;
  O.WholeWord := FChkWord.Checked;
  O.Regex := FChkRegex.Checked;
  O.Recursive := FChkRecurse.Checked;
  O.SkipVCS := FChkSkipVCS.Checked;

  if FOutput <> nil then
  begin
    FOutput.BeginRun('default', O.Directory);
    FOutput.AddNote(Format('Searching %s for "%s"...',
      [O.Directory, O.Pattern]));
  end;
  if Assigned(FOnStarted) then FOnStarted;

  FThread := TLedGrepThread.Create(O);
  FThread.OnMatch := @GotMatch;
  FThread.OnDone := @Finished;
  FBtnFind.Enabled := False;
  FBtnStop.Enabled := True;
  FThread.Start;
end;

procedure TLedGrepDialog.DoStop(Sender: TObject);
begin
  if FThread <> nil then FThread.Terminate;
end;

procedure TLedGrepDialog.DoClose(Sender: TObject);
begin
  DoStop(nil);
  Hide;
end;

procedure TLedGrepDialog.GotMatch(const AMatch: TLedGrepMatch);
begin
  if FOutput = nil then Exit;
  { The shape the default output filter understands, so every result is
    clickable without a second parser. }
  FOutput.Append(Format('%s:%d: %s'#10,
    [AMatch.FileName, AMatch.Line, TrimRight(AMatch.Text)]));
end;

procedure TLedGrepDialog.Finished(AFilesSearched, AMatches: Integer;
  ACancelled: Boolean);
begin
  if FOutput <> nil then
  begin
    FOutput.Flush;
    if ACancelled then
      FOutput.AddNote(Format('Stopped after %d matches in %d files.',
        [AMatches, AFilesSearched]))
    else
      FOutput.AddNote(Format('%d matches in %d files.',
        [AMatches, AFilesSearched]));
  end;
  FBtnFind.Enabled := True;
  FBtnStop.Enabled := False;
  { OnDone arrives through Synchronize, so this runs on the main thread while
    the worker is still winding down.  Freeing it is deferred to the next turn
    of the event loop. }
  Application.QueueAsyncCall(@ReapThread, 0);
end;

procedure TLedGrepDialog.ReapThread(Data: PtrInt);
begin
  if FThread = nil then Exit;
  FThread.WaitFor;
  FreeAndNil(FThread);
end;

end.
