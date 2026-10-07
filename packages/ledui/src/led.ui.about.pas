{ LED - a lightweight editor.  Help > About.

  What it was: a five-line ShowMessage -- the name, the version, "In the
  shape of medit", the toolkit, the widget set.  Everything that matters
  about a program's provenance was somewhere else: what licence it is under,
  whose work it ships and under what, what it is built on, and who to credit.
  A reader asking "what is this?" asked the one place in the program that is
  for answering it, and got five lines.

  So: the shape the v2m dialog uses, which is the shape that answers the
  question.  A heading with the icon, the name, what the program is and its
  version; one line for what is behind it -- the engine in a program that has
  one, the toolkit in one that does not; then the text, in sections a reader
  can skim: the copyright, the licence, what it is built with, what it ships
  that belongs to other people, and the acknowledgements.  A link to the
  source and a button.

  Built in code rather than designed, like every other dialog here: the text
  is not the same in the editor and in a fork of it, and a form file would
  have to hold the union of them.  What the fork adds, it adds through the
  two hooks below.

  Everything here is a fact that can be checked: the versions are the ones
  compiled in or asked of the engine, and the bundled list is the table in
  the README.  Nothing is said about a dependency that is not in a uses
  clause of this program. }
unit Led.UI.About;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, LCLIntf,
  LazVersion,
  Led.Core.Types, Led.UI.Dpi;

type
  { A line a program adds about itself.  Empty, or not set at all, in the
    editor; the fork answers both. }
  TLedAboutLine = function: string;

var
  { What is behind the window: the MATLAB engine and its ABI in the fork.
    With none, the dialog says what the program is built with instead --
    which in an editor is the honest answer to the same question. }
  LedAboutEngineHook: TLedAboutLine = nil;

  { A section of the text that only this program has.  Added after "built
    with" and before the bundled list, because a program's own engine is
    nearer to what it is than a font it ships. }
  LedAboutExtraHook: TLedAboutLine = nil;

{ Shows it, modal.  AIcons is the window's image list, for the app icon in
  the heading; nil is allowed and leaves the icon out. }
procedure LedShowAbout(AOwner: TComponent);

{ The text of the dialog, which is the dialog: everything else is a label
  and a button.  Public so that what the program says about itself can be
  read by a check -- a claim about a licence or a bundled work is exactly
  the kind that goes stale quietly. }
function LedAboutText: string;

implementation

type
  { The home-page link needs somewhere for its OnClick to live, and a
    dialog built in code has no form class of its own to put it on.  Owned
    by the form, so it goes when the form does. }
  TLedAboutLink = class(TComponent)
  public
    URL: string;
    procedure Clicked(Sender: TObject);
  end;

procedure TLedAboutLink.Clicked(Sender: TObject);
begin
  if URL <> '' then
    OpenURL(URL);
end;

function LedAboutText: string;
var
  L: TStringList;
  S: string;
begin
  L := TStringList.Create;
  try
    L.Add(LedAppCopyright + ', Northeastern University');
    L.Add('');

    L.Add('LICENSE');
    L.Add(LedAppName + ' is free software: you can redistribute it and/or '
      + 'modify it under the terms of the GNU General Public License, '
      + 'version 3 or (at your option) any later version '
      + '(GPL-3.0-or-later), as published by the Free Software Foundation. '
      + 'It comes with ABSOLUTELY NO WARRANTY, not even the implied warranty '
      + 'of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See '
      + 'LICENSE, or https://www.gnu.org/licenses/gpl-3.0.html.');
    L.Add('');

    L.Add('BUILT WITH');
    L.Add('- Free Pascal ' + {$I %FPCVERSION%} + ' and the Lazarus LCL '
      + laz_version + ', on ' + LedWidgetSetName);
    L.Add('- SynEdit, the editor control, and AnchorDocking, the panes');
    L.Add('- TAChart for the charts, and Turbo Power IPro for the rendered '
      + 'pages: the Markdown preview, the notebook cells and the assistant''s '
      + 'answers');
    L.Add('(all of them Lazarus components, under the modified LGPL with the '
      + 'static-linking exception.)');
    L.Add('');

    if Assigned(LedAboutExtraHook) then
    begin
      S := Trim(LedAboutExtraHook());
      if S <> '' then
      begin
        L.Add(S);
        L.Add('');
      end;
    end;

    { The table in the README, in the same words: none of it is covered by
      this program's licence and each piece keeps its own, which is the
      thing a reader is actually asking. }
    L.Add('BUNDLED, EACH UNDER ITS OWN LICENCE');
    L.Add('- Language definitions and colour themes from GtkSourceView, in '
      + 'data/langs and data/themes (LGPL-2.1-or-later)');
    L.Add('- Fira Code, in data/fonts (SIL Open Font License 1.1)');
    L.Add('- The SCOWL en_US word list by Kevin Atkinson, in data/dict (its '
      + 'own notice, in en_US.COPYRIGHT)');
    L.Add('- The TextMate grammar engine, copied from Lazarus 4.2, in '
      + 'packages/ledsyn/vendor (as upstream)');
    L.Add('');

    L.Add('ACKNOWLEDGEMENTS');
    L.Add('- Yevgen Muntyan, author of medit (2004-2010), whose feature set, '
      + 'vocabulary and shipped tools LED was built against. LED is a new '
      + 'program written in Free Pascal: no medit source is used here and '
      + 'none was translated line by line. See PARITY.md.');
    L.Add('- Developed with the assistance of the AI coding assistant Claude '
      + '(Anthropic)');
    L.Add('');
    L.Add('Source code and bug reports: ' + LedAppHome);

    Result := L.Text;
  finally
    L.Free;
  end;
