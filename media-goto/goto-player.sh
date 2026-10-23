#!/usr/bin/env bash
# Focus the window playing the current media. Args: <track title> <player identity/desktop entry>
title="${1:-}"; ident="${2:-}"
addr=$(hyprctl clients -j | jq -r --arg t "$title" --arg i "$ident" '
  ($t | ascii_downcase) as $t | ($i | ascii_downcase) as $i
  | (if $i == "" then "" else ($i | sub("org\\.mozilla\\."; "") | split(".") | last) end) as $k
  | ([.[] | select($t != "" and (.title | ascii_downcase | contains($t))) | "\(.address) win"][0])
    // ([.[] | select($k != "" and (.class | ascii_downcase | contains($k)) and ((.title | ascii_downcase | contains("private")) | not)) | "\(.address) app"][0])
    // empty')
[ -z "$addr" ] && exit 1
set -- $addr
hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null
