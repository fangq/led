# Vendored: bjdata.pas

`bjdata.pas` is the Object Pascal reader and writer for [Binary
JData](https://github.com/NeuroJSON/bjdata), the binary JSON format the
NeuroJSON scientific formats are built on -- `.bnii`, `.bmsh`, `.bnirs`,
`.bjd`, `.jdb`.  led uses it to show those files as a structure rather than as
a hex dump.

| | |
|---|---|
| Upstream | `git@github.com:fangq/bjdpas.git` |
| Commit | `0a4fa67d955b0007ab1be4e75e8298106f2abcdb`, 2026-09-13, *flatten the tree, the repository is the library* |
| Version | 0.5.0 |
| Licence | Apache-2.0, Copyright (c) 2026 Qianqian Fang |

## Why it is vendored

The same reason `ledsyn/vendor` exists: one source tree that builds from a
clean clone with nothing to install.  The library is a single unit depending
only on `Classes, SysUtils, Math`, so vendoring costs one file and adds no
package, no submodule and no build step.

**It is on `ledcore`'s unit path, so it must stay free of the LCL** -- and it
is: the RTL is its whole dependency surface.  The `headless core tests (nogui)`
CI job builds `test/ledcoretest.lpi` with `--widgetset=nogui` and would fail
immediately otherwise.

Nothing else from the upstream repository is here.  `test/`, `tools/`,
`examples/`, the Makefile and the `.lpk` are all useful and none of them
belong in led; the `.lpk` in particular must not be registered as a Lazarus
package named `bjdata`, because Lazarus generates and overwrites
`<packagename>.pas` and would destroy the unit.

## Local patches

Each is tagged `*** led local patch ***` in the source, so a re-sync can find
them with `grep -n "led local patch" bjdata.pas`.

### A ceiling on nesting depth (`BJMaxDepth`, `TBJReader.PushPending`)

Upstream recurses once per container with no limit.  A file of 200,000 `[`
bytes takes the process down:

```
$ bjd2json deep.bjd        # upstream
Segmentation fault (core dumped)     -- exit 139

$ bjd2json deep.bjd        # patched
bjd2json: nesting deeper than 512 levels at byte offset 513   -- exit 2
```

An editor opens files it did not write, so a corrupt one has to be a message
rather than a crash.  `FPendingCount` was already incremented once per
container under construction, so it is the depth, and `PushPending` is the one
place every container path passes through -- the patch is two lines and one
constant.  512 is far above anything real: the deepest document in the
NeuroJSON corpus tested here nests 7 levels.

## What was tried and deliberately *not* kept

**Leniency for containers that carry both a count and a terminator.**  A
container declaring `#` has no end marker -- the spec is explicit, and three
independent parsers (this one, and the reference Perl and Python viewers in
the bjdata repository) all reject a file that has both.  Several `.jdb` files
do have both, so a patch was written to step over the stray byte.

It was reverted, because the evidence did not support it.  Measured across the
NeuroJSON sample files on hand: the patch rescued **zero** valid files.  Every
file it helped was malformed in further ways and still failed a few hundred
bytes later -- unterminated arrays, a count written as a signed `I` that comes
out negative, truncated payloads.  Those files are corrupt downloads, not a
dialect.  Being lenient would have bought nothing and taught the reader to
accept malformed data silently.

Of 40 genuine sample files, **39 parse unmodified**; the one failure is a
2,971-byte `.bnii` whose `_ArrayZipData_` declares a 64,520-byte payload, i.e.
a truncated download.

## Re-syncing

```sh
cd /path/to/bjdpas && git pull
cp bjdata.pas /path/to/led/packages/ledcore/vendor/
cd /path/to/led && grep -n "led local patch" packages/ledcore/vendor/bjdata.pas
# reapply anything the diff dropped, then:
make tests            # Led.Core.Tests.BJData is the gate
```

`make tests` passing is what says the re-sync worked, the way
`bin/langcheck data/grammars` is for the ledsyn vendor.
