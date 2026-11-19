#!/bin/bash
# Builds a Developer ID signed, notarized and stapled build/release/Scanfold-<version>.dmg.
#
# One-time setup (stores your notary credentials in the Keychain):
#   xcrun notarytool store-credentials scanfold --apple-id <apple-id> --team-id G9Y55AN5H5
# Then bump CFBundleShortVersionString / CFBundleVersion in Info.plist and run:
#   scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-scanfold}"
IDENTITY="Developer ID Application"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
OUT=build/release
DMG="$OUT/Scanfold-$VERSION.dmg"
APP=build/Build/Products/Release/Scanfold.app

rm -rf "$OUT" "$APP"
mkdir -p "$OUT/dmg"

# No injected get-task-allow: notarization rejects it.
xcodebuild -project Scanfold.xcodeproj -scheme Scanfold -configuration Release -derivedDataPath build -quiet \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS=--timestamp build
codesign --verify --strict "$APP"

ditto "$APP" "$OUT/dmg/Scanfold.app"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -quiet -volname Scanfold -srcfolder "$OUT/dmg" -format UDZO -ov "$DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

shasum -a 256 "$DMG"
echo "Publish with: gh release create v$VERSION $DMG --generate-notes"
