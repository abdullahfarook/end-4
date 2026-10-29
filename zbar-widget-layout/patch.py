#!/usr/bin/env python3
# usage: patch.py ~/.config/quickshell/ii/modules (idempotent)
import re, sys
Q = sys.argv[1]
# key, button id, icon, label (same keys as bar-widget-toggles)
W = [("mail","mailBtn","mail","Mail"),("teams","teamsBtn","groups","Teams"),("git","gitBtn","commit","Git"),
     ("consolePanel","consoleBtn","terminal","Console"),("fileSearch","fileBtn","search","File search"),
     ("docker","dockerBtn","deployed_code","Docker"),("taskManager","taskBtn","memory","Task manager"),
     ("google","googleBtn","travel_explore","Google search"),("gist","gistBtn","code","Gists")]
keys = [k for k, *_ in W]
jskeys = "[" + ", ".join(f'"{k}"' for k in keys) + "]"

def rw(path, fn):
    s = open(path).read(); n = fn(s)
    if n != s: open(path, "w").write(n)

def config(s):
    if "property list<string> order" in s: return s
    m = re.search(r"\n( *)property JsonObject buttons: JsonObject \{\n", s)
    assert m, "bar.buttons not found (run bar-widget-toggles first)"
    i = m.group(1) + "    "
    return s[:m.end()] + f"{i}property list<string> order: {jskeys}\n{i}property list<string> pinned: []\n" + s[m.end():]
rw(Q + "/common/Config.qml", config)

def bar(s):
    if "function colOf" in s: return s
    old = re.search(r" *readonly property bool mailPinned:.*\n *readonly property bool teamsPinned:.*\n *readonly property int mailCol:.*\n *readonly property int teamsCol:.*\n", s)
    assert old, "icon row header not found (run zbar-reveal first)"
    ind = re.match(r" *", old.group(0)).group(0)
    slots = ", ".join(f"{k}: slot_{k}" for k in keys)
    new = f"""{ind}// column of each slot: shown-for-good slots (user pin, badge, open popup) first, then the rest, both in the Settings order
{ind}function slots() {{ return {{ {slots} }} }}
{ind}function order() {{
{ind}    const known = {jskeys}
{ind}    const o = Config.options.bar.buttons.order.filter(k => known.includes(k))
{ind}    return o.concat(known.filter(k => !o.includes(k)))
{ind}}}
{ind}function colOf(key) {{
{ind}    const sl = slots(), o = order()
{ind}    const firm = o.filter(k => sl[k].active && sl[k].pinned)
{ind}    return 1 + firm.concat(o.filter(k => !firm.includes(k))).indexOf(key)
{ind}}}
"""
    s = s[:old.start()] + new + s[old.end():]
    for k, btn, *_ in W:
        pat = re.compile(r"(RevealSlot \{\n)((?:(?!RevealSlot \{).)*?)(?=id: " + btn + r"\b)", re.S)
        def f(m):
            body = re.sub(r"Layout\.column: [^\n]*", f'Layout.column: iconRow.colOf("{k}")', m.group(2), count=1)
            body = re.sub(r"pinned: ([^\n]*)", lambda x: f'pinned: Config.options.bar.buttons.pinned.includes("{k}") || {x.group(1)}', body, count=1)
            i2 = re.match(r" *", body).group(0)
            return m.group(1) + f"{i2}id: slot_{k}\n" + body
        s, c = pat.subn(f, s, 1)
        if not c: sys.exit("slot not found: " + btn)
    return s
rw(Q + "/ii/bar/BarContent.qml", bar)

def settings(s):
    if "Pin: always show" in s: return s
    m = re.search(r"    ContentSection \{\n        icon: \"widgets\"\n        title: Translation.tr\(\"Bar widgets\"\)\n.*?\n    \}\n", s, re.S)
    assert m, "Bar widgets section not found (run bar-widget-toggles first)"
    meta = ", ".join(f'{k}: ["{ic}", "{lab}"]' for k, _, ic, lab in W)
    sec = f'''    ContentSection {{
        id: barWidgets
        icon: "widgets"
        title: Translation.tr("Bar widgets")
        readonly property var meta: ({{ {meta} }})
        readonly property var order: {{
            const known = Object.keys(meta)
            const o = Config.options.bar.buttons.order.filter(k => known.includes(k))
            return o.concat(known.filter(k => !o.includes(k)))
        }}
        function move(i, d) {{
            const o = order.slice(); const t = o[i]; o[i] = o[i + d]; o[i + d] = t
            Config.options.bar.buttons.order = o
        }}
        function togglePin(k) {{
            const p = Config.options.bar.buttons.pinned.filter(x => x !== k)
            if (p.length === Config.options.bar.buttons.pinned.length) p.push(k)
            Config.options.bar.buttons.pinned = p
        }}

        Repeater {{
            model: barWidgets.order
            delegate: RowLayout {{
                required property string modelData
                required property int index
                Layout.fillWidth: true
                spacing: 2
                ConfigSwitch {{
                    buttonIcon: barWidgets.meta[modelData][0]
                    text: Translation.tr(barWidgets.meta[modelData][1])
                    checked: Config.options.bar.buttons[modelData]
                    onCheckedChanged: Config.options.bar.buttons[modelData] = checked
                }}
                IconToolbarButton {{
                    implicitHeight: 32
                    text: "keep"
                    toggled: Config.options.bar.buttons.pinned.includes(modelData)
                    onClicked: barWidgets.togglePin(modelData)
                    StyledToolTip {{ text: Translation.tr("Pin: always show in the bar") }}
                }}
                IconToolbarButton {{
                    implicitHeight: 32
                    text: "arrow_upward"
                    enabled: index > 0
                    opacity: enabled ? 1 : 0.3
                    onClicked: barWidgets.move(index, -1)
                }}
                IconToolbarButton {{
                    implicitHeight: 32
                    text: "arrow_downward"
                    enabled: index < barWidgets.order.length - 1
                    opacity: enabled ? 1 : 0.3
                    onClicked: barWidgets.move(index, 1)
                }}
            }}
        }}
    }}
'''
    return s[:m.start()] + sec + s[m.end():]
rw(Q + "/settings/BarConfig.qml", settings)
