# Emits led.ui.main.lfm and the matching published-field list.  Kept as a
# generator only because the action, menu and toolbar tables are long and
# repetitive; the output is an ordinary designer-editable form, and this
# script is not needed to build.
#
# STALE -- do not run.  The .lfm has been hand-edited since, and regenerating
# it drops everything added that way: the notebook-split actions, the dock
# header-style menu and more.  Running it once already clobbered them.
#
# Kept because the tables below are still the clearest inventory of the
# actions and menus, and because a future rewrite of the form may want them.
# To add an action now, edit packages/ledui/src/led.ui.main.lfm and the
# published fields in led.ui.main.pas by hand -- there are only two places.
SC_CTRL, SC_SHIFT, SC_ALT = 0x4000, 0x2000, 0x8000

def key(ch):        return ord(ch.upper())
VK = {'F1':112, 'F3':114, 'F5':116, 'F6':117, 'DOWN':40, 'UP':38, 'SLASH':191,
      'RBRACKET':221, 'HOME':36, 'END':35, 'RBRACKET2':219,
      'PGUP':33, 'PGDN':34, 'DEL':46, 'TAB':9}

def sc(*parts):
    v = 0
    for p in parts:
        if p == 'ctrl':  v |= SC_CTRL
        elif p == 'shift': v |= SC_SHIFT
        elif p == 'alt': v |= SC_ALT
        elif p in VK:    v |= VK[p]
        else:            v |= key(p)
    return v

