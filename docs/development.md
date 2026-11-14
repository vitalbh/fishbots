# Development

Built in Swift, with Metal (water, light and fish drawn in the shader) and a custom synthesizer on AVAudioEngine.

The code, protocol, CLI, scripts and file names are in English. The interface is in Portuguese or English (Preferências → Geral → Idioma; automatic follows the Mac's language); menu items and labels below are quoted in Portuguese, with a short gloss. Fishbots was called Aquário before; its old settings, folders and `AQUARIO_*` env vars are picked up automatically. The old Portuguese names (protocol fields and states, routes, headers, CLI commands, script arguments, env vars, `config.json` keys, `ir.sh`) are still accepted.

## Building and running

```sh
swift run -c release            # or: scripts/app.sh  →  build/Fishbots.app
FISHBOTS_DEMO=1 swift run -c release   # opens straight into demo mode
open --env FISHBOTS_HOUR=18.5 build/Fishbots.app   # see another hour's colors (dawn, late afternoon, night)
open --env FISHBOTS_GPUSTATS=1 build/Fishbots.app  # prints the GPU time per frame every 5 s (FISHBOTS_BLOOM=0 turns the glow off)
open --env FISHBOTS_CATALOG=file://$PWD/community/index.json build/Fishbots.app   # the pack catalog from this checkout (off: none)
open --env FISHBOTS_PACK_BUDGET_MS=50 build/Fishbots.app   # how slow (ms per frame) before a pack is looked into (default 33)
```

To avoid the automation permission prompt on every build, create a self-signed **Code Signing** certificate named `Fishbots Dev` in Keychain Access (Certificate Assistant → Create a Certificate). `scripts/app.sh` will use it.

To hand the app out, `scripts/release.sh` signs the app and the screen saver with a Developer ID certificate and builds `build/Fishbots.dmg`, notarized and stapled (setup in the script's header).

## Uninstalling

**Uninstalling:** the agents' hooks point at this clone, so take them out before deleting it, or every session keeps calling a script that isn't there: `scripts/uninstall.sh` removes them from every agent (each settings file keeps a backup next to it), then asks before deleting the data in `~/Library/Application Support/Fishbots`, the screen saver and the app. One agent alone: `scripts/install-hooks.sh <agent> --remove`. Without a terminal, Preferences → General → Agents → **Disconnect agents…** removes the hooks. On the iPhone, deleting the app is enough: a reinstall starts unpaired (the Keychain outlives the app, so the app forgets the old pairing itself), and revoking the device on the Mac (Preferences → General → Other devices) shuts it out from that side.

## Languages and the icon

**Languages:** the interface texts go through `tr(...)` (Sources/Fishbots/L10n.swift): the Portuguese text is the key and `L10nEnglish.swift` has the English. When adding a text, add its English too; `python3 scripts/l10n-check.py` lists what's missing. A pack's theme can bring its name in both languages with `"names": {"en": "…"}`.

The app icon is drawn by `scripts/make-icon.swift` (`swift scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`).

## Seeing every mechanic

To see it all in action: `open --env FISHBOTS_FAST=1 build/Fishbots.app` (shortens the timings) and `scripts/tour.sh`, which stages each mechanic with test fish and tells you in the terminal what to look at.
