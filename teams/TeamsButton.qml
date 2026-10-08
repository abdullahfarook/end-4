pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Bar button for the Teams panel (see teams-panel.sh). Left click toggles the panel; right click shows the same menu as
// Teams' tray icon (Open, Join Meeting, Settings...). The dot shows when Teams has unread messages (it puts the count in its window title: "(3) Chat | ...").
RippleButton {
    id: root
    property real buttonPadding: 5
    implicitWidth: icon.implicitWidth + buttonPadding * 2
    implicitHeight: icon.implicitHeight + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    readonly property var trayItem: SystemTray.items.values.find(i => `${i.id} ${i.title}`.toLowerCase().includes("teams")) ?? null
    // Teams counts as running while it has a window (it is always docked on special:teams) or a tray entry; otherwise the icon dims
    readonly property bool running: trayItem !== null || HyprlandData.windowList.some(w => w.class === "teams-for-linux")
    readonly property int unread: {
        let n = 0;
        for (const w of HyprlandData.windowList) {
            if (w.class !== "teams-for-linux") continue;
            const m = (w.title || "").match(/^\((\d+)\)/);
            if (m) n = Math.max(n, parseInt(m[1]));
        }
        return n;
    }

    // The toggle script can take seconds when Teams is hidden in the tray or starting: show a loader line under the icon meanwhile
    // and ignore clicks (a queued second toggle would just hide the panel again).
    readonly property bool busy: toggler.running
    Process { id: toggler; command: ["bash", "-c", "$HOME/.config/hypr/custom/teams-panel.sh"] }
    onClicked: { if (!toggler.running) toggler.running = true; }
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
        opacity: root.running ? 1 : 0.4
    }
    Rectangle {  // unread dot, same as the mail button
        visible: root.unread > 0
        anchors { top: parent.top; right: parent.right; topMargin: 4; rightMargin: 4 }
        implicitWidth: 8; implicitHeight: 8; radius: 4
        color: Appearance.colors.colPrimary
    }
    Item {  // indeterminate loader line below the icon
        id: loader
        visible: root.busy
        anchors { bottom: parent.bottom; bottomMargin: 2; horizontalCenter: parent.horizontalCenter }
        width: parent.width - 12; height: 2
        clip: true
        Rectangle { anchors.fill: parent; radius: 1; color: Appearance.colors.colOnLayer0; opacity: 0.2 }
        Rectangle {
            id: runner
            height: parent.height; width: parent.width * 0.4; radius: 1
            color: Appearance.colors.colPrimary
            SequentialAnimation on x {
                running: loader.visible; loops: Animation.Infinite
                NumberAnimation { from: -runner.width; to: loader.width; duration: 900; easing.type: Easing.InOutQuad }
            }
        }
    }
}
