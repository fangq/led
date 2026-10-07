{ LED - a lightweight editor.  The cross at the end of a tab strip.

  One button per tab group rather than one per tab: that is what medit does,
  and it is also the only shape that travels.  The LCL will not draw a tab
  itself -- OwnerDraw and OnDrawTab are commented out of TPageControl and no
  widgetset implements them -- and nboShowCloseButtons is declared but
  unimplemented on gtk2, so a per-tab cross would exist on some platforms and
  not others.  A button placed over the strip is drawn by LED on all of them.

  A unit of its own because it is wanted twice over: the editor's two
  notebooks, and the fork's figures, which are a page control with the same
  strip and the same want.  Everything that was hard to get right here --
  which control owns the clicks, where gtk2 says the strip is -- is hard to
  get right once. }
unit Led.UI.TabClose;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, ExtCtrls, ComCtrls, Buttons, ImgList,
  Forms, Led.UI.Icons, Led.UI.Dpi;

var
  { The cross shown on the tab under the pointer, at its right-hand end,
    rather than once at the end of the strip.  A program built on LED turns
    it on (Mima does, before its window shows); LED keeps medit's single
    cross. }
  LedTabHoverClose: Boolean = False;

const
  { Room at the end of a tab's caption for the hover cross to sit in, so it
    does not cover the end of the name.  Added by whoever sets a caption,
    and only while LedTabHoverClose is on. }
  LedTabCaptionPad = '      ';

