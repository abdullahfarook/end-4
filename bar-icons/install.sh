#!/usr/bin/env bash
# Consistent bar icon buttons: the upstream sidebar button gets the same fixed 30x30 box / 20px icon as the custom buttons (idempotent).
set -euo pipefail
Q="$HOME/.config/quickshell/ii/modules/ii/bar"; F="$Q/LeftSidebarButton.qml"
BACKUP="$HOME/backups/bar-icons/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP"; cp "$F" "$BACKUP/"
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("implicitWidth: distroIcon.width + buttonPadding * 2", "implicitWidth: 30")
s = s.replace("implicitHeight: distroIcon.height + buttonPadding * 2", "implicitHeight: 30")
s = s.replace("        width: 19.5\n        height: 19.5\n", "        width: 20\n        height: 20\n")
open(p, "w").write(s)
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
