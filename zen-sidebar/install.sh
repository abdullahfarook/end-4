#!/usr/bin/env bash
# Zen compact-mode sidebar: stop the open/close flicker when the pointer hovers just outside the sidebar edge (idempotent).
# Zen closes the sidebar sidebar-keep-hover.duration ms after the pointer leaves; the default 150 ms makes a jittery edge hover flap it open/closed.
# hover-hack-delay (default 0) re-checks :hover after a short delay before treating a mouseleave as real: over the tab close button and other
# natively handled spots Firefox briefly reports the pointer as having left, which collapsed the sidebar instantly.
# keep-hover.duration is tiny (120) on purpose: Zen's onEnter returns early while the sidebar is still expanded and never cancels the keep-hover flash timer
# (ZenCompactMode.mjs), so a brief mouseleave + re-enter (tab/close buttons) left a timer that collapsed the sidebar under the pointer. With a tiny value the
# hover-hack-delay :hover re-check filters the flicker, and the stray timer is short. It must not be 0: leaving the sidebar then skips flashElement, so a
# pending 60 s edge timer stays registered, and flashElement refuses to re-open the sidebar on the next left-edge hover while a timer is registered.
# Same bug on the screen-edge path: when the pointer crosses the window edge, Zen (no global mouse tracker on Linux) opens the sidebar and arms a
# toolbar-hide-after-hover.duration timer that is never cancelled when the pointer then moves into the sidebar, so it collapsed after exactly 1 s
# under the pointer. 60 s makes that timer irrelevant; the next mousemove outside the sidebar still closes it immediately.
# Written to the profile's user.js, so it applies at the next Zen start (about:config shows the same prefs for a live change).
set -euo pipefail
PROFILE="$HOME/.zen/c0u92kn2.Default (release)"; UJ="$PROFILE/user.js"
BACKUP="$HOME/backups/zen-sidebar/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP"; [ -f "$UJ" ] && cp "$UJ" "$BACKUP/" || true
touch "$UJ"
python3 - "$UJ" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
block = '''// >>> zen-sidebar >>>
user_pref("zen.view.compact.sidebar-keep-hover.duration", 120);
user_pref("zen.view.compact.toolbar-hide-after-hover.duration", 60000);
user_pref("zen.view.compact.hover-hack-delay", 150);
// <<< zen-sidebar <<<'''
pat = r"// >>> zen-sidebar >>>.*?// <<< zen-sidebar <<<"
t = re.sub(pat, lambda _: block, t, flags=re.S) if re.search(pat, t, re.S) else t.rstrip("\n") + ("\n" if t.strip() else "") + block + "\n"
open(p, "w").write(t)
PY
echo "Done. Restart Zen to apply (or set zen.view.compact.sidebar-keep-hover.duration=120 in about:config to apply that part now)."
