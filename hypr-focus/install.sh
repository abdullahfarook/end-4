#!/usr/bin/env bash
# Sets misc:focus_on_activate = false via ~/.config/hypr/custom/general.lua (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
T="$HOME/.config/hypr/custom/general.lua"
B="$HOME/backups/hypr-focus/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$B"; touch "$T"; cp "$T" "$B/"
python3 - "$T" "$REPO/focus.lua" <<'PY'
import re, sys
t, snip = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
s = open(t).read()
pat = r"-- >>> hypr-focus >>>.*?-- <<< hypr-focus <<<"
s = re.sub(pat, lambda _: snip, s, flags=re.S) if re.search(pat, s, re.S) else (s.rstrip("\n") + "\n\n" + snip + "\n").lstrip("\n")
open(t, "w").write(s)
PY
echo "Installed. Hyprland reloads automatically."
