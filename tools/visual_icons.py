#!/usr/bin/env python3
"""The visual editor's toolbar icons, drawn in the style of LED's painted set
(data/icons): thick rounded strokes in a cyan-to-violet gradient over a pale
translucent fill, details as rounded bars, 128x128 RGBA.

    python3 tools/visual_icons.py [outdir]      # data/icons by default
    python3 tools/visual_icons.py --sheet sheet.png

Each icon is a short function below; the names are the ones the visual editor
asks Led.UI.Icons for (and its ArtworkNames lists).
"""

import math
import os
import sys

import cairo

S = 128.0
W = 11.0  # the main stroke


# ---------- palette and primitives ----------

BLUE = [(0.0, (0.02, 0.74, 1.0)), (0.55, (0.30, 0.40, 1.0)), (1.0, (0.70, 0.22, 0.96))]
GREEN = [(0.0, (0.10, 0.86, 0.45)), (1.0, (0.0, 0.62, 0.86))]
RED = [(0.0, (1.0, 0.36, 0.42)), (1.0, (0.88, 0.12, 0.42))]
ORANGE = [(0.0, (1.0, 0.72, 0.10)), (1.0, (1.0, 0.40, 0.25))]
YELLOW = (1.0, 0.86, 0.12)


def grad(stops=BLUE, x0=8, y0=8, x1=120, y1=120, alpha=1.0):
    g = cairo.LinearGradient(x0, y0, x1, y1)
    for o, (r, gg, b) in stops:
        g.add_color_stop_rgba(o, r, gg, b, alpha)
    return g


def rrect(c, x, y, w, h, r):
    c.new_sub_path()
    c.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    c.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    c.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    c.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    c.close_path()


def pale(c, stops=BLUE):
    """the translucent body inside an outline: white, tinted by the gradient"""
    c.set_source_rgba(1, 1, 1, 0.82)
    c.fill_preserve()
    c.set_source(grad(stops, alpha=0.22))
    c.fill_preserve()


def stroke(c, stops=BLUE, width=W):
    c.set_source(grad(stops))
    c.set_line_width(width)
    c.set_line_cap(cairo.LINE_CAP_ROUND)
    c.set_line_join(cairo.LINE_JOIN_ROUND)
    c.stroke()


def bar(c, x0, y0, x1, y1, stops=BLUE, width=W):
    c.move_to(x0, y0)
    c.line_to(x1, y1)
    stroke(c, stops, width)


def body(c, x, y, w, h, r=16, stops=BLUE):
    rrect(c, x, y, w, h, r)
    pale(c, stops)
    stroke(c, stops)


def page(c, x=26, y=12, w=76, h=104, stops=BLUE):
    """a sheet with a folded corner"""
    f = 22
    c.move_to(x + 10, y)
    c.line_to(x + w - f, y)
    c.line_to(x + w, y + f)
    c.line_to(x + w, y + h - 10)
    c.arc(x + w - 10, y + h - 10, 10, 0, math.pi / 2)
    c.line_to(x + 10, y + h)
    c.arc(x + 10, y + h - 10, 10, math.pi / 2, math.pi)
    c.line_to(x, y + 10)
    c.arc(x + 10, y + 10, 10, math.pi, 3 * math.pi / 2)
    c.close_path()
    pale(c, stops)
    stroke(c, stops)
    c.move_to(x + w - f, y + 2)
    c.line_to(x + w - f, y + f)
    c.line_to(x + w - 2, y + f)
    stroke(c, stops, W * 0.8)


def text(c, s, x, y, size, face="DejaVu Sans", bold=True, italic=False, stops=BLUE, center=True):
    c.select_font_face(face, cairo.FONT_SLANT_ITALIC if italic else cairo.FONT_SLANT_NORMAL,
                       cairo.FONT_WEIGHT_BOLD if bold else cairo.FONT_WEIGHT_NORMAL)
    c.set_font_size(size)
    e = c.text_extents(s)
    if center:
        x -= e.x_bearing + e.width / 2
        y -= e.y_bearing + e.height / 2
    c.move_to(x, y)
    c.text_path(s)
    c.set_source(grad(stops))
    c.fill()
    return e


