#!/bin/bash
# Build ShotShelf.app into ./build (ad-hoc signed, for local use).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/ShotShelf.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ShotShelf "$APP/Contents/MacOS/ShotShelf"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Sign with the local Apple Development certificate when there is one, so the
# screen-recording permission survives rebuilds; otherwise fall back to ad-hoc.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
echo "Signed with: ${IDENTITY:-ad-hoc}"

echo "Built $APP"
