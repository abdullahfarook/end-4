import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// File search popup (Everything-style): type to filter an fd file index with `fzf --filter` (fuzzy, ranked).
// Enter / click opens, Ctrl+Enter or the folder button reveals the folder, Up/Down move, Esc closes.
// The index is cached per scope in $XDG_RUNTIME_DIR and rebuilt when older than 2 minutes.
PopupWindow {
    id: root
    required property Item target
    property string query: ""
    property string scope: "home"          // "home" | "root"
    property var results: []               // [{kind, size, mtime, path}]
    property bool indexing: false
    property bool searching: false
    property int current: 0
    readonly property string home: Quickshell.env("HOME")
    readonly property string idxFile: `${Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp"}/file-search-${scope}.idx`

    anchor.window: target.QsWindow.window
    anchor.onAnchoring: {
        const p = target.QsWindow.mapFromItem(target, 0, 0);
        anchor.rect = Qt.rect(p.x, p.y, target.width, target.height);
    }
    anchor.edges: Config.options.bar.bottom ? Edges.Top : Edges.Bottom
    anchor.gravity: anchor.edges === Edges.Top ? Edges.Top : Edges.Bottom
    anchor.adjustment: PopupAdjustment.All
    grabFocus: true
    color: "transparent"
    implicitWidth: card.implicitWidth + 16
    implicitHeight: card.implicitHeight + 16

    onVisibleChanged: {
        if (visible) { buildIndex(); input.forceActiveFocus(); input.selectAll(); }
        else { indexProc.running = false; searchProc.running = false; }
    }
    onScopeChanged: { results = []; buildIndex(); }

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
            '. "$base" > "$idx.tmp" 2>/dev/null; mv -f "$idx.tmp" "$idx"',
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
            'fzf --filter "$2" --scheme=path < "$1" 2>/dev/null | head -60 | ' +
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

    Rectangle {
        id: card
        anchors.centerIn: parent
        implicitWidth: 640
        implicitHeight: 460
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
                            Keys.onEscapePressed: { if (root.menuItem) root.menuItem = null; else root.visible = false }
                            Keys.onDownPressed: root.current = Math.min(root.current + 1, root.results.length - 1)
                            Keys.onUpPressed: root.current = Math.max(root.current - 1, 0)
                            Keys.onReturnPressed: event => {
                                const it = root.results[root.current];
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
                    implicitHeight: 40; implicitWidth: scopeRow.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: { root.scope = root.scope === "home" ? "root" : "home"; input.forceActiveFocus() }
                    contentItem: RowLayout {
                        id: scopeRow
                        spacing: 6
                        MaterialSymbol { text: root.scope === "home" ? "home" : "computer"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer2 }
                        StyledText { text: root.scope === "home" ? Translation.tr("Home") : Translation.tr("System"); color: Appearance.colors.colOnLayer2 }
                    }
                    StyledToolTip { text: Translation.tr("Toggle search scope: home / whole system"); visible: parent.hovered }
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
                model: root.results
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

                StyledText {
                    anchors.centerIn: parent
                    visible: root.results.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colSubtext
                    width: parent.width - 40
                    wrapMode: Text.Wrap
                    text: root.query.trim() === "" ? Translation.tr("Type to search. Fuzzy matching: \"cfgnv\" finds config/nvim.lua")
                        : (root.indexing || root.searching) ? Translation.tr("Searching…") : Translation.tr("No matches")
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Enter open · Ctrl+Enter show in folder · right-click menu · ↑↓ move · Esc close")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
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