def dot(c, x, y, r, stops=BLUE):
    c.arc(x, y, r, 0, 2 * math.pi)
    c.set_source(grad(stops))
    c.fill()


def solid(c, rgb):
    c.set_source_rgb(*rgb)


def arrow(c, x0, y0, x1, y1, stops=BLUE, width=W, head=16):
    bar(c, x0, y0, x1, y1, stops, width)
    a = math.atan2(y1 - y0, x1 - x0)
    for s in (-1, 1):
        c.move_to(x1, y1)
        c.line_to(x1 - head * math.cos(a + s * 0.6), y1 - head * math.sin(a + s * 0.6))
        stroke(c, stops, width)


def badge(c, kind, x=96, y=96, r=24):
    """a round badge in the corner: plus, minus, cross, check"""
    stops = {"plus": GREEN, "check": GREEN, "minus": RED, "cross": RED}[kind]
    c.arc(x, y, r, 0, 2 * math.pi)
    c.set_source(grad(stops, x - r, y - r, x + r, y + r))
    c.fill()
    c.set_source_rgb(1, 1, 1)
    c.set_line_width(8)
    c.set_line_cap(cairo.LINE_CAP_ROUND)
    c.set_line_join(cairo.LINE_JOIN_ROUND)
    k = r * 0.5
    if kind in ("plus", "minus"):
        c.move_to(x - k, y)
        c.line_to(x + k, y)
        if kind == "plus":
            c.move_to(x, y - k)
            c.line_to(x, y + k)
    elif kind == "cross":
        c.move_to(x - k, y - k)
        c.line_to(x + k, y + k)
        c.move_to(x + k, y - k)
        c.line_to(x - k, y + k)
    else:
        c.move_to(x - k, y)
        c.line_to(x - k * 0.2, y + k * 0.7)
        c.line_to(x + k, y - k * 0.6)
    c.stroke()


def grid(c, x, y, w, h, rows, cols, header=False, stops=BLUE, fill_cells=()):
    rrect(c, x, y, w, h, 12)
    pale(c, stops)
    c.new_path()
    for (r, k) in fill_cells:
        cx, cy = x + w * k / cols, y + h * r / rows
        c.rectangle(cx + 4, cy + 4, w / cols - 8, h / rows - 8)
        c.set_source(grad(stops, alpha=0.55))
        c.fill()
    if header:
        rrect(c, x, y, w, h / rows, 12)
        c.set_source(grad(stops, alpha=0.6))
        c.fill()
    rrect(c, x, y, w, h, 12)
    stroke(c, stops)
    for r in range(1, rows):
        bar(c, x, y + h * r / rows, x + w, y + h * r / rows, stops, W * 0.75)
    for k in range(1, cols):
        bar(c, x + w * k / cols, y, x + w * k / cols, y + h, stops, W * 0.75)


def lines(c, x0, ys, lens, stops=BLUE, width=W):
    for y, l in zip(ys, lens):
        bar(c, x0, y, x0 + l, y, stops, width)


# ---------- the icons ----------

ICONS = {}


def icon(name):
    def reg(f):
        ICONS[name] = f
        return f
    return reg


@icon("alignleft")
def _(c):
    lines(c, 18, [28, 50, 72, 94], [92, 60, 92, 52])


@icon("aligncenter")
def _(c):
    for y, l in zip([28, 50, 72, 94], [92, 56, 92, 44]):
        bar(c, 64 - l / 2, y, 64 + l / 2, y)


@icon("alignright")
def _(c):
    for y, l in zip([28, 50, 72, 94], [92, 60, 92, 52]):
        bar(c, 110 - l, y, 110, y)


@icon("alignjustify")
def _(c):
    lines(c, 18, [28, 50, 72, 94], [92, 92, 92, 92])


@icon("bullets")
def _(c):
    for y in (30, 64, 98):
        dot(c, 24, y, 10)
        bar(c, 48, y, 110, y)


@icon("numbering")
def _(c):
    for i, y in enumerate((30, 64, 98)):
        text(c, str(i + 1), 24, y, 30)
        bar(c, 48, y, 110, y)


