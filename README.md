# led — a light editor

`led` is a lightweight programmer's text editor written in Free Pascal with
Lazarus/LCL, so one source tree builds natively on Linux, Windows and macOS.

It is a feature-comparable successor to
[medit](https://github.com/fangq/medit), whose GTK3 implementation had grown
to ~233k lines of C — much of it hand-written widgetry (a docking system, a
notebook, an icon grid, a menu-merge engine, a forked GtkSourceView) that
existed only because GTK lacked an equivalent. `led` uses the LCL equivalents
and keeps the hand-written code for the things that are actually medit's: the
file-format handling, the layered per-document settings, the tools system, the
128 language grammars, and the editing features added in medit 1.8.

## What works

**Editing.** Tabs and split views over one shared buffer; encoding detection
with BOM handling and mixed line endings; backups; reload and external-change
detection; find and replace with regex plus an incremental find bar; find in
files; go to line; matching-bracket navigation; comment/uncomment from the
grammar's own markers; block indent and one-space `Ctrl+0`/`Ctrl+9` shifts;
bookmarks; column selection with paste-as-column; code folding; word
completion; `Ctrl+wheel` zoom.

**Languages.** All 128 of medit's GtkSourceView grammars, converted to
TextMate JSON and loaded by SynEdit's TextMate engine, plus the eight colour
themes read unchanged. Language is detected from the filename, the mime type
or a shebang line.

**Panes.** File browser with a breadcrumb bar, ctags symbol browser, command
output with clickable `file:line`, Markdown preview, and a real terminal.

**Tools.** User-defined commands with medit's option, input, output and
environment-variable contract, and named regex output filters including
`make`'s directory stack.

**Shell.** Preferences, a keyboard-shortcut editor, sessions, recent files,
single-instance file hand-off, and the medit command line including
`FILE:LINE`.

## Building

Needs FPC 3.2.2+ and Lazarus 3.0+.

```sh
./build.sh            # Linux, gtk2
./build.sh qt5        # Linux, Qt5
build.bat             # Windows
./install.sh /usr/local
```

`build.sh` produces `bin/led`, the headless test runner `bin/ledcoretest` and
`bin/langcheck`.

## Running

```sh
bin/led [OPTION...] [FILE[:LINE]...]
bin/led --help
bin/led --self-test          # scripted GUI check; needs a display
bin/led --bench-longline     # the long-line performance measurement
bin/ledcoretest --all --format=plain
bin/langcheck data/grammars  # every grammar must load
```

## Layout

```
app/                  the program
packages/ledcore/     no visual dependency — file I/O, config, tools, grep
packages/ledsyn/      themes, language registry, highlighter factory
packages/ledui/       forms, documents, views, docking, panes
packages/ledterm/     pty, VT parser, terminal widget
data/                 grammars, themes, default tools, .lang sources
tools/                lang2tm.py, gen-parity.py, langcheck
test/                 headless fpcunit suites
```

`ledcore` is built in CI with `LCLWidgetType=nogui`. That is not a detail: it
is the constraint that keeps the interesting logic out of the GUI layer and
testable without a display.

## Configuration

`~/.config/led/` on Linux, `%APPDATA%\led` on Windows, `~/Library/Application
Support/led` on macOS. Override with `$LED_CONFIG_DIR`.

| File | Holds |
|---|---|
| `prefs.ini` | preferences; dotted keys become sections, so `Plugins/Terminal/font` is `[Plugins.Terminal] font=` |
| `keys.ini` | only the shortcuts that differ from the defaults |
| `session.json` | windows, tabs, carets and dock layout |
| `recent.json` | the Open Recent list |
| `tools/*.ini` | one file per user tool |

Session and recent files are written atomically with one `.bak` generation; a
corrupt session file is ignored rather than allowed to stop startup.

Data — grammars, themes, default tools — is found next to the binary, under
`<prefix>/share/led`, or at `$LED_DATA_DIR`. A `langs/` or `themes/` directory
under the config directory shadows the shipped ones.

## Design notes

**One document, many views.** A `TLedDocument` is not a widget and not a
buffer. It owns a hidden master `TSynEdit` whose `TSynEditStringList` holds the
text, the undo list and the marks; every view shares that buffer through
`ShareTextBufferFrom`. Text, undo/redo, modified state and bookmarks are
shared; caret, selection, scroll and fold state stay per view.

Two consequences worth knowing. Edits made by writing directly to `Lines[i]`
bypass the undo list, so programmatic edits must go through the editor API.
And the highlighter is a property of each editor, not of the shared buffer, so
it has to be assigned to every view.

**Grammars are converted, not reinterpreted.** `tools/lang2tm.py` translates
GtkSourceView `.lang` files to TextMate JSON. This is tractable because
GtkSourceView's own parser already reduces every pattern to plain PCRE before
its engine sees it. `bin/langcheck` loads every generated grammar through the
real engine and is a CI gate.

**Measured, not assumed.** medit truncates lines past 4096 characters because
GtkTextView's layout cache collapses on long lines. SynEdit does not: a 5 MB
single-line file opens in 88 ms (`--bench-longline`). And a flat 2053-way
keyword alternation costs about 5 µs per line, so the converter does not
bother with trie compression.

## Parity

[`PARITY.md`](PARITY.md) tracks every medit action, preference key, shipped
tool and behavioural feature, generated from the medit tree by
`tools/gen-parity.py`. It records what is done, what is replaced by an LCL
facility, and what is deliberately not carried over.

## Licence

GNU Lesser General Public License v2.1 or later, following medit.
