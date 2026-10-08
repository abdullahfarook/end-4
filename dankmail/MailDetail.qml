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

    function sendReply() {
        if (!thread || replyBox.text.trim() === "") return;
        store.call("ops.reply", { "id": thread.id, "body": replyBox.text, "replyAll": replyAll });
        replyBox.text = "";
        replying = false;
    }
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
            reuseItems: true
            maximumFlickVelocity: 6000
            property real wheelTarget: 0
            Behavior on contentY { enabled: wheelArea.animating; NumberAnimation { duration: 140; easing.type: Easing.OutCubic; onRunningChanged: if (!running) wheelArea.animating = false } }
            MouseArea {  // bigger, smoothed wheel steps (Qt's default ~20px per notch feels glacial on long mails)
                id: wheelArea
                property bool animating: false
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: w => {
                    const maxY = Math.max(0, messages.contentHeight - messages.height);
                    const base = animating ? messages.wheelTarget : messages.contentY;
                    const step = Math.abs(w.angleDelta.y) >= 120 ? 1.6 : 0.5;  // mouse notch vs touchpad
                    messages.wheelTarget = Math.max(0, Math.min(base - w.angleDelta.y * step, maxY));
                    animating = true;
                    messages.contentY = messages.wheelTarget;
                    w.accepted = true;
                }
            }
            boundsBehavior: Flickable.StopAtBounds
            model: detail.thread ? detail.thread.messages : []
            ScrollBar.vertical: StyledScrollBar {}
            Component {
                id: imageSlot
                Item {
                    id: slot
                    property var seg: ({})
                    readonly property real maxW: Math.max(200, Math.floor(messages.width - 30))
                    implicitHeight: img.status === Image.Error || (img.status === Image.Null && !seg.url) ? 0
                        : img.status === Image.Ready ? img.paintedHeight : Math.max(48, Math.min(160, (seg.w || 120) * 0.5))
                    Image {
                        id: img
                        asynchronous: true
                        source: slot.seg.url || ""
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: Math.ceil(slot.maxW * 2)  // cap decode size: huge originals made scrolling janky
                        cache: true
                        smooth: false
                        mipmap: false
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        width: Math.min(slot.seg.w > 0 ? slot.seg.w : implicitWidth, slot.maxW)
                        height: implicitWidth > 0 ? width * implicitHeight / implicitWidth : 0
                        visible: opacity > 0
                    }
                    Rectangle {  // skeleton: soft rounded block with a slow shimmer while the image loads
                        id: skel
                        visible: img.status === Image.Loading || img.status === Image.Null
                        width: Math.min(slot.seg.w > 0 ? slot.seg.w : slot.maxW, slot.maxW)
                        height: parent.height - 6
                        y: 3
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)
                        clip: true
                        Rectangle {
                            id: shine
                            width: parent.width * 0.5; height: parent.height
                            rotation: 0
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.07) }
                                GradientStop { position: 1; color: "transparent" }
                            }
                            NumberAnimation on x { running: skel.visible; from: -shine.width; to: skel.width; duration: 1800; easing.type: Easing.InOutSine; loops: Animation.Infinite }
                        }
                    }
                }
            }
            Component {
                id: textSlot
                Text {
                    property var seg: ({})
                    text: seg.html
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                    renderType: Text.NativeRendering  // cheaper to scroll than outline-tessellated glyphs
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    linkColor: Appearance.colors.colPrimary
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
            }
            delegate: ColumnLayout {
                id: msg
                required property var modelData
                required property int index
                width: messages.width
                spacing: 0
                readonly property string original: detail.store.rawHtml[modelData.id] || ""
                readonly property var imageSrcs: original !== "" ? BodyFormatter.imageSources(original) : []
                property var imagesLoaded: ({})  // url -> {w, h} once an image preloaded fine; failed ones never appear
                readonly property string html: original !== "" ? BodyFormatter.cleanHtml(original, Math.max(200, Math.floor(messages.width - 30)), msg.imagesLoaded) : BodyFormatter.format(modelData.bodyText || modelData.snippet || "", {
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
                    Repeater {  // text and images as separate items: images are plain QML Images (spinner until ready), never Qt's text-view image loader (its placeholder icon)
                        model: msg.original !== "" ? BodyFormatter.segments(msg.original, Math.max(200, Math.floor(messages.width - 30))) : [{ "html": msg.html }]
                        delegate: Loader {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            sourceComponent: modelData.img ? imageSlot : textSlot
                            onLoaded: item.seg = modelData
                        }
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
                placeholderText: qsTr("Write a reply…  Enter to send · Shift+Enter for a new line")
                placeholderTextColor: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: TextEdit.Wrap
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                        detail.sendReply();
                        event.accepted = true;
                    }
                }
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
                    onClicked: detail.sendReply()
                    StyledText { anchors.centerIn: parent; text: qsTr("Send"); color: parent.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext }
                }
            }
        }
    }
}