@icon("indent")
def _(c):
    lines(c, 52, [26, 50, 74, 98], [58, 58, 58, 58])
    c.move_to(14, 44)
    c.line_to(36, 62)
    c.line_to(14, 80)
    c.close_path()
    c.set_source(grad())
    c.fill()


@icon("unindent")
def _(c):
    lines(c, 52, [26, 50, 74, 98], [58, 58, 58, 58])
    c.move_to(36, 44)
    c.line_to(14, 62)
    c.line_to(36, 80)
    c.close_path()
    c.set_source(grad())
    c.fill()


@icon("linespacing")
def _(c):
    lines(c, 56, [26, 50, 74, 98], [54, 54, 54, 54])
    bar(c, 26, 22, 26, 106)
    for y, s in ((22, 1), (106, -1)):
        c.move_to(12, y + 14 * s)
        c.line_to(26, y)
        c.line_to(40, y + 14 * s)
        stroke(c)


@icon("fontgrow")
def _(c):
    text(c, "A", 52, 70, 92)
    c.move_to(90, 40)
    c.line_to(104, 20)
    c.line_to(118, 40)
    c.close_path()
    c.set_source(grad(GREEN))
    c.fill()


@icon("fontshrink")
def _(c):
    text(c, "A", 52, 74, 76)
    c.move_to(90, 20)
    c.line_to(104, 40)
    c.line_to(118, 20)
    c.close_path()
    c.set_source(grad(RED))
    c.fill()


@icon("fmtbold")
def _(c):
    text(c, "B", 64, 64, 100)


@icon("fmtitalic")
def _(c):
    text(c, "I", 64, 64, 104, face="DejaVu Serif", bold=True, italic=True)


@icon("fmtunderline")
def _(c):
    text(c, "U", 64, 54, 84)
    bar(c, 26, 112, 102, 112)


@icon("fmtstrike")
def _(c):
    text(c, "S", 64, 64, 100)
    bar(c, 14, 66, 114, 66, RED, 9)


@icon("fmtsuper")
def _(c):
    text(c, "x", 50, 76, 88, bold=False)
    text(c, "2", 102, 30, 46, stops=GREEN)


@icon("fmtsub")
def _(c):
    text(c, "x", 50, 56, 88, bold=False)
    text(c, "2", 102, 100, 46, stops=GREEN)


@icon("textcolor")
def _(c):
    text(c, "A", 64, 50, 86)
    rrect(c, 16, 98, 96, 20, 8)
    c.set_source(grad(RED, 16, 98, 112, 118))
    c.fill()


@icon("highlight")
def _(c):
    c.save()
    c.translate(64, 52)
    c.rotate(math.radians(40))
    rrect(c, -14, -40, 28, 66, 6)
    pale(c)
    stroke(c, width=9)
    c.move_to(-12, 28)
    c.line_to(0, 46)
    c.line_to(12, 28)
    stroke(c, width=9)
    c.restore()
    rrect(c, 16, 100, 96, 18, 8)
    solid(c, YELLOW)
    c.fill()


@icon("clearformat")
def _(c):
    text(c, "A", 50, 60, 92)
    badge(c, "cross", 98, 96, 24)


@icon("inserttable")
def _(c):
    grid(c, 14, 20, 100, 88, 3, 3, header=True)


@icon("insertpicture")
def _(c):
    body(c, 12, 20, 104, 88, 16)
    c.move_to(20, 98)
    c.line_to(52, 60)
    c.line_to(74, 84)
    c.line_to(88, 70)
    c.line_to(108, 98)
    c.close_path()
    c.set_source(grad(GREEN, 20, 60, 108, 98))
    c.fill()
    c.arc(88, 44, 11, 0, 2 * math.pi)
    solid(c, YELLOW)
    c.fill()


@icon("insertlink")
def _(c):
    c.save()
    c.translate(64, 64)
    c.rotate(math.radians(-45))
    for x in (-24, 24):
        rrect(c, x - 26, -16, 52, 32, 16)
        stroke(c, width=12)
    bar(c, -14, 0, 14, 0, GREEN, 12)
    c.restore()


