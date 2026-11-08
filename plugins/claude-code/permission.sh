#!/bin/sh
# Claude Code PermissionRequest hook: see plugins/common/permission.sh.
exec "$(dirname "$0")/../common/permission.sh" claude-code
