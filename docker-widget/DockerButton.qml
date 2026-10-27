import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Quickshell.Hyprland

// Docker widget: bar button (running-container count, right-click Start/Stop Docker) + side panel with the container list,
// CPU/memory, ports and live logs (follow/pause, copy, start/stop/restart). Panel behavior (open/close, click-away,
// monitors) comes from WidgetBase; the panel content (and its polling) only exists while open.
WidgetBase {
    id: root
    iconName: "deployed_code"
    iconOpacity: available ? 1 : 0.4
    property int running: 0
    property bool available: true

    Process {
        id: countProc
        command: ["sh", "-c", "systemctl is-active --quiet docker.service && docker ps -q"]  // is-active first: polling must not wake the on-demand daemon
        stdout: StdioCollector {
            onStreamFinished: { root.available = true; root.running = text.trim() === "" ? 0 : text.trim().split("\n").length }
        }
        onExited: code => { if (code !== 0) { root.available = false; root.running = 0 } }
    }
    Timer { interval: 10000; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!countProc.running) countProc.running = true }

    Rectangle {  // running-container count, top-right corner like the mail/Teams badges (hidden at 0)
        visible: root.available && root.running > 0
        anchors { top: parent.top; right: parent.right; topMargin: 2; rightMargin: 0 }
        implicitWidth: Math.max(14, countText.implicitWidth + 8); implicitHeight: 14; radius: 7
        color: Appearance.colors.colPrimary
        StyledText {
            id: countText
            anchors.centerIn: parent
            text: root.running > 99 ? "99+" : root.running
            font.pixelSize: 9
            color: Appearance.colors.colOnPrimary
        }
    }

    // Right-click menu entry (WidgetBase places and closes the menu)
    menuContent: Component { RippleButton {
        implicitHeight: 36
        buttonRadius: Appearance.rounding.small
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        onClicked: {
            Quickshell.execDetached(root.available ? ["systemctl", "stop", "docker.service"] : ["sh", "-c", "systemctl start docker.socket; systemctl start docker.service"]);
            root.closeMenu();
        }
        contentItem: RowLayout {
            spacing: 8
            MaterialSymbol {
                text: root.available ? "power_settings_new" : "play_arrow"
                iconSize: Appearance.font.pixelSize.larger
                color: root.available ? "#ef5350" : Appearance.colors.colOnLayer2
            }
            StyledText {
                text: root.available ? Translation.tr("Stop Docker") : Translation.tr("Start Docker")
                color: Appearance.colors.colOnLayer2
            }
        }
    } }

    panelContent: Component { FocusScope {
        id: dk
        // Esc in the logs view goes back to the list; on the list it falls through to WidgetBase (close)
        Keys.onEscapePressed: event => {
            if (dk.selected !== "") dk.selected = "";
            else if (dk.query !== "") filterInput.text = "";
            else event.accepted = false;
        }
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

        // ---- list filter (like the Gist panel): words match name, image, status, ports, id; state chips; sort
        property string query: ""
        property string stateFilter: "all"   // all | running | stopped
        property string sortKey: "state"     // state | name | cpu | mem
        readonly property int runningCount: containers.filter(c => c.state === "running").length
        function memBytes(m) {
            const x = /^([\d.]+)\s*([kKMGT]?i?B)$/.exec((m ?? "").trim());
            if (!x) return 0;
            const u = { B: 1, kB: 1e3, KB: 1e3, KiB: 1024, MB: 1e6, MiB: 1048576, GB: 1e9, GiB: 1073741824, TB: 1e12, TiB: 1099511627776 };
            return parseFloat(x[1]) * (u[x[2]] ?? 1);
        }
        readonly property var visibleContainers: {
            const words = query.trim().toLowerCase().split(/\s+/).filter(w => w !== "");
            const out = containers.filter(c => {
                if (stateFilter === "running" && c.state !== "running") return false;
                if (stateFilter === "stopped" && c.state === "running") return false;
                const h = `${c.name} ${c.image} ${c.state} ${c.status} ${c.ports} ${c.id}`.toLowerCase();
                return words.every(w => h.includes(w));
            });
            const cpu = c => parseFloat(stats[c.name]?.cpu ?? "0") || 0, mem = c => memBytes(stats[c.name]?.mem);
            if (sortKey === "name") out.sort((a, b) => a.name.localeCompare(b.name));
            else if (sortKey === "cpu") out.sort((a, b) => cpu(b) - cpu(a) || a.name.localeCompare(b.name));
            else if (sortKey === "mem") out.sort((a, b) => mem(b) - mem(a) || a.name.localeCompare(b.name));
            else out.sort((a, b) => (b.state === "running") - (a.state === "running") || a.name.localeCompare(b.name));
            return out;
        }
        // remembered across opens
        readonly property string stateFile: `${Quickshell.env("HOME")}/.local/state/docker-widget.json`
        property bool stateReady: false
        function saveState() { if (stateReady) stateView.setText(JSON.stringify({ stateFilter, sortKey })) }
        onStateFilterChanged: saveState()
        onSortKeyChanged: saveState()
        FileView { id: stateView; path: dk.stateFile; blockLoading: true; atomicWrites: true; printErrors: false }

        Component.onCompleted: {
            try {
                const j = JSON.parse(stateView.text());
                if (["all", "running", "stopped"].includes(j.stateFilter)) stateFilter = j.stateFilter;
                if (["state", "name", "cpu", "mem"].includes(j.sortKey)) sortKey = j.sortKey;
            } catch (e) {}
            stateReady = true;
            refresh();
            Qt.callLater(() => filterInput.forceActiveFocus());   // type to filter right away
        }
        Component.onDestruction: { selected = ""; logProc.running = false }
        onSelectedChanged: {
            if (selected === "") Qt.callLater(() => filterInput.forceActiveFocus());
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
        Timer { id: refreshSoon; interval: 1200; onTriggered: dk.refresh() }
        Timer { interval: 3000; repeat: true; running: true; onTriggered: dk.refresh() }

        Process {
            id: psProc
            command: ["sh", "-c", "systemctl is-active --quiet docker.service && exec docker ps -a --format '{{json .}}'"]  // is-active first: must not wake the on-demand daemon
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
                    dk.containers = out; dk.error = ""; dk.loaded = true; dk.daemonDown = false;
                }
            }
            stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") { dk.error = text.trim().split("\n")[0]; dk.loaded = true } }
            onExited: code => {
                if (code !== 0) { dk.daemonDown = true; dk.containers = []; dk.stats = ({}); dk.loaded = true; dk.selected = "" }
            }
        }
        Process {  // needs root: graphical polkit prompt
            id: stopProc
            command: ["systemctl", "stop", "docker.service"]
            onExited: { dk.refresh(); refreshSoon.restart() }
        }
        Process {  // needs root: graphical polkit prompt
            id: startProc
            command: ["sh", "-c", "systemctl start docker.socket; systemctl start docker.service"]
            onExited: { dk.refresh(); refreshSoon.restart() }
        }
        Process {
            id: statsProc
            command: ["sh", "-c", "systemctl is-active --quiet docker.service && exec docker stats --no-stream --format '{{json .}}'"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const s = {};
                    for (const l of text.split("\n")) {
                        if (!l.trim()) continue;
                        try { const j = JSON.parse(l); s[j.Name] = { cpu: j.CPUPerc, mem: j.MemUsage.split(" / ")[0], memPerc: j.MemPerc }; } catch (e) {}
                    }
                    dk.stats = s;
                }
            }
        }
        Process {
            id: logProc
            // command is set in onSelectedChanged (a binding raced with `running` and passed an empty name)
            stdout: SplitParser {
                onRead: line => {
                    if (dk.paused) return;
                    const clean = line.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
                    const next = dk.logLines.length >= 1000 ? dk.logLines.slice(-800) : dk.logLines.slice();
                    next.push(clean);
                    dk.logLines = next;
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

        component Chip: RippleButton {
            id: chip
            property string label
            property bool active: false
            implicitHeight: 26
            implicitWidth: chipText.implicitWidth + 20
            buttonRadius: Appearance.rounding.full
            colBackground: active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
            colBackgroundHover: active ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
            contentItem: StyledText {
                id: chipText
                horizontalAlignment: Text.AlignHCenter
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: chip.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            }
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


        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                IconBtn { visible: dk.selected !== ""; symbol: "arrow_back"; tip: Translation.tr("Back"); onClicked: dk.selected = "" }
                MaterialSymbol { visible: dk.selected === ""; text: "deployed_code"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colOnLayer2 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: dk.selected !== "" ? dk.selected : Translation.tr("Docker")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: dk.selected !== ""
                            ? (dk.current ? `${dk.current.image} · ${dk.current.status}` : Translation.tr("Container removed"))
                            : dk.daemonDown ? Translation.tr("Daemon stopped")
            : `${dk.runningCount} ${Translation.tr("running")}` + (dk.containers.length > dk.runningCount ? ` · ${dk.containers.length - dk.runningCount} ${Translation.tr("stopped")}` : "")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
                // Log actions
                IconBtn {
                    visible: dk.selected !== ""
                    symbol: dk.paused ? "play_arrow" : "pause"
                    tip: dk.paused ? Translation.tr("Resume stream") : Translation.tr("Pause stream")
                    onClicked: dk.paused = !dk.paused
                }
                IconBtn {
                    visible: dk.selected !== ""
                    symbol: "content_copy"; tip: Translation.tr("Copy logs")
                    onClicked: Quickshell.clipboardText = dk.logLines.join("\n")
                }
                IconBtn {
                    visible: dk.selected !== ""
                    symbol: "delete_sweep"; tip: Translation.tr("Clear view")
                    onClicked: dk.logLines = []
                }
                IconBtn {
                    visible: dk.selected !== "" && dk.current && dk.current.state !== "running"
                    symbol: "play_circle"; tip: Translation.tr("Start"); onClicked: dk.act("start")
                }
                IconBtn {
                    visible: dk.selected !== "" && dk.current && dk.current.state === "running"
                    symbol: "stop_circle"; tip: Translation.tr("Stop"); onClicked: dk.act("stop")
                }
                IconBtn {
                    visible: dk.selected !== ""
                    symbol: "restart_alt"; tip: Translation.tr("Restart"); onClicked: dk.act("restart")
                }
                IconBtn {
                    visible: dk.selected === "" && !dk.daemonDown
                    symbol: "power_settings_new"; tip: stopProc.running ? Translation.tr("Stopping…") : Translation.tr("Stop Docker")
                    enabled: !stopProc.running
                    onClicked: stopProc.running = true
                }
                IconBtn { visible: dk.selected === ""; symbol: "refresh"; tip: Translation.tr("Refresh"); onClicked: dk.refresh() }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }

            // Daemon not running
            Item {
              visible: dk.daemonDown
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

            // Filter + state chips + sort (list only)
            Rectangle {
                visible: dk.selected === "" && !dk.daemonDown
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
                    spacing: 8
                    MaterialSymbol { text: "search"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colSubtext }
                    StyledTextInput {
                        id: filterInput
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        clip: true
                        onTextChanged: dk.query = text
                        Keys.onReturnPressed: if (dk.visibleContainers.length) dk.selected = dk.visibleContainers[0].name
                        Keys.onEnterPressed: if (dk.visibleContainers.length) dk.selected = dk.visibleContainers[0].name
                        StyledText {
                            visible: filterInput.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Filter by name, image, status or port…")
                            color: Appearance.colors.colSubtext
                        }
                    }
                    IconBtn { visible: filterInput.text !== ""; symbol: "close"; implicitWidth: 26; implicitHeight: 26; onClicked: filterInput.text = "" }
                }
            }
            RowLayout {
                visible: dk.selected === "" && !dk.daemonDown
                Layout.fillWidth: true
                spacing: 4
                Chip { label: `${Translation.tr("All")} ${dk.containers.length}`; active: dk.stateFilter === "all"; onClicked: dk.stateFilter = "all" }
                Chip { label: `${Translation.tr("Running")} ${dk.runningCount}`; active: dk.stateFilter === "running"; onClicked: dk.stateFilter = "running" }
                Chip { label: `${Translation.tr("Stopped")} ${dk.containers.length - dk.runningCount}`; active: dk.stateFilter === "stopped"; onClicked: dk.stateFilter = "stopped" }
                Item { Layout.fillWidth: true }
                RippleButton {
                    id: sortBtn
                    implicitHeight: 26
                    implicitWidth: sortRow.implicitWidth + 16
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: dk.sortKey = ({ state: "name", name: "cpu", cpu: "mem", mem: "state" })[dk.sortKey]
                    contentItem: RowLayout {
                        id: sortRow
                        spacing: 4
                        MaterialSymbol { text: "sort"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
                        StyledText {
                            text: ({ state: Translation.tr("Running first"), name: Translation.tr("Name"), cpu: Translation.tr("CPU"), mem: Translation.tr("Memory") })[dk.sortKey]
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledToolTip { text: Translation.tr("Change sort order"); visible: sortBtn.hovered }
                }
            }

            // Container list
            ListView {
                id: list
                visible: dk.selected === "" && !dk.daemonDown
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: dk.visibleContainers
                boundsBehavior: Flickable.StopAtBounds
                delegate: RippleButton {
                    id: rowBtn
                    required property var modelData
                    readonly property var st: dk.stats[modelData.name]
                    readonly property bool up: modelData.state === "running"
                    width: list.width
                    implicitHeight: 58
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: dk.selected = modelData.name
                    contentItem: RowLayout {
                        spacing: 10
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.leftMargin: 4
                            implicitWidth: 10; implicitHeight: 10; radius: 5
                            color: dk.stateColor(rowBtn.modelData.state)
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
                                    model: dk.parsePorts(rowBtn.modelData.ports)
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
                    visible: dk.loaded && dk.visibleContainers.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colSubtext
                    text: dk.error !== "" ? dk.error
                        : dk.containers.length === 0 ? Translation.tr("No containers")
                        : dk.query !== "" ? Translation.tr("No containers match")
                        : dk.stateFilter === "running" ? Translation.tr("No running containers") : Translation.tr("No stopped containers")
                    width: parent.width - 40
                    wrapMode: Text.Wrap
                }
            }

            // Log view
            Rectangle {
                visible: dk.selected !== ""
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
                    model: dk.logLines
                    boundsBehavior: Flickable.StopAtBounds
                    onCountChanged: if (dk.follow) Qt.callLater(logView.positionViewAtEnd)
                    onMovementEnded: dk.follow = logView.atYEnd
                    onFlickStarted: dk.follow = false
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
                        visible: dk.logLines.length === 0
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("No log output yet")
                    }
                }
                RippleButton {  // jump to the live tail when scrolled away
                    visible: !dk.follow
                    anchors { right: parent.right; bottom: parent.bottom; margins: 10 }
                    implicitHeight: 30; implicitWidth: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    onClicked: { dk.follow = true; logView.positionViewAtEnd() }
                    contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; text: "arrow_downward"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnPrimary }
                }
            }
        }
    } }
}