@icon("insertbreak")
def _(c):
    c.move_to(28, 12)
    c.line_to(100, 12)
    c.line_to(100, 44)
    c.move_to(28, 12)
    c.line_to(28, 44)
    stroke(c)
    c.move_to(28, 116)
    c.line_to(100, 116)
    c.line_to(100, 84)
    c.move_to(28, 116)
    c.line_to(28, 84)
    stroke(c)
    c.set_dash([10, 10])
    bar(c, 10, 64, 118, 64, ORANGE, 8)
    c.set_dash([])


@icon("insertequation")
def _(c):
    c.move_to(98, 26)
    c.line_to(98, 16)
    c.line_to(28, 16)
    c.line_to(68, 64)
    c.line_to(28, 112)
    c.line_to(98, 112)
    c.line_to(98, 102)
    stroke(c, width=12)


@icon("insertnote")
def _(c):
    page(c)
    lines(c, 40, [42, 62], [44, 26], width=9)
    text(c, "1", 80, 54, 24, stops=ORANGE)      # the mark in the text
    bar(c, 40, 84, 62, 84, width=5)             # the rule above the notes
    text(c, "1", 44, 102, 18, stops=ORANGE)
    bar(c, 54, 102, 86, 102, ORANGE, 7)


@icon("insertfield")
def _(c):
    body(c, 12, 22, 104, 84, 18)
    text(c, "#", 64, 64, 60)


@icon("insertform")
def _(c):
    # a ticked box beside a line, and a drop-down field below
    body(c, 12, 14, 40, 40, 10)
    c.move_to(21, 34)
    c.line_to(30, 44)
    c.line_to(45, 22)
    stroke(c, GREEN, 9)
    lines(c, 64, [34], [50], width=9)
    body(c, 12, 70, 104, 40, 10)
    lines(c, 26, [90], [44], width=8)
    c.move_to(84, 84)
    c.line_to(104, 84)
    c.line_to(94, 97)
    c.close_path()
    c.set_source(grad())
    c.fill()


@icon("insertsymbol")
def _(c):
    text(c, "Ω", 64, 64, 104)


@icon("margins")
def _(c):
    page(c)
    c.set_dash([8, 8])
    c.rectangle(40, 34, 48, 66)
    stroke(c, ORANGE, 6)
    c.set_dash([])


@icon("orientation")
def _(c):
    rrect(c, 12, 30, 64, 86, 10)
    pale(c)
    stroke(c)
    rrect(c, 44, 12, 74, 52, 10)
    pale(c, GREEN)
    stroke(c, GREEN)


@icon("pagesize")
def _(c):
    page(c, 30, 16, 70, 96)
    text(c, "A4", 64, 74, 30)


@icon("columns")
def _(c):
    page(c)
    lines(c, 38, [44, 60, 76, 92], [14, 14, 14, 14], width=8)
    lines(c, 72, [44, 60, 76, 92], [14, 14, 14, 10], width=8)


@icon("header")
def _(c):
    page(c)
    rrect(c, 36, 24, 46, 14, 6)
    c.set_source(grad(ORANGE))
    c.fill()
    lines(c, 38, [62, 80, 98], [50, 50, 34], width=8)


@icon("footer")
def _(c):
    page(c)
    lines(c, 38, [38, 56, 74], [50, 50, 34], width=8)
    rrect(c, 36, 92, 56, 14, 6)
    c.set_source(grad(ORANGE))
    c.fill()


@icon("pagenumbers")
def _(c):
    page(c)
    lines(c, 38, [40, 58], [50, 38], width=8)
    text(c, "1", 64, 90, 34, stops=ORANGE)


@icon("linenumbers")
def _(c):
    for i, y in enumerate((26, 54, 82, 110)):
        text(c, str(i + 1), 20, y, 24, stops=ORANGE)
        bar(c, 44, y, 112, y)


@icon("toc")
def _(c):
    for i, y in enumerate((24, 52, 80, 108)):
        x = 14 if i != 2 else 30
        bar(c, x, y, x + 26, y, width=9)
        for k in range(x + 38, 92, 10):
            dot(c, k, y + 2, 2.5)
        text(c, str(i + 1), 108, y, 24, stops=ORANGE)


