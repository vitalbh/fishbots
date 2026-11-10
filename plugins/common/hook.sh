#!/bin/sh
# Shared agent hook: forwards the hook JSON (stdin) to Fishbots at POST /<route>, along with where the session is
# (Rex, Herdr, iTerm, Terminal, tmux, WezTerm, kitty…), so clicking the fish takes you to it.
# Never blocks or fails the session.
#   hook.sh <route> [process patterns…]
#     route              the provider's route, without the leading slash ("claude-code", "codex", "agent/<id>"…)
#     process patterns   globs for the agent's executable, used to find its pid outside Rex/iTerm/tmux…
#                        (default: Claude Code's)
#   FISHBOTS_HOOK_LOG=1  keeps the last event in ~/Library/Logs/Fishbots/<route>-last.json (to check a new format)
route="$1"; [ -n "$route" ] || exit 0
shift
set -f   # the patterns are globs for `case`, not for the file system
patterns="${*:-*/claude/versions/* */bin/claude */claude-code/*/claude}"
input=$(cat)

if [ -n "$FISHBOTS_HOOK_LOG" ]; then
  # "agent/aider" → agent-aider-last.json
  mkdir -p "$HOME/Library/Logs/Fishbots" && printf '%s\n' "$input" > "$HOME/Library/Logs/Fishbots/$(printf '%s' "$route" | tr / -)-last.json"
fi

tty=""; app=""; pid=""
if [ -z "$REX_BLOCK$HC_TERMINAL_ID$ITERM_SESSION_ID$WEZTERM_PANE$KITTY_WINDOW_ID$TMUX_PANE" ]; then
  # walks up the parent processes: the tty (Terminal.app and others), the agent's pid and the .app that opened it all
  p=$PPID; i=0
  while [ $i -lt 10 ] && [ -n "$p" ] && [ "$p" -gt 1 ]; do
    line=$(ps -o tty=,comm= -p "$p" 2>/dev/null)
    t=${line%% *}; c=${line#* }; c=$(printf '%s' "$c" | sed 's/^ *//')
    [ -z "$tty" ] && [ -n "$t" ] && [ "$t" != "??" ] && tty=$t
    if [ -z "$pid" ]; then
      for pat in $patterns; do
        case "$c" in $pat) pid=$p; break ;; esac
      done
    fi
    # the outermost .app (Claude Helper lives inside Claude.app): cut at the first ".app/"
    case "$c" in *.app/*) app="${c%%.app/*}.app" ;; esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); i=$((i + 1))
  done
fi

printf '%s' "$input" | curl -s -m 1 -H 'Expect:' -H 'Content-Type: application/json' \
  -H "X-Where-Term: ${TERM_PROGRAM:-}" \
  -H "X-Where-Rex-Session: ${REX_SESSION:-}" \
  -H "X-Where-Rex-Block: ${REX_BLOCK:-}" \
  -H "X-Where-Rex-Bin: $(command -v rex 2>/dev/null)" \
  -H "X-Where-Herdr: ${HC_TERMINAL_ID:-}" \
  -H "X-Where-Iterm: ${ITERM_SESSION_ID:-}" \
  -H "X-Where-Tmux: ${TMUX_PANE:-}" \
  -H "X-Where-Wezterm: ${WEZTERM_PANE:-}" \
  -H "X-Where-Kitty: ${KITTY_WINDOW_ID:-}" \
  -H "X-Where-Tty: ${tty}" \
  -H "X-Where-App: ${app}" \
  -H "X-Where-Pid: ${pid}" \
  -H "X-Where-Entrypoint: ${CLAUDE_CODE_ENTRYPOINT:-}" \
  -H "X-Where-Parent: ${FISHBOTS_PARENT:-}" \
  --data-binary @- "http://127.0.0.1:${FISHBOTS_PORT:-${AQUARIO_PORT:-7777}}/$route" >/dev/null 2>&1
exit 0
