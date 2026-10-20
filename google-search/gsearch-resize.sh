#!/usr/bin/env bash
# Usage: gsearch-resize.sh <width>  - set the width of the gsearch browser window (keeps its height) and re-pin it at (5,86) of its monitor.
# No-op if it isn't open. Keep the position in sync with google-search-rules.lua.
w="${1:?width}"
sel=$(hyprctl clients -j | jq -r '[.[]|select(.title=="gsearch")][0] | if . then "\(.address) \(.size[1]) \(.monitor)" else empty end')
[ -n "$sel" ] || exit 0
read -r addr h mon <<<"$sel"
read -r mx my <<<"$(hyprctl monitors -j | jq -r --argjson m "$mon" '.[]|select(.id==$m)|"\(.x) \(.y)"')"
hyprctl dispatch "hl.dsp.window.resize({ x = $w, y = $h, exact = true, window = \"address:$addr\" })" >/dev/null
hyprctl dispatch "hl.dsp.window.move({ x = $((mx+5)), y = $((my+86)), window = \"address:$addr\" })" >/dev/null
