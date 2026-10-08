import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Bar button right of the workspaces: a search icon, no background unless the overview is open; opens the same overview/launcher as the SUPER key.
RippleButton {
    id: root
    implicitWidth: 24
    implicitHeight: 24
    buttonRadius: Appearance.rounding.full
    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1, 1)
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    property bool openedByClick: false  // background only when opened via this button, not via shortcuts
    toggled: openedByClick && GlobalStates.overviewOpen
    colBackgroundToggled: Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.colors.colPrimaryHover

    onClicked: {
        openedByClick = !GlobalStates.overviewOpen
        GlobalStates.overviewOpen = !GlobalStates.overviewOpen
    }
    Connections {  // clicking another window / switching workspace drops the highlight too
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindowv2" || event.name === "workspacev2") root.openedByClick = false
        }
    }
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() { if (!GlobalStates.overviewOpen) root.openedByClick = false }
    }

    Image {
        anchors.centerIn: parent
        width: 16; height: 16
        sourceSize: Qt.size(64, 64)
        source: Quickshell.shellPath("assets/icons/bar-search/search.svg")
        fillMode: Image.PreserveAspectFit
        layer.enabled: true     // tint the white glyph with the icon colour
        layer.effect: MultiEffect {
            colorization: 1
            colorizationColor: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
        }
    }
}
