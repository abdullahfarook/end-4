#!/usr/bin/env bash
# Runs Teams for Linux and restarts it (and re-docks the panel window) if it crashes (non-zero exit / killed by a signal).
# A clean quit (tray -> Quit, exit 0) ends the watchdog. Single instance. Gives up after 5 crashes within 2 minutes.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/teams-watchdog.lock"; flock -n 9 || exit 0
T=/opt/teams-for-linux/teams-for-linux; crashes=0; first=$(date +%s)
while true; do
    "$T" --ozone-platform=x11 >/dev/null 2>&1 9>&- &
    pid=$!
    ~/.config/hypr/custom/teams-panel.sh dock >/dev/null 2>&1 9>&- &
    wait "$pid"; rc=$?
    [ $rc -eq 0 ] && exit 0
    now=$(date +%s); [ $((now - first)) -gt 120 ] && { crashes=0; first=$now; }
    crashes=$((crashes + 1)); [ $crashes -ge 5 ] && exit 1
    sleep 3
done
