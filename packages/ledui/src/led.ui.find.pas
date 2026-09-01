{ led - a light editor.  Find and replace.

  Two surfaces over one engine: a modeless Find/Replace dialog for the full
  set of options, and an incremental find bar that appears at the foot of the
  window and searches as you type.  Both drive SynEdit's SearchReplace, and
  both share the search history and the option state, so switching between
  them does not lose your place.

  Highlight-all is a SynEdit markup rather than a search: it paints every
  occurrence without moving the caret. }
unit Led.UI.Find;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  SynEdit, SynEditTypes, SynEditMarkupHighAll,
  Led.UI.Edit;

type
  { Supplies the view to act on.  The dialog outlives any one document, so it
    asks each time rather than holding a reference. }
  TLedViewFunc = function: TLedEdit of object;

  TLedSearchState = class
  private
    FHistory: TStringList;
    FReplaceHistory: TStringList;
  public
    SearchText: string;
    ReplaceText: string;
    MatchCase: Boolean;
    WholeWord: Boolean;
    Regex: Boolean;
    Backwards: Boolean;
    SelectedOnly: Boolean;
    HighlightAll: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Options: TSynSearchOptions;
    procedure RememberSearch(const S: string);
    procedure RememberReplace(const S: string);
    property History: TStringList read FHistory;
    property ReplaceHistory: TStringList read FReplaceHistory;
  end;

  { Runs one search step against AView.  Returns True when something was
    found; wraps around once and reports that it did. }
  TLedFindOutcome = (lfoFound, lfoNotFound, lfoWrapped);

function LedFindNext(AView: TLedEdit; AState: TLedSearchState;
  ABackwards: Boolean): TLedFindOutcome;
function LedReplaceOne(AView: TLedEdit; AState: TLedSearchState): Boolean;
function LedReplaceAll(AView: TLedEdit; AState: TLedSearchState): Integer;

{ Paints every occurrence of AState.SearchText, or clears the painting when
  highlight-all is off or the text is empty. }
procedure LedUpdateHighlightAll(AView: TLedEdit; AState: TLedSearchState);

type
  TLedFindForm = class(TForm)
  private
    FState: TLedSearchState;
    FGetView: TLedViewFunc;
    FCboFind: TComboBox;
    FCboReplace: TComboBox;
    FChkCase: TCheckBox;
    FChkWord: TCheckBox;
    FChkRegex: TCheckBox;
    FChkSelection: TCheckBox;
    FChkHighlight: TCheckBox;
    FLblStatus: TLabel;
    procedure BuildUI;
    procedure Pull;
    procedure Push;
    procedure DoFindNext(Sender: TObject);
    procedure DoFindPrev(Sender: TObject);
    procedure DoReplace(Sender: TObject);
    procedure DoReplaceAll(Sender: TObject);
    procedure DoClose(Sender: TObject);
    procedure OptionChanged(Sender: TObject);
    procedure Report(AOutcome: TLedFindOutcome);
  public
    constructor CreateFor(AOwner: TComponent; AState: TLedSearchState;
      AGetView: TLedViewFunc);
    procedure ShowFor(AReplace: Boolean);
  end;

  { The incremental bar.  Parented into the window rather than floating,
    because it has to stay out of the way while you keep typing. }
  TLedFindBar = class(TPanel)
  private
    FState: TLedSearchState;
    FGetView: TLedViewFunc;
    FEdit: TEdit;
    FLabel: TLabel;
    FStartPos: TPoint;
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DoNext(Sender: TObject);
    procedure DoPrev(Sender: TObject);
    procedure DoHide(Sender: TObject);
  public
    constructor CreateFor(AOwner: TComponent; AState: TLedSearchState;
      AGetView: TLedViewFunc);
    procedure Activate;
  end;

implementation

uses
  LCLType;

{ TLedSearchState }

constructor TLedSearchState.Create;
begin
  inherited Create;
  FHistory := TStringList.Create;
  FReplaceHistory := TStringList.Create;
  HighlightAll := True;
end;

destructor TLedSearchState.Destroy;
begin
  FHistory.Free;
  FReplaceHistory.Free;
  inherited Destroy;
end;

function TLedSearchState.Options: TSynSearchOptions;
begin
  Result := [];
  if MatchCase then Include(Result, ssoMatchCase);
  if WholeWord then Include(Result, ssoWholeWord);
  if Regex then Include(Result, ssoRegExpr);
  if SelectedOnly then Include(Result, ssoSelectedOnly);
