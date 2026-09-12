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
    FPendingText: string;
    FPendingTitle: string;
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
    { Shows AText rendered as Markdown.  Debounced, because it is called on
      every keystroke and IPro relays out the whole document each time. }
    procedure Update(const AText, ATitle, ABaseDir: string);
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
  if FHasRendered then
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
  FTimer.Enabled := False;
end;

procedure TLedPreviewPane.Update(const AText, ATitle, ABaseDir: string);
begin
  FPendingText := AText;
  FPendingTitle := ATitle;
  FBaseDir := ABaseDir;
  { Restarting the timer on each call is the debounce: the render happens a
    quarter-second after typing stops, not during it. }
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TLedPreviewPane.Render(Sender: TObject);
var
  Page: string;
begin
  FTimer.Enabled := False;
  if FIsWiki then
    Page := LedWikiToPage(FPendingText, FPendingTitle)
  else
    Page := LedMarkdownToPage(FPendingText, FPendingTitle);
  try
    { IPro measures a page on one canvas and paints it on another: the layout
      runs against the control's own canvas, and the paint against a TBitmap
      it allocates for the purpose.  A TCustomControl copies its PixelsPerInch
      onto its canvas -- customcontrol.inc:66 -- and the startup scale sweep
      has put 300 there, while a fresh TBitmap gets the screen's 150.  Same
      point size, two pixel heights: every word is measured at twice the size
      it is drawn at, so each one is advanced by about double its own width
      and the line falls apart into gaps that grow with the word.

      Measured on this display: "led" drawn 88 pixels wide, the next word
      starting at 190.  The glyphs were always the right size -- it is the
      spacing between them that was doubled.

      So the control is put back on the screen's PPI before each render.  It
      changes no drawn size, because gtk2 renders a point size at the Xft DPI
      whatever the font's PixelsPerInch says; it only makes the measuring
      canvas agree with the painting one. }
    FHtml.Font.PixelsPerInch := Screen.PixelsPerInch;
    FHtml.SetHtmlFromStr(Page);
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
