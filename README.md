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

**Editing.** Tabs and split views over one shared buffer; two independent tab
groups per window — *Split Notebook*, *Move to Split Notebook* and *Focus
Other Split Notebook*, on the View menu and on a tab's right-click menu,
enabled once more than one tab is open; encoding detection
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
Each window edge carries a strip of buttons, one per pane registered there and
pressed while that pane is open, so a pane closed from its own header can be
brought back with one click instead of only through the View menu. Turn the
strips off with `Editor/show_pane_buttons`.

Panes can be dragged between edges, floated and redocked, and the arrangement
persists in `layout.xml`. `Editor/lock_pane_layout` disables dragging if you
would rather panes stayed put; it gates only the two places AnchorDocking
starts a drag — a header and a tab — so panes still open, close and resize.
**View ▸ Pane Header Style** picks how the header's drag handle is drawn,
from the six the docking package ships plus led's own plain band; the same
list is on a pane header's right-click menu, beside the docking options it
belongs with. **View ▸ Reset Pane Layout** closes every pane,
redocks the editor and discards that file — the way back from an arrangement
dragging has made unusable, which the docking package offers no other route
out of.

**Tools.** User-defined commands with medit's option, input, output and
environment-variable contract, and named regex output filters including
`make`'s directory stack.

**Shell.** Preferences, a keyboard-shortcut editor, sessions, recent files,
single-instance file hand-off, and the medit command line including
`FILE:LINE`. Files dropped on the window open; a dropped folder points the
file browser at itself.

## Building

Needs FPC 3.2.2+ and Lazarus 2.2+.  `lazbuild` must be on `PATH`.

Lazarus 2.2 is enough because the TextMate grammar engine — which only ships
with Lazarus 3 and later — is vendored under `packages/ledsyn/vendor`, with its
provenance and the two version shims recorded in the README there.

```sh
make                  # the editor, optimized and stripped -> bin/led
make debug            # with symbols and range checks
make WIDGETSET=qt5    # Qt5 instead of gtk2
make help             # every target
```

`make` produces `bin/led`; `make tests` and `make grammars` produce
`bin/ledcoretest` and `bin/langcheck`.  `make check` runs all three suites.

A distribution Lazarus ships LCL and the bundled packages as *source*, so
`lazbuild` has to compile them and needs to be able to write into its own
directory.  If you see `unable to create package output directory
"/usr/lib/lazarus/..."`, grant it once:

```sh
sudo chown -R "$(id -u):$(id -g)" /usr/lib/lazarus
```

If `lazbuild`'s saved configuration points at the wrong Lazarus — a shared
home written by another machine, say — override it:

```sh
make LAZARUSDIR=/usr/lib/lazarus/2.2.0
```

### Installing

```sh
make && make install                       # into ~/.local, no sudo
make && sudo make install PREFIX=/usr/local
make uninstall
```

`install` copies the already-built files and never recompiles, so it is safe
under `sudo`.  led reads its grammars, themes and shipped tools at run time
and finds them relative to its own binary — `<prefix>/share/led` after an
install, `data/` next to `bin/` in a build tree — so `LED_DATA_DIR` is only
needed if you move them apart.

### Packages

| Platform | Artifact | Built by |
|---|---|---|
| Linux | `.deb`, portable `.tar.gz` | `make deb` (`packaging/linux/build-deb.sh`) |
| Windows | Inno Setup `.exe`, portable `.zip` | `packaging/windows/led.iss` |
| macOS | `.dmg` holding `led.app` | `packaging/macos/build-app.sh` |

Each carries `data/` as well as the binary; a package with only the executable
produces an editor that opens every file as plain text.

The Windows installer is unsigned and the macOS bundle is ad-hoc signed, so
both will draw a warning on a machine that did not build them.  Code signing
and notarization are not done.

### Continuous integration

`.github/workflows/ci.yml` builds gtk2, qt5, win32 and cocoa, runs the
headless core suite under the `nogui` widgetset (which is what keeps `ledcore`
free of any visual dependency), regenerates and loads all 128 grammars, runs
the scripted GUI self-test under `xvfb`, and checks the committed icons still
match `tools/make-icon.py`.

The Linux jobs pin `ubuntu-22.04` and install Lazarus from apt, through the
composite action in `.github/actions/lazarus-apt`. Two reasons. It fixes the
Lazarus version at 2.2, which is the only configuration that compiles
`packages/ledsyn/vendor` — on Lazarus 3 and later the TextMate engine comes
from the IDE's own packages and the vendored copy is never built. And it does
not download anything: `gcarreno/setup-lazarus` fetches the Lazarus `.deb`
from SourceForge, which stalls often enough to have failed a required job on a
push whose code was fine, and once held a runner for an hour and a half.

Windows and macOS have no distribution package, so those jobs still use the
action, with a step timeout so a stall fails fast and names itself. One
optional `newest Lazarus` job covers the current release — it is allowed to
fail, because it is the remaining job that depends on that download and a slow
mirror says nothing about led.

`.github/workflows/package.yml` builds the three installers on every push to
`main`, and attaches them to a GitHub Release on a `v*` tag.

### Column selection

Hold **Ctrl** and drag, or use **Ctrl+Shift+arrows** (**Alt+Shift+arrows**
also works, where the window manager does not eat it).  With a rectangle
selected, typing replaces it on every line, Backspace and Delete take a
character from every line, and copy puts the rectangle on the clipboard one
row per line.

Pasting text that was copied as a rectangle puts it back as a rectangle
rather than inserting whole lines.  The system clipboard has no way to say
"this is a column", so led remembers what it last put there; copy anything
else, from any application, and the paste is an ordinary one again.

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
| `recovery/` | unsaved buffers, journalled while led runs; emptied on a clean exit |

Session and recent files are written atomically with one `.bak` generation; a
corrupt session file is ignored rather than allowed to stop startup.

**Crash recovery.** Every few seconds each modified document is written to
`recovery/`, and the entry is dropped as soon as it is saved or closed. A
clean exit empties the directory, so anything still there at the next startup
means the previous run was killed — led says so and offers the work back.
Untitled buffers are covered too, which `session.json` does not do: it stores
paths and caret positions, no text. Turn it off with
`Editor/recovery_enabled`, or change the cadence with
`Editor/recovery_interval`.

Each entry is a `.txt` holding the buffer and a `.json` holding the metadata
and the text's byte length. The text is written first, so the metadata acts as
the commit record: an entry is only offered when the two agree. Being killed
midway through a snapshot therefore loses that snapshot rather than offering a
truncated buffer to save over your file.

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
