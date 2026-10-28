import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets

// Shared base for bar widgets: fixed 30×30 icon button + left side panel shown while `open`.
// The panel (and everything in panelContent) is only instantiated while open and unloaded on close.
// Shared behavior: click outside closes, Esc closes, opens on the screen of the bar that was clicked,
// closes when something else opens on its own monitor, but never because of activity on another monitor.
// Widget-specific content (lists, right-click menus, state) goes in panelContent, in the widget's own file.
RippleButton {
    id: root
    property string iconName: ""
    property int iconSize: 21
    property real iconOpacity: 1
    property bool open: false
    property Component panelContent: null
    property int panelWidth: 440
    property int panelKeyboardFocus: WlrKeyboardFocus.OnDemand
    property var ignoredLayers: []     // extra layer namespaces whose opening must not close the panel
    // false: the content draws its own card(s) (e.g. a list + a detail pane) and lists its clickable items in
    // `panelMaskItems`; it may also set `panelClickThrough` (a rect, screen coordinates: clicks there reach the windows
    // below, e.g. a browser window placed next to the card), `panelHidden` (hide the panel window for a while) and
    // `panelCloseHold` (after closing, keep the panel window up while true, max 250 ms, to get ready for the slide-out)
    property bool panelCard: true
    readonly property var panelScreen: root.QsWindow.window?.screen ?? null

    function close() { open = false }

    // Right-click menu: the widget gives only its entries (menuContent); WidgetBase places the menu under the button
    // (above it for a bottom bar), closes the panel when it opens, and closes on an outside click or closeMenu().
    property Component menuContent: null
    readonly property bool menuOpen: menu.visible   // keeps the bar slot revealed while the menu is open
    function closeMenu() { menu.visible = false }
    // with the panel open, the menu is shown once the panel is gone (its teardown would dismiss the menu's focus grab)
    altAction: menuContent ? () => { if (open) { open = false; menuAfterPanel.restart() } else menu.visible = !menu.visible } : undefined
    Timer { id: menuAfterPanel; interval: 250; onTriggered: menu.visible = true }
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
            implicitWidth: Math.max(180, (menuEntries.item?.implicitWidth ?? 0) + 12)
            implicitHeight: (menuEntries.item?.implicitHeight ?? 0) + 12
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            Loader {
                id: menuEntries
                anchors { fill: parent; margins: 6 }
                active: menu.visible
                sourceComponent: root.menuContent
            }
        }
    }

    property real buttonPadding: 5
    implicitWidth: 30    // fixed size so every bar icon button is identical
    implicitHeight: 30
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    property bool clickOpens: true   // false: the widget handles left click itself (e.g. opens an app instead)
    onClicked: if (clickOpens) open = !open

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.iconName
        iconSize: root.iconSize
        color: Appearance.colors.colOnLayer0
        opacity: root.iconOpacity
    }

    // keep the panel alive briefly after closing: unmapping (not destroying) the layer lets Hyprland play the slide-out.
    // A flag, not unloadDelay.running: restarting a running timer flips `running` and would recreate the panel.
    property bool panelLoaded: false
    onOpenChanged: if (open) panelLoaded = true; else unloadDelay.restart()
    Timer { id: unloadDelay; interval: 400; onTriggered: if (!root.open) root.panelLoaded = false }
    Loader {
        active: (root.open || root.panelLoaded) && root.panelContent !== null
        sourceComponent: Scope {
            id: panel
            property real openedAt: Date.now()
            // reopened during the close animation: this instance is reused, so restart the open-time state
            Connections { target: root; function onOpenChanged() { if (root.open) { panel.openedAt = Date.now(); panel.wsAtOpen = panel.monitor?.activeWorkspace?.id ?? 0; panel.holdExpired = false; holdLimit.stop() } else holdLimit.restart() } }
            // the content may keep the panel window up for a moment after closing (panelCloseHold), never longer than holdLimit
            // (Google: swaps its browser window for a still in the panel, so the card and the browser slide out as one).
            // `held` must not depend on `open`: the window's visibility would read it stale on close and unmap/remap the panel
            property bool holdExpired: false
            readonly property bool held: (content.item?.panelCloseHold ?? false) && !holdExpired
            Timer { id: holdLimit; interval: 250; onTriggered: panel.holdExpired = true }
            onHeldChanged: if (!held && !root.open) unloadDelay.restart()   // the slide-out starts now: keep the content until it is done
            // monitor the panel was opened on (frozen at open)
            readonly property string popupMon: root.panelScreen?.name ?? Hyprland.focusedMonitor?.name ?? ""
            readonly property var screen: root.panelScreen

            // Clicks on the bar pass through the click-away layer (it covers everything below the bar), so one click on another bar
            // button both reaches that button and closes this panel: close when something else opens (a popup or the sidebar
            // layer, the AI panel's special workspace, another workspace) on this panel's monitor.
            // workspace shown on the panel's own monitor, recorded at open: a workspace change closes the panel only if this
            // monitor now shows another one, so activity on other monitors (in any event order) never closes it
            readonly property var monitor: Hyprland.monitors.values.find(m => m.name === panel.popupMon) ?? null
            property int wsAtOpen: 0
            Component.onCompleted: wsAtOpen = monitor?.activeWorkspace?.id ?? 0   // frozen: no binding
            Timer {
                id: wsCheck
                interval: 200
                onTriggered: {
                    const cur = panel.monitor?.activeWorkspace?.id ?? panel.wsAtOpen;
                    // a special workspace (id < 0) still reported at open is stale: re-record; specials close via activespecial
                    if (panel.wsAtOpen <= 0 || cur <= 0) panel.wsAtOpen = cur;
                    else if (cur !== panel.wsAtOpen) root.close();
                }
            }
            Connections {
                target: Hyprland
                enabled: root.open
                function onRawEvent(event) {
                    if (Date.now() - panel.openedAt < 600) return;   // our own layers opening
                    if (event.name === "activespecial") { const q = event.data.split(","); if (q[0] !== "" && q[1] === panel.popupMon) root.close(); return; }
                    if (event.name === "workspacev2") { wsCheck.restart(); return; }   // decided once Hyprland.monitors has updated
                    // the window close-button overlay (closebutton config) and bar tooltips (StyledPopup) are not panels: never a reason to close
                    if (event.name === "openlayer" && event.data !== "quickshell:popup-dismiss" && event.data !== "quickshell:closebutton"
                        && event.data !== "quickshell:popup"
                        && !root.ignoredLayers.includes(event.data)
                        && Hyprland.focusedMonitor?.name === panel.popupMon) root.close();
                }
            }

            // Click-away layer below the bar: a click anywhere outside the panel closes it (except in the content's click-through rect)
            readonly property rect hole: content.item?.panelClickThrough ?? Qt.rect(0, 0, 0, 0)
            readonly property bool holed: hole.width > 0 && hole.height > 0
            PanelWindow {
                id: away
                screen: panel.screen
                visible: root.open
                // Item-based bands around the hole (a Subtract region is unreliable): above, left of, right of and below it
                mask: Region {
                    item: panel.holed ? aboveHole : belowBar
                    Region { item: leftOfHole }
                    Region { item: rightOfHole }
                    Region { item: belowHole }
                }
                readonly property real barH: Config.options.bar.bottom ? 0 : Appearance.sizes.barHeight
                Item { id: aboveHole; x: 0; y: away.barH; width: away.width; height: Math.max(0, panel.hole.y - away.barH) }
                Item { id: leftOfHole; x: 0; y: panel.hole.y; width: panel.holed ? panel.hole.x : 0; height: panel.hole.height }
                Item { id: rightOfHole; x: panel.hole.x + panel.hole.width; y: panel.hole.y; width: panel.holed ? away.width - x : 0; height: panel.hole.height }
                Item { id: belowHole; x: 0; y: panel.hole.y + panel.hole.height; width: panel.holed ? away.width : 0; height: Math.max(0, away.height - y) }
                color: "transparent"
                anchors { left: true; right: true; top: true; bottom: true }
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0
                WlrLayershell.namespace: "quickshell:popup-dismiss"
                WlrLayershell.layer: WlrLayer.Top
                Item { id: belowBar; x: 0; y: Config.options.bar.bottom ? 0 : Appearance.sizes.barHeight; width: parent.width; height: parent.height - Appearance.sizes.barHeight }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.close() }
            }

            // Side panel: same geometry as the left sidebar, top/left/bottom anchored, hyprland outer gap around the card
            PanelWindow {
                id: win
                screen: panel.screen
                visible: (root.open || panel.held) && !(content.item?.panelHidden ?? false)
                color: "transparent"
                anchors { top: true; left: true; bottom: true }
                implicitWidth: root.panelWidth + Appearance.sizes.hyprlandGapsOut + Appearance.sizes.elevationMargin
                mask: Region { item: root.panelCard ? card : null; regions: maskRegions.instances }
                Variants {   // custom layout: one input region per item the content lists
                    id: maskRegions
                    model: root.panelCard ? [] : (content.item?.panelMaskItems ?? [])
                    Region { required property Item modelData; item: modelData }
                }
                exclusionMode: ExclusionMode.Normal
                exclusiveZone: 0
                WlrLayershell.namespace: "quickshell:sidebarLeft"  // same Hyprland layer rule (slide left) as the left sidebar: native slide in/out
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: root.panelKeyboardFocus
                onVisibleChanged: if (visible) content.item?.forceActiveFocus()

                StyledRectangularShadow { target: card; visible: root.panelCard }
                Rectangle {
                    id: card
                    visible: root.panelCard
                    anchors { top: parent.top; left: parent.left; bottom: parent.bottom }
                    anchors.topMargin: Appearance.sizes.hyprlandGapsOut
                    anchors.leftMargin: Appearance.sizes.hyprlandGapsOut
                    anchors.bottomMargin: Appearance.sizes.hyprlandGapsOut
                    width: root.panelWidth
                    color: Appearance.m3colors.m3surfaceContainer
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    clip: true
                    Loader {
                        id: content
                        parent: root.panelCard ? card : win.contentItem   // custom layout: the whole window, content draws its own cards
                        anchors.fill: parent
                        focus: true
                        sourceComponent: root.panelContent
                        onLoaded: Qt.callLater(() => content.item?.forceActiveFocus())   // the content's `focus: true` item gets the keys
                        Keys.onEscapePressed: root.close()
                    }
                }
            }
        }
    }
}
