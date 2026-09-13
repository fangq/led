# led — a lightweight programmer's text editor

<p align="center">
  <img src="packaging/icons/led.svg" width="120" alt="led">
</p>

[![CI](https://github.com/fangq/led/actions/workflows/ci.yml/badge.svg)](https://github.com/fangq/led/actions/workflows/ci.yml)
[![License: GPL v3+](https://img.shields.io/badge/License-GPLv3--or--later-blue.svg)](#license)

- **Copyright**: (C) Qianqian Fang (2026) \<q.fang at neu.edu>
- **License**: GNU General Public License, version 3 or later
- **Version**: 0.5.0-dev
- **GitHub**: <https://github.com/fangq/led>

**A fast, no-nonsense editor for code and text.** `led` opens instantly, brings
its own syntax highlighting for 128 languages, and puts a file browser, a real
terminal, a symbol list, a Markdown preview and a C/C++ debugger in the same
window — without a plugin marketplace, an account, or a background updater.

One native binary per platform. Nothing to configure before you can use it.

> **Who it's for:** anyone who wants a small, quick editor that still has the
> things a working programmer reaches for — split views, column selection, find
> in files, a terminal, breakpoints. If you have used **medit**, **gedit**,
> **Kate** or **Notepad++**, led will feel familiar.

---

## Contents

- [Highlights](#highlights)
- [Features](#features)
  - [Editing](#editing)
  - [Languages, themes and fonts](#languages-themes-and-fonts)
  - [Finding things](#finding-things)
  - [Panes and window layout](#panes-and-window-layout)
  - [Terminal](#terminal)
  - [Markdown and wiki preview](#markdown-and-wiki-preview)
  - [Binary files](#binary-files)
  - [Debugging C and C++](#debugging-c-and-c)
  - [Tools](#tools)
  - [Sessions and crash recovery](#sessions-and-crash-recovery)
- [Installation](#installation)
  - [Download a package](#download-a-package)
  - [Unsigned installers](#unsigned-installers)
  - [Build from source](#build-from-source)
- [Getting started](#getting-started)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [For developers](#for-developers)
- [License](#license)
- [Credits and links](#credits-and-links)

---

## Highlights

- **Starts fast and stays fast.** A 5 MB single-line file opens in under a
  tenth of a second.
- **128 languages out of the box** — no downloads, no language servers.
- **Split views and split tab groups** — the same file twice, or two files
  side by side, in one window.
- **Column (box) selection** with copy, paste and typing across the rectangle.
- **A real terminal** in a pane, splittable, following the current file's
  folder.
- **Step-by-step C/C++ debugging** with gdb — breakpoints, watchpoints,
  hover-to-inspect, `launch.json` projects.
- **Binaries open as a hex dump** instead of as garbage you might save back.
- **Live Markdown and wiki preview**, scroll-synced with the text.
- **Crash recovery** — unsaved work is journalled continuously, including
  never-saved buffers.
- **Brings its own font** (Fira Code) so it looks the same on every machine.

---

## Features

### Editing

- **Tabs and split views** over one shared buffer — edit in either half, both
  update. Split *side by side* or *stacked*.
- **Two independent tab groups** per window (*Split Notebook*), so you can keep
  two files visible and still flip through tabs on each side.
- **Column (box) selection** — hold `Ctrl` and drag, or `Ctrl+Shift+arrows`.
  Typing replaces the rectangle on every line, Backspace and Delete take a
  character from each, and copy puts it on the clipboard one row per line.
  Pasting a rectangle puts it back as a rectangle.
- **Code folding** with margin glyphs, plus *Fold All* / *Unfold All*.
- **Comment and uncomment** using the language's own markers.
- **Block indent** and one-space `Ctrl+0` / `Ctrl+9` shifts.
- **Bookmarks** across documents, with a bookmark manager.
- **Matching-bracket** jump and select-to-bracket.
- **Word completion** from the current document.
- **`Ctrl+wheel` zoom**, per window, without touching your preferences.
- **Very long lines** stay responsive: past 4096 characters a line is drawn up
  to a red `...` marker; click it to reveal 4096 more. Display only — the text
  itself is never altered, so copy, search and save always see the whole line.
- **Encoding detection** with BOM handling and mixed line endings, *Reopen with
  Encoding*, and external-change detection with reload.
- **Spell checking** as you type, with suggestions on right-click and a
  personal dictionary. The `en_US` word list ships with led.
- **Print**, **Export as PDF** and **Export as HTML**.

### Languages, themes and fonts

- **128 syntax highlighting grammars**, covering everything from C, C++, Rust,
  Go, Python, JavaScript and Java to LaTeX, Makefiles, INI, Diff and SQL.
  Language is picked from the filename, the MIME type or a `#!` line, and can
  be set by hand per document.
- **8 colour themes** — `classic`, `cobalt`, `kate`, `medit`, `oblivion`,
  `solarized-dark`, `solarized-light`, `tango` — switchable from
  **View ▸ Colour Theme**.
- **Fira Code is bundled** and is the default, so a fresh install looks
  identical on Linux, Windows and macOS. Nothing is installed on your system —
  led registers the font for its own process only. Pick any other monospace
  family in **Preferences ▸ View ▸ Editor font**.

### Finding things

- **Find and replace** with regular expressions, whole-word and
  case-sensitivity options.
- **Incremental find bar** (`Ctrl+Shift+F`) that searches as you type.
- **Find word at cursor** (`Ctrl+F3`), forwards or backwards.
- **Find in Files** (`Ctrl+Shift+G`) — a grep across a folder tree with glob
  filters and regex, results in a pane, one click to the line.
- **Go to line** (`Ctrl+G`), and `led file.c:120` from the command line.
- **Symbol browser** — functions, classes and variables in the current file,
  click to jump. Needs `ctags` installed; the pane simply stays empty without
  it.

### Panes and window layout

led has a **File Browser** (with a clickable breadcrumb path bar), **Project
Files**, **Symbols**, **Output**, **Terminal**, **Preview**, **Debugger** and
**Breakpoints** panes.

- Every window edge carries a **strip of buttons**, one per pane docked there,
  so a pane you closed comes back with one click.
- Panes can be **dragged between edges, floated and re-docked**, and the
  arrangement is remembered between runs.
- **View ▸ Reset Pane Layout** puts everything back if a drag leaves the window
  in a state you cannot undo.
- Opening a pane that will not fit **grows the window** rather than squeezing
  the editor down to nothing.
- Prefer panes to stay put? Set `Editor/lock_pane_layout` — it stops dragging
  without stopping panes opening, closing or resizing.

### Terminal

A real terminal in a pane — not a log window. It follows the current file's
directory, can be **split side by side or stacked** to run several shells, and
the active half is marked with a coloured band across its top so you can see
where your keystrokes are going. Works on Linux, macOS and Windows (via
ConPTY).

### Markdown and wiki preview

**View ▸ Markdown Preview** renders the document beside it, and the two are
tied together:

- **Scroll the text and the preview follows.**
- **Click the preview and the caret moves** to the line that block came from.
- Code blocks are wrapped to the width of the pane rather than forcing the
  whole page wider than the window.
- Relative image paths resolve against the document's own folder.

Wiki files — `.wiki`, `.wp`, `.usemod`, or any file starting with
`<!-- wiki -->` — render through the same pane using medit's UseMod/Habitat
dialect: `= Heading =`, numbered headings with `<toc>`, `*`/`#` lists,
`; term : definition`, `||tables||`, `'''bold'''`, `[[FreeLinks]]`,
`[url label]`, bare URLs, `WikiWord`, `[#anchors]` and `<nowiki>`.

### Binary files

Open an ELF, a PNG or a `.zip` in most editors and you get line noise — and if
you press Save, the file is quietly corrupted, because the editor rewrote its
line endings.

led shows a file that is not text as a **hex dump** instead, in the layout
`hexedit` and `xxd` use:

```
00000000  7f 45 4c 46 02 01 01 00  00 00 00 00 00 00 00 00  |.ELF............|
```

The three columns are coloured so the text half stands out, and the dump is
**editable**: type hex digits on the left or characters on the right to change
a byte, `Ctrl+Z` to undo, `Ctrl+S` to write the bytes back — and only the bytes
you changed are different. Editing is overwrite-only, so offsets never shift.

If led guesses wrong, **File ▸ Open as Text** overrules it for that one
opening.

### Debugging C and C++

led drives `gdb` as a subprocess, so all you need is `gdb` on your `PATH`.

| Shortcut | Action |
|---|---|
| `F7` | Build the project |
| `Ctrl+F5` | Start debugging, or continue |
| `F9`, or click the line number | Toggle a breakpoint |
| `Ctrl+Shift+F9` | Give a breakpoint a condition |
| `Ctrl+Shift+F10` | Watch an expression |
| `Ctrl+F10` | Run to the caret's line |
| `F10` / `F11` / `Shift+F11` | Step over / into / out |
| `Ctrl+F6` | Pause |
| `Shift+F5` | Stop |

- **Conditional breakpoints** stop only where an expression is true (`i == 7`),
  and are drawn as a hollow octagon so one that may not stop cannot be mistaken
  for one that always will.
- **Watchpoints** stop the program when a value *changes*, wherever that
  happens — what you want when something is being overwritten and you do not
  know by what. Read and access watchpoints are available too, and the Output
  pane reports what the value was and what it became.
- The **Breakpoints pane** lists every breakpoint and watchpoint with its
  condition and hit count. Double-click to go to its line, `Delete` to forget
  one, `Space` to switch it off without forgetting it (it stays in the gutter
  as a grey octagon).
- The **Debugger pane** shows locals, the call stack and watched expressions.
  Structs, arrays and pointers **open** in Locals, fetching each level only
  when you look at it.
- **Hover over an expression** in the source to see its value — `box.tl.y`,
  `p->next->value` and `arr[2].x` are read as written, not just the word under
  the pointer. Structs are shown one field to a line.
- gdb's output, your program's output and any build all go to the **Output**
  pane, where `file:line` is clickable. There is a box for raw gdb commands.

**Projects.** A folder containing `.led/launch.json` (or `.vscode/launch.json`)
is a project; led walks up from the file you are editing to find it. The format
is VS Code's:

```jsonc
{
  "configurations": [
    { // comments and trailing commas are fine
      "name": "Debug",
      "program": "${workspaceFolder}/myprog",
      "args": ["--verbose"],
      "preLaunchTask": "build",
    },
  ]
}
```

`${workspaceFolder}`, `${file}`, `${fileBasename}`,
`${fileBasenameNoExtension}`, `${fileDirname}` and `${env:VAR}` are all
substituted. `preLaunchTask` names a label in `tasks.json`, or a configuration
can carry a `build` command directly. Starting a session rebuilds first if the
binary is older than your sources, and does not launch if that build fails.

Without a project, led debugs the open file's name minus its extension —
`foo.c` → `foo`, which is what `gcc -g foo.c -o foo` gives you.

### Tools

Run external commands on the current file or selection and get the result back
in the editor, in the Output pane, or as a replacement for what you selected.
led ships 15 ready to use, including **Sort Lines**, **Sort | Uniq**, **Diff to
Disk**, **Insert Date**, **Switch Header/Source**, **Make**, **LaTeX**,
**pdflatex** and **BibTeX**.

Output filters turn a compiler's `file:line: error` into a clickable link —
including `make`'s directory stack, so errors from a recursive build still name
the right file. Add your own under **Edit ▸ Preferences ▸ Tools**.

### Sessions and crash recovery

- **Sessions** restore your open files, carets and pane layout.
- **Recent files**, and a **Project Files** pane for a curated list.
- **Single instance** — opening a file from your file manager or a shell reuses
  the running window instead of starting a second copy.
- **Crash recovery.** Every few seconds each modified document is written to a
  journal, and dropped as soon as you save or close it. A clean exit empties
  the journal — so anything left at startup means the last run was killed, and
  led offers the work back. **Untitled buffers are covered too**, which a
  session file cannot do.
- **Drag and drop** files onto the window to open them; drop a folder and the
  file browser points at it.

---

## Installation

### Download a package

Grab the installer for your system from the
**[Releases](../../releases)** page (or, between releases, from the artifacts of
the latest **Package** workflow run under the Actions tab):

| OS | Package | How to install |
|----|---------|----------------|
| **Linux** | `.deb` | `sudo apt install ./led_*.deb` — adds the binary, a menu entry and icons |
| **Linux** | `.tar.gz` | Portable; unpack anywhere and run `bin/led` |
| **Windows** | Setup `.exe` | Inno Setup installer, per-user or system-wide |
| **Windows** | `.zip` | Portable; unpack and run `led.exe` |
| **macOS** | `.dmg` | Drag **led** to *Applications* |

Every package carries led's `data/` directory — grammars, themes, tools, the
dictionary and the bundled font. A copy with only the executable would open
every file as plain, unhighlighted text.

**Optional extras**, picked up automatically if present:

| Program | Enables |
|---|---|
| `gdb` | The C/C++ debugger |
| `ctags` (universal or exuberant) | The symbol browser |

### Unsigned installers

The Windows installer is **not code-signed** and the macOS bundle is only
ad-hoc signed, so both will warn on a machine that did not build them.

- **Windows** — SmartScreen shows *"Windows protected your PC"*. Click **More
  info → Run anyway**. If you downloaded a `.zip`, right-click it →
  **Properties** → tick **Unblock** *before* extracting.
- **macOS** — the first launch needs **right-click → Open** rather than a
  double-click.

Code signing and notarization are not done yet.

### Build from source

You need **FPC 3.2.2+** and **Lazarus 2.2+**, with `lazbuild` on your `PATH`.

```sh
git clone https://github.com/fangq/led
cd led
make                  # optimized and stripped -> bin/led
make run              # build and launch
make debug            # with symbols and range checks
make WIDGETSET=qt5    # Qt5 instead of gtk2 on Linux
make help             # every target
```

Install it:

```sh
make && make install                        # into ~/.local, no sudo
make && sudo make install PREFIX=/usr/local
make uninstall
```

`make install` copies what is already built and never recompiles, so it is safe
under `sudo`. led finds its data relative to its own binary —
`<prefix>/share/led` after an install, `data/` beside `bin/` in a build tree —
so you only need `$LED_DATA_DIR` if you move the two apart.

Build a package for your platform:

```sh
make deb              # .deb and portable .tar.gz
```

Windows and macOS packages are built by `packaging/windows/led.iss` and
`packaging/macos/build-app.sh`.

---

## Getting started

1. **Open something.** `led file.c`, or `led file.c:120` to land on a line.
   Drag files onto the window, or use the File Browser pane.
2. **Pick a look.** **View ▸ Colour Theme** for the scheme,
   **Preferences ▸ View ▸ Editor font** if you would rather not use Fira Code.
3. **Open the panes you want.** The **View** menu lists them all; the buttons
   down each window edge toggle the ones docked there. Your arrangement is
   remembered.
4. **Set your keys.** **Edit ▸ Configure Shortcuts** remaps any command; only
   what you change is saved.
5. **To debug a C or C++ program**, open a source file, press `F9` on a line to
   set a breakpoint, and `Ctrl+F5` to start. Add a `.led/launch.json` when you
   want arguments, a working directory or a build step.

---

## Keyboard shortcuts

All of these are remappable in **Edit ▸ Configure Shortcuts**.

### Files

| Shortcut | Action |
|----------|--------|
| `Ctrl+N` | New |
| `Ctrl+Shift+N` | New window |
| `Ctrl+O` | Open |
| `Ctrl+S` | Save |
| `Ctrl+Shift+S` | Save As |
| `F5` | Reload from disk |
| `Ctrl+W` | Close tab |
| `Ctrl+P` | Print |
| `Ctrl+Q` | Quit |

### Editing

| Shortcut | Action |
|----------|--------|
| `Ctrl+Z` / `Ctrl+Shift+Z` | Undo / Redo |
| `Ctrl+X` / `Ctrl+C` / `Ctrl+V` | Cut / Copy / Paste |
| `Ctrl+Shift+V` | Paste as column |
| `Ctrl+A` | Select all |
| `Ctrl+/` / `Ctrl+Shift+/` | Comment / Uncomment |
| `Ctrl+0` / `Ctrl+9` | Indent / unindent by one space |
| `Ctrl+Drag` | Column (box) selection |
| `Ctrl+Shift+arrows` | Column selection from the keyboard |
| `Ctrl+wheel` | Zoom in and out |

### Searching and navigating

| Shortcut | Action |
|----------|--------|
| `Ctrl+F` / `Ctrl+R` | Find / Replace |
| `F3` / `Shift+F3` | Find next / previous |
| `Ctrl+Shift+F` | Incremental find bar |
| `Ctrl+F3` / `Ctrl+Shift+F3` | Find word at cursor, forwards / backwards |
| `Ctrl+Shift+G` | Find in files |
| `Ctrl+G` | Go to line |
| `Ctrl+]` / `Ctrl+Shift+]` | Go to / select to matching bracket |
| `Ctrl+B` | Toggle bookmark |
| `Alt+Down` / `Alt+Up` | Next / previous bookmark |
| `Ctrl+PageDown` / `Ctrl+PageUp` | Next / previous tab |

### View

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+[` | Toggle fold |
| `F6` | Cycle split views |
| `Alt+End` | Focus the document |
| `F1` | Help |

### Debugging

See [Debugging C and C++](#debugging-c-and-c) for the full table — `F9`
breakpoint, `Ctrl+F5` start, `F10`/`F11` step, `F7` build.

---

## Configuration

Settings live in a folder you do not normally need to open:

| OS | Location |
|----|----------|
| Linux | `~/.config/led/` |
| macOS | `~/Library/Application Support/led/` |
| Windows | `%APPDATA%\led\` |

Override it with `$LED_CONFIG_DIR`.

| File | Holds |
|------|-------|
| `prefs.ini` | Everything in the Preferences dialog |
| `keys.ini` | Only the shortcuts you changed |
| `session.json` | Windows, tabs, carets and pane layout |
| `recent.json` | The Open Recent list |
| `layout.xml` | Where the panes are docked |
| `tools/*.ini` | One file per tool you define |
| `recovery/` | Unsaved work, journalled while led runs |
| `user-dictionary.txt` | Words you told the spell checker to accept |

A few preferences worth knowing, set in `prefs.ini` or the Preferences dialog:

| Key | Meaning |
|-----|---------|
| `Editor/font` | Editor font (Preferences ▸ View); unset means the bundled Fira Code |
| `Editor/max_line_len` | Where long lines are truncated for drawing (4096; `0` disables) |
| `Editor/show_pane_buttons` | The button strips down each window edge |
| `Editor/lock_pane_layout` | Stop panes being dragged around |
| `Editor/recovery_enabled` | Crash-recovery journalling |
| `Editor/recovery_interval` | How often it snapshots |

A `langs/` or `themes/` folder in your config directory overrides the shipped
ones, so you can add a language or a colour scheme without touching the
installation.

---

## Troubleshooting

**Chinese, Japanese or Korean text sits lower than the Latin text beside it.**
Your editor font has no CJK glyphs, so the toolkit substitutes one whose
letters sit differently. Choose a font that covers what you read —
`Noto Sans Mono CJK SC`, `Noto Sans Mono CJK JP`, `WenQuanYi Micro Hei Mono` or
`Sarasa Mono` — in **Preferences ▸ View ▸ Editor font**.

**led exits over `ssh -X` with a `BadAccess` error.** It no longer does — led
recognises this one and carries on. For the curious: ssh forwards the X
server's extension list unchanged, so shared-memory drawing is advertised even
though the server is on your machine and led is on the other one. Drawing falls
back to the ordinary path, which is slightly slower over the wire and otherwise
identical.

**Everything is tiny on a high-DPI screen.** led follows your desktop's scaling
including the window-scaling factor, which the underlying toolkit ignores on
its own. If something still looks wrong, please report it with your `Xft.dpi`
and scaling factor.

**A binary file opened as a hex dump and I wanted the text.** *File ▸ Open as
Text*. It applies to that one opening, so a genuine binary comes back as a dump
next time.

**The symbol pane is empty.** Install `ctags` (`universal-ctags` on most
distributions) and reopen the file.

**Building: `unable to create package output directory "/usr/lib/lazarus/..."`.**
A distribution Lazarus ships its packages as source, so `lazbuild` needs to
write into its own directory. Grant it once:

```sh
sudo chown -R "$(id -u):$(id -g)" /usr/lib/lazarus
```

**Building: `lazbuild` picks the wrong Lazarus** (a shared home written by
another machine, say):

```sh
make LAZARUSDIR=/usr/lib/lazarus/2.2.0
```

---

## For developers

led is written in Free Pascal with Lazarus/LCL — one source tree builds
natively on Linux, Windows and macOS.

```
app/                  the program
packages/ledcore/     no visual dependency — file I/O, config, tools, grep, hex
packages/ledsyn/      themes, language registry, highlighter factory
packages/ledui/       forms, documents, views, docking, panes
packages/ledterm/     pty, VT parser, terminal widget
data/                 grammars, themes, tools, dictionary, fonts
tools/                lang2tm.py, gen-parity.py, langcheck
test/                 headless fpcunit suites
```

`ledcore` is built in CI with the `nogui` widgetset, which is what keeps the
interesting logic out of the GUI layer and testable without a display.

```sh
make tests            # headless core suite
make grammars         # regenerate and load all 128 grammars
make selftest         # scripted GUI check (needs a display)
make check            # all of the above
```

CI builds gtk2, qt5, win32 and cocoa on every push, runs the headless suite,
loads every grammar, runs the GUI self-test under `xvfb`, verifies the bundled
fonts against their upstream checksums, and checks the committed icons still
match their generator.

**Parity with medit.** led is a feature-comparable successor to
[medit](https://github.com/fangq/medit). [`PARITY.md`](PARITY.md) tracks every
medit action, preference key, shipped tool and behavioural feature, recording
what is done, what an LCL facility replaces, and what is deliberately not
carried over.

---

## License

led is free software: you can redistribute it and/or modify it under the terms
of the **GNU General Public License, version 3 or later**, as
published by the Free Software Foundation.

led is distributed in the hope that it will be useful, but **WITHOUT ANY
WARRANTY**; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE. See <https://www.gnu.org/licenses/gpl-3.0.html> for the
full text.

The bundled **Fira Code** font is distributed under the SIL Open Font License
1.1; see [`data/fonts/OFL.txt`](data/fonts/OFL.txt). The bundled `en_US` word
list carries its own notice in [`data/dict/`](data/dict/).

---

## Credits and links

- **Qianqian Fang** — author, with assistance from the AI coding assistant
  [Claude](https://claude.ai) (Anthropic).
- **Yevgen Muntyan** — original author of [medit](http://mooedit.sourceforge.net/)
  (2004–2010), whose design and feature set led follows.
- Source code and bug reports: <https://github.com/fangq/led>
