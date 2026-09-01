#!/bin/sh
# led - build everything.  Usage: ./build.sh [widgetset]   (default: gtk2)
#
# Kept because it is what the documentation and the plan reference; the build
# itself lives in the Makefile now, so there is one place to change.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
exec make -C "$DIR" WIDGETSET="${1:-gtk2}" build tests grammars
