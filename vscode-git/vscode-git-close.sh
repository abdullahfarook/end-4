#!/usr/bin/env bash
# SUPER+Q: hides the git panel / the AI sidebar / the dankmail window instead of closing them (they keep running); closes any other window as usual.
active=$(hyprctl activewindow -j)
if jq -e '.title | test("⎇")' >/dev/null <<<"$active"; then
    exec "$HOME/.config/hypr/custom/vscode-git-hide.sh" force
fi
if jq -e '.class == "org.arqueon.dankmail"' >/dev/null <<<"$active"; then
    exec dmail toggle   # hides the window; the daemon keeps syncing
fi
if jq -e '.class == "ai-sidebar"' >/dev/null <<<"$active"; then
    exec hyprctl dispatch 'hl.dsp.workspace.toggle_special("ai")'   # hide the AI panel; the session keeps running
fi
exec hyprctl dispatch 'hl.dsp.window.close()'
