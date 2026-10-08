import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets

// Right-click menu of the mail button (mirrors dankmail's own tray menu): open, compose, sync, do-not-disturb, restart, stop.
// A click-away layer replaces HyprlandFocusGrab: releasing the grab made Hyprland refocus the last window, which revealed the hidden
// AI / Git / Teams special-workspace panels whenever an item was clicked.
Scope {
    id: root
    required property var store
    required property Item hoverTarget
    signal menuClosed()

    function open() {}                       // shown as soon as it is loaded
    function close() { menuClosed(); }

    PanelWindow {
        color: "transparent"
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:popup-dismiss"
        WlrLayershell.layer: WlrLayer.Top
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.close() }
    }

    PanelWindow {
        color: "transparent"
        anchors { left: true; top: true }
        implicitWidth: 240 + Appearance.sizes.elevationMargin * 2
        implicitHeight: col.implicitHeight + 16 + Appearance.sizes.elevationMargin * 2
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        margins {
            left: Math.max(4, root.hoverTarget.QsWindow?.mapFromItem(root.hoverTarget, 0, 0).x ?? 4)
            top: Appearance.sizes.barHeight
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        StyledRectangularShadow { target: bg }
        Rectangle {
            id: bg
            anchors { fill: parent; margins: Appearance.sizes.elevationMargin }
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.small
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 8 }
            spacing: 2

            component Item_: RippleButton {
                property string label
                property string sym
                property bool danger: false
                Layout.fillWidth: true
                implicitHeight: 34
                buttonRadius: Appearance.rounding.small
                contentItem: RowLayout {
                    spacing: 10
                    MaterialSymbol { text: parent.parent.sym; iconSize: 18; color: parent.parent.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer1 }
                    StyledText {
                        Layout.fillWidth: true
                        text: parent.parent.label
                        color: parent.parent.danger ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                    }
                }
            }
            component Sep: Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border; opacity: 0.6 }

            Item_ { sym: "mail"; label: "Open Dank Mail"; onClicked: { root.store.toggleApp(); root.close(); } }
            Item_ { sym: "edit_square"; label: "Compose"; onClicked: { Quickshell.execDetached(["bash", "-c", "$HOME/.config/hypr/custom/dankmail-compose.sh"]); root.close(); } }
            Item_ { sym: "sync"; label: root.store.syncing ? "Syncing…" : "Sync now"; onClicked: { root.store.syncNow(); root.close(); } }
            Item_ {
                sym: root.store.dnd ? "notifications_off" : "notifications"
                label: root.store.dnd ? "Do not disturb: on" : "Do not disturb: off"
                onClicked: { root.store.call(root.store.dnd ? "dnd.off" : "dnd.on", {}); root.close(); }
            }
            Sep {}
            Item_ { sym: "restart_alt"; label: "Restart dankmail"; onClicked: { Quickshell.execDetached(["dmail", "restart"]); root.close(); } }
            Item_ { sym: "power_settings_new"; label: "Stop dankmail completely"; danger: true
                    onClicked: { root.close(); root.store.stopDaemon(); } }
        }
        }
    }
}
