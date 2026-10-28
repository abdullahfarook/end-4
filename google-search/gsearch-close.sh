#!/usr/bin/env bash
# Panel closed: it already hid the browser window (after putting a still of it in the panel, so both slid out as one).
# Hide the browser's special workspace if it is still shown, then quit the helper. A reopen in between (new generation) cancels.
F="${XDG_RUNTIME_DIR:-/tmp}/gsearch-gen"
gen=$(cat "$F" 2>/dev/null || echo 0)
same() { [ "$(cat "$F" 2>/dev/null || echo 0)" = "$gen" ]; }
sleep 0.1   # Hyprland hides the workspace by itself once its last window is gone: toggling before that would show it again
same || exit 0
hyprctl monitors | grep -q "special workspace: .* (special:gsearch)" \
    && hyprctl dispatch 'hl.dsp.workspace.toggle_special("gsearch")' >/dev/null
sleep 1; same || exit 0
exec "$HOME/.config/hypr/custom/gsearch.sh" hide
