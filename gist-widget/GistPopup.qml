import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Gist popup: list of your gists (filter by description, file name, language or content; All/Public/Secret; sort),
// click one to view its files (copy, open on GitHub, edit, delete), or create a new one. Data and the gh calls live
// in GistButton (store); this popup is instantiated only while open.
Scope {
    id: root
    required property Item target
    required property var store
    property bool visible: true
    property string mode: "list"           // list | view | edit | create
    property string selectedId: ""
    readonly property var current: store.gists.find(g => g.id === selectedId) ?? null
    property string query: ""
    property string visibility: "all"      // all | public | secret
    property string sortKey: "updated"     // updated | created | name
    property bool confirmDelete: false
    property string notice: ""             // short confirmation at the bottom ("Link copied")
    property string formError: ""
    property real now: Date.now()
    Timer { interval: 30000; repeat: true; running: true; onTriggered: root.now = Date.now() }

    // Remembered across opens: visibility filter and sort
    readonly property string stateFile: `${Quickshell.env("HOME")}/.local/state/gist-widget.json`
    property bool stateReady: false
    function saveState() { if (stateReady) stateView.setText(JSON.stringify({ visibility, sortKey })) }
    onVisibilityChanged: saveState()
    onSortKeyChanged: saveState()
    FileView { id: stateView; path: root.stateFile; blockLoading: true; atomicWrites: true; printErrors: false }
    Component.onCompleted: {
        try {
            const j = JSON.parse(stateView.text());
            if (["all", "public", "secret"].includes(j.visibility)) root.visibility = j.visibility;
            if (["updated", "created", "name"].includes(j.sortKey)) root.sortKey = j.sortKey;
        } catch (e) {}
        root.stateReady = true;
        if (store.pendingMode === "create") { store.pendingMode = ""; if (store.draftMode === "") startCreate(); }
        resumeDraft();
    }
    // Reopen an unsaved draft (kept in the store, or restored from disk; that load can finish after the popup opened)
    function resumeDraft() {
        if (store.draftMode === "" || mode === "edit" || mode === "create") return;
        selectedId = store.draftId; mode = store.draftMode; draftGen++;
        if (store.draftRestored) { store.draftRestored = false; flash(Translation.tr("Restored your unsaved draft (%1)").arg(ago(store.draftSavedAt))); }
    }
    Connections { target: root.store; function onDraftRestoredChanged() { if (root.store.draftRestored) root.resumeDraft() } }

    // ---- helpers
    function title(g) { return g.description !== "" ? g.description : (g.files.length ? g.files[0].filename : g.id) }
    function ago(iso) {
        if (!iso) return "";
        const s = (now - Date.parse(iso)) / 1000;
        if (s < 60) return Translation.tr("just now");
        if (s < 3600) return `${Math.floor(s / 60)} min ago`;
        if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
        if (s < 86400 * 30) return `${Math.floor(s / 86400)} d ago`;
        return new Date(iso).toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }
    function fmtSize(b) { return b >= 1048576 ? (b / 1048576).toFixed(1) + " MB" : b >= 1024 ? (b / 1024).toFixed(1) + " KB" : b + " B" }
    function allContent(g) { return g.files.length === 1 ? g.files[0].content : g.files.map(f => `// ${f.filename}\n${f.content}`).join("\n\n") }
    function flash(text) { notice = text; noticeTimer.restart() }
    Timer { id: noticeTimer; interval: 2500; onTriggered: root.notice = "" }
    function copy(text, what) { Quickshell.clipboardText = text; flash(what) }

    // ---- filter (words must all match: description, id, file names, languages, or file content)
    readonly property var hay: store.gists.map(g => ({
        meta: `${g.description} ${g.id} ${g.files.map(f => f.filename + " " + f.language).join(" ")}`.toLowerCase(),
        content: g.files.map(f => f.content.toLowerCase())
    }))
    readonly property var filtered: {
        const words = query.trim().toLowerCase().split(/\s+/).filter(w => w !== "");
        const out = [];
        store.gists.forEach((g, gi) => {
            if (visibility === "public" && !g.public) return;
            if (visibility === "secret" && g.public) return;
            const h = hay[gi];
            if (!h) return;
            let excerpt = "";
            for (const w of words) {
                if (h.meta.includes(w)) continue;
                const fi = h.content.findIndex(c => c.includes(w));
                if (fi < 0) return;
                if (excerpt === "") {
                    const c = g.files[fi].content, i = h.content[fi].indexOf(w);
                    excerpt = `${g.files[fi].filename}: ${i > 30 ? "…" : ""}${c.slice(Math.max(0, i - 30), i + w.length + 60).replace(/\s+/g, " ").trim()}…`;
                }
            }
            out.push({ g: g, excerpt: excerpt });
        });
        if (sortKey === "name") out.sort((a, b) => title(a.g).localeCompare(title(b.g)));
        else if (sortKey === "created") out.sort((a, b) => b.g.created_at.localeCompare(a.g.created_at));
        else out.sort((a, b) => b.g.updated_at.localeCompare(a.g.updated_at));
        return out;
    }

    // ---- navigation
    function openGist(id) { selectedId = id; confirmDelete = false; mode = "view"; Qt.callLater(() => keyScope.forceActiveFocus()) }
    function toList() { mode = "list"; selectedId = ""; confirmDelete = false; Qt.callLater(() => input.forceActiveFocus()) }
    function back() {
        if (confirmDelete) { confirmDelete = false; return; }
        if (mode === "edit" || mode === "create") {
            if (store.draftDirty && !discardArmed) { discardArmed = true; formError = Translation.tr("Unsaved changes: press Esc or Cancel again to discard them."); return; }
            const wasEdit = mode === "edit";
            endDraft();
            if (wasEdit && current) { mode = "view"; keyScope.forceActiveFocus(); } else toList();
        }
        else if (mode === "view") toList();
        else if (query !== "") input.text = "";
        else root.visible = false;
    }

    // ---- editor. The draft (store.draft: one row per file; orig = name on GitHub, "" for a new file; locked = content
    // not fully loaded) lives in the store, so closing the popup by accident keeps it: it reopens in the editor.
    // Every change goes through store.touchDraft(), which autosaves it locally 2 s later (never to GitHub).
    readonly property var draft: store.draft
    property int draftGen: 0               // bumps when the draft is replaced so the fields re-read it
    property bool discardArmed: false      // Esc on a changed draft asks first; a second Esc discards
    property bool overwriteArmed: false    // the gist changed on GitHub since editing started: a second Save overwrites
    // Never replace an unsaved draft: reopen it instead (save or discard it first)
    function guardDraft() {
        if (!store.hasDraft) return false;
        resumeDraft(); flash(Translation.tr("Save or discard this draft first"));
        return true;
    }
    function startCreate(content) {
        if (guardDraft()) return;
        store.clearSavedDraft();
        draft.clear(); store.removedFiles = []; formError = ""; store.draftDesc = ""; store.draftPublic = false;
        draft.append({ orig: "", name: "", content: content ?? "", locked: false });
        store.draftId = ""; store.draftBase = ""; store.draftMode = "create"; store.draftDirty = false; discardArmed = false; overwriteArmed = false;
        draftGen++; mode = "create";
        Qt.callLater(() => desc.input.forceActiveFocus());
    }
    function startEdit() {
        if (!current || guardDraft()) return;
        store.clearSavedDraft();
        draft.clear(); store.removedFiles = []; formError = ""; store.draftDesc = current.description; store.draftPublic = current.public;
        for (const f of current.files) draft.append({ orig: f.filename, name: f.filename, content: f.content, locked: f.truncated || f.clipped });
        store.draftId = current.id; store.draftBase = current.updated_at; store.draftMode = "edit"; store.draftDirty = false;
        discardArmed = false; overwriteArmed = false;
        draftGen++; mode = "edit";
    }
    function endDraft() {
        store.clearSavedDraft();
        store.draftMode = ""; store.draftId = ""; store.draftBase = ""; store.draftDirty = false; draft.clear();
        discardArmed = false; overwriteArmed = false; formError = "";
    }
    function addFile() { draft.append({ orig: "", name: "", content: "", locked: false }); store.touchDraft() }
    function removeFile(i) {
        const o = draft.get(i).orig;
        if (o !== "") store.removedFiles = store.removedFiles.concat([o]);
        draft.remove(i); store.touchDraft();
    }
    function save() {
        if (store.busy) return;
        formError = "";
        if (draft.count === 0) { formError = Translation.tr("A gist needs at least one file."); return; }
        const files = {}, seen = {};
        for (let i = 0; i < draft.count; i++) {
            const d = draft.get(i);
            const name = d.name.trim() !== "" ? d.name.trim() : `gistfile${i + 1}.txt`;
            if (seen[name]) { formError = Translation.tr("Two files are named \"%1\".").arg(name); return; }
            seen[name] = true;
            if (!d.locked && d.content.trim() === "") { formError = Translation.tr("\"%1\" is empty; GitHub doesn't allow empty files.").arg(name); return; }
            if (mode === "create" || d.orig === "") { files[name] = { content: d.content }; continue; }
            const o = current?.files.find(f => f.filename === d.orig);
            const e = {};
            if (name !== d.orig) e.filename = name;
            if (!d.locked && (!o || d.content !== o.content)) e.content = d.content;
            if (Object.keys(e).length) files[d.orig] = e;
        }
        for (const r of store.removedFiles) files[r] = null;
        // A draft can be old (it survives restarts): don't silently overwrite changes made on GitHub in the meantime.
        if (mode === "edit" && current && store.draftBase !== "" && current.updated_at !== store.draftBase && !overwriteArmed) {
            overwriteArmed = true;
            formError = Translation.tr("This gist changed on GitHub (%1) after you started editing. Save again to overwrite it with your version.").arg(ago(current.updated_at));
            return;
        }
        if (mode === "create") {
            store.run(["create"], JSON.stringify({ description: store.draftDesc.trim(), public: store.draftPublic, files: files }), (ok, out) => {
                if (!ok) return;
                const [id, url] = out.split("\n").pop().split(" ");
                Quickshell.clipboardText = url;
                endDraft(); openGist(id); flash(Translation.tr("Gist created · link copied"));
            });
        } else {
            const id = store.draftId;
            store.run(["update", id], JSON.stringify({ description: store.draftDesc.trim(), files: files }), ok => {
                if (!ok) return;
                endDraft(); openGist(id); flash(Translation.tr("Saved"));
            });
        }
    }
    function remove() {
        const id = selectedId;
        store.run(["delete", id], "", ok => { if (ok) { toList(); flash(Translation.tr("Gist deleted")); } else confirmDelete = false; });
    }
    Process {  // "Paste" in the editor: the clipboard into the first empty file (or a new one)
        id: pasteProc
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === "") return;
                let i = -1;
                for (let k = 0; k < draft.count; k++) if (!draft.get(k).locked && draft.get(k).content.trim() === "") { i = k; break; }
                if (i < 0) { root.addFile(); i = draft.count - 1; }
                draft.setProperty(i, "content", text);
                store.touchDraft();
                root.draftGen++;
            }
        }
    }

    // ---- row context menu
    property var menuGist: null
    property real menuX: 0
    property real menuY: 0

    component IconBtn: RippleButton {
        id: ib
        property string symbol
        property string tip
        property color iconColor: Appearance.colors.colOnLayer2
        implicitWidth: 30; implicitHeight: 30
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: ib.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: ib.iconColor
        }
        StyledToolTip { text: ib.tip; visible: ib.hovered && ib.tip !== "" }
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
    component LangChip: Rectangle {
        property string text
        visible: text !== ""
        implicitHeight: langText.implicitHeight + 4
        implicitWidth: langText.implicitWidth + 12
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer1
        StyledText {
            id: langText
            anchors.centerIn: parent
            text: parent.text
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colSubtext
        }
    }
    component Field: Rectangle {  // single-line input in a pill, like the task manager's filter
        id: fld
        property alias input: fieldInput
        property string placeholder
        signal edited(string text)
        property bool mono: false
        Layout.fillWidth: true
        implicitHeight: 38
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        border.width: fieldInput.activeFocus ? 1 : 0
        border.color: Appearance.colors.colPrimary
        StyledTextInput {
            id: fieldInput
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            verticalAlignment: TextInput.AlignVCenter
            color: Appearance.colors.colOnLayer2
            font.family: fld.mono ? Appearance.font.family.monospace : Appearance.font.family.main
            clip: true
            onTextChanged: fld.edited(text)
            StyledText {
                visible: fieldInput.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: fld.placeholder
                color: Appearance.colors.colSubtext
            }
        }
    }

    // Same geometry as the Docker/task-manager popups: left edge like the left sidebar, full height below the bar.
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
        implicitWidth: 480 + Appearance.sizes.hyprlandGapsOut + Appearance.sizes.elevationMargin
        mask: Region { item: card }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:sidebarLeft"  // same Hyprland layer rule (slide left) as the left sidebar
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        Component.onCompleted: if (root.mode === "list") input.forceActiveFocus()
        StyledRectangularShadow { target: card }

    Rectangle {
        id: card
        anchors { top: parent.top; left: parent.left; bottom: parent.bottom }
        anchors.topMargin: Appearance.sizes.hyprlandGapsOut
        anchors.leftMargin: Appearance.sizes.hyprlandGapsOut
        anchors.bottomMargin: Appearance.sizes.hyprlandGapsOut
        width: 480
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true
        // Esc = back/close, Ctrl+S = save, Ctrl+N = new gist (fields don't consume these, so they bubble up here)
        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier;
            if (event.key === Qt.Key_Escape) { if (root.menuGist) root.menuGist = null; else root.back(); event.accepted = true; }
            else if (ctrl && event.key === Qt.Key_S && (root.mode === "edit" || root.mode === "create")) { root.save(); event.accepted = true; }
            else if (ctrl && event.key === Qt.Key_N && root.mode !== "edit" && root.mode !== "create") { root.startCreate(); event.accepted = true; }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                IconBtn { visible: root.mode !== "list"; symbol: "arrow_back"; tip: root.mode === "edit" || root.mode === "create" ? Translation.tr("Cancel (Esc)") : Translation.tr("Back (Esc)"); onClicked: root.back() }
                MaterialSymbol { visible: root.mode === "list"; text: "data_object"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colOnLayer2 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.mode === "create" ? Translation.tr("New gist")
                            : root.mode === "edit" ? Translation.tr("Edit gist")
                            : root.mode === "view" ? (root.current ? root.title(root.current) : Translation.tr("Gist"))
                            : Translation.tr("Gists")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.mode === "list"
                            ? (root.store.syncing ? Translation.tr("Syncing…")
                               : root.store.syncError !== "" ? Translation.tr("Sync failed · showing cached gists")
                               : `${root.store.gists.length} ${Translation.tr("gists")}` + (root.store.lastSync ? ` · ${Translation.tr("synced")} ${root.ago(root.store.lastSync)}` : ""))
                            : root.current && root.mode !== "create"
                                ? `${root.current.public ? Translation.tr("Public") : Translation.tr("Secret")} · ${root.current.files.length} ${root.current.files.length === 1 ? Translation.tr("file") : Translation.tr("files")} · ${Translation.tr("updated")} ${root.ago(root.current.updated_at)}`
                                : root.mode === "create" ? Translation.tr("Ctrl+S to save") : ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.mode === "list" && root.store.syncError !== "" ? "#ef5350" : Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
                // list actions
                IconBtn { visible: root.mode === "list"; symbol: "add"; tip: Translation.tr("New gist (Ctrl+N)"); onClicked: root.startCreate() }
                IconBtn {
                    visible: root.mode === "list"
                    symbol: "sync"; tip: root.store.syncing ? Translation.tr("Syncing…") : Translation.tr("Sync now")
                    enabled: !root.store.syncing
                    onClicked: root.store.sync()
                }
                // view actions
                IconBtn { visible: root.mode === "view" && root.current; symbol: "link"; tip: Translation.tr("Copy link"); onClicked: root.copy(root.current.html_url, Translation.tr("Link copied")) }
                IconBtn { visible: root.mode === "view" && root.current; symbol: "open_in_new"; tip: Translation.tr("Open on GitHub"); onClicked: Qt.openUrlExternally(root.current.html_url) }
                IconBtn { visible: root.mode === "view" && root.current; symbol: "edit"; tip: Translation.tr("Edit"); onClicked: root.startEdit() }
                IconBtn { visible: root.mode === "view" && root.current; symbol: "delete"; tip: Translation.tr("Delete"); iconColor: "#ef5350"; onClicked: root.confirmDelete = true }
                // editor actions
                IconBtn { visible: root.mode === "edit" || root.mode === "create"; symbol: "content_paste"; tip: Translation.tr("Paste clipboard into a file"); onClicked: pasteProc.running = true }
                IconBtn { visible: root.mode === "edit" || root.mode === "create"; symbol: "note_add"; tip: Translation.tr("Add file"); onClicked: root.addFile() }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }

            // Delete confirmation
            Rectangle {
                visible: root.confirmDelete && root.mode === "view"
                Layout.fillWidth: true
                implicitHeight: delRow.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colErrorContainer
                RowLayout {
                    id: delRow
                    anchors { fill: parent; margins: 8; leftMargin: 12 }
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("Delete this gist on GitHub? This can't be undone.")
                        color: Appearance.colors.colOnErrorContainer
                    }
                    Chip { label: Translation.tr("Cancel"); onClicked: root.confirmDelete = false }
                    RippleButton {
                        implicitHeight: 30; implicitWidth: delText.implicitWidth + 24
                        buttonRadius: Appearance.rounding.full
                        colBackground: "#d32f2f"; colBackgroundHover: "#e53935"
                        enabled: !root.store.busy
                        onClicked: root.remove()
                        contentItem: StyledText { id: delText; horizontalAlignment: Text.AlignHCenter; text: root.store.busy ? Translation.tr("Deleting…") : Translation.tr("Delete"); color: "white" }
                    }
                }
            }

            // ---------------- list ----------------
            Rectangle {
                visible: root.mode === "list"
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
                    spacing: 8
                    MaterialSymbol { text: "search"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colSubtext }
                    StyledTextInput {
                        id: input
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        clip: true
                        onTextChanged: root.query = text
                        Keys.onEscapePressed: root.back()
                        Keys.onReturnPressed: if (root.filtered.length) root.openGist(root.filtered[0].g.id)
                        Keys.onEnterPressed: if (root.filtered.length) root.openGist(root.filtered[0].g.id)
                        StyledText {
                            visible: input.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Filter by description, file, language or content…")
                            color: Appearance.colors.colSubtext
                        }
                    }
                    IconBtn { visible: input.text !== ""; symbol: "close"; implicitWidth: 26; implicitHeight: 26; onClicked: input.text = "" }
                }
            }
            RowLayout {
                visible: root.mode === "list"
                Layout.fillWidth: true
                spacing: 4
                Chip { label: Translation.tr("All"); active: root.visibility === "all"; onClicked: root.visibility = "all" }
                Chip { label: Translation.tr("Public"); active: root.visibility === "public"; onClicked: root.visibility = "public" }
                Chip { label: Translation.tr("Secret"); active: root.visibility === "secret"; onClicked: root.visibility = "secret" }
                Item { Layout.fillWidth: true }
                RippleButton {
                    implicitHeight: 26
                    implicitWidth: sortRow.implicitWidth + 16
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.sortKey = root.sortKey === "updated" ? "created" : root.sortKey === "created" ? "name" : "updated"
                    contentItem: RowLayout {
                        id: sortRow
                        spacing: 4
                        MaterialSymbol { text: "sort"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
                        StyledText {
                            text: root.sortKey === "updated" ? Translation.tr("Recently updated") : root.sortKey === "created" ? Translation.tr("Newest") : Translation.tr("Name")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledToolTip { text: Translation.tr("Change sort order"); visible: parent.hovered }
                }
            }

            StyledListView {
                id: list
                visible: root.mode === "list"
                animateAppearance: false
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds
                delegate: RippleButton {
                    id: rowBtn
                    required property var modelData
                    readonly property var g: modelData.g
                    width: list.width
                    implicitHeight: rowCol.implicitHeight + 16
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.openGist(g.id)
                    altAction: () => {
                        const p = rowBtn.mapToItem(card, rowBtn.width - 220, rowBtn.height / 2);
                        root.menuX = p.x; root.menuY = p.y; root.menuGist = rowBtn.g;
                    }
                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 2
                            Layout.leftMargin: 4
                            text: rowBtn.g.public ? "public" : "lock"
                            iconSize: Appearance.font.pixelSize.larger
                            color: rowBtn.g.public ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            id: rowCol
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: root.title(rowBtn.g)
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: `${rowBtn.g.files.map(f => f.filename).join(", ")} · ${root.ago(rowBtn.g.updated_at)}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                elide: Text.ElideRight
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {  // where a content match was found
                                visible: rowBtn.modelData.excerpt !== ""
                                Layout.fillWidth: true
                                text: rowBtn.modelData.excerpt
                                textFormat: Text.PlainText
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.monospace
                                elide: Text.ElideRight
                                color: Appearance.colors.colPrimary
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: [...new Set(rowBtn.g.files.map(f => f.language).filter(l => l !== ""))]
                                    delegate: LangChip { required property string modelData; text: modelData }
                                }
                            }
                        }
                        IconBtn {
                            Layout.alignment: Qt.AlignVCenter
                            symbol: "content_copy"
                            tip: Translation.tr("Copy content")
                            iconColor: Appearance.colors.colSubtext
                            onClicked: root.copy(root.allContent(rowBtn.g), Translation.tr("Content copied"))
                        }
                    }
                }

                ColumnLayout {  // empty states
                    anchors.centerIn: parent
                    width: parent.width - 40
                    visible: root.filtered.length === 0
                    spacing: 10
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.store.gists.length === 0 && root.store.syncing ? "sync" : root.store.gists.length === 0 ? "data_object" : "search_off"
                        iconSize: 48
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                        text: root.store.gists.length > 0 ? Translation.tr("No gists match")
                            : root.store.syncing ? Translation.tr("Loading your gists…")
                            : root.store.syncError !== "" ? root.store.syncError
                            : Translation.tr("No gists yet. Press + or Ctrl+N to create one.")
                    }
                }
            }

            // ---------------- view ----------------
            StyledListView {
                id: fileList
                visible: root.mode === "view"
                animateAppearance: false
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 12
                model: root.current ? root.current.files : []
                boundsBehavior: Flickable.StopAtBounds
                delegate: ColumnLayout {
                    id: fileItem
                    required property var modelData
                    width: fileList.width
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialSymbol { text: "description"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colSubtext }
                        StyledText {
                            Layout.fillWidth: true
                            text: fileItem.modelData.filename
                            font.family: Appearance.font.family.monospace
                            font.weight: Font.Medium
                            elide: Text.ElideMiddle
                            color: Appearance.colors.colOnLayer2
                        }
                        LangChip { text: fileItem.modelData.language }
                        StyledText { text: root.fmtSize(fileItem.modelData.size); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                        IconBtn { symbol: "content_copy"; tip: Translation.tr("Copy file"); onClicked: root.copy(fileItem.modelData.content, Translation.tr("File copied")) }
                        IconBtn { symbol: "code"; tip: Translation.tr("Copy raw URL (for curl)"); onClicked: root.copy(fileItem.modelData.raw_url, Translation.tr("Raw URL copied")) }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: code.implicitHeight + 16
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer0
                        TextEdit {
                            id: code
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            textFormat: TextEdit.PlainText
                            text: fileItem.modelData.content
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer0
                            selectionColor: Appearance.colors.colSecondaryContainer
                            selectedTextColor: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                    StyledText {
                        visible: fileItem.modelData.truncated || fileItem.modelData.clipped
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("Only the start of this file is shown; open it on GitHub for the rest.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: "#ffb300"
                    }
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: !root.current
                    color: Appearance.colors.colSubtext
                    text: root.store.busy || root.store.syncing ? Translation.tr("Loading…") : Translation.tr("This gist no longer exists")
                }
            }

            // ---------------- create / edit ----------------
            StyledFlickable {
                id: edFlick
                visible: root.mode === "edit" || root.mode === "create"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: edCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                // keep the text cursor visible while typing in a tall file
                function reveal(item, r) {
                    const p = item.mapToItem(edFlick.contentItem, r.x, r.y);
                    if (p.y < contentY) contentY = Math.max(0, p.y - 8);
                    else if (p.y + r.height > contentY + height) contentY = p.y + r.height - height + 8;
                }
                ColumnLayout {
                    id: edCol
                    width: edFlick.width - 8
                    spacing: 10
                    Field {
                        id: desc
                        placeholder: Translation.tr("Description (optional)")
                        onEdited: text => { if (text !== root.store.draftDesc) { root.store.draftDesc = text; root.store.touchDraft(); } }
                        Connections { target: root; function onDraftGenChanged() { desc.input.text = root.store.draftDesc } }
                        Component.onCompleted: input.text = root.store.draftDesc
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Chip { visible: root.mode === "create" || !root.store.draftPublic; label: Translation.tr("Secret"); active: !root.store.draftPublic; onClicked: if (root.mode === "create") { root.store.draftPublic = false; root.store.touchDraft(); } }
                        Chip { visible: root.mode === "create" || root.store.draftPublic; label: Translation.tr("Public"); active: root.store.draftPublic; onClicked: if (root.mode === "create") { root.store.draftPublic = true; root.store.touchDraft(); } }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            wrapMode: Text.Wrap
                            text: root.mode === "edit" ? Translation.tr("GitHub can't change a gist's visibility after creation.")
                                : root.store.draftPublic ? Translation.tr("Listed on your profile and searchable.")
                                : Translation.tr("Unlisted: only people with the link can see it.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Repeater {
                        model: root.draft
                        delegate: ColumnLayout {
                            id: fileEd
                            required property int index
                            required property string name
                            required property string content
                            required property bool locked
                            Layout.fillWidth: true
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Field {
                                    id: nameField
                                    mono: true
                                    placeholder: Translation.tr("File name with extension, e.g. notes.md")
                                    onEdited: text => { if (text !== fileEd.name) { root.draft.setProperty(fileEd.index, "name", text); root.store.touchDraft(); } }
                                    Connections { target: root; function onDraftGenChanged() { nameField.input.text = root.draft.get(fileEd.index)?.name ?? "" } }
                                    Component.onCompleted: input.text = fileEd.name
                                }
                                IconBtn {
                                    visible: root.draft.count > 1
                                    symbol: "delete"; tip: Translation.tr("Remove file")
                                    iconColor: Appearance.colors.colSubtext
                                    onClicked: root.removeFile(fileEd.index)
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: Math.max(160, area.implicitHeight + 4)
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer0
                                border.width: area.activeFocus ? 1 : 0
                                border.color: Appearance.colors.colPrimary
                                StyledTextArea {
                                    id: area
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 2 }
                                    readOnly: fileEd.locked
                                    wrapMode: TextEdit.WrapAnywhere
                                    textFormat: TextEdit.PlainText
                                    selectByMouse: true
                                    placeholderText: Translation.tr("Content")
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    background: null
                                    onTextChanged: if (!fileEd.locked && text !== fileEd.content) { root.draft.setProperty(fileEd.index, "content", text); root.store.touchDraft(); }
                                    onCursorRectangleChanged: if (activeFocus) edFlick.reveal(area, cursorRectangle)
                                    Connections { target: root; function onDraftGenChanged() { area.text = root.draft.get(fileEd.index)?.content ?? "" } }
                                    Component.onCompleted: text = fileEd.content
                                }
                            }
                            StyledText {
                                visible: fileEd.locked
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: Translation.tr("Too large to edit here (only the start was loaded); you can rename or remove it.")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: "#ffb300"
                            }
                        }
                    }
                }
            }
            RowLayout {  // editor footer
                visible: root.mode === "edit" || root.mode === "create"
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    readonly property bool isError: root.formError !== "" || root.store.actError !== ""
                    text: root.formError !== "" ? root.formError : root.store.actError !== "" ? root.store.actError
                        : root.notice !== "" ? root.notice
                        : root.store.draftSavedAt !== "" ? Translation.tr("Draft saved on this computer · %1").arg(root.ago(root.store.draftSavedAt))
                        : root.store.draftDirty ? Translation.tr("Unsaved (the draft is kept on this computer)") : ""
                    color: isError ? "#ef5350" : root.notice !== "" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                Chip { label: Translation.tr("Cancel"); onClicked: root.back() }
                RippleButton {
                    implicitHeight: 34; implicitWidth: saveRow.implicitWidth + 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    enabled: !root.store.busy
                    onClicked: root.save()
                    contentItem: RowLayout {
                        id: saveRow
                        spacing: 6
                        Item { Layout.fillWidth: true }
                        MaterialSymbol { text: root.mode === "create" ? "cloud_upload" : "save"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnPrimary }
                        StyledText {
                            text: root.store.busy ? Translation.tr("Saving…") : root.mode === "create" ? Translation.tr("Create") : Translation.tr("Save")
                            color: Appearance.colors.colOnPrimary
                        }
                        Item { Layout.fillWidth: true }
                    }
                    StyledToolTip { text: "Ctrl+S"; visible: parent.hovered }
                }
            }

            // Footer: confirmation, last error, or hints
            StyledText {
                visible: root.mode === "list" || root.mode === "view"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.notice !== "" ? root.notice
                    : root.store.actError !== "" ? root.store.actError
                    : root.mode === "list" ? Translation.tr("Enter opens the first match · Ctrl+N new · right-click a gist for actions")
                    : Translation.tr("Select text to copy part of a file · Esc goes back")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.notice !== "" ? Appearance.colors.colPrimary : root.store.actError !== "" ? "#ef5350" : Appearance.colors.colSubtext
            }
        }

        // Right-click menu for a list row (overlay inside the card)
        MouseArea {
            anchors.fill: parent
            visible: root.menuGist !== null
            acceptedButtons: Qt.AllButtons
            onPressed: root.menuGist = null
        }
        Rectangle {
            visible: root.menuGist !== null
            x: Math.max(8, Math.min(root.menuX, card.width - width - 8))
            y: Math.max(8, Math.min(root.menuY, card.height - height - 8))
            width: 220
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
                Repeater {
                    model: [
                        { icon: "link", label: Translation.tr("Copy link"), act: "link" },
                        { icon: "content_copy", label: Translation.tr("Copy content"), act: "copy" },
                        { icon: "open_in_new", label: Translation.tr("Open on GitHub"), act: "web" },
                        { icon: "edit", label: Translation.tr("Edit"), act: "edit" },
                        { icon: "delete", label: Translation.tr("Delete…"), act: "delete", danger: true },
                    ]
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            const g = root.menuGist;
                            root.menuGist = null;
                            if (!g) return;
                            if (modelData.act === "link") root.copy(g.html_url, Translation.tr("Link copied"));
                            else if (modelData.act === "copy") root.copy(root.allContent(g), Translation.tr("Content copied"));
                            else if (modelData.act === "web") Qt.openUrlExternally(g.html_url);
                            else if (modelData.act === "edit") { root.openGist(g.id); root.startEdit(); }
                            else { root.openGist(g.id); root.confirmDelete = true; }
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
    }
    }
    }
}
