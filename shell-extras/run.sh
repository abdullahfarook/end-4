#!/usr/bin/env bash
# Supervisor: keeps `qs -c extras` alive (restarts it if it crashes). Single instance.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/extras-run.lock"
flock -n 9 || exit 0
while true; do qs -c extras >/dev/null 2>&1; sleep 2; done
