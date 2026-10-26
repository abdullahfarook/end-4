#!/usr/bin/env bash
# Hides the AI panel if shown (kept for callers such as SUPER+Q); the logic is shared by all window panels: side-panel.sh.
exec "$HOME/.config/hypr/custom/side-panel.sh" hide ai "$@"
