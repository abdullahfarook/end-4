#!/usr/bin/env bash
# Toggles the Teams panel: the Teams for Linux main window floated on the "teams" special workspace, left-aligned like the Git panel.
# First use moves the window there; if Teams is not running it is started. Toggling, docking and the closing rules come from side-panel.sh.
W=480                                       # panel width
P="$HOME/.config/hypr/custom/side-panel.sh"   # shared window-panel behavior (toggle, closing, monitors, focus, one panel per monitor)
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/teams-panel.lock"; flock 9
# wait up to $1 x 0.2 s for the Teams window to exist ($2: relaunch every 3 s while waiting)
wait_win() {
    for i in $(seq "$1"); do
        sleep 0.2; "$P" dock teams "$W" && return 0
        [ -n "${2:-}" ] && [ $((i % 15)) -eq 0 ] && launch
    done; return 1
}
launch() { nohup /opt/teams-for-linux/teams-for-linux --ozone-platform=x11 >/dev/null 2>&1 9>&- & }
if [ "${1:-}" = dock ]; then   # at login: park the window on the (hidden) special workspace without showing it
    "$P" dock teams "$W" || wait_win 600; exit 0
fi
"$P" toggle teams "$W" 9>&-; [ $? = 3 ] || exit 0   # shared: hide / show here / dock a stray window
launch; wait_win 300 launch || exit 0
"$P" show teams "$W"
