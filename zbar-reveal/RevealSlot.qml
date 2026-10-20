import QtQuick
import QtQuick.Layouts

// Bar reveal slot: one 0..1 progress value drives width and opacity together (a single NumberAnimation, so the neighbours
// glide instead of stepping). Shown while `open` (pointer on that bar area) or always while `pinned` (new-mail badge, unread Teams).
// The default child is its content; `gap` is the trailing space kept while shown.
Item {
    id: root
    default property alias content: holder.data
    property bool open: false
    property bool pinned: false
    property real gap: 2
    readonly property bool shown: open || pinned
    property real p: shown ? 1 : 0

    Layout.alignment: Qt.AlignVCenter
    clip: p < 1
    implicitHeight: holder.childrenRect.height
    implicitWidth: Math.round((holder.childrenRect.width + gap) * p)   // whole pixels: no sub-pixel jitter of the neighbouring title
    opacity: p
    visible: implicitWidth > 0

    // opens with a decelerating ease, closes with a symmetric ease so the end of the close has no long sub-pixel tail
    Behavior on p { NumberAnimation { duration: root.shown ? 280 : 240; easing.type: root.shown ? Easing.OutCubic : Easing.InOutCubic } }

    Item {
        id: holder
        width: childrenRect.width
        height: parent.height
    }
}
