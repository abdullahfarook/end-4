import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
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

    // Right-click menu: Stop / Start Docker, below the button
    altAction: () => { popup.visible = false; menu.visible = !menu.visible }
    PopupWindow {
        id: menu
        visible: false
        anchor.window: root.QsWindow.window
        anchor.onAnchoring: {
            const p = root.QsWindow.mapFromItem(root, 0, 0);
            anchor.rect = Qt.rect(p.x, p.y, root.width, root.height);
        }
        anchor.edges: Config.options.bar.bottom ? Edges.Top : Edges.Bottom
        anchor.gravity: anchor.edges === Edges.Top ? Edges.Top : Edges.Bottom
        anchor.adjustment: PopupAdjustment.All
        grabFocus: true
        color: "transparent"
        implicitWidth: menuCard.implicitWidth + 16
        implicitHeight: menuCard.implicitHeight + 16
        Rectangle {
            id: menuCard
            anchors.centerIn: parent
            implicitWidth: 180
            implicitHeight: entry.implicitHeight + 12
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            RippleButton {
                id: entry
                anchors { fill: parent; margins: 6 }
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: {
                    Quickshell.execDetached(["pkexec", "systemctl", root.available ? "stop" : "start", "docker.service", "docker.socket"]);
                    menu.visible = false;
                }
                contentItem: RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: root.available ? "power_settings_new" : "play_arrow"
                        iconSize: Appearance.font.pixelSize.larger
                        color: root.available ? "#ef5350" : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        text: root.available ? Translation.tr("Stop Docker") : Translation.tr("Start Docker")
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }

    DockerPopup { id: popup; target: root; visible: false }
}
