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
    property Item hoverTarget
    signal closeRequested()

    active: open

    component: PanelWindow {
        id: popupWindow
        color: "transparent"
        anchors.left: true
        anchors.top: true
        implicitWidth: 440 + Appearance.sizes.elevationMargin * 2
        implicitHeight: Math.min(640, panel.implicitHeight) + Appearance.sizes.elevationMargin * 2
        mask: Region { item: panel }
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

        StyledRectangularShadow { target: panel }

        Rectangle {
            id: panel
            anchors { fill: parent; margins: Appearance.sizes.elevationMargin }
            implicitHeight: header.implicitHeight + (listArea.implicitHeight) + 20
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true

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
                        delegate: MailRow { width: list.width; store: root.store; onOpened: root.closeRequested() }
                    }
                }
            }
        }
    }
}
