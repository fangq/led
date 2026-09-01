#!/bin/sh
# Builds led.app from an already-compiled binary, and a .dmg around it.
#
#   packaging/macos/build-app.sh <repo-root> [version]
#
# Kept as a script rather than inlined in the workflow so it can be run by
# hand on a Mac to reproduce exactly what CI produces.
set -eu

ROOT="${1:?usage: build-app.sh <repo-root> [version]}"
VERSION="${2:-${VERSION:-0.0.0-dev}}"
cd "$ROOT"

# lazbuild puts the binary at bin/led, but a cocoa build may produce a bundle
# skeleton of its own; take whichever is there.
if [ -x "bin/led.app/Contents/MacOS/led" ]; then
  BIN="bin/led.app/Contents/MacOS/led"
elif [ -x "bin/led" ]; then
  BIN="bin/led"
else
  echo "no led binary produced" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
APP="$STAGE/led.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/led"
chmod +x "$APP/Contents/MacOS/led"
cp packaging/icons/led.icns "$APP/Contents/Resources/led.icns"

# The grammars, themes and shipped tools are read at run time.  Contents/
# Resources/data is where Led.Core.Paths looks first on Darwin.
mkdir -p "$APP/Contents/Resources/data"
for sub in grammars themes tools langs; do
  [ -d "data/$sub" ] && cp -R "data/$sub" "$APP/Contents/Resources/data/"
done

sed "s/__VERSION__/${VERSION}/g" packaging/macos/Info.plist \
    > "$APP/Contents/Info.plist"

# Ad-hoc signing, so the bundle runs on the machine that built it.  A
# downloaded .dmg still needs a Developer ID and notarization; that is a
# separate step and is documented as not done.
codesign -s - --force --deep "$APP" 2>/dev/null || true

ln -s /Applications "$STAGE/Applications"

mkdir -p dist
hdiutil create -volname "led" -srcfolder "$STAGE" \
        -ov -format UDZO "dist/led-${VERSION}-macos.dmg"
ls -lh dist
