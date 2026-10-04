#!/usr/bin/env bash
# Run on every left click (non-consuming bind): hides the AI panel if it is shown and the click landed outside it.
sleep 0.25  # let a click on the bar's sidebar button toggle first, so we don't reopen it
t="${XDG_RUNTIME_DIR:-/tmp}/ai-sidebar-toggled"
# This click (or a keybind) just toggled the panel itself: leave it alone
[ -e "$t" ] && [ $(( $(date +%s) - $(stat -c %Y "$t") )) -lt 1 ] && exit 0
hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:ai")' >/dev/null || exit 0
read -r cx cy < <(hyprctl cursorpos | tr -d ',')
read -r x y w h < <(hyprctl clients -j | jq -r '.[]|select(.class=="ai-sidebar")|"\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' | head -1)
[ -n "${x:-}" ] || exit 0
if [ "$cx" -lt "$x" ] || [ "$cx" -gt $((x + w)) ] || [ "$cy" -lt "$y" ] || [ "$cy" -gt $((y + h)) ]; then
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("ai")' >/dev/null
fi