@icon("caption")
def _(c):
    body(c, 18, 12, 92, 64, 12)
    c.move_to(26, 68)
    c.line_to(50, 40)
    c.line_to(66, 58)
    c.line_to(78, 48)
    c.line_to(102, 68)
    c.close_path()
    c.set_source(grad(GREEN, 26, 40, 102, 68))
    c.fill()
    bar(c, 30, 98, 98, 98, ORANGE, 9)
    bar(c, 40, 116, 88, 116, width=8)


@icon("crossref")
def _(c):
    page(c, 14, 30, 58, 84)
    c.move_to(54, 52)
    c.curve_to(76, 10, 112, 18, 108, 62)
    stroke(c, ORANGE)
    c.move_to(96, 50)
    c.line_to(108, 64)
    c.line_to(120, 50)
    stroke(c, ORANGE)


@icon("bookmark")
def _(c):
    c.move_to(34, 12)
    c.line_to(94, 12)
    c.line_to(94, 116)
    c.line_to(64, 90)
    c.line_to(34, 116)
    c.close_path()
    pale(c, ORANGE)
    stroke(c, ORANGE)


@icon("trackchanges")
def _(c):
    page(c, 14, 12)
    lines(c, 28, [44, 64], [36, 28], width=8)
    bar(c, 28, 84, 62, 84, RED, 8)
    c.save()
    c.translate(92, 78)
    c.rotate(math.radians(40))
    rrect(c, -9, -42, 18, 62, 5)
    pale(c, GREEN)
    stroke(c, GREEN, 8)
    c.move_to(-9, 20)
    c.line_to(0, 36)
    c.line_to(9, 20)
    stroke(c, GREEN, 8)
    c.restore()


@icon("prevchange")
def _(c):
    page(c, 30, 30, 68, 86)
    arrow(c, 64, 70, 64, 10, ORANGE)


@icon("nextchange")
def _(c):
    page(c, 30, 12, 68, 86)
    arrow(c, 64, 58, 64, 118, ORANGE)


@icon("accept")
def _(c):
    page(c, 14, 12)
    badge(c, "check", 92, 92, 28)


@icon("reject")
def _(c):
    page(c, 14, 12)
    badge(c, "cross", 92, 92, 28)


@icon("addcomment")
def _(c):
    c.move_to(26, 16)
    c.line_to(102, 16)
    c.arc(102, 30, 14, -math.pi / 2, 0)
    c.line_to(116, 70)
    c.arc(102, 70, 14, 0, math.pi / 2)
    c.line_to(54, 84)
    c.line_to(30, 108)
    c.line_to(32, 84)
    c.line_to(26, 84)
    c.arc(26, 70, 14, math.pi / 2, math.pi)
    c.line_to(12, 30)
    c.arc(26, 30, 14, math.pi, 3 * math.pi / 2)
    c.close_path()
    pale(c, ORANGE)
    stroke(c, ORANGE)
    lines(c, 34, [40, 60], [56, 40], ORANGE, 8)


@icon("zoomin")
def _(c):
    c.arc(54, 54, 38, 0, 2 * math.pi)
    pale(c)
    stroke(c)
    bar(c, 82, 82, 114, 114, width=14)
    bar(c, 36, 54, 72, 54, GREEN, 10)
    bar(c, 54, 36, 54, 72, GREEN, 10)


@icon("zoomout")
def _(c):
    c.arc(54, 54, 38, 0, 2 * math.pi)
    pale(c)
    stroke(c)
    bar(c, 82, 82, 114, 114, width=14)
    bar(c, 36, 54, 72, 54, RED, 10)


@icon("formatmarks")
def _(c):
    text(c, "¶", 64, 66, 112)


@icon("navigation")
def _(c):
    body(c, 10, 18, 108, 92, 14)
    bar(c, 48, 22, 48, 106, width=8)
    lines(c, 20, [42, 62, 82], [16, 16, 16], ORANGE, 8)
    lines(c, 62, [42, 62, 82], [40, 30, 40], width=8)


