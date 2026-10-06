#!/usr/bin/env bash
# Hides the git panel only if shown (serialized; ignores calls right after a toggle).
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/vscode-git.lock"; flock 9
t="${XDG_RUNTIME_DIR:-/tmp}/vscode-git-toggled"
[ -e "$t" ] && [ $(( $(date +%s%3N) - $(cat "$t") )) -lt 800 ] && exit 0
hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:vgit")' >/dev/null || exit 0
hyprctl dispatch 'hl.dsp.workspace.toggle_special("vgit")' >/dev/null
