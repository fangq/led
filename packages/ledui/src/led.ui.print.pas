{ led - a light editor.  Printing.

  A paginated dump of the document with line numbers and a header, drawn on
  the printer canvas.  Deliberately plain: syntax colours on paper cost more
  than they are worth, and most people printing code want it legible in
  black on white.

  Printer4Lazarus is what makes this portable; the same code drives CUPS,
  the Windows spooler and the macOS print system. }
unit Led.UI.Print;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Printers, PrintersDlgs, Dialogs, Forms,
  fppdf, SynExportHTML,
  Led.UI.Edit;

{ Prints AView's document.  ATitle appears in the page header.  Returns False
  when there is no printer configured, or the user cancelled. }
function LedPrintDocument(AView: TLedEdit; const ATitle: string): Boolean;

{ True when a printer is available at all, so the menu can be greyed out
  rather than raising when clicked. }
function LedPrinterAvailable: Boolean;

{ The platform page-setup dialog.  Margins and orientation belong to the
  printer, so there is nothing of led's own to persist here. }
procedure LedPageSetup(AOwner: TComponent);

{ Writes the document as a PDF without going through a printer, which is
  what medit's "Print to PDF" did via cairo.  fcl-pdf's base-14 Courier is
  used rather than an embedded TTF: it needs no font file at run time and a
  code listing is monospaced anyway. }
function LedExportPdf(AView: TLedEdit; const ATitle, AFileName: string): Boolean;

{ Writes the document as syntax-coloured HTML, using the highlighter that is
  already attached to the view. }
function LedExportHtml(AView: TLedEdit; const ATitle, AFileName: string): Boolean;

implementation

function LedPrinterAvailable: Boolean;
begin
  Result := False;
  try
    Result := Printer.Printers.Count > 0;
  except
    { Some systems raise rather than report an empty list. }
    Result := False;
  end;
end;

function LedPrintDocument(AView: TLedEdit; const ATitle: string): Boolean;
var
  Dlg: TPrintDialog;
  LineH, Top, Bottom, Left, y, i, PageNo, NumW: Integer;
  Header, Text_: string;
begin
  Result := False;
  if (AView = nil) or (AView.Lines.Count = 0) then Exit;
  if not LedPrinterAvailable then Exit;

  Dlg := TPrintDialog.Create(nil);
  try
    if not Dlg.Execute then Exit;
  finally
    Dlg.Free;
  end;

  Printer.Title := ATitle;
  Printer.BeginDoc;
  try
    Printer.Canvas.Font.Name :=
      {$IFDEF WINDOWS}'Consolas'{$ELSE}'Monospace'{$ENDIF};
    Printer.Canvas.Font.Size := 9;
    Printer.Canvas.Font.Color := clBlack;

    LineH := Printer.Canvas.TextHeight('Mg');
    if LineH < 1 then LineH := 12;
    Left := Printer.PageWidth div 25;
    Top := Printer.PageHeight div 25;
    Bottom := Printer.PageHeight - Top;
    NumW := Printer.Canvas.TextWidth('99999 ');

    PageNo := 1;
    y := Top;
    Header := ATitle;

    for i := 0 to AView.Lines.Count - 1 do
    begin
      if y = Top then
      begin
        { A header on every page, because a stack of printed code is
          otherwise impossible to sort out. }
        Printer.Canvas.Font.Style := [fsBold];
        Printer.Canvas.TextOut(Left, y,
          Format('%s    -    page %d', [Header, PageNo]));
        Printer.Canvas.Font.Style := [];
        Inc(y, LineH * 2);
      end;

      Printer.Canvas.Font.Color := clGray;
      Printer.Canvas.TextOut(Left, y, Format('%5d', [i + 1]));
      Printer.Canvas.Font.Color := clBlack;
      Text_ := AView.Lines[i];
      Printer.Canvas.TextOut(Left + NumW, y, Text_);

      Inc(y, LineH);
      if y + LineH > Bottom then
      begin
        Printer.NewPage;
        Inc(PageNo);
        y := Top;
      end;
    end;
  finally
    Printer.EndDoc;
  end;
  Result := True;
end;

procedure LedPageSetup(AOwner: TComponent);
var
  Dlg: TPageSetupDialog;
begin
  Dlg := TPageSetupDialog.Create(AOwner);
  try
    Dlg.Execute;
  finally
    Dlg.Free;
  end;
end;

function LedExportHtml(AView: TLedEdit; const ATitle, AFileName: string): Boolean;
var
  Exp: TSynExporterHTML;
begin
  Exp := TSynExporterHTML.Create(nil);
  try
    Exp.Highlighter := AView.Highlighter;
    Exp.Title := ATitle;
    Exp.ExportAsText := False;
    Exp.Font := AView.Font;
    Exp.Color := AView.Color;
    Exp.ExportAll(AView.Lines);
    Exp.SaveToFile(AFileName);
    Result := True;
  finally
    Exp.Free;
  end;
end;

function LedExportPdf(AView: TLedEdit; const ATitle, AFileName: string): Boolean;
const
  LeftMargin  = 40;
  TopMargin   = 40;
  FontSize    = 9;
  Leading     = 11;
var
  Doc: TPDFDocument;
  Sec: TPDFSection;
  Page: TPDFPage;
  FontIdx, i: Integer;
  Y, Bottom: TPDFFloat;

  procedure NewPage;
  begin
    Page := Doc.Pages.AddPage;
    Page.PaperType := ptA4;
    Page.UnitOfMeasure := uomPixels;
    Sec.AddPage(Page);
    Y := TopMargin;
  end;

  { fcl-pdf writes the string into a PDF text object, where a backslash and
    the parentheses are syntax.  Tabs have no width there either, so they are
    expanded here rather than silently collapsing. }
  function Clean(const S: string): string;
  begin
    Result := StringReplace(S, #9, '    ', [rfReplaceAll]);
  end;

begin
  Doc := TPDFDocument.Create(nil);
  try
    Doc.Infos.Title := ATitle;
    Doc.Infos.Producer := 'led';
    Doc.Infos.CreationDate := Now;
    Doc.Options := [poPageOriginAtTop, poNoEmbeddedFonts];
    Doc.StartDocument;
    Sec := Doc.Sections.AddSection;
    FontIdx := Doc.AddFont('Courier');

    NewPage;
    Bottom := Page.Paper.H - TopMargin;
    Page.SetFont(FontIdx, FontSize);

    for i := 0 to AView.Lines.Count - 1 do
    begin
      if Y > Bottom then
      begin
        NewPage;
        Page.SetFont(FontIdx, FontSize);
      end;
      if AView.Lines[i] <> '' then
        Page.WriteText(LeftMargin, Y, Clean(AView.Lines[i]));
      Y := Y + Leading;
    end;

    Doc.SaveToFile(AFileName);
    Result := True;
  finally
    Doc.Free;
  end;
end;

end.