@icon("share")
def _(c):
    for (x, y) in ((96, 26), (96, 102), (30, 64)):
        pass
    bar(c, 34, 64, 92, 30, width=9)
    bar(c, 34, 64, 92, 98, width=9)
    for (x, y, st) in ((96, 28, GREEN), (96, 100, GREEN), (30, 64, BLUE)):
        c.arc(x, y, 18, 0, 2 * math.pi)
        pale(c, st)
        stroke(c, st, 9)


@icon("join")
def _(c):
    page(c, 50, 12, 64, 92)
    arrow(c, 8, 64, 56, 64, GREEN, 12)


@icon("host")
def _(c):
    body(c, 20, 18, 88, 36, 10)
    body(c, 20, 66, 88, 36, 10)
    dot(c, 40, 36, 6, GREEN)
    dot(c, 40, 84, 6, GREEN)
    lines(c, 58, [36, 84], [34, 34], width=8)


@icon("formatpainter")
def _(c):
    # the brush's head
    rrect(c, 14, 14, 86, 34, 10)
    pale(c, ORANGE)
    stroke(c, ORANGE)
    # its handle, down from the head's right end and back to the middle
    c.move_to(100, 31)
    c.line_to(112, 31)
    c.line_to(112, 62)
    c.line_to(60, 62)
    c.line_to(60, 76)
    stroke(c)
    rrect(c, 50, 76, 20, 40, 6)
    c.set_source(grad())
    c.fill()


@icon("tblinsert")
def _(c):
    grid(c, 10, 14, 88, 78, 3, 3)
    badge(c, "plus", 98, 98, 24)


@icon("tbldelete")
def _(c):
    grid(c, 10, 14, 88, 78, 3, 3)
    badge(c, "minus", 98, 98, 24)


@icon("tblmerge")
def _(c):
    grid(c, 10, 22, 108, 84, 2, 2)
    arrow(c, 22, 46, 54, 46, ORANGE, 8, 12)
    arrow(c, 106, 46, 74, 46, ORANGE, 8, 12)


@icon("shading")
def _(c):
    grid(c, 12, 20, 104, 88, 3, 3, fill_cells=((1, 1), (2, 0), (0, 2)))


@icon("borders")
def _(c):
    grid(c, 14, 20, 100, 88, 3, 3)
    rrect(c, 14, 20, 100, 88, 12)
    stroke(c, ORANGE, 14)


@icon("headerrow")
def _(c):
    grid(c, 12, 18, 104, 92, 4, 3, header=True)


@icon("distribute")
def _(c):
    grid(c, 12, 14, 104, 62, 1, 3)
    for x in (29, 64, 99):     # a span under each column, the same for all
        bar(c, x - 14, 102, x + 14, 102, ORANGE, 6)
        for s in (-1, 1):
            c.move_to(x + s * 14 - s * 7, 94)
            c.line_to(x + s * 14, 102)
            c.line_to(x + s * 14 - s * 7, 110)
            stroke(c, ORANGE, 6)


# ---------- out ----------

def render(name):
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, int(S), int(S))
    c = cairo.Context(surf)
    c.set_antialias(cairo.ANTIALIAS_BEST)
    ICONS[name](c)
    return surf


def main():
    args = sys.argv[1:]
    if args and args[0] == "--sheet":
        out = args[1] if len(args) > 1 else "visual_icons_sheet.png"
        n = len(ICONS)
        cols = 10
        rows = (n + cols - 1) // cols
        sheet = cairo.ImageSurface(cairo.FORMAT_ARGB32, cols * 150, rows * 160)
        c = cairo.Context(sheet)
        c.set_source_rgb(1, 1, 1)
        c.paint()
        for i, name in enumerate(sorted(ICONS)):
            x, y = (i % cols) * 150 + 11, (i // cols) * 160 + 6
            c.set_source_surface(render(name), x, y)
            c.paint()
            c.set_source_rgb(0.2, 0.2, 0.2)
            c.select_font_face("DejaVu Sans")
            c.set_font_size(13)
            c.move_to(x, y + 148)
            c.show_text(name)
        sheet.write_to_png(out)
        print(out)
        return
    outdir = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "icons")
    for name in sorted(ICONS):
        render(name).write_to_png(os.path.join(outdir, name + ".png"))
    print("%d icons in %s" % (len(ICONS), outdir))


if __name__ == "__main__":
    main()
