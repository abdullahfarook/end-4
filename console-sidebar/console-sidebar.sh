#!/usr/bin/env bash
# Left console panel: a kitty shell on the "console" special workspace, styled like the AI sidebar.
#   console-sidebar.sh          toggle (start the terminal if needed)
#   console-sidebar.sh hide     hide if shown
#   console-sidebar.sh clickaway hide if the click landed outside the panel
#   console-sidebar.sh stop     kill the terminal (next toggle starts a fresh one)
#   console-sidebar.sh watch    hide when focus moves to another window (single instance)
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/console-sidebar.lock"
shown() { hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:console")' >/dev/null; }
stamp="${XDG_RUNTIME_DIR:-/tmp}/console-sidebar-toggled"
case "${1:-toggle}" in
hide)
    flock 9; shown && hyprctl dispatch 'hl.dsp.workspace.toggle_special("console")' >/dev/null; exit 0 ;;
clickaway)
    sleep 0.08
    [ -e "$stamp" ] && [ $(( $(date +%s%3N) - $(cat "$stamp") )) -lt 1000 ] && exit 0
    read -r x y w h < <(hyprctl clients -j | jq -r '.[] | select(.class=="console-sidebar" and .workspace.name=="special:console") | "\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' | head -1)
    [ -n "${x:-}" ] && shown || exit 0
    read -r cx cy < <(hyprctl cursorpos | tr -d ',')
    if [ "$cx" -lt "$x" ] || [ "$cx" -gt $((x + w)) ] || [ "$cy" -lt "$y" ] || [ "$cy" -gt $((y + h)) ]; then "$0" hide; fi
    exit 0 ;;
stop)
    for pid in $(hyprctl clients -j | jq -r '.[]|select(.class=="console-sidebar")|.pid'); do kill "$pid"; done; exit 0 ;;
watch)
    exec 8>"${XDG_RUNTIME_DIR:-/tmp}/console-sidebar-watch.lock"; flock -n 8 || exit 0
    socat -u "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" - | while IFS= read -r line; do
        case "$line" in activewindow\>\>*) ;; *) continue ;; esac
        class=${line#activewindow>>}; class=${class%%,*}
        [ -z "$class" ] || [ "$class" = console-sidebar ] && continue
        sleep 0.05
        cur=$(hyprctl activewindow -j | jq -r 'select(.workspace.name != "special:console") | .class // empty')
        [ -z "$cur" ] || [ "$cur" = console-sidebar ] && continue
        "$0" hide
    done ;;
toggle)
    flock 9
    date +%s%3N > "$stamp"
    nohup "$0" watch >/dev/null 2>&1 9>&- &
    win=$(hyprctl clients -j | jq -c '[.[] | select(.class=="console-sidebar")][0] // empty')
    if [ -n "$win" ]; then
        addr=$(jq -r .address <<<"$win")
        if shown; then
            hyprctl dispatch 'hl.dsp.workspace.toggle_special("console")' >/dev/null
        else
            [ "$(jq -r .workspace.name <<<"$win")" != special:console ] &&
                hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:console\", window = \"address:$addr\", follow = false })" >/dev/null
            hyprctl dispatch 'hl.dsp.workspace.toggle_special("console")' >/dev/null
            sleep 0.1; hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null
        fi
    else
        nohup kitty --class console-sidebar --title console-sidebar -d "$HOME" >/dev/null 2>&1 9>&- &
    fi ;;
esac
