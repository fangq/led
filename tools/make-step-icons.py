#!/usr/bin/env python3
"""Draw the debugger's three step icons: data/icons/step{over,into,out}.png.

The set every debugger uses, so they read at a glance: Step Over an arc
leaping over a dot (the line runs, the debugger does not go into it), Step
Into an arrow down into a dot, Step Out an arrow up and away from one.  In
the toolbar's style -- strokes about a sixth of the icon wide with round
ends, filled with a diagonal gradient, top-left to bottom-right -- and each
in the colours it already wore, so a reader used to the toolbar finds them
where they were: Step Over the run controls' blue-violet, Into green, Out
orange.

Step Over had been the same picture as Forward, a triangle to a bar, and
Into and Out a bracket and an arrow that read as other commands.

Drawn four times over and scaled down, which is Pillow's antialiasing; 128
pixels square, as the rest of data/icons is.

Run from the repository root:  python3 tools/make-step-icons.py
Requires Pillow.
"""
import math
import os

from PIL import Image, ImageDraw

SIZE = 128
SS = 4                     # supersampling
W = 21                     # stroke width, at SIZE
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "icons")

# top-left, middle, bottom-right, as the current artwork has them
COLOURS = {
    "stepover": [(153, 159, 255), (50, 96, 254), (75, 15, 255)],
    "stepinto": [(45, 230, 112), (16, 207, 111), (9, 195, 142)],
    "stepout": [(255, 233, 79), (253, 147, 15), (250, 104, 14)],
}


def gradient(stops):
    """A diagonal gradient through three colours, at the supersampled size."""
    n = SIZE * SS
    im = Image.new("RGB", (n, n))
    px = im.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2.0 * (n - 1))
            if t < 0.5:
                a, b, u = stops[0], stops[1], t / 0.5
            else:
                a, b, u = stops[1], stops[2], (t - 0.5) / 0.5
            px[x, y] = tuple(int(round(a[i] + (b[i] - a[i]) * u)) for i in range(3))
    return im


class Pen:
    """Round-capped strokes on a mask, in SIZE coordinates."""

    def __init__(self):
        self.mask = Image.new("L", (SIZE * SS, SIZE * SS), 0)
        self.d = ImageDraw.Draw(self.mask)

    def dot(self, x, y, r):
        s = SS
        self.d.ellipse([(x - r) * s, (y - r) * s, (x + r) * s, (y + r) * s], fill=255)

    def line(self, *pts):
        s = SS
        self.d.line([(x * s, y * s) for x, y in pts], fill=255, width=W * s)
        for x, y in pts:
            self.dot(x, y, W / 2.0)

    def arc(self, cx, cy, r, a0, a1, steps=64):
        pts = []
        for k in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * k / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        self.line(*pts)
        return pts


def chevron(pen, tip, direction, arm=28, spread=44):
    """An arrowhead at tip pointing along direction (a unit vector)."""
    dx, dy = direction
    back = math.atan2(-dy, -dx)
    pts = []
    for s in (+1, -1):
        a = back + s * math.radians(spread)
        pts.append((tip[0] + arm * math.cos(a), tip[1] + arm * math.sin(a)))
    pen.line(pts[0], tip, pts[1])


def stepinto():
    p = Pen()
    p.line((64, 12), (64, 70))
    chevron(p, (64, 72), (0, 1))
    p.dot(64, 103, 15)
    return p.mask


def stepout():
    p = Pen()
    p.dot(64, 103, 15)
    p.line((64, 76), (64, 18))
    chevron(p, (64, 16), (0, -1))
    return p.mask


def stepover():
    p = Pen()
    # over the top of a circle, from the left round to the right, coming
    # down on the far side; the dot it leaps over below
    cx, cy, r = 64, 70, 42
    a0, a1 = 195, 340
    p.arc(cx, cy, r, a0, a1)
    t = math.radians(a1)
    end = (cx + r * math.cos(t), cy + r * math.sin(t))
    tangent = (-math.sin(t), math.cos(t))
    chevron(p, (end[0] + 2 * tangent[0], end[1] + 2 * tangent[1]), tangent)
    p.dot(64, 105, 14)
    return p.mask


def main():
    for name, draw in (("stepover", stepover), ("stepinto", stepinto), ("stepout", stepout)):
        mask = draw()
        im = gradient(COLOURS[name]).convert("RGBA")
        im.putalpha(mask)
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
        path = os.path.join(OUT, name + ".png")
        im.save(path)
        print("wrote", os.path.normpath(path))


if __name__ == "__main__":
    main()
