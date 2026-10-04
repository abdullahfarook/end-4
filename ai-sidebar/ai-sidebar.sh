#!/usr/bin/env bash
# Toggles the left AI sidebar. Backend comes from ai.sidebarBackend in the illogical-impulse config:
#   native -> the shell's own Intelligence sidebar
#   claude / codex -> a kitty window running that CLI on the "ai" special workspace
backend=$(jq -r '.ai.sidebarBackend // "native"' "$HOME/.config/illogical-impulse/config.json" 2>/dev/null)
if [ "$backend" != claude ] && [ "$backend" != codex ]; then
    exec hyprctl dispatch 'hl.dsp.global("quickshell:sidebarLeftToggle")'
fi
# Window title carries the backend so a changed setting replaces a stale window
title="ai-sidebar-$backend"
clients=$(hyprctl clients -j)
stale=$(jq -r '.[] | select(.class=="ai-sidebar" and .title!="'"$title"'") | .address' <<<"$clients")
for a in $stale; do hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null; done
if jq -e '.[] | select(.class=="ai-sidebar" and .title=="'"$title"'")' <<<"$clients" >/dev/null; then
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("ai")' >/dev/null
else
    nohup kitty --class ai-sidebar --title "$title" -d "$HOME" "$backend" >/dev/null 2>&1 &
fi
