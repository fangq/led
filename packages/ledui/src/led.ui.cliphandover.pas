{ LED - a lightweight editor.  The clipboard outliving the window it was
  copied from.

  On X a copy copies nothing.  Ctrl+C only says "LED has the clipboard", and
  the text stays in LED until somebody pastes and asks for it -- so when LED
  exits, the clipboard goes with it.  Select all, copy, close the window,
  open it again, paste: nothing.

  What keeps a clipboard alive is the desktop's clipboard manager (xfsettingsd
  on xfce, gsd on gnome), which owns CLIPBOARD_MANAGER and takes a copy of
  whatever an exiting program hands it.  Handing it over is the program's
  part, and a GTK program does it without being asked: gtk_main() stores
  every storable clipboard on the way out.  The LCL does not get that for
  two reasons.  It never calls gtk_main() -- it runs its own loop -- and it
  takes the clipboard with gtk_selection_owner_set on a widget of its own
  rather than through GtkClipboard, so GtkClipboard has nothing it could
  store even if asked.

  So, on the way out: if LED still holds the clipboard, the text is read
  back from the LCL (which has it locally, no round trip), put on the
  clipboard again through GtkClipboard, marked storable, and stored.  Text
  only -- LED is a text editor, and text is the one format every reader of
  the clipboard takes.  gtk_clipboard_store waits for the manager while it
  copies, and gives up by itself if there is none. }
unit Led.UI.ClipHandover;

{$mode objfpc}{$H+}

{$IF DEFINED(UNIX) and not DEFINED(DARWIN) and DEFINED(LCLGtk2)}
  {$DEFINE LED_CLIP_HANDOVER}
{$ENDIF}

interface

{ Call once, after Application.Run has returned and before the forms are
  freed: the LCL's clipboard widget is the main form's, and the text is read
  back from the LCL. }
procedure LedHandClipboardToManager;

{ Whether the clipboard holds text, and the text: the LCL's answer, and when it has none, gtk's -- the one a GTK
  program (medit) gets.  The LCL counts text only when the owner offers text/plain, TEXT, STRING or COMPOUND_TEXT;
  an owner that offers UTF8_STRING alone (xclip, and others) has none for it, though it reads it, and Paste stayed
  off.  gtk asks for every name text goes by.  Both wait for the owner by running the toolkit's loop: not while a
  menu is open (see TLedMainForm.ClipboardHasText). }
function LedClipboardHasText: Boolean;
function LedClipboardText: string;

implementation

{$IFDEF LED_CLIP_HANDOVER}
uses
  SysUtils, Clipbrd, LCLType, glib2, gdk2, gtk2;

function LedClipboardHasText: Boolean;
var
  Cb: PGtkClipboard;
begin
  Result := Clipboard.HasFormat(CF_TEXT);
  if Result then Exit;
  Cb := gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  Result := (Cb <> nil) and gtk_clipboard_wait_is_text_available(Cb);
end;

function LedClipboardText: string;
var
  Cb: PGtkClipboard;
  P: Pgchar;
begin
  Result := Clipboard.AsText;
  if Result <> '' then Exit;
  Cb := gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  if Cb = nil then Exit;
  P := gtk_clipboard_wait_for_text(Cb);
  if P = nil then Exit;
  Result := StrPas(P);
  g_free(P);
end;

procedure LedHandClipboardToManager;
var
  Cb: PGtkClipboard;
  S: string;
begin
  try
    { gdk only answers for windows of this process: someone else's owner,
      or none, comes back nil, and then there is nothing of ours to keep. }
    if gdk_selection_owner_get(GDK_SELECTION_CLIPBOARD) = nil then Exit;
    S := Clipboard.AsText;
    if S = '' then Exit;
    Cb := gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    if Cb = nil then Exit;
    gtk_clipboard_set_text(Cb, PChar(S), Length(S));
    { nil, 0: every target the clipboard offers may be stored }
    gtk_clipboard_set_can_store(Cb, nil, 0);
    gtk_clipboard_store(Cb);
  except
    { Leaving is not the moment to fail.  The worst case is the clipboard
      going with the window, which is what happened before this existed. }
  end;
end;
{$ELSE}
uses
  Clipbrd, LCLType;

procedure LedHandClipboardToManager;
begin
end;

function LedClipboardHasText: Boolean;
begin
  Result := Clipboard.HasFormat(CF_TEXT);
end;

function LedClipboardText: string;
begin
  Result := Clipboard.AsText;
end;
{$ENDIF}

end.
