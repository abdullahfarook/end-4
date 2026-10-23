import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Bar button for the Gist widget: your GitHub gists (gh) mirrored in a local cache by gist-widget.sh.
// Syncs in the background every 5 minutes and whenever the popup opens (loader line under the icon while it runs).
// An unsaved create/edit draft is autosaved locally (never to GitHub) and restored after a shell restart; a dot marks it.
// Left click = popup (list/filter, view, create, edit), right click = menu (new, secret gist from clipboard, sync, open GitHub).
RippleButton {
    id: root
    property real buttonPadding: 5
    property bool open: false
    property bool menuOpen: menu.visible
    readonly property bool hasDraft: draftMode !== "" && draftDirty
    readonly property bool pinned: open || menuOpen || hasDraft   // keeps the icon shown in the sliding bar row (zbar-reveal)
    property var gists: []                 // index.json: [{id, description, public, html_url, created_at, updated_at, files: [{filename, language, size, content, truncated, clipped}]}]
    property bool syncing: syncProc.running
    property string lastSync: ""           // ISO time of the last successful sync
    property string syncError: ""
    property bool busy: actProc.running     // a create/update/delete/clip is running
    property string actError: ""
    property var _onDone: null
    // Editor draft (GistPopup): kept here so closing the popup doesn't lose it
    property string draftMode: ""          // "" | create | edit
    property string draftId: ""
    property string draftDesc: ""
    property bool draftPublic: false
    property bool draftDirty: false
    property var removedFiles: []
    property ListModel draft: ListModel {}
    property string draftBase: ""          // the gist's updated_at when editing started (warns before overwriting newer changes)
    property string draftSavedAt: ""       // last local autosave
    property bool draftRestored: false     // restored from disk; the popup says so once

    // Local draft autosave: 2 s after the last change, to ~/.local/state/gist-widget (0700), one file per screen's bar.
    // Never calls GitHub; the file is removed when the draft is saved or discarded.
    readonly property string stateDir: `${Quickshell.env("HOME")}/.local/state/gist-widget`
    readonly property string screenKey: root.QsWindow.window?.screen?.name ?? ""
    function touchDraft() { draftDirty = true; draftTimer.restart() }
    function clearSavedDraft() {
        draftTimer.stop(); draftSavedAt = "";
        if (draftFile.path !== "") Quickshell.execDetached(["rm", "-f", draftFile.path]);
    }
    function writeDraft() {
        if (draftMode === "" || !draftDirty || draftFile.path === "") return;
        const files = [];
        for (let i = 0; i < draft.count; i++) {
            const d = draft.get(i);
            files.push({ orig: d.orig, name: d.name, content: d.content, locked: d.locked });
        }
        draftSavedAt = new Date().toISOString();
        draftFile.setText(JSON.stringify({ version: 1, mode: draftMode, id: draftId, base: draftBase, desc: draftDesc,
            public: draftPublic, removed: removedFiles, files: files, savedAt: draftSavedAt }));
    }
    Timer { id: draftTimer; interval: 2000; onTriggered: root.writeDraft() }
    FileView {
        id: draftFile
        path: root.screenKey !== "" ? `${root.stateDir}/draft-${root.screenKey}.json` : ""
        atomicWrites: true
        printErrors: false
        onLoaded: {
            if (root.draftMode !== "") return;   // never replace a draft that is already in memory
            try {
                const j = JSON.parse(text());
                if (j.version !== 1 || !["create", "edit"].includes(j.mode) || !Array.isArray(j.files)) return;
                root.draft.clear();
                for (const f of j.files) root.draft.append({ orig: f.orig ?? "", name: f.name ?? "", content: f.content ?? "", locked: !!f.locked });
                root.draftId = j.id ?? ""; root.draftBase = j.base ?? ""; root.draftDesc = j.desc ?? "";
                root.draftPublic = !!j.public; root.removedFiles = j.removed ?? []; root.draftSavedAt = j.savedAt ?? "";
                root.draftDirty = true; root.draftMode = j.mode; root.draftRestored = true;
            } catch (e) {}
        }
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
    onOpenChanged: if (open) sync()

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
    Timer { interval: 300000; repeat: true; running: true; onTriggered: root.sync() }
    Timer { interval: 8000; running: true; onTriggered: root.sync() }   // first sync shortly after the shell starts

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

    MaterialSymbol {
        anchors.centerIn: parent
        text: "data_object"
        iconSize: 21
        color: root.syncError !== "" ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
    }
    Rectangle {  // unsaved draft: small dot top-right, like the mail/Teams badges
        visible: root.hasDraft
        anchors { top: parent.top; right: parent.right; topMargin: 4; rightMargin: 3 }
        implicitWidth: 8; implicitHeight: 8; radius: 4
        color: Appearance.colors.colPrimary
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
            onVisibleChanged: if (!visible) root.open = false
        }
    }
}
