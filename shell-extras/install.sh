#!/usr/bin/env bash
# Close button + type-search in one supervised quickshell config (`qs -c extras`); replaces the old separate
# closebutton/typesearch configs. Also applies the openWith IPC patch on ii Overview (idempotent).
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
install -Dm644 "$REPO/shell.qml" "$D/shell.qml"
install -Dm644 "$REPO/CloseButton.qml" "$D/CloseButton.qml"
install -Dm644 "$REPO/TypeSearch.qml" "$D/TypeSearch.qml"
install -Dm755 "$REPO/run.sh" "$S"
python3 "$REPO/patch.py" "$O"
sed -i '/close-button/d; /closebutton-run/d; /type-search/d; /typesearch-run/d; /shell-extras/d; /extras-run/d' "$E"
printf -- '-- shell-extras: supervised close button + type-search (one quickshell process)\nhl.on("hyprland.start", function () hl.exec_cmd("%s") end)\n' "$S" >> "$E"
sed -i '/-- >>> type-search >>>/,/-- <<< type-search <<</d; /-- >>> shell-extras >>>/,/-- <<< shell-extras <<</d' "$K"
cat >> "$K" <<'LUA'
-- >>> shell-extras >>>
-- A left click ends type-search's keyboard capture (non-consuming: the click still reaches the target).
hl.bind("mouse:272", hl.dsp.global("typesearch:click"), { non_consuming = true, description = "type-search: release keyboard on click" })
-- <<< shell-extras <<<
LUA
# stop supervisors first (they would restart their qs), then the shells; exact matches, never this script
pkill -f '^bash .*/(closebutton|typesearch|extras)-run\.sh$' || true
pkill -f '^qs -c (closebutton|typesearch|extras)$' || true
rm -rf "$C/closebutton" "$C/typesearch"; rm -f "$H/closebutton-run.sh" "$H/typesearch-run.sh"
sleep 1
setsid -f "$S" >/dev/null 2>&1
echo "Done. Backup: $BACKUP"
