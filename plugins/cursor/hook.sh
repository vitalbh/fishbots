#!/bin/sh
# Cursor hook (the app's agent and cursor-agent): see plugins/common/hook.sh.
# While the Cursor provider is being written, every event is also appended to
# ~/Library/Logs/Fishbots/cursor-events.jsonl (rotated at 5 MB) to learn the format.
log="$HOME/Library/Logs/Fishbots/cursor-events.jsonl"
input=$(cat)
mkdir -p "$(dirname "$log")"
[ -f "$log" ] && [ "$(wc -c < "$log")" -gt 5000000 ] && mv -f "$log" "$log.1"
# one write per event (hooks run in parallel, and two writes per event got interleaved)
printf '%s\n' "$(printf '%s' "$input" | tr '\n' ' ')" >> "$log"
printf '%s' "$input" | FISHBOTS_HOOK_LOG=1 exec "$(dirname "$0")/../common/hook.sh" cursor '*/cursor-agent' '*/cursor-agent/*'
