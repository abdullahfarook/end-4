import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.modules.common
import qs.modules.common.widgets

// Right-click menu of the mail button (mirrors dankmail's own tray menu): open, compose, sync, do-not-disturb, restart, stop.
PopupWindow {
    id: root
    required property var store
    signal menuClosed()

    color: "transparent"
    implicitWidth: 240 + Appearance.sizes.elevationMargin * 2
    implicitHeight: col.implicitHeight + 16 + Appearance.sizes.elevationMargin * 2

    function open() { visible = true; }
    function close() { visible = false; menuClosed(); }

    HyprlandFocusGrab {
        // the bar window must be in the grab too, otherwise the grab is cleared the moment the menu opens (same as the tray menus)
        windows: [root.anchor.window, root]
        active: root.visible
        onCleared: root.close()
    }

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
            Item_ { sym: "edit_square"; label: "Compose"; onClicked: { root.store.call("ui.compose", {}); root.close(); } }
            Item_ { sym: "sync"; label: root.store.syncing ? "Syncing…" : "Sync now"; onClicked: { root.store.syncNow(); root.close(); } }
            Item_ {
                sym: root.store.dnd ? "notifications_off" : "notifications"
                label: root.store.dnd ? "Do not disturb: on" : "Do not disturb: off"
                onClicked: { root.store.call(root.store.dnd ? "dnd.off" : "dnd.on", {}); root.close(); }
            }
            Sep {}
            Item_ { sym: "restart_alt"; label: "Restart dankmail"; onClicked: { Quickshell.execDetached(["dmail", "restart"]); root.close(); } }
            Item_ { sym: "power_settings_new"; label: "Stop dankmail completely"; danger: true
                    onClicked: { Quickshell.execDetached(["dmail", "kill"]); root.close(); } }
        }
    }
}
