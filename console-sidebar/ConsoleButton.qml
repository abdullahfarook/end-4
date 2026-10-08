import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets

// Bar button that toggles the left console panel (see console-sidebar.sh).
RippleButton {
    id: root
    property real buttonPadding: 5
    implicitWidth: icon.implicitWidth + buttonPadding * 2
    implicitHeight: icon.implicitHeight + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    onPressed: Quickshell.execDetached(["bash", "-c", "$HOME/.config/hypr/custom/console-sidebar.sh"])
    altAction: () => { stopMenu.visible = !stopMenu.visible; }

    // Right-click menu: stop the console terminal
    PopupWindow {
        id: stopMenu
        color: "transparent"
        implicitWidth: 112 + 2 * Appearance.sizes.elevationMargin
        implicitHeight: 44 + 2 * Appearance.sizes.elevationMargin
        anchor {
            window: root.QsWindow.window
            item: root
            edges: Edges.Bottom
            gravity: Edges.Bottom
            rect.x: (root.width - stopMenu.implicitWidth) / 2
            rect.y: root.height
        }
        HyprlandFocusGrab {
            active: stopMenu.visible
            windows: [stopMenu]
            onCleared: stopMenu.visible = false
        }
        PanelWindow {  // full-screen click catcher: any click outside the menu closes it
            visible: stopMenu.visible
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell:stop-menu-dismiss"
            anchors { top: true; bottom: true; left: true; right: true }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: stopMenu.visible = false
            }
        }
        Connections {  // also close when focus moves elsewhere (clicking another window / workspace)
            target: Hyprland
            enabled: stopMenu.visible
            function onRawEvent(event) {
                if (["activewindowv2", "workspacev2", "focusedmonv2"].includes(event.name)) stopMenu.visible = false
            }
        }
        StyledRectangularShadow { target: menuBg }
        Rectangle {
            id: menuBg
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.windowRounding
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            RippleButton {
                anchors.fill: parent
                anchors.margins: 4
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                onClicked: {
                    stopMenu.visible = false;
                    Quickshell.execDetached(["bash", "-c", "$HOME/.config/hypr/custom/console-sidebar.sh stop"]);
                }
                contentItem: RowLayout {
                    spacing: 6
                    Item { Layout.fillWidth: true }
                    MaterialSymbol { text: "stop_circle"; iconSize: 18; color: Appearance.colors.colOnLayer0 }
                    StyledText { text: "Stop"; color: Appearance.colors.colOnLayer0 }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        text: "terminal"
        iconSize: 20
        color: Appearance.colors.colOnLayer0
    }
}
