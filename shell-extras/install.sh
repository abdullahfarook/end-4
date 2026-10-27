#!/usr/bin/env bash
# Every shell extra (see README.md) in one supervised quickshell config (`qs -c extras`): installs all *.qml here,
# keybinds.lua into the shell-extras block of keybinds.lua, and the ii patches. Replaces the old separate
# closebutton/typesearch configs. Idempotent; restarts only the extras process, never ii.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
C="$HOME/.config/quickshell"; H="$HOME/.config/hypr/custom"
D="$C/extras"; E="$H/execs.lua"; K="$H/keybinds.lua"; S="$H/extras-run.sh"
O="$C/ii/modules/ii/overview/Overview.qml"
BACKUP="$HOME/backups/shell-extras/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP" "$D"; cp "$E" "$K" "$O" "$BACKUP/"
for old in "$C/closebutton" "$C/typesearch" "$D" "$H/closebutton-run.sh" "$H/typesearch-run.sh"; do
    if [ -e "$old" ]; then cp -r "$old" "$BACKUP/"; fi
done
# the live folder mirrors the repo: an extra removed here disappears there too
rm -f "$D"/*.qml
for q in "$REPO"/*.qml; do install -Dm644 "$q" "$D/$(basename "$q")"; done
install -Dm755 "$REPO/run.sh" "$S"
# ii patches (idempotent): type-search's openWith IPC on Overview
python3 "$REPO/patch.py" "$O"
sed -i '/close-button/d; /closebutton-run/d; /type-search/d; /typesearch-run/d; /shell-extras/d; /extras-run/d' "$E"
printf -- '-- shell-extras: supervised close button + type-search (one quickshell process)\nhl.on("hyprland.start", function () hl.exec_cmd("%s") end)\n' "$S" >> "$E"
sed -i '/-- >>> type-search >>>/,/-- <<< type-search <<</d; /-- >>> shell-extras >>>/,/-- <<< shell-extras <<</d' "$K"
{ echo '-- >>> shell-extras >>>'; cat "$REPO/keybinds.lua"; echo '-- <<< shell-extras <<<'; } >> "$K"
# stop supervisors first (they would restart their qs), then the shells; exact matches, never this script
pkill -f '^bash .*/(closebutton|typesearch|extras)-run\.sh$' || true
pkill -f '^qs -c (closebutton|typesearch|extras)$' || true
rm -rf "$C/closebutton" "$C/typesearch"; rm -f "$H/closebutton-run.sh" "$H/typesearch-run.sh"
sleep 1
setsid -f "$S" >/dev/null 2>&1
echo "Done. Backup: $BACKUP"
