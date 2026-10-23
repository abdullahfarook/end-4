#!/usr/bin/env bash
# Bar: show the swap indicator only when swap is at least 50% full or the resources widget is hovered (idempotent; replaces the earlier ">= 100 MiB used" rule).
set -euo pipefail
F="$HOME/.config/quickshell/ii/modules/ii/bar/Resources.qml"
BACKUP="$HOME/backups/swap-bar-threshold/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP"; cp "$F" "$BACKUP/"
python3 - "$F" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p).read()
t = re.sub(r"( *)// (?:swapUsed is in KiB|show swap only).*\n( *)shown: ResourceUsage\.swapUsed(?:Percentage >= 0\.5.*| >= 100 \* 1024)",
           r"\1// show swap only when at least 50% full, or while the widget is hovered\n\2shown: ResourceUsage.swapUsedPercentage >= 0.5 || root.containsMouse", t)
t = t.replace("swapUsedPercentage >= 0.5 || root.containsMouse", "swapUsedPercentage >= 0.5 || root.hot")
if "property bool hot" not in t:
    t = t.replace("    hoverEnabled: !Config.options.bar.tooltips.clickToShow\n", """    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    property bool hot: false
    onContainsMouseChanged: { if (containsMouse) { closeTimer.stop(); hot = true } else closeTimer.restart() }
    Timer { id: closeTimer; interval: 700; onTriggered: root.hot = false }
""", 1)
open(p, "w").write(t)
PY
grep -n "swapUsedPercentage >= 0.5 || root.hot" "$F" >/dev/null && echo "Applied. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
