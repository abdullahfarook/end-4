#!/usr/bin/env bash
# Forced close button (top-right corner) on windows whose app has none; runs as its own quickshell config (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
D="$HOME/.config/quickshell/closebutton"; E="$HOME/.config/hypr/custom/execs.lua"
BACKUP="$HOME/backups/close-button/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP" "$D"; cp "$E" "$BACKUP/"; cp -r "$D/." "$BACKUP/" 2>/dev/null || true
install -Dm644 "$REPO/shell.qml" "$D/shell.qml"
grep -q "close-button" "$E" || printf '\n-- close-button: forced close button on windows without one\nhl.on("hyprland.start", function () hl.exec_cmd("qs -c closebutton") end)\n' >> "$E"
K="$HOME/.config/hypr/custom/keybinds.lua"; cp "$K" "$BACKUP/keybinds.lua.bak"
grep -q "close-button-drag" "$K" || { echo >> "$K"; cat "$REPO/keybinds.lua" >> "$K"; }
pkill -f "qs -c closebutton" || true
nohup qs -c closebutton >/dev/null 2>&1 & disown
echo "Done."
