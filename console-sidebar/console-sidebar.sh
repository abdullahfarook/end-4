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
    "$P" toggle console; [ $? = 3 ] || exit 0   # shared: hide / show here / dock a stray window
    nohup kitty -o window_padding_width=0 -o window_margin_width=10 -o font_size=10 --class console-sidebar --title console-sidebar -d "$HOME" >/dev/null 2>&1 & ;;
esac
