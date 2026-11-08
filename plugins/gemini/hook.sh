#!/bin/sh
# Gemini CLI hook: see plugins/common/hook.sh. Gemini reads the hook's stdout as JSON, so it answers {} (go on).
# Keeps the last event (to check the Gemini format): ~/Library/Logs/Fishbots/gemini-last.json
FISHBOTS_HOOK_LOG=1 "$(dirname "$0")/../common/hook.sh" gemini '*/gemini' '*/gemini-cli/*'
printf '{}\n'
