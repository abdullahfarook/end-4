#!/usr/bin/env bash
# File search widget: bar button + popup (Everything-style, fd index + fzf --filter backend) (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"; BAR="$Q/modules/ii/bar/BarContent.qml"
BACKUP="$HOME/backups/file-search/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$BAR" "$BACKUP/"
"$REPO/../widget-base/install.sh"   # shared panel behavior (WidgetBase.qml)
for f in FileSearchButton.qml FileSearchPopup.qml; do
  [ -f "$Q/modules/ii/bar/$f" ] && cp "$Q/modules/ii/bar/$f" "$BACKUP/"
done
install -Dm644 "$REPO/FileSearchButton.qml" "$Q/modules/ii/bar/FileSearchButton.qml"
rm -f "$Q/modules/ii/bar/FileSearchPopup.qml"   # merged into FileSearchButton.qml
python3 - "$BAR" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
if "FileSearchButton {" not in s:
    m = re.search(r"( *)DockerButton \{.*?\n\1\}\n", s, re.S)
    ind = m.group(1)
    block = (f"\n{ind}FileSearchButton {{ // file search (fzf) button\n{ind}    Layout.alignment: Qt.AlignVCenter\n"
             f"{ind}    Layout.leftMargin: 2\n"
             f"{ind}    colBackground: barLeftSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)\n{ind}}}\n")
    s = s[:m.end()] + block + s[m.end():]
    open(p, "w").write(s)
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
