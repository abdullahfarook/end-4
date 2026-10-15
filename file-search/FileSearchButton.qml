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
    onClicked: popup.visible = !popup.visible

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        text: "manage_search"
        iconSize: 20
        color: Appearance.colors.colOnLayer0
    }

    FileSearchPopup { id: popup; target: root; visible: false }
}