end;

procedure Remember(AList: TStringList; const S: string);
var
  i: Integer;
begin
  if S = '' then Exit;
  i := AList.IndexOf(S);
  if i >= 0 then AList.Delete(i);
  AList.Insert(0, S);
  while AList.Count > 20 do AList.Delete(AList.Count - 1);
end;

procedure TLedSearchState.RememberSearch(const S: string);
begin
  Remember(FHistory, S);
end;

procedure TLedSearchState.RememberReplace(const S: string);
begin
  Remember(FReplaceHistory, S);
end;

{ --- the engine ----------------------------------------------------------- }

function LedFindNext(AView: TLedEdit; AState: TLedSearchState;
  ABackwards: Boolean): TLedFindOutcome;
var
  Opts: TSynSearchOptions;
  Found: Integer;
begin
  Result := lfoNotFound;
  if (AView = nil) or (AState.SearchText = '') then Exit;

  Opts := AState.Options + [ssoFindContinue];
  if ABackwards then Include(Opts, ssoBackwards);

  Found := AView.SearchReplace(AState.SearchText, '', Opts);
  if Found > 0 then Exit(lfoFound);

  { Nothing ahead: start again from the far end.  Reported separately so the
    user is told it wrapped rather than silently jumping. }
  Opts := AState.Options + [ssoEntireScope];
  if ABackwards then Include(Opts, ssoBackwards);
  Found := AView.SearchReplace(AState.SearchText, '', Opts);
  if Found > 0 then
    Result := lfoWrapped;
end;

function LedReplaceOne(AView: TLedEdit; AState: TLedSearchState): Boolean;
begin
  Result := False;
  if (AView = nil) or (AState.SearchText = '') or AView.ReadOnly then Exit;

  { Replace only when the current selection is the match; otherwise find the
    next one first, so pressing Replace repeatedly steps through. }
  if AView.SelAvail and
     ((AState.MatchCase and (AView.SelText = AState.SearchText)) or
      ((not AState.MatchCase) and SameText(AView.SelText, AState.SearchText))) then
  begin
    AView.SelText := AState.ReplaceText;
    Result := True;
  end;
  LedFindNext(AView, AState, AState.Backwards);
end;

function LedReplaceAll(AView: TLedEdit; AState: TLedSearchState): Integer;
begin
  Result := 0;
  if (AView = nil) or (AState.SearchText = '') or AView.ReadOnly then Exit;
  Result := AView.SearchReplace(AState.SearchText, AState.ReplaceText,
    AState.Options + [ssoReplaceAll, ssoEntireScope]);
end;

procedure LedUpdateHighlightAll(AView: TLedEdit; AState: TLedSearchState);
var
  M: TSynEditMarkupHighlightAllCaret;
begin
  if AView = nil then Exit;
  M := TSynEditMarkupHighlightAllCaret(
    AView.MarkupByClass[TSynEditMarkupHighlightAllCaret]);
  if M = nil then Exit;
  { The caret-driven markup is repurposed as the search highlighter: setting
    a search string makes it paint that instead of the word under the caret. }
  if AState.HighlightAll and (AState.SearchText <> '') then
  begin
    M.SearchOptions := AState.Options;
    M.SearchString := AState.SearchText;
  end
  else
    M.SearchString := '';
end;

{ --- the dialog ----------------------------------------------------------- }

constructor TLedFindForm.CreateFor(AOwner: TComponent; AState: TLedSearchState;
  AGetView: TLedViewFunc);
begin
  inherited CreateNew(AOwner);
  FState := AState;
  FGetView := AGetView;
  BuildUI;
end;

{ Built in code rather than as a designed form: it is a plain two-column grid
  of labels and controls, and the layout is easier to follow here than in an
  .lfm. }
procedure TLedFindForm.BuildUI;
const
  Gap = 8;
