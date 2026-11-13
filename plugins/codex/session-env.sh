# Sourced by the Codex hooks (hook.sh, permission.sh). When Codex's app-server daemon runs, the hooks run in it
# ("codex app-server"), with the daemon's environment: the terminal it was started from (maybe long ago, maybe
# closed, maybe another agent's pane now) and nothing of the session's own (FISHBOTS_PORT, FISHBOTS_PARENT, its
# pane). Then the session's terminal process (a codex with a tty working in the hook's folder) lends its variables;
# if there isn't exactly one, nothing says where the session is, which is better than a wrong pane.
#   codex_session_env "<the hook's JSON>"
codex_session_env() {
  p=$PPID; i=0; daemon=""
  while [ $i -lt 5 ] && [ "${p:-1}" -gt 1 ]; do
    case "$(ps -o command= -p "$p" 2>/dev/null)" in *codex*" app-server"*) daemon=1; break ;; esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); i=$((i + 1))
  done
  [ -n "$daemon" ] || return 0
  vars="REX_SESSION REX_BLOCK HC_TERMINAL_ID ITERM_SESSION_ID TMUX_PANE WEZTERM_PANE KITTY_WINDOW_ID TERM_PROGRAM FISHBOTS_PARENT FISHBOTS_PORT"
  for v in $vars; do unset "$v"; done
  cwd=$(printf '%s' "$1" | sed -n 's/.*"cwd" *: *"\([^"]*\)".*/\1/p' | head -1)
  [ -n "$cwd" ] || return 0
  found=""; port=""; ports=0
  for pid in $(ps -axo pid=,tty=,comm= | awk '$2 != "??" && ($3 == "codex" || $3 ~ /\/codex$/) { print $1 }'); do
    case "$(ps -o command= -p "$pid" 2>/dev/null)" in *" app-server"*) continue ;; esac
    [ "$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')" = "$cwd" ] || continue
    p_=$(ps eww -o command= -p "$pid" 2>/dev/null | tr ' ' '\n' | sed -n 's/^FISHBOTS_PORT=//p' | tail -1)
    [ $ports -eq 0 ] && port="$p_"; [ "$p_" = "$port" ] || port="?"; ports=$((ports + 1))
    found=$pid
  done
  if [ $ports -gt 1 ]; then
    # two sessions in that folder: can't tell which pane, but if they report to the same aquarium, that one
    case "$port" in ''|*[!0-9]*) ;; *) export FISHBOTS_PORT="$port" ;; esac
    return 0
  fi
  [ -n "$found" ] || return 0
  envs=$(ps eww -o command= -p "$found" 2>/dev/null | tr ' ' '\n')
  for v in $vars; do
    val=$(printf '%s\n' "$envs" | sed -n "s/^$v=//p" | tail -1)
    case "$val" in ''|*[!A-Za-z0-9:%._/-]*) ;; *) export "$v=$val" ;; esac
  done
  # where the walk up for the tty and the .app starts (plugins/common/hook.sh)
  export FISHBOTS_HOOK_FROM="$found"
}
