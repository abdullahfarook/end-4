//@ pragma UseQApplication
// Breeze-style window buttons (minimize / maximize / close) drawn by the shell at the top-right corner of
// windows whose app has no buttons of its own. Idle: small handle at the top-centre of the window;
// hover: a drawer slides down with three circles.
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

    function refresh() { clientsProc.running = true }

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
            Timer { id: closeDelay; interval: 250; onTriggered: win.open = false }
            readonly property int sw: 152   // fixed surface size: never resizes, so hover can't flicker
            readonly property int sh: 58
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
                width: 136; height: 62; x: (win.sw - width) / 2
                y: win.open ? -14 : -height
                opacity: win.open ? 1 : 0
                Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
                Behavior on opacity { NumberAnimation { duration: 140 } }
                radius: 18; color: "#ff17171c"
                border.width: 1; border.color: "#14ffffff"
                clip: true

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; y: 20; spacing: 8
                    visible: win.open
                    Repeater {
                        model: [
                            { kind: "min", cmd: "hl.dsp.window.move({ workspace = 'special:minimized', window = '%A' })" },
                            { kind: "max", cmd: "hl.dsp.window.fullscreen({ mode = 1, window = '%A' })" },
                            { kind: "close", cmd: "hl.dsp.window.close({ window = '%A' })" }
                        ]
                        delegate: Rectangle {
                            id: btn
                            required property var modelData
                            width: 32; height: 32; radius: 16
                            color: ma.containsMouse ? (modelData.kind === "close" ? "#e5484d" : "#3d3d46") : "#26262d"
                            border.width: 1; border.color: "#14ffffff"
                            Behavior on color { ColorAnimation { duration: 100 } }
                            scale: ma.pressed ? 0.92 : 1
                            Behavior on scale { NumberAnimation { duration: 70 } }
                            Shape {
                                anchors.centerIn: parent; width: 16; height: 16
                                layer.enabled: true; layer.samples: 4
                                ShapePath {
                                    strokeColor: "#e8e8ee"; strokeWidth: 1.6; fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                                    PathPolyline {
                                        path: btn.modelData.kind === "min" ? [Qt.point(3, 6), Qt.point(8, 11), Qt.point(13, 6)]
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
                            MouseArea {
                                id: ma; anchors.fill: parent; hoverEnabled: true
                                onClicked: act.run(win.modelData.address, btn.modelData.cmd)
                            }
                        }
                    }
                }
            }
        }
    }
}
