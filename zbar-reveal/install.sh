#!/usr/bin/env bash
# Left bar: only the AI button is always visible; the other buttons slide out of it inside the bar when the pointer is on the left side of the bar (icons or title).
# Right side: the clock date and util buttons reveal with the same Revealer animation (patch-right.py).
# Buttons with an unread count (Mail, Teams) stay visible until the count is 0. Run AFTER the other bar installers (patches BarContent.qml; idempotent).
set -euo pipefail
Q="$HOME/.config/quickshell/ii/modules/ii/bar"; BAR="$Q/BarContent.qml"
B="$HOME/backups/zbar-reveal/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$B"; cp "$BAR" "$Q/ClockWidget.qml" "$Q/UtilButtons.qml" "$B/"
install -Dm644 "$(dirname "$0")/RevealSlot.qml" "$Q/RevealSlot.qml"
python3 - "$BAR" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
if "RevealSlot" in s: sys.exit(0)
pins = {"MailButton": ("mailBtn", "mailBtn.newTotal > 0 || mailBtn.popupOpen"), "TeamsButton": ("teamsBtn", "teamsBtn.unread > 0"),
        "FileSearchButton": ("fileBtn", "fileBtn.open"), "DockerButton": ("dockerBtn", "dockerBtn.open"),
        "TaskManagerButton": ("taskBtn", "taskBtn.open"), "GoogleSearchButton": ("googleBtn", "googleBtn.open")}
names = ["VscodeGitButton", "ConsoleButton", "MailButton", "TeamsButton", "FileSearchButton", "DockerButton", "TaskManagerButton", "GoogleSearchButton"]
def block(n):
    m = re.search(r"^( *)" + n + r" \{[^\n]*\n.*?^\1\}\n", s, re.S | re.M)
    if not m: sys.exit(n + " not found")
    return m
for n in names:
    m = block(n); ind = m.group(1); body = m.group(0)
    lines = body.rstrip("\n").split("\n")
    if n in pins: lines.insert(1, ind + "    id: " + pins[n][0])
    inner = "\n".join("    " + l if l else l for l in lines)
    pin = f"{ind}    pinned: {pins[n][1]}\n" if n in pins else ""
    s = s[:m.start()] + f"{ind}RevealSlot {{\n{ind}    open: iconRow.hot\n{pin}{inner}\n{ind}}}\n" + s[m.end():]
a = block("LeftSidebarButton"); last = re.search(r"^( *)RevealSlot \{\n(?:(?!^\1RevealSlot).)*?GoogleSearchButton \{.*?^\1\}\n", s, re.S | re.M)
start, end = a.start(), last.end()
ind = a.group(1)
chunk = s[start:end]
chunk = "\n".join("    " + l if l else l for l in chunk.split("\n"))
head = f"""{ind}RowLayout {{ // icon row: AI button always visible, the rest slide out on hover
{ind}    id: iconRow
{ind}    spacing: 0
{ind}    Layout.alignment: Qt.AlignVCenter
{ind}    property bool hot: false
{ind}    readonly property bool wantOpen: barLeftSideMouseArea.hovered
{ind}    onWantOpenChanged: {{ if (wantOpen) {{ closeTimer.stop(); hot = true }} else closeTimer.restart() }}
{ind}    Timer {{ id: closeTimer; interval: 700; onTriggered: iconRow.hot = false }}
"""
s = s[:start] + head + chunk.rstrip(" ") + f"{ind}}}\n" + s[end:]
open(p, "w").write(s)
PY
python3 "$(dirname "$0")/reorder.py" "$BAR"
python3 "$(dirname "$0")/patch-right.py" "$BAR" "$Q/ClockWidget.qml"
python3 "$(dirname "$0")/patch-util.py" "$Q/UtilButtons.qml"
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
