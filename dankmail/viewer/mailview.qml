import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

// Long-lived HTML mail viewer: `QML_XHR_ALLOW_FILE_READ=1 qml6 mailview.qml <pointer-file>`.
// The mail widget writes the message HTML to a file and rewrites the pointer file (line 1: html path,
// line 2: title, line 3: sequence); this window polls the pointer and navigates, so one window is reused for every email.
// JavaScript is off, remote images are allowed, links open in the default browser.
// Quits on close, Escape, or when minimized.
ApplicationWindow {
    id: win
    width: 900; height: 800
    visible: true
    title: "Mail"
    color: "white"

    readonly property string pointer: Qt.application.arguments.length > 1 ? Qt.application.arguments[Qt.application.arguments.length - 1] : ""
    property string seq: ""

    onVisibilityChanged: if (visibility === Window.Minimized) Qt.quit()
    onClosing: Qt.quit()

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10; anchors.rightMargin: 4
            Label { text: win.title; elide: Text.ElideRight; Layout.fillWidth: true; font.bold: true }
            ToolButton { text: "–"; onClicked: win.showMinimized(); ToolTip.visible: hovered; ToolTip.text: "Minimize (closes the viewer)" }
            ToolButton { text: "✕"; onClicked: Qt.quit(); ToolTip.visible: hovered; ToolTip.text: "Close" }
        }
    }

    WebEngineView {
        id: view
        anchors.fill: parent
        backgroundColor: "white"
        settings.javascriptEnabled: false
        settings.autoLoadImages: true
        settings.localContentCanAccessRemoteUrls: true   // file:// page loading remote images
        settings.localContentCanAccessFileUrls: false
        settings.pluginsEnabled: false
        onNavigationRequested: request => {
            if (request.navigationType === WebEngineNavigationRequest.LinkClickedNavigation) {
                request.action = WebEngineNavigationRequest.IgnoreRequest;
                Qt.openUrlExternally(request.url);
            }
        }
    }

    function poll() {
        if (!pointer) return;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || !xhr.responseText) return;
            const lines = xhr.responseText.split("\n");
            if (lines.length < 3 || lines[2] === win.seq) return;
            win.seq = lines[2];
            win.title = lines[1] || "Mail";
            view.url = "file://" + lines[0];
        };
        xhr.open("GET", "file://" + pointer);
        xhr.send();
    }
    Timer { interval: 200; repeat: true; running: true; triggeredOnStart: true; onTriggered: win.poll() }
    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
}
