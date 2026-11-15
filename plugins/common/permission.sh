#!/bin/sh
# Shared PermissionRequest hook: asks Fishbots (POST /<route>/permission) and waits for you to click Allow or Deny.
# The request still shows in the terminal at the same time; whichever answers first wins.
# Without the app open, or without a decision, it exits silently and the normal flow goes on.
#   permission.sh <route>      e.g. "claude-code", "codex"
# The reply is Claude Code's format, which Codex shares; an agent with another format needs its own script.
route="$1"; [ -n "$route" ] || exit 0
input=$(cat)
resp=$(printf '%s' "$input" | curl -s -m 290 -H 'Expect:' -H 'Content-Type: application/json' \
  -H "X-Where-Term: ${TERM_PROGRAM:-}" -H "X-Where-Rex-Session: ${REX_SESSION:-}" -H "X-Where-Rex-Block: ${REX_BLOCK:-}" \
  --data-binary @- "http://127.0.0.1:${FISHBOTS_PORT:-7777}/$route/permission" 2>/dev/null)
case "$resp" in
  *'"behavior"'*) printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":%s}}' "$resp" ;;
esac
exit 0
