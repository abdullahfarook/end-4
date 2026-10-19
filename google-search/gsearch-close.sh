#!/usr/bin/env bash
# Popup closed: slide the browser's special workspace out together with the header layer, then quit the helper once the slide is over.
# A reopen in between (new generation) cancels the quit.
# Tune: seconds in ~/.config/hypr/custom/gsearch-close-delay (default 0) delay the browser slide if it leaves before the header.
F="${XDG_RUNTIME_DIR:-/tmp}/gsearch-gen"
gen=$(cat "$F" 2>/dev/null || echo 0)
same() { [ "$(cat "$F" 2>/dev/null || echo 0)" = "$gen" ]; }
delay=$(cat "$HOME/.config/hypr/custom/gsearch-close-delay" 2>/dev/null || echo 0)
[ "$delay" != 0 ] && sleep "$delay"
same || exit 0
hyprctl monitors | grep -q "special workspace: .* (special:gsearch)" \
    && hyprctl dispatch 'hl.dsp.workspace.toggle_special("gsearch")' >/dev/null
sleep 1; same || exit 0
exec "$HOME/.config/hypr/custom/gsearch.py" hide
