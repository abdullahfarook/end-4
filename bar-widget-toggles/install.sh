#!/usr/bin/env bash
# Settings > Bar > "Bar widgets": switches to enable/disable each left-bar button (idempotent).
# Also fixes the tray tooltip opening off-screen on first hover (re-anchor once its size is known).
set -euo pipefail
Q="$HOME/.config/quickshell/ii"
B="$HOME/backups/bar-widget-toggles/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$B"
cp "$Q/modules/common/Config.qml" "$Q/modules/ii/bar/BarContent.qml" "$Q/modules/ii/bar/RevealSlot.qml" \
   "$Q/modules/settings/BarConfig.qml" "$Q/modules/common/widgets/PopupToolTip.qml" "$Q/modules/ii/bar/StyledPopup.qml" "$B/"
python3 - "$Q" <<'PY'
import re, sys
Q = sys.argv[1]
names = [("mail","mailBtn","mail","Mail"),("teams","teamsBtn","groups","Teams"),("git","gitBtn","commit","Git"),
         ("consolePanel","consoleBtn","terminal","Console"),("fileSearch","fileBtn","search","File search"),
         ("docker","dockerBtn","deployed_code","Docker"),("taskManager","taskBtn","memory","Task manager"),
         ("google","googleBtn","travel_explore","Google search"),("gist","gistBtn","code","Gists")]
def rw(path, fn):
    s = open(path).read(); n = fn(s)
    if n != s: open(path, "w").write(n)

def config(s):
    if "property JsonObject buttons" in s: return s
    m = re.search(r"\n( *)property JsonObject bar: JsonObject \{\n", s)
    i = m.group(1) + "    "
    blk = f"{i}property JsonObject buttons: JsonObject {{\n" + "".join(f"{i}    property bool {k}: true\n" for k,*_ in names) + f"{i}}}\n"
    return s[:m.end()] + blk + s[m.end():]
rw(Q + "/modules/common/Config.qml", config)

def slot(s):
    if "property bool active" in s: return s
    s = s.replace("    property bool pinned: false\n", "    property bool pinned: false\n    property bool active: true   // false: the slot is hidden entirely (disabled in Settings)\n")
    s = s.replace("readonly property bool shown: open || pinned", "readonly property bool shown: active && (open || pinned)")
    return s
rw(Q + "/modules/ii/bar/RevealSlot.qml", slot)

def bar(s):
    for k, btn, *_ in names:
        pat = re.compile(r"(RevealSlot \{\n(?:(?!RevealSlot \{).)*?)(\n *pinned: [^\n]*\n)(?=(?:(?!RevealSlot \{).)*?id: " + btn + r"\b)", re.S)
        if f"Config.options.bar.buttons.{k}" in s: continue
        s, c = pat.subn(lambda m: m.group(1) + m.group(2) + f"                    active: Config.options.bar.buttons.{k}\n", s, 1)
        if not c: sys.exit("slot not found: " + btn)
    return s
rw(Q + "/modules/ii/bar/BarContent.qml", bar)

def settings(s):
    if "Bar widgets" in s: return s
    rows = "".join(f'''        ConfigSwitch {{
            buttonIcon: "{ic}"
            text: Translation.tr("{lab}")
            checked: Config.options.bar.buttons.{k}
            onCheckedChanged: Config.options.bar.buttons.{k} = checked
        }}
''' for k,_,ic,lab in names)
    sec = f'''    ContentSection {{
        icon: "widgets"
        title: Translation.tr("Bar widgets")

{rows}    }}

'''
    m = re.search(r"    ContentSection \{\n        icon: \"shelf_auto_hide\"", s)
    return s[:m.start()] + sec + s[m.start():]
rw(Q + "/modules/settings/BarConfig.qml", settings)

def tip(s):
    if "onImplicitWidthChanged" in s: return s
    return s.replace("            visible: true\n            anchor {",
      "            visible: true\n            onImplicitWidthChanged: anchor.updateAnchor()\n            onImplicitHeightChanged: anchor.updateAnchor()\n            anchor {", 1)
rw(Q + "/modules/common/widgets/PopupToolTip.qml", tip)
PY
# bar popups (e.g. the window-title popup) centred on a target near the screen edge must not start left of the screen
python3 - "$Q/modules/ii/bar/StyledPopup.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
if "Math.max(0, root.QsWindow" not in s:
    s = s.replace("if (!Config.options.bar.vertical) return root.QsWindow?.mapFromItem(\n                    root.hoverTarget, \n                    (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0\n                ).x;",
                  "if (!Config.options.bar.vertical) return Math.max(0, root.QsWindow?.mapFromItem(\n                    root.hoverTarget, \n                    (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0\n                ).x);")
    open(p, "w").write(s)
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
