import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Docker popup: container list with state, image, CPU/memory and ports; click a container for live logs
// (follow/pause, copy, start/stop/restart). Polls only while visible.
Scope {
    id: root
    required property Item target
    property bool visible: true
    property var containers: []        // [{id, name, image, state, status, ports, cpu, mem}]
    property var stats: ({})           // name -> {cpu, mem}
    property string error: ""
    property bool loaded: false
    property bool daemonDown: false    // `docker ps` failed: daemon not running / not reachable
    property string selected: ""       // container name whose logs are shown ("" = list)
    property var logLines: []
    property bool follow: true
    property bool paused: false
    readonly property var current: containers.find(c => c.name === selected) ?? null

    Component.onCompleted: refresh()
    onVisibleChanged: if (!visible) { selected = ""; logProc.running = false }
    onSelectedChanged: {
        logProc.running = false;
        logLines = []; follow = true; paused = false;
        if (selected !== "") {
            logProc.command = ["bash", "-c", "exec docker logs -f --tail 300 \"$0\" 2>&1", selected];
            logProc.running = true;
        }
    }

    function refresh() {
        if (!psProc.running) psProc.running = true;
        if (!statsProc.running) statsProc.running = true;
    }
    function act(verb) { Quickshell.execDetached(["docker", verb, selected]); refreshSoon.restart() }
    Timer { id: refreshSoon; interval: 1200; onTriggered: root.refresh() }
    Timer { interval: 3000; repeat: true; running: root.visible; onTriggered: root.refresh() }

    Process {
        id: psProc
        command: ["docker", "ps", "--format", "{{json .}}"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const l of text.split("\n")) {
                    if (!l.trim()) continue;
                    try {
                        const j = JSON.parse(l);
                        out.push({ id: j.ID, name: j.Names, image: j.Image, state: j.State, status: j.Status, ports: j.Ports ?? "" });
                    } catch (e) {}
                }
                out.sort((a, b) => (b.state === "running") - (a.state === "running") || a.name.localeCompare(b.name));
                root.containers = out; root.error = ""; root.loaded = true; root.daemonDown = false;
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") { root.error = text.trim().split("\n")[0]; root.loaded = true } }
        onExited: code => {
            if (code !== 0) { root.daemonDown = true; root.containers = []; root.stats = ({}); root.loaded = true; root.selected = "" }
        }
    }
    Process {  // needs root: graphical polkit prompt
        id: stopProc
        command: ["pkexec", "systemctl", "stop", "docker.service", "docker.socket"]
        onExited: { root.refresh(); refreshSoon.restart() }
    }
    Process {  // needs root: graphical polkit prompt
        id: startProc
        command: ["pkexec", "systemctl", "start", "docker.socket", "docker.service"]
        onExited: { root.refresh(); refreshSoon.restart() }
    }
    Process {
        id: statsProc
        command: ["docker", "stats", "--no-stream", "--format", "{{json .}}"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = {};
                for (const l of text.split("\n")) {
                    if (!l.trim()) continue;
                    try { const j = JSON.parse(l); s[j.Name] = { cpu: j.CPUPerc, mem: j.MemUsage.split(" / ")[0], memPerc: j.MemPerc }; } catch (e) {}
                }
                root.stats = s;
            }
        }
    }
    Process {
        id: logProc
        // command is set in onSelectedChanged (a binding raced with `running` and passed an empty name)
        stdout: SplitParser {
            onRead: line => {
                if (root.paused) return;
                const clean = line.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
                const next = root.logLines.length >= 1000 ? root.logLines.slice(-800) : root.logLines.slice();
                next.push(clean);
                root.logLines = next;
            }
        }
    }

    // "0.0.0.0:18080->80/tcp, [::]:18080->80/tcp, 5432/tcp" -> unique [{host, container, proto, published}]
    function parsePorts(str) {
        const seen = {}, out = [];
        for (const part of str.split(",")) {
            const m = part.trim().match(/^(?:.*:)?(\d+(?:-\d+)?)->(\d+(?:-\d+)?)\/(\w+)$/);
            const u = part.trim().match(/^(\d+(?:-\d+)?)\/(\w+)$/);
            const e = m ? { host: m[1], container: m[2], proto: m[3], published: true }
                        : u ? { container: u[1], proto: u[2], published: false } : null;
            if (!e) continue;
            const k = `${e.host}|${e.container}|${e.proto}`;
            if (!seen[k]) { seen[k] = true; out.push(e); }
        }
        return out;
    }

    function stateColor(s) {
        if (s === "running") return "#4caf50";
        if (s === "paused" || s === "restarting") return "#ffb300";
        if (s === "exited" || s === "dead") return Appearance.colors.colSubtext;
        return Appearance.colors.colSubtext;
    }

    component IconBtn: RippleButton {
        id: ib
        property string symbol
        property string tip
        implicitWidth: 30; implicitHeight: 30
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: ib.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer2
        }
        StyledToolTip { text: ib.tip; visible: ib.hovered && ib.tip !== "" }
    }

    // Same geometry as the left sidebar: top/left/bottom anchored below the bar, hyprland outer gap around the card.
    // A click-away layer closes it (a click anywhere, including the bar button).
    PanelWindow {
        mask: Region { item: root.visible ? dismissArea : null }
        color: "transparent"
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:popup-dismiss"
        WlrLayershell.layer: WlrLayer.Top
        MouseArea { id: dismissArea; anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.visible = false }
    }
    PanelWindow {
        id: win
        color: "transparent"
        anchors { top: true; left: true; bottom: true }
        implicitWidth: 440 + Appearance.sizes.hyprlandGapsOut + Appearance.sizes.elevationMargin
        mask: Region { item: card }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:sidebarLeft"  // same Hyprland layer rule (slide left) as the left sidebar: native slide in/out
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        StyledRectangularShadow { target: card }

    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.topMargin: Appearance.sizes.hyprlandGapsOut
        anchors.leftMargin: Appearance.sizes.hyprlandGapsOut
        anchors.bottomMargin: Appearance.sizes.hyprlandGapsOut
        width: 440
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                IconBtn { visible: root.selected !== ""; symbol: "arrow_back"; tip: Translation.tr("Back"); onClicked: root.selected = "" }
                MaterialSymbol { visible: root.selected === ""; text: "deployed_code"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colOnLayer2 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.selected !== "" ? root.selected : Translation.tr("Docker")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.selected !== ""
                            ? (root.current ? `${root.current.image} · ${root.current.status}` : Translation.tr("Container removed"))
                            : root.daemonDown ? Translation.tr("Daemon stopped")
            : `${root.containers.length} ${Translation.tr("running")}`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
                // Log actions
                IconBtn {
                    visible: root.selected !== ""
                    symbol: root.paused ? "play_arrow" : "pause"
                    tip: root.paused ? Translation.tr("Resume stream") : Translation.tr("Pause stream")
                    onClicked: root.paused = !root.paused
                }
                IconBtn {
                    visible: root.selected !== ""
                    symbol: "content_copy"; tip: Translation.tr("Copy logs")
                    onClicked: Quickshell.clipboardText = root.logLines.join("\n")
                }
                IconBtn {
                    visible: root.selected !== ""
                    symbol: "delete_sweep"; tip: Translation.tr("Clear view")
                    onClicked: root.logLines = []
                }
                IconBtn {
                    visible: root.selected !== "" && root.current && root.current.state !== "running"
                    symbol: "play_circle"; tip: Translation.tr("Start"); onClicked: root.act("start")
                }
                IconBtn {
                    visible: root.selected !== "" && root.current && root.current.state === "running"
                    symbol: "stop_circle"; tip: Translation.tr("Stop"); onClicked: root.act("stop")
                }
                IconBtn {
                    visible: root.selected !== ""
                    symbol: "restart_alt"; tip: Translation.tr("Restart"); onClicked: root.act("restart")
                }
                IconBtn {
                    visible: root.selected === "" && !root.daemonDown
                    symbol: "power_settings_new"; tip: stopProc.running ? Translation.tr("Stopping…") : Translation.tr("Stop Docker")
                    enabled: !stopProc.running
                    onClicked: stopProc.running = true
                }
                IconBtn { visible: root.selected === ""; symbol: "refresh"; tip: Translation.tr("Refresh"); onClicked: root.refresh() }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }

            // Daemon not running
            Item {
              visible: root.daemonDown
              Layout.fillWidth: true
              Layout.fillHeight: true
              ColumnLayout {
                id: downCol
                anchors.centerIn: parent
                width: Math.min(parent.width - 32, 420)
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "power_off"
                    iconSize: 48
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Docker is not running")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: startProc.running ? Translation.tr("Starting the Docker service…") : Translation.tr("The Docker daemon isn't reachable, so containers can't be listed.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    implicitWidth: 140; implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    enabled: !startProc.running
                    onClicked: startProc.running = true
                    contentItem: RowLayout {
                        spacing: 6
                        Item { Layout.fillWidth: true }
                        MaterialSymbol { text: "play_arrow"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnPrimary }
                        StyledText { text: startProc.running ? Translation.tr("Starting…") : Translation.tr("Start Docker"); color: Appearance.colors.colOnPrimary }
                        Item { Layout.fillWidth: true }
                    }
                }
              }
            }

            // Container list
            ListView {
                id: list
                visible: root.selected === "" && !root.daemonDown
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: root.containers
                boundsBehavior: Flickable.StopAtBounds
                delegate: RippleButton {
                    id: rowBtn
                    required property var modelData
                    readonly property var st: root.stats[modelData.name]
                    readonly property bool up: modelData.state === "running"
                    width: list.width
                    implicitHeight: 58
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.selected = modelData.name
                    contentItem: RowLayout {
                        spacing: 10
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 4
                            implicitWidth: 10; implicitHeight: 10; radius: 5
                            color: root.stateColor(rowBtn.modelData.state)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text: rowBtn.modelData.name
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: `${rowBtn.modelData.image} · ${rowBtn.modelData.status}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                elide: Text.ElideRight
                                color: Appearance.colors.colSubtext
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: rowBtn.modelData.ports !== ""
                                Repeater {
                                    model: root.parsePorts(rowBtn.modelData.ports)
                                    delegate: Rectangle {
                                        required property var modelData
                                        implicitHeight: chip.implicitHeight + 4
                                        implicitWidth: chip.implicitWidth + 12
                                        radius: Appearance.rounding.full
                                        color: modelData.published ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                                        StyledText {
                                            id: chip
                                            anchors.centerIn: parent
                                            text: modelData.published ? `${modelData.host} → ${modelData.container}/${modelData.proto}` : `${modelData.container}/${modelData.proto}`
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.family: Appearance.font.family.monospace
                                            color: modelData.published ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                        }
                                    }
                                }
                            }
                        }
                        ColumnLayout {
                            visible: rowBtn.up && rowBtn.st !== undefined
                            Layout.rightMargin: 6
                            spacing: 1
                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: rowBtn.st ? `CPU ${rowBtn.st.cpu}` : ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: rowBtn.st ? `MEM ${rowBtn.st.mem}` : ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MaterialSymbol { text: "chevron_right"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colSubtext }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.loaded && root.containers.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colSubtext
                    text: root.error !== "" ? root.error : Translation.tr("No running containers")
                    width: parent.width - 40
                    wrapMode: Text.Wrap
                }
            }

            // Log view
            Rectangle {
                visible: root.selected !== ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer0
                clip: true

                ListView {
                    id: logView
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    model: root.logLines
                    boundsBehavior: Flickable.StopAtBounds
                    onCountChanged: if (root.follow) Qt.callLater(logView.positionViewAtEnd)
                    onMovementEnded: root.follow = logView.atYEnd
                    onFlickStarted: root.follow = false
                    delegate: Text {
                        required property string modelData
                        width: logView.width
                        text: modelData
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: /error|fatal|panic|exception/i.test(modelData) ? "#ef5350"
                             : /warn/i.test(modelData) ? "#ffb300" : Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: root.logLines.length === 0
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("No log output yet")
                    }
                }
                RippleButton {  // jump to the live tail when scrolled away
                    visible: !root.follow
                    anchors { right: parent.right; bottom: parent.bottom; margins: 10 }
                    implicitHeight: 30; implicitWidth: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    onClicked: { root.follow = true; logView.positionViewAtEnd() }
                    contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; text: "arrow_downward"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnPrimary }
                }
            }
        }
    }
    }
}
