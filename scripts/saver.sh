#!/bin/sh
# Builds the screen saver (build/Fishbots.saver) with the same engine as the app and, with "install",
# copies it to ~/Library/Screen Savers. Then: System Settings → Screen Saver → Fishbots.
set -e
cd "$(dirname "$0")/.."
SRC=Sources/Fishbots
OUT="build/Fishbots.saver"   # keep the file name ASCII (the settings pane got lost with "Aquário.saver"); the name in the list is CFBundleName
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
swiftc -O -swift-version 5 -module-name FishbotsSaver -emit-library -Xlinker -bundle \
  -target "$(uname -m)-apple-macos15.0" \
  -o "$OUT/Contents/MacOS/FishbotsSaver" \
  $SRC/Renderer.swift $SRC/Shaders.swift $SRC/Tank.swift $SRC/TankSprites.swift $SRC/Steering.swift $SRC/Fish.swift $SRC/Math.swift $SRC/Sky.swift $SRC/Pearls.swift $SRC/Gauges.swift $SRC/Motes.swift $SRC/Weeds.swift $SRC/Scenery.swift $SRC/Motifs.swift $SRC/Synth.swift $SRC/Visual.swift $SRC/Fauna.swift $SRC/Scene.swift $SRC/Env.swift $SRC/Theme.swift $SRC/Visualizers.swift $SRC/FishKinds.swift $SRC/ToolBehaviors.swift $SRC/PackFauna.swift $SRC/Packs.swift $SRC/Generator.swift $SRC/L10n.swift $SRC/L10nEnglish.swift \
  Saver/FishbotsSaver.swift \
  -framework ScreenSaver -framework MetalKit -framework Metal -framework AppKit -framework AVFoundation
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Fishbots</string>
  <key>CFBundleDisplayName</key><string>Fishbots</string>
  <key>CFBundleIdentifier</key><string>io.vitalbh.fishbots.saver</string>
  <key>CFBundleExecutable</key><string>FishbotsSaver</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSPrincipalClass</key><string>FishbotsSaverView</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
ID="${FISHBOTS_SIGN_ID:-Fishbots Dev}"
if security find-certificate -c "$ID" >/dev/null 2>&1; then codesign -s "$ID" --force "$OUT" >/dev/null
else codesign -s - --force "$OUT" >/dev/null; fi
echo "done: $OUT"
if [ "$1" = "install" ] || [ "$1" = "instalar" ]; then
  mkdir -p "$HOME/Library/Screen Savers"
  rm -rf "$HOME/Library/Screen Savers/Aquário.saver" "$HOME/Library/Screen Savers/Aquario.saver" "$HOME/Library/Screen Savers/Fishbots.saver"
  cp -R "$OUT" "$HOME/Library/Screen Savers/"
  # the screen saver process keeps the old version in memory: kill it so it reloads
  killall legacyScreenSaver 2>/dev/null || true
  echo "installed in ~/Library/Screen Savers"
fi
