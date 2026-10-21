#!/usr/bin/env bash
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/typesearch-run.lock"
flock -n 9 || exit 0
while true; do qs -c typesearch >/dev/null 2>&1; sleep 2; done
