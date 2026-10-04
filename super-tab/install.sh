#!/usr/bin/env bash
# SUPER+Tab opens the overview; repeated Tab presses cycle workspaces (safe to run repeatedly).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
for f in super-tab.sh super-tab-release.sh; do install -Dm755 "$REPO/$f" "$HOME/.config/hypr/custom/$f"; done
touch "$KEYBINDS"
python3 - "$KEYBINDS" "$REPO/super-tab-keybinds.lua" <<'PY'
import re, sys
target, snippet = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
s = open(target).read()
pattern = r"-- >>> super-tab-workspaces >>>.*?-- <<< super-tab-workspaces <<<"
if re.search(pattern, s, re.S):
    s = re.sub(pattern, lambda _: snippet, s, flags=re.S)
else:
    s = s.rstrip("\n") + "\n\n" + snippet + "\n"
open(target, "w").write(s)
PY
echo "Installed. Hyprland reloads automatically; if not: hyprctl reload"
