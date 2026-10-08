#!/usr/bin/env bash
# Adds CPU Speed (avg GHz) and Temp (package, °C) rows to the bar's resources popup (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"
BACKUP="$HOME/backups/cpu-info/$(date +%Y%m%d-%H%M%S)"
for f in services/ResourceUsage.qml modules/ii/bar/ResourcesPopup.qml; do mkdir -p "$BACKUP/$(dirname "$f")"; cp "$Q/$f" "$BACKUP/$f"; done
echo "Backed up to $BACKUP"
if patch -d "$Q" -p1 -R --dry-run -s -f < "$REPO/cpu-info.patch" >/dev/null 2>&1; then echo "Already applied."
else patch -d "$Q" -p1 -s -f --no-backup-if-mismatch < "$REPO/cpu-info.patch" && echo "Applied. Restart the shell."; fi
