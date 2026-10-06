#!/usr/bin/env bash
# Hides the ai-sidebar special workspace when focus moves to another window (click outside), like the native sidebar,
# or when the shell's launcher/overview opens (SUPER).
# Started by ai-sidebar.sh; exits with the Hyprland session.
exec 9>"$XDG_RUNTIME_DIR/ai-sidebar-watch.lock"; flock -n 9 || exit 0  # single instance
sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -u "UNIX-CONNECT:$sock" - | while IFS= read -r line; do
    case "$line" in
    openlayer\>\>quickshell:overview) "$HOME/.config/hypr/custom/ai-sidebar-hide.sh"; continue ;;  # SUPER launcher/overview opened: close the panel
    openwindow\>\>*)  # a window mapped while the panel is shown (e.g. Teams from the tray) lands on special:ai: close the panel and move it out
        IFS=, read -r addr ws class _ <<<"${line#openwindow>>}"
        [ "$ws" = special:ai ] && [ "$class" != ai-sidebar ] || continue
        "$HOME/.config/hypr/custom/ai-sidebar-hide.sh"
        dest=$(hyprctl monitors -j | jq -r '.[]|select(.focused).activeWorkspace.id')
        hyprctl dispatch "hl.dsp.window.move({ workspace = \"$dest\", window = \"address:0x$addr\" })" >/dev/null
        continue ;;
    activewindow\>\>*) ;;
    *) continue ;;
    esac
    class=${line#activewindow>>}; class=${class%%,*}
    [ -z "$class" ] && continue  # focus went to nothing (e.g. opening on an empty workspace): click-away handles outside clicks
    [ "$class" = ai-sidebar ] && continue
    sleep 0.05  # let the open/focus sequence settle before deciding
    cur=$(hyprctl activewindow -j | jq -r 'select(.workspace.name != "special:ai") | .class // empty')  # windows on the panel's own workspace don't count as "outside"
    [ -z "$cur" ] || [ "$cur" = ai-sidebar ] && continue
    "$HOME/.config/hypr/custom/ai-sidebar-hide.sh"
done
