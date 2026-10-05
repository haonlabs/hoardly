#!/bin/bash
# Builds dist/Hoardly-<version>.dmg (Developer ID signed, notarized, stapled) and dist/appcast.xml for Sparkle.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your login keychain (Xcode → Settings → Accounts).
#   2. xcrun notarytool store-credentials hoardly-notary --apple-id YOU@example.com --team-id TEAMID
#   3. scripts/release.sh keys        # makes the Sparkle signing key (kept in your keychain — back it up
#                                     # with generate_keys -x) and writes its public half into Info.plist
#
# usage: TEAM_ID=TEAMID scripts/release.sh     # full release
#        scripts/release.sh --adhoc           # no Apple Developer account: ad-hoc signed DMG + appcast. Gatekeeper
#                                             # warns on first open, and Safari hides the extension unless the user
#                                             # enables Develop → Allow Unsigned Extensions.
#        scripts/release.sh --local           # ad-hoc DMG only: checks the packaging
set -euo pipefail
cd "$(dirname "$0")/.."
DERIVED=build/DerivedData
SPARKLE_BIN=$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin
REPO=https://github.com/haonlabs/hoardly

if [ "${1:-}" = keys ]; then
  xcodebuild -project Hoardly.xcodeproj -scheme Hoardly -derivedDataPath $DERIVED -resolvePackageDependencies -quiet
  # -p prints the existing public key (errors go to stdout, hence the exit-code check); otherwise create one.
  KEY=$("$SPARKLE_BIN/generate_keys" -p) || { "$SPARKLE_BIN/generate_keys" >/dev/null; KEY=$("$SPARKLE_BIN/generate_keys" -p); }
  /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" Hoardly/Info.plist 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $KEY" Hoardly/Info.plist
  echo "SUPublicEDKey = $KEY (written to Hoardly/Info.plist — commit it)"
  exit 0
fi

MODE=${1:-full}
if [ "$MODE" != full ]; then
  SIGN=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual)
  [ "$MODE" = --adhoc ] && { /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Hoardly/Info.plist >/dev/null || { echo "Run scripts/release.sh keys first"; exit 1; }; }
else
  : "${TEAM_ID:?set TEAM_ID to your Apple Developer team ID}"
  /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Hoardly/Info.plist >/dev/null || { echo "Run scripts/release.sh keys first"; exit 1; }
  SIGN=(DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS=--timestamp)
fi

VERSION=$(xcodebuild -project Hoardly.xcodeproj -scheme Hoardly -configuration Release -showBuildSettings 2>/dev/null | awk '/ MARKETING_VERSION /{print $3}')
ARCHIVE=build/Hoardly-$VERSION.xcarchive
rm -rf "$ARCHIVE" build/dmg && mkdir -p dist build/dmg
echo "▸ Archiving Hoardly $VERSION"
xcodebuild -project Hoardly.xcodeproj -scheme Hoardly -configuration Release -derivedDataPath $DERIVED \
  -archivePath "$ARCHIVE" archive "${SIGN[@]}" -quiet
APP="$ARCHIVE/Products/Applications/Hoardly.app"
codesign --verify --deep --strict "$APP"

echo "▸ Building DMG"
DMG=dist/Hoardly-$VERSION.dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "Hoardly $VERSION" -srcfolder build/dmg -format UDZO -ov "$DMG" -quiet
rm -rf build/dmg "$ARCHIVE" # keeps stray Hoardly.app copies out of Spotlight/Launchpad

if [ "$MODE" = full ]; then
  codesign --sign "Developer ID Application" --timestamp "$DMG"
  echo "▸ Notarizing (takes a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile hoardly-notary --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature "$DMG"
fi
if [ "$MODE" != --local ]; then
  echo "▸ Appcast"
  rm -rf build/appcast && mkdir -p build/appcast && cp "$DMG" build/appcast/ # only app archives; dist/ also holds the extension zip
  "$SPARKLE_BIN/generate_appcast" build/appcast --download-url-prefix "$REPO/releases/download/v$VERSION/" -o dist/appcast.xml
  echo "Next: gh release create v$VERSION $DMG dist/appcast.xml --title \"Hoardly $VERSION\""
fi
echo "✔ $DMG"
