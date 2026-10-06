#!/usr/bin/env bash
# Restore illogical-impulse shell settings (config.json). Backs up the live copy first.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.config/illogical-impulse/config.json"
B="$HOME/backups/illogical-config/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$B" "$(dirname "$DEST")"
[ -f "$DEST" ] && cp "$DEST" "$B/"
install -Dm644 "$REPO/config.json" "$DEST"
echo "Installed config.json (backup in $B). The shell reloads it automatically."
