import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import "MailBody.js" as BodyFormatter

// Right-hand detail panel of the mail popup: subject, triage actions and every message of the selected thread.
Rectangle {
    id: detail
    required property var store
    signal closeRequested()

    readonly property var thread: store.currentThread
    property bool replying: false
    property bool replyAll: false
    readonly property var sentReplies: thread ? (store.sentReplies[thread.id] || []) : []  // replies sent from this panel
    property var _threadId: null
    onThreadChanged: {  // the store swaps the thread object on every refresh: reset only when another thread opens
        const id = thread ? thread.id : null;
        if (id === null || id === _threadId) return;
        _threadId = id;
        replying = false; replyBox.text = "";
    }
    onReplyingChanged: if (replying) focusTimer.restart()
    Timer { id: focusTimer; interval: 60; onTriggered: replyBox.forceActiveFocus() }
    color: Appearance.m3colors.m3surfaceContainer
    radius: Appearance.rounding.normal
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    clip: true

    function senderName(raw) {
        const m = String(raw || "").match(/^\s*"?([^"<]*?)"?\s*<[^>]+>\s*$/);
        return m && m[1].trim() !== "" ? m[1].trim() : String(raw || "");
    }
    function fullDate(iso) { return Qt.formatDateTime(new Date(iso), "ddd d MMM yyyy, HH:mm"); }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 4
            StyledText {
                Layout.fillWidth: true
                text: detail.thread ? (detail.thread.subject || qsTr("(no subject)")) : ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
            }
            component Act: RippleButton {
                property string sym
                property string tip
                property color iconColor: Appearance.colors.colOnLayer1
                implicitWidth: 28; implicitHeight: 28; buttonRadius: 14
                MaterialSymbol { anchors.centerIn: parent; text: parent.sym; iconSize: 18; color: parent.iconColor }
                StyledToolTip { text: parent.tip }
            }
            Act { visible: !!detail.thread; sym: "archive"; tip: "Archive"; onClicked: { detail.store.op("ops.archive", detail.thread.id); detail.closeRequested(); } }
            Act { visible: !!detail.thread; sym: "delete"; tip: "Delete"; iconColor: Appearance.colors.colError
                  onClicked: { detail.store.op("ops.trash", detail.thread.id); detail.closeRequested(); } }
            Act { visible: !!detail.thread; sym: detail.thread && detail.thread.unread ? "drafts" : "mark_email_unread"
                  tip: detail.thread && detail.thread.unread ? "Mark as read" : "Mark as unread"
                  onClicked: detail.store.op(detail.thread.unread ? "ops.markRead" : "ops.markUnread", detail.thread.id) }
            Act { visible: !!detail.thread; sym: "star"; tip: detail.thread && detail.thread.starred ? "Unstar" : "Star"
                  iconColor: detail.thread && detail.thread.starred ? "#f5b942" : Appearance.colors.colOnLayer1
                  onClicked: detail.store.op(detail.thread.starred ? "ops.unstar" : "ops.star", detail.thread.id) }
            Act { visible: !!detail.thread; sym: "reply"; tip: "Reply"; onClicked: detail.replying = !detail.replying }
            Act { visible: !!detail.thread; sym: "web"; tip: "Full view (browser window)"; onClicked: detail.store.fetchHtml(detail.thread.id, true) }
            Act { visible: !!detail.thread; sym: "open_in_new"; tip: "Open in webmail"; onClicked: detail.store.call("ui.openLink", { "id": detail.thread.id }) }
            Act { sym: "close"; tip: "Close"; onClicked: detail.closeRequested() }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }

        Item {  // loading state: spinner until the thread and its original HTML are both ready
            visible: !detail.thread || !detail.store.htmlReady
            Layout.fillWidth: true; Layout.fillHeight: true
            StyledIndeterminateProgressBar {  // sliding bar right under the header
                anchors { top: parent.top; left: parent.left; right: parent.right }
            }
        }

        ListView {
            id: messages
            visible: !!detail.thread && detail.store.htmlReady
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            model: detail.thread ? detail.thread.messages : []
            ScrollBar.vertical: StyledScrollBar {}
            footer: Column {  // replies you just sent
                width: messages.width
                Repeater {
                    model: detail.sentReplies
                    delegate: Column {
                        required property var modelData
                        width: messages.width
                        Rectangle { width: parent.width; height: 1; color: Appearance.colors.colLayer0Border; opacity: 0.5 }
                        Item {
                            width: parent.width
                            implicitHeight: sentCol.implicitHeight + 28
                            height: implicitHeight
                            ColumnLayout {
                                id: sentCol
                                x: 14; y: 14
                                width: parent.width - 28
                                spacing: 4
                                StyledText {
                                    text: qsTr("You") + " · " + modelData.time + (modelData.all ? " · " + qsTr("reply all") : "")
                                    font.weight: Font.Bold
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.body
                                    wrapMode: Text.Wrap
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }
            delegate: ColumnLayout {
                id: msg
                required property var modelData
                required property int index
                width: messages.width
                spacing: 0
                readonly property string original: detail.store.rawHtml[modelData.id] || ""
                readonly property string html: original !== "" ? BodyFormatter.cleanHtml(original, Math.max(200, Math.floor(messages.width - 30))) : BodyFormatter.format(modelData.bodyText || modelData.snippet || "", {
                    "linkColor": String(Appearance.colors.colPrimary),
                    "quoteColor": String(Appearance.colors.colSubtext)
                })
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 14
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 36; implicitHeight: 36; radius: 18
                            color: Qt.hsla(((detail.senderName(modelData.from).charCodeAt(0) || 0) * 37 % 360) / 360, 0.45, 0.62, 1)
                            StyledText {
                                anchors.centerIn: parent
                                text: (detail.senderName(modelData.from).charAt(0) || "?").toUpperCase()
                                font.pixelSize: Appearance.font.pixelSize.larger
                                color: "#1b1b1f"
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: detail.senderName(modelData.from)
                                elide: Text.ElideRight
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: qsTr("to ") + (modelData.to || []).join(", ")
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                        StyledText {
                            text: detail.fullDate(modelData.date)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: msg.html
                        textFormat: Text.RichText
                        wrapMode: Text.Wrap
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        linkColor: Appearance.colors.colPrimary
                        onLinkActivated: link => Qt.openUrlExternally(link)
                        HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    }
                }
                Rectangle {
                    visible: msg.index < messages.count - 1
                    Layout.fillWidth: true; implicitHeight: 1
                    color: Appearance.colors.colLayer0Border; opacity: 0.5
                }
            }
        }

        Rectangle { visible: detail.replying; Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }
        ColumnLayout {  // inline reply: plain text, sent through ops.reply (no need to open the Dank Mail app)
            visible: detail.replying && !!detail.thread
            Layout.fillWidth: true
            Layout.margins: 10
            spacing: 6
            MaterialTextArea {
                id: replyBox
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                placeholderText: qsTr("Reply…")
                wrapMode: TextEdit.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                StyledText { text: qsTr("Reply all"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
                StyledSwitch { checked: detail.replyAll; onClicked: detail.replyAll = !detail.replyAll }
                RippleButton {
                    implicitWidth: 72; implicitHeight: 30; buttonRadius: 15
                    enabled: replyBox.text.trim() !== ""
                    colBackground: enabled ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: enabled ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2
                    onClicked: {
                        detail.store.call("ops.reply", { "id": detail.thread.id, "body": replyBox.text, "replyAll": detail.replyAll });
                        const all = Object.assign({}, detail.store.sentReplies);
                        all[detail.thread.id] = detail.sentReplies.concat([{ "body": replyBox.text.trim(), "all": detail.replyAll, "time": Qt.formatTime(new Date(), "HH:mm") }]);
                        detail.store.sentReplies = all;
                        replyBox.text = "";
                        detail.replying = false;
                        Qt.callLater(() => messages.positionViewAtEnd());
                    }
                    StyledText { anchors.centerIn: parent; text: qsTr("Send"); color: parent.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext }
                }
            }
        }
    }
}
