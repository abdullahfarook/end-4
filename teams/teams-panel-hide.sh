#!/usr/bin/env bash
# Hides the Teams panel only if shown (serialized; ignores calls right after a toggle).
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/teams-panel.lock"; flock 9
t="${XDG_RUNTIME_DIR:-/tmp}/teams-panel-toggled"
[ "${1:-}" != force ] && [ -e "$t" ] && [ $(( $(date +%s%3N) - $(cat "$t") )) -lt 800 ] && exit 0
hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:teams")' >/dev/null || exit 0
hyprctl dispatch 'hl.dsp.workspace.toggle_special("teams")' >/dev/null
