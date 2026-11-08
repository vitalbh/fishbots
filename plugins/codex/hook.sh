#!/bin/sh
# Codex hook (same format as Claude Code): see plugins/common/hook.sh.
# Keeps the last event (to check the Codex format): ~/Library/Logs/Fishbots/codex-last.json
FISHBOTS_HOOK_LOG=1 exec "$(dirname "$0")/../common/hook.sh" codex '*/codex'
