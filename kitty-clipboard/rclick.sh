#!/usr/bin/env bash
# Kitty clipboard helper (run via `launch --type=background --allow-remote-control`).
#   rclick.sh        right click: copy+clear the selection (stdin) if any, else paste
#   rclick.sh paste  ctrl+v: paste
# Paste of an image on the clipboard sends a real ctrl+v to the app (Claude Code reads the image itself).
act() { kitten @ action --match "id:$KITTY_WINDOW_ID" "$@"; }
paste() {
    if wl-paste --list-types 2>/dev/null | grep -q '^image/'; then
        kitten @ send-key --match "id:$KITTY_WINDOW_ID" ctrl+v
    else
        act paste_from_clipboard
    fi
}
if [ "${1:-}" = paste ]; then paste; exit 0; fi
sel=$(cat)
if [ -n "$sel" ]; then
    printf %s "$sel" | wl-copy
    act clear_selection
else
    paste
fi
