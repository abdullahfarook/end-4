#!/usr/bin/env bash
# Toggles the Teams panel: the Teams for Linux main window floated on the "teams" special workspace, left-aligned like the Git panel.
# First use moves the window there; if Teams is not running it is started. Only one side panel at a time (AI / Git panels are hidden first).
W=480; LEFT=6; TOP=46                     # panel width, offsets from the monitor's top-left (same spot as the Git panel)
dock=0; [ "${1:-}" = dock ] && dock=1       # "dock": at login, park the window on the (hidden) special workspace without showing it
[ $dock = 1 ] || date +%s%3N > "${XDG_RUNTIME_DIR:-/tmp}/teams-panel-toggled"   # lets click-away ignore the click that caused this toggle
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/teams-panel.lock"; flock 9
shown() { hyprctl monitors -j | jq -e --arg n "special:$1" 'any(.[]; .specialWorkspace.name==$n)' >/dev/null; }
[ $dock = 1 ] || for p in ai vgit; do shown "$p" && hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$p\")" >/dev/null; done
win() { hyprctl clients -j | jq -r '[.[]|select(.class=="teams-for-linux" and (.title|test("Microsoft Teams")))]|sort_by(-(.size[0]*.size[1]))|.[0]|"\(.address) \(.workspace.name)"' ; }
read -r a ws < <(win)
if [ $dock = 1 ] && { [ -z "${a:-}" ] || [ "$a" = null ]; }; then
    for _ in $(seq 600); do sleep 0.2; read -r a ws < <(win); [ -n "${a:-}" ] && [ "$a" != null ] && break; done
    [ -n "${a:-}" ] && [ "$a" != null ] || exit 0
fi
if [ -z "${a:-}" ] || [ "$a" = null ]; then
    # No mapped window: Teams is hidden in the tray (or not running, and it starts hidden). A second launch makes the running
    # instance show its window (~0.4s); until then keep nudging every 3s, polling fast.
    launch() { nohup /opt/teams-for-linux/teams-for-linux --ozone-platform=x11 >/dev/null 2>&1 9>&- & }
    launch
    for i in $(seq 300); do
        sleep 0.2; read -r a ws < <(win); [ -n "${a:-}" ] && [ "$a" != null ] && break
        [ $((i % 15)) -eq 0 ] && launch
    done
    [ -n "${a:-}" ] && [ "$a" != null ] || exit 0
fi
if [ "$ws" != "special:teams" ]; then
    read -r mw mh mx my < <(hyprctl monitors -j | jq -r '.[]|select(.focused)|"\(.width) \(.height) \(.x) \(.y)"')
    w="address:$a"
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:teams\", window = \"$w\", follow = false })" >/dev/null
    hyprctl dispatch "hl.dsp.window.float({ action = \"enable\", window = \"$w\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.resize({ x = $W, y = $((mh - 83)), relative = false, window = \"$w\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.move({ x = $((mx + LEFT)), y = $((my + TOP)), relative = false, window = \"$w\" })" >/dev/null
    [ $dock = 1 ] && exit 0
    sleep 0.3
    shown teams || hyprctl dispatch 'hl.dsp.workspace.toggle_special("teams")' >/dev/null
else
    [ $dock = 1 ] && exit 0
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("teams")' >/dev/null
fi
