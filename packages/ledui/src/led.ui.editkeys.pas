{ LED - a lightweight editor.  The editing keys belong to the box the caret
  is in.

  Reported as: Ctrl+F, then paste, and the text lands in the document behind
  the search window instead of in the search box.

  It is the LCL's shortcut order, and it is documented in its own source.
  TApplication.IsShortcut offers a key to the focused form first and then,
  if that form did not want it, to the *main* form:

      // let the main form handle the shortcut
      if Assigned(MainForm) and (Screen.ActiveCustomForm <> MainForm) ...
        Result := FMainForm.IsShortcut(Message);

  A dialog of plain controls has no shortcuts of its own, so every editing
  key it is given falls through to LED's window, where Ctrl+V is the
  editor's Paste action -- and that action pastes into the document.  The
  same happens without a second window at all: a box inside the main window,
  like the incremental find bar, loses the key to the main form's own
  shortcut lookup before the box ever sees it.

  So the keys are claimed here, before either form is asked, whenever the
  caret is in an ordinary text box.  A claimed key is not delivered, so the
  work is done here too: copy, cut, paste and select-all, on the control
  that has the caret.

  The document's own editor is deliberately not included.  It is a SynEdit,
  not a TCustomEdit, so it does not match -- and its editing keys should go
  on reaching the window's actions, which is what puts them in the menu,
  through the undo the document owns. }
unit Led.UI.EditKeys;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, StdCtrls, Clipbrd, LCLType, LMessages,
  LCLProc;

{ Installs the guard on Application.OnShortcut.  Call once at startup. }
procedure LedInstallEditKeyGuard;

{ What Ctrl and this key should do to this control, and whether it did it --
  which is also the answer to "is this key a shortcut", since a key that has
  been dealt with must not be delivered again.

  Split out from the hook because the hook cannot be driven from a script:
  the LCL reads the live modifier state off the keyboard rather than out of
  the message, so a check has no way to say "Ctrl was down".  Here it says
  so by passing it. }
function LedEditKeyAction(AKey: Word; AShift: TShiftState;
  AControl: TWinControl): Boolean;

{ The four operations, on whatever control has the caret.  Each answers
  whether it did anything, so a control that cannot do it -- a drop-down
  list has no text to cut -- leaves the key alone.  Public for the
  self-test, which drives them without a keyboard. }
function LedEditCopy(AControl: TWinControl): Boolean;
function LedEditCut(AControl: TWinControl): Boolean;
function LedEditPaste(AControl: TWinControl): Boolean;
function LedEditSelectAll(AControl: TWinControl): Boolean;

implementation

type
  { OnShortcut is a method pointer and there is no object to hang it on, so
    this is the object. }
  TLedKeyGuard = class
    procedure Shortcut(var AMessage: TLMKey; var AHandled: Boolean);
  end;

var
  GGuard: TLedKeyGuard = nil;

{ Whether this control edits text of its own.  A combo that only drops down
  a list does not: it has no caret, and its keys belong to the list. }
function Editable(AControl: TWinControl; out AEdit: TCustomEdit;
  out ACombo: TCustomComboBox): Boolean;
begin
  AEdit := nil;
  ACombo := nil;
  if AControl = nil then Exit(False);
  if AControl is TCustomEdit then
    AEdit := TCustomEdit(AControl)
  else if AControl is TCustomComboBox then
  begin
    ACombo := TCustomComboBox(AControl);
    if ACombo.Style = csDropDownList then ACombo := nil;
  end;
  Result := (AEdit <> nil) or (ACombo <> nil);
end;

function LedEditCopy(AControl: TWinControl): Boolean;
var
  E: TCustomEdit;
  C: TCustomComboBox;
begin
  Result := False;
  if not Editable(AControl, E, C) then Exit;
  if E <> nil then
  begin
    E.CopyToClipboard;
    Exit(True);
  end;
  { A combo has the selection but not the clipboard methods. }
  if C.SelText = '' then Exit;
  Clipboard.AsText := C.SelText;
  Result := True;
end;

function LedEditCut(AControl: TWinControl): Boolean;
var
  E: TCustomEdit;
  C: TCustomComboBox;
begin
  Result := False;
  if not Editable(AControl, E, C) then Exit;
  if E <> nil then
  begin
    if E.ReadOnly then Exit;
    E.CutToClipboard;
    Exit(True);
  end;
  if C.ReadOnly or (C.SelText = '') then Exit;
  Clipboard.AsText := C.SelText;
  C.SelText := '';
  Result := True;
end;

function LedEditPaste(AControl: TWinControl): Boolean;
var
  E: TCustomEdit;
  C: TCustomComboBox;
begin
  Result := False;
  if not Editable(AControl, E, C) then Exit;
  if E <> nil then
  begin
    if E.ReadOnly then Exit;
    E.PasteFromClipboard;
    Exit(True);
  end;
  if C.ReadOnly then Exit;
  { Over the selection, which is what pasting means everywhere else. }
  C.SelText := Clipboard.AsText;
  Result := True;
end;

function LedEditSelectAll(AControl: TWinControl): Boolean;
var
  E: TCustomEdit;
  C: TCustomComboBox;
begin
  Result := False;
  if not Editable(AControl, E, C) then Exit;
  if E <> nil then
    E.SelectAll
  else
    C.SelectAll;
  Result := True;
end;

function LedEditKeyAction(AKey: Word; AShift: TShiftState;
  AControl: TWinControl): Boolean;
begin
  Result := False;
  { Ctrl and nothing else: Ctrl+Shift+V is the editor's column paste, and
    Ctrl+Alt belongs to somebody else. }
  if AShift * [ssCtrl, ssAlt, ssShift, ssMeta] <> [ssCtrl] then Exit;
  case AKey of
    VK_C: Result := LedEditCopy(AControl);
    VK_X: Result := LedEditCut(AControl);
    VK_V: Result := LedEditPaste(AControl);
    VK_A: Result := LedEditSelectAll(AControl);
  end;
end;

procedure TLedKeyGuard.Shortcut(var AMessage: TLMKey; var AHandled: Boolean);
begin
  if AHandled then Exit;
  AHandled := LedEditKeyAction(AMessage.CharCode,
    KeyDataToShiftState(AMessage.KeyData), Screen.ActiveControl);
end;

procedure LedInstallEditKeyGuard;
begin
  if GGuard = nil then GGuard := TLedKeyGuard.Create;
  Application.OnShortcut := @GGuard.Shortcut;
end;

finalization
  FreeAndNil(GGuard);

end.
