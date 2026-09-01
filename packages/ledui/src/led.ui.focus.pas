{ led - a light editor.  Focusing a control without risking an exception.

  The obvious LCL idiom is a trap:

      if View.CanFocus then View.SetFocus;

  TWinControl.CanFocus walks up the parent chain checking that everything is
  visible and enabled, but it stops at the form and deliberately does not test
  it (wincontrol.inc: "if Control = Form then break").  TWinControl.SetFocus
  then calls Form.FocusControl, which calls Form.SetFocus, which raises
  EInvalidOperation when the form is not visible and enabled -- the LCL source
  even carries the comment "if not CanFocus then this will raise an
  exception".

  So the guard misses exactly the case that fails.  The form is not visible
  during FormCreate, and it is not enabled for as long as a modal dialog is
  up, and in both of those states any attempt to focus an editor view puts a
  "Can not focus / risk data corruption" dialog in the user's face.

  LedTryFocus asks the question the idiom meant to ask.  Focus is a courtesy,
  never a correctness requirement, so it reports failure rather than raising
  and the caller is free to ignore the result. }
unit Led.UI.Focus;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms;

{ Focuses AControl if it can genuinely be focused right now.  Returns whether
  it did. }
function LedTryFocus(AControl: TControl): Boolean;

{ True when AControl could be focused right now, form included. }
function LedCanReallyFocus(AControl: TControl): Boolean;

implementation

function LedCanReallyFocus(AControl: TControl): Boolean;
var
  Win: TWinControl;
  Form: TCustomForm;
begin
  Result := False;
  if not (AControl is TWinControl) then Exit;
  Win := TWinControl(AControl);
  if not Win.HandleAllocated then Exit;
  if not Win.CanFocus then Exit;

  Form := GetParentForm(Win);
  if Form = nil then Exit;
  { The test CanFocus skips.  An already-active form is fine whatever it
    reports, because FocusControl only calls SetFocus when the form was not
    active to begin with. }
  Result := Form.Active or (Form.IsControlVisible and Form.Enabled);
end;

function LedTryFocus(AControl: TControl): Boolean;
begin
  Result := False;
  if not LedCanReallyFocus(AControl) then Exit;
  try
    TWinControl(AControl).SetFocus;
    Result := True;
  except
    on EInvalidOperation do
      { Lost a race with the widgetset -- the form stopped being focusable
        between the check and the call.  Not worth a dialog. }
      Result := False;
  end;
end;

end.
