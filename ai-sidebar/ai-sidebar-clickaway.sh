#!/usr/bin/env bash
# Run on every left click (non-consuming bind): hides the AI panel if it is shown and the click landed outside it.
sleep 0.08  # let a click on the bar's sidebar button stamp its toggle first (see ai-sidebar-toggled)
t="${XDG_RUNTIME_DIR:-/tmp}/ai-sidebar-toggled"
# This click (or a keybind) just toggled the panel itself: leave it alone
[ -e "$t" ] && [ $(( $(date +%s%3N) - $(cat "$t") )) -lt 1000 ] && exit 0
# Panel geometry, only if it is on screen: on the shown special workspace, or stranded on a visible normal workspace
read -r x y w h mon < <(hyprctl clients -j | jq -r --argjson a "$(hyprctl monitors -j | jq -c '[.[] | .activeWorkspace.id, (select(.specialWorkspace.id != 0) | .specialWorkspace.id)]')" \
    '.[] | select(.class=="ai-sidebar" and (.workspace.id as $i | $a | index($i))) | "\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1]) \(.monitor)"' | head -1)
[ -n "${x:-}" ] || exit 0
read -r cx cy < <(hyprctl cursorpos | tr -d ',')
# A click on another monitor isn't "outside the panel": the panel stays while you work there
cmon=$(hyprctl monitors -j | jq -r --argjson cx "$cx" --argjson cy "$cy" '.[] | select($cx >= .x and $cx < .x + .width and $cy >= .y and $cy < .y + .height) | .id' | head -1)
[ -n "$cmon" ] && [ "$cmon" != "$mon" ] && exit 0
if [ "$cx" -lt "$x" ] || [ "$cx" -gt $((x + w)) ] || [ "$cy" -lt "$y" ] || [ "$cy" -gt $((y + h)) ]; then
    "$HOME/.config/hypr/custom/ai-sidebar-hide.sh"
fi
