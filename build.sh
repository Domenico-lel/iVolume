#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
destination="${1:-dist/iVolume.app}"
architecture="$(uname -m)"
mkdir -p "$destination/Contents/MacOS" "$destination/Contents/Resources" build
xcrun clang -O2 -arch "$architecture" -mmacosx-version-min=14.2 -c Render.c -o build/Render.o
xcrun swiftc -swift-version 5 -O -target "$architecture-apple-macos14.2" -import-objc-header Render.h Audio.swift Model.swift App.swift build/Render.o -o "$destination/Contents/MacOS/iVolume" -framework AppKit -framework SwiftUI -framework CoreAudio -framework AudioToolbox -framework ApplicationServices
cp Info.plist "$destination/Contents/Info.plist"
if [ -f AppIcon.icns ]; then cp AppIcon.icns "$destination/Contents/Resources/"; fi
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --identifier it.domenicolella.ivolume "$destination"
codesign --verify --strict "$destination"
