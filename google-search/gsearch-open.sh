#!/usr/bin/env bash
# Popup opened: bump the generation (cancels a pending delayed close) and slide the browser's special workspace in.
F="${XDG_RUNTIME_DIR:-/tmp}/gsearch-gen"
echo $(( $(cat "$F" 2>/dev/null || echo 0) + 1 )) > "$F"
hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:gsearch")' >/dev/null \
    || hyprctl dispatch 'hl.dsp.workspace.toggle_special("gsearch")' >/dev/null
