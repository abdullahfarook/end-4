#!/usr/bin/env bash
# Docker widget: bar button (running count) + popup with container list, CPU/mem, and live logs (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"; BAR="$Q/modules/ii/bar/BarContent.qml"
BACKUP="$HOME/backups/docker-widget/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$BAR" "$BACKUP/"
"$REPO/../widget-base/install.sh"   # shared panel behavior (WidgetBase.qml)
for f in DockerButton.qml DockerPopup.qml; do
  [ -f "$Q/modules/ii/bar/$f" ] && cp "$Q/modules/ii/bar/$f" "$BACKUP/"
done
install -Dm644 "$REPO/DockerButton.qml" "$Q/modules/ii/bar/DockerButton.qml"
rm -f "$Q/modules/ii/bar/DockerPopup.qml"   # merged into DockerButton.qml
python3 - "$BAR" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
if "DockerButton {" not in s:
    m = re.search(r"( *)TeamsButton \{.*?\n\1\}\n", s, re.S)
    ind = m.group(1)
    block = (f"\n{ind}DockerButton {{ // Docker containers button\n{ind}    Layout.alignment: Qt.AlignVCenter\n"
             f"{ind}    Layout.leftMargin: 2\n"
             f"{ind}    colBackground: barLeftSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)\n{ind}}}\n")
    s = s[:m.end()] + block + s[m.end():]
    open(p, "w").write(s)
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
