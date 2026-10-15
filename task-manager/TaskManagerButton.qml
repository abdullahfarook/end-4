import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// Bar button for the task manager. The popup (and its polling process) is only instantiated while open;
// closing it (click outside / Esc / button) unloads it again, so nothing stays in memory.
RippleButton {
    id: root
    property real buttonPadding: 5
    property bool open: false
    implicitWidth: icon.implicitWidth + buttonPadding * 2   // same sizing as the Docker/Mail buttons
    implicitHeight: icon.implicitHeight + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    onClicked: open = !open

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        text: "memory"
        iconSize: 20
        color: Appearance.colors.colOnLayer0
    }

    Loader {
        active: root.open
        sourceComponent: TaskManagerPopup {
            target: root
            visible: true
            onVisibleChanged: if (!visible) root.open = false
        }
    }
}
