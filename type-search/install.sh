#!/usr/bin/env bash
# Type-to-search after a workspace switch; own quickshell config + openWith IPC patch on ii Overview (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
D="$HOME/.config/quickshell/typesearch"; E="$HOME/.config/hypr/custom/execs.lua"
O="$HOME/.config/quickshell/ii/modules/ii/overview/Overview.qml"
S="$HOME/.config/hypr/custom/typesearch-run.sh"
BACKUP="$HOME/backups/type-search/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP" "$D"; cp "$E" "$O" "$BACKUP/"; cp -r "$D/." "$BACKUP/" 2>/dev/null || true
install -Dm644 "$REPO/shell.qml" "$D/shell.qml"
install -Dm755 "$REPO/run.sh" "$S"
python3 "$REPO/patch.py" "$O"
sed -i '/type-search/d; /typesearch-run/d' "$E"
printf -- '-- type-search: type after workspace switch opens launcher search\nhl.on("hyprland.start", function () hl.exec_cmd("%s") end)\n' "$S" >> "$E"
pkill -f 'typesearch-run.sh$' || true
pkill -f '^qs -c typesearch' || true
sleep 1
setsid -f "$S" >/dev/null 2>&1
echo "Done. Restart ii shell to load the IPC patch: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
