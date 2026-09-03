#!/usr/bin/env python3
"""Generate the led application icon from the artwork.

The design is a green LED standing on a lit strip -- the pun the editor is
named for.  Two files in packaging/icons are inputs, not outputs:

  led.svg          the master, drawn by hand; also shipped as the scalable
                   icon Linux desktops prefer
  led-master.png   that SVG rendered once at 1024 wide, committed

Everything else is derived from led-master.png by this script:

  led.ico                       multi-size Windows icon, embedded as MAINICON
  led.icns                      macOS bundle icon
  hicolor/<N>x<N>/apps/led.png  the sizes Linux icon themes look for
  ../windows/wizard-*.bmp       the Inno Setup wizard images

The render is committed rather than done here because the glow under the LED
is an feGaussianBlur, and the obvious build-time rasteriser drops it:
cairosvg renders that filter as a hard-edged bar, losing the one thing that
makes the LED look lit.  Inkscape gets it right but is far too heavy to put
in CI, and pinning a renderer well enough for a pixel comparison to stay
stable is worse than committing its output.  So when the artwork changes,
re-render it by hand and commit both:

  inkscape --export-type=png --export-filename=packaging/icons/led-master.png \
           --export-width=1024 packaging/icons/led.svg

Run from the repository root:  python3 tools/make-icon.py
Requires Pillow.
"""

import io
import os
import struct

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "packaging", "icons")
MASTER_PNG = os.path.join(OUT, "led-master.png")

MASTER = 1024              # downscale from here with LANCZOS for crisp edges
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
PNG_SIZES = [16, 22, 24, 32, 48, 64, 128, 256, 512]

# Inno Setup wizard images, which must be BMP and are drawn on the page
# background rather than composited, so they carry no alpha.
WIZARD_BG = (255, 255, 255)
WIZARD_LARGE = (164, 314)
WIZARD_SMALL = (55, 55)

_master = None

_master = None


def master():
    """The artwork, square and centred.

    The drawing is 139.36 x 139.65 units -- close to square but not square --
    so the render comes out 1024 x 1026 and is centred on a square canvas
    rather than squashed to fit.
    """
    global _master
    if _master is None:
        art = Image.open(MASTER_PNG).convert("RGBA")
        side = max(MASTER, art.width, art.height)
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(art, ((side - art.width) // 2,
                           (side - art.height) // 2), art)
        _master = canvas if side == MASTER else \
            canvas.resize((MASTER, MASTER), Image.LANCZOS)
    return _master


def render(n):
    """The icon at n x n pixels."""
    return master().resize((n, n), Image.LANCZOS)


def write_wizard_images():
    """The two bitmaps Inno Setup shows in its wizard.

    Flattened onto white: Inno draws these opaque, and a transparent PNG
    turned into a BMP loses its alpha to black otherwise.
    """
    d = os.path.join(ROOT, "packaging", "windows")
    os.makedirs(d, exist_ok=True)
    for name, (w, h) in (("wizard-large.bmp", WIZARD_LARGE),
                         ("wizard-small.bmp", WIZARD_SMALL)):
        side = min(w, h)
        art = render(side if name.endswith("small.bmp") else int(side * 0.8))
        sheet = Image.new("RGB", (w, h), WIZARD_BG)
        tile = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        tile.paste(art, ((w - art.width) // 2, (h - art.height) // 2), art)
        sheet.paste(tile, (0, 0), tile)
        sheet.save(os.path.join(d, name), format="BMP")

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



def main():
    os.makedirs(OUT, exist_ok=True)
    write_ico(os.path.join(OUT, "led.ico"), ICO_SIZES)
    write_icns(os.path.join(OUT, "led.icns"))
    for n in PNG_SIZES:
        d = os.path.join(OUT, "hicolor", "%dx%d" % (n, n), "apps")
        os.makedirs(d, exist_ok=True)
        render(n).save(os.path.join(d, "led.png"))
    write_wizard_images()
    print("wrote led.ico, led.icns, %d hicolor PNGs and the wizard images "
          "from %s" % (len(PNG_SIZES), os.path.relpath(MASTER_PNG, ROOT)))


if __name__ == "__main__":
    main()
