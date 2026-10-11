#!/usr/bin/env bash
# Usage: launch-bg <command...>  — start a command on the lowest empty workspace, silently (no switch, no flash).
# A temporary catch-all window rule is used so apps that forward to an already
# running instance (VS Code, Electron, browsers) also land there.
before=$(hyprctl clients -j | jq -r '.[].address')
used=$(hyprctl clients -j | jq -r '.[] | select(.workspace.id>0) | .workspace.id' | sort -un)
ws=1; while grep -qx "$ws" <<<"$used"; do ws=$((ws+1)); done
name="launchbg$$"
hyprctl dispatch "function() hl.window_rule({ name = \"$name\", match = { class = \".*\" }, workspace = \"$ws silent\" }) end" >/dev/null
cmd=$(printf '%q ' "$@")
nohup setsid bash -c "$cmd" >/dev/null 2>&1 &
for _ in $(seq 150); do
  sleep 0.1
  new=$(hyprctl clients -j | jq -r '.[] | select(.workspace.id>0) | .address' | grep -vxFf <(echo "$before") | head -1)
  [ -n "$new" ] && break
done
hyprctl dispatch "function() hl.window_rule({ name = \"$name\", match = { class = \".*\" }, enabled = false }) end" >/dev/null
