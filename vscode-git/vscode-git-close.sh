#!/usr/bin/env bash
# SUPER+Q: hides the git panel instead of closing it (keeps it running); closes any other window as usual.
if hyprctl activewindow -j | jq -e '.title | test("⎇")' >/dev/null; then
    exec "$HOME/.config/hypr/custom/vscode-git-hide.sh" force
fi
exec hyprctl dispatch 'hl.dsp.window.close()'
