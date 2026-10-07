#!/usr/bin/env bash
# Per-monitor workspace groups (idempotent): appends monitor-workspaces.lua to custom/rules.lua.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.config/hypr/custom/rules.lua"
BACKUP="$HOME/backups/monitor-workspaces/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$TARGET" "$BACKUP/"
python3 - "$TARGET" "$REPO/monitor-workspaces.lua" <<'PY'
import re, sys
target, snippet = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
s = open(target).read()
pat = r"-- >>> monitor-workspaces >>>.*?-- <<< monitor-workspaces <<<"
s = re.sub(pat, lambda _: snippet, s, flags=re.S) if re.search(pat, s, re.S) else s.rstrip("\n") + "\n\n" + snippet + "\n"
open(target, "w").write(s)
PY
echo "Done."
