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

**Phase 0 — walking skeleton.** Builds and runs; opens, edits, splits and
saves files. Everything else is on the roadmap.

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

## Parity

[`PARITY.md`](PARITY.md) tracks every medit action, preference key, shipped
tool and behavioural feature, and is generated from the medit tree by
`tools/gen-parity.py`.

## Licence

GNU Lesser General Public License v2.1 or later, following medit.
