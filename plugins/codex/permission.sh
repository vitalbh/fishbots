#!/bin/sh
# Codex PermissionRequest hook: see plugins/common/permission.sh.
input=$(cat)
. "$(dirname "$0")/session-env.sh"
codex_session_env "$input"
printf '%s' "$input" | exec "$(dirname "$0")/../common/permission.sh" codex
