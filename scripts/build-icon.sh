#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift scripts/render-icon.swift Resources/AppIcon.png
thunderaudio_iconstage=$(mktemp -d "${TMPDIR:-/tmp}/ThunderAudio-icon.XXXXXX")
trap 'rm -rf "$thunderaudio_iconstage"' EXIT
mkdir -p "$thunderaudio_iconstage/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$thunderaudio_iconstage/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" Resources/AppIcon.png --out "$thunderaudio_iconstage/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$thunderaudio_iconstage/AppIcon.iconset" -o Resources/AppIcon.icns
