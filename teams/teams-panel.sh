#!/usr/bin/env bash
# Toggles the Teams panel: the Teams for Linux main window floated on the "teams" special workspace, left-aligned like the Git panel.
# First use moves the window there; if Teams is not running it is started. One panel per monitor and the closing rules come from side-panel.sh.
W=480; LEFT=6; TOP=46                     # panel width, offsets from the monitor's top-left (same spot as the Git panel)
dock=0; [ "${1:-}" = dock ] && dock=1       # "dock": at login, park the window on the (hidden) special workspace without showing it
P="$HOME/.config/hypr/custom/side-panel.sh"   # shared window-panel behavior (closing, monitors, focus, one panel per monitor)
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/teams-panel.lock"; flock 9
# Clicking the button while the panel is open: click-away may hide it first (the click is outside the panel); this toggle must then not reopen it
[ $dock = 1 ] || { "$P" hidden-recently teams 1000 && exit 0; }
[ $dock = 1 ] || { "$P" stamp teams; nohup "$P" watch >/dev/null 2>&1 9>&- & }   # stamp: click-away ignores the click that caused this toggle
shown() { hyprctl monitors -j | jq -e --arg n "special:$1" 'any(.[]; .specialWorkspace.name==$n)' >/dev/null; }
here() { [ "$("$P" mon teams)" = "$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')" ]; }
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
    [ $dock = 1 ] || "$P" launching teams   # the window may take seconds: it must not count as "shown without a toggle"
    launch
    for i in $(seq 300); do
        sleep 0.2; read -r a ws < <(win); [ -n "${a:-}" ] && [ "$a" != null ] && break
        [ $((i % 15)) -eq 0 ] && launch
    done
    [ -n "${a:-}" ] && [ "$a" != null ] || exit 0
fi
# Teams (X11) restores its own saved geometry after mapping: set the panel geometry every time before it is shown
place() {
    read -r mw mh mx my < <(hyprctl monitors -j | jq -r '.[]|select(.focused)|"\(.width) \(.height) \(.x) \(.y)"')
    local w="address:$a"
    hyprctl dispatch "hl.dsp.window.float({ action = \"enable\", window = \"$w\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.resize({ x = $W, y = $((mh - 58)), relative = false, window = \"$w\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.move({ x = $((mx + LEFT)), y = $((my + TOP)), relative = false, window = \"$w\" })" >/dev/null
}
if [ "$ws" != "special:teams" ]; then
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:teams\", window = \"address:$a\", follow = false })" >/dev/null
    place
    [ $dock = 1 ] && exit 0
    sleep 0.3
    "$P" stamp teams
    shown teams || hyprctl dispatch 'hl.dsp.workspace.toggle_special("teams")' >/dev/null
else
    [ $dock = 1 ] && exit 0
    if here; then "$P" hide teams force   # shown on this monitor: hide
    else "$P" stamp teams; place; hyprctl dispatch 'hl.dsp.workspace.toggle_special("teams")' >/dev/null; fi   # hidden or on another monitor: show here
fi
