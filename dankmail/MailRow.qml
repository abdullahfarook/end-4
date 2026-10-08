import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets

// One inbox row: avatar, sender, time, subject, snippet; hover shows the action bar (archive, trash, read, star, snooze, webmail).
Item {
    id: row
    required property var modelData
    required property var store
    signal opened()
    readonly property bool selected: store.selectedId === modelData.id
    implicitHeight: 78

    readonly property string sender: {
        const raw = (modelData.participants && modelData.participants.length > 0) ? modelData.participants[0] : "";
        const m = raw.match(/^\s*"?([^"<]*?)"?\s*<[^>]+>\s*$/);
        return m && m[1].trim() !== "" ? m[1].trim() : raw;
    }
    readonly property string timeText: {
        const d = new Date(modelData.lastMessageAt), now = new Date();
        return d.toDateString() === now.toDateString() ? Qt.formatTime(d, "HH:mm") : Qt.formatDate(d, "d MMM");
    }
    readonly property string snippet: (modelData.snippet || "").replace(/[\s­͏​-‏⁠﻿]+/g, " ").trim()
    readonly property color avatarColor: Qt.hsla(((sender.charCodeAt(0) || 0) * 37 % 360) / 360, 0.45, 0.62, 1)

    Rectangle {  // unread accent
        visible: modelData.unread
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: 3; color: Appearance.colors.colPrimary
    }
    Rectangle {
        anchors.fill: parent
        color: row.selected ? Appearance.colors.colLayer1Active : hover.hovered ? Appearance.colors.colLayer1Hover : "transparent"
    }
    HoverHandler { id: hover }
    TapHandler { onTapped: { row.store.selectThread(modelData.id); row.opened(); } }

    RowLayout {
        anchors { fill: parent; leftMargin: 14; rightMargin: 12; topMargin: 8; bottomMargin: 8 }
        spacing: 12
        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 40; implicitHeight: 40; radius: 20
            color: row.avatarColor
            StyledText {
                anchors.centerIn: parent
                text: (row.sender.charAt(0) || "?").toUpperCase()
                font.pixelSize: Appearance.font.pixelSize.larger
                color: "#1b1b1f"
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: row.sender
                    elide: Text.ElideRight
                    font.weight: modelData.unread ? Font.Bold : Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
                MaterialSymbol { visible: modelData.hasAttachments; text: "attach_file"; iconSize: 14; color: Appearance.colors.colSubtext }
                StyledText {
                    visible: !hover.hovered
                    text: row.timeText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                MaterialSymbol {
                    visible: !hover.hovered
                    text: "star"; fill: modelData.starred ? 1 : 0; iconSize: 16
                    color: modelData.starred ? "#f5b942" : Appearance.colors.colSubtext
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: modelData.subject
                elide: Text.ElideRight
                font.weight: modelData.unread ? Font.Bold : Font.Normal
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: row.snippet
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    // Hover action bar
    Rectangle {
        visible: hover.hovered
        anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 6 }
        implicitWidth: actions.implicitWidth + 12; implicitHeight: 34; radius: 17
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1; border.color: Appearance.colors.colLayer0Border
        RowLayout {
            id: actions
            anchors.centerIn: parent
            spacing: 2
            component Act: RippleButton {
                property string sym
                property string tip
                property color iconColor: Appearance.colors.colOnLayer1
                implicitWidth: 28; implicitHeight: 28; buttonRadius: 14
                MaterialSymbol { anchors.centerIn: parent; text: parent.sym; iconSize: 18; color: parent.iconColor }
                StyledToolTip { text: parent.tip }
            }
            Act { sym: "archive"; tip: "Archive"; onClicked: row.store.op("ops.archive", modelData.id) }
            Act { sym: "delete"; tip: "Delete"; iconColor: Appearance.colors.colError; onClicked: row.store.op("ops.trash", modelData.id) }
            Act { sym: modelData.unread ? "drafts" : "mark_email_unread"; tip: modelData.unread ? "Mark as read" : "Mark as unread"
                  onClicked: row.store.op(modelData.unread ? "ops.markRead" : "ops.markUnread", modelData.id) }
            Act { sym: "star"; tip: modelData.starred ? "Unstar" : "Star"
                  onClicked: row.store.op(modelData.starred ? "ops.unstar" : "ops.star", modelData.id) }
            Act { sym: "snooze"; tip: "Snooze"; onClicked: row.store.op("ops.snoozePreset", modelData.id) }
            Act { sym: "open_in_new"; tip: "Open in webmail"; onClicked: row.store.call("ui.openLink", { "id": modelData.id }) }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        implicitHeight: 1; color: Appearance.colors.colLayer0Border; opacity: 0.5
    }
}
