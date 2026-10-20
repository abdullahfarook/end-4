#!/usr/bin/env bash
# Usage: gsearch-popout.sh <seconds> <page-url> - floating always-on-top mpv (yt-dlp resolves the page), resumed at <seconds>.
# One pop-out at a time: a new one replaces the old. Window rules for title gsearch-pip are in google-search-rules.lua.
# The window opens on the special:gsearch workspace (the widget is showing), which would hide it with the widget, so it is moved to the
# monitor's regular active workspace (it is pinned, so it then follows workspace switches).
t="${1:-0}"; url="${2:?url}"
# Google's inline preview reports a google.com URL (frame address); the YouTube id is in its fragment (vid:<id>) or /embed/<id>.
# YouTube goes to gsearch-pip.qml (yt-dlp is blocked by YouTube's bot check); anything else to mpv.
id=""
if [[ "$url" =~ vid:([A-Za-z0-9_-]{11}) ]] || [[ "$url" =~ youtube(-nocookie)?\.com/embed/([A-Za-z0-9_-]{11}) ]] \
    || [[ "$url" =~ youtube\.com/watch\?(.*&)?v=([A-Za-z0-9_-]{11}) ]] || [[ "$url" =~ youtu\.be/([A-Za-z0-9_-]{11}) ]]; then
    id="${BASH_REMATCH[${#BASH_REMATCH[@]}-1]}"
fi
SRC="$HOME/.local/share/gsearch"; DST="$HOME/.local/share/gsearch-pip"
pkill -f 'qml6 .*gsearch-pip\.qml' 2>/dev/null
pkill -f 'mpv .*--title=gsearch-pip' 2>/dev/null
if [ -n "$id" ]; then
    mkdir -p "$DST"; cp -a "$SRC"/Cookies "$SRC"/Cookies-journal "$SRC/Local Storage" "$SRC/Network Persistent State" "$SRC"/TransportSecurity "$DST/" 2>/dev/null
    export QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1
    setsid -f bash -c 'qml6 "$1" -- "$2" "$3" "$4" 2>&1 >/dev/null | while read -r l; do
        a=$(hyprctl clients -j | jq -r "[.[]|select(.title==\"gsearch-pip\")][0].address // empty")
        case "$l" in
            *"PIP fs 1") hyprctl dispatch "hl.dsp.window.pin({ action = \"disable\", window = \"address:$a\" })"
                         hyprctl dispatch "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"set\", window = \"address:$a\" })" ;;
            *"PIP fs 0") hyprctl dispatch "hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"unset\", window = \"address:$a\" })"
                         hyprctl dispatch "hl.dsp.window.pin({ action = \"enable\", window = \"address:$a\" })" ;;
        esac >/dev/null
    done' _ "$(dirname "$(readlink -f "$0")")/gsearch-pip.qml" "$id" "$t" "$DST" >/dev/null 2>&1 </dev/null
else
setsid -f mpv --title=gsearch-pip --force-window=immediate --keep-open=yes --osc=yes --script-opts=osc-vidscale=no,osc-scalewindowed=1.8 --start="$t" --ytdl-format='bv*[height<=720]+ba/b[height<=720]/b' "$url" >/dev/null 2>&1 </dev/null
fi
for _ in $(seq 100); do
    sleep 0.1
    addr=$(hyprctl clients -j | jq -r '[.[]|select(.title=="gsearch-pip")][0].address // empty')
    [ -n "$addr" ] && break
done
if [ -n "$addr" ]; then
    ws=$(hyprctl clients -j | jq -r --arg a "$addr" '.[]|select(.address==$a)|.monitor' | xargs -I{} sh -c "hyprctl monitors -j | jq -r '.[]|select(.id=={})|.activeWorkspace.id'")
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"$ws\", follow = false, window = \"address:$addr\" })" >/dev/null
fi