# name, caption, shortcut, handler-suffix, icon (see Led.UI.Icons; '' for none)
ACTIONS = [
 ('actNew',            '&New',                  sc('ctrl','N'), 'actNewExecute', 'new'),
 ('actOpen',           '&Open...',              sc('ctrl','O'), 'actOpenExecute', 'open'),
 ('actSave',           '&Save',                 sc('ctrl','S'), 'actSaveExecute', 'save'),
 ('actSaveAs',         'Save &As...',           sc('ctrl','shift','S'), 'actSaveAsExecute', 'saveas'),
 ('actReload',         '&Reload from Disk',     sc('F5'), 'actReloadExecute', 'reload'),
 ('actCloseTab',       '&Close',                sc('ctrl','W'), 'actCloseTabExecute', 'close'),
 ('actPrint',          '&Print...',             sc('ctrl','P'), 'actPrintExecute', 'print'),
 ('actPreferences',    '&Preferences...',       0, 'actPreferencesExecute', 'prefs'),
 ('actShortcuts',      'Configure &Shortcuts...', 0, 'actShortcutsExecute', 'shortcuts'),
 ('actQuit',           '&Quit',                 sc('ctrl','Q'), 'actQuitExecute', 'quit'),

 ('actUndo',           '&Undo',                 sc('ctrl','Z'), 'actUndoExecute', 'undo'),
 ('actRedo',           '&Redo',                 sc('ctrl','shift','Z'), 'actRedoExecute', 'redo'),
 ('actCut',            'Cu&t',                  sc('ctrl','X'), 'actCutExecute', 'cut'),
 ('actCopy',           '&Copy',                 sc('ctrl','C'), 'actCopyExecute', 'copy'),
 ('actPaste',          '&Paste',                sc('ctrl','V'), 'actPasteExecute', 'paste'),
 ('actSelectAll',      'Select &All',           sc('ctrl','A'), 'actSelectAllExecute', 'selectall'),
 ('actPasteColumn',    'Paste as Col&umn',      sc('ctrl','shift','V'), 'actPasteColumnExecute', ''),
 ('actClearSelection', 'Clear Se&lection',      0, 'actClearSelectionExecute', ''),
 ('actIndent',         '&Indent',               0, 'actIndentExecute', 'indent'),
 ('actUnindent',       '&Unindent',             0, 'actUnindentExecute', 'unindent'),
 ('actIndentSpace',    'Indent by One &Space',  sc('ctrl','0'), 'actIndentSpaceExecute', ''),
 ('actUnindentSpace',  'Unindent by One S&pace',sc('ctrl','9'), 'actUnindentSpaceExecute', ''),
 ('actComment',        'Co&mment',              sc('ctrl','SLASH'), 'actCommentExecute', 'comment'),
 ('actUncomment',      'Uncomm&ent',            sc('ctrl','shift','SLASH'), 'actUncommentExecute', 'uncomment'),

 ('actFind',           '&Find...',              sc('ctrl','F'), 'actFindExecute', 'find'),
 ('actReplace',        '&Replace...',           sc('ctrl','R'), 'actReplaceExecute', 'replace'),
 ('actFindNext',       'Find &Next',            sc('F3'), 'actFindNextExecute', 'findnext'),
 ('actFindPrev',       'Find &Previous',        sc('shift','F3'), 'actFindPrevExecute', 'findprev'),
 ('actQuickFind',      '&Incremental Find',     sc('ctrl','shift','F'), 'actQuickFindExecute', ''),
 ('actFindInFiles',    'Find in &Files...',     sc('ctrl','shift','G'), 'actFindInFilesExecute', ''),
 ('actGotoLine',       '&Go to Line...',        sc('ctrl','G'), 'actGotoLineExecute', 'gotoline'),
 ('actToggleBracket',  'Go to &Matching Bracket', sc('ctrl','RBRACKET'), 'actToggleBracketExecute', ''),
 ('actSelectToBracket','&Select to Matching Bracket', sc('ctrl','shift','RBRACKET'), 'actSelectToBracketExecute', ''),

 ('actToggleBookmark', 'Toggle &Bookmark',      sc('ctrl','B'), 'actToggleBookmarkExecute', 'bookmark'),
 ('actAddBookmark',    '&Add Bookmark',         0, 'actAddBookmarkExecute', ''),
 ('actEditBookmarks',  '&Edit Bookmarks...',    0, 'actEditBookmarksExecute', ''),
 ('actNextBookmark',   '&Next Bookmark',        sc('alt','DOWN'), 'actNextBookmarkExecute', ''),
 ('actPrevBookmark',   '&Previous Bookmark',    sc('alt','UP'), 'actPrevBookmarkExecute', ''),

 ('actSplitSideBySide','Split &Side by Side',   0, 'actSplitSideBySideExecute', 'splith'),
 ('actSplitStacked',   'Split S&tacked',        0, 'actSplitStackedExecute', 'splitv'),
 ('actUnsplit',        '&Unsplit',              0, 'actUnsplitExecute', ''),
 ('actCycleViews',     'Cycle Split &Views',    sc('F6'), 'actCycleViewsExecute', ''),
 ('actToggleFold',     'Toggle &Fold',          sc('ctrl','shift','RBRACKET2'), 'actToggleFoldExecute', ''),
 ('actFoldAll',        'Fold &All',             0, 'actFoldAllExecute', ''),
 ('actUnfoldAll',      '&Unfold All',           0, 'actUnfoldAllExecute', ''),
 ('actWrapText',       '&Wrap Text',            0, 'actWrapTextExecute', 'wrap'),
 ('actLineNumbers',    'Line &Numbers',         0, 'actLineNumbersExecute', 'linenumbers'),
 ('actStopTool',       '&Stop Running Tool',    0, 'actStopToolExecute', 'stop'),
 ('actToggleOutput',   '&Output Pane',          0, 'actToggleOutputExecute', ''),
 ('actToggleTerminal', '&Terminal',             0, 'actToggleTerminalExecute', 'terminal'),
 ('actToggleSymbols',  '&Symbols',              0, 'actToggleSymbolsExecute', 'symbols'),
 ('actTogglePreview',  'Markdown Pre&view',     0, 'actTogglePreviewExecute', ''),
 ('actComplete',       'Complete &Word',        0, 'actCompleteExecute', ''),
 ('actToggleLeftPane', '&Left Pane',            0, 'actToggleLeftPaneExecute', ''),
 ('actToggleBottomPane','&Bottom Pane',         0, 'actToggleBottomPaneExecute', ''),

 # The remainder of medit.xml's action inventory.
 ('actNewWindow',      'New &Window',           sc('ctrl','shift','N'), 'actNewWindowExecute', ''),
 ('actCloseAll',       'Close A&ll',            0, 'actCloseAllExecute', ''),
 ('actReopenEncoding', 'Reopen &with Encoding', 0, 'actReopenEncodingExecute', ''),
 ('actPageSetup',      'Page Set&up...',        0, 'actPageSetupExecute', ''),
 ('actPrintPdf',       'Export as P&DF...',     0, 'actPrintPdfExecute', ''),
 ('actExportHtml',     'Export as &HTML...',    0, 'actExportHtmlExecute', ''),
 ('actDelete',         '&Delete',               sc('DEL'), 'actDeleteExecute', ''),
 ('actFindCurrent',    'Find Word at &Cursor',  sc('ctrl','shift','UP'), 'actFindCurrentExecute', ''),
 ('actFindCurrentBack','Find Word at Cursor &Backwards', sc('ctrl','shift','DOWN'), 'actFindCurrentBackExecute', ''),
 ('actPrevTab',        '&Previous Tab',         sc('ctrl','PGUP'), 'actPrevTabExecute', ''),
 ('actNextTab',        '&Next Tab',             sc('ctrl','PGDN'), 'actNextTabExecute', ''),
 ('actFocusDoc',       '&Focus Document',       sc('alt','END'), 'actFocusDocExecute', ''),
 ('actMoveToSplit',    '&Move to Split View',   0, 'actMoveToSplitExecute', ''),
 ('actShowToolbar',    'Show &Toolbar',         0, 'actShowToolbarExecute', ''),
 ('actStripTrailing',  'Strip &Trailing Space', 0, 'actStripTrailingExecute', ''),
 ('actToggleBrowser',  'File &Browser',         0, 'actToggleBrowserExecute', 'browser'),
 ('actSplitTermH',     'Split Terminal S&ide by Side', 0, 'actSplitTermHExecute', ''),
 ('actSplitTermV',     'Split Terminal St&acked', 0, 'actSplitTermVExecute', ''),
 ('actHelp',           '&Contents',             sc('F1'), 'actHelpExecute', 'help'),
 ('actReportBug',      '&Report a Bug',         0, 'actReportBugExecute', ''),
 ('actAbout',          '&About led',            0, 'actAboutExecute', 'about'),
]

