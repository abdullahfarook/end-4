#!/usr/bin/env bash
# ALT+Tab: Windows-style MRU workspace switcher with overview (safe to run repeatedly).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
for f in super-tab.sh super-tab-release.sh ws-mru-lib.sh ws-mru-watch.sh; do install -Dm755 "$REPO/$f" "$HOME/.config/hypr/custom/$f"; done
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
pgrep -f ws-mru-watch.sh >/dev/null || { nohup "$HOME/.config/hypr/custom/ws-mru-watch.sh" >/dev/null 2>&1 & disown; }
echo "Installed. Hyprland reloads automatically; if not: hyprctl reload"
