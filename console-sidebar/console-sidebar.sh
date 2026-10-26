#!/usr/bin/env bash
# Left console panel: a kitty shell on the "console" special workspace, styled like the AI sidebar.
# Closing, monitors and focus rules are shared by all window panels: see side-panel.sh.
#   console-sidebar.sh          toggle (start the terminal if needed)
#   console-sidebar.sh hide     hide if shown
#   console-sidebar.sh stop     kill the terminal (next toggle starts a fresh one)
P="$HOME/.config/hypr/custom/side-panel.sh"
case "${1:-toggle}" in
hide) exec "$P" hide console force ;;
stop)
    for pid in $(hyprctl clients -j | jq -r '.[]|select(.class=="console-sidebar")|.pid'); do kill "$pid"; done; exit 0 ;;
toggle)
    "$P" stamp console   # before anything slow: its own click/focus must not close it again
    exec 9>"${XDG_RUNTIME_DIR:-/tmp}/console-sidebar.lock"; flock 9
    nohup "$P" watch >/dev/null 2>&1 9>&- &
    win=$(hyprctl clients -j | jq -c '[.[] | select(.class=="console-sidebar")][0] // empty')
    if [ -n "$win" ]; then
        addr=$(jq -r .address <<<"$win")
        if [ "$("$P" mon console)" = "$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')" ]; then
            "$P" hide console force   # shown on this monitor: hide
        else  # hidden, or shown on another monitor: show it here
            [ "$(jq -r .workspace.name <<<"$win")" != special:console ] &&
                hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:console\", window = \"address:$addr\", follow = false })" >/dev/null
            hyprctl dispatch 'hl.dsp.workspace.toggle_special("console")' >/dev/null
            sleep 0.1; hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null
        fi
    else
        nohup kitty -o window_padding_width=0 -o window_margin_width=10 -o font_size=10 --class console-sidebar --title console-sidebar -d "$HOME" >/dev/null 2>&1 9>&- &
    fi ;;
esac
