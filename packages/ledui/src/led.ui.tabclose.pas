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
  Classes, SysUtils, Controls, ExtCtrls, ComCtrls, Buttons, ImgList,
  Led.UI.Icons, Led.UI.Dpi;

type
  TLedTabClose = class(TComponent)
  private
    FHost: TPanel;
    FButton: TSpeedButton;
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

    property Button: TSpeedButton read FButton;
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
  FButton.Images := nil;
  FButton.Glyph.Assign(LedIconBitmap('close', QuietColour, LedScale96(11)));
  if FButton.Glyph.Empty then
    FButton.Caption := 'x';
end;

procedure TLedTabClose.Place(ABook: TPageControl);
var
  Sz, Pad, Size, StripTop: Integer;
  R: TRect;
begin
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
