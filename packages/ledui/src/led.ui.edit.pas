{ led - a light editor.  The editor view control.

  One TLedEdit is one *view*.  A document may own several of them, all sharing
  a single text buffer, which is how split view works. }
unit Led.UI.Edit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Graphics, SynEdit, SynEditTypes,
  SynEditMouseCmds, SynEditWrappedView, SynCompletion, SynEditFoldedView,
  Led.UI.Dpi;

type
  TLedEdit = class(TSynEdit)
  private
    FDocument: TObject;   // the owning TLedDocument; typed loosely to avoid
                          // a circular unit reference
    FWrapPlugin: TLazSynEditLineWrapPlugin;
    FCompletion: TSynCompletion;
    function GetWrapEnabled: Boolean;
    procedure SetWrapEnabled(AValue: Boolean);
    procedure CompletionSearch(var APosition: Integer);
    procedure CollectWords(const APrefix: string; AInto: TStrings);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Document: TObject read FDocument write FDocument;
    { SynEdit implements wrapping as a view plugin rather than a property;
      attaching and detaching it is how the View menu toggles wrap. }
    property WrapEnabled: Boolean read GetWrapEnabled write SetWrapEnabled;
    { Created on first use.  TSynCompletion builds a popup form, and building
      a form inside another form's constructor hangs. }
    function Completion: TSynCompletion;
    { Lines actually on display.  Folding hides lines in the view, never in
      the buffer, so Lines.Count does not move when something is folded and
      is the wrong thing to look at.  TextView is protected on TSynEdit, so
      a descendant is the only place this can be reached. }
    function VisibleLineCount: Integer;
    { The folded view, which SynEdit keeps private but exposes to descendants
      through GetFoldedTextBuffer.  Its API is indexed by text line, unlike
      CodeFoldAction, which works from screen rows and therefore does nothing
      unless the display happens to be in the state it expects. }
    function FoldedView: TSynEditFoldedView;
  end;

implementation

constructor TLedEdit.Create(AOwner: TComponent);
var
  i: Integer;
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

  { medit selected a rectangle with Ctrl+drag; SynEdit ships Alt+drag.  Both
    are bound, since Alt+drag is grabbed by the window manager on several
    Linux desktops and would otherwise be unreachable.

    emUseMouseActions makes SynEdit take every mouse gesture from these
    lists instead of its built-in handling, and the lists start EMPTY.  So
    they have to be filled with the defaults first, or the only gesture the
    editor understands is the one added below -- no caret placement, no
    drag-select, no wheel, no context menu, and no clicking the fold boxes
    in the gutter. }
  MouseOptions := MouseOptions + [emUseMouseActions];
  ResetMouseActions;
  MouseActions.AddCommand(emcStartColumnSelections, True, mbXLeft, ccSingle,
    cdDown, [ssCtrl], [ssCtrl, ssAlt, ssShift]);
  DefaultSelectionMode := smNormal;

  Gutter.Visible := True;
  Gutter.LineNumberPart.Visible := True;
  Gutter.CodeFoldPart.Visible := True;
  Gutter.ChangesPart.Visible := True;
  { The gutter parts keep their own action lists, and they are empty for the
    same reason. }
  for i := 0 to Gutter.Parts.Count - 1 do
    Gutter.Parts[i].ResetMouseActions;

  { medit sizes the line-number column to the digits actually needed.
    AutoSize does that, but SynEdit's floor of 22 pixels of padding makes a
    three-digit file look like a five-digit one. }
  Gutter.LineNumberPart.AutoSize := True;
  Gutter.LineNumberPart.DigitCount := 2;
  Gutter.LineNumberPart.LeadingZeros := False;
  Gutter.MarksPart.AutoSize := False;
  Gutter.MarksPart.Width := LedScale96(12);
  Gutter.SeparatorPart.Width := LedScale96(2);
  Gutter.ChangesPart.Width := LedScale96(3);

  { The fold column must be sized explicitly, and this is not cosmetic
    fiddling.  TSynGutterCodeFolding derives its box from
      HalfBoxSize := Min(Width, LineHeight - 2) div 2
    and its pen from
      Pen.Width := Min(..., FPpiPenWidth)
    where FPpiPenWidth is only ever recomputed inside SetWidth -- and SetWidth
    returns immediately while AutoSize is on.  Left on AutoSize the markers
    therefore stay small *and* keep a one-pixel pen at any DPI, which is why
    the fold boxes and the vertical rule joining a block to its end looked
    faint.  Sizing the column to the line height gives both room to grow. }
  Gutter.CodeFoldPart.AutoSize := False;
  Gutter.CodeFoldPart.Width := LedScale96(14);

  Font.Name := LedDefaultFontName;
  Font.Size := LedDefaultFontSize;

  BorderStyle := bsNone;
  ScrollBars := ssAutoBoth;

end;

{ Word completion drawn from the document itself.  medit had none at all, and
  it is the absence people notice within a minute. }
function TLedEdit.Completion: TSynCompletion;
begin
  if FCompletion = nil then
  begin
    { Owned by nothing: making the editor its owner deadlocks, because
      TSynCompletion also attaches itself to that editor as a plugin. }
    FCompletion := TSynCompletion.Create(nil);
    FCompletion.Editor := Self;
    FCompletion.ShortCut := 16416;      { Ctrl+Space }
    FCompletion.CaseSensitive := False;
    FCompletion.OnSearchPosition := @CompletionSearch;
  end;
  Result := FCompletion;
end;

{ Every distinct word in the buffer that begins with what has been typed.
  Scanning the whole document each time is affordable -- it is a pass over a
  few hundred kilobytes of text -- and it means the list is never stale. }
procedure TLedEdit.CollectWords(const APrefix: string; AInto: TStrings);
var
  i, j, k, n: Integer;
  Line, Word, Lower: string;
begin
  Lower := LowerCase(APrefix);
  for i := 0 to Lines.Count - 1 do
  begin
    Line := Lines[i];
    n := Length(Line);
    j := 1;
    while j <= n do
    begin
      if Line[j] in ['A'..'Z', 'a'..'z', '_'] then
      begin
        k := j;
        while (k <= n) and (Line[k] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
          Inc(k);
        Word := Copy(Line, j, k - j);
        { Too short to be worth offering, and never the word being typed. }
        if (Length(Word) > 2) and
           ((Lower = '') or (Pos(Lower, LowerCase(Word)) = 1)) and
           (not SameText(Word, APrefix)) then
          AInto.Add(Word);
        j := k;
      end
      else
        Inc(j);
    end;
  end;
end;

procedure TLedEdit.CompletionSearch(var APosition: Integer);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Sorted := True;
    L.Duplicates := dupIgnore;
    CollectWords(FCompletion.CurrentString, L);
    FCompletion.ItemList.Assign(L);
  finally
    L.Free;
  end;
  APosition := 0;
end;

destructor TLedEdit.Destroy;
begin
  FreeAndNil(FCompletion);
  inherited Destroy;
end;

function TLedEdit.VisibleLineCount: Integer;
begin
  Result := TextView.Count;
end;

function TLedEdit.FoldedView: TSynEditFoldedView;
begin
  Result := TSynEditFoldedView(GetFoldedTextBuffer);
end;

function TLedEdit.GetWrapEnabled: Boolean;
begin
  Result := FWrapPlugin <> nil;
end;

procedure TLedEdit.SetWrapEnabled(AValue: Boolean);
begin
  if AValue = GetWrapEnabled then Exit;
  if AValue then
    FWrapPlugin := TLazSynEditLineWrapPlugin.Create(Self)
  else
    FreeAndNil(FWrapPlugin);
end;

end.
