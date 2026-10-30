#!/usr/bin/env bash
# Settings > Bar > "Bar widgets": per left-bar button an on/off switch, a pin (always shown, not only on hover) and up/down to set the order.
# In the bar, shown-for-good icons (user pin, unread badge; never a merely open panel or menu, so opening a widget does not reorder icons) come first in that order, so they never move when the rest reveal.
# Run AFTER bar-widget-toggles and zbar-reveal (patches their output; idempotent).
set -euo pipefail
Q="$HOME/.config/quickshell/ii/modules"
B="$HOME/backups/zbar-widget-layout/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$B"
cp "$Q/common/Config.qml" "$Q/ii/bar/BarContent.qml" "$Q/settings/BarConfig.qml" "$B/"
python3 "$(dirname "$0")/patch.py" "$Q"
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
