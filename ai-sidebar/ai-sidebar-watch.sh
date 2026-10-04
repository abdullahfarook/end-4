#!/usr/bin/env bash
# Hides the ai-sidebar special workspace when focus moves to another window (click outside), like the native sidebar.
# Started by ai-sidebar.sh; exits with the Hyprland session.
exec 9>"$XDG_RUNTIME_DIR/ai-sidebar-watch.lock"; flock -n 9 || exit 0  # single instance
sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -u "UNIX-CONNECT:$sock" - | while IFS= read -r line; do
    case "$line" in
    activewindow\>\>*) ;;
    *) continue ;;
    esac
    class=${line#activewindow>>}; class=${class%%,*}
    [ "$class" = ai-sidebar ] && continue
    sleep 0.05  # let the open/focus sequence settle before deciding
    [ "$(hyprctl activewindow -j | jq -r .class)" = ai-sidebar ] && continue
    "$HOME/.config/hypr/custom/ai-sidebar-hide.sh"
done
