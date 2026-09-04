{ led - a light editor.  GDB/MI: the machine interface gdb speaks.

  `gdb --interpreter=mi3` answers in a line-oriented grammar meant for
  programs rather than people.  This unit is the reader for it: one line in,
  one record out.  Nothing here runs gdb or knows what the records mean --
  that is Led.Debug.Session's job -- so the whole protocol layer is covered by
  the headless suite, which is the point of putting it in ledcore.

  The grammar, from the GDB manual's "GDB/MI Output Syntax":

    output         -> ( out-of-band-record )* [ result-record ] "(gdb)" nl
    result-record  -> [ token ] "^" result-class ( "," result )* nl
    exec-async     -> [ token ] "*" async-class ( "," result )* nl
    status-async   -> [ token ] "+" async-class ( "," result )* nl
    notify-async   -> [ token ] "=" async-class ( "," result )* nl
    console-stream -> "~" c-string nl
    target-stream  -> "@" c-string nl
    log-stream     -> "&" c-string nl
    result         -> variable "=" value
    value          -> const | tuple | list
    const          -> c-string
    tuple          -> "{}" | "{" result ( "," result )* "}"
    list           -> "[]" | "[" value ( "," value )* "]"
                           | "[" result ( "," result )* "]"

  Two details that a reader written from the shape of the output rather than
  from the grammar tends to get wrong, and which the tests pin down:

    * a list's elements may be *named*, and the names repeat.  A stack comes
      back as `stack=[frame={...},frame={...}]`, so a name is not a key and a
      tuple-like lookup loses every frame but one.

    * `^error` carries `msg="..."` whose text is a C string with the usual
      escapes, and gdb puts real quotes inside it.  Unescaping has to happen
      while scanning, not afterwards, or the first embedded quote ends the
      string early. }
