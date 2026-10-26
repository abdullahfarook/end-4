pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Bar button for the Teams panel (see teams-panel.sh). Left click toggles the panel; right click shows the same menu as
// Teams' tray icon (Open, Join Meeting, Settings...). The badge shows the count of unread Teams messages (it puts the count in its window title: "(3) Chat | ...").
RippleButton {
    id: root
    property real buttonPadding: 5
    implicitWidth: 30    // fixed size so every bar icon button is identical
    implicitHeight: 30
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    // Newest matching entry: after Teams restarts, the shell can keep the dead process's entry, whose menu is gone
    readonly property var trayItem: SystemTray.items.values.filter(i => `${i.id} ${i.title}`.toLowerCase().includes("teams")).pop() ?? null
    // Teams counts as running while its process exists; otherwise the icon dims. Not the tray entry: after Teams crashes the
    // shell can keep the dead entry, which kept the icon bright while Teams was not running.
    property bool running: false
    Process { id: aliveProc; command: ["pgrep", "-x", "teams-for-linux"]; onExited: code => root.running = code === 0 }
    Timer { interval: 3000; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!aliveProc.running) aliveProc.running = true }
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
        if (!root.trayItem || !root.trayItem.hasMenu) { fallback.visible = !fallback.visible; if (fallback.visible) root.placeMenu(fallback); return; } // no tray entry: own menu
        if (menu.active && menu.item && typeof menu.item.close === "function") menu.item.close();
        else menu.active = true;
    }

    // The bar slot animates, so the anchor is computed from the button's position at the moment the menu opens
    function placeMenu(m) {
        const pt = root.mapToItem(null, 0, 0);
        m.anchor.rect.x = pt.x + root.width / 2; // gravity Bottom centers the popup on this point
        m.anchor.rect.y = pt.y + root.height;
        m.anchor.updateAnchor();
    }
    readonly property bool menuOpen: menuWindow !== null || fallback.visible // keeps the bar slot revealed while a menu is open

    // Fallback right-click menu, used while Teams has no tray entry (it is hidden or still starting)
    PopupWindow {
        id: fallback
        color: "transparent"
        implicitWidth: 150 + 2 * Appearance.sizes.elevationMargin
        implicitHeight: 84 + 2 * Appearance.sizes.elevationMargin
        anchor {
            window: root.QsWindow.window
            edges: Edges.Bottom
            gravity: Edges.Bottom
        }
        HyprlandFocusGrab {
            active: fallback.visible
            windows: [fallback]
            onCleared: fallback.visible = false
        }
        StyledRectangularShadow { target: fallbackBg }
        Rectangle {
            id: fallbackBg
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.windowRounding
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            Column {
                anchors.fill: parent
                anchors.margins: 4
                Repeater {
                    model: [
                        { label: "Open Teams", icon: "forum", cmd: "$HOME/.config/hypr/custom/teams-panel.sh" },
                        { label: "Quit Teams", icon: "power_settings_new", cmd: "pkill -f /opt/teams-for-linux/teams-for-linux" }
                    ]
                    RippleButton {
                        required property var modelData
                        width: parent.width
                        height: parent.height / 2
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        onClicked: {
                            fallback.visible = false;
                            Quickshell.execDetached(["bash", "-c", modelData.cmd]);
                        }
                        contentItem: RowLayout {
                            spacing: 6
                            MaterialSymbol { text: parent.parent.modelData.icon; iconSize: 18; color: Appearance.colors.colOnLayer0 }
                            StyledText { text: parent.parent.modelData.label; color: Appearance.colors.colOnLayer0 }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
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
        iconSize: 18
        color: Appearance.colors.colOnLayer0
        opacity: root.running ? 1 : 0.4
    }
    Rectangle {  // unread count (Teams' own count: clears once you read the messages), hidden at 0
        visible: root.unread > 0
        anchors { top: parent.top; right: parent.right; topMargin: 2; rightMargin: 0 }
        implicitWidth: Math.max(14, unreadText.implicitWidth + 8); implicitHeight: 14; radius: 7
        color: Appearance.colors.colPrimary
        StyledText {
            id: unreadText
            anchors.centerIn: parent
            text: root.unread > 99 ? "99+" : root.unread
            font.pixelSize: 9
            color: Appearance.colors.colOnPrimary
        }
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
