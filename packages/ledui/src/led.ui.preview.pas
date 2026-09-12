{ led - a lightweight editor.  The Markdown and wiki preview pane.

  medit rendered HTML with a 3,100-line DOM-to-text-buffer renderer of its
  own, because GTK had no HTML control it could use.  Lazarus ships
  TIpHtmlPanel, which the IDE's own help viewer is built on, so the renderer
  is not carried over.

  Wiki markup renders here too, in medit's UseMod / Habitat dialect -- see
  Led.Core.Wiki.  It was dropped up front as a niche format, which turned out
  to be a judgement about other people's files rather than this editor's
  users. }
unit Led.UI.Preview;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, StdCtrls, Graphics, Forms,
  LCLIntf, LCLType,
  IpHtml, Ipfilebroker,
  Led.Core.Markdown, Led.Core.Wiki;

type
  TLedPreviewPane = class(TPanel)
  private
    FHtml: TIpHtmlPanel;
    FProvider: TIpFileDataProvider;
    FNote: TLabel;
    FBaseDir: string;
    FIsWiki: Boolean;
    FTimer: TTimer;
    FResizeTimer: TTimer;
    FHasRendered: Boolean;
    FPendingRender: Boolean;
    FRenderedWidth: Integer;
    FRenderedText: string;
    FRenderedTitle: string;
    FRenderedWiki: Boolean;
    FPendingText: string;
    FPendingTitle: string;
    function CodeColumns: Integer;
    procedure Render(Sender: TObject);
    { Resolves an <img> URL against the document's own folder, since
      TIpFileDataProvider otherwise looks relative to the process's working
      directory.  Any failure to load degrades to "no image" instead of an
      exception escaping into IPro's layout code. }
    procedure ProvideImage(Sender: TIpHtmlNode; const URL: string;
      var Picture: TPicture);
    { TIpHtmlPanel relays out the whole document on every repaint it is
      given, not only when the content actually changed -- so a live
      drag-resize would otherwise force a full relayout on every
      intermediate size.  Hiding it for the duration of the drag and
      revealing it once, after the size has settled, keeps the drag itself
      responsive; see FResizeTimer. }
    procedure PaneResize(Sender: TObject);
    procedure ResizeSettled(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    { Shows AText rendered as Markdown.  Debounced by default, because a
      refresh can arrive several times over in a row -- a tab change is three
      notifications -- and IPro relays out the whole document each time.
      AImmediate is for the one case where the quarter second is all the user
      would see: opening the pane, where waiting means looking at a blank
      panel for as long as it takes to notice it is blank. }
    procedure Update(const AText, ATitle, ABaseDir: string;
      AImmediate: Boolean = False);
    { Which dialect to render.  Set from the file name, so a .wiki and a .md
      in adjacent tabs each render as themselves. }
    property IsWiki: Boolean read FIsWiki write FIsWiki;
    procedure ShowMessage_(const AText: string);
    { Renders now instead of a quarter-second from now, and says whether the
      HTML control took it.  For the self-test: the render path swallows an
      exception into a message label, so "it rendered" and "it quietly gave
      up" look identical from outside. }
    function RenderNow: Boolean;
  end;

{ True when this document is one the preview understands. }
function LedPreviewHandles(const AFileName: string): Boolean;
{ The first line matters because a wiki file may be named anything and say
  so with a "<!-- wiki -->" comment, which is medit's convention. }
function LedPreviewHandles(const AFileName, AFirstLine: string): Boolean;

implementation

function LedPreviewHandles(const AFileName: string): Boolean;
begin
  Result := LedPreviewHandles(AFileName, '');
end;

function LedPreviewHandles(const AFileName, AFirstLine: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.md') or (Ext = '.markdown') or (Ext = '.mdx') or
            LedIsWikiFile(AFileName, AFirstLine);
end;

constructor TLedPreviewPane.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';

  FNote := TLabel.Create(Self);
  FNote.Parent := Self;
  FNote.Align := alTop;
  FNote.WordWrap := True;
  FNote.Caption := 'Open a Markdown or wiki file to see it rendered here.';

  FProvider := TIpFileDataProvider.Create(Self);
  FProvider.OnGetImage := @ProvideImage;

  FHtml := TIpHtmlPanel.Create(Self);
  FHtml.Parent := Self;
  FHtml.Align := alClient;
  FHtml.DataProvider := FProvider;
  FHtml.Visible := False;
  { IPro lays a page out on the control's own canvas and then, by default,
    paints it into a bitmap it allocates for the purpose.  Nothing makes the
    two agree about resolution, and here they do not: the startup sweep puts
    the control at the scaled PPI and a fresh TBitmap comes up at the
    screen's.  Every word was measured at twice the size it was drawn at,
    which is a page of text with a gap after every word that grows with the
    word.

    Painting straight onto the control's canvas makes the measuring and the
    painting the same canvas at the same resolution -- and that resolution is
    the scaled one, so the page is drawn at the size this display is scaled
    to rather than at half of it.  Doing the same by putting the control back
    on the screen's PPI also lines the two up, but lines them up small.

    The buffer this gives up is what stops flicker on a repaint; gtk2
    double-buffers its own expose events, so on this widgetset there is
    nothing to lose. }
  FHtml.UsePaintBuffer := False;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 250;
  FTimer.Enabled := False;
  FTimer.OnTimer := @Render;

  FResizeTimer := TTimer.Create(Self);
  FResizeTimer.Interval := 200;
  FResizeTimer.Enabled := False;
  FResizeTimer.OnTimer := @ResizeSettled;
  OnResize := @PaneResize;
end;

procedure TLedPreviewPane.PaneResize(Sender: TObject);
begin
  if FHasRendered and FHtml.Visible then
    FHtml.Visible := False;
  FResizeTimer.Enabled := False;
  FResizeTimer.Enabled := True;
end;

procedure TLedPreviewPane.ResizeSettled(Sender: TObject);
begin
  FResizeTimer.Enabled := False;
  if not (FHasRendered or FPendingRender) then Exit;
  { The page was built for a width -- its code blocks are wrapped to it, see
    CodeColumns -- so a pane that is no longer that width needs the page
    rebuilt rather than merely shown again.  This is also where a render that
    arrived before the pane had a size gets made good. }
  if FPendingRender or (FHtml.ClientWidth <> FRenderedWidth) then
    Render(nil)
  else
    FHtml.Visible := True;
end;

procedure TLedPreviewPane.ProvideImage(Sender: TIpHtmlNode; const URL: string;
  var Picture: TPicture);
var
  FN: string;
begin
  Picture := nil;
  if URL = '' then Exit;

  if (Pos('://', URL) > 0) or ((Length(URL) > 1) and (URL[2] = ':')) or
     (URL[1] in ['/', '\']) then
    FN := URL
  else
    FN := IncludeTrailingPathDelimiter(FBaseDir) + URL;

  Picture := TPicture.Create;
  try
    Picture.LoadFromFile(FN);
  except
    on E: Exception do
    begin
      Picture.Free;
      Picture := nil;
    end;
  end;
end;

procedure TLedPreviewPane.ShowMessage_(const AText: string);
begin
  FNote.Caption := AText;
  FNote.Visible := True;
  FHtml.Visible := False;
  FHasRendered := False;
  FPendingRender := False;
  FRenderedText := '';
  FTimer.Enabled := False;
end;

procedure TLedPreviewPane.Update(const AText, ATitle, ABaseDir: string;
  AImmediate: Boolean);
begin
  FPendingText := AText;
  FPendingTitle := ATitle;
  FBaseDir := ABaseDir;
  FTimer.Enabled := False;
  if AImmediate then
  begin
    Render(nil);
    Exit;
  end;
  { Restarting the timer on each call is the debounce: a burst of refreshes
    renders once, at the end. }
  FTimer.Enabled := True;
end;

{ How many characters of a code block fit across the pane.

  A <pre> is the one thing on a page that will not narrow: its minimum width
  is its longest line, and IPro, which cannot scroll a single block, answers
  by laying the whole document out that wide -- which is how an eighty-column
  code sample pushes the prose off the right of a pane half that wide.  So
  the page is built to fit, and this is the measurement it is built to.

  Measured in the font IPro actually uses for a <pre>: the fixed typeface at
  two points under the document size, which is what TIpHtmlNodePRE.SetProps
  does.  Measured on the panel's own canvas rather than worked out, because
  that canvas is the one the page is laid out on, at whatever PPI the startup
  sweep left it.

  The allowances are the vertical scrollbar, which a preview of anything long
  has and which comes out of the width the layout gets, and IPro's page
  margin.  Only one margin turns up in the page width it computes -- both are
  subtracted, and the difference is the slack that keeps a rounding error
  from costing a column. }
function TLedPreviewPane.CodeColumns: Integer;
var
  CharW, Usable: Integer;
begin
  Result := 0;
  if (FHtml.ClientWidth <= 0) or not FHtml.HandleAllocated then Exit;
  FHtml.Canvas.Font.Name := FHtml.FixedTypeface;
  FHtml.Canvas.Font.Size := FHtml.DefaultFontSize - 2;
  { Over twenty characters, because a single one rounds badly. }
  CharW := FHtml.Canvas.TextWidth(StringOfChar('0', 20)) div 20;
  if CharW < 1 then Exit;
  Usable := FHtml.ClientWidth - 2 * FHtml.MarginWidth -
            GetSystemMetrics(SM_CXVSCROLL);
  Result := Usable div CharW;
  { Narrower than this and the wrapping is worse than the overflow it is
    there to prevent. }
  if Result < 16 then Result := 16;
end;

procedure TLedPreviewPane.Render(Sender: TObject);
var
  Page: string;
begin
  FTimer.Enabled := False;

  { Laying a page out costs more than everything else the pane does put
    together -- half a second for a README -- so it is worth some care about
    not doing it twice.

    Before the window is on screen the pane has whatever width the form was
    designed at, not the one it is about to be given: the files named on the
    command line are opened there, and a page laid out then is laid out for a
    pane 170 pixels wide and thrown away a moment later.  It waits for the
    size instead -- asked of the pane, not of the HTML control, which is
    hidden until there is a page in it and so is never showing. }
  if not Showing then
  begin
    FPendingRender := True;
    Exit;
  end;

  { And the same document at the same width is the same page.  Opening a file
    asks for the preview from more than one direction -- the tab change, the
    command line, the pane appearing -- and each of them is right to ask. }
  if FHasRendered and (not FPendingRender) and
     (FHtml.ClientWidth = FRenderedWidth) and (FIsWiki = FRenderedWiki) and
     (FPendingTitle = FRenderedTitle) and (FPendingText = FRenderedText) then
  begin
    FHtml.Visible := True;
    Exit;
  end;

  if FIsWiki then
    Page := LedWikiToPage(FPendingText, FPendingTitle)
  else
    Page := LedMarkdownToPage(FPendingText, FPendingTitle);
  try
    { Both adjustments are for the renderer rather than for the document:
      see LedWrapPreLines and LedSplitInlineRuns. }
    FHtml.SetHtmlFromStr(LedSplitInlineRuns(LedWrapPreLines(Page, CodeColumns)));
    FRenderedWidth := FHtml.ClientWidth;
    FRenderedText := FPendingText;
    FRenderedTitle := FPendingTitle;
    FRenderedWiki := FIsWiki;
    FPendingRender := False;
    FNote.Visible := False;
    FHtml.Visible := True;
    FHasRendered := True;
  except
    on E: Exception do
      ShowMessage_('The preview could not be rendered: ' + E.Message);
  end;
end;

function TLedPreviewPane.RenderNow: Boolean;
begin
  FTimer.Enabled := False;
  Render(nil);
  Result := FHtml.Visible and not FNote.Visible;
end;

end.