type
  TLedTabClose = class(TComponent)
  private
    FHost: TPanel;
    FButton: TSpeedButton;
    { hover mode: the strip the cross is over, and which of its tabs }
    FHoverBook: TPageControl;
    FHoverIndex: Integer;
    procedure ButtonMouseLeave(Sender: TObject);
    procedure ShowOnTab(ABook: TPageControl; AIndex: Integer);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    { Builds the button, hidden until the first Place.  AOnClick is given the
      *button*, whose Tag is ATag, so one handler can serve several strips. }
    constructor CreateFor(AOwner: TComponent;
      AImages: TCustomImageList; AOnClick: TNotifyEvent;
      const AHint: string; ATag: PtrInt = 0);

    { Puts the button where ABook's strip is now, or hides it when there is
      no strip to put it on.  Call from the book's resize and whenever a tab
      is added, removed or the book is reparented.

      The book is an argument rather than something remembered, and that is
      not a style choice: the second notebook is created by a split and
      freed by an unsplit, so a reference held here outlives the control it
      points at.  Held once, it crashed the session-save check the first
      time a split was undone. }
    procedure Place(ABook: TPageControl);

    { The strip's pointer moves and leaves, in hover mode.  Place hooks them
      onto a strip that has no handlers of its own; one that has calls them
      from its own (the editor's notebooks show a hint from theirs). }
    procedure BookMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BookMouseLeave(Sender: TObject);
    { Takes the hover cross away: after a close, when the tabs have moved
      under it; the next pointer move puts it back on whatever is there. }
    procedure HideHover;

    property Button: TSpeedButton read FButton;
    { In hover mode, the page whose tab the cross is on, or -1: the tab a
      click closes, whichever is in front. }
    property HoverIndex: Integer read FHoverIndex;
  end;

implementation

uses
  Graphics;

{ Halfway between the text and the face it sits on }
function QuietColour: TColor;
var
  A, B: TColor;
begin
  A := ColorToRGB(clBtnText);
  B := ColorToRGB(clBtnFace);
  Result := RGBToColor(
    ((A and $FF) + (B and $FF)) div 2,
    (((A shr 8) and $FF) + ((B shr 8) and $FF)) div 2,
    (((A shr 16) and $FF) + ((B shr 16) and $FF)) div 2);
end;

constructor TLedTabClose.CreateFor(AOwner: TComponent;
  AImages: TCustomImageList; AOnClick: TNotifyEvent;
  const AHint: string; ATag: PtrInt = 0);
begin
  inherited Create(AOwner);

  { A windowed host, and the button inside it.

    The button on its own did not work: TSpeedButton is a TGraphicControl,
    which has no window of its own and is painted onto whatever it is
    parented to.  Parented to the panel behind the notebook it was drawn --
    so it looked right, and a self-test that called Btn.Click passed -- but
    every windowed control stacked above that panel took the mouse first.
    Asked what a click at the middle of the button would actually reach, the
    LCL answered TLedEdit: the editor, straight through the cross.

    A TPanel is a TWinControl, so it owns that rectangle of the screen and
    the clicks land in it; the button fills it and gets them from there. }
  FHost := TPanel.Create(Self);
  FHost.BevelOuter := bvNone;
  FHost.Caption := '';
  FHost.FullRepaint := False;
  FHost.Visible := False;

  FButton := TLedSpeedButton.Create(Self);
  FButton.Parent := FHost;
  FButton.Align := alClient;
  FButton.Flat := True;
  FButton.ShowHint := True;
  FButton.Hint := AHint;
  FButton.Tag := ATag;
  FButton.OnClick := AOnClick;
  { A small cross in a quiet colour, drawn for this button rather than taken
    from the toolbar's list.  At the toolbar's size, in the text colour, it
    was the biggest and darkest thing on the strip -- louder than the names
    of the files it closes. }
  FButton.OnMouseLeave := @ButtonMouseLeave;
  FHoverIndex := -1;
  FButton.Images := nil;
  FButton.Glyph.Assign(LedIconBitmap('close', QuietColour, LedScale96(11)));
  if FButton.Glyph.Empty then
    FButton.Caption := 'x';
end;

procedure TLedTabClose.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  { the second notebook is freed by an unsplit, with the cross over it }
  if (Operation = opRemove) and (AComponent = FHoverBook) then
  begin
    FHoverBook := nil;
    FHoverIndex := -1;
  end;
end;

procedure TLedTabClose.HideHover;
begin
  FHost.Visible := False;
  FHoverIndex := -1;
end;

{ The cross on tab AIndex of ABook: square, at the tab's right-hand end and
  centred on it, over the room LedTabCaptionPad left in the caption.  The
  rectangle comes in the strip's coordinates on gtk2, which Place explains. }
procedure TLedTabClose.ShowOnTab(ABook: TPageControl; AIndex: Integer);
var
  R: TRect;
  Dx, Dy, H, Pad, Size: Integer;
begin
  if FHoverBook <> ABook then
  begin
    if FHoverBook <> nil then
      FHoverBook.RemoveFreeNotification(Self);
    FHoverBook := ABook;
    ABook.FreeNotification(Self);
  end;
  R := ABook.TabRect(AIndex);
  H := R.Bottom - R.Top;
  if (H < LedScale96(8)) or (R.Right <= R.Left) then
  begin
    { No rectangle to be had: no handle yet, or a strip not on screen.  The
      cross goes where it went before hover mode, at the end of the strip,
      and still closes the tab it was asked for -- a cross in roughly the
      right place beats none, as Place says of the same case. }
    LedTabHoverClose := False;
    try
      Place(ABook);
    finally
      LedTabHoverClose := True;
    end;
    FHoverIndex := AIndex;
    Exit;
  end;
  Dx := 0;
  Dy := 0;
  if R.Top < 0 then
  begin
    Dx := ABook.ClientOrigin.x - ABook.ControlOrigin.x;
    Dy := ABook.ClientOrigin.y - ABook.ControlOrigin.y;
  end;
  Pad := LedScale96(3);
  Size := H - 2 * LedScale96(4);
  if Size > LedScale96(16) then Size := LedScale96(16);
  if Size < LedScale96(8) then Size := LedScale96(8);

  FHoverIndex := AIndex;
  FHost.Parent := ABook.Parent;
  FHost.SetBounds(ABook.Left + Dx + R.Right - Size - Pad,
                  ABook.Top + Dy + R.Top + (H - Size) div 2, Size, Size);
  FHost.Visible := True;
  FHost.BringToFront;
end;

procedure TLedTabClose.BookMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  Book: TPageControl;
  I, K: Integer;
begin
  if not LedTabHoverClose or not (Sender is TPageControl) then Exit;
  Book := TPageControl(Sender);
  if not Book.ShowTabs then
  begin
    HideHover;
    Exit;
  end;
  I := Book.IndexOfTabAt(X, Y);
  { a strip not on screen answers nothing; its rectangles still do }
  if I < 0 then
    for K := 0 to Book.PageCount - 1 do
      if PtInRect(Book.TabRect(K), Point(X, Y)) then
      begin
        I := K;
        Break;
      end;
  if I < 0 then
    HideHover
  else if (I <> FHoverIndex) or (FHoverBook <> Book) or not FHost.Visible then
    ShowOnTab(Book, I);
end;

{ Off the strip: the cross goes, unless the pointer went onto the cross
  itself, which is a window of its own and so a leave from the strip. }
procedure TLedTabClose.BookMouseLeave(Sender: TObject);
var
  P: TPoint;
begin
  if not FHost.Visible then Exit;
  P := FHost.ScreenToClient(Mouse.CursorPos);
  if not PtInRect(FHost.ClientRect, P) then
    HideHover;
end;

procedure TLedTabClose.ButtonMouseLeave(Sender: TObject);
var
  P: TPoint;
begin
  if not LedTabHoverClose or (FHoverBook = nil) then Exit;
  P := FHoverBook.ScreenToClient(Mouse.CursorPos);
  if FHoverBook.IndexOfTabAt(P.X, P.Y) <> FHoverIndex then
    HideHover;
end;

procedure TLedTabClose.Place(ABook: TPageControl);
var
  Sz, Pad, Size, StripTop: Integer;
  R: TRect;
begin
  { Hover mode: no cross at the end of the strip; the strip's pointer moves
    put one on the tab under it (see ShowOnTab). Placing is then only
    wiring, and hiding what may be left over a tab that has gone. }
  if LedTabHoverClose then
  begin
    if ABook <> nil then
    begin
      if not Assigned(ABook.OnMouseMove) then
        ABook.OnMouseMove := @BookMouseMove;
      if not Assigned(ABook.OnMouseLeave) then
        ABook.OnMouseLeave := @BookMouseLeave;
    end;
    { a refresh places the strip again; the cross stays on its tab unless
      that tab has gone, or the strip has }
    if (ABook = nil) or (ABook <> FHoverBook) or not ABook.ShowTabs or
       (FHoverIndex < 0) or (FHoverIndex >= ABook.PageCount) then
      HideHover;
    Exit;
  end;

  { No strip, no button: with a single tab the strip is hidden, and there is
    nothing to put a cross at the end of. }
  if (ABook = nil) or (not ABook.ShowTabs) or (ABook.PageCount = 0) or
     (ABook.Parent = nil) then
  begin
    FHost.Visible := False;
    Exit;
  end;

  { Above the book, and in whatever the book's parent is now -- a split moves
    the book into a splitter side and the button has to follow.  BringToFront
    on a windowed control is a real z-order change, which is what puts it
    over the notebook rather than under it. }
  FHost.Parent := ABook.Parent;
  FHost.BringToFront;

  { Tabs along the top is the only arrangement this button knows where to sit
    in; LED never sets anything else, but a skin that did should get no
    button rather than one in the wrong place. }
  if ABook.TabPosition <> tpTop then
  begin
    FHost.Visible := False;
    Exit;
  end;

  { Where the strip is, and how tall.  Both come from TabRect, and its origin
    needs converting rather than discarding.

    gtk2 reports the rectangle relative to the page area, so a strip above
    the page comes back with a negative top; reading that as a control
    coordinate puts the button above the window, which is why this used to
    take the height alone and place the button at the top of the control.
    But the strip does not start at the top of the control -- there is a
    notebook frame above it, 29 pixels of it on this desktop -- so a cross
    placed there sits high of the tab it belongs to, which is what it did.

    The conversion is the distance from the control to the page area, which
    is the difference between the two origins.  A widgetset that measures the
    rectangle from the control itself reports a positive top and wants no
    conversion; the sign says which one this is. }
  R := ABook.TabRect(0);
  Sz := R.Bottom - R.Top;
  Pad := LedScale96(2);
  if Sz >= LedScale96(12) then
  begin
    StripTop := ABook.Top + R.Top;
    if R.Top < 0 then
      Inc(StripTop, ABook.ClientOrigin.y - ABook.ControlOrigin.y);
  end
  else
  begin
    { No rectangle to be had -- no handle yet, or a widgetset that does not
      answer.  A strip is about this tall, and starts where the control does;
      a button in roughly the right place beats none. }
    Sz := LedScale96(16);
    StripTop := ABook.Top;
  end;

  { Square, inset by the same padding on all four sides, and centred on the
    band rather than hung from the top of it. }
  Size := Sz - Pad * 2;
  if Size < LedScale96(8) then Size := LedScale96(8);

  FHost.SetBounds(ABook.Left + ABook.Width - Size - Pad * 2,
                  StripTop + (Sz - Size) div 2, Size, Size);
  FHost.Visible := True;
  FHost.BringToFront;
end;

end.
