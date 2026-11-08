#!/bin/sh
# Installs or removes example plugins (as links) in the Fishbots folder.
#   scripts/plugins.sh                 lists the installed and the example plugins
#   scripts/plugins.sh install github mac
#   scripts/plugins.sh remove github
cd "$(dirname "$0")/.."
DEST="$HOME/Library/Application Support/Fishbots/plugins"
mkdir -p "$DEST"
action="$1"; [ $# -gt 0 ] && shift
case "$action" in
  install|instalar) for n in "$@"; do f=$(ls plugins/examples/"$n".* 2>/dev/null | head -1)
              [ -n "$f" ] || { echo "not found: plugins/examples/$n.*" >&2; continue; }
              ln -sf "$PWD/$f" "$DEST/$(basename "$f")" && echo "installed: $(basename "$f")"; done ;;
  remove|remover) for n in "$@"; do rm -f "$DEST/$n".* && echo "removed: $n"; done ;;
  *)        echo "installed ($DEST):"; ls "$DEST" | sed 's/^/  /'
            echo "examples:"; ls plugins/examples | sed 's/^/  /' ;;
esac
