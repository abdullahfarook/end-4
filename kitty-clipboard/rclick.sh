#!/usr/bin/env bash
# Kitty right click: copy the selection (arrives on stdin) and clear it if there is one, else paste.
sel=$(cat)
if [ -n "$sel" ]; then
    printf %s "$sel" | wl-copy
    kitten @ action --match "id:$KITTY_WINDOW_ID" clear_selection
else
    kitten @ action --match "id:$KITTY_WINDOW_ID" paste_from_clipboard
fi
