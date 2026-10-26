import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Google widget: bar button + side panel (search field + results in a separate QtWebEngine window placed next to the card).
// Panel behavior (open/close, click-away, monitors) comes from WidgetBase; the content draws its own card (it shrinks to a
// header when results show) and leaves the browser area click-through.
WidgetBase {
    id: root
    iconName: "public"
    iconSize: 18
    panelCard: false
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

    panelContent: Component { FocusScope {
        id: gq
        readonly property var target: root   // the button keeps the session (query, page, width) and history while closed
        // WidgetBase contract for a custom layout
        readonly property list<Item> panelMaskItems: [card, dropdown, grip]
        readonly property rect panelClickThrough: gq.browserShown ? Qt.rect(gq.browserX, gq.browserY, gq.cardWidth, (root.panelScreen?.height ?? 2000) - gq.browserY) : Qt.rect(0, 0, 0, 0)
        readonly property bool panelHidden: gq.fullscreen   // the page video is fullscreen
        Binding { target: root; property: "panelWidth"; value: gq.cardWidth }
        // The field must own the keyboard on open and while the first search loads (the browser window would steal focus when it maps),
        // so grab it exclusively for a moment / while loading; otherwise OnDemand, because an exclusive layer makes Hyprland
        // ignore clicks on windows and on the click-away layer.
        Binding { target: root; property: "panelKeyboardFocus"; value: (gq.openGrab || (gq.loading && !gq.browserShown)) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand }
        readonly property string screenName: root.panelScreen?.name ?? ""   // the bar's monitor, pinned at open (the browser opens there too)
        property string query: ""
        property bool browserShown: false
        property bool restoring: false
        property bool openGrab: true // exclusive keyboard focus right after opening
        property bool loading: false
        property real progress: 0
        property bool canBack: false
        property bool canForward: false
        property bool hasVideo: false
        property bool fullscreen: false // the page video is fullscreen: hide the card
        readonly property string bin: Quickshell.env("HOME") + "/.config/hypr/custom/gsearch.sh"
        property int cardWidth: target.memWidth
        readonly property int minWidth: 320
        readonly property int maxWidth: Math.max(minWidth, (root.panelScreen?.width ?? 1200) - 100)
        function applyWidth() { Quickshell.execDetached([scriptDir + "/gsearch-resize.sh", String(cardWidth)]) }
        readonly property int headerHeight: 40
        readonly property int overlap: 8       // card extends this far over the browser's rounded top corners
        readonly property int browserX: 5
        readonly property int browserY: 86

        function go(text) { // search/open `text` (Enter or picking a suggestion); typing alone never searches
            const q = (text ?? query).trim();
            if (q === "") return;
            suggestOpen = false;
            target.memQuery = q;
            target.history = [q].concat(target.history.filter(h => h.toLowerCase() !== q.toLowerCase())).slice(0, 50);
            target.saveHistory();
            if (!browserShown) loading = true; // first search: spinner in the field until the page is loaded
            Quickshell.execDetached([bin, "show", q]);
        }

        // Suggestions from recent searches/addresses (in memory, kept on the bar button)
        property bool suggestOpen: false
        property int sel: -1
        property var suggestions: []
        function refreshSuggestions() { // only while typing, and only entries related to the typed text
            const q = input.text.trim().toLowerCase();
            const h = target.history ?? [];
            sel = -1;
            if (q === "") { suggestions = []; suggestOpen = false; return; }
            const r = h.filter(x => x.toLowerCase().includes(q) && x.toLowerCase() !== q);
            suggestions = r.filter(x => x.toLowerCase().startsWith(q)).concat(r.filter(x => !x.toLowerCase().startsWith(q))).slice(0, 8);
            suggestOpen = suggestions.length > 0;
        }
        function removeHistory(item) {
            target.history = target.history.filter(h => h !== item);
            target.saveHistory();
            refreshSuggestions();
        }

        // The browser window lives on its own special workspace (rule in google-search-rules.lua); toggling it slides the browser in/out with the
        // curve/speed of the header layer. The scripts time the close against the layer's exit and keep the helper alive until the slide is done.
        readonly property string scriptDir: Quickshell.env("HOME") + "/.config/hypr/custom"
        property bool closed: false
        Component.onCompleted: {
            Quickshell.execDetached([scriptDir + "/gsearch-open.sh"]);
            target.loadHistory(); // pick up changes saved by another bar's button
            const url = gq.target.memUrl ?? "";
            if (url !== "") { // restore the last session: field text + exact page (selected, so typing replaces it)
                gq.restoring = true;
                input.text = gq.target.memQuery ?? "";
                input.selectAll();
                gq.restoring = false;
                gq.loading = true;
            }
            Quickshell.execDetached({
                command: url !== "" ? [bin, "goto", url] : [bin, "show", ""],
                environment: { GSEARCH_BG: String(Appearance.m3colors.m3surfaceContainer), GSEARCH_THUMB: String(Appearance.colors.colOutlineVariant), GSEARCH_THUMB_HOVER: String(Appearance.colors.colOutline) }
            });
        }
        function closeBrowser() {
            if (closed) return;
            closed = true;
            if (query.trim() === "") { target.memUrl = ""; target.memQuery = "" } // cleared and closed: don't restore the last page next time
            Quickshell.execDetached([scriptDir + "/gsearch-close.sh"]);
        }
        Component.onDestruction: closeBrowser()

        Timer { interval: 400; running: true; onTriggered: gq.openGrab = false }
        Timer { id: resizeTick; interval: 50; onTriggered: gq.applyWidth() }
        // The helper runs detached (it must outlive this popup until the slide-out is done); it reports status lines to a file
        readonly property string statusFile: (Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp") + "/gsearch-status"
        Process {
            running: true
            command: ["sh", "-c", 'touch "$1"; exec tail -n 0 -F "$1"', "_", gq.statusFile]
            stdout: SplitParser {
                onRead: line => {
                    if (line === "shown") { gq.browserShown = true; if (gq.cardWidth !== 440) gq.applyWidth(); Quickshell.execDetached([gq.scriptDir + "/gsearch-open.sh"]) } // open.sh is idempotent: re-shows the browser workspace if it got out of sync
                    else if (line.startsWith("popout ")) { const i = line.indexOf(" ", 7); Quickshell.execDetached([gq.scriptDir + "/gsearch-popout.sh", line.slice(7, i), line.slice(i + 1)]) }
                    else if (line === "popout-none") Quickshell.execDetached(["notify-send", "-a", "Google", "No video on this page"])
                    else if (line.startsWith("fullscreen ")) gq.fullscreen = line.endsWith("1")
                    else if (line.startsWith("video ")) gq.hasVideo = line.endsWith("1")
                    else if (line.startsWith("nav ")) { const p = line.split(" "); gq.canBack = p[1] === "1"; gq.canForward = p[2] === "1" }
                    else if (line.startsWith("url ")) gq.target.memUrl = line.slice(4)
                    else if (line === "loading") { gq.loading = true; gq.progress = 0 }
                    else if (line.startsWith("progress ")) gq.progress = Number(line.slice(9)) / 100
                    else if (line === "done" || line === "failed") gq.loading = false
                    else if (line === "exit") root.close() // Esc in the browser
                }
            }
        }

        StyledRectangularShadow { target: card }

        Item { // drag handle on the right edge: resizes the widget (card + browser window)
            id: grip
            x: card.x + card.width - 2
            y: card.y
            width: 10
            height: gq.height - card.y - Appearance.sizes.hyprlandGapsOut // full height: the card shrinks to the header once the browser is shown
            z: 20
            property real startX: 0
            property int startW: 440
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                onPressed: mouse => { grip.startX = mapToItem(null, mouse.x, 0).x; grip.startW = gq.cardWidth }
                onPositionChanged: mouse => {
                    if (!pressed) return;
                    const dx = mapToItem(null, mouse.x, 0).x - grip.startX;
                    gq.target.memWidth = Math.round(Math.max(gq.minWidth, Math.min(gq.maxWidth, grip.startW + dx)));
                    if (!resizeTick.running) resizeTick.start();
                }
                onReleased: gq.applyWidth()
                onDoubleClicked: { gq.target.memWidth = 440; gq.applyWidth() }
                Rectangle { // subtle grab indicator on hover
                    anchors.centerIn: parent
                    width: 3; height: 48; radius: 2
                    color: Appearance.colors.colOutline
                    opacity: parent.containsMouse || parent.pressed ? 0.8 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }
        }

        Rectangle { // suggestions from recent searches (over the empty state or the browser), like a browser address-bar list
            id: dropdown
            visible: gq.suggestOpen && gq.suggestions.length > 0
            x: card.x + 14
            y: card.y + 14 + 40 + 4
            width: gq.suggestOpen ? gq.cardWidth - 28 : 0
            height: visible ? list.implicitHeight + 8 : 0
            radius: Appearance.rounding.small + 4
            color: Appearance.m3colors.m3surfaceContainerHigh // opaque: the layer-2 color is translucent and showed the windows behind
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            z: 10
            ColumnLayout {
                id: list
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
                spacing: 0
                Repeater {
                    model: gq.suggestions
                    delegate: RippleButton {
                        id: row
                        required property string modelData
                        required property int index
                        readonly property string typed: input.text.trim()
                        readonly property string shown: tm.elidedText
                        readonly property int at: shown.toLowerCase().indexOf(typed.toLowerCase())
                        function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
                        // typed part regular, the rest bold (address-bar style: the completion stands out)
                        readonly property string html: at < 0 ? esc(shown)
                            : esc(shown.slice(0, at)) + "<span style='color:" + Appearance.colors.colSubtext + "'>" + esc(shown.slice(at, at + typed.length)) + "</span><b>" + esc(shown.slice(at + typed.length)) + "</b>"
                        TextMetrics { id: tm; font.pixelSize: Appearance.font.pixelSize.small; text: modelData; elide: Text.ElideRight; elideWidth: Math.max(0, label.width) }
                        Layout.fillWidth: true
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.small
                        colBackground: gq.sel === index ? Appearance.colors.colSecondaryContainer : "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: { input.programmatic = true; input.text = modelData; input.programmatic = false; gq.go(modelData) }
                        contentItem: RowLayout {
                            spacing: 8
                            MaterialSymbol { Layout.leftMargin: 4; text: /^(https?:\/\/|www\.)|^[\w-]+(\.[\w-]+)+(\/|$)/i.test(row.modelData) ? "language" : "history"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colSubtext }
                            StyledText { id: label; Layout.fillWidth: true; clip: true; textFormat: Text.RichText; text: row.html; elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer2 }
                            RippleButton { // forget this entry
                                visible: row.hovered || gq.sel === row.index
                                implicitWidth: 22; implicitHeight: 22
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer1Hover
                                onClicked: gq.removeHistory(row.modelData)
                                contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; text: "close"; iconSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                                StyledToolTip { text: "Remove from history"; visible: parent.hovered }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: card
            anchors { top: parent.top; left: parent.left; topMargin: Appearance.sizes.hyprlandGapsOut; leftMargin: Appearance.sizes.hyprlandGapsOut }
            width: gq.cardWidth
            // empty state: full-height card like the file search; after a search it shrinks to the header and the browser takes the body
            height: gq.browserShown ? gq.headerHeight + gq.overlap : parent.height - Appearance.sizes.hyprlandGapsOut * 2
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true

            Rectangle { // square bottom corners while the browser is attached
                visible: gq.browserShown
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Appearance.rounding.normal
                color: card.color
            }

            ColumnLayout { // empty state
                visible: !gq.browserShown
                anchors.centerIn: parent
                spacing: 12
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 72; implicitHeight: 72
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer
                    MaterialSymbol { anchors.centerIn: parent; text: "travel_explore"; iconSize: 36; color: Appearance.colors.colOnSecondaryContainer }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Search Google"
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
            }
            StyledText {
                visible: !gq.browserShown
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                text: "Enter search · Ctrl+click a link opens it in the browser · Esc close"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RowLayout { // browser toolbar (only with results)
                id: tools
                visible: gq.browserShown
                anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: gq.browserShown ? 12 : 14 }
                height: 28
                spacing: 2
                Repeater {
                    model: [
                        { icon: "arrow_back", tip: "Back", cmd: "back", on: gq.canBack },
                        { icon: "arrow_forward", tip: "Forward", cmd: "forward", on: gq.canForward },
                        { icon: gq.loading ? "close" : "refresh", tip: gq.loading ? "Stop" : "Reload", cmd: gq.loading ? "stop" : "reload", on: true },
                        { icon: "picture_in_picture_alt", tip: "Pop out video", cmd: "popout", on: true },
                        { icon: "open_in_new", tip: "Open in browser", cmd: "open", on: true }
                    ]
                    delegate: RippleButton {
                        required property var modelData
                        visible: modelData.cmd !== "popout" || gq.hasVideo
                        implicitWidth: 26; implicitHeight: 26
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        enabled: modelData.on
                        onClicked: Quickshell.execDetached([gq.bin, modelData.cmd])
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            color: modelData.on ? Appearance.colors.colOnLayer1 : Appearance.colors.colOutlineVariant
                        }
                        StyledToolTip { text: modelData.tip; visible: parent.hovered }
                    }
                }
            }

            Rectangle { // search pill
                id: pill
                anchors { left: parent.left; right: gq.browserShown ? tools.left : parent.right; top: parent.top; margins: gq.browserShown ? 12 : 14; leftMargin: 14; rightMargin: gq.browserShown ? 6 : 14 }
                height: gq.browserShown ? 28 : 40
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                MouseArea { // text cursor over the field; clicks fall through to the input and buttons
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.IBeamCursor
                }
                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
                    spacing: 8
                    Item {
                        implicitWidth: Appearance.font.pixelSize.huge; implicitHeight: Appearance.font.pixelSize.huge
                        MaterialSymbol { anchors.centerIn: parent; visible: !gq.loading; text: "search"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colSubtext }
                        MaterialSymbol {
                            id: spin
                            anchors.centerIn: parent
                            visible: gq.loading
                            text: "progress_activity"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                            RotationAnimator on rotation { running: gq.loading; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                    }
                    StyledTextInput {
                        id: input
                        focus: true
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        clip: true
                        property bool programmatic: false
                        onTextChanged: {
                            gq.query = text;
                            if (gq.restoring || programmatic) return;
                            gq.refreshSuggestions(); // typing only suggests; searching needs Enter
                        }
                        onActiveFocusChanged: if (!activeFocus) gq.suggestOpen = false
                        Keys.onEscapePressed: { if (gq.suggestOpen) gq.suggestOpen = false; else root.close() }
                        Keys.onDownPressed: {
                            if (!gq.suggestOpen) gq.refreshSuggestions();
                            if (gq.suggestions.length > 0) gq.sel = Math.min(gq.sel + 1, gq.suggestions.length - 1);
                        }
                        Keys.onUpPressed: gq.sel = Math.max(gq.sel - 1, -1)
                        Keys.onReturnPressed: {
                            const pick = gq.sel >= 0 ? gq.suggestions[gq.sel] : null;
                            if (pick) { programmatic = true; text = pick; programmatic = false; gq.go(pick) } else gq.go()
                        }
                        StyledText {
                            visible: input.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search Google…"
                            color: Appearance.colors.colSubtext
                        }
                    }
                    RippleButton { // clear
                        visible: input.text !== ""
                        implicitWidth: 28; implicitHeight: 28
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: { input.text = ""; input.forceActiveFocus() }
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }
                        StyledToolTip { text: "Clear"; visible: parent.hovered }
                    }
                }
            }

            Rectangle { // page load progress
                visible: gq.loading
                anchors { left: parent.left; top: parent.top; topMargin: gq.headerHeight + gq.overlap - 2 }
                height: 2
                width: parent.width * gq.progress
                color: Appearance.colors.colPrimary
                Behavior on width { NumberAnimation { duration: 150 } }
            }
        }
    } }
}
