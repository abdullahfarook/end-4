import QtQuick
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

    MaterialSymbol {
        anchors.centerIn: parent
        text: "search"
        iconSize: 16
        color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
    }
}
