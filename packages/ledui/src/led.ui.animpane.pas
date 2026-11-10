{ LED - a lightweight editor.  The animation pane of the visual editor.

  Beside a presentation's slide, as PowerPoint's Animation Pane and Transitions tab have it: the slide's transition
  (its kind, direction, speed, and whether a click or a time goes on), and the list of its animations in the order
  they play, each numbered by the click it plays on. One is added to the shape selected (Add), taken away, moved,
  made another effect, started on a click, with the one before it or after it, given a duration and a delay.
  Picking one in the list selects its shape on the slide.

  The slide's timing is read with paradeanim and set again on every change (TParadeEdit.SetSlideTiming): the slide
  show plays it at once and the PowerPoint export writes it. Each change is a step of Undo ("Animation"); the pane
  reads the slide again when Undo or Redo changes it.

  Every control has a name, so the self-test works it as a writer would. }

unit Led.UI.AnimPane;

{$mode objfpc}{$H+}
{$I led.parade.inc}

interface

{$IFDEF LED_PARADE}
uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Menus, Spin, Graphics, Forms,
  parade, paradeedit, paradeanim;

type
  TLedAnimPane = class(TPanel)
  private
    FEdit: TParadeEdit;
    FAnim: TParadeAnim;
    FSlide: Integer;
    FInner: string;             { the slide's timing as last read or set }
    FFilling, FCommitting: Boolean;
    FShapes: TParadeAnimShapes;
    FPresets: array of TAnimPreset;
    FTransBox, FEffBox: TGroupBox;
    FTransKind, FTransDir, FTransSpeed: TComboBox;
    FTransClick, FTransAfter: TCheckBox;
    FTransTime: TFloatSpinEdit;
    FTransAll: TButton;
    FList: TListBox;
    FAddBtn, FRemoveBtn, FUpBtn, FDownBtn, FPlayBtn: TButton;
    FAddMenu: TPopupMenu;
    FEffKind, FEffDir, FEffStart: TComboBox;
    FEffDur, FEffDelay: TFloatSpinEdit;
    FNoShape: TLabel;
    FOnPlay: TNotifyEvent;
    function Row(AParent: TWinControl; const ACaption: string; AControl: TControl): TPanel;
    function Combo(AParent: TWinControl; const AName: string; AOnChange: TNotifyEvent): TComboBox;
    function Spin(AParent: TWinControl; const AName: string; AOnChange: TNotifyEvent): TFloatSpinEdit;
    function Btn(AParent: TWinControl; const AName, ACaption, AHint: string; AOnClick: TNotifyEvent): TButton;
    function ShapeName(Id: Int32): string;
    function EffectText(I: Integer): string;
    procedure FillAll(Sel: Integer);
    procedure FillTrans;
    procedure FillList(Sel: Integer);
    procedure FillEffect;
    procedure UpdateEnabled;
    procedure Commit(Sel: Integer);
    procedure TransChanged(Sender: TObject);
    procedure TransAllClicked(Sender: TObject);
    procedure ListClicked(Sender: TObject);
    procedure AddClicked(Sender: TObject);
    procedure AddItemClicked(Sender: TObject);
    procedure RemoveClicked(Sender: TObject);
    procedure UpClicked(Sender: TObject);
    procedure DownClicked(Sender: TObject);
    procedure PlayClicked(Sender: TObject);
    procedure EffKindChanged(Sender: TObject);
    procedure EffDirChanged(Sender: TObject);
    procedure EffTimingChanged(Sender: TObject);
    function TransFromControls(out Kind, Dir, Speed: string; out AdvClick: Boolean; out AdvTime: Integer): Boolean;
  public
    constructor Create(AOwner: TComponent; AEdit: TParadeEdit); reintroduce;
    destructor Destroy; override;
    { the slide being edited: its timing read again when it is another slide or was changed elsewhere; the
      buttons as the selection allows }
    procedure Follow;
    { an effect (an AnimPresets index) added to the shape selected, after the one picked in the list; False when no
      shape is selected }
    function AddPreset(Index: Integer): Boolean;
    property Anim: TParadeAnim read FAnim;
    property Slide: Integer read FSlide;
    property OnPlay: TNotifyEvent read FOnPlay write FOnPlay;
  end;
{$ENDIF}

implementation

{$IFDEF LED_PARADE}
uses
  Math, StrUtils, Led.UI.Dpi;

const
  Speeds: array[0..2] of string = ('fast', 'med', 'slow');
  SpeedNames: array[0..2] of string = ('Fast', 'Medium', 'Slow');

function ClsName(const Cls: string): string;
begin
  case Cls of
    'entr': Result := 'Entrance';
    'exit': Result := 'Exit';
    'emph': Result := 'Emphasis';
    'path': Result := 'Motion path';
  else
    Result := Cls;
  end;
end;

constructor TLedAnimPane.Create(AOwner: TComponent; AEdit: TParadeEdit);
var
  P: TPanel;
  I: Integer;
  Sub: array[0..2] of TMenuItem;
  M: TMenuItem;
  K: string;
begin
  inherited Create(AOwner);
  FEdit := AEdit;
  FAnim := TParadeAnim.Create;
  FSlide := -2;
  FPresets := AnimPresets;
  Caption := '';
  BevelOuter := bvNone;
  Width := LedScale96(270);
  Name := 'AnimPane';

  { the transition }
  FTransBox := TGroupBox.Create(Self);
  FTransBox.Parent := Self;
  FTransBox.Align := alTop;
  FTransBox.Caption := 'Transition to this slide';
  FTransBox.AutoSize := True;
  FTransBox.BorderSpacing.Around := LedScale96(4);
  FTransKind := Combo(FTransBox, 'AnimTransKind', @TransChanged);
  FTransKind.Items.AddObject('None', nil);
  for K in SplitString(AnimTransKinds, ',') do
    FTransKind.Items.Add(AnimTransName(K));
  FTransDir := Combo(FTransBox, 'AnimTransDir', @TransChanged);
  FTransSpeed := Combo(FTransBox, 'AnimTransSpeed', @TransChanged);
  for I := 0 to High(SpeedNames) do
    FTransSpeed.Items.Add(SpeedNames[I]);
  FTransClick := TCheckBox.Create(Self);
  FTransClick.Name := 'AnimTransClick';
  FTransClick.Caption := 'On mouse click';
  FTransClick.OnChange := @TransChanged;
  FTransAfter := TCheckBox.Create(Self);
  FTransAfter.Name := 'AnimTransAfter';
  FTransAfter.Caption := 'After (s)';
  FTransAfter.OnChange := @TransChanged;
  FTransTime := Spin(FTransBox, 'AnimTransTime', @TransChanged);
  FTransTime.MaxValue := 3600;
  FTransAll := Btn(FTransBox, 'AnimTransAll', 'Apply to all slides', 'Every slide given this transition and advance',
    @TransAllClicked);
  { (in their order, from the top: each row aligned to the top after the one before it) }
  Row(FTransBox, 'Effect', FTransKind);
  Row(FTransBox, 'Direction', FTransDir);
  Row(FTransBox, 'Speed', FTransSpeed);
  Row(FTransBox, 'Advance', FTransClick);
  P := Row(FTransBox, '', FTransTime);
  FTransAfter.Parent := P;
  FTransAfter.Align := alLeft;
  FTransAfter.Width := LedScale96(80);
  FTransTime.Align := alLeft;
  FTransTime.Width := LedScale96(70);
  FTransTime.Left := LedScale96(200);
  Row(FTransBox, '', FTransAll).Height := LedScale96(30);

  { the animations }
  FEffBox := TGroupBox.Create(Self);
  FEffBox.Parent := Self;
  FEffBox.Align := alClient;
  FEffBox.Caption := 'Animations on this slide';
  FEffBox.BorderSpacing.Around := LedScale96(4);
  P := TPanel.Create(Self);
  P.Parent := FEffBox;
  P.Align := alTop;
  P.BevelOuter := bvNone;
  P.Caption := '';
  P.Height := LedScale96(30);
  FAddBtn := Btn(P, 'AnimAdd', 'Add...', 'An animation for the shape selected on the slide', @AddClicked);
  FRemoveBtn := Btn(P, 'AnimRemove', 'Remove', 'The animation picked taken away', @RemoveClicked);
  FUpBtn := Btn(P, 'AnimUp', 'Up', 'The animation picked played earlier', @UpClicked);
  FDownBtn := Btn(P, 'AnimDown', 'Down', 'The animation picked played later', @DownClicked);
  FPlayBtn := Btn(P, 'AnimPlay', 'Play', 'The slide show from this slide', @PlayClicked);
  for I := 0 to P.ControlCount - 1 do
  begin
    P.Controls[I].Align := alLeft;
    P.Controls[I].AutoSize := True;
    P.Controls[I].BorderSpacing.Right := LedScale96(2);
  end;
  FAddBtn.Left := 0;
  FRemoveBtn.Left := 100;
  FUpBtn.Left := 200;
  FDownBtn.Left := 300;
  FPlayBtn.Left := 400;
  FNoShape := TLabel.Create(Self);
  FNoShape.Parent := FEffBox;
  FNoShape.Align := alTop;
  FNoShape.Top := 40;
  FNoShape.WordWrap := True;
  FNoShape.Caption := 'Select a shape on the slide to add an animation to it.';
  FNoShape.Font.Color := clGrayText;
  FNoShape.BorderSpacing.Around := LedScale96(2);
  FAddMenu := TPopupMenu.Create(Self);
  Sub[0] := TMenuItem.Create(FAddMenu);
  Sub[0].Caption := 'Entrance';
  Sub[1] := TMenuItem.Create(FAddMenu);
  Sub[1].Caption := 'Emphasis';
  Sub[2] := TMenuItem.Create(FAddMenu);
  Sub[2].Caption := 'Exit';
  for I := 0 to 2 do
    FAddMenu.Items.Add(Sub[I]);
  for I := 0 to High(FPresets) do
  begin
    M := TMenuItem.Create(FAddMenu);
    M.Caption := FPresets[I].Name;
    M.Tag := I;
    M.OnClick := @AddItemClicked;
    if FPresets[I].Cls = 'entr' then
      Sub[0].Add(M)
    else if FPresets[I].Cls = 'emph' then
      Sub[1].Add(M)
    else
      Sub[2].Add(M);
  end;

  P := TPanel.Create(Self);   { the one picked }
  P.Parent := FEffBox;
  P.Align := alBottom;
  P.BevelOuter := bvNone;
  P.Caption := '';
  P.AutoSize := True;
  FEffKind := Combo(P, 'AnimEffKind', @EffKindChanged);
  FEffDir := Combo(P, 'AnimEffDir', @EffDirChanged);
  FEffStart := Combo(P, 'AnimEffStart', @EffTimingChanged);
  FEffStart.Items.Add('On click');
  FEffStart.Items.Add('With previous');
  FEffStart.Items.Add('After previous');
  FEffDur := Spin(P, 'AnimEffDur', @EffTimingChanged);
  FEffDur.MinValue := 0.01;
  FEffDur.MaxValue := 60;
  FEffDelay := Spin(P, 'AnimEffDelay', @EffTimingChanged);
  FEffDelay.MaxValue := 60;
  Row(P, 'Effect', FEffKind);
  Row(P, 'Direction', FEffDir);
  Row(P, 'Start', FEffStart);
  Row(P, 'Duration (s)', FEffDur);
  Row(P, 'Delay (s)', FEffDelay);

  FList := TListBox.Create(Self);
  FList.Name := 'AnimList';
  FList.Parent := FEffBox;
  FList.Align := alClient;
  FList.BorderSpacing.Around := LedScale96(2);
  FList.OnClick := @ListClicked;
  FillAll(-1);
end;

destructor TLedAnimPane.Destroy;
begin
  FAnim.Free;
  inherited Destroy;
end;

function TLedAnimPane.Row(AParent: TWinControl; const ACaption: string; AControl: TControl): TPanel;
var
  L: TLabel;
  I: Integer;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.Height := LedScale96(26);
  Result.Align := alTop;
  Result.Top := 0;
  for I := 0 to AParent.ControlCount - 1 do   { below the rows before it }
    if (AParent.Controls[I] <> Result) and (AParent.Controls[I].Align = alTop) then
      Result.Top := Max(Result.Top, AParent.Controls[I].Top + AParent.Controls[I].Height + 1);
  L := TLabel.Create(Self);
  L.Parent := Result;
  L.Align := alLeft;
  L.Width := LedScale96(80);
  L.AutoSize := False;
  L.Layout := tlCenter;
  L.Caption := ACaption;
  L.BorderSpacing.Left := LedScale96(4);
  AControl.Parent := Result;
  AControl.Align := alClient;
  AControl.BorderSpacing.Around := LedScale96(1);
end;

function TLedAnimPane.Combo(AParent: TWinControl; const AName: string; AOnChange: TNotifyEvent): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Name := AName;
  Result.Style := csDropDownList;
  Result.Parent := AParent;
  Result.OnChange := AOnChange;
end;

function TLedAnimPane.Spin(AParent: TWinControl; const AName: string; AOnChange: TNotifyEvent): TFloatSpinEdit;
begin
  Result := TFloatSpinEdit.Create(Self);
  Result.Name := AName;
  Result.Parent := AParent;
  Result.DecimalPlaces := 2;
  Result.Increment := 0.25;
  Result.MinValue := 0;
  Result.OnChange := AOnChange;
end;

function TLedAnimPane.Btn(AParent: TWinControl; const AName, ACaption, AHint: string; AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Name := AName;
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.OnClick := AOnClick;
end;

function TLedAnimPane.ShapeName(Id: Int32): string;
var
  I: Integer;
begin
  for I := 0 to High(FShapes) do
    if FShapes[I].Id = Id then
      if FShapes[I].Name <> '' then
        Exit(FShapes[I].Name)
      else
        Exit('Shape ' + IntToStr(Id));
  Result := 'Shape ' + IntToStr(Id) + ' (not on the slide)';
end;

function TLedAnimPane.EffectText(I: Integer): string;
var
  E: TAnimEffect;
begin
  E := FAnim.Effects[I];
  case E.Start of
    asClick: Result := IntToStr(FAnim.ClickOf(I)) + '.  ';
    asWith: Result := '      with: ';
  else
    Result := '      after: ';
  end;
  Result := Result + AnimPresetName(E.Cls, E.Preset);
  if E.Cls = 'exit' then
    Result := Result + ' (exit)'
  else if E.Cls = 'emph' then
    Result := Result + ' (emphasis)';
  Result := Result + ' - ' + ShapeName(E.Shape);
  if E.ParaSt >= 0 then
    if E.ParaEnd > E.ParaSt then
      Result := Result + Format(', paragraphs %d-%d', [E.ParaSt + 1, E.ParaEnd + 1])
    else
      Result := Result + Format(', paragraph %d', [E.ParaSt + 1]);
end;

procedure TLedAnimPane.Follow;
var
  S: Integer;
  X: string;
begin
  if FCommitting or (FEdit = nil) then
    Exit;
  S := FEdit.CurrentSlide;
  if S >= 0 then
    X := FEdit.SlideTiming(S)
  else
    X := '';
  if (S <> FSlide) or (ParadeTailInner(X) <> FInner) then
  begin
    FSlide := S;
    FInner := ParadeTailInner(X);
    FAnim.Load(X);
    FShapes := FEdit.SlideAnimShapes(S);
    FillAll(-1);
  end
  else
    UpdateEnabled;
end;

procedure TLedAnimPane.FillAll(Sel: Integer);
begin
  FillTrans;
  FillList(Sel);
end;

procedure TLedAnimPane.FillTrans;
var
  I: Integer;
  Kinds: TStringArray;
  D: string;
begin
  FFilling := True;
  try
    Kinds := SplitString(AnimTransKinds, ',');
    while FTransKind.Items.Count > Length(Kinds) + 1 do   { (a kind as read, not one made here: the last) }
      FTransKind.Items.Delete(FTransKind.Items.Count - 1);
    FTransKind.ItemIndex := 0;
    if FAnim.Trans.Kind <> '' then
    begin
      for I := 0 to High(Kinds) do
        if Kinds[I] = FAnim.Trans.Kind then
          FTransKind.ItemIndex := I + 1;
      if FTransKind.ItemIndex = 0 then
      begin
        FTransKind.Items.Add(AnimTransName(FAnim.Trans.Kind));
        FTransKind.ItemIndex := FTransKind.Items.Count - 1;
      end;
    end;
    FTransDir.Items.Clear;
    for D in SplitString(AnimTransDirs(FAnim.Trans.Kind), ',') do
      if D <> '' then
        FTransDir.Items.Add(AnimDirName(D));
    FTransDir.ItemIndex := -1;
    I := 0;
    for D in SplitString(AnimTransDirs(FAnim.Trans.Kind), ',') do
    begin
      if D = FAnim.Trans.Dir then
        FTransDir.ItemIndex := I;
      Inc(I);
    end;
    if (FTransDir.ItemIndex < 0) and (FTransDir.Items.Count > 0) then
      FTransDir.ItemIndex := 0;
    FTransDir.Enabled := FTransDir.Items.Count > 0;
    FTransSpeed.ItemIndex := 0;
    for I := 0 to High(Speeds) do
      if Speeds[I] = FAnim.Trans.Speed then
        FTransSpeed.ItemIndex := I;
    FTransClick.Checked := FAnim.Trans.AdvClick;
    FTransAfter.Checked := FAnim.Trans.AdvTime >= 0;
    FTransTime.Value := Max(0, FAnim.Trans.AdvTime) / 1000;
    FTransTime.Enabled := FTransAfter.Checked;
  finally
    FFilling := False;
  end;
end;

procedure TLedAnimPane.FillList(Sel: Integer);
var
  I: Integer;
begin
  FFilling := True;
  try
    FList.Items.BeginUpdate;
    try
      FList.Items.Clear;
      for I := 0 to High(FAnim.Effects) do
        FList.Items.Add(EffectText(I));
    finally
      FList.Items.EndUpdate;
    end;
    if (Sel >= 0) and (Sel < FList.Items.Count) then
      FList.ItemIndex := Sel
    else
      FList.ItemIndex := -1;
  finally
    FFilling := False;
  end;
  FillEffect;
end;

procedure TLedAnimPane.FillEffect;
var
  I, K, Cur: Integer;
  E: TAnimEffect;
  S: string;
begin
  FFilling := True;
  try
    I := FList.ItemIndex;
    FEffKind.Items.Clear;
    FEffDir.Items.Clear;
    if (I < 0) or (I > High(FAnim.Effects)) then
    begin
      FEffStart.ItemIndex := -1;
      FEffDur.Value := 0;
      FEffDelay.Value := 0;
    end
    else
    begin
      E := FAnim.Effects[I];
      Cur := -1;
      for K := 0 to High(FPresets) do
      begin
        FEffKind.Items.AddObject(ClsName(FPresets[K].Cls) + ': ' + FPresets[K].Name, TObject(PtrInt(K)));
        if (FPresets[K].Cls = E.Cls) and (FPresets[K].Preset = E.Preset) then
          Cur := K;
      end;
      if Cur < 0 then
      begin   { one this pane does not make: as read, first }
        FEffKind.Items.InsertObject(0, ClsName(E.Cls) + ': ' + AnimPresetName(E.Cls, E.Preset) + ' (as read)',
          TObject(PtrInt(-1)));
        FEffKind.ItemIndex := 0;
      end
      else
        FEffKind.ItemIndex := Cur;
      for S in SplitString(AnimSubtypes(E.Cls, E.Preset), ',') do
        if S <> '' then
        begin
          FEffDir.Items.AddObject(AnimSubtypeName(StrToInt(S)), TObject(PtrInt(StrToInt(S))));
          if StrToInt(S) = E.Subtype then
            FEffDir.ItemIndex := FEffDir.Items.Count - 1;
        end;
      FEffStart.ItemIndex := Ord(E.Start);
      FEffDur.Value := IfThen(E.Dur <= 1, 0, E.Dur / 1000);
      FEffDelay.Value := E.Delay / 1000;
    end;
  finally
    FFilling := False;
  end;
  UpdateEnabled;
end;

procedure TLedAnimPane.UpdateEnabled;
var
  I: Integer;
  On, Shape: Boolean;
begin
  I := FList.ItemIndex;
  On := (FSlide >= 0) and not FEdit.ReadOnly;
  Shape := On and (FEdit.SelectedAnimShape <> 0);
  FTransBox.Enabled := On;
  FAddBtn.Enabled := Shape;
  FNoShape.Visible := On and not Shape;
  FRemoveBtn.Enabled := On and (I >= 0);
  FUpBtn.Enabled := On and (I > 0);
  FDownBtn.Enabled := On and (I >= 0) and (I < FList.Items.Count - 1);
  FPlayBtn.Enabled := FSlide >= 0;
  FEffKind.Enabled := On and (I >= 0);
  FEffDir.Enabled := On and (I >= 0) and (FEffDir.Items.Count > 0);
  FEffStart.Enabled := On and (I >= 0);
  FEffDur.Enabled := On and (I >= 0) and (FAnim.Effects[I].Preset <> 1);
  FEffDelay.Enabled := On and (I >= 0);
end;

procedure TLedAnimPane.Commit(Sel: Integer);
begin
  if FSlide < 0 then
    Exit;
  FCommitting := True;
  try
    FEdit.SetSlideTiming(FSlide, FAnim.Save);
    FInner := ParadeTailInner(FEdit.SlideTiming(FSlide));
  finally
    FCommitting := False;
  end;
  FillList(Sel);
end;

function TLedAnimPane.TransFromControls(out Kind, Dir, Speed: string; out AdvClick: Boolean;
  out AdvTime: Integer): Boolean;
var
  Kinds, Dirs: TStringArray;
  I: Integer;
begin
  Kinds := SplitString(AnimTransKinds, ',');
  I := FTransKind.ItemIndex;
  if I <= 0 then
    Kind := ''
  else if I <= Length(Kinds) then
    Kind := Kinds[I - 1]
  else
    Kind := FAnim.Trans.Kind;     { the one as read }
  Dirs := SplitString(AnimTransDirs(Kind), ',');
  Dir := '';
  if Kind = FAnim.Trans.Kind then
    Dir := FAnim.Trans.Dir;
  if (Length(Dirs) > 0) and (Dirs[0] <> '') then
    if (Kind = FAnim.Trans.Kind) and (FTransDir.ItemIndex >= 0) and (FTransDir.ItemIndex <= High(Dirs)) then
      Dir := Dirs[FTransDir.ItemIndex]
    else if Kind <> FAnim.Trans.Kind then
      Dir := Dirs[0];
  Speed := Speeds[Max(0, FTransSpeed.ItemIndex)];
  AdvClick := FTransClick.Checked;
  AdvTime := -1;
  if FTransAfter.Checked then
    AdvTime := Round(FTransTime.Value * 1000);
  Result := True;
end;

procedure TLedAnimPane.TransChanged(Sender: TObject);
var
  Kind, Dir, Speed: string;
  AdvClick: Boolean;
  AdvTime: Integer;
begin
  if FFilling or (FSlide < 0) then
    Exit;
  TransFromControls(Kind, Dir, Speed, AdvClick, AdvTime);
  FAnim.SetTransition(Kind, Dir, Speed, AdvClick, AdvTime);
  Commit(FList.ItemIndex);
  FillTrans;
end;

procedure TLedAnimPane.TransAllClicked(Sender: TObject);
var
  A: TParadeAnim;
  I: Integer;
  Kind, Dir, Speed: string;
  AdvClick: Boolean;
  AdvTime: Integer;
begin
  if FSlide < 0 then
    Exit;
  TransFromControls(Kind, Dir, Speed, AdvClick, AdvTime);
  A := TParadeAnim.Create;
  FCommitting := True;
  try
    for I := 0 to FEdit.SlideCount - 1 do
      if A.Load(FEdit.SlideTiming(I)) then
      begin
        if (I = FSlide) or (A.Trans.Kind <> Kind) or (A.Trans.Dir <> Dir) or (A.Trans.Speed <> Speed) or
           (A.Trans.AdvClick <> AdvClick) or (A.Trans.AdvTime <> AdvTime) then
          A.SetTransition(Kind, Dir, Speed, AdvClick, AdvTime);
        FEdit.SetSlideTiming(I, A.Save);
      end;
  finally
    FCommitting := False;
    A.Free;
  end;
  FSlide := -2;     { read again }
  Follow;
end;

procedure TLedAnimPane.ListClicked(Sender: TObject);
begin
  if FFilling then
    Exit;
  FillEffect;
  if (FList.ItemIndex >= 0) and (FList.ItemIndex <= High(FAnim.Effects)) then
    FEdit.SelectAnimShape(FAnim.Effects[FList.ItemIndex].Shape);
  UpdateEnabled;
end;

procedure TLedAnimPane.AddClicked(Sender: TObject);
var
  P: TPoint;
begin
  P := FAddBtn.ClientToScreen(Point(0, FAddBtn.Height));
  FAddMenu.PopUp(P.X, P.Y);
end;

procedure TLedAnimPane.AddItemClicked(Sender: TObject);
begin
  AddPreset((Sender as TMenuItem).Tag);
end;

function TLedAnimPane.AddPreset(Index: Integer): Boolean;
var
  Sh: Int32;
  At: Integer;
begin
  Sh := FEdit.SelectedAnimShape;
  Result := (FSlide >= 0) and (Sh <> 0) and (Index >= 0) and (Index <= High(FPresets)) and not FEdit.ReadOnly;
  if not Result then
    Exit;
  At := -1;
  if FList.ItemIndex >= 0 then
    At := FList.ItemIndex + 1;
  At := FAnim.Add(Sh, FPresets[Index].Cls, FPresets[Index].Preset, FPresets[Index].Subtype, asClick,
    IfThen((FPresets[Index].Cls = 'emph') and (FPresets[Index].Preset = 32), 1000, 500), At);   { (a Teeter: a second) }
  Commit(At);
end;

procedure TLedAnimPane.RemoveClicked(Sender: TObject);
var
  I: Integer;
begin
  I := FList.ItemIndex;
  if I < 0 then
    Exit;
  FAnim.Delete(I);
  Commit(Min(I, High(FAnim.Effects)));
end;

procedure TLedAnimPane.UpClicked(Sender: TObject);
var
  I: Integer;
begin
  I := FList.ItemIndex;
  if I <= 0 then
    Exit;
  FAnim.Move(I, I - 1);
  Commit(I - 1);
end;

procedure TLedAnimPane.DownClicked(Sender: TObject);
var
  I: Integer;
begin
  I := FList.ItemIndex;
  if (I < 0) or (I >= High(FAnim.Effects)) then
    Exit;
  FAnim.Move(I, I + 1);
  Commit(I + 1);
end;

procedure TLedAnimPane.PlayClicked(Sender: TObject);
begin
  if Assigned(FOnPlay) then
    FOnPlay(Self);
end;

procedure TLedAnimPane.EffKindChanged(Sender: TObject);
var
  I, K: Integer;
begin
  I := FList.ItemIndex;
  if FFilling or (I < 0) or (FEffKind.ItemIndex < 0) then
    Exit;
  K := PtrInt(FEffKind.Items.Objects[FEffKind.ItemIndex]);
  if K < 0 then
    Exit;
  FAnim.SetPreset(I, FPresets[K].Cls, FPresets[K].Preset, FPresets[K].Subtype);
  Commit(I);
end;

procedure TLedAnimPane.EffDirChanged(Sender: TObject);
var
  I: Integer;
  E: TAnimEffect;
begin
  I := FList.ItemIndex;
  if FFilling or (I < 0) or (FEffDir.ItemIndex < 0) then
    Exit;
  E := FAnim.Effects[I];
  FAnim.SetPreset(I, E.Cls, E.Preset, PtrInt(FEffDir.Items.Objects[FEffDir.ItemIndex]));
  Commit(I);
end;

procedure TLedAnimPane.EffTimingChanged(Sender: TObject);
var
  I: Integer;
begin
  I := FList.ItemIndex;
  if FFilling or (I < 0) or (I > High(FAnim.Effects)) then
    Exit;
  if FEffStart.ItemIndex >= 0 then
    FAnim.Effects[I].Start := TAnimStart(FEffStart.ItemIndex);
  if FAnim.Effects[I].Preset <> 1 then
    FAnim.Effects[I].Dur := Max(10, Round(FEffDur.Value * 1000));
  FAnim.Effects[I].Delay := Max(0, Round(FEffDelay.Value * 1000));
  Commit(I);
end;
{$ENDIF}

end.
