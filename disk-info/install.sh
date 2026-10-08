#!/usr/bin/env bash
# Adds root-filesystem fill (hard_drive icon in the bar; Used/Free/Total in the popup) (idempotent).
# Run after ../cpu-info and ../gpu-info install.sh (the patch builds on them).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"
BACKUP="$HOME/backups/disk-info/$(date +%Y%m%d-%H%M%S)"
for f in modules/ii/bar/BarContent.qml services/ResourceUsage.qml modules/ii/bar/Resources.qml modules/ii/bar/ResourcesPopup.qml; do mkdir -p "$BACKUP/$(dirname "$f")"; cp "$Q/$f" "$BACKUP/$f"; done
echo "Backed up to $BACKUP"
if patch -d "$Q" -p1 -R --dry-run -s -f < "$REPO/disk-info.patch" >/dev/null 2>&1; then echo "Already applied."
else patch -d "$Q" -p1 -s -f --no-backup-if-mismatch < "$REPO/disk-info.patch" && echo "Applied. Restart the shell."; fi
