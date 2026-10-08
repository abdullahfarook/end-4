#!/usr/bin/env bash
# Stops the AI sidebar terminal (kitty running claude/codex); the next toggle starts a fresh one.
for pid in $(hyprctl clients -j | jq -r '.[]|select(.class=="ai-sidebar")|.pid'); do kill "$pid"; done
exit 0
