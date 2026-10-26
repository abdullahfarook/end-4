#!/usr/bin/env bash
# Hides the Teams panel if shown; the logic is shared by all window panels: side-panel.sh.
exec "$HOME/.config/hypr/custom/side-panel.sh" hide teams "$@"
