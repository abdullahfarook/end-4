import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// Bar button for the file-search widget (Everything-style, fzf backend); click opens FileSearchPopup.
RippleButton {
    id: root
    property real buttonPadding: 5
    implicitWidth: icon.implicitWidth + buttonPadding * 2   // same sizing as the Docker/Mail buttons
    implicitHeight: icon.implicitHeight + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    property bool open: false
    onClicked: open = !open

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        text: "manage_search"
        iconSize: 20
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
