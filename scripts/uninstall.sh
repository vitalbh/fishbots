#!/bin/sh
# Takes Fishbots off this Mac: first the hooks it put in each agent (they point at this clone and would fail once it's
# gone), then, asking each time, its data, the screen saver and the app. Backups of every settings file it touches
# stay next to it (.bak-fishbots-…).
#   scripts/uninstall.sh        asks before deleting anything that isn't a hook
#   scripts/uninstall.sh -y     deletes everything without asking
cd "$(dirname "$0")/.."
yes=0; [ "$1" = "-y" ] && yes=1
ask() { [ $yes = 1 ] && return 0; printf '%s [y/N] ' "$1"; read -r r; case "$r" in y|Y) return 0 ;; esac; return 1; }

# the app first, so it doesn't write its files again on the way out
if pgrep -xq Fishbots; then osascript -e 'tell application id "io.vitalbh.fishbots" to quit' >/dev/null 2>&1; sleep 1; fi

echo "Agent hooks:"
# Claude Code: the usual folder and the ones CLAUDE_CONFIG_DIR points at (~/.claude-work…)
for f in "$HOME"/.claude/settings.json "$HOME"/.claude-*/settings.json; do
  [ -f "$f" ] && sh scripts/install-hooks.sh claude-code "$f" --remove
done
[ -f "$HOME/.codex/hooks.json" ] && sh scripts/install-hooks.sh codex --remove
[ -f "$HOME/.cursor/hooks.json" ] && sh scripts/install-hooks.sh cursor --remove
[ -f "$HOME/.gemini/config/hooks.json" ] && sh scripts/install-hooks.sh antigravity --remove
[ -f "$HOME/.gemini/settings.json" ] && sh scripts/install-hooks.sh gemini --remove
[ -L "$HOME/.config/opencode/plugins/fishbots.js" ] && sh scripts/install-hooks.sh opencode --remove
# the hooks' scripts the app installed (Preferences → Agents → Connect)
[ -d "$HOME/.local/share/fishbots" ] && rm -rf "$HOME/.local/share/fishbots" && echo "$HOME/.local/share/fishbots: removed"

DATA="$HOME/Library/Application Support/Fishbots"
if [ -d "$DATA" ] && ask "Delete its data (paired devices, keys, history, assistant, packs) in $DATA?"; then
  rm -rf "$DATA" "$HOME/Library/Logs/Fishbots"
  defaults delete io.vitalbh.fishbots >/dev/null 2>&1
  echo "data deleted"
fi
SAVER="$HOME/Library/Screen Savers/Fishbots.saver"
if [ -d "$SAVER" ] && ask "Remove the screen saver?"; then rm -rf "$SAVER" && echo "screen saver removed"; fi
for app in /Applications/Fishbots.app "$HOME/Applications/Fishbots.app" build/Fishbots.app; do
  if [ -d "$app" ] && ask "Delete $app?"; then rm -rf "$app" && echo "$app deleted"; fi
done
echo "Done. Restart any agent still open so it drops the hooks. On the iPhone, just delete the app."
