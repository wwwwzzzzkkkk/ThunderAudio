#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
thunderaudio_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
# Stage outside cloud-backed folders, which can attach Finder metadata while
# codesign is sealing the app. Clean only this temporary build product.
thunderaudio_stage=$(mktemp -d "${TMPDIR:-/tmp}/ThunderAudio-build.XXXXXX")
trap 'rm -rf "$thunderaudio_stage"' EXIT
mkdir -p "$thunderaudio_stage/ThunderAudio.app/Contents/MacOS"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos13.0 Sources/*.swift -o "$thunderaudio_stage/ThunderAudio.app/Contents/MacOS/ThunderAudio"
cp Info.plist "$thunderaudio_stage/ThunderAudio.app/Contents/Info.plist"
xattr -cr "$thunderaudio_stage/ThunderAudio.app"
codesign --force --sign - "$thunderaudio_stage/ThunderAudio.app"
codesign --verify --deep --strict "$thunderaudio_stage/ThunderAudio.app"
ditto --norsrc --noextattr -c -k --keepParent "$thunderaudio_stage/ThunderAudio.app" "build/ThunderAudio-${thunderaudio_version}-macOS-arm64.zip"
ditto --norsrc --noextattr "$thunderaudio_stage/ThunderAudio.app" build/ThunderAudio.app
printf 'Built: %s/build/ThunderAudio.app\nDistribution ZIP: %s/build/ThunderAudio-%s-macOS-arm64.zip\n' "$PWD" "$PWD" "$thunderaudio_version"
