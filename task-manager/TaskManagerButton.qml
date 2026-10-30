import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Task manager: bar button + side panel with process list (PID, CPU, RAM), filter field like the Search widget,
// right-click actions per row. Panel behavior (open/close, click-away, monitors) comes from WidgetBase; the panel content
// (and its `top` sampling every 2 s) only exists while open.
WidgetBase {
    id: root
    iconName: "memory"
    panelId: "task-manager"

    panelContent: Component { FocusScope {
        id: tm
        property var procs: []             // [{pid, user, cpu, mem, name}]
        property var apps: []              // [{pid, name, title, cpu, mem}] one per window-owning process tree
        property string query: ""
        property string sortKey: "name"    // name | pid | cpu | mem
        property bool sortAsc: true
        property bool appsOpen: true
        property bool procsOpen: true
        property real appsH: 220
        // Remembered across opens (and shell restarts): sort column/direction, section open state, divider position
        readonly property string stateFile: `${Quickshell.env("HOME")}/.local/state/task-manager.json`
        property bool stateReady: false
        function saveState() {
            if (!stateReady) return;
            stateView.setText(JSON.stringify({ sortKey, sortAsc, appsOpen, procsOpen, appsH }));
        }
        onSortKeyChanged: saveState()
        onSortAscChanged: saveState()
        onAppsOpenChanged: saveState()
        onProcsOpenChanged: saveState()
        onAppsHChanged: saveState()
        FileView {
            id: stateView
            path: tm.stateFile
            blockLoading: true
            atomicWrites: true
        }
        Component.onCompleted: {
            try {
                const j = JSON.parse(stateView.text());
                if (["name", "pid", "cpu", "mem"].includes(j.sortKey)) tm.sortKey = j.sortKey;
                if (typeof j.sortAsc === "boolean") tm.sortAsc = j.sortAsc;
                if (typeof j.appsOpen === "boolean") tm.appsOpen = j.appsOpen;
                if (typeof j.procsOpen === "boolean") tm.procsOpen = j.procsOpen;
                if (typeof j.appsH === "number") tm.appsH = j.appsH;
            } catch (e) {}
            tm.stateReady = true;
            sample();
        }
        function setSort(k) {
            if (sortKey === k) sortAsc = !sortAsc;
            else { sortKey = k; sortAsc = (k === "name" || k === "pid"); }
        }
        function sortAndFilter(arr) {
            const words = query.trim().toLowerCase().split(/\s+/).filter(w => w !== "");
            const out = arr.filter(p => {
                const hay = `${p.name} ${p.pid} ${p.user ?? ""} ${p.title ?? ""}`.toLowerCase();
                return words.every(w => hay.includes(w));
            });
            const k = sortKey, d = sortAsc ? 1 : -1;
            out.sort((a, b) => {
                let r;
                if (k === "name") r = a.name.localeCompare(b.name);
                else if (k === "pid") r = a.pid - b.pid;
                else if (k === "mem") r = a.mem - b.mem || a.cpu - b.cpu;
                else r = a.cpu - b.cpu || a.mem - b.mem;
                return r * d;
            });
            return out;
        }
        readonly property var filtered: sortAndFilter(procs)
        readonly property var filteredApps: sortAndFilter(apps)


        function sample() { if (!topProc.running) topProc.running = true }
        function fmtMem(kib) {
            if (kib >= 1048576) return (kib / 1048576).toFixed(1) + " GB";
            if (kib >= 1024) return Math.round(kib / 1024) + " MB";
            return kib + " KB";
        }
        function toKib(s) {  // top RES: plain KiB, or with m/g/t suffix
            const n = parseFloat(s), u = s.slice(-1);
            return u === "m" ? n * 1024 : u === "g" ? n * 1048576 : u === "t" ? n * 1073741824 : n;
        }

        property var menuItem: null
        property real menuX: 0
        property real menuY: 0
        function signal_(sig) {
            if (menuItem) Quickshell.execDetached(["kill", "-" + sig].concat((menuItem.pids ?? [menuItem.pid]).map(String)));
            menuItem = null;
            sampleSoon.restart();
        }
        Timer { id: sampleSoon; interval: 600; onTriggered: tm.sample() }
        Timer { interval: 2000; repeat: true; running: true; onTriggered: tm.sample() }

        Process {
            id: topProc
            // two iterations: the second one has real (instantaneous) CPU numbers
            command: ["bash", "-c", "top -b -n 2 -d 0.5 -w 256 -e k; echo ==PS==; ps -eo pid=,ppid=; echo ==HC==; hyprctl clients -j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const iPs = text.indexOf("==PS=="), iHc = text.indexOf("==HC==");
                    const topTxt = text.slice(0, iPs);
                    const i = topTxt.lastIndexOf("PID USER");
                    if (i < 0) return;
                    const out = [], byPid = {};
                    for (const l of topTxt.slice(i).split("\n").slice(1)) {
                        const f = l.trim().split(/\s+/);
                        if (f.length < 12) continue;
                        const o = { pid: parseInt(f[0]), user: f[1], mem: tm.toKib(f[5]), cpu: parseFloat(f[8]), name: f.slice(11).join(" ") };
                        out.push(o); byPid[o.pid] = o;
                    }
                    tm.procs = out;
                    // applications: windows' pids, CPU/RAM summed over each pid's process tree
                    const kids = {};
                    for (const l of text.slice(iPs + 6, iHc).split("\n")) {
                        const f = l.trim().split(/\s+/);
                        if (f.length === 2) (kids[f[1]] = kids[f[1]] ?? []).push(parseInt(f[0]));
                    }
                    const sum = (pid, acc) => {
                        const o = byPid[pid];
                        if (o) { acc.cpu += o.cpu; acc.mem += o.mem; }
                        for (const c of kids[pid] ?? []) sum(c, acc);
                    };
                    let clients = [];
                    try { clients = JSON.parse(text.slice(iHc + 6)); } catch (e) {}
                    const byName = {}, appList = [];
                    for (const c of clients) {
                        if (!c.mapped || c.pid <= 0) continue;
                        const cls = c.class || c.title;
                        const de = DesktopEntries.heuristicLookup(cls);
                        let name = de?.name ?? "";
                        if (name === "") {
                            const last = cls.split(".").pop().replace(/[-_]/g, " ");
                            name = last.charAt(0).toUpperCase() + last.slice(1);
                        }
                        let a = byName[name];
                        if (!a) { a = byName[name] = { pid: c.pid, pids: [], name: name, title: c.title, cpu: 0, mem: 0, seen: {} }; appList.push(a); }
                        if (a.seen[c.pid]) continue;
                        a.seen[c.pid] = true; a.pids.push(c.pid);
                        const acc = { cpu: 0, mem: 0 };
                        sum(c.pid, acc);
                        a.cpu += acc.cpu; a.mem += acc.mem;
                    }
                    tm.apps = appList;
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    spacing: 8
                    MaterialSymbol { text: "search"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colSubtext }
                    StyledTextInput {
                        id: input
                        focus: true
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        clip: true
                        onTextChanged: tm.query = text
                        Keys.onEscapePressed: { if (tm.menuItem) tm.menuItem = null; else root.close() }
                        StyledText {
                            visible: input.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Filter by name, PID or user…")
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // Section header (collapsible) + sortable column headers
            component SectionHeader: RowLayout {
                id: sh
                property string title
                property bool open
                property int count
                signal toggled()
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 10
                spacing: 8
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: sh.toggled()
                    contentItem: RowLayout {
                        spacing: 6
                        MaterialSymbol { text: sh.open ? "expand_more" : "chevron_right"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colSubtext }
                        StyledText { text: `${sh.title} (${sh.count})`; font.weight: Font.Medium; color: Appearance.colors.colOnLayer2 }
                        Item { Layout.fillWidth: true }
                    }
                }
            }
            component SortHead: RippleButton {
                id: sk
                property string key
                property string label
                property bool alignLeft: false
                implicitHeight: 26
                implicitWidth: contentItem.implicitWidth + 16
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: tm.setSort(key)
                contentItem: RowLayout {
                    spacing: 2
                    Item { Layout.fillWidth: !sk.alignLeft; visible: !sk.alignLeft }
                    StyledText { text: sk.label; font.pixelSize: Appearance.font.pixelSize.smaller; color: tm.sortKey === sk.key ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                    MaterialSymbol {
                        visible: tm.sortKey === sk.key
                        text: tm.sortAsc ? "arrow_upward" : "arrow_downward"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colPrimary
                    }
                    Item { Layout.fillWidth: sk.alignLeft; visible: sk.alignLeft }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                spacing: 4
                SortHead { key: "name"; label: Translation.tr("Name"); alignLeft: true }
                Item { Layout.fillWidth: true }
                SortHead { Layout.preferredWidth: 64; key: "pid"; label: "PID" }
                SortHead { Layout.preferredWidth: 60; key: "cpu"; label: "CPU" }
                SortHead { Layout.preferredWidth: 76; key: "mem"; label: "RAM" }
            }

            component ProcList: StyledListView {
                id: pl
                property var rows: []
                animateAppearance: false
                Layout.fillWidth: true
                clip: true
                spacing: 2
                model: rows
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: pl.width
                    implicitHeight: 34
                    radius: Appearance.rounding.small
                    color: hover.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                    HoverHandler { id: hover }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: mouse => {
                            const p = mapToItem(tm, mouse.x, mouse.y);
                            tm.menuX = p.x; tm.menuY = p.y; tm.menuItem = row.modelData;
                        }
                    }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 4
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.preferredWidth: 64
                            text: row.modelData.pid
                            horizontalAlignment: Text.AlignRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.preferredWidth: 60
                            text: row.modelData.cpu.toFixed(1) + "%"
                            horizontalAlignment: Text.AlignRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: row.modelData.cpu >= 50 ? "#ef5350" : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.preferredWidth: 76
                            text: tm.fmtMem(row.modelData.mem)
                            horizontalAlignment: Text.AlignRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }

            // Applications
            SectionHeader { title: Translation.tr("Applications"); open: tm.appsOpen; count: tm.filteredApps.length; onToggled: tm.appsOpen = !tm.appsOpen }
            ProcList {
                visible: tm.appsOpen
                Layout.fillHeight: !tm.procsOpen
                Layout.preferredHeight: tm.appsOpen ? tm.appsH : 0
                rows: tm.filteredApps
            }

            // Slider between the two sections: drag to resize
            Rectangle {
                visible: tm.appsOpen && tm.procsOpen
                Layout.fillWidth: true
                Layout.preferredHeight: 10
                color: "transparent"
                Rectangle { anchors.centerIn: parent; width: 48; height: 4; radius: 2; color: dragArea.pressed || dragArea.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.SplitVCursor
                    property real startY: 0
                    property real startH: 0
                    onPressed: mouse => { startY = mapToItem(tm, 0, mouse.y).y; startH = tm.appsH }
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        const dy = mapToItem(tm, 0, mouse.y).y - startY;
                        tm.appsH = Math.max(40, Math.min(tm.height - 260, startH + dy));
                    }
                }
            }

            // Processes
            SectionHeader { title: Translation.tr("Processes"); open: tm.procsOpen; count: tm.filtered.length; onToggled: tm.procsOpen = !tm.procsOpen }
            ProcList {
                visible: tm.procsOpen
                Layout.fillHeight: true
                rows: tm.filtered
            }
            Item { visible: !tm.procsOpen; Layout.fillHeight: !tm.appsOpen }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Click a header to sort · right-click a row for actions")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Right-click menu (overlay inside the card)
        MouseArea {
            anchors.fill: parent
            visible: tm.menuItem !== null
            acceptedButtons: Qt.AllButtons
            onPressed: tm.menuItem = null
        }
        Rectangle {
            id: ctx
            visible: tm.menuItem !== null
            x: Math.max(8, Math.min(tm.menuX, tm.width - width - 8))
            y: Math.max(8, Math.min(tm.menuY, tm.height - height - 8))
            width: 210
            implicitHeight: ctxCol.implicitHeight + 12
            height: implicitHeight
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            ColumnLayout {
                id: ctxCol
                anchors { fill: parent; margins: 6 }
                spacing: 2
                StyledText {
                    Layout.leftMargin: 8
                    Layout.topMargin: 2
                    Layout.fillWidth: true
                    text: tm.menuItem ? `${tm.menuItem.name} · ${tm.menuItem.pid}` : ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: [
                        { icon: "stop_circle", label: Translation.tr("Stop (end task)"), act: "TERM", danger: false },
                        { icon: "dangerous", label: Translation.tr("Force kill"), act: "KILL", danger: true },
                        { icon: "pause_circle", label: Translation.tr("Pause"), act: "STOP", danger: false },
                        { icon: "play_circle", label: Translation.tr("Resume"), act: "CONT", danger: false },
                        { icon: "content_copy", label: Translation.tr("Copy PID"), act: "COPY", danger: false },
                    ]
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            if (modelData.act === "COPY") {
                                Quickshell.execDetached(["wl-copy", String(tm.menuItem.pid)]);
                                tm.menuItem = null;
                            } else tm.signal_(modelData.act);
                        }
                        contentItem: RowLayout {
                            spacing: 10
                            MaterialSymbol { Layout.leftMargin: 4; text: modelData.icon; iconSize: Appearance.font.pixelSize.larger; color: modelData.danger ? "#ef5350" : Appearance.colors.colSubtext }
                            StyledText { Layout.fillWidth: true; text: modelData.label; color: modelData.danger ? "#ef5350" : Appearance.colors.colOnLayer2 }
                        }
                    }
                }
            }
        }
    } }
}
