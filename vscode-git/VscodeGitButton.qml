import QtQuick
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

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        text: "merge_type"
        iconSize: 20
        color: Appearance.colors.colOnLayer0
    }
}
