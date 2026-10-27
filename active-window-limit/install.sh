#!/usr/bin/env bash
# Caps the bar's active-window title width (longer titles end in "..."). Change MAXW and re-run to adjust.
# Done inside ActiveWindow (colLayout width) so the outer bar layout/position stays untouched.
set -euo pipefail
MAXW=${MAXW:-170}
F="$HOME/.config/quickshell/ii/modules/ii/bar/ActiveWindow.qml"
BACKUP="$HOME/backups/active-window-limit/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$F" "$BACKUP/"
sed -i '/\/\/ active-window-limit/d' "$F"
sed -i "s#^        anchors.right: parent.right\$#        width: Math.min(parent.width, $MAXW) // active-window-limit#" "$F"
grep -q active-window-limit "$F" && echo "Applied (max ${MAXW}px). Restart the shell."
