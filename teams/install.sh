#!/bin/sh
# Teams for Linux: start in the tray once the network is up.
set -e
d=$(dirname "$0")
mkdir -p ~/.config/teams-for-linux ~/.config/autostart
cp "$d/config.json" ~/.config/teams-for-linux/config.json
cp "$d/teams-for-linux.desktop" ~/.config/autostart/
f=~/.config/hypr/custom/execs.lua
grep -q teams-for-linux "$f" || cat >> "$f" <<'LUA'

-- Teams for Linux: Hyprland doesn't process ~/.config/autostart, so launch it here
hl.on("hyprland.start", function () hl.exec_cmd("sh -c 'nm-online -q -t 120; for i in $(seq 60); do busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1 && break; sleep 1; done; /opt/teams-for-linux/teams-for-linux --ozone-platform=x11 & exec ~/.config/hypr/custom/teams-panel.sh dock'") end)
LUA

# Existing installs: switch the autostart line to "start, then dock the window on the hidden special:teams workspace"
sed -i "s|exec /opt/teams-for-linux/teams-for-linux --ozone-platform=x11'|/opt/teams-for-linux/teams-for-linux --ozone-platform=x11 \\& exec ~/.config/hypr/custom/teams-panel.sh dock'|" "$f"

# Tray click workaround: quickshell tray click launches a 2nd instance, which shows the hidden window
q=~/.config/quickshell/ii
b=~/backups/teams/$(date +%Y%m%d-%H%M%S)
mkdir -p "$b/ii/bar" "$b/waffle/bar/tray"
cp "$q/modules/ii/bar/SysTrayItem.qml" "$b/ii/bar/"; cp "$q/modules/waffle/bar/tray/TrayButton.qml" "$b/waffle/bar/tray/"
cp "$d/files/modules/ii/bar/SysTrayItem.qml" "$q/modules/ii/bar/"
cp "$d/files/modules/waffle/bar/tray/TrayButton.qml" "$q/modules/waffle/bar/tray/"
