#!/usr/bin/env python3
"""One-off migration helper: turn an old <X>Popup.qml (Scope + click-away layer + side panel window + card) into the
panelContent of a WidgetBase-based button file. Prints the content block; the caller merges it into the button file.

usage: migrate.py POPUP.qml ID
  ID: id for the content root (replaces the popup's `root`; the button file's `root` is the WidgetBase).
Keeps: the popup's own state/functions/processes (between `property bool visible` and the shared monitor logic) and
the card's children. Drops: Scope, required target, visible, the shared close logic, both PanelWindows, the card itself.
"""
import re
import sys

src, ident = sys.argv[1], sys.argv[2]
lines = open(src).read().split("\n")
while lines and lines[-1] == "":
    lines.pop()

def find(pred, start=0):
    for i in range(start, len(lines)):
        if pred(lines[i]):
            return i
    raise SystemExit(f"pattern not found in {src}")

state_start = find(lambda l: l.strip() == "property bool visible: true") + 1
state_end = find(lambda l: l.strip().startswith("property real openedAt"))
card = find(lambda l: l.strip() == "id: card", state_end)
body_start = find(lambda l: l.strip() == "clip: true", card) + 1
# file ends with: card "}" (indent 4), window "}" (indent 4), Scope "}"
assert lines[-1] == "}" and lines[-2].strip() == "}" and lines[-3].strip() == "}", "unexpected file tail"
body_end = len(lines) - 3

state = [l for l in lines[state_start:state_end] if "required property Item target" not in l]
body = lines[body_start:body_end]

def fix(block, indent):
    s = "\n".join(block)
    s = s.replace("root.visible = false", "@@CLOSE@@").replace("running: root.visible", "running: true")
    # cleanup that ran when the old popup was hidden: now the content is destroyed on close
    s = re.sub(r"onVisibleChanged: if \(!visible\) \{(.*?)\}", r"Component.onDestruction: {\1}", s)
    s = re.sub(r"\broot\.", ident + ".", s)
    s = s.replace("@@CLOSE@@", "root.close()")
    s = s.replace("mapToItem(card,", f"mapToItem({ident},")
    s = re.sub(r"\bcard\.(width|height)\b", ident + r".\1", s)
    return "\n".join((indent + l) if l.strip() else "" for l in s.split("\n"))

out = fix(state, "    ").rstrip() + "\n\n" + fix(body, "")
leftover = [w for w in ("card", "win", "target", "popupMon", "wsCheck") if re.search(r"\b%s\b" % w, out)]
print(out)
if leftover:
    print(f"WARNING: still references {leftover}", file=sys.stderr)
