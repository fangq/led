#!/bin/sh
# Builds dist/led_<version>_<arch>.deb and a portable dist/led-<version>-linux-<arch>.tar.gz
# from an already-compiled bin/led.
#
#   packaging/linux/build-deb.sh <repo-root> [version]
#
# A script rather than inline workflow steps, so the packaging can be run and
# fixed on a laptop instead of only ever being exercised by CI.
set -eu

ROOT="${1:?usage: build-deb.sh <repo-root> [version]}"
VERSION="${2:-${VERSION:-0.0.0-dev}}"
cd "$ROOT"

[ -x bin/led ] || { echo "bin/led is not built; run make first" >&2; exit 1; }

ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
SIZES="16 22 24 32 48 64 128 256 512"
PKG="build/deb/led_${VERSION}_${ARCH}"

rm -rf "$PKG"
mkdir -p "$PKG/DEBIAN" "$PKG/usr/bin" "$PKG/usr/share/led" \
         "$PKG/usr/share/applications" "$PKG/usr/share/doc/led" \
         "$PKG/usr/share/icons/hicolor/scalable/apps"

install -m 0755 bin/led "$PKG/usr/bin/led"

# The grammars, themes and shipped tools are read at run time.  A package that
# ships only the executable produces an editor that opens every file as plain
# text, so this is not optional.
for sub in grammars themes tools langs; do
  [ -d "data/$sub" ] && cp -r "data/$sub" "$PKG/usr/share/led/"
done

install -m 0644 packaging/linux/led.desktop \
        "$PKG/usr/share/applications/led.desktop"
install -m 0644 packaging/icons/led.svg \
        "$PKG/usr/share/icons/hicolor/scalable/apps/led.svg"
for s in $SIZES; do
  d="$PKG/usr/share/icons/hicolor/${s}x${s}/apps"
  mkdir -p "$d"
  install -m 0644 "packaging/icons/hicolor/${s}x${s}/apps/led.png" "$d/led.png"
done
install -m 0644 README.md "$PKG/usr/share/doc/led/README.md"

# control: fields at column 0, Description continuation lines prefixed with a
# single space.
{
  echo "Package: led"
  echo "Version: ${VERSION}"
  echo "Section: editors"
  echo "Priority: optional"
  echo "Architecture: ${ARCH}"
  echo "Depends: libgtk2.0-0 | libgtk2.0-0t64, libx11-6, libc6"
  echo "Suggests: universal-ctags | exuberant-ctags, python3"
  echo "Maintainer: Qianqian Fang <q.fang@northeastern.edu>"
  echo "Homepage: https://github.com/fangq/led"
  echo "Description: led - a light programmer's text editor"
  echo " A lightweight, cross-platform programmer's editor: tabs and split"
  echo " views over a shared buffer, syntax highlighting for 128 languages,"
  echo " code folding, find in files, user-defined tools with clickable"
  echo " compiler output, a file browser, a symbol browser and an embedded"
  echo " terminal."
} > "$PKG/DEBIAN/control"

mkdir -p dist
dpkg-deb --build --root-owner-group "$PKG" "dist/led_${VERSION}_${ARCH}.deb"

# The portable tree, for people who do not want a package manager involved.
STAGE="led-${VERSION}-linux-$(uname -m)"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/data"
cp bin/led "$STAGE/bin/"
for sub in grammars themes tools langs; do
  [ -d "data/$sub" ] && cp -r "data/$sub" "$STAGE/data/"
done
for f in README.md PARITY.md install.sh; do
  [ -f "$f" ] && cp "$f" "$STAGE/"
done
tar czf "dist/${STAGE}.tar.gz" "$STAGE"

ls -lh dist
