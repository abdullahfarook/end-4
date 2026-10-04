#!/usr/bin/env bash
# ALT+Tab: every press goes to the next workspace and shows the overview.
# Releasing ALT (see super-tab-release.sh) closes the overview on the selected workspace.
touch "${XDG_RUNTIME_DIR:-/tmp}/super-tab-active"
hyprctl dispatch 'hl.dsp.submap("super-tab")' >/dev/null
hyprctl dispatch 'hl.dsp.focus({ workspace = "e+1" })' >/dev/null
hyprctl layers | grep -q "quickshell:overview" || qs -c ii ipc call search open
