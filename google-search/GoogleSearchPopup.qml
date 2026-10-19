import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Google widget: one card (search field + progress line); the results are a real QtWebEngine window (gsearch.py)
// that appears under it only after the first search and tucks its top corners behind the card, so both read as one panel.
// Placed by the Hyprland rule in google-search-rules.lua; keep the geometry constants in sync.
// Typing loads results after a short pause, Enter immediately; Esc closes everything (also Esc in the browser).
Scope {
    id: root
    required property Item target
    property bool visible: true
    property string query: ""
    property bool browserShown: false
    property bool openGrab: true // exclusive keyboard focus right after opening
    property bool loading: false
    property real progress: 0
    property bool canBack: false
    property bool canForward: false
    readonly property string bin: Quickshell.env("HOME") + "/.config/hypr/custom/gsearch.py"
    readonly property int cardWidth: 440
    readonly property int headerHeight: 68
    readonly property int overlap: 8       // card extends this far over the browser's rounded top corners
    readonly property int browserX: 5
    readonly property int browserY: 114

    function go() { // send the query to the running browser window
        debounce.stop();
        const q = query.trim();
        if (q === "") { browserShown = false; loading = false }
        else if (!browserShown) loading = true; // first search: spinner in the card until the page is loaded
        Quickshell.execDetached([bin, "show", q]);
    }
    onVisibleChanged: if (!visible) closeBrowser()

    // The browser window lives on its own special workspace (rule in google-search-rules.lua); toggling it slides the browser in/out with the
    // curve/speed of the header layer. The scripts time the close against the layer's exit and keep the helper alive until the slide is done.
    readonly property string scriptDir: Quickshell.env("HOME") + "/.config/hypr/custom"
    property bool closed: false
    Component.onCompleted: {
        Quickshell.execDetached([scriptDir + "/gsearch-open.sh"]);
        Quickshell.execDetached({
            command: [bin, "show", ""],
            environment: { GSEARCH_BG: String(Appearance.m3colors.m3surfaceContainer), GSEARCH_THUMB: String(Appearance.colors.colOutlineVariant), GSEARCH_THUMB_HOVER: String(Appearance.colors.colOutline) }
        });
    }
    function closeBrowser() {
        if (closed) return;
        closed = true;
        Quickshell.execDetached([scriptDir + "/gsearch-close.sh"]);
    }
    Component.onDestruction: closeBrowser()

    Timer { interval: 400; running: true; onTriggered: root.openGrab = false }
    Timer { id: debounce; interval: 800; onTriggered: root.go() }
    // The helper runs detached (it must outlive this popup until the slide-out is done); it reports status lines to a file
    readonly property string statusFile: (Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp") + "/gsearch-status"
    Process {
        running: true
        command: ["sh", "-c", 'touch "$1"; exec tail -n 0 -F "$1"', "_", root.statusFile]
        stdout: SplitParser {
            onRead: line => {
                if (line === "shown") root.browserShown = true
                else if (line.startsWith("nav ")) { const p = line.split(" "); root.canBack = p[1] === "1"; root.canForward = p[2] === "1" }
                else if (line === "loading") { root.loading = true; root.progress = 0 }
                else if (line.startsWith("progress ")) root.progress = Number(line.slice(9)) / 100
                else if (line === "done" || line === "failed") root.loading = false
                else if (line === "exit") root.visible = false // Esc in the browser
            }
        }
    }

    // Click-away layer on every screen; on the popup's screen the browser area is left uncovered
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: away
            required property var modelData
            screen: modelData
            color: "transparent"
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:popup-dismiss"
            WlrLayershell.layer: WlrLayer.Top
            // Everything except the browser rectangle (a Subtract child region doesn't work reliably, so build the complement from bands)
            readonly property bool cut: root.browserShown && modelData.name === panel.screen?.name
            readonly property int bx: root.browserX
            readonly property int bx2: root.browserX + root.cardWidth
            // Item-based regions track geometry reliably (explicit rects were evaluated before the window had a size)
            mask: Region {
                item: topBand
                Region { item: leftBand }
                Region { item: rightBand }
            }
            Item { id: topBand; x: 0; y: 0; width: away.width; height: away.cut ? root.browserY : away.height }
            Item { id: leftBand; x: 0; y: 0; width: away.cut ? away.bx : 0; height: away.height }
            Item { id: rightBand; x: away.bx2; y: 0; width: away.cut ? away.width - away.bx2 : 0; height: away.height }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.visible = false }
        }
    }

    PanelWindow {
        id: panel
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null // same monitor the special workspace opens on
        color: "transparent"
        anchors { top: true; left: true }
        implicitWidth: root.cardWidth + Appearance.sizes.hyprlandGapsOut + Appearance.sizes.elevationMargin
        anchors.bottom: true
        mask: Region { item: card }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:sidebarLeft"
        WlrLayershell.layer: WlrLayer.Overlay
        // The field must own the keyboard on open and while the first search loads (the browser window would steal focus when it maps),
        // so grab it exclusively for a moment / while loading; otherwise OnDemand, because an exclusive layer makes Hyprland
        // ignore clicks on windows and on the click-away layer.
        WlrLayershell.keyboardFocus: (root.openGrab || (root.query.trim() !== "" && !root.browserShown)) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
        Component.onCompleted: input.forceActiveFocus()

        StyledRectangularShadow { target: card }
        Rectangle {
            id: card
            anchors { top: parent.top; left: parent.left; topMargin: Appearance.sizes.hyprlandGapsOut; leftMargin: Appearance.sizes.hyprlandGapsOut }
            width: root.cardWidth
            // empty state: full-height card like the file search; after a search it shrinks to the header and the browser takes the body
            height: root.browserShown ? root.headerHeight + root.overlap : parent.height - Appearance.sizes.hyprlandGapsOut * 2
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true

            Rectangle { // square bottom corners while the browser is attached
                visible: root.browserShown
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Appearance.rounding.normal
                color: card.color
            }

            ColumnLayout { // empty state
                visible: !root.browserShown
                anchors.centerIn: parent
                spacing: 12
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 72; implicitHeight: 72
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.loading ? "progress_activity" : "travel_explore"
                        iconSize: 36
                        color: Appearance.colors.colOnSecondaryContainer
                        RotationAnimator on rotation { running: root.loading; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onRunningChanged: if (!running && target) target.rotation = 0 }
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.loading ? "Searching…" : "Search Google"
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
            }
            StyledText {
                visible: !root.browserShown
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                text: "Enter search · Alt+click a link opens it in the browser · Esc close"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RowLayout { // browser toolbar (only with results)
                id: tools
                visible: root.browserShown
                anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: 14 }
                height: 40
                spacing: 2
                Repeater {
                    model: [
                        { icon: "arrow_back", tip: "Back", cmd: "back", on: root.canBack },
                        { icon: "arrow_forward", tip: "Forward", cmd: "forward", on: root.canForward },
                        { icon: root.loading ? "close" : "refresh", tip: root.loading ? "Stop" : "Reload", cmd: root.loading ? "stop" : "reload", on: true },
                        { icon: "open_in_new", tip: "Open in browser", cmd: "open", on: true }
                    ]
                    delegate: RippleButton {
                        required property var modelData
                        implicitWidth: 34; implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        enabled: modelData.on
                        onClicked: Quickshell.execDetached([root.bin, modelData.cmd])
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
                anchors { left: parent.left; right: root.browserShown ? tools.left : parent.right; top: parent.top; margins: 14; rightMargin: root.browserShown ? 6 : 14 }
                height: 40
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
                    spacing: 8
                    Item {
                        implicitWidth: Appearance.font.pixelSize.huge; implicitHeight: Appearance.font.pixelSize.huge
                        MaterialSymbol { anchors.centerIn: parent; visible: !root.loading; text: "search"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colSubtext }
                        MaterialSymbol {
                            id: spin
                            anchors.centerIn: parent
                            visible: root.loading
                            text: "progress_activity"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                            RotationAnimator on rotation { running: root.loading; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                    }
                    StyledTextInput {
                        id: input
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        clip: true
                        onTextChanged: {
                            root.query = text;
                            if (text.trim() === "") root.go(); else debounce.restart();
                        }
                        Keys.onEscapePressed: root.visible = false
                        Keys.onReturnPressed: root.go()
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
                visible: root.loading
                anchors { left: parent.left; top: parent.top; topMargin: root.headerHeight + root.overlap - 2 }
                height: 2
                width: parent.width * root.progress
                color: Appearance.colors.colPrimary
                Behavior on width { NumberAnimation { duration: 150 } }
            }
        }
    }
}
