#!/usr/bin/env bash
# Zen compact-mode sidebar: stop the open/close flicker when the pointer hovers just outside the sidebar edge (idempotent).
# Zen closes the sidebar sidebar-keep-hover.duration ms after the pointer leaves; the default 150 ms makes a jittery edge hover flap it open/closed.
# Written to the profile's user.js, so it applies at the next Zen start (about:config shows the same prefs for a live change).
set -euo pipefail
PROFILE="$HOME/.zen/c0u92kn2.Default (release)"; UJ="$PROFILE/user.js"
BACKUP="$HOME/backups/zen-sidebar/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP"; [ -f "$UJ" ] && cp "$UJ" "$BACKUP/" || true
touch "$UJ"
python3 - "$UJ" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
block = '''// >>> zen-sidebar >>>
user_pref("zen.view.compact.sidebar-keep-hover.duration", 600);
user_pref("zen.view.compact.toolbar-hide-after-hover.duration", 1000);
// <<< zen-sidebar <<<'''
pat = r"// >>> zen-sidebar >>>.*?// <<< zen-sidebar <<<"
t = re.sub(pat, lambda _: block, t, flags=re.S) if re.search(pat, t, re.S) else t.rstrip("\n") + ("\n" if t.strip() else "") + block + "\n"
open(p, "w").write(t)
PY
echo "Done. Restart Zen to apply (or set zen.view.compact.sidebar-keep-hover.duration=600 in about:config for an immediate change)."
