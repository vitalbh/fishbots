#!/bin/sh
# A build to hand out: Fishbots.app and Fishbots.saver signed with Developer ID (hardened runtime), in a DMG
# notarized by Apple and stapled, so it opens on any Mac without Gatekeeper warnings → build/Fishbots.dmg
#
# Once: a "Developer ID Application" certificate (Xcode → Settings → Accounts → Manage Certificates) and the
# notary credentials in the Keychain:
#   xcrun notarytool store-credentials fishbots --apple-id <apple id> --team-id <team id> --password <app password>
# FISHBOTS_RELEASE_ID picks the certificate (default: the first Developer ID Application found),
# FISHBOTS_NOTARY_PROFILE the credentials (default: fishbots). "scripts/release.sh nonotary" skips Apple.
set -e
cd "$(dirname "$0")/.."
ID="${FISHBOTS_RELEASE_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}"
[ -n "$ID" ] || { echo "no Developer ID Application certificate (Xcode → Settings → Accounts → Manage Certificates)"; exit 1; }
PROFILE="${FISHBOTS_NOTARY_PROFILE:-fishbots}"

scripts/app.sh >/dev/null
scripts/saver.sh >/dev/null
.build/release/Fishbots --check-shaders
# signed in a copy: build/Fishbots.app stays the everyday one (development signing)
rm -rf build/dist && mkdir -p build/dist
ditto build/Fishbots.app build/dist/Fishbots.app
ditto build/Fishbots.saver build/dist/Fishbots.saver

sign() { codesign --force --timestamp --options runtime -s "$ID" "$@"; }
# with a team (FISHBOTS_TEAM, or the one app.sh remembers): iCloud on its production side, which the phones from the
# App Store and TestFlight use for their notifications (CloudNotes.swift), through a Developer ID profile
TEAM="${FISHBOTS_TEAM:-$(cat build/signing-team 2>/dev/null)}"
if [ -n "$TEAM" ] && scripts/mac-signing.sh "$TEAM" release >/dev/null; then
  cp build/mac-signing/release/embedded.provisionprofile build/dist/Fishbots.app/Contents/embedded.provisionprofile
  sign --entitlements build/mac-signing/release/Fishbots.entitlements build/dist/Fishbots.app
  echo "iCloud: production"
else
  rm -f build/dist/Fishbots.app/Contents/embedded.provisionprofile
  sign --entitlements Resources/Fishbots.entitlements build/dist/Fishbots.app
  echo "iCloud: off (no team)"
fi
sign build/dist/Fishbots.saver
codesign --verify --strict --deep build/dist/Fishbots.app build/dist/Fishbots.saver
echo "signed with: $ID"

STAGE=build/dmg DMG=build/Fishbots.dmg
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/dist/Fishbots.app build/dist/Fishbots.saver "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname Fishbots -srcfolder "$STAGE" -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp -s "$ID" "$DMG"

if [ "$1" != "nonotary" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"
fi
echo "done: $DMG"
