#!/usr/bin/env bash
# Only the bar's AI/start button opens the left sidebar: clicking empty bar space or the window title no longer does (idempotent).
set -euo pipefail
Q="$HOME/.config/quickshell/ii"; BAR="$Q/modules/ii/bar/BarContent.qml"
BACKUP="$HOME/backups/ai-button-only/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP"; cp "$BAR" "$BACKUP/"; echo "Backed up to $BACKUP"
python3 - "$BAR" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
pat = r"( *)onPressed: event => \{\n\s*if \(event\.button === Qt\.LeftButton\)\n\s*GlobalStates\.sidebarLeftOpen = !GlobalStates\.sidebarLeftOpen;\n\s*\}\n"
m = re.search(pat, s)
if m:
    ind = m.group(1)
    s = s[:m.start()] + f"{ind}// left-click on empty bar space no longer opens the sidebar (ai-button-only); use the button\n" + s[m.end():]
    open(p, "w").write(s); print("patched")
else:
    print("already patched or pattern not found")
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
