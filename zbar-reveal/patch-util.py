#!/usr/bin/env python3
# UtilButtons: the performance-profile button stays visible; the other util buttons slide out (RevealSlot) while `expanded`.
# usage: patch-util.py UtilButtons.qml (idempotent; BarContent passes expanded: rightCenterGroup.hot)
import sys
p = sys.argv[1]; s = open(p).read()
if "RevealSlot" in s: sys.exit(0)
a = s.index("        Loader {\n            active: Config.options.bar.utilButtons.showScreenSnip")
b = s.index("        Loader {\n            active: Config.options.bar.utilButtons.showPerformanceProfileToggle")
chunk = "".join(("        " + l if l.strip() else l) for l in s[a:b].splitlines(True))
new = "        RevealSlot {\n            open: root.expanded\n            gap: rowLayout.spacing\n            RowLayout {\n                spacing: rowLayout.spacing\n" + chunk + "            }\n        }\n\n"
s = s[:a] + new + s[b:]
s = s.replace("    property bool borderless: Config.options.bar.borderless\n", "    property bool borderless: Config.options.bar.borderless\n    property bool expanded: true\n", 1)
open(p, "w").write(s)
