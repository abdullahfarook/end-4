import QtQuick
import QtQuick.Effects
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets

// Bar button right of the workspaces: a circle with a search icon; opens the same overview/launcher as the SUPER key.
RippleButton {
    id: root
    implicitWidth: 24
    implicitHeight: 24
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colRipple: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.overviewOpen
    colBackgroundToggled: Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.colors.colPrimaryHover

    onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen

    Image {
        anchors.centerIn: parent
        width: 16; height: 16
        sourceSize: Qt.size(64, 64)
        source: Quickshell.shellPath("assets/icons/bar-search/search.svg")
        fillMode: Image.PreserveAspectFit
        layer.enabled: true     // tint the white glyph with the icon colour
        layer.effect: MultiEffect {
            colorization: 1
            colorizationColor: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
        }
    }
}
