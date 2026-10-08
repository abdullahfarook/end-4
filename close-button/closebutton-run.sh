#!/usr/bin/env bash
# Supervisor: keeps `qs -c closebutton` alive (restarts it if it crashes). Single instance.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/closebutton-run.lock"
flock -n 9 || exit 0
while true; do
    qs -c closebutton >/dev/null 2>&1
    sleep 2
done
