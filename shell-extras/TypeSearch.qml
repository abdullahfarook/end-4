import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// After a workspace switch to an empty workspace, grab the keyboard for a short window; the first
// printable key opens the launcher search with that text. After the timeout
// the grab is released and typing goes to the window as usual.
Scope {
    id: root
    property bool armed: false
    readonly property int timeoutMs: 2500

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name === "openlayer" && root.armed && ev.data.indexOf("typesearch") < 0) { console.log("typesearch: disarm, layer opened", ev.data); root.disarm(); }   // popup/launcher opened: step aside
            if (ev.name === "workspacev2") { root.wsId = ev.data.split(",")[0]; wsQuery.running = true; }
        }
    }

    // only arm when the new workspace has no windows (asked from hyprctl: Quickshell's own state lags a switch)
    property string wsId: ""
    Process {
        id: wsQuery
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let empty = false;
                try {
                    const ws = JSON.parse(text).find(w => String(w.id) === root.wsId);
                    empty = !ws || ws.windows === 0;  // a workspace not listed yet is a fresh, empty one
                } catch (e) {}
                console.log("typesearch: ws", root.wsId, "empty =", empty);
                if (empty) root.arm(); else root.disarm();
            }
        }
    }

    // A left click ends the capture at once (Hyprland's non-consuming mouse:272 bind -> this shortcut):
    // holding the keyboard through a click would make shell popups close instantly. Pointer movement is fine.
    GlobalShortcut {
        appid: "typesearch"
        name: "click"
        onPressed: if (root.armed) { console.log("typesearch: disarm, click"); root.disarm(); }
    }

    function arm() { console.log("typesearch: arm"); armed = true; timer.restart(); }
    function disarm() { armed = false; timer.stop(); }

    Timer { id: timer; interval: root.timeoutMs; onTriggered: if (root.buffer === "") root.armed = false }

    // open on the first key at once; keys typed while it spins up are re-sent as one string
    property string buffer: ""
    property string sentText: ""
    function flush() {
        if (sender.running || buffer === "" || buffer === sentText) return;
        sentText = buffer;
        console.log("typesearch: send", JSON.stringify(buffer));
        sender.text = buffer;
        sender.running = true;
    }

    function finish() {
        console.log("typesearch: sender done, buffer", JSON.stringify(buffer), "sent", JSON.stringify(sentText));
        if (buffer !== sentText) { flush(); return; }
        buffer = ""; sentText = ""; disarm();
    }

    Process {
        id: sender
        property string text: ""
        onRunningChanged: if (!running) root.finish()
        command: ["bash", "-c", "exec qs -c ii ipc call search openWith \"$1\"", "_", text]
    }

    PanelWindow {
        id: grabWin
        visible: root.armed
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        // an empty Region {} still takes input, so leave only a 1px corner as the input area; clicks elsewhere pass through
        mask: Region { x: 0; y: 0; width: 1; height: 1 }
        WlrLayershell.namespace: "quickshell:typesearch"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.armed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                console.log("typesearch: key", event.key, JSON.stringify(event.text));
                if (event.key === Qt.Key_Escape) { root.disarm(); return; }
                const t = event.text;
                if (t.length > 0 && t >= " " && t !== "\x7f"
                        && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                    root.buffer += t;
                    root.flush();
                } else if (event.key === Qt.Key_Backspace && root.buffer.length > 0) {
                    root.buffer = root.buffer.slice(0, -1);
                    root.flush();
                } else if (t.length > 0 || event.key === Qt.Key_Return || event.key === Qt.Key_Tab) {
                    root.disarm();   // a shortcut or other real key: leave typing alone
                }
                // bare modifier presses (Super is usually still down after a switch) are ignored
            }
        }
    }
}
