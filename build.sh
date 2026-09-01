#!/bin/sh
# led - build everything.  Usage: ./build.sh [widgetset]   (default: gtk2)
set -e
WS="${1:-gtk2}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> app  (widgetset: $WS)"
lazbuild --widgetset="$WS" "$DIR/app/led.lpi"

echo "==> core tests  (widgetset: nogui)"
lazbuild --widgetset=nogui "$DIR/test/ledcoretest.lpi"

echo "==> grammar checker"
lazbuild --widgetset=nogui "$DIR/tools/langcheck/langcheck.lpi"

echo
echo "built: $DIR/bin/led"
echo "       $DIR/bin/ledcoretest"
echo "       $DIR/bin/langcheck"
