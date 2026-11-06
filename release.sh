#!/bin/bash
# Build the downloadable ShotShelf-<version>.dmg in ./dist:
# universal (Apple silicon + Intel), Developer ID signed, notarized and stapled.
#
# Needs a "Developer ID Application" certificate in the keychain and a notarytool
# keychain profile, created once with an App Store Connect API key
# (App Store Connect › Users and Access › Integrations › Team Keys, "Developer" access):
#   xcrun notarytool store-credentials ShotShelf --key AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER-ID>
# or with an Apple ID and an app-specific password:
#   xcrun notarytool store-credentials ShotShelf --apple-id <you@example.com> --team-id <TEAMID>
# Use NOTARY_PROFILE=<name> for a different profile name.
# ./release.sh --no-notarize builds and signs only (for checking locally; don't ship that).
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${NOTARY_PROFILE:-ShotShelf}"
NOTARIZE=1
[ "${1:-}" = "--no-notarize" ] && NOTARIZE=0

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
if [ -z "$IDENTITY" ]; then
    echo "No \"Developer ID Application\" certificate in the keychain." >&2
    exit 1
fi
if [ $NOTARIZE = 1 ] && ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "No notarytool profile \"$PROFILE\". Create it first (see the top of this script)." >&2
    exit 1
fi

DIST=dist
APP="$DIST/ShotShelf.app"
DMG="$DIST/ShotShelf-$VERSION.dmg"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Building universal binary"
swift build -c release --arch arm64 --arch x86_64
cp .build/apple/Products/Release/ShotShelf "$APP/Contents/MacOS/ShotShelf"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing with $IDENTITY"
# Hardened runtime + secure timestamp are required for notarization.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

notarize() {
    local file="$1" log="$DIST/notary.log"
    echo "==> Notarizing $(basename "$file") (usually takes a few minutes)"
    xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait | tee "$log"
    if ! grep -q "status: Accepted" "$log"; then
        local id
        id=$(awk '/^  id:/ {print $2; exit}' "$log")
        [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$PROFILE"
        echo "Notarization failed." >&2
        exit 1
    fi
    rm -f "$log"
}

if [ $NOTARIZE = 1 ]; then
    # Notarize and staple the app itself, so it opens even offline once copied out of the dmg.
    ditto -c -k --keepParent "$APP" "$DIST/ShotShelf.zip"
    notarize "$DIST/ShotShelf.zip"
    rm "$DIST/ShotShelf.zip"
    xcrun stapler staple "$APP"
fi

echo "==> Making $DMG"
STAGE="$DIST/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications" # drag-to-install target
hdiutil create -quiet -volname "ShotShelf" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ $NOTARIZE = 1 ]; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    echo "==> Gatekeeper check"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    spctl --assess --type execute --verbose=2 "$APP"
fi

echo "Done: $DMG"
