#!/bin/sh
# Connects an agent to Fishbots: merges plugins/<agent>/hooks.json into the agent's settings, pointing at this clone
# (wherever it lives), with a backup. Running it again changes nothing.
#   scripts/install-hooks.sh claude-code [settings.json]     default: ~/.claude/settings.json
#   scripts/install-hooks.sh codex [hooks.json]              default: ~/.codex/hooks.json
#   scripts/install-hooks.sh cursor [hooks.json]             default: ~/.cursor/hooks.json
#   scripts/install-hooks.sh antigravity [hooks.json]        default: ~/.gemini/config/hooks.json (CLI, IDE and app)
#   scripts/install-hooks.sh gemini [settings.json]          default: ~/.gemini/settings.json (Gemini CLI, retired)
#   scripts/install-hooks.sh opencode [plugins folder]       default: ~/.config/opencode/plugins (a link to the plugin)
# The permission hook (it can approve tools on your behalf) only goes in with --permission:
#   scripts/install-hooks.sh claude-code --permission
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
agent="$1"; [ $# -gt 0 ] && shift
perm=0; target=""
for a in "$@"; do case "$a" in --permission) perm=1 ;; *) target="$a" ;; esac; done
case "$agent" in
  claude-code) target="${target:-$HOME/.claude/settings.json}" ;;
  codex)       target="${target:-$HOME/.codex/hooks.json}" ;;
  cursor)      target="${target:-$HOME/.cursor/hooks.json}" ;;
  gemini)      target="${target:-$HOME/.gemini/settings.json}" ;;
  antigravity) target="${target:-$HOME/.gemini/config/hooks.json}" ;;
  opencode)
    # opencode loads every .js in its plugins folder: a link to this clone's plugin (updates come with git pull)
    dir="${target:-$HOME/.config/opencode/plugins}"
    mkdir -p "$dir"
    if [ "$(readlink "$dir/fishbots.js" 2>/dev/null)" = "$ROOT/plugins/opencode/fishbots.js" ]; then
      echo "$dir/fishbots.js: already connected"
    else
      [ -e "$dir/fishbots.js" ] && mv -f "$dir/fishbots.js" "$dir/fishbots.js.bak-fishbots-$(date +%Y%m%d-%H%M%S)"
      ln -s "$ROOT/plugins/opencode/fishbots.js" "$dir/fishbots.js" && echo "$dir/fishbots.js: linked (restart opencode)"
    fi
    exit 0 ;;
  *) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
python3 -I - "$ROOT" "$agent" "$target" "$perm" <<'PY'
import json, os, shutil, sys, time
root, agent, target, perm = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
template = json.load(open(os.path.join(root, "plugins", agent, "hooks.json")))

def commands(entry):
    # Claude Code / Codex: {"hooks": [{"command": …}]}; Cursor: {"command": …}
    return [h.get("command", "") for h in entry.get("hooks", [])] + ([entry["command"]] if "command" in entry else [])

def fix(entry):
    # the template points at ~/Dev/fishbots; this clone may live anywhere
    e = json.loads(json.dumps(entry).replace("~/Dev/fishbots", root))
    return e

data = json.load(open(target)) if os.path.exists(target) else {}
if agent == "antigravity":
    # keyed by hook name, each with its events: Fishbots' hook is the "fishbots" entry
    if "fishbots" in data:
        print(f"{target}: already connected"); sys.exit()
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.exists(target):
        shutil.copy(target, target + ".bak-fishbots-" + time.strftime("%Y%m%d-%H%M%S"))
    data["fishbots"] = fix(template["fishbots"])
    json.dump(data, open(target, "w"), indent=2, ensure_ascii=False); open(target, "a").write("\n")
    print(f"{target}: connected (the CLI, the IDE and the app share it)"); sys.exit()
if agent == "cursor": data.setdefault("version", 1)
hooks = data.setdefault("hooks", {})
added = skipped = 0
for event, entries in template["hooks"].items():
    for entry in entries:
        entry = fix(entry)
        cmds = commands(entry)
        # the same script from any clone (~/Dev/fishbots, an absolute path, elsewhere) counts as already there
        def key(c): return c[c.rfind("/plugins/" + agent + "/"):] if "/plugins/" + agent + "/" in c else c
        have = {key(c) for e in hooks.get(event, []) for c in commands(e)}
        if any(key(c) in have for c in cmds):
            continue
        if any(c.endswith("/permission.sh") for c in cmds) and not perm:
            skipped += 1; continue
        hooks.setdefault(event, []).append(entry)
        added += 1
if added == 0:
    print(f"{target}: already connected" + (f" ({skipped} permission hook(s) left out: use --permission)" if skipped else ""))
    sys.exit()
os.makedirs(os.path.dirname(target), exist_ok=True)
if os.path.exists(target):
    shutil.copy(target, target + ".bak-fishbots-" + time.strftime("%Y%m%d-%H%M%S"))
json.dump(data, open(target, "w"), indent=2, ensure_ascii=False); open(target, "a").write("\n")
print(f"{target}: {added} hook(s) added" + (f", {skipped} permission hook(s) left out (use --permission)" if skipped else ""))
PY
