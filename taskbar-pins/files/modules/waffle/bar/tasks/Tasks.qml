import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.waffle.looks

MouseArea {
    id: root

    Layout.fillHeight: true
    implicitHeight: appRow.implicitHeight
    implicitWidth: appRow.implicitWidth
    hoverEnabled: true

    function showPreviewPopup(appEntry, button) {
        previewPopup.show(appEntry, button);
    }

    Behavior on implicitWidth {
        animation: Looks.transition.move.createObject(this)
    }

    WListView {
        id: appRow
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        orientation: Qt.Horizontal
        spacing: 0
        implicitWidth: contentWidth
        clip: true
        interactive: false
        // TODO: Include only apps (and windows) in current workspace only | wait, does that even make sense in a Hyprland workflow?
        model: ScriptModel {
            objectProp: "appId"
            values: TaskbarApps.apps.filter(app => app.appId !== "SEPARATOR")
        }
        footer: Item {
            width: TaskbarApps.editMode ? doneText.implicitWidth + 20 : 0
            height: appRow.height
            visible: TaskbarApps.editMode
            WText {
                id: doneText
                anchors.centerIn: parent
                text: Translation.tr("Done")
                color: Looks.colors.accent
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: TaskbarApps.editMode = false
                }
            }
        }
        delegate: TaskAppButton {
            required property var modelData
            id: taskBtn
            appEntry: modelData
            property bool editable: TaskbarApps.editMode && appEntry.pinned
            property real dragDx: 0
            transform: Translate { x: taskBtn.dragDx }
            z: dragArea.drag.active || dragArea.pressed ? 10 : 0
            opacity: TaskbarApps.editMode && !appEntry.pinned ? 0.4 : 1

            MouseArea {
                id: dragArea
                anchors.fill: parent
                enabled: taskBtn.editable
                visible: taskBtn.editable
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real startX
                onPressed: mouse => startX = mapToItem(appRow, mouse.x, 0).x
                onPositionChanged: mouse => {
                    if (pressed) taskBtn.dragDx = mapToItem(appRow, mouse.x, 0).x - startX;
                }
                onReleased: {
                    const from = TaskbarApps.pinIndex(taskBtn.appEntry.appId);
                    const step = Math.round(taskBtn.dragDx / taskBtn.width);
                    taskBtn.dragDx = 0;
                    TaskbarApps.movePin(from, from + step);
                }
            }

            Rectangle {
                visible: taskBtn.editable
                z: 20
                width: 16; height: 16; radius: 8
                color: Looks.colors.bg1Base
                border.width: 1
                border.color: Looks.colors.accent
                anchors { top: parent.top; right: parent.right; topMargin: 2; rightMargin: 2 }
                FluentIcon {
                    anchors.centerIn: parent
                    icon: "dismiss"
                    implicitSize: 10
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: TaskbarApps.togglePin(taskBtn.appEntry.appId)
                }
            }

            onHoverPreviewRequested: {
                root.showPreviewPopup(appEntry, this);
            }
            onHoverPreviewDismissed: {
                previewPopup.close();
            }
        }
    }

    // (Done button lives in the list footer)
    // Previews popup
    TaskPreview {
        id: previewPopup
        tasksHovered: root.containsMouse
        anchor.window: root.QsWindow.window
    }
}
