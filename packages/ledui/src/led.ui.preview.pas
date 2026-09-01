{ led - a light editor.  The Markdown preview pane.

  medit rendered HTML with a 3,100-line DOM-to-text-buffer renderer of its
  own, because GTK had no HTML control it could use.  Lazarus ships
  TIpHtmlPanel, which the IDE's own help viewer is built on, so the renderer
  is not carried over.

  Wiki markup is not supported.  medit had it; it was dropped deliberately as
  a niche format, and saying so is better than a half-working parser. }
unit Led.UI.Preview;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, StdCtrls, Graphics, Forms,
  IpHtml, Ipfilebroker,
  Led.Core.Markdown;

type
  TLedPreviewPane = class(TPanel)
  private
    FHtml: TIpHtmlPanel;
    FProvider: TIpFileDataProvider;
    FNote: TLabel;
    FBaseDir: string;
    FTimer: TTimer;
    FPendingText: string;
    FPendingTitle: string;
    procedure Render(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    { Shows AText rendered as Markdown.  Debounced, because it is called on
      every keystroke and IPro relays out the whole document each time. }
    procedure Update(const AText, ATitle, ABaseDir: string);
    procedure ShowMessage_(const AText: string);
  end;

{ True when this document is one the preview understands. }
function LedPreviewHandles(const AFileName: string): Boolean;

implementation

function LedPreviewHandles(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.md') or (Ext = '.markdown') or (Ext = '.mdx');
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
  FNote.Caption := 'Open a Markdown file to see it rendered here.';

  FProvider := TIpFileDataProvider.Create(Self);

  FHtml := TIpHtmlPanel.Create(Self);
  FHtml.Parent := Self;
  FHtml.Align := alClient;
  FHtml.DataProvider := FProvider;
  FHtml.Visible := False;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 250;
  FTimer.Enabled := False;
  FTimer.OnTimer := @Render;
end;

procedure TLedPreviewPane.ShowMessage_(const AText: string);
begin
  FNote.Caption := AText;
  FNote.Visible := True;
  FHtml.Visible := False;
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
  Page := LedMarkdownToPage(FPendingText, FPendingTitle);
  try
    FHtml.SetHtmlFromStr(Page);
    FNote.Visible := False;
    FHtml.Visible := True;
  except
    on E: Exception do
      ShowMessage_('The preview could not be rendered: ' + E.Message);
  end;
end;

end.
