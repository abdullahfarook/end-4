#!/usr/bin/env python3
# Keep a bar slot revealed while its right-click menu is open (otherwise the slot collapses when the pointer leaves the bar
# and the menu jumps to the left edge). usage: patch-pins.py BarContent.qml (idempotent)
import re, sys
p = sys.argv[1]; s = open(p).read()
for btn, bid in (("VscodeGitButton", "gitBtn"), ("ConsoleButton", "consoleBtn"), ("TeamsButton", "teamsBtn")):
    m = re.search(r"^( *)RevealSlot \{\n((?:(?!^\1\}).*\n)*?)\1    " + btn + r" \{", s, re.M)
    assert m, btn + " slot not found"
    ind, head = m.group(1), m.group(2)
    if bid + ".menuOpen" in head: continue
    new = head
    if "pinned:" in head: new = re.sub(r"pinned: (.*)", lambda x: "pinned: " + x.group(1) + " || " + bid + ".menuOpen", head, 1)
    else: new = head + ind + "    pinned: " + bid + ".menuOpen\n"
    s = s[:m.start(2)] + new + s[m.end(2):]
    if "id: " + bid not in s:
        s = re.sub(r"(" + btn + r" \{[^\n]*\n)", lambda x: x.group(1) + ind + "        id: " + bid + "\n", s, 1)
open(p, "w").write(s)
# also keep the whole row revealed while any of those menus is open, so the icon under the menu does not move
s = open(p).read()
old = "readonly property bool wantOpen: barLeftSideMouseArea.hovered\n"
if "gitBtn.menuOpen" not in s.split(old)[0][-0:] and old in s:
    s = s.replace(old, "readonly property bool wantOpen: barLeftSideMouseArea.hovered || gitBtn.menuOpen || consoleBtn.menuOpen || teamsBtn.menuOpen\n", 1)
    open(p, "w").write(s)
