# led — a light editor

`led` is a lightweight programmer's text editor written in Free Pascal with
Lazarus/LCL, so one source tree builds natively on Linux, Windows and macOS.

It is a feature-comparable successor to
[medit](https://github.com/fangq/medit), whose GTK3 implementation had grown
~233k lines of C — much of it hand-written widgetry (a docking system, a
notebook, an icon grid, a menu-merge engine, a forked GtkSourceView) that
existed only because GTK lacked an equivalent. `led` uses the LCL equivalents
instead and keeps the hand-written code for the things that are actually
medit's: the file-format handling, the layered per-document settings, the
tools system, and the editing features added in medit 1.8.

## Status

**Phase 1 — the file layer.** Builds and runs on Linux and Windows. Opens,
edits, splits and saves files with proper encoding detection, BOM handling and
line-ending preservation; layered per-document settings with modeline support;
INI preferences, JSON session and recent files; reload and external-change
detection.

medit's 128 grammars and 8 colour themes are vendored in `data/` and read
unchanged. Language is detected from the filename, the mime type or a shebang
line; the Document menu lists every grammar grouped by section, and the View
menu switches themes live.

Highlighting currently uses Lazarus's own highlighters, which cover about
twenty of the 128 languages — the rest are recognised, and carry their comment
markers, but are not yet coloured. The grammar converter that closes that gap
is a later phase.

Filename-glob rules and an encoding prompt round out phase 1. A rule pairs a
filter (`globs:Makefile*`, `langs:python`, `regex:^/etc/`) with a config
string, and applies above a modeline but below the language default -- so a
Makefile gets real tabs whatever the file itself claims. Built-in rules cover
makefiles, patches and Python; they live in `prefs.ini` under
`[FilterSettings]` and can be replaced wholesale.

## Building

Needs FPC 3.2.2+ and Lazarus 3.0+.

```sh
./build.sh            # Linux, gtk2
./build.sh qt5        # Linux, Qt5
build.bat             # Windows
```

Both produce `bin/led` and the headless test runner `bin/ledcoretest`.

## Running

```sh
bin/led [FILE...]
bin/led --self-test        # scripted GUI check; needs a display
bin/led --bench-longline   # the long-line performance measurement
bin/ledcoretest --all --format=plain
```

## Layout

```
app/                  the program
packages/ledcore/     no visual dependency at all — file I/O, config, tools
packages/ledsyn/      themes and highlighting
packages/ledui/       forms, documents, views, docking
packages/ledterm/     terminal emulator (later phase, optional)
data/                 grammars, themes, default tools, icons
tools/                offline converters and generators
test/                 headless fpcunit suites
```

`ledcore` is built in CI with `LCLWidgetType=nogui`. That is not a detail: it
is the constraint that keeps the interesting logic out of the GUI layer and
testable without a display.

## Design notes

**One document, many views.** A `TLedDocument` is not a widget and not a
buffer. It owns a hidden master `TSynEdit` whose `TSynEditStringList` holds
the text, the undo list and the marks; every visible view shares that buffer
through `ShareTextBufferFrom`. Text, undo/redo, modified state and bookmarks
are shared across views, while caret, selection, scroll position and fold
state stay per view. A document can also exist with no views at all, which
find-in-files replace and session preload both need.

One consequence worth knowing: edits made by writing directly to `Lines[i]`
bypass the undo list. Programmatic edits — from scripts, from replace-in-files
— must go through the editor API to be undoable.

**Measured, not assumed.** medit truncates lines past 4096 characters because
GtkTextView's layout cache collapses on long lines. SynEdit does not have that
problem: a 5 MB single-line file opens in 88 ms and edits in ~145 ms
(`--bench-longline`). So `led` still ships truncate-and-reveal, but as a
readability feature rather than a performance workaround.

## Configuration

`~/.config/led/` on Linux, `%APPDATA%\led` on Windows, `~/Library/Application
Support/led` on macOS. Override with `$LED_CONFIG_DIR`.

| File | Holds |
|---|---|
| `prefs.ini` | preferences; dotted keys become sections, so `Plugins/Terminal/font` is `[Plugins.Terminal] font=` |
| `session.json` | windows, tabs, carets and dock layout (when `Editor/save_session` is on) |
| `recent.json` | the Open Recent list |

Filename-glob rules are stored in `prefs.ini`:

```ini
[FilterSettings]
count=1
1.filter=globs:Makefile*;*.mk
1.config=indent-use-tabs: true; tab-width: 8
```

`data/langs/*.lang` and `data/themes/*.xml` are read from the install or the
build tree; a `langs/` or `themes/` directory under the config directory
shadows them, so a user grammar wins over a shipped one with the same id.

`data/langs/*.lang` and `data/themes/*.xml` are read from the install (or the
build tree); a `langs/` or `themes/` directory under the config directory
shadows them, so a user grammar wins over a shipped one of the same id.

Session and recent files are written atomically with one `.bak` generation; a
corrupt session file is ignored rather than allowed to stop startup.

## Parity

[`PARITY.md`](PARITY.md) tracks every medit action, preference key, shipped
tool and behavioural feature, and is generated from the medit tree by
`tools/gen-parity.py`.

## Licence

GNU Lesser General Public License v2.1 or later, following medit.
