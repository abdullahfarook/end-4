// Pulled-out YouTube video: small floating QtWebEngine window (title gsearch-pip; placed by the Hyprland rule in google-search-rules.lua).
// Run by gsearch-popout.sh: qml6 gsearch-pip.qml -- <video id> <start seconds>. Shows the watch page reduced to its player (works without yt-dlp, which YouTube blocks as a bot).
import QtQuick
import QtQuick.Window
import QtWebEngine

Window {
    id: win
    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    property bool fs: false
    visible: true; width: 480; height: 270; title: "gsearch-pip"; color: "black"

    WebEngineProfile { // cookies copied from the widget's profile by gsearch-popout.sh (solved captcha / consent), so YouTube doesn't show its bot check
        id: profile
        storageName: "gsearch-pip"
        persistentStoragePath: win.args[2]
        offTheRecord: false
    }

    WebEngineView {
        id: view
        profile: profile
        anchors.fill: parent
        backgroundColor: "black"
        settings.playbackRequiresUserGesture: false
        settings.fullScreenSupportEnabled: true
        // Hyprland refuses fullscreen for pinned windows: the window is only told here, gsearch-popout.sh (watching stderr) unpins + fullscreens it
        onFullScreenRequested: (req) => { req.accept(); win.fs = req.toggleOn; console.log("PIP fs " + (req.toggleOn ? 1 : 0)) }
        // The watch page with everything but the player hidden (the bare embed player refuses to play here: error 152/153, no referrer)
        url: "https://www.youtube.com/watch?v=" + win.args[0] + "&t=" + (win.args[1] || 0) + "s"
        userScripts.collection: [ {
            name: "pip", injectionPoint: WebEngineScript.DocumentReady, worldId: WebEngineScript.MainWorld, runsOnSubFrames: false,
            sourceCode: "(function(){var s=document.createElement('style');s.textContent="
                + JSON.stringify("html,body{overflow:hidden!important;background:#000!important}ytd-masthead,#secondary,#below,#comments,#related,tp-yt-app-drawer,#guide,ytd-miniplayer,ytd-consent-bump-v2-lightbox,tp-yt-iron-overlay-backdrop{display:none!important}"
                + "#movie_player{position:fixed!important;left:0!important;top:0!important;width:100vw!important;height:100vh!important;z-index:2147483647!important}")
                + ";document.documentElement.appendChild(s);setInterval(function(){window.dispatchEvent(new Event('resize'))},1500)})()"
        } ]
    }

    Rectangle { // close button, only while hovered
        id: closeBtn
        anchors { top: parent.top; right: parent.right; margins: 8 }
        width: 28; height: 28; radius: 14
        color: "#cc000000"
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Text { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 14 }
        TapHandler { onTapped: Qt.quit() }
    }
    HoverHandler { id: hover }
    Shortcut { sequence: "Esc"; onActivated: { if (win.fs) view.fullScreenCancelled(); else Qt.quit() } }
}
