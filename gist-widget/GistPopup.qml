import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Gist popup: list of your gists (filter by description, file name, language or content; All/Public/Secret/Drafts; sort),
// click one to view its files (copy, open on GitHub, edit, delete), or create a new one. Creating and editing happen in
// drafts (GistButton keeps them, also on disk): going back keeps the draft, the list marks it, Save (top right, Ctrl+S)
// publishes it and keeps the editor open. Data and gh calls live in GistButton (store); this popup exists only while open.
Scope {
    id: root
    required property Item target
    required property var store
    property var screen: null              // the bar's screen: the popup opens next to the button that was clicked
    property bool visible: true
    property string mode: "list"           // list | view | editor
    property string selectedId: ""
    readonly property var current: store.gistById(selectedId)
    property string query: ""
    property string visibility: "all"      // all | public | secret | drafts
    property string sortKey: "updated"     // updated | created | name
    property bool confirmDelete: false
    property string confirmDiscardKey: ""  // draft waiting for "Discard?" confirmation
    property string notice: ""             // short confirmation ("Link copied")
    property string formError: ""
    property bool overwriteArmed: false    // the gist changed on GitHub since editing started: a second Save goes ahead
    property int draftGen: 0               // bumps when the buffer is replaced from outside the fields, so they re-read it
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
        if (store.pendingMode === "create") { store.pendingMode = ""; startCreate(); }
        else if (store.activeKey !== "") { selectedId = store.draftId; mode = "editor"; }   // the editor was open when the popup closed
    }
    Component.onDestruction: store.stash()   // save the open draft right away instead of 2 s later

    // ---- helpers
    function title(g) { return g.description !== "" ? g.description : (g.files.length ? g.files[0].filename : g.id) }
    function draftTitle(d) {
        const named = d.files.find(f => f.name.trim() !== "");
        return d.desc.trim() !== "" ? d.desc.trim() : named ? named.name : Translation.tr("Untitled gist");
    }
    function ago(iso) {
        if (!iso) return "";
        const s = (now - Date.parse(iso)) / 1000;
        if (s < 60) return Translation.tr("just now");
        if (s < 3600) return `${Math.floor(s / 60)} min ago`;
        if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
        if (s < 86400 * 30) return `${Math.floor(s / 86400)} d ago`;
        return new Date(iso).toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }
    // GitHub-style inline diff (line LCS): [{t: " " | "+" | "-", s}]. Very large files fall back to "all removed, all added".
    function diffLines(a, b) {
        const A = a === "" ? [] : a.split("\n"), B = b === "" ? [] : b.split("\n");
        let p = 0; while (p < A.length && p < B.length && A[p] === B[p]) p++;
        let q = 0; while (q < A.length - p && q < B.length - p && A[A.length - 1 - q] === B[B.length - 1 - q]) q++;
        const a2 = A.slice(p, A.length - q), b2 = B.slice(p, B.length - q), n = a2.length, m = b2.length, mid = [];
        if (n * m > 4000000) { for (const s of a2) mid.push({ t: "-", s }); for (const s of b2) mid.push({ t: "+", s }); }
        else {
            const L = []; for (let i = 0; i <= n; i++) L.push(new Int32Array(m + 1));
            for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) L[i][j] = a2[i] === b2[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
            let i = 0, j = 0;
            while (i < n && j < m) {
                if (a2[i] === b2[j]) { mid.push({ t: " ", s: a2[i] }); i++; j++; }
                else if (L[i + 1][j] >= L[i][j + 1]) mid.push({ t: "-", s: a2[i++] });
                else mid.push({ t: "+", s: b2[j++] });
            }
            while (i < n) mid.push({ t: "-", s: a2[i++] }); while (j < m) mid.push({ t: "+", s: b2[j++] });
        }
        // keep 3 lines of context around changes, like GitHub
        const all = A.slice(0, p).map(s => ({ t: " ", s })).concat(mid, A.slice(A.length - q).map(s => ({ t: " ", s })));
        const keep = all.map(() => false);
        all.forEach((l, k) => { if (l.t !== " ") for (let x = Math.max(0, k - 3); x <= Math.min(all.length - 1, k + 3); x++) keep[x] = true; });
        const out = []; let gap = false;
        all.forEach((l, k) => { if (keep[k]) { out.push(l); gap = false; } else if (!gap) { out.push({ t: "@", s: "⋯" }); gap = true; } });
        return out;
    }
    // per file of a draft vs the GitHub version: [{name, status: added|removed|renamed|modified, lines}]
    function draftDiff(d, g) {
        const out = [];
        if (!d || !g) return out;
        if ((d.desc ?? "") !== g.description) out.push({ name: Translation.tr("Description"), status: "modified", lines: diffLines(g.description, d.desc) });
        for (const f of d.files) {
            const o = g.files.find(x => x.filename === f.orig);
            if (!o) { out.push({ name: f.name, status: "added", lines: diffLines("", f.content) }); continue; }
            const renamed = f.name !== f.orig, changed = !f.locked && f.content !== o.content;
            if (!renamed && !changed) continue;
            out.push({ name: renamed ? `${f.orig} → ${f.name}` : f.name, status: renamed && !changed ? "renamed" : "modified", lines: changed ? diffLines(o.content, f.content) : [] });
        }
        for (const r of d.removed ?? []) { const o = g.files.find(x => x.filename === r); out.push({ name: r, status: "removed", lines: diffLines(o?.content ?? "", "") }); }
        return out;
    }
    function fmtSize(b) { return b >= 1048576 ? (b / 1048576).toFixed(1) + " MB" : b >= 1024 ? (b / 1024).toFixed(1) + " KB" : b + " B" }
    function allContent(g) { return g.files.length === 1 ? g.files[0].content : g.files.map(f => `// ${f.filename}\n${f.content}`).join("\n\n") }
    function flash(text) { notice = text; noticeTimer.restart() }
    Timer { id: noticeTimer; interval: 2500; onTriggered: root.notice = "" }
    function copy(text, what) { Quickshell.clipboardText = text; flash(what) }

    // ---- list: draft rows (new gists, or drafts of gists deleted on GitHub) first, then gists. All words must match.
    readonly property var hay: store.gists.map(g => ({
        meta: `${g.description} ${g.id} ${g.files.map(f => f.filename + " " + f.language).join(" ")}`.toLowerCase(),
        content: g.files.map(f => f.content.toLowerCase())
    }))
    readonly property var entries: {
        const words = query.trim().toLowerCase().split(/\s+/).filter(w => w !== "");
        const drafts = store.drafts, out = [];
        if (visibility === "all" || visibility === "drafts") {
            const rows = [];
            for (const k in drafts) {
                const d = drafts[k];
                const orphan = d.mode === "edit" && !store.gistById(d.id);
                if (d.mode !== "create" && !orphan) continue;
                const h = `${d.desc} ${d.files.map(f => f.name + " " + f.content).join(" ")}`.toLowerCase();
                if (words.every(w => h.includes(w))) rows.push({ type: "draft", d: d, orphan: orphan });
            }
            rows.sort((a, b) => (b.d.savedAt ?? "").localeCompare(a.d.savedAt ?? ""));
            out.push(...rows);
        }
        const gistRows = [];
        store.gists.forEach((g, gi) => {
            if (visibility === "public" && !g.public) return;
            if (visibility === "secret" && g.public) return;
            if (visibility === "drafts" && !drafts[g.id]) return;
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
            gistRows.push({ type: "gist", g: g, excerpt: excerpt });
        });
        if (sortKey === "name") gistRows.sort((a, b) => title(a.g).localeCompare(title(b.g)));
        else if (sortKey === "created") gistRows.sort((a, b) => b.g.created_at.localeCompare(a.g.created_at));
        else gistRows.sort((a, b) => b.g.updated_at.localeCompare(a.g.updated_at));
        out.push(...gistRows);
        return out;
    }

    // ---- navigation
    function openGist(id) { selectedId = id; confirmDelete = false; mode = "view"; Qt.callLater(() => keyScope.forceActiveFocus()) }
    function toList() { mode = "list"; selectedId = ""; confirmDelete = false; Qt.callLater(() => filterInput.forceActiveFocus()) }
    function openEntry(e) { if (e.type === "draft") openDraft(e.d.key); else openGist(e.g.id) }
    function enterEditor() { formError = ""; overwriteArmed = false; confirmDelete = false; draftGen++; mode = "editor" }
    function startCreate() {
        store.beginCreate(); selectedId = ""; enterEditor();
        Qt.callLater(() => desc.input.forceActiveFocus());
    }
    function startEdit(g) { store.beginEdit(g); selectedId = g.id; enterEditor() }
    function openDraft(key) { store.openDraft(key); selectedId = store.draftId; enterEditor() }
    // Back from the editor keeps any changes as a draft (marked in the list); only Discard throws them away.
    function leaveEditor() {
        const key = store.activeKey;
        store.closeEditor();
        if (store.drafts[key]) flash(Translation.tr("Kept as a draft"));
        toList();
    }
    function discard(key) {
        const wasOpen = mode === "editor" && key === store.activeKey;
        store.discardDraft(key);
        confirmDiscardKey = "";
        flash(Translation.tr("Draft discarded"));
        if (wasOpen) toList();
    }
    function back() {
        if (menuGist) { menuGist = null; return; }
        if (confirmDiscardKey !== "") { confirmDiscardKey = ""; return; }
        if (confirmDelete) { confirmDelete = false; return; }
        if (mode === "editor") { if (!store.busy) leaveEditor(); }
        else if (mode === "view") toList();
        else if (query !== "") filterInput.text = "";
        else root.visible = false;
    }

    // ---- save: publishes the open draft; the editor stays open on the saved gist
    function save() {
        if (store.busy || mode !== "editor") return;
        formError = "";
        const d = store.draft;
        if (d.count === 0) { formError = Translation.tr("A gist needs at least one file."); return; }
        if (!store.changed) { formError = Translation.tr("No changes to save."); return; }
        let renamed = false;
        for (let i = 0; i < d.count; i++) {   // the names GitHub will store, so the fields show them too
            const n = d.get(i).name, t = n.trim() !== "" ? n.trim() : `gistfile${i + 1}.txt`;
            if (t !== n) { d.setProperty(i, "name", t); renamed = true; }
        }
        if (store.draftDesc !== store.draftDesc.trim()) { store.draftDesc = store.draftDesc.trim(); renamed = true; }
        if (renamed) { draftGen++; store.touchDraft(); }
        const files = {}, seen = {};
        for (let i = 0; i < d.count; i++) {
            const f = d.get(i);
            if (seen[f.name]) { formError = Translation.tr("Two files are named \"%1\".").arg(f.name); return; }
            seen[f.name] = true;
            if (!f.locked && f.content.trim() === "") { formError = Translation.tr("\"%1\" is empty; GitHub doesn't allow empty files.").arg(f.name); return; }
            if (store.draftMode === "create" || f.orig === "") { files[f.name] = { content: f.content }; continue; }
            const e = {};   // only what you changed: files you didn't touch keep whatever GitHub has
            if (f.name !== f.orig) e.filename = f.name;
            if (!f.locked && f.content !== f.origContent) e.content = f.content;
            if (Object.keys(e).length) files[f.orig] = e;
        }
        for (const r of store.removedFiles) files[r] = null;
        if (store.draftMode === "create") {
            store.publish(["create"], JSON.stringify({ description: store.draftDesc, public: store.draftPublic, files: files }), (ok, id) => {
                if (!ok) return;
                if (mode === "editor") selectedId = id;
                flash(Translation.tr("Gist created · link copied"));
            });
            return;
        }
        if (current && store.draftBase !== "" && current.updated_at !== store.draftBase && !overwriteArmed) {
            overwriteArmed = true;
            formError = Translation.tr("This gist changed on GitHub (%1) after you started editing. Save again to apply your changes; files you edited replace the GitHub versions.").arg(ago(current.updated_at));
            return;
        }
        const payload = { description: store.draftDesc };
        if (Object.keys(files).length) payload.files = files;
        store.publish(["update", store.draftId], JSON.stringify(payload), ok => {
            if (!ok) return;
            overwriteArmed = false;
            flash(Translation.tr("Saved to GitHub"));
        });
    }
    function remove() {
        store.removeGist(selectedId, ok => {
            if (!ok) { confirmDelete = false; return; }
            toList(); flash(Translation.tr("Gist deleted"));
        });
    }
    function addFile() { store.draft.append({ orig: "", name: "", content: "", origContent: "", locked: false }); store.touchDraft() }
    function removeFile(i) {
        const o = store.draft.get(i).orig;
        if (o !== "") store.removedFiles = store.removedFiles.concat([o]);
        store.draft.remove(i); store.touchDraft();
    }
    Process {  // "Paste" in the editor: the clipboard into the first empty file (or a new one)
        id: pasteProc
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === "") return;
                const d = root.store.draft;
                let i = -1;
                for (let k = 0; k < d.count; k++) if (!d.get(k).locked && d.get(k).content.trim() === "") { i = k; break; }
                if (i < 0) { root.addFile(); i = d.count - 1; }
                d.setProperty(i, "content", text);
                root.store.touchDraft();
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
            opacity: ib.enabled ? 1 : 0.4
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
    component DraftPill: Rectangle {  // "Draft" marker on list rows
        implicitHeight: pillRow.implicitHeight + 4
        implicitWidth: pillRow.implicitWidth + 12
        radius: Appearance.rounding.full
        color: Appearance.colors.colTertiaryContainer
        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 3
            MaterialSymbol { text: "edit_note"; iconSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnTertiaryContainer }
            StyledText { text: Translation.tr("Draft"); font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.Medium; color: Appearance.colors.colOnTertiaryContainer }
        }
    }
    // Text cursor: shown at once when a field gets focus or the cursor moves, then blinks (Qt's own cursor could start
    // in its "off" phase, so it appeared only after a delay).
    component Caret: Rectangle {
        id: caret
        width: 2
        color: Appearance.colors.colPrimary
        visible: !!parent && parent.activeFocus && !parent.readOnly && parent.selectionStart === parent.selectionEnd
        function wake() { opacity = 1; blink.restart() }
        onVisibleChanged: if (visible) wake()
        Connections {
            target: caret.parent
            ignoreUnknownSignals: true
            function onCursorPositionChanged() { caret.wake() }
            function onTextChanged() { caret.wake() }
        }
        Timer { id: blink; interval: 530; repeat: true; running: caret.visible; onTriggered: caret.opacity = caret.opacity > 0 ? 0 : 1 }
    }
    component Field: Rectangle {  // single-line input in a pill, like the task manager's filter
        id: fld
        property alias input: fieldInput
        property string placeholder
        property bool mono: false
        signal edited(string text)
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
            cursorDelegate: Component { Caret {} }
            onTextChanged: fld.edited(text)
            StyledText {
                visible: fieldInput.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: fld.placeholder
                color: Appearance.colors.colSubtext
            }
        }
    }
    component ConfirmBar: Rectangle {  // inline "are you sure" row (delete gist, discard draft)
        id: cb
        property string text
        property string action
        property bool busy: false
        signal confirmed()
        signal cancelled()
        Layout.fillWidth: true
        implicitHeight: cbRow.implicitHeight + 16
        radius: Appearance.rounding.small
        color: Appearance.colors.colErrorContainer
        RowLayout {
            id: cbRow
            anchors { fill: parent; margins: 8; leftMargin: 12 }
            spacing: 8
            StyledText { Layout.fillWidth: true; wrapMode: Text.Wrap; text: cb.text; color: Appearance.colors.colOnErrorContainer }
            Chip { label: Translation.tr("Cancel"); onClicked: cb.cancelled() }
            RippleButton {
                implicitHeight: 30; implicitWidth: cbText.implicitWidth + 24
                buttonRadius: Appearance.rounding.full
                colBackground: "#d32f2f"; colBackgroundHover: "#e53935"
                enabled: !cb.busy
                onClicked: cb.confirmed()
                contentItem: StyledText { id: cbText; horizontalAlignment: Text.AlignHCenter; text: cb.action; color: "white" }
            }
        }
    }

    property real openedAt: Date.now()
    // Clicks on the bar pass through the click-away layer (it covers everything below the bar), so one click on another bar
    // button both reaches that button and closes this popup: close when something else opens (a popup or the sidebar
    // layer, the AI panel's special workspace, another workspace).
    Connections {
        target: Hyprland
        enabled: true
        function onRawEvent(event) {
            if (Date.now() - root.openedAt < 600) return;   // our own layers opening
            if (["activespecial", "workspacev2"].includes(event.name)
                || (event.name === "openlayer" && event.data !== "quickshell:popup-dismiss")) root.visible = false
        }
    }
    // Same geometry as the Docker/task-manager popups: left edge like the left sidebar, full height below the bar.
    // A click-away layer closes it (a click anywhere, including the bar button).
    PanelWindow {
        screen: root.screen ?? Quickshell.screens[0]
        mask: Region { item: root.visible ? belowBar : null }
        color: "transparent"
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:popup-dismiss"
        WlrLayershell.layer: WlrLayer.Top
        Item { id: belowBar; x: 0; y: Config.options.bar.bottom ? 0 : Appearance.sizes.barHeight; width: parent.width; height: parent.height - Appearance.sizes.barHeight }
        MouseArea { id: dismissArea; anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.visible = false }
    }
    PanelWindow {
        id: win
        screen: root.screen ?? Quickshell.screens[0]
        color: "transparent"
        anchors { top: true; left: true; bottom: true }
        implicitWidth: 480 + Appearance.sizes.hyprlandGapsOut + Appearance.sizes.elevationMargin
        mask: Region { item: card }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:sidebarLeft"  // same Hyprland layer rule (slide left) as the left sidebar
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        Component.onCompleted: if (root.mode === "list") filterInput.forceActiveFocus()
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
        // Esc = back/close (the editor keeps your draft), Ctrl+S = save, Ctrl+N = new gist (fields don't consume these)
        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier;
            if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true; }
            else if (ctrl && event.key === Qt.Key_S && root.mode === "editor") { root.save(); event.accepted = true; }
            else if (ctrl && event.key === Qt.Key_N) { root.startCreate(); event.accepted = true; }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                IconBtn {
                    visible: root.mode !== "list"
                    symbol: "arrow_back"
                    tip: root.mode === "editor" ? Translation.tr("Back (Esc) · keeps your changes as a draft") : Translation.tr("Back (Esc)")
                    enabled: !(root.mode === "editor" && root.store.busy)
                    onClicked: root.back()
                }
                MaterialSymbol { visible: root.mode === "list"; text: "note_stack"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colOnLayer2 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.mode === "editor" ? (root.store.draftMode === "create" ? Translation.tr("New gist")
                                                         : root.current ? root.title(root.current) : Translation.tr("Edit gist"))
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
                               : `${root.store.gists.length} ${Translation.tr("gists")}`
                                 + (root.store.draftCount ? ` · ${root.store.draftCount} ${root.store.draftCount === 1 ? Translation.tr("draft") : Translation.tr("drafts")}` : "")
                                 + (root.store.lastSync ? ` · ${Translation.tr("synced")} ${root.ago(root.store.lastSync)}` : ""))
                            : root.mode === "editor"
                                ? (root.store.draftMode === "create" ? Translation.tr("Not on GitHub until you create it")
                                   : !root.current ? Translation.tr("This gist no longer exists on GitHub")
                                   : `${Translation.tr("Editing")} · ${root.current.public ? Translation.tr("Public") : Translation.tr("Secret")}`)
                            : root.current
                                ? `${root.current.public ? Translation.tr("Public") : Translation.tr("Secret")} · ${root.current.files.length} ${root.current.files.length === 1 ? Translation.tr("file") : Translation.tr("files")} · ${Translation.tr("updated")} ${root.ago(root.current.updated_at)}`
                                : ""
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
                IconBtn { visible: root.mode === "view" && !!root.current; symbol: "link"; tip: Translation.tr("Copy link"); onClicked: root.copy(root.current.html_url, Translation.tr("Link copied")) }
                IconBtn { visible: root.mode === "view" && !!root.current; symbol: "open_in_new"; tip: Translation.tr("Open on GitHub"); onClicked: Qt.openUrlExternally(root.current.html_url) }
                IconBtn {
                    visible: root.mode === "view" && !!root.current
                    symbol: "edit"; tip: root.store.drafts[root.selectedId] ? Translation.tr("Continue your draft") : Translation.tr("Edit")
                    onClicked: root.startEdit(root.current)
                }
                IconBtn { visible: root.mode === "view" && !!root.current; symbol: "delete"; tip: Translation.tr("Delete"); iconColor: "#ef5350"; onClicked: root.confirmDelete = true }
                // editor actions; Save is the primary action, top right
                IconBtn { visible: root.mode === "editor"; symbol: "content_paste"; tip: Translation.tr("Paste clipboard into a file"); onClicked: pasteProc.running = true }
                IconBtn { visible: root.mode === "editor"; symbol: "note_add"; tip: Translation.tr("Add file"); onClicked: root.addFile() }
                IconBtn {
                    visible: root.mode === "editor" && (root.store.changed || !!root.store.drafts[root.store.activeKey])
                    symbol: "delete"
                    tip: root.store.draftMode === "create" ? Translation.tr("Discard draft") : Translation.tr("Discard changes")
                    iconColor: Appearance.colors.colSubtext
                    onClicked: root.confirmDiscardKey = root.store.activeKey
                }
                RippleButton {
                    id: saveBtn
                    visible: root.mode === "editor"
                    readonly property bool ready: root.store.changed && !root.store.busy
                    implicitHeight: 32; implicitWidth: saveRow.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: ready ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: ready ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2
                    enabled: ready
                    onClicked: root.save()
                    contentItem: RowLayout {
                        id: saveRow
                        spacing: 4
                        MaterialSymbol {
                            text: root.store.draftMode === "create" ? "cloud_upload" : "save"
                            iconSize: Appearance.font.pixelSize.larger
                            color: saveBtn.ready ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: root.store.busy ? Translation.tr("Saving…") : root.store.draftMode === "create" ? Translation.tr("Create") : Translation.tr("Save")
                            font.weight: Font.Medium
                            color: saveBtn.ready ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        }
                    }
                    StyledToolTip {
                        text: root.store.changed ? "Ctrl+S" : Translation.tr("No unsaved changes")
                        visible: saveBtn.hovered
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }

            ConfirmBar {
                visible: root.confirmDelete && root.mode === "view"
                text: Translation.tr("Delete this gist on GitHub? This can't be undone.")
                action: root.store.busy ? Translation.tr("Deleting…") : Translation.tr("Delete")
                busy: root.store.busy
                onConfirmed: root.remove()
                onCancelled: root.confirmDelete = false
            }
            ConfirmBar {
                readonly property var d: root.store.drafts[root.confirmDiscardKey] ?? null
                readonly property bool isNew: d ? d.mode === "create" : root.store.draftMode === "create"
                visible: root.confirmDiscardKey !== ""
                text: isNew ? Translation.tr("Discard this draft? It was never saved to GitHub.")
                            : Translation.tr("Discard your unsaved changes? The gist on GitHub stays as it is.")
                action: Translation.tr("Discard")
                onConfirmed: root.discard(root.confirmDiscardKey)
                onCancelled: root.confirmDiscardKey = ""
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
                        id: filterInput
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        clip: true
                        cursorDelegate: Component { Caret {} }
                        onTextChanged: root.query = text
                        Keys.onEscapePressed: root.back()
                        Keys.onReturnPressed: if (root.entries.length) root.openEntry(root.entries[0])
                        Keys.onEnterPressed: if (root.entries.length) root.openEntry(root.entries[0])
                        StyledText {
                            visible: filterInput.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Filter by description, file, language or content…")
                            color: Appearance.colors.colSubtext
                        }
                    }
                    IconBtn { visible: filterInput.text !== ""; symbol: "close"; implicitWidth: 26; implicitHeight: 26; onClicked: filterInput.text = "" }
                }
            }
            RowLayout {
                visible: root.mode === "list"
                Layout.fillWidth: true
                spacing: 4
                Chip { label: Translation.tr("All"); active: root.visibility === "all"; onClicked: root.visibility = "all" }
                Chip { label: Translation.tr("Public"); active: root.visibility === "public"; onClicked: root.visibility = "public" }
                Chip { label: Translation.tr("Secret"); active: root.visibility === "secret"; onClicked: root.visibility = "secret" }
                Chip {
                    visible: root.store.draftCount > 0 || root.visibility === "drafts"
                    label: Translation.tr("Drafts")
                    active: root.visibility === "drafts"
                    onClicked: root.visibility = "drafts"
                }
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
                model: root.entries
                boundsBehavior: Flickable.StopAtBounds
                // One row type for both: a gist (with a Draft pill if you have unsaved changes to it) or a draft of a new gist
                delegate: RippleButton {
                    id: rowBtn
                    required property var modelData
                    readonly property bool isDraft: modelData.type === "draft"
                    readonly property var g: modelData.g ?? null
                    readonly property var d: isDraft ? modelData.d : (root.store.drafts[g.id] ?? null)
                    width: list.width
                    implicitHeight: rowCol.implicitHeight + 16
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.openEntry(modelData)
                    altAction: () => {
                        if (rowBtn.isDraft) { root.confirmDiscardKey = rowBtn.d.key; return; }
                        const p = rowBtn.mapToItem(card, rowBtn.width - 220, rowBtn.height / 2);
                        root.menuX = p.x; root.menuY = p.y; root.menuGist = rowBtn.g;
                    }
                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 2
                            Layout.leftMargin: 4
                            text: rowBtn.isDraft ? "edit_note" : rowBtn.g.public ? "public" : "lock"
                            iconSize: Appearance.font.pixelSize.larger
                            color: rowBtn.isDraft ? Appearance.colors.colTertiary : rowBtn.g.public ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            id: rowCol
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                StyledText {
                                    Layout.fillWidth: true
                                    text: rowBtn.isDraft ? root.draftTitle(rowBtn.d) : root.title(rowBtn.g)
                                    font.weight: Font.Medium
                                    font.italic: rowBtn.isDraft
                                    elide: Text.ElideRight
                                    color: Appearance.colors.colOnLayer2
                                }
                                DraftPill { visible: rowBtn.d !== null }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: rowBtn.isDraft
                                    ? `${rowBtn.modelData.orphan ? Translation.tr("Gist deleted on GitHub") : Translation.tr("New gist")} · ${Translation.tr("saved on this computer")} ${root.ago(rowBtn.d.savedAt)}`
                                    : `${rowBtn.g.files.map(f => f.filename).join(", ")} · ${root.ago(rowBtn.g.updated_at)}`
                                      + (rowBtn.d ? ` · ${Translation.tr("unsaved changes")} ${root.ago(rowBtn.d.savedAt)}` : "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                elide: Text.ElideRight
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {  // where a content match was found
                                visible: !rowBtn.isDraft && rowBtn.modelData.excerpt !== ""
                                Layout.fillWidth: true
                                text: rowBtn.modelData.excerpt ?? ""
                                textFormat: Text.PlainText
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.monospace
                                elide: Text.ElideRight
                                color: Appearance.colors.colPrimary
                            }
                            Flow {
                                visible: !rowBtn.isDraft
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: rowBtn.isDraft ? [] : [...new Set(rowBtn.g.files.map(f => f.language).filter(l => l !== ""))]
                                    delegate: LangChip { required property string modelData; text: modelData }
                                }
                            }
                        }
                        IconBtn {
                            Layout.alignment: Qt.AlignVCenter
                            symbol: rowBtn.isDraft ? "delete" : "content_copy"
                            tip: rowBtn.isDraft ? Translation.tr("Discard draft") : Translation.tr("Copy content")
                            iconColor: Appearance.colors.colSubtext
                            onClicked: {
                                if (rowBtn.isDraft) root.confirmDiscardKey = rowBtn.d.key;
                                else root.copy(root.allContent(rowBtn.g), Translation.tr("Content copied"));
                            }
                        }
                    }
                }

                ColumnLayout {  // empty states
                    anchors.centerIn: parent
                    width: parent.width - 40
                    visible: root.entries.length === 0
                    spacing: 10
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.store.gists.length === 0 && root.store.syncing ? "sync" : root.store.gists.length === 0 ? "note_stack" : "search_off"
                        iconSize: 48
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                        text: root.visibility === "drafts" ? Translation.tr("No drafts")
                            : root.store.gists.length > 0 ? Translation.tr("No gists match")
                            : root.store.syncing ? Translation.tr("Loading your gists…")
                            : root.store.syncError !== "" ? root.store.syncError
                            : Translation.tr("No gists yet. Press + or Ctrl+N to create one.")
                    }
                }
            }

            // ---------------- view ----------------
            Rectangle {  // you have a draft for this gist
                id: viewDraft
                readonly property var d: root.store.drafts[root.selectedId] ?? null
                visible: root.mode === "view" && d !== null
                Layout.fillWidth: true
                implicitHeight: draftRow.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colTertiaryContainer
                RowLayout {
                    id: draftRow
                    anchors { fill: parent; margins: 8; leftMargin: 12 }
                    spacing: 8
                    MaterialSymbol { text: "edit_note"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnTertiaryContainer }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("Unsaved changes (%1), compared with GitHub below.").arg(root.ago(viewDraft.d?.savedAt ?? ""))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnTertiaryContainer
                    }
                    Chip { label: Translation.tr("Discard"); onClicked: root.confirmDiscardKey = root.selectedId }
                    Chip { label: Translation.tr("Continue"); active: true; onClicked: root.startEdit(root.current) }
                }
            }
            StyledListView {  // draft vs GitHub, inline diff
                id: diffList
                visible: root.mode === "view" && viewDraft.d !== null
                animateAppearance: false
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 12
                model: visible ? root.draftDiff(viewDraft.d, root.current) : []
                boundsBehavior: Flickable.StopAtBounds
                delegate: ColumnLayout {
                    id: dItem
                    required property var modelData
                    width: diffList.width
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialSymbol { text: "description"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colSubtext }
                        StyledText { Layout.fillWidth: true; text: dItem.modelData.name; font.family: Appearance.font.family.monospace; font.weight: Font.Medium; elide: Text.ElideMiddle; color: Appearance.colors.colOnLayer2 }
                        StyledText {
                            text: dItem.modelData.status === "added" ? Translation.tr("new file") : dItem.modelData.status === "removed" ? Translation.tr("deleted")
                                : dItem.modelData.status === "renamed" ? Translation.tr("renamed") : `+${dItem.modelData.lines.filter(l => l.t === "+").length} −${dItem.modelData.lines.filter(l => l.t === "-").length}`
                            font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance.font.family.monospace
                            color: dItem.modelData.status === "removed" ? "#ef5350" : "#4caf50"
                        }
                    }
                    Rectangle {
                        visible: dItem.modelData.lines.length > 0
                        Layout.fillWidth: true
                        implicitHeight: dCol.implicitHeight + 8
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer0
                        clip: true
                        Column {
                            id: dCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 4 }
                            Repeater {
                                model: dItem.modelData.lines
                                delegate: Rectangle {
                                    required property var modelData
                                    width: dCol.width
                                    implicitHeight: lineText.implicitHeight + 2
                                    color: modelData.t === "+" ? Qt.rgba(0.18, 0.63, 0.26, 0.22) : modelData.t === "-" ? Qt.rgba(0.85, 0.2, 0.2, 0.22)
                                         : modelData.t === "@" ? Appearance.colors.colLayer1 : "transparent"
                                    Text {
                                        id: lineText
                                        anchors { left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                        text: (parent.modelData.t === "@" ? "" : parent.modelData.t + " ") + parent.modelData.s
                                        wrapMode: Text.WrapAnywhere
                                        textFormat: Text.PlainText
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: parent.modelData.t === "@" ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
                                    }
                                }
                            }
                        }
                    }
                }
            }
            StyledListView {
                id: fileList
                visible: root.mode === "view" && viewDraft.d === null
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

            // ---------------- editor (create / edit) ----------------
            StyledFlickable {
                id: edFlick
                visible: root.mode === "editor"
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
                        Component.onCompleted: desc.input.text = root.store.draftDesc
                    }
                    RowLayout {
                        id: visRow
                        Layout.fillWidth: true
                        spacing: 4
                        readonly property bool isNew: root.store.draftMode === "create"
                        Chip { visible: visRow.isNew || !root.store.draftPublic; label: Translation.tr("Secret"); active: !root.store.draftPublic; onClicked: if (visRow.isNew) { root.store.draftPublic = false; root.store.touchDraft(); } }
                        Chip { visible: visRow.isNew || root.store.draftPublic; label: Translation.tr("Public"); active: root.store.draftPublic; onClicked: if (visRow.isNew) { root.store.draftPublic = true; root.store.touchDraft(); } }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            wrapMode: Text.Wrap
                            text: !visRow.isNew ? Translation.tr("GitHub can't change a gist's visibility after creation.")
                                : root.store.draftPublic ? Translation.tr("Listed on your profile and searchable.")
                                : Translation.tr("Unlisted: only people with the link can see it.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Repeater {
                        model: root.store.draft
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
                                    onEdited: text => { if (text !== fileEd.name) { root.store.draft.setProperty(fileEd.index, "name", text); root.store.touchDraft(); } }
                                    Connections { target: root; function onDraftGenChanged() { nameField.input.text = root.store.draft.get(fileEd.index)?.name ?? "" } }
                                    Component.onCompleted: nameField.input.text = fileEd.name
                                }
                                IconBtn {
                                    visible: root.store.draft.count > 1
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
                                    cursorDelegate: Component { Caret {} }
                                    onTextChanged: if (!fileEd.locked && text !== fileEd.content) { root.store.draft.setProperty(fileEd.index, "content", text); root.store.touchDraft(); }
                                    onCursorRectangleChanged: if (activeFocus) edFlick.reveal(area, cursorRectangle)
                                    Connections { target: root; function onDraftGenChanged() { area.text = root.store.draft.get(fileEd.index)?.content ?? "" } }
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

            // Footer: error or confirmation, else the draft state, else hints
            StyledText {
                readonly property bool isError: (root.formError !== "" && root.mode === "editor") || root.store.actError !== ""
                Layout.fillWidth: true
                horizontalAlignment: root.mode === "editor" && !isError ? Text.AlignLeft : Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.formError !== "" && root.mode === "editor" ? root.formError
                    : root.store.actError !== "" ? root.store.actError
                    : root.notice !== "" ? root.notice
                    : root.mode === "editor"
                        ? (root.store.changed
                            ? (root.store.savedAt !== "" ? Translation.tr("Unsaved changes · draft kept on this computer (%1)").arg(root.ago(root.store.savedAt))
                                                         : Translation.tr("Unsaved changes"))
                              + " · " + Translation.tr("Esc goes back and keeps the draft")
                            : root.store.draftMode === "edit" ? Translation.tr("No unsaved changes") : Translation.tr("Ctrl+S creates the gist"))
                    : root.mode === "list" ? Translation.tr("Enter opens the first match · Ctrl+N new · right-click a gist for actions")
                    : Translation.tr("Select text to copy part of a file · Esc goes back")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: isError ? "#ef5350" : root.notice !== "" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
        }

        // Right-click menu for a gist row (overlay inside the card)
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
                        { icon: "edit", label: root.menuGist && root.store.drafts[root.menuGist.id] ? Translation.tr("Continue draft") : Translation.tr("Edit"), act: "edit" },
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
                            else if (modelData.act === "edit") root.startEdit(g);
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
