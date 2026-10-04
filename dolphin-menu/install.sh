#!/usr/bin/env bash
# Adds "Open in Claude" / "Open in VS Code" to Dolphin's right-click menu (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/kio/servicemenus"
FILE=open-with-dev-tools.desktop
mkdir -p "$DEST"
if [ -e "$DEST/$FILE" ]; then
  b="$HOME/backups/dolphin-menu/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$b"; cp "$DEST/$FILE" "$b/"
fi
install -Dm755 "$REPO/$FILE" "$DEST/$FILE"
echo "Installed. Restart Dolphin if the entries don't show."
