#!/bin/sh
# Installs the startup AUR auto-updater. Edit aur-packages.list in this folder and re-run to change the packages.
set -e
here=$(cd "$(dirname "$0")" && pwd)
b=~/backups/aur-autoupdate/$(date +%Y%m%d-%H%M%S); mkdir -p "$b" ~/.config/aur-autoupdate
cp ~/.config/aur-autoupdate/aur-packages.list ~/.config/hypr/custom/aur-autoupdate.sh ~/.config/hypr/custom/execs.lua "$b/" 2>/dev/null || true
install -m755 "$here/aur-autoupdate.sh" ~/.config/hypr/custom/aur-autoupdate.sh
cp "$here/aur-packages.list" ~/.config/aur-autoupdate/aur-packages.list
f=~/.config/hypr/custom/execs.lua; touch "$f"
if ! grep -q '>>> aur-autoupdate >>>' "$f"; then
cat >> "$f" <<'EOS'

-- >>> aur-autoupdate >>>
hl.on("hyprland.start", function () hl.exec_cmd("sh -c 'sleep 30; exec ~/.config/hypr/custom/aur-autoupdate.sh'") end)
-- <<< aur-autoupdate <<<
EOS
fi
