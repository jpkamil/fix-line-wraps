#!/bin/bash
# render-icon.sh — render Packaging/FixLineWraps.icns from FixLineWrapsIcon.swift.
# Only needed after editing the .swift; the .icns is committed so build-app.sh works without it.
set -e
cd "$(dirname "$0")"
command -v swift >/dev/null || { echo "swift not found (needs the Xcode Command Line Tools)"; exit 1; }
T=$(mktemp -d)
swift FixLineWrapsIcon.swift "$T" >/dev/null
SET="$T/FixLineWraps.iconset"; mkdir -p "$SET"
for n in 16 32 128 256 512; do
  sips -z $n $n "$T/_reflow_icon_1024.png" --out "$SET/icon_${n}x${n}.png" >/dev/null
  d=$((n*2)); sips -z $d $d "$T/_reflow_icon_1024.png" --out "$SET/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o FixLineWraps.icns
rm -rf "$T"
echo "wrote Packaging/FixLineWraps.icns"
