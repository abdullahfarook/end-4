#!/usr/bin/env bash
# Forced close button on windows whose app has none; runs as its own quickshell config, supervised (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
D="$HOME/.config/quickshell/closebutton"; E="$HOME/.config/hypr/custom/execs.lua"
S="$HOME/.config/hypr/custom/closebutton-run.sh"
BACKUP="$HOME/backups/close-button/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP" "$D"; cp "$E" "$BACKUP/"; cp -r "$D/." "$BACKUP/" 2>/dev/null || true
install -Dm644 "$REPO/shell.qml" "$D/shell.qml"
install -Dm755 "$REPO/closebutton-run.sh" "$S"
sed -i '/close-button/d; /qs -c closebutton/d' "$E"
printf -- '-- close-button: supervised forced close button on windows without one\nhl.on("hyprland.start", function () hl.exec_cmd("%s") end)\n' "$S" >> "$E"
# stop old instances (exact match on the process, not this shell), then start the supervisor
pkill -f '^bash .*closebutton-run.sh' || true
pkill -f '^qs -c closebutton' || true
setsid -f "$S" >/dev/null 2>&1
echo "Done."
