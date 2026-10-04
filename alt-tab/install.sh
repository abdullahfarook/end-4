#!/usr/bin/env bash
# Alt+Tab toggles between the current and previous workspace (safe to run repeatedly).
# Writes the marked block in ~/.config/hypr/custom/keybinds.lua.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
BACKUP="$HOME/backups/alt-tab/$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP" "$(dirname "$KEYBINDS")"
touch "$KEYBINDS"
cp "$KEYBINDS" "$BACKUP/"
echo "Backed up $KEYBINDS to $BACKUP"

# Replace the marked block, or append it
python3 - "$KEYBINDS" "$REPO/alt-tab-keybinds.lua" <<'PY'
import re, sys
target, snippet = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
s = open(target).read()
pattern = r"-- >>> alt-tab-workspaces >>>.*?-- <<< alt-tab-workspaces <<<"
if re.search(pattern, s, re.S):
    s = re.sub(pattern, lambda _: snippet, s, flags=re.S)
else:
    s = s.rstrip("\n") + "\n\n" + snippet + "\n"
open(target, "w").write(s)
PY
echo "Alt+Tab bind installed in $KEYBINDS"
echo "Hyprland reloads automatically; if not: hyprctl reload"
