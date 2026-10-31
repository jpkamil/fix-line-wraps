#!/bin/bash
# build-app.sh — build "Fix Line Wraps.app" from Sources/FixLineWraps.swift and reflow_md.py.
#
#   ./build-app.sh             build into ~/Library/Caches/fix-line-wraps-build/
#   ./build-app.sh --install   build, then copy to /Applications (replacing the old one)
#   ./build-app.sh --open      build, install and launch
#
# Build output stays out of this folder on purpose: codesign fails on iCloud-tagged files, and
# the .app is a build artefact, not a source file. Needs the Xcode Command Line Tools (swiftc).
set -euo pipefail
cd "$(dirname "$0")"
command -v swiftc >/dev/null || { echo "swiftc not found: run  xcode-select --install"; exit 1; }
OUT="$HOME/Library/Caches/fix-line-wraps-build"
APP="$OUT/Fix Line Wraps.app"
mkdir -p "$OUT"

swiftc -O -swift-version 5 -framework AppKit -framework UniformTypeIdentifiers \
  -o "$OUT/FixLineWraps" Sources/FixLineWraps.swift

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/FixLineWraps" "$APP/Contents/MacOS/"
cp Packaging/Info.plist "$APP/Contents/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp reflow_md.py "$APP/Contents/Resources/"          # the app carries its own copy of the tool
cp Packaging/FixLineWraps.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built: $APP"

case "${1:-}" in
  --install|--open)
    DEST="/Applications/Fix Line Wraps.app"
    osascript -e 'tell application "Fix Line Wraps" to quit' >/dev/null 2>&1 || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    touch "$DEST"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
    echo "Installed: $DEST"
    [ "$1" = "--open" ] && open "$DEST"
    ;;
esac
