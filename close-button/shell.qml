//@ pragma UseQApplication
// Breeze-style window buttons (drag / maximize / close) drawn by the shell for windows whose app has no
// buttons of its own. Idle: small handle at the top-centre of the window; hover: a drawer slides down with
// three circles. The grip circle drags the window: drop on the left/right screen edge to send it to the
// previous/next workspace.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    readonly property var noCloseClasses: ["org.kde.dolphin", "org.kde.konsole", "kitty", "org.kde.kate",
        "org.kde.okular", "org.kde.gwenview", "org.kde.ark", "org.kde.kcalc", "org.kde.spectacle",
        "org.kde.discover", "systemsettings", "pavucontrol", "nm-connection-editor", "org.gnome.nautilus"]
    property var wins: []

    // --- grip drag: the window follows the cursor over an overview-style workspace grid (2 rows x 5) ---
    property string dragAddr: ""
    property var dragScreen: null
    property var dragWin: null       // client being dragged (position/size/floating at drag start)
    property real dragX: 0
    property real dragY: 0
    property double lastMove: 0
    readonly property int edge: 48   // px at the left/right screen edge that act as "previous / next workspace" drop zones
    // -1 = previous workspace (left edge), +1 = next (right edge), 0 = none
    function edgeAt(x, sw) { return x <= edge ? -1 : (x >= sw - edge ? 1 : 0) }
    function track(win, mx, my, area) {
        const p = area.mapToItem(null, mx, my)
        dragX = win.margins.left + p.x
        dragY = win.margins.top + p.y
        const now = Date.now()
        if (now - lastMove < 16) return
        lastMove = now
        const mon = win.mon
        Hyprland.dispatch("hl.dsp.window.move({ x = " + Math.round(dragX + mon.x - dragWin.size[0] / 2) + ", y = " + Math.round(dragY + mon.y - 12)
            + ", window = 'address:" + dragAddr + "' })")
    }
    function beginDrag(win, mx, my, area) {
        dragWin = win.modelData
        dragScreen = win.screen
        dragAddr = win.modelData.address
        const p = area.mapToItem(null, mx, my)
        dragX = win.margins.left + p.x
        dragY = win.margins.top + p.y
        if (!dragWin.floating) Hyprland.dispatch("hl.dsp.window.float({ action = 'enable', window = 'address:" + dragAddr + "' })")
    }
    function endDrag() {
        if (dragAddr === "") return
        const dir = edgeAt(dragX, dragScreen.width)
        const ws = Math.max(1, dragWin.workspace.id + dir)
        const addr = dragAddr, w = dragWin
        dragAddr = ""
        if (dir !== 0) act.run(addr, "hl.dsp.window.move({ workspace = " + ws + ", follow = false, window = '%A' })")
        else Hyprland.dispatch("hl.dsp.window.move({ x = " + w.at[0] + ", y = " + w.at[1] + ", window = 'address:" + addr + "' })")
        if (!w.floating) Hyprland.dispatch("hl.dsp.window.float({ action = 'disable', window = 'address:" + addr + "' })")
        debounce.restart()
    }

    // click-through overlay shown while dragging: only a faint strip on the screen edge the cursor is over
    PanelWindow {
        visible: root.dragAddr !== ""
        screen: root.dragScreen
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:closebutton-drag"
        mask: Region {}
        readonly property int dir: root.dragScreen ? root.edgeAt(root.dragX, root.dragScreen.width) : 0
        Rectangle { visible: parent.dir === -1; x: 0; width: root.edge; height: parent.height; color: "#337aa2ff" }
        Rectangle { visible: parent.dir === 1; x: parent.width - root.edge; width: root.edge; height: parent.height; color: "#337aa2ff" }
    }

    function refresh() { if (dragAddr === "") clientsProc.running = true }

    Process {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.wins = JSON.parse(text).filter(c => c.mapped && !c.hidden && c.workspace.id > 0
                        && root.noCloseClasses.indexOf(c.class.toLowerCase()) >= 0)
                } catch (e) { root.wins = [] }
            }
        }
    }
    Timer { id: debounce; interval: 60; onTriggered: root.refresh() }
    Connections {
        target: Hyprland
        function onRawEvent(ev) { debounce.restart() }
    }
    Component.onCompleted: refresh()

    Process {
        id: act
        function run(addr, expr) {
            command = ["hyprctl", "dispatch", expr.replace("%A", "address:" + addr)]
            running = true
        }
    }

    Variants {
        model: root.wins
        PanelWindow {
            id: win
            required property var modelData
            readonly property var mon: Hyprland.monitors.values.find(m => m.id === modelData.monitor)
            screen: Quickshell.screens.find(s => s.name === (mon ? mon.name : "")) ?? Quickshell.screens[0]
            // only windows on the workspace currently shown on their monitor
            visible: mon && mon.activeWorkspace && mon.activeWorkspace.id === modelData.workspace.id
            color: "transparent"
            anchors { top: true; left: true }
            property bool open: false
            // short close delay so brief hover drops never flicker the drawer
            Timer { id: closeDelay; interval: 700; onTriggered: win.open = false }
            readonly property int sw: 108   // fixed surface size: never resizes, so hover can't flicker
            readonly property int sh: 38
            margins {
                left: modelData.at[0] - (mon ? mon.x : 0) + (modelData.size[0] - sw) / 2
                top: modelData.at[1] - (mon ? mon.y : 0)
            }
            implicitWidth: sw; implicitHeight: sh
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay   // above fullscreen/maximized windows too
            WlrLayershell.namespace: "quickshell:closebutton"

            // only the tab (idle) or the drawer (open) takes input; the rest of the surface is click-through
            mask: Region { item: win.open ? drawer : tab }

            Item {
                anchors.fill: parent
                HoverHandler { onHoveredChanged: { if (hovered) { closeDelay.stop(); win.open = true } else closeDelay.restart() } }
            }

            // idle: thin line; the invisible hit area (tab) keeps the larger trigger zone
            Item {
                id: tab
                width: 52; height: 14; x: (win.sw - width) / 2; y: 0
                opacity: win.open ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Rectangle {
                    width: parent.width; height: 4; y: -2
                    radius: 2; color: "#b3e8e8ee"
                }
            }

            // drawer: slides down from the window's top edge, rounded at the bottom only
            Rectangle {
                id: drawer
                width: 108; height: 52; x: (win.sw - width) / 2
                y: win.open ? -14 : -height
                opacity: win.open ? 1 : 0
                Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
                Behavior on opacity { NumberAnimation { duration: 140 } }
                radius: 16; color: "#ff17171c"
                border.width: 1; border.color: "#14ffffff"
                clip: true

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 20; spacing: 6
                    visible: win.open
                    Repeater {
                        model: [
                            { kind: "drag", cmd: "hl.dsp.window.drag()" },
                            { kind: "max", cmd: "hl.dsp.window.fullscreen({ mode = 1, window = '%A' })" },
                            { kind: "close", cmd: "hl.dsp.window.close({ window = '%A' })" }
                        ]
                        delegate: Rectangle {
                            id: btn
                            required property var modelData
                            width: 26; height: 26; radius: 13
                            color: ma.containsMouse ? (modelData.kind === "close" ? "#e5484d" : "#3d3d46") : "#26262d"
                            border.width: 1; border.color: "#14ffffff"
                            Behavior on color { ColorAnimation { duration: 100 } }
                            scale: ma.pressed ? 0.92 : 1
                            Behavior on scale { NumberAnimation { duration: 70 } }
                            Shape {
                                anchors.centerIn: parent; width: 16; height: 16; scale: 0.85
                                layer.enabled: true; layer.samples: 4
                                ShapePath {
                                    strokeColor: "#e8e8ee"; strokeWidth: 1.6; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                                    PathPolyline {
                                        path: btn.modelData.kind === "drag" ? []
                                            : btn.modelData.kind === "max" ? [Qt.point(8, 2), Qt.point(14, 8), Qt.point(8, 14), Qt.point(2, 8), Qt.point(8, 2)]
                                            : [Qt.point(3, 3), Qt.point(13, 13)]
                                    }
                                }
                                ShapePath {
                                    strokeColor: btn.modelData.kind === "close" ? "#e8e8ee" : "transparent"
                                    strokeWidth: 1.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                    PathPolyline { path: [Qt.point(13, 3), Qt.point(3, 13)] }
                                }
                            }
                            // drag: standard 2x3 grip-dot handle
                            Grid {
                                visible: btn.modelData.kind === "drag"
                                anchors.centerIn: parent; columns: 2; spacing: 2
                                Repeater { model: 6; Rectangle { width: 2; height: 2; radius: 1; color: "#e8e8ee" } }
                            }
                            MouseArea {
                                id: ma; anchors.fill: parent; hoverEnabled: true
                                preventStealing: true
                                onClicked: if (btn.modelData.kind !== "drag") act.run(win.modelData.address, btn.modelData.cmd)
                                // grip: press and drag (tap-and-drag on the touchpad); the window follows the cursor, release over a tile moves it there
                                onPressed: mouse => { if (btn.modelData.kind === "drag") { closeDelay.stop(); root.beginDrag(win, mouse.x, mouse.y, ma) } }
                                onPositionChanged: mouse => { if (root.dragAddr !== "" && btn.modelData.kind === "drag") root.track(win, mouse.x, mouse.y, ma) }
                                onReleased: if (btn.modelData.kind === "drag") root.endDrag()
                                onCanceled: if (btn.modelData.kind === "drag") root.endDrag()
                            }
                        }
                    }
                }
            }
        }
    }
}
