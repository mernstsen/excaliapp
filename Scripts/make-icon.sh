#!/bin/sh
# Regenerates the app icon PNGs from Scripts/GenerateAppIcon.swift.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/ExcaliApp/Assets.xcassets/AppIcon.appiconset"
bin=$(mktemp -d)/geniconn
swiftc -O "$root/Scripts/GenerateAppIcon.swift" -o "$bin"
"$bin" "$out"
