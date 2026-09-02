{ led - a light editor.  Which scripts a document is written in.

  This exists to answer one question: does this text contain characters the
  ordinary monospace fonts do not carry?  If it does, led picks a font for the
  document that does -- see Led.UI.Dpi -- because of how the editor draws.

  medit does not need any of this.  MooTextView descends from GtkTextView, so
  GTK lays each line out as a single PangoLayout and pango puts every run in
  that line on one baseline, whatever font each run came from; when a line
  needs a taller font GTK simply makes that line taller.  SynEdit positions
  glyphs itself, and LCL's gtk2 backend goes further: given the character
  offset array SynEdit supplies, ExtTextOut draws one codepoint at a time,
  each as its own layout with its *top* at the row's top.  A CJK glyph comes
  from a fallback font with a larger ascent, so top-aligning it drops its
  baseline below the Latin text beside it.

  Rows in SynEdit are all one height, so the GTK answer -- a taller line -- is
  not available.  What is available is making every glyph in the document come
  from one font, which gives a single ascent and therefore a single baseline.

  No LCL dependency, so the headless suite covers it. }
unit Led.Core.Scripts;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  { How much of a document to look at.  A file that uses CJK uses it early --
    a header, a comment, a name in the first records -- and reading eight
    megabytes to decide a font would undo the point of opening quickly. }
  LedScriptScanLimit = 256 * 1024;

{ True when the text contains a character from a script the usual monospace
  fonts do not cover: Han, Kana, Hangul, Bopomofo, the CJK punctuation block
  and the fullwidth forms. }
function LedTextNeedsWideFont(const AText: string;
  ALimit: Integer = LedScriptScanLimit): Boolean;

{ The first codepoint of AText at byte position AIndex, and how many bytes it
  occupies.  Returns 0 and 1 for a malformed sequence, so a caller always
  makes progress. }
function LedCodepointAt(const AText: string; AIndex: Integer;
  out ALen: Integer): Cardinal;

implementation

function LedCodepointAt(const AText: string; AIndex: Integer;
  out ALen: Integer): Cardinal;
var
  B: Byte;
  N, i: Integer;
begin
  ALen := 1;
  Result := 0;
  if (AIndex < 1) or (AIndex > Length(AText)) then Exit;

  B := Byte(AText[AIndex]);
  if B < $80 then
    Exit(B)
  else if (B and $E0) = $C0 then begin N := 2; Result := B and $1F; end
  else if (B and $F0) = $E0 then begin N := 3; Result := B and $0F; end
  else if (B and $F8) = $F0 then begin N := 4; Result := B and $07; end
  else
    Exit(0);          { a stray continuation byte; step over it }

  if AIndex + N - 1 > Length(AText) then
  begin
    Result := 0;
    Exit;
  end;

  for i := 1 to N - 1 do
  begin
    B := Byte(AText[AIndex + i]);
    if (B and $C0) <> $80 then
    begin
      { Truncated sequence.  Report one byte consumed rather than N, so the
        scan resynchronises on the next lead byte instead of skipping past
        it. }
      Result := 0;
      ALen := 1;
      Exit;
    end;
    Result := (Result shl 6) or (B and $3F);
  end;
  ALen := N;
end;

function LedTextNeedsWideFont(const AText: string; ALimit: Integer): Boolean;
var
  i, Len, Last: Integer;
  C: Cardinal;
begin
  Result := False;
  Last := Length(AText);
  if (ALimit > 0) and (Last > ALimit) then Last := ALimit;

  i := 1;
  while i <= Last do
  begin
    C := LedCodepointAt(AText, i, Len);
    { Plain ASCII is the overwhelming majority of every file this will ever
      look at, so it is worth getting out of the way first. }
    if C >= $1100 then
    begin
      if ((C >= $1100) and (C <= $11FF)) or        { Hangul Jamo            }
         ((C >= $2E80) and (C <= $2EFF)) or        { CJK radicals           }
         ((C >= $3000) and (C <= $303F)) or        { CJK punctuation        }
         ((C >= $3040) and (C <= $30FF)) or        { Hiragana, Katakana     }
         ((C >= $3100) and (C <= $312F)) or        { Bopomofo               }
         ((C >= $3130) and (C <= $318F)) or        { Hangul compatibility   }
         ((C >= $3400) and (C <= $4DBF)) or        { Han extension A        }
         ((C >= $4E00) and (C <= $9FFF)) or        { Han                    }
         ((C >= $AC00) and (C <= $D7AF)) or        { Hangul syllables       }
         ((C >= $F900) and (C <= $FAFF)) or        { Han compatibility      }
         ((C >= $FF00) and (C <= $FFEF)) or        { fullwidth forms        }
         ((C >= $20000) and (C <= $2FA1F)) then    { Han extensions B..F    }
        Exit(True);
    end;
    Inc(i, Len);
  end;
end;

end.
