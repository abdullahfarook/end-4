import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// File search popup (Everything-style): type to filter an fd file index with `fzf --filter` (fuzzy, ranked).
// Enter / click opens, Ctrl+Enter or the folder button reveals the folder, Up/Down move, Esc closes.
// The index is cached per scope in $XDG_RUNTIME_DIR and rebuilt when older than 2 minutes.
Scope {
    id: root
    required property Item target
    property bool visible: true
    property string query: ""
    property string scope: "home"          // "home" | "root"
    property var results: []               // [{kind, size, mtime, path}]
    property bool indexing: false
    property bool searching: false
    property int current: 0
    property string sortKey: "relevance"   // relevance | name | type | size | date
    property string sortDir: ""            // "" = default order for the key | "asc" | "desc"
    // Effective direction: explicit choice, else the key's natural default (name/type A→Z, size/date big/new first)
    readonly property bool sortAsc: sortDir !== "" ? sortDir === "asc" : (sortKey === "relevance" || sortKey === "name" || sortKey === "type")
    property bool sortMenuOpen: false
    property bool helpOpen: false
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
        const r = results.slice();
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
        sortKey = k; sortDir = "";
        current = 0;
    }
    readonly property string home: Quickshell.env("HOME")
    readonly property string idxFile: `${Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp"}/file-search2-${scope}.idx`

    // Remembered across opens (and shell restarts): sort key/direction, Home/System scope and the search text (selected on open)
    readonly property string stateFile: `${Quickshell.env("HOME")}/.local/state/file-search.json`
    property bool stateReady: false
    function saveState() {
        if (stateReady) stateView.setText(JSON.stringify({ sortKey, sortDir, scope, query }));
    }
    onSortKeyChanged: saveState()
    onSortDirChanged: saveState()
    onQueryChanged: saveState()
    FileView { id: stateView; path: root.stateFile; blockLoading: true; atomicWrites: true }
    Component.onCompleted: {
        try {
            const j = JSON.parse(stateView.text());
            if (sortDefs.some(d => d.key === j.sortKey)) root.sortKey = j.sortKey;
            if (["", "asc", "desc"].includes(j.sortDir)) root.sortDir = j.sortDir;
            if (j.scope === "home" || j.scope === "root") root.scope = j.scope;
            if (typeof j.query === "string" && j.query !== "") { input.text = j.query; input.selectAll(); }
        } catch (e) {}
        root.stateReady = true;
        buildIndex();
    }
    onVisibleChanged: if (!visible) { indexProc.running = false; searchProc.running = false }
    onScopeChanged: { saveState(); results = []; buildIndex(); }

    function buildIndex() {
        if (indexProc.running) return;
        root.indexing = true;
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
            'if [[ "$2" == */* ]]; then nth="1,2"; else nth="1"; fi; ' +
            'fzf --filter "$2" --delimiter $\'\\t\' --nth "$nth" --tiebreak=length,index < "$1" 2>/dev/null | head -1500 | cut -f2- | ' +
            'xargs -d "\\n" -r stat --printf "%F\\t%s\\t%Y\\t%n\\n" 2>/dev/null',
            "_", idxFile, q];
        searchProc.running = true;
    }
    function openPath(p) { Quickshell.execDetached(["xdg-open", p]); root.visible = false }
    function parentOf(p) { return p.replace(/\/[^\/]*$/, "") || "/" }
    function revealPath(item) {
        Quickshell.execDetached(["dolphin", "--select", item.path]); root.visible = false;
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
            { icon: "terminal", label: Translation.tr("Open terminal here"), run: () => { Quickshell.execDetached(["kitty", "--directory", dir]); root.visible = false } },
            { icon: "code", label: Translation.tr("Open in VS Code"), run: () => { Quickshell.execDetached(["code", it.path]); root.visible = false } },
            { sep: true },
            { icon: "content_copy", label: Translation.tr("Copy full path"), run: () => Quickshell.clipboardText = it.path },
            { icon: "drive_file_rename_outline", label: Translation.tr("Copy name"), run: () => Quickshell.clipboardText = it.path.split("/").pop() },
            { icon: "folder_copy", label: Translation.tr("Copy parent path"), run: () => Quickshell.clipboardText = parentOf(it.path) },
            { sep: true },
            { icon: "delete", label: Translation.tr("Move to trash"), danger: true, run: () => {
                Quickshell.execDetached(["gio", "trash", it.path]);
                root.results = root.results.filter(r => r.path !== it.path);
                root.current = Math.min(root.current, Math.max(0, root.results.length - 1));
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
        return Qt.formatDateTime(new Date(s * 1000), "yyyy-MM-dd HH:mm");
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

    Timer { id: debounce; interval: 120; onTriggered: root.search() }
    Process {
        id: indexProc
        onExited: { root.indexing = false; if (root.query.trim() !== "") root.search() }
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
                root.results = out; root.current = 0; root.searching = false;
            }
        }
    }

    // Same geometry as the Mail widget: own layer window, like the left sidebar (gap, full height).
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
        // Same geometry as the left sidebar: top/left/bottom anchored below the bar, hyprland outer gap around the card
        color: "transparent"
        anchors { top: true; left: true; bottom: true }
        implicitWidth: 440 + Appearance.sizes.hyprlandGapsOut + Appearance.sizes.elevationMargin
        mask: Region { item: card }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:sidebarLeft"  // same Hyprland layer rule (slide left) as the left sidebar: native slide in/out
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        Component.onCompleted: { input.forceActiveFocus(); input.selectAll() }

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
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.normal
                            clip: true
                            onTextChanged: { root.query = text; debounce.restart() }
                            Keys.onEscapePressed: { if (root.menuItem) root.menuItem = null; else if (root.helpOpen) root.helpOpen = false; else if (root.sortMenuOpen) root.sortMenuOpen = false; else root.visible = false }
                            Keys.onDownPressed: root.current = Math.min(root.current + 1, root.sortedResults.length - 1)
                            Keys.onUpPressed: root.current = Math.max(root.current - 1, 0)
                            Keys.onReturnPressed: event => {
                                const it = root.sortedResults[root.current];
                                if (!it) return;
                                if (event.modifiers & Qt.ControlModifier) root.revealPath(it); else root.openPath(it.path);
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
                            colBackground: root.helpOpen ? Appearance.colors.colSecondaryContainer : "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: { root.helpOpen = !root.helpOpen; input.forceActiveFocus() }
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "help"
                                iconSize: Appearance.font.pixelSize.larger
                                color: root.helpOpen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                            }
                            StyledToolTip { text: Translation.tr("Search tips"); visible: parent.hovered }
                        }
                        MaterialSymbol {
                            visible: root.indexing || root.searching
                            text: "progress_activity"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                            RotationAnimator on rotation { running: parent.visible; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                    }
                }
                RippleButton {
                    id: sortBtn
                    implicitHeight: 40
                    implicitWidth: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        const p = mapToItem(card, 0, height + 4);
                        root.sortMenuX = p.x; root.sortMenuY = p.y; root.sortMenuOpen = !root.sortMenuOpen;
                    }
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: root.sortDir === "" ? "swap_vert" : root.sortDir === "asc" ? "arrow_upward" : "arrow_downward"
                        iconSize: Appearance.font.pixelSize.larger
                        color: root.sortDir === "" && root.sortKey === "relevance" ? Appearance.colors.colOnLayer2 : Appearance.colors.colPrimary
                    }
                    StyledToolTip { text: Translation.tr("Sort: %1 (%2)").arg(root.sortLabel).arg(root.sortDir === "" ? Translation.tr("default order") : root.sortDir === "asc" ? Translation.tr("ascending") : Translation.tr("descending")); visible: sortBtn.hovered }
                }
                RippleButton {
                    implicitHeight: 40; implicitWidth: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: { root.scope = root.scope === "home" ? "root" : "home"; input.forceActiveFocus() }
                    contentItem: RowLayout {
                        id: scopeRow
                        spacing: 6
                        MaterialSymbol { text: root.scope === "home" ? "home" : "computer"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer2 }
                    }
                    StyledToolTip { text: root.scope === "home" ? Translation.tr("Searching home: click for whole system") : Translation.tr("Searching whole system: click for home"); visible: parent.hovered }
                }
            }

            // Results
            StyledListView {
                id: list
                animateAppearance: false
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: root.sortedResults
                currentIndex: root.current
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: RippleButton {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === root.current
                    width: list.width
                    implicitHeight: 58
                    buttonRadius: Appearance.rounding.small
                    colBackground: sel ? Appearance.colors.colSecondaryContainer : "transparent"
                    colBackgroundHover: sel ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2Hover
                    onClicked: root.openPath(modelData.path)
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: mouse => {
                            root.current = row.index;
                            const p = mapToItem(card, mouse.x, mouse.y);
                            root.showMenu(row.modelData, p);
                        }
                    }
                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            Layout.leftMargin: 4
                            text: root.iconFor(row.modelData)
                            iconSize: Appearance.font.pixelSize.huge
                            color: row.modelData.kind === "dir" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.path.split("/").pop() || "/"
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.prettyPath(row.modelData.path)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                elide: Text.ElideMiddle
                                color: Appearance.colors.colSubtext
                            }
                        }
                        ColumnLayout {
                            Layout.rightMargin: 6
                            spacing: 0
                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: row.modelData.kind === "dir" ? Translation.tr("Folder") : root.fmtSize(row.modelData.size)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: root.fmtDate(row.modelData.mtime)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                // Empty / loading / no-match states
                ColumnLayout {
                    id: emptyState
                    anchors.centerIn: parent
                    visible: root.sortedResults.length === 0
                    width: parent.width - 48
                    spacing: 6
                    readonly property bool idle: root.query.trim() === ""
                    readonly property bool busy: !idle && (root.indexing || root.searching)
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
                        text: emptyState.busy ? (root.indexing ? Translation.tr("Indexing files…") : Translation.tr("Searching…"))
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
                            : root.scope === "home"
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
                        onClicked: root.helpOpen = true
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
                text: (root.sortedResults.length > 0 ? Translation.tr("%1 results · ").arg(root.sortedResults.length) : "") + Translation.tr("Enter open · Ctrl+Enter show in folder · right-click menu")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Search tips overlay (explains what can be typed into the field)
        MouseArea {
            anchors.fill: parent
            visible: root.helpOpen
            onPressed: root.helpOpen = false
        }
        Rectangle {
            visible: root.helpOpen
            x: 12
            y: 60
            width: card.width - 24
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
                            root.helpOpen = false; input.forceActiveFocus();
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
            visible: root.sortMenuOpen
            onPressed: root.sortMenuOpen = false
        }
        Rectangle {
            visible: root.sortMenuOpen
            x: Math.max(8, Math.min(root.sortMenuX, card.width - width - 8))
            y: root.sortMenuY
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
                    model: root.sortDefs
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: { root.sortKey = modelData.key; root.sortDir = ""; root.current = 0; root.sortMenuOpen = false }
                        contentItem: RowLayout {
                            spacing: 10
                            MaterialSymbol { Layout.leftMargin: 4; text: modelData.icon; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer2 }
                            StyledText { Layout.fillWidth: true; text: modelData.label; color: Appearance.colors.colOnLayer2 }
                            MaterialSymbol { visible: root.sortKey === modelData.key; text: "check"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colPrimary }
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
                        onClicked: { root.sortDir = root.sortDir === modelData.dir ? "" : modelData.dir; root.current = 0; root.sortMenuOpen = false }
                        contentItem: RowLayout {
                            spacing: 10
                            MaterialSymbol { Layout.leftMargin: 4; text: modelData.icon; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer2 }
                            StyledText { Layout.fillWidth: true; text: modelData.label; color: Appearance.colors.colOnLayer2 }
                            MaterialSymbol { visible: root.sortDir === modelData.dir; text: "check"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colPrimary }
                        }
                    }
                }
            }
        }

        // Right-click context menu (overlay inside the card)
        MouseArea {
            anchors.fill: parent
            visible: root.menuItem !== null
            acceptedButtons: Qt.AllButtons
            onPressed: root.menuItem = null
        }
        Rectangle {
            id: ctxMenu
            visible: root.menuItem !== null
            x: Math.max(8, Math.min(root.menuX, card.width - width - 8))
            y: Math.max(8, Math.min(root.menuY, card.height - height - 8))
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
                    model: root.menuEntries
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
                                onClicked: { const e = modelData; root.menuItem = null; e.run() }
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
    }
    }
}