# The toolbar, in medit.xml's order.  '-' is a separator.
TOOLBAR = ['actNew', '-', 'actOpen', 'actSave', 'actSaveAs', '-',
           'actUndo', 'actRedo', '-',
           'actCut', 'actCopy', 'actPaste', '-',
           'actFind', 'actReplace', '-',
           'actStopTool']

# The right-click menu over the text area.
CONTEXT = [('action','actUndo'), ('action','actRedo'), ('sep',),
           ('action','actCut'), ('action','actCopy'), ('action','actPaste'),
           ('action','actDelete'), ('sep',),
           ('action','actSelectAll'), ('sep',),
           ('action','actComment'), ('action','actUncomment'),
           ('action','actIndent'), ('action','actUnindent'), ('sep',),
           ('action','actToggleBookmark'),
           ('action','actToggleFold'), ('sep',),
           ('sub','miCtxTools','(no tools)','miToolListClick'), ('sep',),
           ('action','actGotoLine'), ('action','actFindCurrent')]

# The right-click menu on a notebook tab.
TABMENU = [('action','actSave'), ('action','actSaveAs'),
           ('action','actReload'), ('sep',),
           ('action','actCloseTab'), ('action','actCloseAll'), ('sep',),
           ('sub','miTabCloseOthers','Close &Other Tabs','miTabCloseOthersClick'),
           ('sub','miTabCopyPath','Cop&y Full Path','miTabCopyPathClick'),
           ('sub','miTabOpenFolder','Open Containing &Folder','miTabOpenFolderClick'), ('sep',),
           ('action','actSplitSideBySide'), ('action','actSplitStacked')]

