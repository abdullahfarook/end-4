#!/bin/sh
# Teams for Linux: start in the tray once the network is up.
set -e
d=$(dirname "$0")
mkdir -p ~/.config/teams-for-linux ~/.config/autostart
cp "$d/config.json" ~/.config/teams-for-linux/config.json
cp "$d/teams-for-linux.desktop" ~/.config/autostart/
f=~/.config/hypr/custom/execs.lua
grep -q teams-for-linux "$f" || cat >> "$f" <<'LUA'

-- Teams for Linux: Hyprland doesn't process ~/.config/autostart, so launch it here (after the network is up)
hl.on("hyprland.start", function () hl.exec_cmd("sh -c 'nm-online -q -t 120 && exec /opt/teams-for-linux/teams-for-linux --ozone-platform=x11'") end)
LUA
