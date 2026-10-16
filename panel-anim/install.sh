#!/usr/bin/env bash
# Native slide-left animation for the special-workspace panels (idempotent; block replaced between markers).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"; T="$HOME/.config/hypr/custom/general.lua"
BACKUP="$HOME/backups/panel-anim/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP"; cp "$T" "$BACKUP/" 2>/dev/null || true
python3 - "$T" "$REPO/panel-anim.lua" <<'PY'
import re, sys
t, b = sys.argv[1:3]; s = open(t).read() if __import__("os").path.exists(t) else ""
blk = open(b).read()
s = re.sub(r"-- >>> panel-anim >>>.*?-- <<< panel-anim <<<\n", "", s, flags=re.S)
open(t, "w").write(s.rstrip("\n") + "\n\n" + blk)
PY
echo "Done (Hyprland reloads by itself)."
