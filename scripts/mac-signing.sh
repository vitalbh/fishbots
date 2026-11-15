#!/bin/sh
# The Mac app's provisioning profile and entitlements for iCloud (scripts/app.sh calls it): builds a one-file app with
# the same bundle id and entitlements through Xcode, which registers what's missing with Apple and downloads the
# profile, and keeps both in build/mac-signing. Prints the signing identity to use (its SHA-1).
#   scripts/mac-signing.sh <team id>
set -e
cd "$(dirname "$0")/.."
TEAM="$1"; [ -n "$TEAM" ] || { echo "usage: scripts/mac-signing.sh <team id>" >&2; exit 2; }
BUNDLE=io.vitalbh.fishbots
CONTAINER="${FISHBOTS_CLOUD_CONTAINER:-iCloud.io.vitalbh.fishbots}"
DIR=build/mac-signing
PROFILE="$DIR/embedded.provisionprofile"
mkdir -p "$DIR/src"

fresh() {
  [ -f "$PROFILE" ] && [ "$(cat "$DIR/team" 2>/dev/null)" = "$TEAM" ] || return 1
  # more than a week left
  security cms -D -i "$PROFILE" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null |
    python3 -c 'import sys,datetime as d; e=d.datetime.fromisoformat(sys.stdin.read().strip().replace("Z","+00:00")); sys.exit(0 if e-d.datetime.now(d.timezone.utc)>d.timedelta(days=7) else 1)'
}

if ! fresh; then
  command -v xcodegen >/dev/null || { echo "xcodegen is needed (brew install xcodegen)" >&2; exit 1; }
  echo 'print("fishbots signing stub")' > "$DIR/src/main.swift"
  cat > "$DIR/project.yml" <<YML
name: FishbotsSigning
options: { deploymentTarget: { macOS: "15.0" } }
settings:
  base: { SWIFT_VERSION: "5.0", DEVELOPMENT_TEAM: "$TEAM", CODE_SIGN_STYLE: Automatic, PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE, GENERATE_INFOPLIST_FILE: YES, PRODUCT_NAME: Fishbots }
targets:
  Stub:
    type: application
    platform: macOS
    entitlements:
      path: Stub.entitlements
      properties:
        com.apple.developer.icloud-container-identifiers: [$CONTAINER]
        com.apple.developer.icloud-services: [CloudKit]
    sources: [src]
YML
  xcodegen generate --spec "$DIR/project.yml" --project "$DIR" --quiet >&2
  xcodebuild -project "$DIR/FishbotsSigning.xcodeproj" -scheme Stub -configuration Debug -destination 'platform=macOS' \
    SYMROOT="$PWD/$DIR/out" OBJROOT="$PWD/$DIR/obj" -allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet build >&2
  cp "$DIR/out/Debug/Fishbots.app/Contents/embedded.provisionprofile" "$PROFILE"
  codesign -d -vvv "$DIR/out/Debug/Fishbots.app" 2>&1 | sed -n 's/^Authority=\(Apple Development: .*\)/\1/p' | head -1 > "$DIR/identity-name"
  echo "$TEAM" > "$DIR/team"
fi

# the entitlements the app is signed with: iCloud, plus what the hardened runtime would otherwise block
cat > "$DIR/Fishbots.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.application-identifier</key><string>$TEAM.$BUNDLE</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM</string>
  <key>com.apple.developer.icloud-container-identifiers</key><array><string>$CONTAINER</string></array>
  <key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>
  <key>com.apple.security.device.audio-input</key><true/>
  <key>com.apple.security.automation.apple-events</key><true/>
</dict></plist>
PLIST
# the identity by its hash: the name alone can match several certificates
name=$(cat "$DIR/identity-name")
id=$(security find-identity -v -p codesigning | grep -F "\"$name\"" | awk '{print $2}' | head -1)
[ -n "$id" ] || { echo "no signing identity for team $TEAM in the Keychain" >&2; exit 1; }
echo "$id"
