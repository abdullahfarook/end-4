import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets

// Right-click menu entries of the mail button (mirrors dankmail's own tray menu): open, compose, sync, do-not-disturb, restart, stop.
// WidgetBase places the menu under the button and closes it on an outside click (MailButton.qml: menuContent).
ColumnLayout {
    id: root
    required property var store
    signal closeRequested()
    width: 228
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

    Item_ { sym: "mail"; label: "Open Dank Mail"; onClicked: { root.store.toggleApp(); root.closeRequested(); } }
    Item_ { sym: "edit_square"; label: "Compose"; onClicked: { Quickshell.execDetached(["bash", "-c", "$HOME/.config/hypr/custom/dankmail-compose.sh"]); root.closeRequested(); } }
    Item_ { sym: "sync"; label: root.store.syncing ? "Syncing…" : "Sync now"; onClicked: { root.store.syncNow(); root.closeRequested(); } }
    Item_ {
        sym: root.store.dnd ? "notifications_off" : "notifications"
        label: root.store.dnd ? "Do not disturb: on" : "Do not disturb: off"
        onClicked: { root.store.call(root.store.dnd ? "dnd.off" : "dnd.on", {}); root.closeRequested(); }
    }
    Sep {}
    Item_ { sym: "restart_alt"; label: "Restart dankmail"; onClicked: { Quickshell.execDetached(["dmail", "restart"]); root.closeRequested(); } }
    Item_ { sym: "power_settings_new"; label: "Stop dankmail completely"; danger: true
            onClicked: { root.closeRequested(); root.store.stopDaemon(); } }
}
