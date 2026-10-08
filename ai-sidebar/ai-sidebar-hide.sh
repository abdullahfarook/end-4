#!/usr/bin/env bash
# Hides the AI panel only if it is currently shown. Serialized with a lock so that concurrent callers
# (focus watcher, click-away) can't both toggle it (which would close and reopen it).
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/ai-sidebar.lock"
flock 9
# The panel was toggled moments ago (the click/focus that opened it also triggers click-away): leave it alone
t="${XDG_RUNTIME_DIR:-/tmp}/ai-sidebar-toggled"
[ -e "$t" ] && [ $(( $(date +%s%3N) - $(cat "$t") )) -lt 800 ] && exit 0
if hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:ai")' >/dev/null; then
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("ai")' >/dev/null
else
    # Panel stranded on a visible normal workspace: dock it back onto the (hidden) special workspace
    addr=$(hyprctl clients -j | jq -r --argjson a "$(hyprctl monitors -j | jq -c '[.[].activeWorkspace.id]')" \
        '[.[] | select(.class=="ai-sidebar" and .workspace.name!="special:ai" and (.workspace.id as $i | $a | index($i)))][0].address // empty')
    [ -n "$addr" ] && hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:ai\", window = \"address:$addr\", follow = false })" >/dev/null
fi
exit 0
