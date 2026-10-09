#!/usr/bin/env bash
# Kitty: right click copies+clears the selection or pastes, ctrl+v pastes. Idempotent.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"; T="$HOME/.config/kitty/kitty.conf"
BACKUP="$HOME/backups/kitty/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP"; cp "$T" "$BACKUP/"; echo "Backed up to $BACKUP"
install -Dm755 "$REPO/rclick.sh" "$HOME/.config/kitty/rclick.sh"
python3 - "$T" "$REPO/kitty-clipboard.conf" <<'PY'
import re, sys
target, snippet = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
s = open(target).read()
pat = r"# >>> kitty-clipboard >>>.*?# <<< kitty-clipboard <<<"
s = re.sub(pat, lambda _: snippet, s, flags=re.S) if re.search(pat, s, re.S) else s.rstrip("\n") + "\n\n" + snippet + "\n"
open(target, "w").write(s)
PY
echo "Done. New kitty windows pick it up; in running ones press ctrl+shift+f5 to reload."
