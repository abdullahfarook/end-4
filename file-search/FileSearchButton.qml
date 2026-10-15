import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// Bar button for the file-search widget (Everything-style, fzf backend); click opens FileSearchPopup.
RippleButton {
    id: root
    property real buttonPadding: 5
    implicitWidth: 30    // fixed size so every bar icon button is identical
    implicitHeight: 30
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    property bool open: false
    onClicked: open = !open

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        text: "manage_search"
        iconSize: 22
        color: Appearance.colors.colOnLayer0
    }

    // Popup is created only while open and unloaded on close
    Loader {
        active: root.open
        sourceComponent: FileSearchPopup {
            target: root
            onVisibleChanged: if (!visible) root.open = false
        }
    }
}
