#!/usr/bin/env bash
# Stops Hyprland from warping the pointer (e.g. back to a dialog that opens or takes focus): cursor.no_warps = true (idempotent).
set -euo pipefail
G="$HOME/.config/hypr/hyprland/general.lua"
BACKUP="$HOME/backups/cursor/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$G" "$BACKUP/"
echo "Backed up to $BACKUP"
if grep -q 'no_warps' "$G"; then
    sed -i 's/no_warps *= *[a-z]*/no_warps = true/' "$G"
else
    sed -i 's/^\( *\)hotspot_padding = \([0-9]*\)$/\1hotspot_padding = \2,\n\1no_warps = true/' "$G"
fi
grep -q 'no_warps = true' "$G" || { echo "Could not set no_warps; add it to the cursor block of $G by hand." >&2; exit 1; }
hyprctl reload >/dev/null 2>&1 || true
echo "Done."
