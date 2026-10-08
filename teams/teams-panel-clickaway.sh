#!/usr/bin/env bash
# Run on every left click: hides the Teams panel if shown and the click landed outside it.
sleep 0.08
t="${XDG_RUNTIME_DIR:-/tmp}/teams-panel-toggled"
[ -e "$t" ] && [ $(( $(date +%s%3N) - $(cat "$t") )) -lt 1000 ] && exit 0
hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:teams")' >/dev/null || exit 0
read -r cx cy < <(hyprctl cursorpos | tr -d ',')
read -r x y w h < <(hyprctl clients -j | jq -r '.[]|select(.workspace.name=="special:teams")|"\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' | head -1)
[ -n "${x:-}" ] || exit 0
if [ "$cx" -lt "$x" ] || [ "$cx" -gt $((x + w)) ] || [ "$cy" -lt "$y" ] || [ "$cy" -gt $((y + h)) ]; then
    date +%s%3N > "${XDG_RUNTIME_DIR:-/tmp}/teams-panel-hidden"
    "$HOME/.config/hypr/custom/teams-panel-hide.sh"
fi
