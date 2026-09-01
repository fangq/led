#!/usr/bin/env python3
"""Check that packaging/icons is still what tools/make-icon.py produces.

The icons are committed so a fresh clone builds without Pillow, which means
they can silently drift from the generator that is supposed to define them.

Byte comparison is the obvious check and the wrong one: a different Pillow
version re-encodes the same image differently, and a red build nobody can act
on is worse than no check.  So the SVG (text, deterministic) is compared
exactly, and the rasters are compared by pixel content.

  python3 tools/check-icons.py <reference-dir>

where <reference-dir> is a copy of packaging/icons taken before regenerating.
"""

import pathlib
import sys

from PIL import Image


def pixels(path):
    """The raw RGBA bytes.  tobytes() rather than getdata(), which Pillow 14
    removes."""
    with Image.open(path) as im:
        return im.convert("RGBA").tobytes()


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2

    before = pathlib.Path(sys.argv[1])
    after = pathlib.Path(__file__).resolve().parent.parent / "packaging" / "icons"
    bad = []

    if (before / "led.svg").read_text() != (after / "led.svg").read_text():
        bad.append("led.svg differs")

    for p in sorted(after.rglob("*.png")):
        q = before / p.relative_to(after)
        if not q.exists():
            bad.append("%s is not committed" % p)
        elif pixels(p) != pixels(q):
            bad.append("%s differs in pixels" % p)

    for name in ("led.ico", "led.icns"):
        a, b = after / name, before / name
        if not b.exists():
            bad.append("%s is not committed" % name)
        elif a.stat().st_size == 0:
            bad.append("%s is empty" % name)

    with Image.open(after / "led.ico") as ia, Image.open(before / "led.ico") as ib:
        if sorted(ia.ico.sizes()) != sorted(ib.ico.sizes()):
            bad.append("led.ico holds different sizes")

    if bad:
        print("packaging/icons is out of date; run 'make icon' and commit.")
        print("\n".join("  " + b for b in bad))
        return 1

    print("icons match their generator")
    return 0


if __name__ == "__main__":
    sys.exit(main())
