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
    property bool open: false
    property Component panelContent: null
    property int panelWidth: 440
    property int panelKeyboardFocus: WlrKeyboardFocus.OnDemand
    property var ignoredLayers: []     // extra layer namespaces whose opening must not close the panel
    readonly property var panelScreen: root.QsWindow.window?.screen ?? null

    function close() { open = false }

    property real buttonPadding: 5
    implicitWidth: 30    // fixed size so every bar icon button is identical
    implicitHeight: 30
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    onClicked: open = !open

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.iconName
        iconSize: 21
        color: Appearance.colors.colOnLayer0
    }

    Loader {
        active: root.open && root.panelContent !== null
        sourceComponent: Scope {
            id: panel
            readonly property real openedAt: Date.now()
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
                function onRawEvent(event) {
                    if (Date.now() - panel.openedAt < 600) return;   // our own layers opening
                    if (event.name === "activespecial") { const q = event.data.split(","); if (q[0] !== "" && q[1] === panel.popupMon) root.close(); return; }
                    if (event.name === "workspacev2") { wsCheck.restart(); return; }   // decided once Hyprland.monitors has updated
                    if (event.name === "openlayer" && event.data !== "quickshell:popup-dismiss" && !root.ignoredLayers.includes(event.data)
                        && Hyprland.focusedMonitor?.name === panel.popupMon) root.close();
                }
            }

            // Click-away layer below the bar: a click anywhere outside the card closes the panel
            PanelWindow {
                screen: panel.screen
                mask: Region { item: belowBar }
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
                screen: panel.screen
                color: "transparent"
                anchors { top: true; left: true; bottom: true }
                implicitWidth: root.panelWidth + Appearance.sizes.hyprlandGapsOut + Appearance.sizes.elevationMargin
                mask: Region { item: card }
                exclusionMode: ExclusionMode.Normal
                exclusiveZone: 0
                WlrLayershell.namespace: "quickshell:sidebarLeft"  // same Hyprland layer rule (slide left) as the left sidebar: native slide in/out
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: root.panelKeyboardFocus
                onVisibleChanged: if (visible) content.item?.forceActiveFocus()

                StyledRectangularShadow { target: card }
                Rectangle {
                    id: card
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
