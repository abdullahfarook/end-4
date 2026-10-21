import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// After a workspace switch to an empty workspace, grab the keyboard for a short window; the first
// printable key opens the launcher search with that text. After the timeout
// the grab is released and typing goes to the window as usual.
ShellRoot {
    id: root
    property bool armed: false
    readonly property int timeoutMs: 2500

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name === "workspacev2") checkTimer.restart();
        }
    }

    // only arm when the new workspace has no windows (give Hyprland state a moment to update)
    Timer {
        id: checkTimer
        interval: 10
        onTriggered: {
            Hyprland.refreshToplevels();
            const ws = Hyprland.focusedWorkspace;
            if (ws && ws.toplevels.values.length === 0) root.arm(); else root.disarm();
        }
    }

    function arm() { armed = true; timer.restart(); }
    function disarm() { armed = false; timer.stop(); }

    Timer { id: timer; interval: root.timeoutMs; onTriggered: if (root.buffer === "") root.armed = false }

    // open on the first key at once; keys typed while it spins up are re-sent as one string
    property string buffer: ""
    property string sentText: ""
    function flush() {
        if (sender.running || buffer === "" || buffer === sentText) return;
        sentText = buffer;
        sender.text = buffer;
        sender.running = true;
    }

    function finish() {
        if (buffer !== sentText) { flush(); return; }
        buffer = ""; sentText = ""; disarm();
    }

    Process {
        id: sender
        property string text: ""
        onRunningChanged: if (!running) root.finish()
        command: ["bash", "-c", "exec qs -c ii ipc call search openWith \"$1\"", "_", text]
    }

    // a click anywhere else clears the grab, so clicking works normally right after a switch
    HyprlandFocusGrab {
        windows: [grabWin]
        active: root.armed
        onCleared: root.disarm()
    }

    PanelWindow {
        id: grabWin
        visible: root.armed
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}   // empty: pointer input passes through
        WlrLayershell.namespace: "quickshell:typesearch"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.armed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) { root.disarm(); return; }
                const t = event.text;
                if (t.length > 0 && t >= " " && t !== "\x7f"
                        && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                    root.buffer += t;
                    root.flush();
                } else if (event.key === Qt.Key_Backspace && root.buffer.length > 0) {
                    root.buffer = root.buffer.slice(0, -1);
                    root.flush();
                } else {
                    root.disarm();
                }
            }
        }
    }
}
