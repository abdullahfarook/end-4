#!/usr/bin/env bash
# Search button in the bar, right of the workspaces; opens the SUPER-key overview/launcher (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"; BAR="$Q/modules/ii/bar/BarContent.qml"
BACKUP="$HOME/backups/bar-search/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$BAR" "$BACKUP/"
install -Dm644 "$REPO/search.svg" "$Q/assets/icons/bar-search/search.svg"
install -Dm644 "$REPO/SearchButton.qml" "$Q/modules/ii/bar/SearchButton.qml"
python3 - "$BAR" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
if "SearchButton {" not in s:
    m = re.search(r"( *)Workspaces \{.*?\n\1\}\n", s, re.S)
    ind = m.group(1)
    block = f"\n{ind}SearchButton {{ // search / launcher button\n{ind}    Layout.alignment: Qt.AlignVCenter\n{ind}}}\n"
    s = s[:m.end()] + block + s[m.end():]
    open(p, "w").write(s)
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
