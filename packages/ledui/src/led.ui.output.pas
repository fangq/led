{ led - a light editor.  The command output pane.

  A read-only editor showing what a tool printed, with the lines that name a
  place in a file turned into something you can click.  The parsing is done
  by Led.Core.OutputFilter; this unit is the surface.

  Reusing TSynEdit here rather than a memo is deliberate: it brings selection,
  clipboard, scrollback, search, UTF-8 and correct wide-character widths with
  it, which is most of what an output pane needs. }
unit Led.UI.Output;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Menus, StdCtrls, SynEdit, SynEditTypes,
  SynEditMarkupSpecialLine, Led.Core.OutputFilter;

type
  TLedJumpEvent = procedure(const AFileName: string; ALine, AColumn: Integer)
    of object;

  TLedOutputPane = class(TSynEdit)
  private
    FFilter: TLedOutputFilter;
    FOnJump: TLedJumpEvent;
    FKinds: TStringList;      // line index -> match kind, for colouring
    FPending: string;         // partial line from the last chunk
    procedure SpecialLineColors(Sender: TObject; Line: Integer;
      var Special: Boolean; var FG, BG: TColor);
    procedure PaneDblClick(Sender: TObject);
    procedure RecordKind(ALineIndex: Integer; AKind: TLedMatchKind);
    function KindOf(ALineIndex: Integer): TLedMatchKind;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Starts a run: clears the pane and points the filter at ABaseDir, which
      is where relative paths in the output will be resolved from. }
    procedure BeginRun(const AFilterId, ABaseDir: string);
    { Appends output.  Chunks arrive at arbitrary boundaries, so a partial
      last line is held back until its newline shows up -- otherwise a split
      "src/a.c:12: err" is parsed as two lines that match nothing. }
    procedure Append(const AText: string);
    procedure Flush;
    procedure AddNote(const AText: string);

    { Interprets the line under the caret and raises OnJump if it names a
      place. }
    procedure JumpToCaretLine;

    property OnJump: TLedJumpEvent read FOnJump write FOnJump;
  end;

implementation

constructor TLedOutputPane.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKinds := TStringList.Create;
  ReadOnly := True;
  Gutter.Visible := False;
  RightEdge := 0;
  Options := Options + [eoNoCaret];
  ScrollBars := ssAutoBoth;
  Font.Name := {$IFDEF WINDOWS}'Consolas'{$ELSE}'Monospace'{$ENDIF};
  Font.Size := 9;
  OnSpecialLineColors := @SpecialLineColors;
  OnDblClick := @PaneDblClick;
end;

destructor TLedOutputPane.Destroy;
begin
  FKinds.Free;
  inherited Destroy;
end;

procedure TLedOutputPane.RecordKind(ALineIndex: Integer; AKind: TLedMatchKind);
begin
  while FKinds.Count <= ALineIndex do
    FKinds.Add('0');
  FKinds[ALineIndex] := IntToStr(Ord(AKind));
end;

function TLedOutputPane.KindOf(ALineIndex: Integer): TLedMatchKind;
begin
  if (ALineIndex < 0) or (ALineIndex >= FKinds.Count) then
    Exit(lmkNone);
  Result := TLedMatchKind(StrToIntDef(FKinds[ALineIndex], 0));
end;

procedure TLedOutputPane.SpecialLineColors(Sender: TObject; Line: Integer;
  var Special: Boolean; var FG, BG: TColor);
begin
  case KindOf(Line - 1) of
    lmkError:   begin Special := True; FG := clMaroon; end;
    lmkWarning: begin Special := True; FG := clOlive; end;
    lmkInfo:    begin Special := True; FG := clNavy; end;
  end;
end;

procedure TLedOutputPane.BeginRun(const AFilterId, ABaseDir: string);
begin
  FFilter := LedFilters.Find(AFilterId);
  if FFilter = nil then FFilter := LedFilters.Find('default');
  if FFilter <> nil then FFilter.Reset(ABaseDir);
  FKinds.Clear;
  FPending := '';
  ReadOnly := False;
  try
    Lines.Clear;
  finally
    ReadOnly := True;
  end;
end;

procedure TLedOutputPane.Append(const AText: string);
var
  Chunk: string;
  Parts: TStringArray;
  i, Idx: Integer;
  M: TLedOutputMatch;
begin
  if AText = '' then Exit;
  Chunk := FPending + StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Chunk := StringReplace(Chunk, #13, #10, [rfReplaceAll]);
  Parts := Chunk.Split([#10]);

  { The last piece has no newline yet, so keep it for the next chunk. }
  FPending := Parts[High(Parts)];

  ReadOnly := False;
  try
    for i := 0 to High(Parts) - 1 do
    begin
      Idx := Lines.Add(Parts[i]);
      if FFilter <> nil then
      begin
        M := FFilter.Process(Parts[i]);
        RecordKind(Idx, M.Kind);
      end;
    end;
  finally
    ReadOnly := True;
  end;
  CaretY := Lines.Count;
  EnsureCursorPosVisible;
end;

procedure TLedOutputPane.Flush;
var
  Rest: string;
begin
  if FPending = '' then Exit;
  Rest := FPending;
  FPending := '';
  Append(Rest + #10);
end;

procedure TLedOutputPane.AddNote(const AText: string);
begin
  Flush;
  ReadOnly := False;
  try
    Lines.Add(AText);
  finally
    ReadOnly := True;
  end;
  CaretY := Lines.Count;
  EnsureCursorPosVisible;
end;

procedure TLedOutputPane.PaneDblClick(Sender: TObject);
begin
  JumpToCaretLine;
end;

procedure TLedOutputPane.JumpToCaretLine;
var
  M: TLedOutputMatch;
  Probe: TLedOutputFilter;
begin
  if not Assigned(FOnJump) then Exit;
  if (CaretY < 1) or (CaretY > Lines.Count) then Exit;
  if FFilter = nil then Exit;

  { Re-run the line through a filter whose directory state matches where the
    run had got to.  Replaying from the top would be exact but slow on a long
    build log; the current directory is right for the common case of clicking
    an error soon after it appears. }
  Probe := FFilter;
  M := Probe.Process(Lines[CaretY - 1]);
  if (M.Kind <> lmkNone) and (M.FileName <> '') and FileExists(M.FileName) then
    FOnJump(M.FileName, M.Line, M.Column);
end;

end.
