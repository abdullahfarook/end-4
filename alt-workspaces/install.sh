#!/usr/bin/env bash
# ALT+1..0 switch workspaces, disabled while Zen Browser is focused (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
BACKUP="$HOME/backups/alt-workspaces/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$KEYBINDS" "$BACKUP/"
python3 - "$KEYBINDS" "$REPO/alt-workspaces.lua" <<'PY'
import re, sys
target, snippet = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
s = open(target).read()
pat = r"-- >>> alt-workspaces >>>.*?-- <<< alt-workspaces <<<"
s = re.sub(pat, lambda _: snippet, s, flags=re.S) if re.search(pat, s, re.S) else s.rstrip("\n") + "\n\n" + snippet + "\n"
open(target, "w").write(s)
PY
echo "Done."
