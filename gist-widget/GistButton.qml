import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Quickshell.Hyprland

// Bar button for the Gist widget: your GitHub gists (gh) mirrored in a local cache by gist-widget.sh, plus local notes: plain
// files in a folder (gist-local.py) that list, filter, edit and draft like gists but stay on this computer until uploaded.
// Settings (the panel's gear): the local notes folder and the drafts folder, in ~/.config/gist-widget/settings.json.
// Syncs in the background every 30 minutes and on open if the last sync is older than 5 minutes (loader line under the icon while it runs).
// Unsaved create/edit drafts are kept locally (never sent to GitHub before Save) and survive restarts.
// Left click = side panel (list/filter, view, create, edit), right click = menu (new, secret gist from clipboard, sync, open GitHub).
// Panel and menu behavior (open/close, click-away, monitors) comes from WidgetBase; the panel content only exists while open.
WidgetBase {
    id: root
    iconName: ""   // draws its own GitHub mark below
    panelId: "gist"
    readonly property bool pinned: open || menuOpen   // keeps the icon shown in the sliding bar row (zbar-reveal) while in use
    property var gists: []                 // index.json: [{id, description, public, html_url, created_at, updated_at, files: [{filename, language, size, content, truncated, clipped}]}]
    property bool syncing: syncProc.running
    property string lastSync: ""           // ISO time of the last successful sync
    property string syncError: ""
    property bool busy: actProc.running     // a create/update/delete/clip is running
    property string actError: ""
    property var _onDone: null
    property var localGists: []            // gist-local.py index: same shape, ids "local:<name>", local: true, html_url/raw_url = paths
    readonly property var allGists: localGists.concat(gists)
    function gistById(id) { return allGists.find(g => g.id === id) ?? null }

    // ---- Settings
    readonly property string home: Quickshell.env("HOME")
    readonly property string defaultLocalDir: `${home}/Documents/Gists`
    readonly property string defaultDraftDir: `${home}/.local/state/gist-widget`
    property string localDir: defaultLocalDir
    property string draftDir: defaultDraftDir
    function expand(p) { p = p.trim(); return p === "~" ? home : p.startsWith("~/") ? home + p.slice(1) : p }
    function saveSettings(local, drafts) {
        localDir = expand(local) || defaultLocalDir;
        draftDir = expand(drafts) || defaultDraftDir;
        Quickshell.execDetached(["mkdir", "-p", `${home}/.config/gist-widget`]);
        settingsFile.setText(JSON.stringify({ localDir, draftDir }, null, 1));
    }
    FileView {
        id: settingsFile
        path: `${root.home}/.config/gist-widget/settings.json`
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const j = JSON.parse(text());
                if (typeof j.localDir === "string" && j.localDir.trim() !== "") root.localDir = root.expand(j.localDir);
                if (typeof j.draftDir === "string" && j.draftDir.trim() !== "") root.draftDir = root.expand(j.draftDir);
            } catch (e) {}
        }
    }

    // ---- Local notes: rescanned on open, every 15 s while open, after every action and when the folder changes
    property string localError: ""
    readonly property string localScript: `${home}/.config/hypr/custom/gist-local.py`
    property bool _rescan: false
    function scanLocal() { if (localProc.running) _rescan = true; else localProc.running = true }
    onLocalDirChanged: { localGists = []; scanLocal() }
    Process {
        id: localProc
        command: ["python3", root.localScript, "index", root.localDir]
        stdout: StdioCollector { id: localOut }
        stderr: StdioCollector { id: localErr }
        onExited: code => {
            if (code === 0) { try { root.localGists = JSON.parse(localOut.text); root.localError = ""; } catch (e) {} }
            else root.localError = localErr.text.trim().split("\n").pop() || `local notes: failed (${code})`;
            if (root._rescan) { root._rescan = false; running = true; }
        }
    }

    // ---- Drafts. Creating and editing always happen in a draft; nothing goes to GitHub until Save. Drafts are keyed by
    // gist id ("new-<time>" for a new gist), survive going back and closing the popup, and are autosaved locally 2 s after
    // a change (~/.local/state/gist-widget/drafts-<screen>.json, 0700; one file per screen's bar), so a restart keeps them.
    // The editor works on one draft at a time through the buffer below; a draft without changes is dropped.
    property var drafts: ({})              // key -> {key, mode, id, base, origDesc, desc, public, removed, files: [{orig, name, content, origContent, locked}], savedAt}
    readonly property int draftCount: Object.keys(drafts).length
    property string activeKey: ""          // draft open in the editor ("" = editor closed)
    property ListModel draft: ListModel {} // buffer: the open draft's files (orig = name on GitHub, "" for a new file; locked = only partly loaded)
    property string draftMode: ""          // create | edit
    property bool draftLocal: false        // a local note (create: saved as files, not on GitHub)
    property string draftId: ""
    property string draftBase: ""          // the gist's updated_at when editing started (Save warns if GitHub has a newer version)
    property string origDesc: ""
    property string draftDesc: ""
    property bool draftPublic: false
    property var removedFiles: []
    property int draftTick: 0              // bumps on every change so `changed` re-evaluates
    readonly property bool changed: { draftTick; return activeKey !== "" && bufferChanged() }
    readonly property string savedAt: drafts[activeKey]?.savedAt ?? ""

    function bufferChanged() {
        if (draftMode === "create") {
            if (draftDesc.trim() !== "") return true;
            for (let i = 0; i < draft.count; i++) { const d = draft.get(i); if (d.name.trim() !== "" || d.content.trim() !== "") return true; }
            return false;
        }
        if (draftDesc !== origDesc || removedFiles.length > 0) return true;
        for (let i = 0; i < draft.count; i++) {
            const d = draft.get(i);
            if (d.orig === "" || d.name !== d.orig || (!d.locked && d.content !== d.origContent)) return true;
        }
        return false;
    }
    function loadBuffer(d) {
        draft.clear();
        for (const f of d.files ?? []) draft.append({ orig: f.orig ?? "", name: f.name ?? "", content: f.content ?? "", origContent: f.origContent ?? "", locked: !!f.locked });
        draftMode = d.mode; draftId = d.id ?? ""; draftBase = d.base ?? ""; origDesc = d.origDesc ?? ""; draftDesc = d.desc ?? "";
        draftPublic = !!d.public; draftLocal = !!d.local; removedFiles = d.removed ?? []; activeKey = d.key; draftTick++;
    }
    function bufferObject() {
        const files = [];
        for (let i = 0; i < draft.count; i++) {
            const d = draft.get(i);
            files.push({ orig: d.orig, name: d.name, content: d.content, origContent: d.origContent, locked: d.locked });
        }
        return { key: activeKey, mode: draftMode, id: draftId, base: draftBase, origDesc: origDesc, desc: draftDesc,
                 public: draftPublic, local: draftLocal, removed: removedFiles, files: files };
    }
    property bool newLocal: false          // new drafts start as local notes (remembered by the panel)
    function beginCreate() {
        stash();
        loadBuffer({ key: `new-${Date.now()}`, mode: "create", local: newLocal, files: [{ orig: "", name: "", content: "", origContent: "", locked: false }] });
    }
    function beginEdit(g) {   // continues the gist's draft if it has one
        stash();
        if (drafts[g.id]) { loadBuffer(drafts[g.id]); return; }
        loadBuffer({ key: g.id, mode: "edit", id: g.id, base: g.updated_at, origDesc: g.description, desc: g.description, public: g.public, local: !!g.local,
                     files: g.files.map(f => ({ orig: f.filename, name: f.filename, content: f.content, origContent: f.content, locked: f.truncated || f.clipped })) });
    }
    function openDraft(key) { if (drafts[key]) { stash(); loadBuffer(drafts[key]); } }
    function touchDraft() { draftTick++; stashTimer.restart() }
    // buffer -> drafts (dropped when it has no changes) -> disk
    function stash() {
        stashTimer.stop();
        if (activeKey === "") return;
        const m = Object.assign({}, drafts);
        if (bufferChanged()) m[activeKey] = Object.assign(bufferObject(), { savedAt: new Date().toISOString() });
        else delete m[activeKey];
        drafts = m; persist();
    }
    function closeEditor() { stash(); activeKey = ""; draft.clear(); }
    function discardDraft(key) {
        const m = Object.assign({}, drafts); delete m[key]; drafts = m; persist();
        if (key === activeKey) { stashTimer.stop(); activeKey = ""; draft.clear(); }
    }
    // After a successful save the buffer becomes the new baseline; the editor stays open on the saved gist.
    function rebase(id, updatedAt) {
        const m = Object.assign({}, drafts); delete m[activeKey]; drafts = m; persist();
        for (let i = 0; i < draft.count; i++) { const d = draft.get(i); draft.set(i, { orig: d.name, origContent: d.content }); }
        draftMode = "edit"; draftId = id; draftBase = updatedAt; origDesc = draftDesc; removedFiles = []; activeKey = id; draftTick++;
    }
    // Publish the open draft (payload built by the popup) / delete a gist. The bookkeeping runs here, not in the popup, so it
    // completes even if the popup is closed before GitHub answers; onDone(ok, id) is only for the popup's own feedback.
    function publish(args, payload, onDone) {
        const key = activeKey;
        return run(args, payload, (ok, out) => {
            const line = ok ? out.split("\n").pop() : "";
            const [id, url, updated] = ok ? line.split(line.includes("\t") ? "\t" : " ") : ["", "", ""];   // local notes: tab-separated
            if (ok) {
                if (activeKey === key) rebase(id, updated); else discardDraft(key);
                if (args[0] === "create") Quickshell.clipboardText = url;   // not for local notes: url is a path
            }
            if (onDone) { try { onDone(ok, id); } catch (e) {} }   // the popup may be gone by now
        });
    }
    function removeGist(id, onDone) {
        return run(id.startsWith("local:") ? ["local", "delete", localDir, id] : ["delete", id], "", ok => {
            if (ok && drafts[id]) discardDraft(id);
            if (onDone) { try { onDone(ok); } catch (e) {} }
        });
    }
    // Upload a local note as a new gist (the note then goes to the trash); onDone(ok, newId). Copies the gist's link.
    function upload(id, isPublic, onDone) {
        return run(["upload", localDir, id, isPublic ? "public" : "secret"], "", (ok, out) => {
            const [nid, url] = ok ? out.split("\n").pop().split(" ") : ["", ""];
            if (ok) Quickshell.clipboardText = url;
            if (onDone) { try { onDone(ok, nid); } catch (e) {} }
        });
    }
    function persist() { if (draftsLoaded && draftFile.path !== "") draftFile.setText(JSON.stringify({ version: 2, drafts: drafts })) }
    Timer { id: stashTimer; interval: 2000; onTriggered: root.stash() }

    // Drafts folder (a setting): created 0700 first; moving it merges the drafts already there with the current ones.
    readonly property string screenKey: root.QsWindow.window?.screen?.name ?? ""
    property bool draftsLoaded: false
    property bool draftDirReady: false
    onDraftDirChanged: { draftDirReady = false; draftsLoaded = false; mkdirProc.running = true }
    Process { id: mkdirProc; command: ["mkdir", "-p", "-m", "700", root.draftDir]; onExited: root.draftDirReady = true }
    FileView {
        id: draftFile
        path: root.screenKey !== "" && root.draftDirReady ? `${root.draftDir}/drafts-${root.screenKey}.json` : ""
        atomicWrites: true
        printErrors: false
        onLoaded: {
            if (root.draftsLoaded) return;   // only the first read of this file; later writes are ours
            root.draftsLoaded = true;
            try {
                const j = JSON.parse(text());
                if (j.version === 2 && j.drafts && typeof j.drafts === "object") root.drafts = Object.assign({}, j.drafts, root.drafts);
            } catch (e) {}
            root.persist();
        }
        onLoadFailed: { root.draftsLoaded = true; root.persist() }
    }
    Component.onCompleted: { mkdirProc.running = true; scanLocal() }
    readonly property string script: `${Quickshell.env("HOME")}/.config/hypr/custom/gist-widget.sh`
    readonly property string cacheDir: `${Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"}/gist-widget`

    // on open only when the last sync is over 5 min old; the button below syncs any time
    onOpenChanged: {
        if (!open) return;
        scanLocal();
        if (!lastSync || Date.now() - Date.parse(lastSync) > 300000) sync();
    }

    function sync() { if (!syncProc.running) syncProc.running = true }
    // Run a mutation (create/update ID/delete ID/clip); payload goes to the script's stdin. onDone(ok, stdout) afterwards.
    function run(args, payload, onDone) {
        if (actProc.running) return false;
        actError = "";
        _onDone = onDone ?? null;
        actProc.payload = payload ?? "";
        actProc.command = args[0] === "local" ? ["python3", root.localScript].concat(args.slice(1)) : ["bash", root.script].concat(args);
        actProc.running = true;
        return true;
    }

    FileView {
        id: indexFile
        path: `${root.cacheDir}/index.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.gists = JSON.parse(text()); } catch (e) {} }
        printErrors: false
    }
    FileView {
        path: `${root.cacheDir}/synced_at`
        onLoaded: root.lastSync = text().trim()
        printErrors: false
    }
    Process {
        id: syncProc
        command: ["bash", root.script, "sync"]
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") root.lastSync = text.trim() }
        stderr: StdioCollector { id: syncErr }
        onExited: code => {
            root.syncError = code === 0 ? "" : (syncErr.text.trim().split("\n").pop() || `sync failed (${code})`);
            indexFile.reload();   // the file may not have existed when the FileView started watching
        }
    }
    Timer { interval: 1800000; repeat: true; running: true; onTriggered: root.sync() }   // background sync every 30 min
    Timer { interval: 60000; running: true; onTriggered: root.sync() }   // first sync a minute after the shell starts

    Process {
        id: actProc
        property string payload: ""
        stdinEnabled: true
        onStarted: { write(payload); stdinEnabled = false }
        stdout: StdioCollector { id: actOut }
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            stdinEnabled = true;
            const out = actOut.text.trim();
            if (code !== 0) {
                const lines = actErr.text.trim().split("\n").filter(l => l.trim() !== "");
                root.actError = lines.length ? lines.pop() : `failed (${code})`;
            }
            indexFile.reload();
            root.scanLocal();
            const cb = root._onDone; root._onDone = null;
            if (cb) cb(code === 0, out);
        }
    }

    CustomIcon {  // GitHub mark, sized to match the neighbouring glyph icons
        anchors.centerIn: parent
        width: 16
        height: 16
        source: "github-symbolic"
        colorize: true
        color: root.syncError !== "" ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
    }
    Item {  // indeterminate loader line below the icon while syncing (same as the Mail/Teams buttons)
        id: loader
        visible: root.syncing || root.busy
        anchors { bottom: parent.bottom; bottomMargin: 2; horizontalCenter: parent.horizontalCenter }
        width: parent.width - 12; height: 2
        clip: true
        Rectangle { anchors.fill: parent; radius: 1; color: Appearance.colors.colOnLayer0; opacity: 0.2 }
        Rectangle {
            id: runner
            height: parent.height; width: parent.width * 0.4; radius: 1
            color: Appearance.colors.colPrimary
            SequentialAnimation on x {
                running: loader.visible; loops: Animation.Infinite
                NumberAnimation { from: -runner.width; to: loader.width; duration: 900; easing.type: Easing.InOutQuad }
            }
        }
    }

    // Right-click menu entries (WidgetBase places and closes the menu)
    property string pendingMode: ""   // "create": the panel opens straight into a new gist
    menuContent: Component { ColumnLayout {
        width: 238
        spacing: 2
        Repeater {
            model: [
                { icon: "add", label: Translation.tr("New gist"), act: "new" },
                { icon: "content_paste", label: Translation.tr("Secret gist from clipboard"), act: "clip" },
                { icon: "sync", label: root.syncing ? Translation.tr("Syncing…") : Translation.tr("Sync now"), act: "sync" },
                { icon: "open_in_new", label: Translation.tr("Open gist.github.com"), act: "web" },
            ]
            delegate: RippleButton {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: {
                    root.closeMenu();
                    if (modelData.act === "new") { root.pendingMode = "create"; root.open = true; }
                    else if (modelData.act === "clip") root.run(["clip"]);
                    else if (modelData.act === "sync") root.sync();
                    else Qt.openUrlExternally("https://gist.github.com/");
                }
                contentItem: RowLayout {
                    spacing: 10
                    MaterialSymbol { Layout.leftMargin: 4; text: modelData.icon; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colSubtext }
                    StyledText { Layout.fillWidth: true; text: modelData.label; color: Appearance.colors.colOnLayer2 }
                }
            }
        }
    } }

    panelContent: Component { FocusScope {
        id: gs
        readonly property var store: root   // the button keeps the data (gists, drafts, sync) while the panel is closed
        property string mode: "list"           // list | view | editor | settings
        property string selectedId: ""
        readonly property var current: store.gistById(selectedId)
        property string query: ""
        property string visibility: "all"      // all | public | secret | local | drafts
        property string sortKey: "updated"     // updated | created | name
        property bool confirmDelete: false
        property bool confirmUpload: false     // view of a local note: "Upload as a secret / public gist?"
        property string confirmDiscardKey: ""  // draft waiting for "Discard?" confirmation
        property string notice: ""             // short confirmation ("Link copied")
        property string formError: ""
        property bool overwriteArmed: false    // the gist changed on GitHub since editing started: a second Save goes ahead
        property int draftGen: 0               // bumps when the buffer is replaced from outside the fields, so they re-read it
        property real now: Date.now()
        Timer { interval: 30000; repeat: true; running: true; onTriggered: gs.now = Date.now() }
        Timer { interval: 15000; repeat: true; running: true; onTriggered: gs.store.scanLocal() }   // pick up edits made outside

        // Remembered across opens: visibility filter and sort
        readonly property string stateFile: `${Quickshell.env("HOME")}/.local/state/gist-widget.json`
        property bool stateReady: false
        function saveState() { if (stateReady) stateView.setText(JSON.stringify({ visibility, sortKey, newLocal: store.newLocal })) }
        onVisibilityChanged: saveState()
        onSortKeyChanged: saveState()
        Connections { target: gs.store; function onNewLocalChanged() { gs.saveState() } }
        FileView { id: stateView; path: gs.stateFile; blockLoading: true; atomicWrites: true; printErrors: false }
        Component.onCompleted: {
            Qt.callLater(() => { if (gs.mode === "list") filterInput.forceActiveFocus() })   // type to filter right away
            try {
                const j = JSON.parse(stateView.text());
                if (["all", "public", "secret", "local"].includes(j.visibility)) gs.visibility = j.visibility;
                if (typeof j.newLocal === "boolean") store.newLocal = j.newLocal;
                if (["updated", "created", "name"].includes(j.sortKey)) gs.sortKey = j.sortKey;
            } catch (e) {}
            gs.stateReady = true;
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
        Timer { id: noticeTimer; interval: 2500; onTriggered: gs.notice = "" }
        function copy(text, what) { Quickshell.clipboardText = text; flash(what) }

        // ---- list: draft rows (new gists, or drafts of gists deleted on GitHub) first, then gists. All words must match.
        readonly property var hay: store.allGists.map(g => ({
            meta: `${g.description} ${g.id} ${g.files.map(f => f.filename + " " + f.language).join(" ")}`.toLowerCase(),
            content: g.files.map(f => f.content.toLowerCase())
        }))
        readonly property var entries: {
            const words = query.trim().toLowerCase().split(/\s+/).filter(w => w !== "");
            const drafts = store.drafts, out = [];
            if (visibility === "all" || visibility === "drafts" || visibility === "local") {
                const rows = [];
                for (const k in drafts) {
                    const d = drafts[k];
                    const orphan = d.mode === "edit" && !store.gistById(d.id);
                    if (d.mode !== "create" && !orphan) continue;
                    if (visibility === "local" && !d.local) continue;
                    const h = `${d.desc} ${d.files.map(f => f.name + " " + f.content).join(" ")}`.toLowerCase();
                    if (words.every(w => h.includes(w))) rows.push({ type: "draft", d: d, orphan: orphan });
                }
                rows.sort((a, b) => (b.d.savedAt ?? "").localeCompare(a.d.savedAt ?? ""));
                out.push(...rows);
            }
            const gistRows = [];
            store.allGists.forEach((g, gi) => {
                if (visibility === "public" && (g.local || !g.public)) return;
                if (visibility === "secret" && (g.local || g.public)) return;
                if (visibility === "local" && !g.local) return;
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
        function openGist(id) { selectedId = id; confirmDelete = false; confirmUpload = false; mode = "view"; Qt.callLater(() => keyScope.forceActiveFocus()) }
        function toList() { mode = "list"; selectedId = ""; confirmDelete = false; confirmUpload = false; Qt.callLater(() => filterInput.forceActiveFocus()) }
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
            if (confirmUpload) { confirmUpload = false; return; }
            if (mode === "editor") { if (!store.busy) leaveEditor(); }
            else if (mode === "view" || mode === "settings") toList();
            else if (query !== "") filterInput.text = "";
            else root.close();
        }

        // ---- save: publishes the open draft; the editor stays open on the saved gist
        function save() {
            if (store.busy || mode !== "editor") return;
            formError = "";
            const d = store.draft;
            if (d.count === 0) { formError = Translation.tr("A gist needs at least one file."); return; }
            if (!store.changed) { formError = Translation.tr("No changes to save."); return; }
            let renamed = false;
            for (let i = 0; i < d.count; i++) {   // the names GitHub will store, so the fields show them too (unnamed = Markdown)
                const n = d.get(i).name, t = n.trim() !== "" ? n.trim() : `gistfile${i + 1}.md`;
                if (t !== n) { d.setProperty(i, "name", t); renamed = true; }
            }
            if (store.draftDesc !== store.draftDesc.trim()) { store.draftDesc = store.draftDesc.trim(); renamed = true; }
            if (renamed) { draftGen++; store.touchDraft(); }
            const files = {}, seen = {};
            for (let i = 0; i < d.count; i++) {
                const f = d.get(i);
                if (seen[f.name]) { formError = Translation.tr("Two files are named \"%1\".").arg(f.name); return; }
                seen[f.name] = true;
                if (!store.draftLocal && !f.locked && f.content.trim() === "") { formError = Translation.tr("\"%1\" is empty; GitHub doesn't allow empty files.").arg(f.name); return; }
                if (store.draftMode === "create" || f.orig === "") { files[f.name] = { content: f.content }; continue; }
                const e = {};   // only what you changed: files you didn't touch keep whatever GitHub has
                if (f.name !== f.orig) e.filename = f.name;
                if (!f.locked && f.content !== f.origContent) e.content = f.content;
                if (Object.keys(e).length) files[f.orig] = e;
            }
            for (const r of store.removedFiles) files[r] = null;
            if (store.draftLocal) {   // local note: files on disk, same payload shape as GitHub
                const lp = { description: store.draftDesc, files: files };
                store.publish(["local", "save", store.localDir].concat(store.draftMode === "create" ? [] : [store.draftId]), JSON.stringify(lp), (ok, id) => {
                    if (!ok) return;
                    overwriteArmed = false;
                    if (mode === "editor") selectedId = id;
                    flash(Translation.tr("Saved to %1").arg(store.localDir));
                });
                return;
            }
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
                formError = current.local
                    ? Translation.tr("This note changed on disk (%1) after you started editing. Save again to apply your changes; files you edited replace the versions on disk.").arg(ago(current.updated_at))
                    : Translation.tr("This gist changed on GitHub (%1) after you started editing. Save again to apply your changes; files you edited replace the GitHub versions.").arg(ago(current.updated_at));
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
            const wasLocal = !!current?.local;
            store.removeGist(selectedId, ok => {
                if (!ok) { confirmDelete = false; return; }
                toList(); flash(wasLocal ? Translation.tr("Note moved to the trash") : Translation.tr("Gist deleted"));
            });
        }
        function upload(isPublic) {
            if (store.drafts[selectedId]) { confirmUpload = false; flash(Translation.tr("Save or discard your unsaved changes first")); return; }
            store.upload(selectedId, isPublic, (ok, id) => {
                confirmUpload = false;
                if (!ok) return;
                if (mode === "view") selectedId = id;
                flash(Translation.tr("Uploaded as a gist · link copied"));
            });
        }
        function openPath(p) { Qt.openUrlExternally("file://" + p) }
        // a one-file note is the file itself (html_url = raw_url): open the folder it is in
        function openFolder(g) { const p = g.files.length && g.files[0].raw_url === g.html_url ? g.html_url.slice(0, g.html_url.lastIndexOf("/")) : g.html_url; openPath(p) }
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
                    const d = gs.store.draft;
                    let i = -1;
                    for (let k = 0; k < d.count; k++) if (!d.get(k).locked && d.get(k).content.trim() === "") { i = k; break; }
                    if (i < 0) { gs.addFile(); i = d.count - 1; }
                    d.setProperty(i, "content", text);
                    gs.store.touchDraft();
                    gs.draftGen++;
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
            signal accepted()
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
                onAccepted: fld.accepted()
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


    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true
        // Esc = back/close (the editor keeps your draft), Ctrl+S = save, Ctrl+N = new gist (fields don't consume these)
        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier;
            if (event.key === Qt.Key_Escape) { gs.back(); event.accepted = true; }
            else if (ctrl && event.key === Qt.Key_S && gs.mode === "editor") { gs.save(); event.accepted = true; }
            else if (ctrl && event.key === Qt.Key_N) { gs.startCreate(); event.accepted = true; }
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
                    visible: gs.mode !== "list"
                    symbol: "arrow_back"
                    tip: gs.mode === "editor" ? Translation.tr("Back (Esc) · keeps your changes as a draft") : Translation.tr("Back (Esc)")
                    enabled: !(gs.mode === "editor" && gs.store.busy)
                    onClicked: gs.back()
                }
                MaterialSymbol { visible: gs.mode === "list"; text: "note_stack"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colOnLayer2 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: gs.mode === "editor" ? (gs.store.draftMode === "create" ? Translation.tr("New gist")
                                                         : gs.current ? gs.title(gs.current) : Translation.tr("Edit gist"))
                            : gs.mode === "view" ? (gs.current ? gs.title(gs.current) : Translation.tr("Gist"))
                            : gs.mode === "settings" ? Translation.tr("Settings")
                            : Translation.tr("Gists")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: gs.mode === "list"
                            ? (gs.store.syncing ? Translation.tr("Syncing…")
                               : gs.store.syncError !== "" ? Translation.tr("Sync failed · showing cached gists")
                               : `${gs.store.gists.length} ${Translation.tr("gists")}`
                                 + (gs.store.localGists.length ? ` · ${gs.store.localGists.length} ${Translation.tr("local")}` : "")
                                 + (gs.store.draftCount ? ` · ${gs.store.draftCount} ${gs.store.draftCount === 1 ? Translation.tr("draft") : Translation.tr("drafts")}` : "")
                                 + (gs.store.lastSync ? ` · ${Translation.tr("synced")} ${gs.ago(gs.store.lastSync)}` : ""))
                            : gs.mode === "editor"
                                ? (gs.store.draftMode === "create" ? (gs.store.draftLocal ? Translation.tr("Saved as files in %1").arg(gs.store.localDir) : Translation.tr("Not on GitHub until you create it"))
                                   : !gs.current ? (gs.store.draftLocal ? Translation.tr("This note no longer exists on disk") : Translation.tr("This gist no longer exists on GitHub"))
                                   : `${Translation.tr("Editing")} · ${gs.current.local ? Translation.tr("Local") : gs.current.public ? Translation.tr("Public") : Translation.tr("Secret")}`)
                            : gs.mode === "settings" ? Translation.tr("Where local notes and drafts are kept")
                            : gs.current
                                ? `${gs.current.local ? Translation.tr("Local") : gs.current.public ? Translation.tr("Public") : Translation.tr("Secret")} · ${gs.current.files.length} ${gs.current.files.length === 1 ? Translation.tr("file") : Translation.tr("files")} · ${Translation.tr("updated")} ${gs.ago(gs.current.updated_at)}`
                                : ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: gs.mode === "list" && gs.store.syncError !== "" ? "#ef5350" : Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
                // list actions
                IconBtn { visible: gs.mode === "list"; symbol: "add"; tip: Translation.tr("New gist (Ctrl+N)"); onClicked: gs.startCreate() }
                IconBtn {
                    visible: gs.mode === "list"
                    symbol: "sync"; tip: gs.store.syncing ? Translation.tr("Syncing…") : Translation.tr("Sync now")
                    enabled: !gs.store.syncing
                    onClicked: { gs.store.sync(); gs.store.scanLocal(); }
                }
                IconBtn { visible: gs.mode === "list"; symbol: "settings"; tip: Translation.tr("Settings"); onClicked: { gs.mode = "settings"; Qt.callLater(() => keyScope.forceActiveFocus()) } }
                // view actions
                IconBtn { visible: gs.mode === "view" && !!gs.current && !gs.current.local; symbol: "link"; tip: Translation.tr("Copy link"); onClicked: gs.copy(gs.current.html_url, Translation.tr("Link copied")) }
                IconBtn { visible: gs.mode === "view" && !!gs.current && !gs.current.local; symbol: "open_in_new"; tip: Translation.tr("Open on GitHub"); onClicked: Qt.openUrlExternally(gs.current.html_url) }
                IconBtn { visible: gs.mode === "view" && !!gs.current && !!gs.current.local; symbol: "folder_open"; tip: Translation.tr("Show in folder"); onClicked: gs.openFolder(gs.current) }
                IconBtn {
                    visible: gs.mode === "view" && !!gs.current && !!gs.current.local
                    symbol: "cloud_upload"; tip: Translation.tr("Upload to GitHub as a gist")
                    enabled: !gs.store.busy
                    onClicked: { gs.confirmDelete = false; gs.confirmUpload = true; }
                }
                IconBtn {
                    visible: gs.mode === "view" && !!gs.current
                    symbol: "edit"; tip: gs.store.drafts[gs.selectedId] ? Translation.tr("Continue your draft") : Translation.tr("Edit")
                    onClicked: gs.startEdit(gs.current)
                }
                IconBtn { visible: gs.mode === "view" && !!gs.current; symbol: "delete"; tip: Translation.tr("Delete"); iconColor: "#ef5350"; onClicked: { gs.confirmUpload = false; gs.confirmDelete = true; } }
                // editor actions; Save is the primary action, top right
                IconBtn { visible: gs.mode === "editor"; symbol: "content_paste"; tip: Translation.tr("Paste clipboard into a file"); onClicked: pasteProc.running = true }
                IconBtn { visible: gs.mode === "editor"; symbol: "note_add"; tip: Translation.tr("Add file"); onClicked: gs.addFile() }
                IconBtn {
                    visible: gs.mode === "editor" && (gs.store.changed || !!gs.store.drafts[gs.store.activeKey])
                    symbol: "delete"
                    tip: gs.store.draftMode === "create" ? Translation.tr("Discard draft") : Translation.tr("Discard changes")
                    iconColor: Appearance.colors.colSubtext
                    onClicked: gs.confirmDiscardKey = gs.store.activeKey
                }
                RippleButton {
                    id: saveBtn
                    visible: gs.mode === "editor"
                    readonly property bool ready: gs.store.changed && !gs.store.busy
                    implicitHeight: 32; implicitWidth: saveRow.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: ready ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: ready ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2
                    enabled: ready
                    onClicked: gs.save()
                    contentItem: RowLayout {
                        id: saveRow
                        spacing: 4
                        MaterialSymbol {
                            text: gs.store.draftMode === "create" && !gs.store.draftLocal ? "cloud_upload" : "save"
                            iconSize: Appearance.font.pixelSize.larger
                            color: saveBtn.ready ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: gs.store.busy ? Translation.tr("Saving…") : gs.store.draftMode === "create" && !gs.store.draftLocal ? Translation.tr("Create") : Translation.tr("Save")
                            font.weight: Font.Medium
                            color: saveBtn.ready ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        }
                    }
                    StyledToolTip {
                        text: gs.store.changed ? "Ctrl+S" : Translation.tr("No unsaved changes")
                        visible: saveBtn.hovered
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }

            ConfirmBar {
                visible: gs.confirmDelete && gs.mode === "view"
                text: gs.current?.local ? Translation.tr("Move this note to the trash?") : Translation.tr("Delete this gist on GitHub? This can't be undone.")
                action: gs.store.busy ? Translation.tr("Deleting…") : Translation.tr("Delete")
                busy: gs.store.busy
                onConfirmed: gs.remove()
                onCancelled: gs.confirmDelete = false
            }
            ConfirmBar {
                readonly property var d: gs.store.drafts[gs.confirmDiscardKey] ?? null
                readonly property bool isNew: d ? d.mode === "create" : gs.store.draftMode === "create"
                visible: gs.confirmDiscardKey !== ""
                readonly property bool isLocal: d ? !!d.local : gs.store.draftLocal
                text: isNew ? (isLocal ? Translation.tr("Discard this draft? It was never saved.") : Translation.tr("Discard this draft? It was never saved to GitHub."))
                            : isLocal ? Translation.tr("Discard your unsaved changes? The note on disk stays as it is.")
                            : Translation.tr("Discard your unsaved changes? The gist on GitHub stays as it is.")
                action: Translation.tr("Discard")
                onConfirmed: gs.discard(gs.confirmDiscardKey)
                onCancelled: gs.confirmDiscardKey = ""
            }

            Rectangle {  // upload a local note: pick the visibility
                visible: gs.confirmUpload && gs.mode === "view"
                Layout.fillWidth: true
                implicitHeight: upRow.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colSecondaryContainer
                RowLayout {
                    id: upRow
                    anchors { fill: parent; margins: 8; leftMargin: 12 }
                    spacing: 6
                    StyledText {
                        Layout.fillWidth: true; wrapMode: Text.Wrap
                        text: gs.store.busy ? Translation.tr("Uploading…") : Translation.tr("Upload as a new gist? The local note then goes to the trash.")
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    Chip { label: Translation.tr("Cancel"); onClicked: gs.confirmUpload = false }
                    Chip { label: Translation.tr("Secret"); active: true; enabled: !gs.store.busy; onClicked: gs.upload(false) }
                    Chip { label: Translation.tr("Public"); enabled: !gs.store.busy; onClicked: gs.upload(true) }
                }
            }

            // ---------------- settings ----------------
            ColumnLayout {
                id: settingsView
                visible: gs.mode === "settings"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6
                function apply() { gs.store.saveSettings(localField.input.text, draftField.input.text); gs.flash(Translation.tr("Settings saved")) }
                component SLabel: StyledText { Layout.fillWidth: true; Layout.topMargin: 6; font.weight: Font.Medium; color: Appearance.colors.colOnLayer2 }
                component SHint: StyledText { Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                SLabel { text: Translation.tr("Local notes folder") }
                RowLayout {
                    Layout.fillWidth: true
                    Field {
                        id: localField; mono: true; placeholder: gs.store.defaultLocalDir
                        Component.onCompleted: input.text = gs.store.localDir
                        onAccepted: settingsView.apply()
                    }
                    IconBtn { symbol: "folder_open"; tip: Translation.tr("Open folder"); onClicked: gs.openPath(gs.store.localDir) }
                }
                SHint { text: Translation.tr("Notes that stay on this computer. Each file is a note, each subfolder a note with several files; files you add here show up too. Upload one to GitHub any time.") }
                SHint { visible: gs.store.localError !== ""; text: gs.store.localError; color: "#ef5350" }
                SLabel { text: Translation.tr("Drafts folder") }
                RowLayout {
                    Layout.fillWidth: true
                    Field {
                        id: draftField; mono: true; placeholder: gs.store.defaultDraftDir
                        Component.onCompleted: input.text = gs.store.draftDir
                        onAccepted: settingsView.apply()
                    }
                    IconBtn { symbol: "folder_open"; tip: Translation.tr("Open folder"); onClicked: gs.openPath(gs.store.draftDir) }
                }
                SHint { text: Translation.tr("Unsaved changes to gists and notes (drafts-<screen>.json). Changing it moves your current drafts there.") }
                SLabel { text: Translation.tr("New notes") }
                RowLayout {
                    spacing: 4
                    Chip { label: Translation.tr("Local"); active: gs.store.newLocal; onClicked: gs.store.newLocal = true }
                    Chip { label: Translation.tr("GitHub gist"); active: !gs.store.newLocal; onClicked: gs.store.newLocal = false }
                }
                SHint { text: Translation.tr("What + and Ctrl+N create first; you can switch in the editor.") }
                RowLayout {
                    Layout.topMargin: 8
                    Item { Layout.fillWidth: true }
                    Chip { label: Translation.tr("Defaults"); onClicked: { localField.input.text = gs.store.defaultLocalDir; draftField.input.text = gs.store.defaultDraftDir } }
                    Chip { label: Translation.tr("Save"); active: true; onClicked: settingsView.apply() }
                }
                Item { Layout.fillHeight: true }
            }

            // ---------------- list ----------------
            Rectangle {
                visible: gs.mode === "list"
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
                        onTextChanged: gs.query = text
                        Keys.onEscapePressed: gs.back()
                        Keys.onReturnPressed: if (gs.entries.length) gs.openEntry(gs.entries[0])
                        Keys.onEnterPressed: if (gs.entries.length) gs.openEntry(gs.entries[0])
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
                visible: gs.mode === "list"
                Layout.fillWidth: true
                spacing: 4
                Chip { label: Translation.tr("All"); active: gs.visibility === "all"; onClicked: gs.visibility = "all" }
                Chip { label: Translation.tr("Public"); active: gs.visibility === "public"; onClicked: gs.visibility = "public" }
                Chip { label: Translation.tr("Secret"); active: gs.visibility === "secret"; onClicked: gs.visibility = "secret" }
                Chip { label: Translation.tr("Local"); active: gs.visibility === "local"; onClicked: gs.visibility = "local" }
                Chip {
                    visible: gs.store.draftCount > 0 || gs.visibility === "drafts"
                    label: Translation.tr("Drafts")
                    active: gs.visibility === "drafts"
                    onClicked: gs.visibility = "drafts"
                }
                Item { Layout.fillWidth: true }
                RippleButton {
                    implicitHeight: 26
                    implicitWidth: sortRow.implicitWidth + 16
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: gs.sortKey = gs.sortKey === "updated" ? "created" : gs.sortKey === "created" ? "name" : "updated"
                    contentItem: RowLayout {
                        id: sortRow
                        spacing: 4
                        MaterialSymbol { text: "sort"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
                        StyledText {
                            text: gs.sortKey === "updated" ? Translation.tr("Recently updated") : gs.sortKey === "created" ? Translation.tr("Newest") : Translation.tr("Name")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledToolTip { text: Translation.tr("Change sort order"); visible: parent.hovered }
                }
            }

            StyledListView {
                id: list
                visible: gs.mode === "list"
                animateAppearance: false
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: gs.entries
                boundsBehavior: Flickable.StopAtBounds
                // One row type for both: a gist (with a Draft pill if you have unsaved changes to it) or a draft of a new gist
                delegate: RippleButton {
                    id: rowBtn
                    required property var modelData
                    readonly property bool isDraft: modelData.type === "draft"
                    readonly property var g: modelData.g ?? null
                    readonly property var d: isDraft ? modelData.d : (gs.store.drafts[g.id] ?? null)
                    width: list.width
                    implicitHeight: rowCol.implicitHeight + 16
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: gs.openEntry(modelData)
                    altAction: () => {
                        if (rowBtn.isDraft) { gs.confirmDiscardKey = rowBtn.d.key; return; }
                        const p = rowBtn.mapToItem(gs, rowBtn.width - 240, rowBtn.height / 2);
                        gs.menuX = p.x; gs.menuY = p.y; gs.menuGist = rowBtn.g;
                    }
                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 2
                            Layout.leftMargin: 4
                            text: rowBtn.isDraft ? "edit_note" : rowBtn.g.local ? "hard_drive" : rowBtn.g.public ? "public" : "lock"
                            iconSize: Appearance.font.pixelSize.larger
                            color: rowBtn.isDraft ? Appearance.colors.colTertiary : rowBtn.g.local ? Appearance.colors.colTertiary : rowBtn.g.public ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
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
                                    text: rowBtn.isDraft ? gs.draftTitle(rowBtn.d) : gs.title(rowBtn.g)
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
                                    ? `${rowBtn.modelData.orphan ? (rowBtn.d.local ? Translation.tr("Note deleted on disk") : Translation.tr("Gist deleted on GitHub")) : rowBtn.d.local ? Translation.tr("New local note") : Translation.tr("New gist")} · ${Translation.tr("saved on this computer")} ${gs.ago(rowBtn.d.savedAt)}`
                                    : `${rowBtn.g.files.map(f => f.filename).join(", ")} · ${gs.ago(rowBtn.g.updated_at)}`
                                      + (rowBtn.d ? ` · ${Translation.tr("unsaved changes")} ${gs.ago(rowBtn.d.savedAt)}` : "")
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
                                if (rowBtn.isDraft) gs.confirmDiscardKey = rowBtn.d.key;
                                else gs.copy(gs.allContent(rowBtn.g), Translation.tr("Content copied"));
                            }
                        }
                    }
                }

                ColumnLayout {  // empty states
                    anchors.centerIn: parent
                    width: parent.width - 40
                    visible: gs.entries.length === 0
                    spacing: 10
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: gs.store.gists.length === 0 && gs.store.syncing ? "sync" : gs.store.gists.length === 0 ? "note_stack" : "search_off"
                        iconSize: 48
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                        text: gs.visibility === "drafts" ? Translation.tr("No drafts")
                            : gs.visibility === "local" && gs.store.localGists.length === 0 ? Translation.tr("No local notes in %1 yet. Press + to write one, or change the folder in Settings.").arg(gs.store.localDir)
                            : gs.store.allGists.length > 0 ? Translation.tr("No gists match")
                            : gs.store.syncing ? Translation.tr("Loading your gists…")
                            : gs.store.syncError !== "" ? gs.store.syncError
                            : Translation.tr("No gists yet. Press + or Ctrl+N to create one.")
                    }
                }
            }

            // ---------------- view ----------------
            Rectangle {  // you have a draft for this gist
                id: viewDraft
                readonly property var d: gs.store.drafts[gs.selectedId] ?? null
                visible: gs.mode === "view" && d !== null
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
                        text: (gs.current?.local ? Translation.tr("Unsaved changes (%1), compared with the file on disk below.") : Translation.tr("Unsaved changes (%1), compared with GitHub below.")).arg(gs.ago(viewDraft.d?.savedAt ?? ""))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnTertiaryContainer
                    }
                    Chip { label: Translation.tr("Discard"); onClicked: gs.confirmDiscardKey = gs.selectedId }
                    Chip { label: Translation.tr("Continue"); active: true; onClicked: gs.startEdit(gs.current) }
                }
            }
            StyledListView {  // draft vs GitHub, inline diff
                id: diffList
                visible: gs.mode === "view" && viewDraft.d !== null
                animateAppearance: false
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 12
                model: visible ? gs.draftDiff(viewDraft.d, gs.current) : []
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
                visible: gs.mode === "view" && viewDraft.d === null
                animateAppearance: false
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 12
                model: gs.current ? gs.current.files : []
                boundsBehavior: Flickable.StopAtBounds
                delegate: ColumnLayout {
                    id: fileItem
                    required property var modelData
                    readonly property bool markdown: modelData.language === "Markdown" || /\.(md|markdown)$/i.test(modelData.filename)
                    property bool source: false   // Markdown files show the rendered preview unless switched to the source
                    readonly property bool preview: markdown && !source
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
                        StyledText { text: gs.fmtSize(fileItem.modelData.size); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                        IconBtn {
                            visible: fileItem.markdown
                            symbol: "preview"; iconColor: fileItem.preview ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                            tip: fileItem.preview ? Translation.tr("Showing the preview · click for the Markdown source") : Translation.tr("Showing the source · click for the preview")
                            onClicked: fileItem.source = !fileItem.source
                        }
                        IconBtn { symbol: "content_copy"; tip: Translation.tr("Copy file"); onClicked: gs.copy(fileItem.modelData.content, Translation.tr("File copied")) }
                        IconBtn {
                            readonly property bool local: !!gs.current?.local
                            symbol: local ? "file_open" : "code"; tip: local ? Translation.tr("Open file (right-click: copy path)") : Translation.tr("Copy raw URL (for curl)")
                            altAction: () => gs.copy(fileItem.modelData.raw_url, Translation.tr("Path copied"))
                            onClicked: local ? gs.openPath(fileItem.modelData.raw_url) : gs.copy(fileItem.modelData.raw_url, Translation.tr("Raw URL copied"))
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: (fileItem.preview ? md.implicitHeight : code.implicitHeight) + 16
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer0
                        TextEdit {   // own item: switching one TextEdit's textFormat back to plain keeps the formatting
                            id: md
                            visible: fileItem.preview
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.MarkdownText
                            text: fileItem.markdown ? fileItem.modelData.content : ""
                            font.family: Appearance.font.family.reading
                            font.hintingPreference: Font.PreferNoHinting
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer0
                            selectionColor: Appearance.colors.colSecondaryContainer
                            selectedTextColor: Appearance.colors.colOnSecondaryContainer
                            onLinkActivated: link => Qt.openUrlExternally(link)
                            HoverHandler { cursorShape: md.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor }
                        }
                        TextEdit {
                            id: code
                            visible: !fileItem.preview
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
                        text: gs.current?.local ? Translation.tr("Only the start of this file is shown; open the file for the rest.") : Translation.tr("Only the start of this file is shown; open it on GitHub for the rest.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: "#ffb300"
                    }
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: !gs.current
                    color: Appearance.colors.colSubtext
                    text: gs.store.busy || gs.store.syncing ? Translation.tr("Loading…") : Translation.tr("This gist or note no longer exists")
                }
            }

            // ---------------- editor (create / edit) ----------------
            StyledFlickable {
                id: edFlick
                visible: gs.mode === "editor"
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
                        onEdited: text => { if (text !== gs.store.draftDesc) { gs.store.draftDesc = text; gs.store.touchDraft(); } }
                        Connections { target: gs; function onDraftGenChanged() { desc.input.text = gs.store.draftDesc } }
                        Component.onCompleted: desc.input.text = gs.store.draftDesc
                    }
                    RowLayout {
                        id: visRow
                        Layout.fillWidth: true
                        spacing: 4
                        readonly property bool isNew: gs.store.draftMode === "create"
                        function pick(local, pub) { if (visRow.isNew) { gs.store.draftLocal = local; gs.store.draftPublic = pub; gs.store.newLocal = local; gs.store.touchDraft(); } }
                        Chip { visible: visRow.isNew || gs.store.draftLocal; label: Translation.tr("Local"); active: gs.store.draftLocal; onClicked: visRow.pick(true, false) }
                        Chip { visible: visRow.isNew || (!gs.store.draftLocal && !gs.store.draftPublic); label: Translation.tr("Secret"); active: !gs.store.draftLocal && !gs.store.draftPublic; onClicked: visRow.pick(false, false) }
                        Chip { visible: visRow.isNew || (!gs.store.draftLocal && gs.store.draftPublic); label: Translation.tr("Public"); active: !gs.store.draftLocal && gs.store.draftPublic; onClicked: visRow.pick(false, true) }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            wrapMode: Text.Wrap
                            text: gs.store.draftLocal ? (visRow.isNew ? Translation.tr("Only on this computer; upload it to GitHub later.") : Translation.tr("Only on this computer; upload it from the note's view."))
                                : !visRow.isNew ? Translation.tr("GitHub can't change a gist's visibility after creation.")
                                : gs.store.draftPublic ? Translation.tr("Listed on your profile and searchable.")
                                : Translation.tr("Unlisted: only people with the link can see it.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Repeater {
                        model: gs.store.draft
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
                                    placeholder: Translation.tr("File name, e.g. notes.md (empty: gistfile%1.md)").arg(fileEd.index + 1)
                                    onEdited: text => { if (text !== fileEd.name) { gs.store.draft.setProperty(fileEd.index, "name", text); gs.store.touchDraft(); } }
                                    Connections { target: gs; function onDraftGenChanged() { nameField.input.text = gs.store.draft.get(fileEd.index)?.name ?? "" } }
                                    Component.onCompleted: nameField.input.text = fileEd.name
                                }
                                IconBtn {
                                    visible: gs.store.draft.count > 1
                                    symbol: "delete"; tip: Translation.tr("Remove file")
                                    iconColor: Appearance.colors.colSubtext
                                    onClicked: gs.removeFile(fileEd.index)
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
                                    anchors { fill: parent; margins: 2 }   // the whole box takes clicks, not just the written lines
                                    readOnly: fileEd.locked
                                    wrapMode: TextEdit.WrapAnywhere
                                    textFormat: TextEdit.PlainText
                                    selectByMouse: true
                                    placeholderText: Translation.tr("Content")
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    background: null
                                    cursorDelegate: Component { Caret {} }
                                    onTextChanged: if (!fileEd.locked && text !== fileEd.content) { gs.store.draft.setProperty(fileEd.index, "content", text); gs.store.touchDraft(); }
                                    onCursorRectangleChanged: if (activeFocus) edFlick.reveal(area, cursorRectangle)
                                    Connections { target: gs; function onDraftGenChanged() { area.text = gs.store.draft.get(fileEd.index)?.content ?? "" } }
                                    Component.onCompleted: text = fileEd.content
                                }
                            }
                            StyledText {
                                visible: fileEd.locked
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: gs.store.draftLocal ? Translation.tr("Too large to edit here (only the start was loaded); you can rename or remove it, or edit the file directly.")
                                                          : Translation.tr("Too large to edit here (only the start was loaded); you can rename or remove it.")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: "#ffb300"
                            }
                        }
                    }
                }
            }

            // Footer: error or confirmation, else the draft state, else hints
            StyledText {
                readonly property bool isError: (gs.formError !== "" && gs.mode === "editor") || gs.store.actError !== ""
                Layout.fillWidth: true
                horizontalAlignment: gs.mode === "editor" && !isError ? Text.AlignLeft : Text.AlignHCenter
                wrapMode: Text.Wrap
                text: gs.formError !== "" && gs.mode === "editor" ? gs.formError
                    : gs.store.actError !== "" ? gs.store.actError
                    : gs.notice !== "" ? gs.notice
                    : gs.mode === "editor"
                        ? (gs.store.changed
                            ? (gs.store.savedAt !== "" ? Translation.tr("Unsaved changes · draft kept on this computer (%1)").arg(gs.ago(gs.store.savedAt))
                                                         : Translation.tr("Unsaved changes"))
                              + " · " + Translation.tr("Esc goes back and keeps the draft")
                            : gs.store.draftMode === "edit" ? Translation.tr("No unsaved changes") : gs.store.draftLocal ? Translation.tr("Ctrl+S saves the note") : Translation.tr("Ctrl+S creates the gist"))
                    : gs.mode === "list" ? Translation.tr("Enter opens the first match · Ctrl+N new · right-click a gist for actions")
                    : gs.mode === "settings" ? Translation.tr("Enter in a field saves · Esc goes back")
                    : Translation.tr("Select text to copy part of a file · Esc goes back")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: isError ? "#ef5350" : gs.notice !== "" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
        }

        // Right-click menu for a gist row (overlay inside the card)
        MouseArea {
            anchors.fill: parent
            visible: gs.menuGist !== null
            acceptedButtons: Qt.AllButtons
            onPressed: gs.menuGist = null
        }
        Rectangle {
            visible: gs.menuGist !== null
            x: Math.max(8, Math.min(gs.menuX, gs.width - width - 8))
            y: Math.max(8, Math.min(gs.menuY, gs.height - height - 8))
            width: 240
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
                    model: gs.menuGist?.local ? [
                        { icon: "content_copy", label: Translation.tr("Copy content"), act: "copy" },
                        { icon: "folder_open", label: Translation.tr("Show in folder"), act: "folder" },
                        { icon: "cloud_upload", label: Translation.tr("Upload to GitHub…"), act: "upload" },
                        { icon: "edit", label: gs.store.drafts[gs.menuGist.id] ? Translation.tr("Continue draft") : Translation.tr("Edit"), act: "edit" },
                        { icon: "delete", label: Translation.tr("Move to trash…"), act: "delete", danger: true },
                    ] : [
                        { icon: "link", label: Translation.tr("Copy link"), act: "link" },
                        { icon: "content_copy", label: Translation.tr("Copy content"), act: "copy" },
                        { icon: "open_in_new", label: Translation.tr("Open on GitHub"), act: "web" },
                        { icon: "edit", label: gs.menuGist && gs.store.drafts[gs.menuGist.id] ? Translation.tr("Continue draft") : Translation.tr("Edit"), act: "edit" },
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
                            const g = gs.menuGist;
                            gs.menuGist = null;
                            if (!g) return;
                            if (modelData.act === "link") gs.copy(g.html_url, Translation.tr("Link copied"));
                            else if (modelData.act === "copy") gs.copy(gs.allContent(g), Translation.tr("Content copied"));
                            else if (modelData.act === "web") Qt.openUrlExternally(g.html_url);
                            else if (modelData.act === "edit") gs.startEdit(g);
                            else if (modelData.act === "folder") gs.openFolder(g);
                            else if (modelData.act === "upload") { gs.openGist(g.id); gs.confirmUpload = true; }
                            else { gs.openGist(g.id); gs.confirmDelete = true; }
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
    } }
}
