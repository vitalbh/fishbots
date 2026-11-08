#!/bin/sh
# Codex PermissionRequest hook: see plugins/common/permission.sh.
exec "$(dirname "$0")/../common/permission.sh" codex
