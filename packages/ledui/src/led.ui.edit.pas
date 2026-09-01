{ led - a light editor.  The editor view control.

  One TLedEdit is one *view*.  A document may own several of them, all sharing
  a single text buffer, which is how split view works. }
unit Led.UI.Edit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Graphics, SynEdit, SynEditTypes;

type
  TLedEdit = class(TSynEdit)
  private
    FDocument: TObject;   // the owning TLedDocument; typed loosely to avoid
                          // a circular unit reference
  public
    constructor Create(AOwner: TComponent); override;
    property Document: TObject read FDocument write FDocument;
  end;

implementation

constructor TLedEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  Options := Options
    + [eoBracketHighlight,     // matching-bracket markup
       eoGroupUndo,            // coalesce typing into one undo step
       eoTabIndent,            // Tab indents a selected block
       eoEnhanceHomeKey,       // smart Home
       eoScrollPastEol,        // needed for column selection past line end
       eoKeepCaretX]
    - [eoSmartTabs];

  Options2 := Options2 + [eoEnhanceEndKey];   // smart End

  { Column selection is reachable with Alt+drag out of the box.  medit used
    Ctrl+drag; the keystroke is remapped in phase 2 once the shortcut layer
    exists, rather than being hard-coded here. }
  DefaultSelectionMode := smNormal;

  Gutter.Visible := True;
  Gutter.LineNumberPart.Visible := True;
  Gutter.CodeFoldPart.Visible := True;
  Gutter.ChangesPart.Visible := True;

  Font.Name := {$IFDEF WINDOWS}'Consolas'{$ELSE}'Monospace'{$ENDIF};
  Font.Size := 10;

  BorderStyle := bsNone;
  ScrollBars := ssAutoBoth;
end;

end.
