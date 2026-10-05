#!/usr/bin/env bash
# Alternative to ../install.sh: ALT+Tab MRU switcher in pure Lua, no watcher or scripts. Run only one of the two.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
# remove helper scripts from earlier versions
rm -f "$HOME"/.config/hypr/custom/{super-tab.sh,super-tab-release.sh,ws-mru-lib.sh,ws-mru-watch.sh}
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
