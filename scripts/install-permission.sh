#!/bin/sh
# Turns on "answer permissions from Fishbots": adds the PermissionRequest hook (plugins/claude-code/permission.sh)
# to the Claude Code settings, with a backup. Run it yourself: the hook can approve tools on your behalf.
#   scripts/install-permission.sh ~/.claude/settings.json   (one or more settings files)
HOOK="$(cd "$(dirname "$0")/.." && pwd)/plugins/claude-code/permission.sh"
for f in "$@"; do
  python3 -I - "$f" "$HOOK" <<'PY'
import json, shutil, sys, time
f, hook = sys.argv[1], sys.argv[2]
d = json.load(open(f)); lst = d.setdefault("hooks", {}).setdefault("PermissionRequest", [])
if any(hook in h.get("command", "") for e in lst for h in e.get("hooks", [])):
    print(f, "already there"); sys.exit()
shutil.copy(f, f + ".bak-fishbots-" + time.strftime("%Y%m%d-%H%M%S"))
lst.append({"matcher": "*", "hooks": [{"type": "command", "command": hook, "timeout": 300}]})
json.dump(d, open(f, "w"), indent=2, ensure_ascii=False); open(f, "a").write("\n")
print(f, "→ permission hook added")
PY
done
