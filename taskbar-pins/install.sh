#!/usr/bin/env bash
# Waffle taskbar: right-click a window preview to pin/unpin its app; "Edit" in the preview popup
# enters edit mode (drag pinned icons to reorder, x to remove, "Done" to finish).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.config/quickshell/ii"
BACKUP="$HOME/backups/taskbar-pins/$(date +%Y%m%d-%H%M%S)"
cd "$REPO/files"
for f in $(find . -type f | sed 's|^\./||'); do
    mkdir -p "$BACKUP/$(dirname "$f")"; cp "$TARGET/$f" "$BACKUP/$f"
    cp "$f" "$TARGET/$f"
done
echo "Installed (backup: $BACKUP). Restart shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
