#!/usr/bin/env bash
# Adds GPU (VRAM in the bar; clocks/VRAM/temp/power in the popup). Prefers the external GPU (idempotent).
# Run after ../cpu-info/install.sh (the patch builds on it).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"
BACKUP="$HOME/backups/gpu-info/$(date +%Y%m%d-%H%M%S)"
for f in services/ResourceUsage.qml modules/ii/bar/Resources.qml modules/ii/bar/ResourcesPopup.qml; do mkdir -p "$BACKUP/$(dirname "$f")"; cp "$Q/$f" "$BACKUP/$f"; done
install -Dm755 "$REPO/gpu-info.sh" "$HOME/.config/hypr/custom/gpu-info.sh"
if patch -d "$Q" -p1 -R --dry-run -s -f < "$REPO/gpu-info.patch" >/dev/null 2>&1; then echo "Already applied."
else patch -d "$Q" -p1 -s -f --no-backup-if-mismatch < "$REPO/gpu-info.patch" && echo "Applied. Restart the shell."; fi
