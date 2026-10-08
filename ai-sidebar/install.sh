#!/usr/bin/env bash
# Installs the optional Claude/Codex AI sidebar: setting in Settings -> Services -> AI, keybinds, script (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"
KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
FILES=(modules/common/Config.qml modules/settings/ServicesConfig.qml modules/ii/sidebarLeft/SidebarLeft.qml modules/ii/bar/LeftSidebarButton.qml)
BACKUP="$HOME/backups/ai-sidebar/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$KEYBINDS" "$BACKUP/"
for f in "${FILES[@]}"; do mkdir -p "$BACKUP/$(dirname "$f")"; cp "$Q/$f" "$BACKUP/$f"; done
echo "Backed up to $BACKUP"
if patch -d "$Q" -p1 -R --dry-run -s -f < "$REPO/ai-sidebar.patch" >/dev/null 2>&1; then
    echo "QML patch already applied."
else
    patch -d "$Q" -p1 -s -f --no-backup-if-mismatch < "$REPO/ai-sidebar.patch" && echo "QML patch applied (restart the shell)."
fi
if patch -d "$Q" -p1 -R --dry-run -s -f < "$REPO/ai-sidebar-stop.patch" >/dev/null 2>&1; then echo "Stop-menu patch already applied."
else patch -d "$Q" -p1 -s -f --no-backup-if-mismatch < "$REPO/ai-sidebar-stop.patch" && echo "Stop-menu patch applied."; fi
if patch -d "$Q" -p1 -R --dry-run -s -f < "$REPO/ai-sidebar-stop-dismiss.patch" >/dev/null 2>&1; then echo "Stop-menu dismiss patch already applied."
else patch -d "$Q" -p1 -s -f --no-backup-if-mismatch < "$REPO/ai-sidebar-stop-dismiss.patch" && echo "Stop-menu dismiss patch applied."; fi
for f in ai-sidebar-stop.sh ai-sidebar.sh ai-sidebar-watch.sh ai-sidebar-clickaway.sh ai-sidebar-hide.sh; do install -Dm755 "$REPO/$f" "$HOME/.config/hypr/custom/$f"; done
python3 - "$KEYBINDS" "$REPO/ai-sidebar-keybinds.lua" <<'PY'
import re, sys
target, snippet = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
s = open(target).read()
pat = r"-- >>> ai-sidebar >>>.*?-- <<< ai-sidebar <<<"
s = re.sub(pat, lambda _: snippet, s, flags=re.S) if re.search(pat, s, re.S) else s.rstrip("\n") + "\n\n" + snippet + "\n"
open(target, "w").write(s)
PY
echo "Done. Pick the backend in Settings -> Services -> AI."
