import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// File search (Everything-style): type to filter an fd file index with `fzf --filter` (fuzzy, ranked).
// Enter / click opens, Ctrl+Enter or the folder button reveals the folder, Up/Down move, Esc closes.
// The index is cached per scope in $XDG_RUNTIME_DIR and rebuilt when older than 2 minutes.
// Panel behavior (open/close, click-away, monitors) comes from WidgetBase; everything below only exists while open.
WidgetBase {
    id: root
    iconName: "manage_search"
    iconSize: 22

    panelContent: Component { FocusScope {
        id: fs
        Binding { target: root; property: "panelWidth"; value: fs.cardW }   // the card is resizable (right-edge grip)
        property string query: ""
        property string scope: "home"          // "home" | "root"
        property var results: []               // [{kind, size, mtime, path}]
        property bool indexing: false
        property bool searching: false
        property int current: 0
        property string sortKey: "name"   // relevance | name | type | size | date
        property string sortDir: ""            // "" = default order for the key | "asc" | "desc"
        // Effective direction: explicit choice, else the key's natural default (name/type A→Z, size/date big/new first)
        readonly property bool sortAsc: sortDir !== "" ? sortDir === "asc" : (sortKey === "relevance" || sortKey === "name" || sortKey === "type")
        property bool sortMenuOpen: false
        property bool helpOpen: false
        property string typeFilter: "all"      // all | dir | file
        property bool matchCase: false
        property bool matchPath: false
        property bool filterOpen: false
        property real filterX: 0
        property real filterY: 0
        property real cardW: 440
        property real sizeW: 64
        property real dateW: 100
        property real sortMenuX: 0
        property real sortMenuY: 0
        readonly property var sortDefs: [
            { key: "relevance", label: Translation.tr("Best match"), icon: "auto_awesome" },
            { key: "name", label: Translation.tr("Name"), icon: "sort_by_alpha" },
            { key: "type", label: Translation.tr("Type"), icon: "folder" },
            { key: "size", label: Translation.tr("Size"), icon: "straighten" },
            { key: "date", label: Translation.tr("Date"), icon: "schedule" },
        ]
        readonly property string sortLabel: sortDefs.find(d => d.key === sortKey).label
        readonly property var sortedResults: {
            const r = typeFilter === "all" ? results.slice() : results.filter(x => x.kind === typeFilter);
            if (sortKey === "relevance") return sortDir === "desc" ? r.reverse() : r;
            const nm = x => x.path.split("/").pop().toLowerCase();
            const dirFirst = x => x.kind === "dir" ? 0 : 1;
            const cmp = {
                name: (a, b) => nm(a).localeCompare(nm(b), undefined, { numeric: true }),
                type: (a, b) => dirFirst(a) - dirFirst(b) || nm(a).localeCompare(nm(b), undefined, { numeric: true }),
                size: (a, b) => (a.kind === "dir" ? -1 : a.size) - (b.kind === "dir" ? -1 : b.size),
                date: (a, b) => a.mtime - b.mtime,
            }[sortKey];
            r.sort((a, b) => sortAsc ? cmp(a, b) : cmp(b, a));
            return r;
        }
        function setSort(k) {
            if (sortKey === k) sortDir = sortAsc ? "desc" : "asc";
            else { sortKey = k; sortDir = ""; }
            current = 0;
        }
        readonly property string home: Quickshell.env("HOME")
        readonly property string idxFile: `${Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp"}/file-search2-${scope}.idx`

        // Remembered across opens (and shell restarts): sort key/direction, Home/System scope and the search text (selected on open)
        readonly property string stateFile: `${Quickshell.env("HOME")}/.local/state/file-search.json`
        property bool stateReady: false
        function saveState() {
            if (stateReady) stateView.setText(JSON.stringify({ sortKey, sortDir, scope, query, cardW, typeFilter, matchCase, matchPath }));
        }
        onSortKeyChanged: saveState()
        onSortDirChanged: saveState()
        onCardWChanged: saveState()
        onTypeFilterChanged: { current = 0; saveState() }
        onMatchCaseChanged: { saveState(); debounce.restart() }
        onMatchPathChanged: { saveState(); debounce.restart() }
        onQueryChanged: saveState()
        FileView { id: stateView; path: fs.stateFile; blockLoading: true; atomicWrites: true }
        Component.onCompleted: {
            try {
                const j = JSON.parse(stateView.text());
                if (sortDefs.some(d => d.key === j.sortKey)) fs.sortKey = j.sortKey;
                if (["", "asc", "desc"].includes(j.sortDir)) fs.sortDir = j.sortDir;
                if (typeof j.cardW === "number") fs.cardW = Math.max(340, Math.min(900, j.cardW));
                if (["all", "dir", "file"].includes(j.typeFilter)) fs.typeFilter = j.typeFilter;
                if (typeof j.matchCase === "boolean") fs.matchCase = j.matchCase;
                if (typeof j.matchPath === "boolean") fs.matchPath = j.matchPath;
                if (j.scope === "home" || j.scope === "root") fs.scope = j.scope;
                if (typeof j.query === "string" && j.query !== "") { input.text = j.query; input.selectAll(); }
            } catch (e) {}
            fs.stateReady = true;
            buildIndex();
        }
        Component.onDestruction: { indexProc.running = false; searchProc.running = false }
        onScopeChanged: { saveState(); results = []; buildIndex(); }

        function buildIndex() {
            if (indexProc.running) return;
            fs.indexing = true;
            // Rebuild only if missing or older than 2 minutes; excludes caches and VCS/build dirs.
            indexProc.command = ["bash", "-c",
                'idx="$1"; base="$2"; ' +
                'if [ -s "$idx" ] && [ $(( $(date +%s) - $(stat -c %Y "$idx") )) -lt 120 ]; then exit 0; fi; ' +
                'fd --hidden --follow --type f --type d --absolute-path ' +
                '--exclude .git --exclude node_modules --exclude .cache --exclude .cargo --exclude .rustup ' +
                '--exclude __pycache__ --exclude proc --exclude sys --exclude dev --exclude run ' +
                '. "$base" 2>/dev/null | awk -F/ \'{n=$NF; if(n=="")n=$(NF-1); print n"\\t"$0}\' > "$idx.tmp"; mv -f "$idx.tmp" "$idx"',
                "_", idxFile, scope === "home" ? home : "/"];
            indexProc.running = true;
        }
        function search() {
            searchProc.running = false;
            const q = query.trim();
            if (q === "") { results = []; searching = false; return; }
            searching = true;
            searchProc.command = ["bash", "-c",
                '[ -s "$1" ] || exit 0; ' +
                // Like Everything: match the file name only, unless the query contains "/" (then match the whole path)
                'if [[ "$2" == */* || "$4" == 1 ]]; then nth="1,2"; else nth="1"; fi; ' +
                'fzf --exact $3 --filter "$2" --delimiter $\'\\t\' --nth "$nth" --tiebreak=length,index < "$1" 2>/dev/null | head -1500 | cut -f2- | ' +
                'xargs -d "\\n" -r stat --printf "%F\\t%s\\t%Y\\t%n\\n" 2>/dev/null',
                "_", idxFile, q, matchCase ? "+i" : "-i", matchPath ? "1" : "0"];
            searchProc.running = true;
        }
        function openPath(p) { Quickshell.execDetached(["xdg-open", p]); root.close() }
        function parentOf(p) { return p.replace(/\/[^\/]*$/, "") || "/" }
        function revealPath(item) {
            Quickshell.execDetached(["dolphin", "--select", item.path]); root.close();
        }
        property var menuItem: null
        property real menuX: 0
        property real menuY: 0
        function showMenu(item, pos) { menuItem = item; menuX = pos.x; menuY = pos.y }
        readonly property var menuEntries: {
            const it = menuItem; if (!it) return [];
            const dir = it.kind === "dir" ? it.path : parentOf(it.path);
            return [
                { icon: "open_in_new", label: Translation.tr("Open"), run: () => openPath(it.path) },
                { icon: "folder_open", label: Translation.tr("Open path (show in folder)"), run: () => revealPath(it) },
                { icon: "terminal", label: Translation.tr("Open terminal here"), run: () => { Quickshell.execDetached(["kitty", "--directory", dir]); root.close() } },
                { icon: "code", label: Translation.tr("Open in VS Code"), run: () => { Quickshell.execDetached(["code", it.path]); root.close() } },
                { sep: true },
                { icon: "content_copy", label: Translation.tr("Copy full path"), run: () => Quickshell.clipboardText = it.path },
                { icon: "drive_file_rename_outline", label: Translation.tr("Copy name"), run: () => Quickshell.clipboardText = it.path.split("/").pop() },
                { icon: "folder_copy", label: Translation.tr("Copy parent path"), run: () => Quickshell.clipboardText = parentOf(it.path) },
                { sep: true },
                { icon: "delete", label: Translation.tr("Move to trash"), danger: true, run: () => {
                    Quickshell.execDetached(["gio", "trash", it.path]);
                    fs.results = fs.results.filter(r => r.path !== it.path);
                    fs.current = Math.min(fs.current, Math.max(0, fs.results.length - 1));
                } },
            ];
        }
        function fmtSize(b) {
            if (b < 1024) return `${b} B`;
            const u = ["KB", "MB", "GB", "TB"]; let i = -1, v = b;
            do { v /= 1024; i++ } while (v >= 1024 && i < u.length - 1);
            return `${v.toFixed(v < 10 ? 1 : 0)} ${u[i]}`;
        }
        function fmtDate(s) {
            return Qt.formatDateTime(new Date(s * 1000), "yy-MM-dd HH:mm");
        }
        function iconFor(item) {
            if (item.kind === "dir") return "folder";
            const ext = (item.path.split(".").pop() || "").toLowerCase();
            if (["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp"].includes(ext)) return "image";
            if (["mp4", "mkv", "webm", "mov", "avi"].includes(ext)) return "movie";
            if (["mp3", "flac", "wav", "ogg", "m4a", "opus"].includes(ext)) return "music_note";
            if (["zip", "tar", "gz", "xz", "7z", "rar", "zst"].includes(ext)) return "folder_zip";
            if (ext === "pdf") return "picture_as_pdf";
            if (["sh", "py", "js", "ts", "qml", "lua", "rs", "go", "c", "cpp", "h", "json", "toml", "yaml", "yml"].includes(ext)) return "code";
            return "description";
        }
        function prettyPath(p) { return p.startsWith(home) ? "~" + p.slice(home.length) : p }

        Timer { id: debounce; interval: 120; onTriggered: fs.search() }
        Process {
            id: indexProc
            onExited: { fs.indexing = false; if (fs.query.trim() !== "") fs.search() }
        }
        Process {
            id: searchProc
            stdout: StdioCollector {
                onStreamFinished: {
                    const out = [];
                    for (const l of text.split("\n")) {
                        if (!l) continue;
                        const p = l.split("\t");
                        if (p.length < 4) continue;
                        out.push({ kind: p[0] === "directory" ? "dir" : "file", size: Number(p[1]), mtime: Number(p[2]), path: p.slice(3).join("\t").replace(/(.)\/+$/, "$1") });
                    }
                    fs.results = out; fs.current = 0; fs.searching = false;
                }
            }
        }


        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Search field + scope toggle
            RowLayout {
                Layout.fillWidth: true
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
                            onTextChanged: { fs.query = text; debounce.restart() }
                            Keys.onEscapePressed: { if (fs.menuItem) fs.menuItem = null; else if (fs.filterOpen) fs.filterOpen = false; else if (fs.helpOpen) fs.helpOpen = false; else if (fs.sortMenuOpen) fs.sortMenuOpen = false; else root.close() }
                            Keys.onDownPressed: fs.current = Math.min(fs.current + 1, fs.sortedResults.length - 1)
                            Keys.onUpPressed: fs.current = Math.max(fs.current - 1, 0)
                            Keys.onReturnPressed: event => {
                                const it = fs.sortedResults[fs.current];
                                if (!it) return;
                                if (event.modifiers & Qt.ControlModifier) fs.revealPath(it); else fs.openPath(it.path);
                            }
                            StyledText {
                                visible: input.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: Translation.tr("Search files and folders…")
                                color: Appearance.colors.colSubtext
                            }
                        }
                        RippleButton {
                            implicitWidth: 28; implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            colBackground: fs.helpOpen ? Appearance.colors.colSecondaryContainer : "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: { fs.helpOpen = !fs.helpOpen; input.forceActiveFocus() }
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "help"
                                iconSize: Appearance.font.pixelSize.larger
                                color: fs.helpOpen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                            }
                            StyledToolTip { text: Translation.tr("Search tips"); visible: parent.hovered }
                        }
                        MaterialSymbol {
                            visible: fs.indexing || fs.searching
                            text: "progress_activity"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                            RotationAnimator on rotation { running: parent.visible; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                    }
                }
                RippleButton {
                    id: filterBtn
                    readonly property bool active: fs.typeFilter !== "all" || fs.matchCase || fs.matchPath
                    implicitWidth: 40; implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        const p = mapToItem(fs, width, height + 4);
                        fs.filterX = p.x; fs.filterY = p.y; fs.filterOpen = !fs.filterOpen;
                        input.forceActiveFocus();
                    }
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "filter_list"
                        iconSize: Appearance.font.pixelSize.larger
                        color: filterBtn.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    }
                    StyledToolTip { text: Translation.tr("Filters"); visible: filterBtn.hovered }
                }
                RippleButton {
                    implicitHeight: 40; implicitWidth: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: { fs.scope = fs.scope === "home" ? "root" : "home"; input.forceActiveFocus() }
                    contentItem: RowLayout {
                        id: scopeRow
                        spacing: 6
                        MaterialSymbol { text: fs.scope === "home" ? "home" : "computer"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer2 }
                    }
                    StyledToolTip { text: fs.scope === "home" ? Translation.tr("Searching home: click for whole system") : Translation.tr("Searching whole system: click for home"); visible: parent.hovered }
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
                onClicked: { fs.setSort(key); input.forceActiveFocus() }
                contentItem: RowLayout {
                    spacing: 2
                    Item { Layout.fillWidth: !sk.alignLeft; visible: !sk.alignLeft }
                    StyledText { text: sk.label; font.pixelSize: Appearance.font.pixelSize.smaller; color: fs.sortKey === sk.key ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                    MaterialSymbol {
                        visible: fs.sortKey === sk.key
                        text: fs.sortAsc ? "arrow_upward" : "arrow_downward"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colPrimary
                    }
                    Item { Layout.fillWidth: sk.alignLeft; visible: sk.alignLeft }
                }
            }
            // Column grip sits in the 4 px gap between columns (rows use the same 4 px spacing); drag left to widen the column on its right
            component ColGrip: Item {
                id: gr
                property real startX: 0
                property real startW: 0
                property real value
                property real minW: 44
                signal resized(real w)
                Layout.preferredWidth: 4
                Layout.preferredHeight: 28
                Rectangle {
                    anchors.centerIn: parent
                    width: 2; radius: 1
                    height: gripArea.pressed || gripArea.containsMouse ? 18 : 12
                    color: gripArea.pressed || gripArea.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    Behavior on height { NumberAnimation { duration: 100 } }
                }
                MouseArea {
                    id: gripArea
                    anchors { fill: parent; leftMargin: -5; rightMargin: -5 }
                    hoverEnabled: true
                    cursorShape: Qt.SplitHCursor
                    onPressed: mouse => { gr.startX = mapToItem(fs, mouse.x, 0).x; gr.startW = gr.value }
                    onPositionChanged: mouse => {
                        if (pressed) gr.resized(Math.max(gr.minW, Math.min(220, gr.startW + gr.startX - mapToItem(fs, mouse.x, 0).x)));
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.fillHeight: false
                Layout.preferredHeight: 28
                spacing: 0
                SortHead { Layout.fillWidth: true; key: "name"; label: Translation.tr("Name"); alignLeft: true }
                ColGrip { value: fs.sizeW; onResized: w => fs.sizeW = w }
                SortHead { Layout.preferredWidth: fs.sizeW; key: "size"; label: Translation.tr("Size") }
                ColGrip { value: fs.dateW; minW: 80; onResized: w => fs.dateW = w }
                SortHead { Layout.preferredWidth: fs.dateW; key: "date"; label: Translation.tr("Modified") }
            }

            // Results
            StyledListView {
                id: list
                animateAppearance: false
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: fs.sortedResults
                currentIndex: fs.current
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: RippleButton {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === fs.current
                    width: list.width
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.small
                    colBackground: sel ? Appearance.colors.colSecondaryContainer : "transparent"
                    colBackgroundHover: sel ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2Hover
                    onClicked: fs.openPath(modelData.path)
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: mouse => {
                            fs.current = row.index;
                            const p = mapToItem(fs, mouse.x, mouse.y);
                            fs.showMenu(row.modelData, p);
                        }
                    }
                    contentItem: RowLayout {
                        spacing: 4
                        MaterialSymbol {
                            Layout.leftMargin: 2
                            text: fs.iconFor(row.modelData)
                            iconSize: Appearance.font.pixelSize.larger
                            color: row.modelData.kind === "dir" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer2
                            textFormat: Text.StyledText
                            text: `${row.modelData.path.split("/").pop().replace(/&/g, "&amp;").replace(/</g, "&lt;") || "/"}  <font color="${Appearance.colors.colSubtext}">${fs.prettyPath(fs.parentOf(row.modelData.path)).replace(/&/g, "&amp;").replace(/</g, "&lt;")}</font>`
                        }
                        StyledText {
                            Layout.preferredWidth: fs.sizeW
                            text: row.modelData.kind === "dir" ? "" : fs.fmtSize(row.modelData.size)
                            horizontalAlignment: Text.AlignRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.preferredWidth: fs.dateW
                            text: fs.fmtDate(row.modelData.mtime)
                            horizontalAlignment: Text.AlignRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // Empty / loading / no-match states
                ColumnLayout {
                    id: emptyState
                    anchors.centerIn: parent
                    visible: fs.sortedResults.length === 0
                    width: parent.width - 48
                    spacing: 6
                    readonly property bool idle: fs.query.trim() === ""
                    readonly property bool busy: !idle && (fs.indexing || fs.searching)
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 72; implicitHeight: 72; radius: 36
                        color: Appearance.colors.colSecondaryContainer
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: emptyState.idle ? "manage_search" : emptyState.busy ? "hourglass_top" : "search_off"
                            iconSize: 36
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                    StyledText {
                        visible: !emptyState.idle
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 8
                        text: emptyState.busy ? (fs.indexing ? Translation.tr("Indexing files…") : Translation.tr("Searching…"))
                            : Translation.tr("No results")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: emptyState.idle ? Translation.tr("Type a name or part of a path")
                            : emptyState.busy ? ""
                            : fs.scope === "home"
                                ? Translation.tr("Try different words, or search the whole system")
                                : Translation.tr("Try different words")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    RippleButton {
                        visible: emptyState.idle
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 10
                        implicitHeight: 32
                        implicitWidth: tipsRow.implicitWidth + 24
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: fs.helpOpen = true
                        contentItem: RowLayout {
                            id: tipsRow
                            spacing: 6
                            MaterialSymbol { text: "lightbulb"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colPrimary }
                            StyledText { text: Translation.tr("Search tips"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer2 }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: (fs.sortedResults.length > 0 ? Translation.tr("%1 results · ").arg(fs.sortedResults.length) : "") + Translation.tr("Enter open · Ctrl+Enter show in folder · right-click menu")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Search tips overlay (explains what can be typed into the field)
        MouseArea {
            anchors.fill: parent
            visible: fs.helpOpen
            onPressed: fs.helpOpen = false
        }
        Rectangle {
            visible: fs.helpOpen
            x: 12
            y: 60
            width: fs.width - 24
            implicitHeight: tipsCol.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            ColumnLayout {
                id: tipsCol
                anchors { fill: parent; margins: 10 }
                spacing: 2
                StyledText {
                    Layout.leftMargin: 6
                    Layout.bottomMargin: 4
                    text: Translation.tr("Search tips")
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                }
                Repeater {
                    model: [
                        { icon: "match_case", ex: "cfgnv", d: Translation.tr("Fuzzy: letters in order (config/nvim.lua)"), ins: "" },
                        { icon: "join_inner", ex: "foo bar", d: Translation.tr("Both words must match"), ins: "" },
                        { icon: "call_split", ex: "foo | bar", d: Translation.tr("Either word"), ins: " | " },
                        { icon: "format_quote", ex: "'foo", d: Translation.tr("Exact match, no fuzziness"), ins: "'" },
                        { icon: "start", ex: "^foo", d: Translation.tr("Starts with"), ins: "^" },
                        { icon: "keyboard_tab", ex: "foo$", d: Translation.tr("Ends with (e.g. .png$)"), ins: "$" },
                        { icon: "block", ex: "!foo", d: Translation.tr("Exclude matches"), ins: " !" },
                    ]
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            if (modelData.ins !== "") { input.text = input.text + modelData.ins; input.cursorPosition = input.text.length; }
                            fs.helpOpen = false; input.forceActiveFocus();
                        }
                        contentItem: RowLayout {
                            spacing: 10
                            MaterialSymbol { Layout.leftMargin: 4; text: modelData.icon; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colSubtext }
                            StyledText {
                                Layout.preferredWidth: 78
                                text: modelData.ex
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.d
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }
                }
            }
        }

        // Sort menu (overlay inside the card)
        MouseArea {
            anchors.fill: parent
            visible: fs.sortMenuOpen
            onPressed: fs.sortMenuOpen = false
        }
        Rectangle {
            visible: fs.sortMenuOpen
            x: Math.max(8, Math.min(fs.sortMenuX, fs.width - width - 8))
            y: fs.sortMenuY
            implicitWidth: 200
            implicitHeight: sortCol.implicitHeight + 12
            radius: Appearance.rounding.small
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            ColumnLayout {
                id: sortCol
                anchors { fill: parent; margins: 6 }
                spacing: 0
                Repeater {
                    model: fs.sortDefs
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: { fs.sortKey = modelData.key; fs.sortDir = ""; fs.current = 0; fs.sortMenuOpen = false }
                        contentItem: RowLayout {
                            spacing: 10
                            MaterialSymbol { Layout.leftMargin: 4; text: modelData.icon; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer2 }
                            StyledText { Layout.fillWidth: true; text: modelData.label; color: Appearance.colors.colOnLayer2 }
                            MaterialSymbol { visible: fs.sortKey === modelData.key; text: "check"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colPrimary }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border; opacity: 0.6 }
                Repeater {
                    model: [
                        { dir: "asc", label: Translation.tr("Ascending"), icon: "arrow_upward" },
                        { dir: "desc", label: Translation.tr("Descending"), icon: "arrow_downward" },
                    ]
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: { fs.sortDir = fs.sortDir === modelData.dir ? "" : modelData.dir; fs.current = 0; fs.sortMenuOpen = false }
                        contentItem: RowLayout {
                            spacing: 10
                            MaterialSymbol { Layout.leftMargin: 4; text: modelData.icon; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer2 }
                            StyledText { Layout.fillWidth: true; text: modelData.label; color: Appearance.colors.colOnLayer2 }
                            MaterialSymbol { visible: fs.sortDir === modelData.dir; text: "check"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colPrimary }
                        }
                    }
                }
            }
        }

        // Drag the right edge to resize the widget width
        MouseArea {
            id: widthGrip
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: 8
            hoverEnabled: true
            cursorShape: Qt.SplitHCursor
            property real pressX: 0
            onPressed: mouse => pressX = mouse.x
            onPositionChanged: mouse => {
                if (pressed) fs.cardW = Math.max(340, Math.min(900, mapToItem(fs, mouse.x, 0).x + width - pressX));
            }
            Rectangle {
                anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
                width: 3; height: 40; radius: 1.5
                opacity: widthGrip.pressed || widthGrip.containsMouse ? 1 : 0
                color: Appearance.colors.colPrimary
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }

        // Filter menu (overlay inside the card)
        MouseArea {
            anchors.fill: parent
            visible: fs.filterOpen
            onPressed: fs.filterOpen = false
        }
        Rectangle {
            visible: fs.filterOpen
            x: Math.max(8, Math.min(fs.filterX - width, fs.width - width - 8))
            y: fs.filterY
            implicitWidth: 230
            implicitHeight: filterCol.implicitHeight + 12
            radius: Appearance.rounding.small
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            component FilterRow: RippleButton {
                id: fr
                property string sym
                property string label
                property bool on
                Layout.fillWidth: true
                implicitHeight: 34
                buttonRadius: Appearance.rounding.small
                colBackground: on ? Appearance.colors.colSecondaryContainer : "transparent"
                colBackgroundHover: on ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                contentItem: RowLayout {
                    spacing: 10
                    MaterialSymbol { Layout.leftMargin: 6; text: fr.sym; iconSize: Appearance.font.pixelSize.larger; color: fr.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2 }
                    StyledText { Layout.fillWidth: true; text: fr.label; font.weight: fr.on ? Font.Medium : Font.Normal; color: fr.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2 }
                    MaterialSymbol { Layout.rightMargin: 6; visible: fr.on; text: "check"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnSecondaryContainer }
                }
            }
            ColumnLayout {
                id: filterCol
                anchors { fill: parent; margins: 6 }
                spacing: 2
                StyledText { Layout.leftMargin: 8; Layout.topMargin: 2; Layout.bottomMargin: 2; text: Translation.tr("Show"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                FilterRow { sym: "select_all"; label: Translation.tr("Files and folders"); on: fs.typeFilter === "all"; onClicked: fs.typeFilter = "all" }
                FilterRow { sym: "description"; label: Translation.tr("Files only"); on: fs.typeFilter === "file"; onClicked: fs.typeFilter = "file" }
                FilterRow { sym: "folder"; label: Translation.tr("Folders only"); on: fs.typeFilter === "dir"; onClicked: fs.typeFilter = "dir" }
                Rectangle { Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 2; implicitHeight: 1; color: Appearance.colors.colLayer0Border; opacity: 0.6 }
                StyledText { Layout.leftMargin: 8; Layout.topMargin: 2; text: Translation.tr("Match"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                FilterRow { sym: "match_case"; label: Translation.tr("Match case"); on: fs.matchCase; onClicked: fs.matchCase = !fs.matchCase }
                FilterRow { sym: "route"; label: Translation.tr("Match full path"); on: fs.matchPath; onClicked: fs.matchPath = !fs.matchPath }
            }
        }

        // Right-click context menu (overlay inside the card)
        MouseArea {
            anchors.fill: parent
            visible: fs.menuItem !== null
            acceptedButtons: Qt.AllButtons
            onPressed: fs.menuItem = null
        }
        Rectangle {
            id: ctxMenu
            visible: fs.menuItem !== null
            x: Math.max(8, Math.min(fs.menuX, fs.width - width - 8))
            y: Math.max(8, Math.min(fs.menuY, fs.height - height - 8))
            implicitWidth: 240
            implicitHeight: menuCol.implicitHeight + 12
            radius: Appearance.rounding.small
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            ColumnLayout {
                id: menuCol
                anchors { fill: parent; margins: 6 }
                spacing: 0
                Repeater {
                    model: fs.menuEntries
                    delegate: Loader {
                        required property var modelData
                        Layout.fillWidth: true
                        sourceComponent: modelData.sep ? sepC : entryC
                        Component {
                            id: sepC
                            Rectangle { implicitHeight: 1; color: Appearance.colors.colLayer0Border; opacity: 0.6 }
                        }
                        Component {
                            id: entryC
                            RippleButton {
                                implicitHeight: 34
                                buttonRadius: Appearance.rounding.small
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                onClicked: { const e = modelData; fs.menuItem = null; e.run() }
                                contentItem: RowLayout {
                                    spacing: 10
                                    MaterialSymbol {
                                        Layout.leftMargin: 4
                                        text: modelData.icon
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: modelData.danger ? "#ef5350" : Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        color: modelData.danger ? "#ef5350" : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    } }
}
