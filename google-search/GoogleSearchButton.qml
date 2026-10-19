import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// Bar button for the Google widget; click opens GoogleSearchPopup (search field + embedded QtWebEngine results).
RippleButton {
    id: root
    implicitWidth: 30    // fixed size so every bar icon button is identical
    implicitHeight: 30
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    property bool open: false
    // Last session (kept in memory only, lost when the shell restarts): restored when the popup opens again
    property string memQuery: ""
    property string memUrl: ""
    property var history: [] // recent searches / addresses, newest first (suggestions)
    onClicked: open = !open

    MaterialSymbol {
        anchors.centerIn: parent
        text: "travel_explore"
        iconSize: 20
        color: Appearance.colors.colOnLayer0
    }

    // Popup is created only while open and unloaded on close
    Loader {
        active: root.open
        sourceComponent: GoogleSearchPopup {
            target: root
            onVisibleChanged: if (!visible) root.open = false
        }
    }
}
