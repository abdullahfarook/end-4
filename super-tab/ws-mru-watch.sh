#!/usr/bin/env bash
# Tracks workspace focus history for ALT+Tab (Windows-style most-recently-used order).
# Ignores focus changes made while an ALT+Tab session is running; the release script records the result.
exec 9>"$XDG_RUNTIME_DIR/ws-mru-watch.lock"; flock -n 9 || exit 0  # single instance
. "$HOME/.config/hypr/custom/ws-mru-lib.sh"
mru_push "$(hyprctl activeworkspace -j | jq -r .id)"
sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -u "UNIX-CONNECT:$sock" - | while IFS= read -r line; do
    case "$line" in workspacev2\>\>*) ;; *) continue ;; esac
    [ -e "$rt/super-tab-active" ] && continue
    id=${line#workspacev2>>}; id=${id%%,*}
    mru_push "$id"
done
