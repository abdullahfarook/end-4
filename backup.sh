#!/usr/bin/env bash
# Snapshots the live config (hypr, quickshell ii, illogical-impulse settings, dolphin menu) to ~/backups/full/<timestamp>/.
# Read-only on the live config. Restore a piece by copying it back. Keeps the 10 newest snapshots.
set -euo pipefail
ROOT="$HOME/backups/full"
BACKUP="$ROOT/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for src in "$HOME/.config/hypr" "$HOME/.config/quickshell/ii" "$HOME/.config/illogical-impulse" "$HOME/.local/share/kio/servicemenus"; do
    [ -e "$src" ] || continue
    dest="$BACKUP/${src#$HOME/}"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
done
ls -1dt "$ROOT"/*/ | tail -n +11 | xargs -r rm -rf
echo "Backed up to $BACKUP"
