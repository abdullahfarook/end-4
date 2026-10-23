import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Bar button for the Gist widget: your GitHub gists (gh) mirrored in a local cache by gist-widget.sh.
// Syncs in the background every 30 minutes and on open if the last sync is older than 5 minutes (loader line under the icon while it runs).
// Unsaved create/edit drafts are kept locally (never sent to GitHub before Save) and survive restarts.
// Left click = popup (list/filter, view, create, edit), right click = menu (new, secret gist from clipboard, sync, open GitHub).
RippleButton {
    id: root
    property real buttonPadding: 5
    property bool open: false
    property bool menuOpen: menu.visible
    readonly property bool pinned: open || menuOpen || draftCount > 0 || changed   // keeps the icon shown in the sliding bar row (zbar-reveal)
    property var gists: []                 // index.json: [{id, description, public, html_url, created_at, updated_at, files: [{filename, language, size, content, truncated, clipped}]}]
    property bool syncing: syncProc.running
    property string lastSync: ""           // ISO time of the last successful sync
    property string syncError: ""
    property bool busy: actProc.running     // a create/update/delete/clip is running
    property string actError: ""
    property var _onDone: null
    function gistById(id) { return gists.find(g => g.id === id) ?? null }

    // ---- Drafts. Creating and editing always happen in a draft; nothing goes to GitHub until Save. Drafts are keyed by
    // gist id ("new-<time>" for a new gist), survive going back and closing the popup, and are autosaved locally 2 s after
    // a change (~/.local/state/gist-widget/drafts-<screen>.json, 0700; one file per screen's bar), so a restart keeps them.
    // The editor works on one draft at a time through the buffer below; a draft without changes is dropped.
    property var drafts: ({})              // key -> {key, mode, id, base, origDesc, desc, public, removed, files: [{orig, name, content, origContent, locked}], savedAt}
    readonly property int draftCount: Object.keys(drafts).length
    property string activeKey: ""          // draft open in the editor ("" = editor closed)
    property ListModel draft: ListModel {} // buffer: the open draft's files (orig = name on GitHub, "" for a new file; locked = only partly loaded)
    property string draftMode: ""          // create | edit
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
        draftPublic = !!d.public; removedFiles = d.removed ?? []; activeKey = d.key; draftTick++;
    }
    function bufferObject() {
        const files = [];
        for (let i = 0; i < draft.count; i++) {
            const d = draft.get(i);
            files.push({ orig: d.orig, name: d.name, content: d.content, origContent: d.origContent, locked: d.locked });
        }
        return { key: activeKey, mode: draftMode, id: draftId, base: draftBase, origDesc: origDesc, desc: draftDesc,
                 public: draftPublic, removed: removedFiles, files: files };
    }
    function beginCreate() {
        stash();
        loadBuffer({ key: `new-${Date.now()}`, mode: "create", files: [{ orig: "", name: "", content: "", origContent: "", locked: false }] });
    }
    function beginEdit(g) {   // continues the gist's draft if it has one
        stash();
        if (drafts[g.id]) { loadBuffer(drafts[g.id]); return; }
        loadBuffer({ key: g.id, mode: "edit", id: g.id, base: g.updated_at, origDesc: g.description, desc: g.description, public: g.public,
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
            const [id, url, updated] = ok ? out.split("\n").pop().split(" ") : ["", "", ""];
            if (ok) {
                if (activeKey === key) rebase(id, updated); else discardDraft(key);
                if (args[0] === "create") Quickshell.clipboardText = url;
            }
            if (onDone) { try { onDone(ok, id); } catch (e) {} }   // the popup may be gone by now
        });
    }
    function removeGist(id, onDone) {
        return run(["delete", id], "", ok => {
            if (ok && drafts[id]) discardDraft(id);
            if (onDone) { try { onDone(ok); } catch (e) {} }
        });
    }
    function persist() { if (draftFile.path !== "") draftFile.setText(JSON.stringify({ version: 2, drafts: drafts })) }
    Timer { id: stashTimer; interval: 2000; onTriggered: root.stash() }

    readonly property string stateDir: `${Quickshell.env("HOME")}/.local/state/gist-widget`
    readonly property string screenKey: root.QsWindow.window?.screen?.name ?? ""
    property bool draftsLoaded: false
    FileView {
        id: draftFile
        path: root.screenKey !== "" ? `${root.stateDir}/drafts-${root.screenKey}.json` : ""
        atomicWrites: true
        printErrors: false
        onLoaded: {
            if (root.draftsLoaded) return;   // only the first read; later writes are ours
            root.draftsLoaded = true;
            try {
                const j = JSON.parse(text());
                if (j.version === 2 && j.drafts && typeof j.drafts === "object") root.drafts = Object.assign({}, j.drafts, root.drafts);
            } catch (e) {}
        }
        onLoadFailed: root.draftsLoaded = true
    }
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", "-m", "700", stateDir])
    readonly property string script: `${Quickshell.env("HOME")}/.config/hypr/custom/gist-widget.sh`
    readonly property string cacheDir: `${Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"}/gist-widget`

    implicitWidth: 30    // fixed size so every bar icon button is identical
    implicitHeight: 30
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    onClicked: open = !open
    // on open only when the last sync is over 5 min old; the button below syncs any time
    onOpenChanged: if (open && (!lastSync || Date.now() - Date.parse(lastSync) > 300000)) sync()

    function sync() { if (!syncProc.running) syncProc.running = true }
    // Run a mutation (create/update ID/delete ID/clip); payload goes to the script's stdin. onDone(ok, stdout) afterwards.
    function run(args, payload, onDone) {
        if (actProc.running) return false;
        actError = "";
        _onDone = onDone ?? null;
        actProc.payload = payload ?? "";
        actProc.command = ["bash", root.script].concat(args);
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

    // Right-click menu, below the button
    property string pendingMode: ""   // "create": the popup opens straight into a new gist
    altAction: () => { menu.visible = !menu.visible }
    PopupWindow {
        id: menu
        visible: false
        anchor.window: root.QsWindow.window
        anchor.onAnchoring: {
            const p = root.QsWindow.mapFromItem(root, 0, 0);
            anchor.rect = Qt.rect(p.x, p.y, root.width, root.height);
        }
        anchor.edges: Config.options.bar.bottom ? Edges.Top : Edges.Bottom
        anchor.gravity: anchor.edges === Edges.Top ? Edges.Top : Edges.Bottom
        anchor.adjustment: PopupAdjustment.All
        grabFocus: true
        color: "transparent"
        implicitWidth: menuCard.implicitWidth + 16
        implicitHeight: menuCard.implicitHeight + 16
        Rectangle {
            id: menuCard
            anchors.centerIn: parent
            implicitWidth: 250
            implicitHeight: menuCol.implicitHeight + 12
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            ColumnLayout {
                id: menuCol
                anchors { fill: parent; margins: 6 }
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
                            menu.visible = false;
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
            }
        }
    }

    // Popup is created only while open and unloaded on close (the data above stays, so reopening is instant)
    Loader {
        active: root.open
        sourceComponent: GistPopup {
            target: root
            store: root
            screen: root.QsWindow.window?.screen ?? null
            onVisibleChanged: if (!visible) root.open = false
        }
    }
}
