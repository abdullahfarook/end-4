#!/usr/bin/env bash
# On ALT release after a ALT+Tab session: close the overview, keeping the selected workspace.
flag="${XDG_RUNTIME_DIR:-/tmp}/super-tab-active"
[ -e "$flag" ] || exit 0
rm -f "$flag"
hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null
sleep 0.15  # let the shell's own release handler run first
qs -c ii ipc call search close
