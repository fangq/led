#!/bin/sh
# led - install into a prefix.  Usage: ./install.sh [PREFIX]   (default /usr/local)
set -e
PREFIX="${1:-/usr/local}"
DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -x "$DIR/bin/led" ]; then
  echo "led is not built yet; run ./build.sh first." >&2
  exit 1
fi

BIN="$PREFIX/bin"
DATA="$PREFIX/share/led"

echo "installing to $PREFIX"
mkdir -p "$BIN" "$DATA"
install -m 755 "$DIR/bin/led" "$BIN/led"

# Grammars, themes and the default tools are read at run time, so they have
# to travel with the binary.
for sub in grammars themes tools langs icons; do
  if [ -d "$DIR/data/$sub" ]; then
    mkdir -p "$DATA/$sub"
    cp -r "$DIR/data/$sub/." "$DATA/$sub/"
  fi
done

if [ -d "$PREFIX/share/applications" ] || mkdir -p "$PREFIX/share/applications"; then
  install -m 644 "$DIR/packaging/led.desktop" "$PREFIX/share/applications/led.desktop"
fi

echo
echo "installed: $BIN/led"
echo "data:      $DATA"
echo
echo "led finds its data next to the binary or at \$LED_DATA_DIR."
echo "If you installed somewhere unusual, set LED_DATA_DIR=$DATA"
