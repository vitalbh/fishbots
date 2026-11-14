#!/bin/sh
# The iPhone app (iOS/): the same engine as the Mac app (scripts/engine-files.txt) plus its own files. It shows the
# Mac's aquarium over the remote listener (Sources/Fishbots/Remote.swift); nothing runs sessions on the phone.
#
#   scripts/ios.sh project   generate build/ios/Fishbots.xcodeproj (XcodeGen: brew install xcodegen) and open it
#   scripts/ios.sh sim       build for the simulator, install and launch it there
#   scripts/ios.sh device    build for the iPhone plugged in (or on the same network) and install it
#
# Signing for a device: FISHBOTS_TEAM=<your team id> (Xcode → Settings → Accounts; a free Apple ID works, the app
# then lasts 7 days). FISHBOTS_IOS_BUNDLE changes the bundle id (it has to be unique to your team).
set -e
cd "$(dirname "$0")/.."
OUT=build/ios
mkdir -p "$OUT"
BUNDLE="${FISHBOTS_IOS_BUNDLE:-io.vitalbh.fishbots.ios}"
TEAM="${FISHBOTS_TEAM:-}"

# the project, from the engine's list: nothing to keep in step by hand
{
  cat <<YML
name: Fishbots
options:
  deploymentTarget: { iOS: "18.0" }
settings:
  base:
    SWIFT_VERSION: "5.0"
    PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE
    DEVELOPMENT_TEAM: "$TEAM"
    CODE_SIGN_STYLE: Automatic
    TARGETED_DEVICE_FAMILY: "1,2"
    MARKETING_VERSION: "0.1"
    CURRENT_PROJECT_VERSION: "1"
    GENERATE_INFOPLIST_FILE: NO
targets:
  Fishbots:
    type: application
    platform: iOS
    info:
      path: Info.plist
      properties:
        CFBundleDisplayName: Fishbots
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait, UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight]
        NSLocalNetworkUsageDescription: "To find your Mac's aquarium on this network."
        NSBonjourServices: [_fishbots._tcp]
        NSCameraUsageDescription: "To read the pairing code on your Mac."
        NSFaceIDUsageDescription: "To confirm it's you before a session on your Mac runs something."
        CFBundleURLTypes: [{ CFBundleURLName: fishbots, CFBundleURLSchemes: [fishbots] }]
    sources:
YML
  grep -v '^#' scripts/engine-files.txt | sed 's#^#      - ../../Sources/Fishbots/#'
  echo "      - ../../Sources/Fishbots/RemoteTLS.swift"
  echo "      - ../../iOS"
} > "$OUT/project.yml"
xcodegen generate --spec "$OUT/project.yml" --project "$OUT" --quiet

case "$1" in
  project)
    open "$OUT/Fishbots.xcodeproj" ;;
  sim)
    PICK='import json,sys; d=[x for k,v in json.load(sys.stdin)["devices"].items() if ".iOS-" in k for x in v if x["name"].startswith("iPhone") and x.get("isAvailable")]; b=[x for x in d if x["state"]=="Booted"]; print((b or d[-1:] or [{"udid":""}])[0]["udid"])'
    SIM=$(xcrun simctl list devices -j | python3 -c "$PICK")
    [ -n "$SIM" ] || { echo "no iPhone simulator (Xcode → Settings → Components)"; exit 1; }
    xcrun simctl boot "$SIM" 2>/dev/null || true
    open -a Simulator
    # by SDK, not by destination: Xcode only lists simulators whose runtime matches its SDK exactly
    xcodebuild -project "$OUT/Fishbots.xcodeproj" -target Fishbots -configuration Debug -sdk iphonesimulator \
      ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES SYMROOT="$PWD/$OUT/products" OBJROOT="$PWD/$OUT/obj" CODE_SIGN_IDENTITY=- -quiet build
    xcrun simctl install "$SIM" "$OUT/products/Debug-iphonesimulator/Fishbots.app"
    xcrun simctl launch "$SIM" "$BUNDLE"
    echo "running in the simulator $SIM" ;;
  device)
    [ -n "$TEAM" ] || { echo "set FISHBOTS_TEAM to your team id (Xcode → Settings → Accounts)"; exit 1; }
    DEV=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone|iPad/ && $0 !~ /unavailable/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) {print $i; exit}}')
    [ -n "$DEV" ] || { echo "no iPhone reachable (plug it in, unlock it, trust this Mac, Developer Mode on)"; exit 1; }
    xcodebuild -project "$OUT/Fishbots.xcodeproj" -scheme Fishbots -configuration Release -destination "generic/platform=iOS" \
      -derivedDataPath "$OUT/derived" -allowProvisioningUpdates -quiet build
    xcrun devicectl device install app --device "$DEV" "$OUT/derived/Build/Products/Release-iphoneos/Fishbots.app"
    xcrun devicectl device process launch --device "$DEV" "$BUNDLE" || true ;;
  *)
    echo "usage: scripts/ios.sh project|sim|device" ;;
esac
