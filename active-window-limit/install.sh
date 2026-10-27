#!/usr/bin/env bash
# Caps the bar's active-window title width (longer titles end in "..."). Change MAXW and re-run to adjust.
# Done inside ActiveWindow (colLayout width) so the outer bar layout/position stays untouched.
set -euo pipefail
MAXW=${MAXW:-170}
F="$HOME/.config/quickshell/ii/modules/ii/bar/ActiveWindow.qml"
BACKUP="$HOME/backups/active-window-limit/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$F" "$BACKUP/"
sed -i -e '/^        width: Math.min(parent.width, [0-9]*) \/\/ active-window-limit$/d' -e '/^        anchors.right: parent.right$/d' "$F"  # undo original/previous
sed -i "0,/^        anchors.left: parent.left\$/s##&\n        width: Math.min(parent.width, $MAXW) // active-window-limit#" "$F"
grep -q active-window-limit "$F" && echo "Applied (max ${MAXW}px). Restart the shell."
# Popup with the full title on hover (the shared bar StyledPopup, so it opens below the bar), only when the title is truncated.
python3 - "$F" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"\n        HoverHandler \{ id: titleHover \}.*?\n        \}\n(?=    \}\n)", "\n", s, flags=re.S)  # drop older tooltip version
s = re.sub(r"\n    Item \{ // active-window-tooltip.*?\n    \}\n(?=\n\}\s*$)", "", s, flags=re.S)
if "id: titleText" not in s:
    s = s.replace("        StyledText {\n            Layout.fillWidth: true\n            font.pixelSize: Appearance.font.pixelSize.small\n",
                  "        StyledText {\n            id: titleText // active-window-tooltip\n            Layout.fillWidth: true\n            font.pixelSize: Appearance.font.pixelSize.small\n", 1)
block = """
    Item { // active-window-tooltip
        id: hoverArea
        anchors.fill: colLayout
        readonly property bool containsMouse: hh.hovered && titleText.truncated
        HoverHandler { id: hh }
        StyledPopup {
            hoverTarget: hoverArea
            StyledText {
                width: Math.min(implicitWidth, 520)
                wrapMode: Text.Wrap
                text: titleText.text
            }
        }
    }
"""
s = re.sub(r"(\n\}\s*)$", lambda m: block + m.group(1), s, count=1)
open(p, "w").write(s)
PY
echo "Hover popup added."
