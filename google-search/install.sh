#!/usr/bin/env bash
# Google widget: bar button + popup with a search field and an embedded QtWebEngine browser (gsearch.py) below it (idempotent).
# Needs: pacman -S pyside6.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"; BAR="$Q/modules/ii/bar/BarContent.qml"; KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
BACKUP="$HOME/backups/google-search/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$BAR" "$KEYBINDS" "$BACKUP/"
python3 -c "import PySide6.QtWebEngineWidgets" 2>/dev/null || { echo "pyside6 missing: pkexec pacman -S pyside6" >&2; exit 1; }
for f in GoogleSearchButton.qml GoogleSearchPopup.qml; do
  [ -f "$Q/modules/ii/bar/$f" ] && cp "$Q/modules/ii/bar/$f" "$BACKUP/"
  install -Dm644 "$REPO/$f" "$Q/modules/ii/bar/$f"
done
install -Dm755 "$REPO/gsearch.py" "$HOME/.config/hypr/custom/gsearch.py"
python3 - "$BAR" "$KEYBINDS" "$REPO/google-search-rules.lua" <<'PY'
import re, sys
bar, kb, rules = sys.argv[1:4]
s = open(bar).read()
if "GoogleSearchButton {" not in s:
    m = re.search(r"( *)FileSearchButton \{.*?\n\1\}\n", s, re.S)
    ind = m.group(1)
    block = (f"\n{ind}GoogleSearchButton {{ // Google (embedded browser) button\n{ind}    Layout.alignment: Qt.AlignVCenter\n"
             f"{ind}    Layout.leftMargin: 2\n"
             f"{ind}    colBackground: barLeftSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)\n{ind}}}\n")
    s = s[:m.end()] + block + s[m.end():]
    open(bar, "w").write(s)
snippet = open(rules).read().rstrip("\n")
t = open(kb).read()
pat = r"-- >>> google-search >>>.*?-- <<< google-search <<<"
t = re.sub(pat, lambda _: snippet, t, flags=re.S) if re.search(pat, t, re.S) else t.rstrip("\n") + "\n\n" + snippet + "\n"
open(kb, "w").write(t)
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