unit Led.Core.GdbMI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  { A value is a string, a tuple (named children) or a list (children that
    may or may not be named). }
  TLedMIValueKind = (mivString, mivTuple, mivList);

  TLedMIValue = class
  private
    FKind: TLedMIValueKind;
    FText: string;
    FNames: TStringList;
    FItems: TFPList;            // of TLedMIValue, owned
    function GetItem(AIndex: Integer): TLedMIValue;
    function GetName(AIndex: Integer): string;
  public
    constructor Create(AKind: TLedMIValueKind);
    destructor Destroy; override;

    procedure Add(const AName: string; AValue: TLedMIValue);

    function Count: Integer;
    property Kind: TLedMIValueKind read FKind;
    { The unescaped text of a string value; '' for tuples and lists. }
    property Text: string read FText write FText;
    property Items[AIndex: Integer]: TLedMIValue read GetItem; default;
    property Names[AIndex: Integer]: string read GetName;

    { First child called AName, or nil.  Repeated names are why IndexOfName
      exists as well -- see the note at the top about stack frames. }
    function ByName(const AName: string): TLedMIValue;
    function IndexOfName(const AName: string; AFrom: Integer = 0): Integer;

    { Dotted lookup, so the session layer reads as the protocol does:
      Str('frame.line') rather than four nil checks.  A missing step yields
      ADefault rather than raising, because a debugger must not fall over
      when a gdb build omits a field. }
    function Find(const APath: string): TLedMIValue;
    function Str(const APath: string; const ADefault: string = ''): string;
    function Int(const APath: string; ADefault: Int64 = -1): Int64;
    function Has(const APath: string): Boolean;
  end;

  { Which of the seven line shapes this is.  mirPrompt is the bare "(gdb)"
    that ends every batch of output. }
  TLedMIRecordKind = (mirResult, mirExec, mirStatus, mirNotify,
                      mirConsole, mirTarget, mirLog, mirPrompt, mirUnknown);

  TLedMIRecord = class
  private
    FKind: TLedMIRecordKind;
    FToken: Integer;
    FClass_: string;
    FText: string;
    FResults: TLedMIValue;
  public
    constructor Create;
    destructor Destroy; override;

    property Kind: TLedMIRecordKind read FKind write FKind;
    { The number a command was tagged with, echoed back on its reply, or -1.
      This is how a reply is matched to the command that asked for it. }
    property Token: Integer read FToken write FToken;
    { "done", "running", "error", "exit", "stopped", "breakpoint-modified"... }
    property Class_: string read FClass_ write FClass_;
    { For the three stream kinds: the unescaped text gdb wants shown. }
    property Text: string read FText write FText;
    { A tuple of the record's `name=value` pairs; never nil. }
    property Results: TLedMIValue read FResults;
  end;

{ Reads one line of gdb output.  Never returns nil and never raises: a line
  that matches nothing comes back as mirUnknown carrying the raw text, because
  a debugger that dies on an unrecognised record is worse than one that shows
  it. }
function LedMIParse(const ALine: string): TLedMIRecord;

{ Unescapes a GDB c-string body (without the surrounding quotes). }
function LedMIUnescape(const AText: string): string;

{ Quotes and escapes a string as gdb expects an argument -- used when building
  commands with paths in them. }
function LedMIQuote(const AText: string): string;

implementation

{ --- TLedMIValue ----------------------------------------------------------- }

constructor TLedMIValue.Create(AKind: TLedMIValueKind);
begin
  inherited Create;
  FKind := AKind;
  FNames := TStringList.Create;
  FItems := TFPList.Create;
end;

destructor TLedMIValue.Destroy;
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    TLedMIValue(FItems[i]).Free;
  FItems.Free;
  FNames.Free;
  inherited Destroy;
end;

procedure TLedMIValue.Add(const AName: string; AValue: TLedMIValue);
begin
  if AValue = nil then Exit;
  FNames.Add(AName);
  FItems.Add(AValue);
end;

function TLedMIValue.Count: Integer;
begin
  Result := FItems.Count;
end;

function TLedMIValue.GetItem(AIndex: Integer): TLedMIValue;
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit(nil);
  Result := TLedMIValue(FItems[AIndex]);
end;

function TLedMIValue.GetName(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= FNames.Count) then Exit('');
  Result := FNames[AIndex];
end;

function TLedMIValue.IndexOfName(const AName: string; AFrom: Integer): Integer;
var
  i: Integer;
begin
  for i := AFrom to FNames.Count - 1 do
    if FNames[i] = AName then Exit(i);
  Result := -1;
end;

function TLedMIValue.ByName(const AName: string): TLedMIValue;
var
  i: Integer;
begin
  i := IndexOfName(AName);
  if i < 0 then Exit(nil);
  Result := TLedMIValue(FItems[i]);
end;

function TLedMIValue.Find(const APath: string): TLedMIValue;
var
  Rest, Step: string;
  p: Integer;
  Cur: TLedMIValue;
begin
  Cur := Self;
  Rest := APath;
  while (Rest <> '') and (Cur <> nil) do
  begin
    p := Pos('.', Rest);
    if p = 0 then
    begin
      Step := Rest;
      Rest := '';
    end
    else
    begin
      Step := Copy(Rest, 1, p - 1);
      Rest := Copy(Rest, p + 1, Length(Rest));
    end;
    if Step = '' then Continue;
    Cur := Cur.ByName(Step);
  end;
  Result := Cur;
end;

function TLedMIValue.Str(const APath: string; const ADefault: string): string;
var
  V: TLedMIValue;
begin
  V := Find(APath);
  if (V = nil) or (V.Kind <> mivString) then Exit(ADefault);
  Result := V.Text;
end;

function TLedMIValue.Int(const APath: string; ADefault: Int64): Int64;
var
  S: string;
begin
  S := Str(APath, '');
  if not TryStrToInt64(Trim(S), Result) then Result := ADefault;
end;

function TLedMIValue.Has(const APath: string): Boolean;
begin
  Result := Find(APath) <> nil;
end;

{ --- TLedMIRecord ---------------------------------------------------------- }

constructor TLedMIRecord.Create;
begin
  inherited Create;
  FToken := -1;
  FResults := TLedMIValue.Create(mivTuple);
end;

destructor TLedMIRecord.Destroy;
begin
  FResults.Free;
  inherited Destroy;
end;

{ --- escaping -------------------------------------------------------------- }

function LedMIUnescape(const AText: string): string;
var
  i, n, Oct: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(AText) do
  begin
    if (AText[i] = '\') and (i < Length(AText)) then
    begin
      Inc(i);
      case AText[i] of
        'n': Result := Result + #10;
        't': Result := Result + #9;
        'r': Result := Result + #13;
        'a': Result := Result + #7;
        'b': Result := Result + #8;
        'f': Result := Result + #12;
        'v': Result := Result + #11;
        '"': Result := Result + '"';
        '''': Result := Result + '''';
        '\': Result := Result + '\';
        '0'..'7':
          begin
            { Up to three octal digits.  gdb uses these for bytes it will not
              spell, and a path from a non-UTF-8 filesystem arrives this way. }
            Oct := 0;
            n := 0;
            while (n < 3) and (i <= Length(AText)) and
                  (AText[i] in ['0'..'7']) do
            begin
              Oct := Oct * 8 + (Ord(AText[i]) - Ord('0'));
              Inc(i);
              Inc(n);
            end;
            Dec(i);
            Result := Result + Chr(Oct and $FF);
          end;
      else
        { An escape this does not know keeps its character rather than losing
          it, which is what a reader that must not fail should do. }
        Result := Result + AText[i];
      end;
      Inc(i);
    end
    else
    begin
      Result := Result + AText[i];
      Inc(i);
    end;
  end;
end;

function LedMIQuote(const AText: string): string;
var
  i: Integer;
begin
  Result := '"';
  for i := 1 to Length(AText) do
    case AText[i] of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #10:  Result := Result + '\n';
      #13:  Result := Result + '\r';
      #9:   Result := Result + '\t';
    else
      Result := Result + AText[i];
    end;
  Result := Result + '"';
end;

{ --- the parser ------------------------------------------------------------ }

type
  { A cursor over the line.  Kept as a record rather than a class so parsing a
    record allocates only the values it returns. }
  TMIScanner = record
    S: string;
    P: Integer;
  end;

function ScanValue(var Sc: TMIScanner): TLedMIValue; forward;

function AtEnd(const Sc: TMIScanner): Boolean;
begin
  Result := Sc.P > Length(Sc.S);
end;

function Peek(const Sc: TMIScanner): Char;
begin
  if AtEnd(Sc) then Exit(#0);
  Result := Sc.S[Sc.P];
end;

{ A quoted c-string, unescaped as it is scanned.

  As it is scanned, not afterwards: finding the closing quote first means
  deciding whether a `"` is the end or part of the text, and that is exactly
  what the escapes are there to say.  gdb puts quoted text inside `msg="..."`
  on every `^error`, so this is the common case, not a corner. }
function ScanString(var Sc: TMIScanner): string;
var
  Oct, n: Integer;
begin
  Result := '';
  if Peek(Sc) <> '"' then Exit;
  Inc(Sc.P);
  while not AtEnd(Sc) do
  begin
    if Sc.S[Sc.P] = '"' then
    begin
      Inc(Sc.P);
      Exit;
    end;

    if (Sc.S[Sc.P] <> '\') or (Sc.P >= Length(Sc.S)) then
    begin
      Result := Result + Sc.S[Sc.P];
      Inc(Sc.P);
      Continue;
    end;

    Inc(Sc.P);                          { past the backslash }
    case Sc.S[Sc.P] of
      'n': begin Result := Result + #10; Inc(Sc.P); end;
      't': begin Result := Result + #9;  Inc(Sc.P); end;
      'r': begin Result := Result + #13; Inc(Sc.P); end;
      'a': begin Result := Result + #7;  Inc(Sc.P); end;
      'b': begin Result := Result + #8;  Inc(Sc.P); end;
      'f': begin Result := Result + #12; Inc(Sc.P); end;
      'v': begin Result := Result + #11; Inc(Sc.P); end;
      '0'..'7':
        begin
          { Up to three octal digits.  gdb spells bytes it will not print this
            way, which is how a path from a non-UTF-8 filesystem arrives. }
          Oct := 0;
          n := 0;
          while (n < 3) and (not AtEnd(Sc)) and (Sc.S[Sc.P] in ['0'..'7']) do
          begin
            Oct := Oct * 8 + (Ord(Sc.S[Sc.P]) - Ord('0'));
            Inc(Sc.P);
            Inc(n);
          end;
          Result := Result + Chr(Oct and $FF);
        end;
    else
      { `\"`, `\\`, and anything this does not know: keep the character.
        Dropping an unknown escape loses text; keeping it never does. }
      Result := Result + Sc.S[Sc.P];
      Inc(Sc.P);
    end;
  end;
end;

{ A bare variable name, up to '=' -- MI does not quote these. }
function ScanName(var Sc: TMIScanner): string;
var
  Start: Integer;
begin
  Start := Sc.P;
  while (not AtEnd(Sc)) and (Sc.S[Sc.P] in ['a'..'z', 'A'..'Z', '0'..'9',
                                            '_', '-']) do
    Inc(Sc.P);
  Result := Copy(Sc.S, Start, Sc.P - Start);
end;

{ Fills AInto with `name=value` pairs, or bare values for an unnamed list. }
procedure ScanResults(var Sc: TMIScanner; AInto: TLedMIValue; ACloser: Char);
var
  Name: string;
  V: TLedMIValue;
  Mark: Integer;
begin
  while not AtEnd(Sc) do
  begin
    if (ACloser <> #0) and (Peek(Sc) = ACloser) then
    begin
      Inc(Sc.P);
      Exit;
    end;

    Name := '';
    Mark := Sc.P;
    if Peek(Sc) in ['a'..'z', 'A'..'Z', '_'] then
    begin
      Name := ScanName(Sc);
      if Peek(Sc) = '=' then
        Inc(Sc.P)
      else
      begin
        { Not a pair after all -- a bare token in a list.  Rewind and take it
          as a value. }
        Sc.P := Mark;
        Name := '';
      end;
    end;

    V := ScanValue(Sc);
    if V = nil then Exit;
    AInto.Add(Name, V);

    if Peek(Sc) = ',' then
    begin
      Inc(Sc.P);
      Continue;
    end;
    if (ACloser <> #0) and (Peek(Sc) = ACloser) then
    begin
      Inc(Sc.P);
      Exit;
    end;
    if ACloser = #0 then Exit;
  end;
end;

function ScanValue(var Sc: TMIScanner): TLedMIValue;
var
  Start: Integer;
begin
  case Peek(Sc) of
    '"':
      begin
        Result := TLedMIValue.Create(mivString);
        Result.Text := ScanString(Sc);
      end;
    '{':
      begin
        Inc(Sc.P);
        Result := TLedMIValue.Create(mivTuple);
        if Peek(Sc) = '}' then
        begin
          Inc(Sc.P);
          Exit;
        end;
        ScanResults(Sc, Result, '}');
      end;
    '[':
      begin
        Inc(Sc.P);
        Result := TLedMIValue.Create(mivList);
        if Peek(Sc) = ']' then
        begin
          Inc(Sc.P);
          Exit;
        end;
        ScanResults(Sc, Result, ']');
      end;
  else
    { Unquoted run -- not in the grammar, but gdb emits bare numbers in some
      builds and refusing them loses the whole record. }
    Start := Sc.P;
    while (not AtEnd(Sc)) and (not (Sc.S[Sc.P] in [',', '}', ']'])) do
      Inc(Sc.P);
    if Sc.P = Start then Exit(nil);
    Result := TLedMIValue.Create(mivString);
    Result.Text := Copy(Sc.S, Start, Sc.P - Start);
  end;
end;

function LedMIParse(const ALine: string): TLedMIRecord;
var
  Sc: TMIScanner;
  Line: string;
  Start: Integer;
begin
  Result := TLedMIRecord.Create;

  { gdb's own line endings, plus the trailing whitespace a pipe can add. }
  Line := ALine;
  while (Line <> '') and (Line[Length(Line)] in [#13, #10]) do
    Delete(Line, Length(Line), 1);

  if Trim(Line) = '' then
  begin
    Result.Kind := mirUnknown;
    Exit;
  end;

  if Trim(Line) = '(gdb)' then
  begin
    Result.Kind := mirPrompt;
    Exit;
  end;

  Sc.S := Line;
  Sc.P := 1;

  { An optional token in front of the type character. }
  Start := Sc.P;
  while (not AtEnd(Sc)) and (Sc.S[Sc.P] in ['0'..'9']) do Inc(Sc.P);
  if Sc.P > Start then
    Result.Token := StrToInt64Def(Copy(Sc.S, Start, Sc.P - Start), -1);

  case Peek(Sc) of
    '^': Result.Kind := mirResult;
    '*': Result.Kind := mirExec;
    '+': Result.Kind := mirStatus;
    '=': Result.Kind := mirNotify;
    '~': Result.Kind := mirConsole;
    '@': Result.Kind := mirTarget;
    '&': Result.Kind := mirLog;
  else
    Result.Kind := mirUnknown;
    Result.Text := Line;
    Exit;
  end;
  Inc(Sc.P);

  if Result.Kind in [mirConsole, mirTarget, mirLog] then
  begin
    Result.Text := ScanString(Sc);
    Exit;
  end;

  Result.Class_ := ScanName(Sc);
  if Peek(Sc) = ',' then
  begin
    Inc(Sc.P);
    ScanResults(Sc, Result.Results, #0);
  end;
end;

end.
