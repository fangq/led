#!/usr/bin/env python3
"""Generate the led application icon.

The design is deliberately plain, because it has to survive being drawn at
16 pixels in a task bar: a dark rounded panel, four indented lines of code,
and one lit caret in amber.  "led" is a light editor, so the caret is the
only bright thing on it and the only part that must stay recognisable when
everything else turns to mush.

This script is the single source for the icon.  It writes, under
packaging/icons/:

  led.svg                       the scalable copy, for Linux desktops
  led.ico                       multi-size Windows icon, embedded as MAINICON
  led.icns                      macOS bundle icon
  hicolor/<N>x<N>/apps/led.png  the sizes Linux icon themes look for

Run from the repository root:  python3 tools/make-icon.py
Requires Pillow.
"""

import os
import struct
from PIL import Image, ImageDraw

# The palette.  Two greys and one accent; nothing else.
PANEL  = (43, 48, 59)      # #2b303b  the sheet
BORDER = (27, 31, 39)      # #1b1f27  its edge, so the icon reads on dark themes
TEXT   = (143, 154, 174)   # #8f9aae  lines of code
CARET  = (255, 197, 66)    # #ffc542  the lit caret

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "packaging", "icons")

MASTER = 1024              # render big, downscale with LANCZOS for crisp edges
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
PNG_SIZES = [16, 22, 24, 32, 48, 64, 128, 256, 512]

# Geometry on a 64-unit grid, shared by the raster and the SVG so the two
# cannot drift apart.
PANEL_BOX = (4, 4, 60, 60)
PANEL_R = 10
LINES = [(14, 17, 26), (20, 27, 24), (20, 37, 16), (14, 47, 20)]  # x, y, width
LINE_H = 4
CARET_BOX = (41, 34, 46, 46)


def render(n):
    """The icon at n x n pixels."""
    s = MASTER / 64.0
    img = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def box(x0, y0, x1, y1):
        return [x0 * s, y0 * s, x1 * s, y1 * s]

    d.rounded_rectangle(box(*PANEL_BOX), radius=PANEL_R * s,
                        fill=PANEL, outline=BORDER, width=int(2 * s))
    for x, y, w in LINES:
        d.rounded_rectangle(box(x, y, x + w, y + LINE_H),
                            radius=(LINE_H / 2) * s, fill=TEXT)
    d.rounded_rectangle(box(*CARET_BOX), radius=2 * s, fill=CARET)

    return img.resize((n, n), Image.LANCZOS)


def _dib(img):
    """One ICO entry as an uncompressed 32-bit BGRA DIB.

    Pillow writes ICO entries as PNG, which the LCL icon reader rejects, so
    the entries are built by hand.  A DIB is stored bottom-up and carries a
    doubled height in its header to account for the (here empty) AND mask.
    """
    w, h = img.size
    px = img.convert("RGBA").load()

    header = struct.pack("<IiiHHIIiiII",
                         40,            # biSize
                         w, h * 2,      # biWidth, biHeight (XOR + AND)
                         1, 32,         # biPlanes, biBitCount
                         0,             # biCompression = BI_RGB
                         w * h * 4,     # biSizeImage
                         0, 0, 0, 0)

    rows = []
    for y in range(h - 1, -1, -1):      # bottom-up
        row = bytearray()
        for x in range(w):
            r, g, b, a = px[x, y]
            row += bytes((b, g, r, a))
        rows.append(bytes(row))

    # The AND mask is unused with an alpha channel, but must be present and
    # padded to a 4-byte boundary per row.
    mask_stride = ((w + 31) // 32) * 4
    mask = bytes(mask_stride * h)

    return header + b"".join(rows) + mask


def write_ico(path, sizes):
    dibs = [_dib(render(n)) for n in sizes]
    with open(path, "wb") as f:
        f.write(struct.pack("<HHH", 0, 1, len(dibs)))   # reserved, type=icon, count
        offset = 6 + 16 * len(dibs)
        for n, dib in zip(sizes, dibs):
            f.write(struct.pack("<BBBBHHII",
                                n if n < 256 else 0,    # 0 means 256
                                n if n < 256 else 0,
                                0, 0, 1, 32, len(dib), offset))
            offset += len(dib)
        for dib in dibs:
            f.write(dib)


# The .icns entry types that carry a PNG payload, and the pixel size each
# one is defined to hold.  The @2x variants are the same bitmap at the same
# pixel count; macOS reads the type to know the point size.
ICNS_TYPES = [(b"ic07", 128), (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024),
              (b"ic11", 32),  (b"ic12", 64),  (b"ic13", 256), (b"ic14", 512)]


def write_icns(path):
    """macOS icon.  An icns file is a magic word, a total length, and a list of
    type-tagged chunks; modern readers take PNG payloads directly, so there is
    no need for the legacy packbits formats."""
    import io

    chunks = []
    for tag, n in ICNS_TYPES:
        buf = io.BytesIO()
        render(n).save(buf, format="PNG")
        data = buf.getvalue()
        chunks.append(tag + struct.pack(">I", len(data) + 8) + data)

    body = b"".join(chunks)
    with open(path, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(body) + 8) + body)


def write_svg(path):
    def rect(x, y, w, h, r, fill, extra=""):
        return ('  <rect x="%g" y="%g" width="%g" height="%g" rx="%g" '
                'fill="%s"%s/>\n' % (x, y, w, h, r, fill, extra))

    def hexof(c):
        return "#%02x%02x%02x" % c

    px, py, px1, py1 = PANEL_BOX
    body = ['<?xml version="1.0" encoding="UTF-8"?>\n',
            '<!-- Generated by tools/make-icon.py; edit that, not this. -->\n',
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" '
            'width="64" height="64">\n',
            rect(px, py, px1 - px, py1 - py, PANEL_R, hexof(PANEL)),
            '  <rect x="%g" y="%g" width="%g" height="%g" rx="%g" fill="none" '
            'stroke="%s" stroke-width="2"/>\n'
            % (px, py, px1 - px, py1 - py, PANEL_R, hexof(BORDER)),
            '  <g fill="%s">\n' % hexof(TEXT)]
    for x, y, w in LINES:
        body.append("  " + rect(x, y, w, LINE_H, LINE_H / 2, hexof(TEXT)).strip() + "\n")
    body.append("  </g>\n")
    cx, cy, cx1, cy1 = CARET_BOX
    body.append(rect(cx, cy, cx1 - cx, cy1 - cy, 2, hexof(CARET)))
    body.append("</svg>\n")
    with open(path, "w") as f:
        f.writelines(body)


def main():
    os.makedirs(OUT, exist_ok=True)
    write_svg(os.path.join(OUT, "led.svg"))
    write_ico(os.path.join(OUT, "led.ico"), ICO_SIZES)
    write_icns(os.path.join(OUT, "led.icns"))
    for n in PNG_SIZES:
        d = os.path.join(OUT, "hicolor", "%dx%d" % (n, n), "apps")
        os.makedirs(d, exist_ok=True)
        render(n).save(os.path.join(d, "led.png"))
    print("wrote led.svg, led.ico, led.icns and %d hicolor PNGs under %s"
          % (len(PNG_SIZES), OUT))


if __name__ == "__main__":
    main()
