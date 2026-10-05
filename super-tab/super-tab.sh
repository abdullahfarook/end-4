#!/usr/bin/env bash
# ALT+Tab like Windows, on workspaces: tap = jump to the previously used workspace, hold ALT and keep
# pressing Tab to go further back in most-recently-used order (ALT+Shift+Tab goes forward again).
# Releasing ALT (see super-tab-release.sh) closes the overview on the selected workspace.
. "$HOME/.config/hypr/custom/ws-mru-lib.sh"
flag="$rt/super-tab-active"; list="$rt/super-tab-list"
if [ ! -e "$flag" ]; then
    mru_push "$(hyprctl activeworkspace -j | jq -r .id)"
    existing=$(hyprctl workspaces -j | jq -r '.[] | select(.id > 0) | .id')
    grep -Fx -f <(echo "$existing") "$mru_file" >"$list"
    echo 0 >"$flag"
    hyprctl dispatch 'hl.dsp.submap("super-tab")' >/dev/null
fi
n=$(wc -l <"$list"); i=$(cat "$flag")
if [ "$1" = prev ]; then i=$(( (i - 1 + n) % n )); else i=$(( (i + 1) % n )); fi
echo "$i" >"$flag"
hyprctl dispatch "hl.dsp.focus({ workspace = \"$(sed -n "$((i + 1))p" "$list")\" })" >/dev/null
hyprctl layers | grep -q "quickshell:overview" || qs -c ii ipc call search open
