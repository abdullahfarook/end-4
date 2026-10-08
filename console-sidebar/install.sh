#!/usr/bin/env bash
# Installs the left console panel (kitty shell on a special workspace, SUPER + `). Idempotent.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"; KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
BACKUP="$HOME/backups/console-sidebar/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$KEYBINDS" "$Q/modules/ii/bar/BarContent.qml" "$BACKUP/"
echo "Backed up to $BACKUP"
if grep -q "ConsoleButton {" "$Q/modules/ii/bar/BarContent.qml"; then echo "QML patch already applied."
else patch -d "$Q" -p1 -s -f --no-backup-if-mismatch < "$REPO/console-sidebar.patch" && echo "QML patch applied (restart the shell)."; fi
install -Dm644 "$REPO/ConsoleButton.qml" "$Q/modules/ii/bar/ConsoleButton.qml"
install -Dm755 "$REPO/console-sidebar.sh" "$HOME/.config/hypr/custom/console-sidebar.sh"
python3 - "$KEYBINDS" "$REPO/console-sidebar-keybinds.lua" <<'PY'
import re, sys
target, snippet = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
s = open(target).read()
pat = r"-- >>> console-sidebar >>>.*?-- <<< console-sidebar <<<"
s = re.sub(pat, lambda _: snippet, s, flags=re.S) if re.search(pat, s, re.S) else s.rstrip("\n") + "\n\n" + snippet + "\n"
open(target, "w").write(s)
PY
echo "Done. Toggle with SUPER + \`."