# (menu-name, caption, [entries])   entry: ('action', name) | ('sep',) |
#                                          ('sub', itemname, caption, onclick)
MENUS = [
 ('mnuFile', '&File', [
   ('action','actNew'), ('action','actNewWindow'), ('sep',),
   ('action','actOpen'),
   ('sub','miOpenRecent','Open &Recent','miOpenRecentClick'),
   ('sub','miReopenEncoding','Reopen &with Encoding','miReopenEncodingClick'),
   ('action','actReload'), ('sep',),
   ('action','actSave'), ('action','actSaveAs'), ('sep',),
   ('action','actPageSetup'), ('action','actPrint'),
   ('action','actPrintPdf'), ('action','actExportHtml'), ('sep',),
   ('action','actCloseTab'), ('action','actCloseAll'), ('sep',),
   ('action','actQuit')]),
 ('mnuEdit', '&Edit', [
   ('action','actUndo'), ('action','actRedo'), ('sep',),
   ('action','actCut'), ('action','actCopy'), ('action','actPaste'),
   ('action','actDelete'), ('sep',),
   ('action','actSelectAll'), ('action','actPasteColumn'),
   ('action','actClearSelection'), ('sep',),
   ('action','actIndent'), ('action','actUnindent'),
   ('action','actIndentSpace'), ('action','actUnindentSpace'), ('sep',),
   ('action','actComment'), ('action','actUncomment'),
   ('action','actStripTrailing'), ('action','actComplete'), ('sep',),
   ('action','actShortcuts'), ('action','actPreferences')]),
 ('mnuSearch', '&Search', [
   ('action','actFind'), ('action','actReplace'),
   ('action','actFindNext'), ('action','actFindPrev'),
   ('action','actQuickFind'), ('action','actFindInFiles'), ('sep',),
   ('action','actFindCurrent'), ('action','actFindCurrentBack'), ('sep',),
   ('action','actGotoLine'), ('sep',),
   ('action','actToggleBracket'), ('action','actSelectToBracket')]),
 ('mnuDocument', '&Document', [
   ('sub','miLanguage','&Language','miLanguageClick'),
   ('sub','miEncoding','&Encoding','miEncodingClick'),
   ('sub','miLineEnd','Line &Endings','miLineEndClick'), ('sep',),
   ('action','actToggleBookmark'), ('action','actAddBookmark'),
   ('action','actNextBookmark'), ('action','actPrevBookmark'),
   ('sub','miBookmarks','&Bookmarks','miBookmarksClick'),
   ('action','actEditBookmarks')]),
 ('mnuTools', '&Tools', [
   ('sub','miToolList','(no tools)','miToolListClick'), ('sep',),
   ('action','actSplitTermH'), ('action','actSplitTermV'), ('sep',),
   ('action','actStopTool')]),
 ('mnuView', '&View', [
   ('action','actShowToolbar'), ('sep',),
   ('action','actWrapText'), ('action','actLineNumbers'), ('sep',),
   ('action','actFocusDoc'), ('action','actMoveToSplit'), ('sep',),
   ('action','actToggleFold'), ('action','actFoldAll'),
   ('action','actUnfoldAll'), ('sep',),
   ('action','actSplitSideBySide'), ('action','actSplitStacked'),
   ('action','actUnsplit'), ('action','actCycleViews'), ('sep',),
   ('sub','miTheme','Colour &Theme','miThemeClick'), ('sep',),
   ('action','actToggleLeftPane'), ('action','actToggleBottomPane'),
   ('action','actToggleBrowser'), ('action','actToggleOutput'),
   ('action','actToggleTerminal'), ('action','actToggleSymbols'),
   ('action','actTogglePreview')]),
 ('mnuWindow', '&Window', [
   ('action','actPrevTab'), ('action','actNextTab'), ('sep',),
   ('sub','miDocList','(no documents)','miDocListClick')]),
 ('mnuHelp', '&Help', [
   ('action','actHelp'), ('action','actReportBug'), ('sep',),
   ('action','actAbout')]),
]

# The image list is filled at run time by Led.UI.Icons in this order, so the
# index of a name here is the ImageIndex the LFM refers to.
ICON_ORDER = ['new', 'open', 'save', 'saveas', 'close', 'reload', 'print', 'quit',
  'undo', 'redo', 'cut', 'copy', 'paste', 'delete', 'selectall',
  'indent', 'unindent', 'comment', 'uncomment',
  'find', 'findnext', 'findprev', 'replace', 'gotoline',
  'bookmark', 'prefs', 'shortcuts', 'stop', 'run', 'terminal',
  'browser', 'symbols', 'splith', 'splitv', 'wrap', 'linenumbers',
  'help', 'about']

def iconidx(name):
    return ICON_ORDER.index(name) if name in ICON_ORDER else -1

ICON_OF = {a[0]: a[4] for a in ACTIONS}

