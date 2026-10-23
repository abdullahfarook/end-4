#!/usr/bin/env python3
# Icon row layout: AI first, then Mail and Teams, then the rest. The row is a one-row GridLayout so Mail/Teams columns can swap:
# a pinned (notification) icon is always placed before an unpinned one, so it never moves when the others reveal.
# usage: reorder.py BarContent.qml (idempotent)
import re, sys
p = sys.argv[1]; s = open(p).read()

def slot(n, optional=False):
    for m in re.finditer(r"^( *)RevealSlot \{\n.*?^\1\}\n\n?", s, re.S | re.M):
        if n + " {" in m.group(0): return m.group(0)
    if optional: return None
    sys.exit(n + " slot not found")

if s.index(slot("MailButton")) > s.index(slot("VscodeGitButton")):
    mail, teams, git = slot("MailButton"), slot("TeamsButton"), slot("VscodeGitButton")
    s = s.replace(mail, "", 1).replace(teams, "", 1)
    g = s.index(git); s = s[:g] + mail + teams + s[g:]

if "GridLayout" not in s:
    cols = {"MailButton": "iconRow.mailCol", "TeamsButton": "iconRow.teamsCol", "VscodeGitButton": 3, "ConsoleButton": 4,
            "FileSearchButton": 5, "DockerButton": 6, "TaskManagerButton": 7, "GoogleSearchButton": 8, "GistButton": 9}
    for n, c in cols.items():
        b = slot(n, optional=(n == "GistButton"))
        if b is None: continue
        i = b.index("\n") + 1
        ind = re.match(r" *", b).group(0) + "    "
        s = s.replace(b, b[:i] + f"{ind}Layout.row: 0\n{ind}Layout.column: {c}\n" + b[i:], 1)
    old = "RowLayout { // icon row: AI button always visible, the rest slide out on hover\n                id: iconRow\n                spacing: 0\n"
    new = ("GridLayout { // icon row: AI button always visible, the rest slide out on hover\n                id: iconRow\n                rows: 1\n                columnSpacing: 0\n                rowSpacing: 0\n"
           "                readonly property bool mailPinned: mailBtn.newTotal > 0 || mailBtn.popupOpen\n"
           "                readonly property bool teamsPinned: teamsBtn.unread > 0\n"
           "                readonly property int mailCol: (teamsPinned && !mailPinned) ? 2 : 1\n"
           "                readonly property int teamsCol: 3 - mailCol\n")
    assert old in s, "icon row header not found"
    s = s.replace(old, new, 1)
    old = "                    id: leftSidebarButton\n"
    s = s.replace(old, old + "                    Layout.row: 0\n                    Layout.column: 0\n", 1)
open(p, "w").write(s)
