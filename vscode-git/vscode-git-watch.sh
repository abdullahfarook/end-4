#!/usr/bin/env bash
# Started by vscode-git.sh; single instance.
#  - hides the git panel when the launcher/overview opens
#  - when an editor/diff opens (title gets " - <file>") the window grows to the RIGHT only (left panel width/height/position untouched);
#    when the editor closes it shrinks back to LEFT. The expanded width is the last one you left it at (drag the right edge to change it).
exec 9>"$XDG_RUNTIME_DIR/vscode-git-watch.lock"; flock -n 9 || exit 0
sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
LEFT=392                                   # width of the sidebar-only panel (keep in sync with vscode-git.sh and the sidebar minimum in patch-min-width.sh)
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/vscode-git-wide-width"
last=0; mode=narrow
width_of() { hyprctl clients -j | jq -r --arg a "$1" '.[]|select(.address==$a)|.size[0]'; }
resize() {  # $1 address, $2 narrow|wide
    local now w cur target mw mh mx my fresh=0
    now=$(date +%s%N); [ $(( (now - last) / 1000000 )) -lt 1500 ] && fresh=1
    w=$(width_of "$1"); [ -n "$w" ] || return
    # Right after our own resize the window is still animating: trust the mode we applied; otherwise trust the real width.
    if [ $fresh = 1 ]; then cur=$mode; elif [ "$w" -gt $((LEFT + 60)) ]; then cur=wide; else cur=narrow; fi
    [ "$cur" = "$2" ] && { mode=$cur; return; }
    read -r mw mh mx my < <(hyprctl monitors -j | jq -r '.[]|select(.focused)|"\(.width) \(.height) \(.x) \(.y)"')
    if [ "$2" = wide ]; then
        target=$(cat "$STATE" 2>/dev/null); [ -n "$target" ] || target=$((LEFT + 600))
        # keep the saved width sane: at least LEFT+200, at most 60% of the screen
        [ "$target" -lt $((LEFT + 200)) ] && target=$((LEFT + 200)); [ "$target" -gt $((mw * 6 / 10)) ] && target=$((mw * 6 / 10))
    else
        # remember the width the user left the editor at (not while still animating)
        if [ $fresh = 0 ] && [ "$w" -ge $((LEFT + 200)) ]; then mkdir -p "$(dirname "$STATE")"; echo "$w" > "$STATE"; fi
        target=$LEFT
    fi
    last=$now; mode=$2
    # fixed height/position (same as vscode-git.sh); Hyprland resizes around the centre, so place it again afterwards
    hyprctl dispatch "hl.dsp.window.resize({ x = $target, y = $((mh - 83)), relative = false, window = \"address:$1\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.move({ x = $((mx + 6)), y = $((my + 46)), relative = false, window = \"address:$1\" })" >/dev/null
}
socat -u "UNIX-CONNECT:$sock" - | while IFS= read -r line; do
    case "$line" in
        openlayer\>\>quickshell:overview) "$HOME/.config/hypr/custom/vscode-git-hide.sh" ;;
        windowtitlev2\>\>*)
            rest=${line#windowtitlev2>>}; addr=0x${rest%%,*}; title=${rest#*,}
            case "$title" in
                "⎇ "*" - "*) resize "$addr" wide ;;
                "⎇ "*) resize "$addr" narrow
                       ( sleep 0.5; hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"CTRL ALT SHIFT\", key = \"h\", window = \"address:$addr\" })" >/dev/null ) & ;;
            esac ;;
    esac
done