out = []
w = out.append
w("object LedMainForm: TLedMainForm")
w("  Left = 300")
w("  Height = 700")
w("  Top = 150")
w("  Width = 1000")
w("  Caption = 'led'")
w("  Menu = MainMenu1")
w("  OnActivate = FormActivate")
w("  OnCloseQuery = FormCloseQuery")
w("  OnCreate = FormCreate")
w("  OnDestroy = FormDestroy")
w("  Position = poScreenCenter")
w("  LCLVersion = '4.2'")
w("  object StatusBar1: TStatusBar")
w("    Left = 0")
w("    Height = 23")
w("    Top = 677")
w("    Width = 1000")
w("    Panels = <    ")
for text, width in [('Line 1  Col 1',160), ('utf8',90), ('LF',70),
                    ('Plain text',130), ('INS',60)]:
    w("      item")
    w("        Text = '%s'" % text)
    w("        Width = %d" % width)
    w("      end    ")
out[-1] = out[-1].rstrip()
out[-1] = "      end>"
w("    SimplePanel = False")
w("  end")

w("  object ActionList1: TActionList")
w("    Images = ImageList1")
w("    OnUpdate = ActionList1Update")
w("    Left = 48")
w("    Top = 48")
for name, caption, shortcut, handler, icon in ACTIONS:
    w("    object %s: TAction" % name)
    w("      Caption = '%s'" % caption.replace("'", "''"))
    if shortcut:
        w("      ShortCut = %d" % shortcut)
    if iconidx(icon) >= 0:
        w("      ImageIndex = %d" % iconidx(icon))
    w("      OnExecute = %s" % handler)
    w("    end")
w("  end")

w("  object MainMenu1: TMainMenu")
w("    Images = ImageList1")
w("    Left = 48")
w("    Top = 112")
sepno = 0
for mname, mcaption, entries in MENUS:
    w("    object %s: TMenuItem" % mname)
    w("      Caption = '%s'" % mcaption)
    for e in entries:
        if e[0] == 'action':
            w("      object mi_%s: TMenuItem" % e[1][3:])
            w("        Action = %s" % e[1])
            w("      end")
        elif e[0] == 'sep':
            sepno += 1
            w("      object miSep%d: TMenuItem" % sepno)
            w("        Caption = '-'")
            w("      end")
        else:
            w("      object %s: TMenuItem" % e[1])
            w("        Caption = '%s'" % e[2])
            w("        OnClick = %s" % e[3])
            w("      end")
    w("    end")
w("  end")

def emit_menu_items(entries, indent, prefix, counter):
    for e in entries:
        if e[0] == 'action':
            w("%sobject %s%s: TMenuItem" % (indent, prefix, e[1][3:]))
            w("%s  Action = %s" % (indent, e[1]))
            w("%send" % indent)
        elif e[0] == 'sep':
            counter[0] += 1
            w("%sobject %sSep%d: TMenuItem" % (indent, prefix, counter[0]))
            w("%s  Caption = '-'" % indent)
            w("%send" % indent)
        else:
            w("%sobject %s: TMenuItem" % (indent, e[1]))
            w("%s  Caption = '%s'" % (indent, e[2].replace("'", "''")))
            w("%s  OnClick = %s" % (indent, e[3]))
            w("%send" % indent)

# The bitmaps are drawn at run time, so the list ships empty and only its
# geometry is set here.
w("  object ImageList1: TImageList")
w("    Height = 16")
w("    Width = 16")
w("    Left = 48")
w("    Top = 304")
w("  end")

w("  object ToolBar1: TToolBar")
w("    Left = 0")
w("    Height = 26")
w("    Top = 0")
w("    Width = 1000")
w("    AutoSize = True")
w("    ButtonHeight = 24")
w("    ButtonWidth = 24")
w("    Caption = 'ToolBar1'")
w("    EdgeBorders = [ebBottom]")
w("    Images = ImageList1")
w("    ParentShowHint = False")
w("    ShowHint = True")
w("    TabOrder = 1")
sepno_tb = 0
for i, item in enumerate(TOOLBAR):
    if item == '-':
        sepno_tb += 1
        w("    object tbSep%d: TToolButton" % sepno_tb)
        w("      Left = %d" % (1 + i * 24))
        w("      Height = 24")
        w("      Top = 2")
        w("      Caption = '-'")
        w("      Style = tbsDivider")
        w("    end")
    else:
        w("    object tb%s: TToolButton" % item[3:])
        w("      Left = %d" % (1 + i * 24))
        w("      Top = 2")
        w("      Action = %s" % item)
        w("    end")
