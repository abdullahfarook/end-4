#!/usr/bin/env bash
# Hides the AI panel only if it is currently shown. Serialized with a lock so that concurrent callers
# (focus watcher, click-away) can't both toggle it (which would close and reopen it).
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/ai-sidebar.lock"
flock 9
hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:ai")' >/dev/null || exit 0
hyprctl dispatch 'hl.dsp.workspace.toggle_special("ai")' >/dev/null
