import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

// Bar button for the Docker widget: whale icon + running-container count; click opens DockerPopup (list, stats, logs).
RippleButton {
    id: root
    property real buttonPadding: 5
    property int running: 0
    property bool available: true
    implicitWidth: icon.implicitWidth + buttonPadding * 2   // same sizing as the Mail/Teams buttons
    implicitHeight: icon.implicitHeight + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    onClicked: popup.visible = !popup.visible

    Process {
        id: countProc
        command: ["docker", "ps", "-q"]
        stdout: StdioCollector {
            onStreamFinished: { root.available = true; root.running = text.trim() === "" ? 0 : text.trim().split("\n").length }
        }
        onExited: code => { if (code !== 0) { root.available = false; root.running = 0 } }
    }
    Timer { interval: 10000; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!countProc.running) countProc.running = true }

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        text: "deployed_code"
        iconSize: 20
        color: Appearance.colors.colOnLayer0
        opacity: root.available ? 1 : 0.4
    }
    Rectangle {  // running-container count, top-right corner like the mail/Teams badges (hidden at 0)
        visible: root.available && root.running > 0
        anchors { top: parent.top; right: parent.right; topMargin: 2; rightMargin: 0 }
        implicitWidth: Math.max(14, countText.implicitWidth + 8); implicitHeight: 14; radius: 7
        color: Appearance.colors.colPrimary
        StyledText {
            id: countText
            anchors.centerIn: parent
            text: root.running > 99 ? "99+" : root.running
            font.pixelSize: 9
            color: Appearance.colors.colOnPrimary
        }
    }

    DockerPopup { id: popup; target: root; visible: false }
}
