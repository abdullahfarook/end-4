import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets

// Bar button that toggles the dankmail triage window; shows the unread count from `dmail status --json`.
RippleButton {
    id: root
    property real buttonPadding: 5
    property int unread: 0
    implicitWidth: icon.implicitWidth + buttonPadding * 2
    implicitHeight: icon.implicitHeight + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    onPressed: Quickshell.execDetached(["dmail", "toggle"])

    Process {
        id: statusProc
        command: ["dmail", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.unread = JSON.parse(text).unread || 0; } catch (e) {}
            }
        }
    }
    Timer {
        interval: 30000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: statusProc.running = true
    }

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        text: "mail"
        iconSize: 20
        color: Appearance.colors.colOnLayer0
    }
    Rectangle {
        visible: root.unread > 0
        anchors { top: parent.top; right: parent.right; topMargin: 1; rightMargin: 1 }
        implicitWidth: Math.max(14, badge.implicitWidth + 6); implicitHeight: 14; radius: 7
        color: Appearance.colors.colPrimary
        StyledText {
            id: badge
            anchors.centerIn: parent
            text: root.unread > 99 ? "99+" : root.unread
            font.pixelSize: 9
            color: Appearance.colors.colOnPrimary
        }
    }
}