var
  Y: Integer;

  function MakeCheck(const ACaption: string; ALeft, ATop: Integer): TCheckBox;
  begin
    Result := TCheckBox.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.Left := ALeft;
    Result.Top := ATop;
    Result.Width := 150;
    Result.OnChange := @OptionChanged;
  end;

  function MakeButton(const ACaption: string; ALeft, ATop: Integer;
    AHandler: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.Left := ALeft;
    Result.Top := ATop;
    Result.Width := 100;
    Result.OnClick := AHandler;
  end;

  procedure MakeLabel(const ACaption: string; ALeft, ATop: Integer);
  var
    L: TLabel;
  begin
    L := TLabel.Create(Self);
    L.Parent := Self;
    L.Caption := ACaption;
    L.Left := ALeft;
    L.Top := ATop + 4;
  end;

begin
  Caption := 'Find and Replace';
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  ClientWidth := 470;

  Y := Gap;
  MakeLabel('Find:', Gap, Y);
  FCboFind := TComboBox.Create(Self);
  FCboFind.Parent := Self;
  FCboFind.Left := 80;
  FCboFind.Top := Y;
  FCboFind.Width := 270;
  Y := Y + 32;

  MakeLabel('Replace with:', Gap, Y);
  FCboReplace := TComboBox.Create(Self);
  FCboReplace.Parent := Self;
  FCboReplace.Left := 80;
  FCboReplace.Top := Y;
  FCboReplace.Width := 270;
  Y := Y + 36;

  FChkCase      := MakeCheck('Match &case', Gap, Y);
  FChkWord      := MakeCheck('&Whole words only', 180, Y);
  Y := Y + 26;
  FChkRegex     := MakeCheck('Regular e&xpression', Gap, Y);
  FChkSelection := MakeCheck('In &selection only', 180, Y);
  Y := Y + 26;
  FChkHighlight := MakeCheck('&Highlight all matches', Gap, Y);
  Y := Y + 32;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := Self;
  FLblStatus.Left := Gap;
  FLblStatus.Top := Y;
  FLblStatus.Width := 340;
  Y := Y + 24;

  MakeButton('Find &Next', 360, Gap, @DoFindNext);
  MakeButton('Find &Previous', 360, Gap + 30, @DoFindPrev);
  MakeButton('&Replace', 360, Gap + 68, @DoReplace);
  MakeButton('Replace &All', 360, Gap + 98, @DoReplaceAll);
  MakeButton('Close', 360, Gap + 136, @DoClose);

  ClientHeight := Y + Gap;
end;

procedure TLedFindForm.Pull;
begin
  FCboFind.Items.Assign(FState.History);
  FCboReplace.Items.Assign(FState.ReplaceHistory);
  FCboFind.Text := FState.SearchText;
  FCboReplace.Text := FState.ReplaceText;
  FChkCase.Checked := FState.MatchCase;
  FChkWord.Checked := FState.WholeWord;
  FChkRegex.Checked := FState.Regex;
  FChkSelection.Checked := FState.SelectedOnly;
  FChkHighlight.Checked := FState.HighlightAll;
end;

procedure TLedFindForm.Push;
begin
  FState.SearchText := FCboFind.Text;
  FState.ReplaceText := FCboReplace.Text;
  FState.MatchCase := FChkCase.Checked;
  FState.WholeWord := FChkWord.Checked;
  FState.Regex := FChkRegex.Checked;
  FState.SelectedOnly := FChkSelection.Checked;
  FState.HighlightAll := FChkHighlight.Checked;
end;

procedure TLedFindForm.OptionChanged(Sender: TObject);
begin
  Push;
  LedUpdateHighlightAll(FGetView(), FState);
end;

procedure TLedFindForm.Report(AOutcome: TLedFindOutcome);
begin
  case AOutcome of
    lfoFound:   FLblStatus.Caption := '';
    lfoWrapped: FLblStatus.Caption := 'Wrapped around.';
    lfoNotFound: FLblStatus.Caption :=
      Format('"%s" not found.', [FState.SearchText]);
  end;
end;

procedure TLedFindForm.DoFindNext(Sender: TObject);
begin
  Push;
  FState.RememberSearch(FState.SearchText);
  LedUpdateHighlightAll(FGetView(), FState);
  Report(LedFindNext(FGetView(), FState, False));
end;

procedure TLedFindForm.DoFindPrev(Sender: TObject);
begin
  Push;
  FState.RememberSearch(FState.SearchText);
  LedUpdateHighlightAll(FGetView(), FState);
  Report(LedFindNext(FGetView(), FState, True));
end;

procedure TLedFindForm.DoReplace(Sender: TObject);
begin
  Push;
  FState.RememberSearch(FState.SearchText);
  FState.RememberReplace(FState.ReplaceText);
  LedReplaceOne(FGetView(), FState);
end;

procedure TLedFindForm.DoReplaceAll(Sender: TObject);
var
  N: Integer;
begin
  Push;
  FState.RememberSearch(FState.SearchText);
  FState.RememberReplace(FState.ReplaceText);
  N := LedReplaceAll(FGetView(), FState);
  if N = 1 then
    FLblStatus.Caption := '1 replacement.'
  else
    FLblStatus.Caption := Format('%d replacements.', [N]);
end;

procedure TLedFindForm.DoClose(Sender: TObject);
begin
  Hide;
end;

procedure TLedFindForm.ShowFor(AReplace: Boolean);
var
  V: TLedEdit;
begin
  V := FGetView();
  { Seed from the selection, which is what the user almost always meant. }
  if (V <> nil) and V.SelAvail and (Pos(#10, V.SelText) = 0) then
    FState.SearchText := V.SelText;
  Pull;
  FCboReplace.Enabled := AReplace;
  FLblStatus.Caption := '';
  Show;
  FCboFind.SetFocus;
end;

{ --- the incremental bar --------------------------------------------------- }

constructor TLedFindBar.CreateFor(AOwner: TComponent; AState: TLedSearchState;
  AGetView: TLedViewFunc);
var
  B: TButton;
begin
  inherited Create(AOwner);
  FState := AState;
  FGetView := AGetView;
  BevelOuter := bvNone;
  Caption := '';
  Height := 30;
  Align := alBottom;
  Visible := False;

  FLabel := TLabel.Create(Self);
  FLabel.Parent := Self;
  FLabel.Caption := 'Find:';
  FLabel.Left := 6;
  FLabel.Top := 8;

  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Left := 44;
  FEdit.Top := 4;
  FEdit.Width := 260;
  FEdit.OnChange := @EditChange;
  FEdit.OnKeyDown := @EditKeyDown;

  B := TButton.Create(Self);
  B.Parent := Self; B.Caption := 'Next'; B.Left := 312; B.Top := 3;
  B.Width := 70; B.OnClick := @DoNext;

  B := TButton.Create(Self);
  B.Parent := Self; B.Caption := 'Previous'; B.Left := 388; B.Top := 3;
  B.Width := 80; B.OnClick := @DoPrev;

  B := TButton.Create(Self);
  B.Parent := Self; B.Caption := 'Close'; B.Left := 474; B.Top := 3;
  B.Width := 70; B.OnClick := @DoHide;
end;

procedure TLedFindBar.Activate;
var
  V: TLedEdit;
begin
  V := FGetView();
  if V <> nil then FStartPos := V.CaretXY;
  Visible := True;
  FEdit.SelectAll;
  FEdit.SetFocus;
end;

{ Incremental: every keystroke restarts from where the search began, so
  deleting a character widens the match rather than skipping ahead. }
procedure TLedFindBar.EditChange(Sender: TObject);
var
  V: TLedEdit;
begin
  V := FGetView();
  if V = nil then Exit;
  FState.SearchText := FEdit.Text;
  LedUpdateHighlightAll(V, FState);
  if FEdit.Text = '' then
  begin
    FEdit.Color := clWindow;
    Exit;
  end;
  V.CaretXY := FStartPos;
  if LedFindNext(V, FState, False) = lfoNotFound then
    FEdit.Color := $C0C0FF          { a soft red: no match }
  else
    FEdit.Color := clWindow;
end;

procedure TLedFindBar.EditKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      begin
        Key := 0;
        DoHide(nil);
      end;
    VK_RETURN:
      begin
        Key := 0;
        if ssShift in Shift then DoPrev(nil) else DoNext(nil);
      end;
  end;
end;

procedure TLedFindBar.DoNext(Sender: TObject);
begin
  FState.SearchText := FEdit.Text;
  LedFindNext(FGetView(), FState, False);
end;

procedure TLedFindBar.DoPrev(Sender: TObject);
begin
  FState.SearchText := FEdit.Text;
  LedFindNext(FGetView(), FState, True);
end;

procedure TLedFindBar.DoHide(Sender: TObject);
var
  V: TLedEdit;
begin
  Visible := False;
  V := FGetView();
  if V <> nil then
  begin
    FState.SearchText := '';
    LedUpdateHighlightAll(V, FState);
    FState.SearchText := FEdit.Text;
    if V.CanFocus then V.SetFocus;
  end;
end;

end.
