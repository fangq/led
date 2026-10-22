{ LED - a lightweight editor.  A tab strip's list button: a small down arrow at the left end of its tabs.

  A strip of tabs shows as many as fit and scrolls the rest with its two
  arrows, so a page that is open is not always a page that can be seen.
  The button at the start of the strip drops a list of every open page --
  the window's files, and in mima its figures -- to go straight to one.

  On gtk2 it is the notebook's own start "action widget"
  (gtk_notebook_set_action_widget), which gtk lays out before the first tab
  and keeps there however the tabs scroll: nothing is overlaid on the strip,
  and nothing has to follow its geometry.  A toolkit without one answers
  False, and the caller offers the list some other way. }
unit Led.UI.TabMenu;

{$mode objfpc}{$H+}

{$IF DEFINED(LINUX) and DEFINED(LCLGtk2)}
  {$DEFINE LED_TABMENU_GTK2}
{$ENDIF}

interface

uses
  Classes, SysUtils, Types, Controls, ComCtrls;

type
  { Asked for the list, with where on the screen it should drop from: the
    button's bottom-left corner }
  TLedTabListEvent = procedure(Sender: TObject; const AAt: TPoint) of object;

{ Puts the list button at the start of ABook's tabs, calling AOnList when it
  is pressed; False where the toolkit has no place for one.  Again for a
  book whose handle was made anew, which drops it. }
function LedAddTabListButton(ABook: TCustomTabControl; AOnList: TLedTabListEvent): Boolean;

{ The current page's tab scrolled fully into view.  gtk scrolls a strip of
  tabs only when the current page changes, so a strip made narrower -- the
  editors given less of the window -- left the current tab half behind the
  scroll arrows, its name cut off.  Nothing is told of a page change: there
  is none. }
procedure LedRevealCurrentTab(ABook: TCustomTabControl);

implementation

{$IFDEF LED_TABMENU_GTK2}
uses
  Glib2, Gdk2, Gtk2;

procedure gtk_notebook_set_action_widget(notebook: PGtkNotebook; widget: PGtkWidget;
  pack_type: TGtkPackType); cdecl; external gtklib;
procedure gtk_widget_set_tooltip_text(widget: PGtkWidget; text: PChar); cdecl; external gtklib;

type
  { what the gtk callback is given back: the book and whom to tell }
  TLedTabListLink = class(TComponent)
  public
    Book: TCustomTabControl;
    OnList: TLedTabListEvent;
  end;

procedure ListClicked(AButton: PGtkWidget; AData: gpointer); cdecl;
var
  L: TLedTabListLink;
  X, Y: gint;
begin
  L := TLedTabListLink(AData);
  if (L = nil) or not Assigned(L.OnList) or (AButton^.window = nil) then Exit;
  { the button's corner, in the window it is drawn in, to the screen }
  gdk_window_get_origin(AButton^.window, @X, @Y);
  L.OnList(L.Book, Point(X + AButton^.allocation.x,
    Y + AButton^.allocation.y + AButton^.allocation.height));
end;

function LedAddTabListButton(ABook: TCustomTabControl; AOnList: TLedTabListEvent): Boolean;
var
  Btn, Arrow: PGtkWidget;
  L: TLedTabListLink;
  I: Integer;
begin
  Result := False;
  if ABook = nil then Exit;
  ABook.HandleNeeded;
  if not ABook.HandleAllocated then Exit;
  { one link a book, owned by it, so it goes when the book does }
  L := nil;
  for I := 0 to ABook.ComponentCount - 1 do
    if ABook.Components[I] is TLedTabListLink then
      L := TLedTabListLink(ABook.Components[I]);
  if L = nil then
    L := TLedTabListLink.Create(ABook);
  L.Book := ABook;
  L.OnList := AOnList;
  Btn := gtk_button_new;
  gtk_button_set_relief(PGtkButton(Btn), GTK_RELIEF_NONE);
  gtk_button_set_focus_on_click(PGtkButton(Btn), False);
  gtk_widget_set_tooltip_text(Btn, 'Every open page');
  Arrow := gtk_arrow_new(GTK_ARROW_DOWN, GTK_SHADOW_NONE);
  gtk_container_add(PGtkContainer(Btn), Arrow);
  g_signal_connect(PGObject(Btn), 'clicked', TGCallback(@ListClicked), L);
  gtk_widget_show_all(Btn);
  gtk_notebook_set_action_widget(PGtkNotebook(ABook.Handle), Btn, GTK_PACK_START);
  Result := True;
end;
procedure LedRevealCurrentTab(ABook: TCustomTabControl);
var
  Nb: PGtkNotebook;
  Cur, N, Other: gint;
  Sig: guint;
begin
  if (ABook = nil) or not ABook.HandleAllocated then Exit;
  Nb := PGtkNotebook(ABook.Handle);
  Cur := gtk_notebook_get_current_page(Nb);
  N := gtk_notebook_get_n_pages(Nb);
  if (Cur < 0) or (N < 2) then Exit;
  if Cur > 0 then Other := Cur - 1 else Other := Cur + 1;
  { the switch away and back is gtk's, and only gtk's: the LCL's handler,
    which would tell the window a page changed, is held off meanwhile }
  Sig := g_signal_lookup('switch-page', gtk_notebook_get_type);
  g_signal_handlers_block_matched(PGObject(Nb), G_SIGNAL_MATCH_ID, Sig, 0, nil, nil, nil);
  try
    gtk_notebook_set_current_page(Nb, Other);
    gtk_notebook_set_current_page(Nb, Cur);
  finally
    g_signal_handlers_unblock_matched(PGObject(Nb), G_SIGNAL_MATCH_ID, Sig, 0, nil, nil, nil);
  end;
end;
{$ELSE}
function LedAddTabListButton(ABook: TCustomTabControl; AOnList: TLedTabListEvent): Boolean;
begin
  Result := False;
end;

procedure LedRevealCurrentTab(ABook: TCustomTabControl);
begin
end;
{$ENDIF}

end.
