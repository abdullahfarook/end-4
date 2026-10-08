pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Bar button for the Teams panel (see teams-panel.sh). Left click toggles the panel; right click shows the same menu as
// Teams' tray icon (Open, Join Meeting, Settings...). The badge is the unread count Teams puts in its window title: "(3) Chat | ...".
RippleButton {
    id: root
    property real buttonPadding: 5
    implicitWidth: icon.implicitWidth + buttonPadding * 2
    implicitHeight: icon.implicitHeight + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    readonly property var trayItem: SystemTray.items.values.find(i => `${i.id} ${i.title}`.toLowerCase().includes("teams")) ?? null
    readonly property int unread: {
        let n = 0;
        for (const w of HyprlandData.windowList) {
            if (w.class !== "teams-for-linux") continue;
            const m = (w.title || "").match(/^\((\d+)\)/);
            if (m) n = Math.max(n, parseInt(m[1]));
        }
        return n;
    }

    onClicked: Quickshell.execDetached(["bash", "-c", "$HOME/.config/hypr/custom/teams-panel.sh"])
    altAction: () => {
        if (!root.trayItem || !root.trayItem.hasMenu) return;
        if (menu.active && menu.item && typeof menu.item.close === "function") menu.item.close();
        else menu.active = true;
    }

    // Like the tray row: while the menu is open a focus grab covers the bar and the menu, and a click anywhere else closes it.
    property var menuWindow: null
    HyprlandFocusGrab {
        active: root.menuWindow !== null
        windows: [root.QsWindow.window, root.menuWindow]
        onCleared: { if (root.menuWindow && typeof root.menuWindow.close === "function") root.menuWindow.close(); }
    }

    Loader {
        id: menu
        active: false
        sourceComponent: SysTrayMenu {
            Component.onCompleted: this.open()
            trayItemMenuHandle: root.trayItem.menu
            trayItemId: root.trayItem.id
            anchor {
                window: root.QsWindow.window
                item: root
                gravity: Config.options.bar.vertical ? (Config.options.bar.bottom ? Edges.Left : Edges.Right) : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
                edges: Config.options.bar.vertical ? (Config.options.bar.bottom ? Edges.Left : Edges.Right) : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
            }
            onMenuOpened: (w) => root.menuWindow = w
            onMenuClosed: { root.menuWindow = null; menu.active = false; }
        }
    }

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        text: "forum"
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
