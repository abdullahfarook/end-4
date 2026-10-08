#!/usr/bin/env bash
# Toggles the dankmail window and, when showing it, brings it to the workspace you are on (the UI otherwise reappears on the
# workspace it was first created on, so the bar button seemed to do nothing).
cls="org.arqueon.dankmail"
if hyprctl clients -j | jq -e --arg c "$cls" 'any(.[]; .class==$c)' >/dev/null; then
    dmail toggle   # visible -> hide
    exit 0
fi
dmail toggle       # hidden -> show
for _ in $(seq 40); do
    sleep 0.1
    a=$(hyprctl clients -j | jq -r --arg c "$cls" '.[]|select(.class==$c)|.address' | head -1)
    [ -n "$a" ] && break
done
[ -n "${a:-}" ] || exit 0
ws=$(hyprctl activeworkspace -j | jq -r .id)
hyprctl dispatch "hl.dsp.window.move({ workspace = \"$ws\", window = \"address:$a\" })" >/dev/null
hyprctl dispatch "hl.dsp.focus({ window = \"address:$a\" })" >/dev/null
