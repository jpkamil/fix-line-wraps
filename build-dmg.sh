#!/bin/bash
# build-dmg.sh — build the app, then wrap it in a drag-to-Applications disk image for a Mac that
# does not have this repository. On that Mac expect one Gatekeeper prompt ("Open Anyway" under
# Privacy & Security): the app is ad-hoc signed, not notarized.
#
#   ./build-dmg.sh [output.dmg]      default: build/Fix Line Wraps.dmg
set -euo pipefail
OUT="${1:-}"
case "$OUT" in ""|/*) ;; *) OUT="$PWD/$OUT" ;; esac   # resolve before leaving the caller's folder
cd "$(dirname "$0")"
[ -n "$OUT" ] || OUT="$PWD/build/Fix Line Wraps.dmg"
./build-app.sh >/dev/null
APP="$HOME/Library/Caches/fix-line-wraps-build/Fix Line Wraps.app"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME.txt" <<'TXT'
Fix Line Wraps

1. Drag "Fix Line Wraps" onto the Applications shortcut beside it.
2. Open it. Drop .md files (or folders of them) on its window, or on its Dock
   icon, or press "Choose Files...". Each file is rewritten in place with one
   line per paragraph, so it flows to any window width. The window shows what
   was joined.

It only ever changes whitespace. Before writing, it proves the text is identical
to the character and refuses the file otherwise, so nothing can be lost. Code
blocks, tables, lists, headings, indented lines and To:/Subject: headers keep
their line breaks.

First run on a new Mac: if macOS says the app cannot be opened, go to System
Settings > Privacy & Security, scroll down, "Open Anyway". Once.

Source: https://github.com/jpkamil/fix-line-wraps
TXT
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil create -volname "Fix Line Wraps" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$OUT" >/dev/null
rm -rf "$STAGE"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
