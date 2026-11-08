#!/bin/sh
# Builds in release mode and assembles build/Fishbots.app (signed).
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Fishbots.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Fishbots "$APP/Contents/MacOS/Fishbots"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate with: swift scripts/make-icon.swift
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Fishbots</string>
  <key>CFBundleDisplayName</key><string>Fishbots</string>
  <key>CFBundleIdentifier</key><string>io.vitalbh.fishbots</string>
  <key>CFBundleExecutable</key><string>Fishbots</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
  <key>CFBundleLocalizations</key><array><string>pt-BR</string><string>en</string></array>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Para você falar com o peixinho: a sua voz vira a resposta para a sessão.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Para transcrever o que você fala ao peixinho (no próprio Mac quando possível).</string>
  <key>NSAudioCaptureUsageDescription</key><string>Para os visualizadores dançarem com o Spotify ou o Música: só o som desses apps, analisado na hora, nada é gravado.</string>
  <key>NSAppleEventsUsageDescription</key><string>Para levar você até o terminal de uma sessão quando você clica no peixe.</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
</dict></plist>
PLIST
# the permission prompts in English (the Info.plist above has the Portuguese ones)
mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/pt-BR.lproj"
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<STRINGS
NSMicrophoneUsageDescription = "So you can talk to the little fish: your voice becomes the reply to the session.";
NSSpeechRecognitionUsageDescription = "To transcribe what you say to the little fish (on the Mac itself when possible).";
NSAudioCaptureUsageDescription = "So the visualizers dance to Spotify or Music: only those apps' sound, analyzed on the fly, nothing recorded.";
NSAppleEventsUsageDescription = "To take you to a session's terminal when you click its fish.";
STRINGS
touch "$APP/Contents/Resources/pt-BR.lproj/InfoPlist.strings"
# With a "Fishbots Dev" certificate in the Keychain (self-signed, free), the signature stays
# stable across builds and macOS doesn't ask for the automation permission again. Without it: ad hoc.
ID="${FISHBOTS_SIGN_ID:-Fishbots Dev}"
if security find-certificate -c "$ID" >/dev/null 2>&1; then
  codesign -s "$ID" --force "$APP" >/dev/null && echo "signed with: $ID"
else
  codesign -s - --force "$APP" >/dev/null && echo "signed ad hoc (create the \"$ID\" certificate so it doesn't ask for permission on every build)"
fi
echo "done: $APP"
