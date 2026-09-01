#!/bin/sh
# led - install into a prefix.  Usage: ./install.sh [PREFIX]   (default /usr/local)
#
# A wrapper around `make install`, which is where the install rules live.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
exec make -C "$DIR" install PREFIX="${1:-/usr/local}"
