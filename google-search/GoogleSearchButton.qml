import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

// Bar button for the Google widget; click opens GoogleSearchPopup (search field + embedded QtWebEngine results).
RippleButton {
    id: root
    implicitWidth: 30    // fixed size so every bar icon button is identical
    implicitHeight: 30
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    property bool open: false
    // Last session (kept in memory only, lost when the shell restarts): restored when the popup opens again
    property string memQuery: ""
    property string memUrl: ""
    property int memWidth: 440 // widget width chosen by dragging its right edge (memory only)
    // Suggestion history (recent searches / addresses, newest first): saved to disk so it survives shell restarts.
    // Every bar has its own button, so the popup reloads the file when it opens and saves after each change.
    property var history: []
    readonly property string historyFile: Quickshell.env("HOME") + "/.local/state/google-search-history.json"
    FileView { id: store; path: root.historyFile; blockLoading: true; atomicWrites: true; watchChanges: false }
    function loadHistory() {
        try {
            store.reload();
            const j = JSON.parse(store.text());
            if (Array.isArray(j)) history = j.filter(x => typeof x === "string").slice(0, 50);
        } catch (e) {}
    }
    function saveHistory() { store.setText(JSON.stringify(history)) }
    Component.onCompleted: loadHistory()
    onClicked: open = !open

    MaterialSymbol {
        anchors.centerIn: parent
        text: "travel_explore"
        iconSize: 18
        color: Appearance.colors.colOnLayer0
    }

    // Popup is created only while open and unloaded on close
    Loader {
        active: root.open
        sourceComponent: GoogleSearchPopup {
            target: root
            onVisibleChanged: if (!visible) root.open = false
        }
    }
}
