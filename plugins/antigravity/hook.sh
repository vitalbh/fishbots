#!/bin/sh
# Antigravity hook (the CLI `agy`, the IDE and the app share ~/.gemini/config/hooks.json): see plugins/common/hook.sh.
#   hook.sh <Event>   Antigravity's payload doesn't name its event, so each one calls this with its name.
# Never in PreToolUse: there a hook must decide, and a failure blocks the tool. Answers what each event expects:
# Stop must decide ("stop" lets it stop, never "continue"); the others take {}.
# Keeps the last event (to check the format): ~/Library/Logs/Fishbots/antigravity-last.json
event="$1"
input=$(cat)
# {"hookEvent":"<Event>", …the payload's own fields}
input="${input#"${input%%[![:space:]]*}"}"   # without leading blanks, it starts with "{"
body="{\"hookEvent\":\"$event\",${input#\{}"
printf '%s' "$body" | FISHBOTS_HOOK_LOG=1 "$(dirname "$0")/../common/hook.sh" antigravity '*/agy' '*/antigravity*'
if [ "$event" = "Stop" ]; then printf '{"decision":"stop"}\n'; else printf '{}\n'; fi