w("  end")

ctxcount = [0]
w("  object PopupEditor: TPopupMenu")
w("    Images = ImageList1")
w("    OnPopup = PopupEditorPopup")
w("    Left = 48")
w("    Top = 368")
emit_menu_items(CONTEXT, "    ", "mc", ctxcount)
w("  end")

tabcount = [0]
w("  object PopupTab: TPopupMenu")
w("    Images = ImageList1")
w("    OnPopup = PopupTabPopup")
w("    Left = 48")
w("    Top = 432")
emit_menu_items(TABMENU, "    ", "mt", tabcount)
w("  end")

w("  object OpenDialog1: TOpenDialog")
w("    Options = [ofAllowMultiSelect, ofEnableSizing, ofViewDetail]")
w("    Left = 48")
w("    Top = 176")
w("  end")
w("  object SaveDialog1: TSaveDialog")
w("    Options = [ofOverwritePrompt, ofEnableSizing, ofViewDetail]")
w("    Left = 48")
w("    Top = 240")
w("  end")
w("end")

open('packages/ledui/src/led.ui.main.lfm','w').write("\n".join(out) + "\n")

# The published field list the .pas must declare, in the same order.
fields = []
fields.append("    ActionList1: TActionList;")
for name, _, _, _, _ in ACTIONS:
    fields.append("    %s: TAction;" % name)
fields.append("    MainMenu1: TMainMenu;")
sepno = 0
for mname, _, entries in MENUS:
    fields.append("    %s: TMenuItem;" % mname)
    for e in entries:
        if e[0] == 'action':
            fields.append("    mi_%s: TMenuItem;" % e[1][3:])
        elif e[0] == 'sep':
            sepno += 1
            fields.append("    miSep%d: TMenuItem;" % sepno)
        else:
            fields.append("    %s: TMenuItem;" % e[1])
fields.append("    ImageList1: TImageList;")
fields.append("    ToolBar1: TToolBar;")
sepno_tb = 0
for item in TOOLBAR:
    if item == '-':
        sepno_tb += 1
        fields.append("    tbSep%d: TToolButton;" % sepno_tb)
    else:
        fields.append("    tb%s: TToolButton;" % item[3:])

def menu_fields(entries, prefix, counter):
    for e in entries:
        if e[0] == 'action':
            fields.append("    %s%s: TMenuItem;" % (prefix, e[1][3:]))
        elif e[0] == 'sep':
            counter[0] += 1
            fields.append("    %sSep%d: TMenuItem;" % (prefix, counter[0]))
        else:
            fields.append("    %s: TMenuItem;" % e[1])

fields.append("    PopupEditor: TPopupMenu;")
menu_fields(CONTEXT, "mc", [0])
fields.append("    PopupTab: TPopupMenu;")
menu_fields(TABMENU, "mt", [0])
fields.append("    OpenDialog1: TOpenDialog;")
fields.append("    SaveDialog1: TSaveDialog;")
fields.append("    StatusBar1: TStatusBar;")
open('/tmp/claude-1000/-home-fangq-space-git-Project-github-mooedit/bd727f38-db94-4db5-b44d-b8c08e116214/scratchpad/fields.txt','w').write("\n".join(fields) + "\n")

handlers = sorted(set(h for _,_,_,h,_ in ACTIONS)) + \
           ['miOpenRecentClick','miLanguageClick','miEncodingClick',
            'miLineEndClick','miThemeClick','miToolListClick',
            'miReopenEncodingClick','miDocListClick',
            'miTabCloseOthersClick','miTabCopyPathClick','miTabOpenFolderClick',
            'miBookmarksClick',
            'PopupEditorPopup','PopupTabPopup']
open('/tmp/claude-1000/-home-fangq-space-git-Project-github-mooedit/bd727f38-db94-4db5-b44d-b8c08e116214/scratchpad/handlers.txt','w').write("\n".join(handlers) + "\n")
print("lfm written; %d actions, %d toolbar buttons, %d menus"
      % (len(ACTIONS), len([t for t in TOOLBAR if t != '-']), len(MENUS)))
