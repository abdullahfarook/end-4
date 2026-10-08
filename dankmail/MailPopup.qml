import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets

// Inbox popup for dankmail (port of the DankMaterialShell plugin's popout): tabs, rows with hover actions, sync/open buttons.
LazyLoader {
    id: root
    required property var store          // MailButton: threads/unread/view/syncing + op()/call()/setView()/syncNow()
    property bool open: false
    property real popupHeight: 0         // 0 = auto; set by dragging a bottom edge (list or detail panel)
    property real detailWidth: 480       // resizable via the detail panel's right-edge handle
    property Item hoverTarget
    signal closeRequested()

    active: open

    component: PanelWindow {
        id: popupWindow
        color: "transparent"
        anchors.left: true
        anchors.top: true
        readonly property bool detailOpen: root.store.selectedId >= 0
        readonly property int contentHeight: root.popupHeight > 0 ? root.popupHeight : Math.max(Math.min(640, panel.implicitHeight), detailOpen ? 560 : 0)
        implicitWidth: 440 + (detailOpen ? 8 + root.detailWidth : 0) + Appearance.sizes.elevationMargin * 2
        implicitHeight: contentHeight + Appearance.sizes.elevationMargin * 2
        mask: Region { item: wrap }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        margins {
            left: Math.max(4, root.QsWindow?.mapFromItem(root.hoverTarget, (root.hoverTarget.width - 440) / 2, 0).x ?? 4)
            top: Appearance.sizes.barHeight
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        HyprlandFocusGrab {
            windows: [popupWindow]
            active: true
            onCleared: root.closeRequested()
        }

        Item {
            id: wrap  // input region: list panel plus the detail panel when open
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: Appearance.sizes.elevationMargin }
            width: 440 + (popupWindow.detailOpen ? 8 + root.detailWidth : 0)
        }

        StyledRectangularShadow { target: panel }
        StyledRectangularShadow { target: detail; visible: detail.visible }

        MailDetail {
            id: detail
            visible: popupWindow.detailOpen
            store: root.store
            anchors { left: panel.right; top: parent.top; bottom: parent.bottom; right: parent.right; leftMargin: 8; topMargin: Appearance.sizes.elevationMargin; bottomMargin: Appearance.sizes.elevationMargin; rightMargin: Appearance.sizes.elevationMargin }
            onCloseRequested: root.store.closeThread()

            MouseArea {  // resize handle (right edge); incremental deltas stay stable while the window grows under the cursor
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 8
                cursorShape: Qt.SizeHorCursor
                property real pressX
                onPressed: mouse => pressX = mouse.x
                onPositionChanged: mouse => {
                    if (pressed) root.detailWidth = Math.max(320, Math.min(900, root.detailWidth + mouse.x - pressX));
                }
            }

            MouseArea {  // resize handle (bottom edge)
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 8
                cursorShape: Qt.SizeVerCursor
                property real pressY
                onPressed: mouse => pressY = mouse.y
                onPositionChanged: mouse => {
                    if (pressed) root.popupHeight = Math.max(240, Math.min(1100, popupWindow.contentHeight + mouse.y - pressY));
                }
            }
        }

        Rectangle {
            id: panel
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: Appearance.sizes.elevationMargin; topMargin: Appearance.sizes.elevationMargin; bottomMargin: Appearance.sizes.elevationMargin }
            width: 440
            implicitHeight: header.implicitHeight + (listArea.implicitHeight) + 20
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true

            MouseArea {  // resize handle (bottom edge)
                z: 10
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 8
                cursorShape: Qt.SizeVerCursor
                property real pressY
                onPressed: mouse => pressY = mouse.y
                onPositionChanged: mouse => {
                    if (pressed) root.popupHeight = Math.max(240, Math.min(1100, popupWindow.contentHeight + mouse.y - pressY));
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Header: title, tabs, actions
                RowLayout {
                    id: header
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 8
                    MaterialSymbol { text: "mail"; iconSize: 22; color: Appearance.colors.colOnLayer1 }
                    StyledText {
                        text: "Dank Mail"
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer1
                    }
                    Item { Layout.fillWidth: true }
                    Repeater {
                        model: [{ "k": "inbox", "t": "All" }, { "k": "unread", "t": "Unread" }, { "k": "starred", "t": "Starred" }]
                        delegate: RippleButton {
                            required property var modelData
                            implicitHeight: 28
                            implicitWidth: tabText.implicitWidth + 24
                            buttonRadius: 14
                            toggled: root.store.view === modelData.k
                            onClicked: root.store.setView(modelData.k)
                            StyledText {
                                id: tabText
                                anchors.centerIn: parent
                                text: modelData.t
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                    RippleButton {
                        implicitWidth: 28; implicitHeight: 28; buttonRadius: 14
                        onClicked: root.store.syncNow()
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "sync"; iconSize: 18; color: Appearance.colors.colOnLayer1
                            RotationAnimation on rotation { running: root.store.syncing; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                        StyledToolTip { text: "Sync now" }
                    }
                    RippleButton {
                        implicitWidth: 28; implicitHeight: 28; buttonRadius: 14
                        onClicked: { root.store.toggleApp(); root.closeRequested(); }
                        MaterialSymbol { anchors.centerIn: parent; text: "open_in_full"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                        StyledToolTip { text: "Open Dank Mail" }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }

                Item {
                    id: listArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: root.store.threads.length > 0 ? Math.min(520, root.store.threads.length * 78) : 120

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.store.threads.length === 0
                        text: root.store.requestError !== "" ? root.store.requestError
                            : root.store.view === "starred" ? "No starred mail."
                            : root.store.view === "unread" ? "No unread mail." : "No mail in the inbox."
                        color: Appearance.colors.colSubtext
                    }

                    ListView {
                        id: list
                        anchors.fill: parent
                        visible: root.store.threads.length > 0
                        model: root.store.threads
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: MailRow { width: list.width; store: root.store }
                        function checkEnd() { if (contentHeight > 0 && contentHeight - contentY - height < 160) root.store.loadMore(); }
                        onContentYChanged: checkEnd()
                        onContentHeightChanged: loadMoreTimer.restart()
                        Timer { id: loadMoreTimer; interval: 150; onTriggered: list.checkEnd() }
                        footer: Item {
                            width: list.width
                            height: root.store.loadingMore ? 44 : 0
                            visible: root.store.loadingMore
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol {
                                    text: "progress_activity"; iconSize: 20; color: Appearance.colors.colSubtext
                                    RotationAnimation on rotation { running: root.store.loadingMore; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                                }
                                StyledText { text: "Loading older mail…"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }
            }
        }
    }
}
