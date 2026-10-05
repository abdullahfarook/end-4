#!/usr/bin/env bash
# Bar performance popup (profiles + Acer fan control) and fan scripts (idempotent). The permission service needs sudo (run once).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"
BACKUP="$HOME/backups/fan-control/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$Q/modules/ii/bar/UtilButtons.qml" "$BACKUP/"
echo "Backed up to $BACKUP"
for f in fan-control.sh fan-restore.sh; do install -Dm755 "$REPO/$f" "$HOME/.config/hypr/custom/$f"; done
if patch -d "$Q" -p1 -R --dry-run -s -f < "$REPO/fan-control.patch" >/dev/null 2>&1; then echo "QML patch already applied."
else patch -d "$Q" -p1 -s -f --no-backup-if-mismatch < "$REPO/fan-control.patch" && echo "QML patch applied (restart the shell)."; fi
EXECS="$HOME/.config/hypr/custom/execs.lua"
grep -q fan-restore.sh "$EXECS" || printf '\n-- fan-control: re-apply saved fan speeds at login and after resume\nhl.on("hyprland.start", function () hl.exec_cmd("~/.config/hypr/custom/fan-restore.sh") end)\n' >> "$EXECS"
if ! systemctl is-enabled fan-control-perms.service >/dev/null 2>&1; then
    echo "Run once: sudo install -m644 $REPO/fan-control-perms.service /etc/systemd/system/ && sudo systemctl enable --now fan-control-perms.service"
fi