end;

{ What the second line of the heading says: the engine where there is one,
  and otherwise what the program is standing on.  Never empty -- a blank
  line under the version reads as something that failed to load. }
function AboutDetail: string;
begin
  Result := '';
  if Assigned(LedAboutEngineHook) then
    Result := Trim(LedAboutEngineHook());
  if Result = '' then
    Result := 'Free Pascal ' + {$I %FPCVERSION%} + ', Lazarus LCL '
      + laz_version + ', ' + LedWidgetSetName;
end;

procedure LedShowAbout(AOwner: TComponent);
var
  F: TForm;
  Head, Foot: TPanel;
  Pic: TImage;
  Title, Subtitle, Version, Detail, Link: TLabel;
  Info: TMemo;
  Ok: TButton;
  Home: TLedAboutLink;
begin
  F := TForm.CreateNew(AOwner);
  try
    F.Caption := 'About ' + LedAppName;
    F.BorderStyle := bsDialog;
    F.Position := poOwnerFormCenter;
    F.ClientWidth := LedScale96(620);
    F.ClientHeight := LedScale96(560);

    Head := TPanel.Create(F);
    Head.Parent := F;
    Head.Align := alTop;
    Head.Height := LedScale96(132);
    Head.BevelOuter := bvNone;

    { The program's own icon, whichever way this build got one: the
      editor reads it from a resource and the fork from a file in the data
      directory, and by the time any window is up both have put it on the
      application.  Asking there is the one answer that is right for both
      and goes on being right for a third. }
    Pic := TImage.Create(F);
    Pic.Parent := Head;
    Pic.SetBounds(LedScale96(16), LedScale96(16), LedScale96(72),
                  LedScale96(72));
    Pic.Center := True;
    Pic.Proportional := True;
    Pic.Stretch := True;
    if (Application.Icon <> nil) and not Application.Icon.Empty then
      try
        Pic.Picture.Assign(Application.Icon);
      except
        on E: Exception do ;         { no icon is not a failure }
      end;

    Title := TLabel.Create(F);
    Title.Parent := Head;
    Title.SetBounds(LedScale96(104), LedScale96(12), LedScale96(400),
                    LedScale96(34));
    Title.Caption := LedAppName;
    Title.Font.Height := -LedScale96(26);
    Title.Font.Style := [fsBold];
    Title.ParentFont := False;

    Subtitle := TLabel.Create(F);
    Subtitle.Parent := Head;
    Subtitle.SetBounds(LedScale96(104), LedScale96(48), LedScale96(500),
                       LedScale96(34));
    Subtitle.AutoSize := False;
    Subtitle.WordWrap := True;
    { The tagline is what the program is called; the sentence after it is
      what it is.  "Mighty Matrix" on its own tells a reader nothing. }
    Subtitle.Caption := LedAppTagline;
    if (LedAppAbout <> '') and (LedAppAbout <> LedAppTagline) then
      Subtitle.Caption := LedAppTagline + ' -- ' + LedAppAbout;

    Version := TLabel.Create(F);
    Version.Parent := Head;
    Version.SetBounds(LedScale96(104), LedScale96(82), LedScale96(400),
                      LedScale96(18));
    Version.Caption := 'Version ' + LedAppVersion;
    Version.Font.Style := [fsBold];
    Version.ParentFont := False;

    { Inside the heading rather than under it as another top-aligned
      band: two controls aligned to the top of the same form are ordered
      by the LCL, not by the order they were made, and this one came out
      above the title.  It belongs with the name and the version anyway --
      it is the fourth line of the same statement. }
    Detail := TLabel.Create(F);
    Detail.Parent := Head;
    Detail.SetBounds(LedScale96(104), LedScale96(106), LedScale96(500),
                     LedScale96(18));
    Detail.AutoSize := False;
    Detail.WordWrap := True;
    Detail.Caption := AboutDetail;

    Foot := TPanel.Create(F);
    Foot.Parent := F;
    Foot.Align := alBottom;
    Foot.Height := LedScale96(50);
    Foot.BevelOuter := bvNone;

    Link := TLabel.Create(F);
    Link.Parent := Foot;
    Link.SetBounds(LedScale96(16), LedScale96(16), LedScale96(380),
                   LedScale96(18));
    Link.Caption := LedAppHome;
    Link.Cursor := crHandPoint;
    Link.Font.Color := clBlue;
    Link.Font.Style := [fsUnderline];
    Link.ParentFont := False;
    Home := TLedAboutLink.Create(F);
    Home.URL := LedAppHome;
    Link.OnClick := @Home.Clicked;

    Ok := TButton.Create(F);
    Ok.Parent := Foot;
    Ok.Anchors := [akTop, akRight];
    { Measured off the panel it is in and after the anchors are set: a
      button placed from the form's width before either was settled ended
      up off the end of the dialog. }
    Ok.SetBounds(Foot.ClientWidth - LedScale96(104), LedScale96(10),
                 LedScale96(88), LedScale96(30));
    Ok.Caption := 'OK';
    Ok.Default := True;
    Ok.Cancel := True;
    Ok.ModalResult := mrOK;

    { Last, so that alClient takes what the three above have left. }
    Info := TMemo.Create(F);
    Info.Parent := F;
    Info.Align := alClient;
    Info.BorderSpacing.Around := LedScale96(16);
    Info.ReadOnly := True;
    Info.WordWrap := True;
    Info.ScrollBars := ssAutoVertical;
    Info.Text := LedAboutText;
    { At the top of it: a memo filled from code is left showing its end. }
    Info.SelStart := 0;

    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.
