import QtQuick
import QtQuick.Layouts

// Left-bar button slot: collapses to zero width (icon slides in/out inside the bar, nothing overlays the windows).
// Shown while `open` (pointer on the icon row), or always while `pinned` (e.g. unread mail/Teams count > 0).
Item {
    id: root
    default property alias content: holder.data
    property bool open: false
    property bool pinned: false
    readonly property bool shown: open || pinned

    Layout.alignment: Qt.AlignVCenter
    clip: true
    implicitHeight: 30
    implicitWidth: shown ? holder.childrenRect.width + 2 : 0
    opacity: shown ? 1 : 0
    visible: implicitWidth > 0.5 || opacity > 0.01

    Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 180 } }

    Item {
        id: holder
        x: 2
        width: childrenRect.width
        height: parent.height
    }
}
