#!/usr/bin/env bash
# Shared panel behavior, installed by every panel widget (idempotent):
#  - WidgetBase.qml: shell panels (bar button + side panel, click-away, Esc, per-monitor close rules)
#  - side-panel.sh + keybind snippet: window panels on special workspaces (AI, Console, Teams, Git), same rules
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
D="$HOME/.config/quickshell/ii/modules/ii/bar"; H="$HOME/.config/hypr/custom"; KEYBINDS="$H/keybinds.lua"
BACKUP="$HOME/backups/widget-base/$(date +%Y%m%d-%H%M%S)"
backup() { mkdir -p "$BACKUP"; cp "$@" "$BACKUP/"; }
[ -f "$D/WidgetBase.qml" ] && ! cmp -s "$REPO/WidgetBase.qml" "$D/WidgetBase.qml" && backup "$D/WidgetBase.qml"
[ -f "$H/side-panel.sh" ] && ! cmp -s "$REPO/side-panel.sh" "$H/side-panel.sh" && backup "$H/side-panel.sh"
grep -q ">>> side-panel >>>" "$KEYBINDS" || backup "$KEYBINDS"
install -Dm644 "$REPO/WidgetBase.qml" "$D/WidgetBase.qml"
install -Dm755 "$REPO/side-panel.sh" "$H/side-panel.sh"
# Per-panel click-away/watch scripts replaced by side-panel.sh
for f in ai-sidebar-clickaway.sh ai-sidebar-watch.sh teams-panel-clickaway.sh vscode-git-clickaway.sh; do
    [ -f "$H/$f" ] && { backup "$H/$f"; rm -f "$H/$f"; }
done
python3 - "$KEYBINDS" "$REPO/side-panel-keybinds.lua" <<'PY'
import re, sys
target, snippet = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
s = open(target).read()
pat = r"-- >>> side-panel >>>.*?-- <<< side-panel <<<"
s = re.sub(pat, lambda _: snippet, s, flags=re.S) if re.search(pat, s, re.S) else s.rstrip("\n") + "\n\n" + snippet + "\n"
open(target, "w").write(s)
PY
true
