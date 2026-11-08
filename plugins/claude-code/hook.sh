#!/bin/sh
# Claude Code hook: see plugins/common/hook.sh.
exec "$(dirname "$0")/../common/hook.sh" claude-code '*/claude/versions/*' '*/bin/claude' '*/claude-code/*/claude'
