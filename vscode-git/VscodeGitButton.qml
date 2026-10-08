import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets

// Bar button that toggles the Git panel (see vscode-git.sh).
RippleButton {
    id: root
    property real buttonPadding: 5
    implicitWidth: icon.implicitWidth + buttonPadding * 2
    implicitHeight: icon.implicitHeight + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    onPressed: Quickshell.execDetached(["bash", "-c", "$HOME/.config/hypr/custom/vscode-git.sh"])
    altAction: () => { stopMenu.visible = !stopMenu.visible; }

    // Right-click menu: stop the git panel's VS Code instance
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
                    Quickshell.execDetached(["bash", "-c", "$HOME/.config/hypr/custom/vscode-git-stop.sh"]);
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
        text: "merge_type"
        iconSize: 20
        color: Appearance.colors.colOnLayer0
    }
}
