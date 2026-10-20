#!/usr/bin/env python3
# Right side, same Revealer animation as the left: the clock date and the util buttons reveal while the pointer is on the clock group.
# usage: patch-right.py BarContent.qml ClockWidget.qml (idempotent)
import sys

b, c = sys.argv[1], sys.argv[2]
s = open(b).read()
if "rtClose" not in s:
    old = "            implicitWidth: root.centerSideModuleWidth\n            implicitHeight: rightCenterGroupContent.implicitHeight\n"
    new = old + """            hoverEnabled: true
            property bool hot: false
            onContainsMouseChanged: { if (containsMouse) { rtClose.stop(); hot = true } else rtClose.restart() }
            Timer { id: rtClose; interval: 700; onTriggered: rightCenterGroup.hot = false }
"""
    assert old in s, "rightCenterGroup not found"
    s = s.replace(old, new, 1)
    old = "                    showDate: (Config.options.bar.verbose && root.useShortenedForm < 2)\n"
    assert old in s, "ClockWidget usage not found"
    s = s.replace(old, old + "                    expanded: rightCenterGroup.hot\n", 1)
    old = """                UtilButtons {
                    visible: (Config.options.bar.verbose && root.useShortenedForm === 0)
                    Layout.alignment: Qt.AlignVCenter
                }
"""
    new = """                UtilButtons {
                    visible: (Config.options.bar.verbose && root.useShortenedForm === 0)
                    expanded: rightCenterGroup.hot
                    Layout.alignment: Qt.AlignVCenter
                }
"""
    assert old in s, "UtilButtons block not found"
    s = s.replace(old, new, 1)
    open(b, "w").write(s)

t = open(c).read()
if "expanded" not in t:
    old = """        StyledText {
            visible: root.showDate
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            text: "•"
        }

        StyledText {
            visible: root.showDate
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            text: DateTime.longDate
        }
"""
    new = """        RevealSlot {
            open: root.showDate && root.expanded
            gap: 0
            Layout.alignment: Qt.AlignVCenter
            RowLayout {
                spacing: 4
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: "•"
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: DateTime.longDate
                }
            }
        }
"""
    assert old in t, "clock date block not found"
    t = t.replace(old, new, 1).replace("    property bool showDate: Config.options.bar.verbose\n", "    property bool showDate: Config.options.bar.verbose\n    property bool expanded: true\n", 1)
    open(c, "w").write(t)
