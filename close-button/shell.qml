//@ pragma UseQApplication
// Forced close button at the top-right corner of windows whose app has no close button of its own.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    // app classes (lowercase) that have no close button; "*" would mean every window
    readonly property var noCloseClasses: ["org.kde.dolphin", "org.kde.konsole", "kitty", "org.kde.kate",
        "org.kde.okular", "org.kde.gwenview", "org.kde.ark", "org.kde.kcalc", "org.kde.spectacle",
        "org.kde.discover", "systemsettings", "pavucontrol", "nm-connection-editor", "org.gnome.nautilus"]
    readonly property int size: 22
    property var wins: []

    function refresh() { clientsProc.running = true }

    Process {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const act = JSON.parse(text)
                    root.wins = act.filter(c => c.mapped && !c.hidden && c.workspace.id > 0
                        && !c.fullscreen && root.noCloseClasses.indexOf(c.class.toLowerCase()) >= 0)
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
        id: closeProc
        function run(addr) {
            command = ["hyprctl", "dispatch", "hl.dsp.window.close({ window = 'address:" + addr + "' })"]
            running = true
        }
    }

    // one tiny layer surface per button: no input mask needed, the rest of the screen stays click-through
    Variants {
        model: root.wins
        PanelWindow {
            id: win
            required property var modelData
            readonly property var mon: Hyprland.monitors.values.find(m => m.id === modelData.monitor)
            screen: Quickshell.screens.find(s => s.name === (mon ? mon.name : "")) ?? Quickshell.screens[0]
            color: "transparent"
            anchors { top: true; left: true }
            margins {
                left: modelData.at[0] - (mon ? mon.x : 0) + modelData.size[0] - width - 1
                top: modelData.at[1] - (mon ? mon.y : 0) + 1
            }
            // collapsed to a thin sliver at the corner; grows into the full button on hover
            property bool open: false
            readonly property int width: open ? root.size : 4
            implicitWidth: width; implicitHeight: root.size
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell:closebutton"

            Rectangle {
                anchors.fill: parent; radius: 6
                color: win.open ? "#e5484d" : "#cce5484d"
                Text { visible: win.open; anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 11 }
                MouseArea {
                    id: ma; anchors.fill: parent; hoverEnabled: true
                    onEntered: win.open = true
                    onExited: win.open = false
                    onClicked: closeProc.run(modelData.address)
                }
            }
        }
    }
}
