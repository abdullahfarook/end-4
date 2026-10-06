#!/usr/bin/env bash
# Focus the window playing the current media. Args: <track title> <player identity/desktop entry>
title="${1:-}"; ident="${2:-}"
addr=$(hyprctl clients -j | python3 -c '
import json,sys
t,i=sys.argv[1].lower(),sys.argv[2].lower()
cs=json.load(sys.stdin)
for c in cs:
    if t and t in c["title"].lower(): print(c["address"],"win"); sys.exit()
key=i.replace("org.mozilla.","").split(".")[-1] if i else ""
for c in cs:
    if key and key in c["class"].lower() and "private" not in c["title"].lower(): print(c["address"],"app"); sys.exit()
' "$title" "$ident")
[ -z "$addr" ] && exit 1
set -- $addr
hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null
