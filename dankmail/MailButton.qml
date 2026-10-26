import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import Quickshell.Wayland

// Mail widget for dankmail (https://github.com/arqueon/dankmail): bar button with unread badge + inbox side panel (list + thread
// detail, MailRow/MailDetail). Panel and menu behavior (open/close, click-away, Esc, monitors) comes from WidgetBase.
// Talks to the dmail daemon over its line-JSON socket ($XDG_RUNTIME_DIR/dankmail.sock): one connection for requests,
// one subscribed to daemon events so the list/badge update live. Left click = popup, middle = full app, right = menu (open, compose, sync, DND, restart, stop).
WidgetBase {
    id: root
    iconName: "mail"
    iconSize: 20
    iconOpacity: daemonConnected ? 1 : 0.4
    clickOpens: daemonConnected   // without the daemon a click opens the Dank Mail app instead
    panelCard: false               // list card + thread detail pane beside it
    panelWidth: 440 + 8 + detailWidth
    property real popupHeight: 0   // 0 = full height; set by dragging a bottom edge (list or detail)
    property real detailWidth: 620 // resizable via the detail pane's right edge
    property bool daemonConnected: false
    property int unread: 0
    property bool dnd: false
    property var threads: []
    property string view: "inbox"          // inbox | unread | starred | spam
    property bool syncing: false
    property string requestError: ""
    property var accounts: []              // [{ id, type, email, unread, ... }] from accounts.list
    property string accountFilter: ""      // "" = all accounts, else an account id; reset to All whenever the popup closes
    property int _accountsReqId: -1
    property var lastSeen: ({})            // accountId -> ISO time you last viewed that account's chip with the popup open
    property var newest: ({})              // accountId -> lastMessageAt of its newest unread thread
    property var times: ({})               // accountId -> lastMessageAt of each recent unread thread
    property var counts: ({})              // accountId -> number of unread threads that arrived after lastSeen (chip badge)
    property var fresh: ({})               // accountId -> true when unread mail arrived after lastSeen (chip shows a dot)
    property var _newestReqs: ({})         // request id -> accountId
    property int _reqId: 0
    property int _statusReqId: -1
    property int _threadsReqId: -1
    property var _syncReqs: ({})           // ids of in-flight system.sync requests
    property int _threadReqId: -1
    property int _htmlReqId: -1
    property bool _htmlForViewer: false
    property bool htmlReady: false         // the original-HTML fetch for the open thread finished (or timed out); the detail panel waits for it so it renders once
    property var rawHtml: ({})             // local message id -> original HTML of the newest received message of the open thread
    // HTML viewer (viewer/mailview.qml): one reused window; the widget writes the message HTML + a pointer file it polls
    readonly property string viewerDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/dankmail-view"
    readonly property string viewerQml: Quickshell.env("HOME") + "/.local/share/dankmail-viewer/mailview.qml"
    property int viewerSeq: 0
    property int _viewerSlot: 0
    property string _viewerPointer: ""
    property var currentThread: null       // full thread (with messages) shown in the popup's detail panel
    property int selectedId: -1
    property int pageSize: 25
    property int limit: pageSize            // how many threads the list currently asks the local cache for
    property bool localExhausted: false     // the cache returned fewer than `limit` threads
    property bool olderDone: false          // the server has no older mail left to pull
    property bool loadingMore: false        // spinner at the bottom of the list
    property var olderNext: null            // opaque per-account cursor for threads.fetchOlder
    property int _olderReqId: -1


    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/dankmail.sock"

    // Loader line under the icon while the daemon is starting or the app window is opening
    property bool starting: false
    readonly property bool busy: starting || openProc.running
    onDaemonConnectedChanged: if (daemonConnected) { starting = false; startGuard.stop(); }
    Process { id: openProc; command: ["bash", "-c", "$HOME/.config/hypr/custom/dankmail-toggle.sh"] }
    Timer { id: startGuard; interval: 30000; onTriggered: root.starting = false }
    Timer { interval: 1000; repeat: true; running: root.starting; onTriggered: { cmdSocket.connected = false; cmdSocket.connected = true; } }  // reconnect fast while starting
    function toggleApp() {
        if (daemonConnected) { if (!openProc.running) openProc.running = true; }
        else if (!starting) {
            starting = true; startGuard.restart();
            Quickshell.execDetached(["systemctl", "--user", "start", "dmail"]);
        }
    }
    // "Stop dankmail completely": react at once (close the popup, drop the connection so the icon dims) instead of waiting for the socket to notice
    function stopDaemon() {
        open = false; closeThread();
        cmdSocket.connected = false;          // -> daemonConnected = false, state cleared, reconnect timer armed
        Quickshell.execDetached(["systemctl", "--user", "stop", "dmail"]);  // not "dmail kill": that exits non-zero and systemd (Restart=on-failure) revives it
    }
    function send(sock, obj) { sock.write(JSON.stringify(obj) + "\n"); sock.flush(); }
    function call(method, params) {
        if (!cmdSocket.connected) return -1;
        _reqId++;
        send(cmdSocket, { "id": _reqId, "method": method, "params": params || {} });
        return _reqId;
    }
    function refresh() {
        if (!cmdSocket.connected) return;
        _statusReqId = call("system.status", {});
        _accountsReqId = call("accounts.list", {});
        if (selectedId >= 0) _threadReqId = call("threads.get", { "id": selectedId });
        _threadsReqId = call("threads.list", view === "spam" ? { "inbox": false, "label": "SPAM", "limit": limit, "account": accountFilter }
            : { "inbox": view !== "starred", "starred": view === "starred", "unread": view === "unread", "limit": limit, "account": accountFilter });
    }
    // Scrolled to the bottom: first reveal more of the local cache, then pull an older month from the server.
    function loadMore() {
        if (!cmdSocket.connected || loadingMore) return;
        if (!localExhausted) { loadingMore = true; limit += pageSize; refresh(); return; }
        if (olderDone || view === "starred" || view === "spam") return;
        loadingMore = true;
        _olderReqId = call("threads.fetchOlder", olderNext ? { "next": olderNext } : {});
        olderGuard.restart();
    }
    function op(method, id) { call(method, { "ids": [id] }); }
    function syncNow() {
        if (!cmdSocket.connected || syncing) return;
        requestError = "";
        syncing = true;
        syncGuard.restart();
        // Account selected: sync just it. None selected: one request per account, all in flight at once.
        const ids = accountFilter !== "" ? [accountFilter] : accounts.map(a => a.id);
        const pending = {};
        if (ids.length === 0) pending[call("system.sync", {})] = true;
        for (const id of ids) pending[call("system.sync", { "accountId": id })] = true;
        _syncReqs = pending;
    }
    function selectThread(id) {
        if (id === selectedId) { closeThread(); return; }
        selectedId = id;
        currentThread = null;
        _threadReqId = call("threads.get", { "id": id });
        call("threads.previewOpened", { "id": id });
        rawHtml = ({});
        htmlReady = false;
        htmlGuard.restart();
        fetchHtml(id, false);
    }
    // Fetch the original HTML of the thread's newest received message: rendered in place by the detail panel,
    // or (forViewer) shown in the Chromium viewer window (viewer/mailview.qml), started on first use and reused after
    function fetchHtml(threadId, forViewer) {
        if (!cmdSocket.connected) return;
        _htmlForViewer = forViewer;
        _htmlReqId = call("messages.getHtml", { "threadId": threadId });
    }
    function showInViewer(result) {
        const esc = t => (t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const body = result.html ? result.html
            : '<pre style="white-space:pre-wrap;font:14px sans-serif;margin:16px;color:#222">' + esc(result.text) + '</pre>';
        const slot = _viewerSlot; _viewerSlot = 1 - _viewerSlot;
        const file = slot === 0 ? htmlFile0 : htmlFile1;
        viewerSeq++;
        _viewerPointer = file.path + "\n" + (result.subject || "Mail").replace(/\n/g, " ") + "\n" + viewerSeq;
        file.setText('<!doctype html><meta charset="utf-8"><base target="_blank">' + body);
    }
    function _viewerFileSaved() {
        ptrFile.setText(_viewerPointer);
        if (!viewerProc.running) viewerProc.running = true;
    }
    function closeThread() { selectedId = -1; currentThread = null; _threadReqId = -1; }
    function updateFresh() {
        const f = {};
        for (const id in newest) f[id] = !!newest[id] && !!lastSeen[id] && Date.parse(newest[id]) > Date.parse(lastSeen[id]);
        fresh = f;
        const c = {};
        for (const id in times) c[id] = !lastSeen[id] ? 0 : times[id].filter(t => Date.parse(t) > Date.parse(lastSeen[id])).length;
        counts = c;
    }
    // Viewing one account (popup open, that chip selected) counts as a visit; the first run starts everything as seen
    function markSeen() {
        const now = new Date().toISOString(), ls = Object.assign({}, lastSeen);
        let changed = false;
        for (const a of accounts) if (!ls[a.id]) { ls[a.id] = now; changed = true; }
        if (open && accountFilter !== "") { ls[accountFilter] = now; changed = true; }
        if (!changed) return;
        lastSeen = ls;
        seenStore.setText(JSON.stringify(ls));
        updateFresh();
    }
    function setAccount(id) { accountFilter = id; markSeen(); limit = pageSize; localExhausted = false; olderNext = null; olderDone = false; closeThread(); refresh(); }
    function setView(v) { view = v; limit = pageSize; localExhausted = false; refresh(); }
    function handleResponse(msg) {
        if (msg.id === _olderReqId) {
            _olderReqId = -1; olderGuard.stop(); loadingMore = false;
            if (msg.error || !msg.result) return;
            olderNext = msg.result.next || null;
            olderDone = !msg.result.next || Object.keys(msg.result.next).length === 0;
            if (msg.result.ingested > 0) { limit += pageSize; localExhausted = false; refresh(); }
            else if (!olderDone) loadMore();   // empty window: keep walking back
            return;
        }
        if (msg.id === _htmlReqId) {
            _htmlReqId = -1;
            if (msg.result && _htmlForViewer) showInViewer(msg.result);
            else if (!_htmlForViewer) {
                if (msg.result && msg.result.html) { const r = {}; r[msg.result.messageId] = msg.result.html; rawHtml = r; }
                htmlReady = true; htmlGuard.stop();
            }
            return;
        }
        if (msg.id in _syncReqs) {
            const p = Object.assign({}, _syncReqs); delete p[msg.id]; _syncReqs = p;
            if (Object.keys(p).length === 0) { syncing = false; syncGuard.stop(); }
        }
        if (msg.error && msg.id === _threadReqId) { closeThread(); return; }
        if (msg.error) { requestError = qsTr("The request failed. Open Dank Mail to check the account."); return; }
        if (msg.id in _newestReqs && Array.isArray(msg.result)) {
            const n = Object.assign({}, newest); n[_newestReqs[msg.id]] = msg.result.length ? msg.result[0].lastMessageAt : "";
            const tm = Object.assign({}, times); tm[_newestReqs[msg.id]] = msg.result.map(t => t.lastMessageAt);
            newest = n; times = tm; updateFresh();
            if (open && accountFilter === _newestReqs[msg.id]) markSeen();
            return;
        }
        if (msg.id === _threadReqId && msg.result) { if (msg.result.id === selectedId) currentThread = msg.result; return; }
        if (msg.id === _accountsReqId && msg.result) {
            accounts = msg.result.accounts || msg.result;
            if (accountFilter !== "" && !accounts.some(a => a.id === accountFilter)) accountFilter = "";
            if (seenStore.loaded) {
                markSeen();
                const reqs = {};
                for (const a of accounts) reqs[call("threads.list", { "inbox": true, "unread": true, "limit": 100, "account": a.id })] = a.id;
                _newestReqs = reqs;
            }
        } else if (msg.id === _statusReqId && msg.result) {
            unread = msg.result.unread || 0;
            dnd = !!msg.result.dnd;
        } else if (msg.id === _threadsReqId && Array.isArray(msg.result)) {
            threads = msg.result;
            localExhausted = msg.result.length < limit;
            if (_olderReqId < 0) loadingMore = false;
        }
    }
    function clearState() {
        unread = 0; dnd = false; threads = []; syncing = false; requestError = "";
        _statusReqId = -1; _threadsReqId = -1; _syncReqs = ({}); closeThread();
        loadingMore = false; _olderReqId = -1; olderNext = null; olderDone = false; localExhausted = false; limit = pageSize;
        syncGuard.stop();
    }

    middleClickAction: () => toggleApp()       // middle click
    onClicked: if (!daemonConnected) toggleApp()
    // Opening refreshes; closing (by any path) closes the thread and goes back to All accounts (the selection is not persisted)
    onOpenChanged: {
        if (open) { limit = pageSize; markSeen(); refresh(); }
        else { closeThread(); if (accountFilter !== "") setAccount(""); }
    }

    Component.onCompleted: { Quickshell.execDetached(["mkdir", "-p", viewerDir]); cmdSocket.connected = true; }

    // Per-account "last viewed" times, so a chip can show a dot for mail that arrived since
    FileView {
        id: seenStore
        property bool loaded: false
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/user/dankmail-seen.json"
        onLoaded: { try { root.lastSeen = JSON.parse(text()) || {}; } catch (e) { root.lastSeen = {}; } loaded = true; root.refresh(); }
        onLoadFailed: { loaded = true; root.refresh(); }   // first run: no file yet
    }

    Process {
        id: viewerProc
        command: ["qml6", root.viewerQml, root.viewerDir + "/current"]
        environment: ({ "QML_XHR_ALLOW_FILE_READ": "1" })
        onRunningChanged: if (!running) Quickshell.execDetached(["bash", "-c", "rm -f '" + root.viewerDir + "'/msg-*.html '" + root.viewerDir + "/current'"])
    }
    FileView { id: htmlFile0; path: root.viewerDir + "/msg-0.html"; atomicWrites: true; onSaved: root._viewerFileSaved() }
    FileView { id: htmlFile1; path: root.viewerDir + "/msg-1.html"; atomicWrites: true; onSaved: root._viewerFileSaved() }
    FileView { id: ptrFile; path: root.viewerDir + "/current"; atomicWrites: true }

    Socket {
        id: cmdSocket
        path: root.socketPath
        connected: false
        onConnectionStateChanged: {
            root.daemonConnected = connected;
            if (connected) { subSocket.connected = true; root.refresh(); retryTimer.stop(); }
            else { subSocket.connected = false; root.clearState(); root.open = false; retryTimer.restart(); }
        }
        parser: SplitParser {
            onRead: line => {
                if (!line) return;
                let msg; try { msg = JSON.parse(line); } catch (e) { return; }
                if (msg.id !== undefined) root.handleResponse(msg);
            }
        }
    }
    Socket {
        id: subSocket
        path: root.socketPath
        connected: false
        onConnectionStateChanged: {
            if (connected) root.send(subSocket, { "id": 1, "method": "subscribe" });
            else if (root.daemonConnected) subRetry.restart();
        }
        parser: SplitParser {
            onRead: line => {
                if (!line) return;
                let ev; try { ev = JSON.parse(line); } catch (e) { return; }
                switch (ev.topic) {
                case "threads.changed": case "unread.changed": case "ops.applied": case "accounts.changed": case "snooze.woke":
                    refreshDebounce.restart(); break;
                case "dnd.changed": root.dnd = !!(ev.payload && ev.payload.enabled); break;
                }
            }
        }
    }
    Timer { id: refreshDebounce; interval: 300; onTriggered: root.refresh() }
    Timer { id: subRetry; interval: 4000; onTriggered: if (cmdSocket.connected) subSocket.connected = true }
    Timer { id: olderGuard; interval: 120000; onTriggered: { root.loadingMore = false; root._olderReqId = -1; } }
    Timer { id: htmlGuard; interval: 5000; onTriggered: root.htmlReady = true }   // slow or failed fetch: show the text version
    Timer { id: syncGuard; interval: 20000; onTriggered: root.syncing = false }
    // Reconnect while the daemon is down, and a slow safety poll while it is up
    Timer { id: retryTimer; interval: 5000; repeat: true; onTriggered: { cmdSocket.connected = false; cmdSocket.connected = true; } }
    Timer { interval: 60000; repeat: true; running: root.daemonConnected; onTriggered: root.refresh() }

    readonly property int newTotal: { let n = 0; for (const id in counts) n += counts[id]; return n; }
    Rectangle {  // new mail since you last viewed each account (hidden at 0)
        visible: root.newTotal > 0
        anchors { top: parent.top; right: parent.right; topMargin: 2; rightMargin: 0 }
        implicitWidth: Math.max(14, newText.implicitWidth + 8); implicitHeight: 14; radius: 7
        color: root.dnd ? Appearance.colors.colOutline : Appearance.colors.colPrimary
        StyledText {
            id: newText
            anchors.centerIn: parent
            text: root.newTotal > 99 ? "99+" : root.newTotal
            font.pixelSize: 9
            color: Appearance.colors.colOnPrimary
        }
    }

    Item {  // indeterminate loader line below the icon (same as the Teams button)
        id: loader
        visible: root.busy
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

    menuContent: Component { MailMenu { store: root; onCloseRequested: root.closeMenu() } }

    panelContent: Component { FocusScope {
        id: ml
        readonly property bool detailOpen: root.selectedId >= 0
        // full height below the bar like every left panel; dragging a bottom edge overrides it
        readonly property real contentHeight: root.popupHeight > 0 ? Math.min(root.popupHeight, height - 2 * Appearance.sizes.hyprlandGapsOut) : height - 2 * Appearance.sizes.hyprlandGapsOut
        // WidgetBase contract for a custom layout: input only on the list card and, while a thread is open, the detail pane
        readonly property list<Item> panelMaskItems: detailOpen ? [panel, detail] : [panel]
        // Esc closes the open thread first, then (falls through to WidgetBase) the panel
        Keys.onEscapePressed: event => { if (ml.detailOpen) root.closeThread(); else event.accepted = false }

    StyledRectangularShadow { target: panel }
    StyledRectangularShadow { target: detail; visible: ml.detailOpen }

    MailDetail {
        id: detail
        // not visible-toggled: re-showing it lost every cursor shape inside (Qt cursor-in-child bookkeeping); fade instead
        opacity: ml.detailOpen ? 1 : 0
        enabled: ml.detailOpen
        store: root
        anchors { left: panel.right; top: panel.top; leftMargin: 8 }
        width: root.detailWidth
        height: ml.contentHeight
        onCloseRequested: root.closeThread()

        MouseArea {  // resize handle (right edge); incremental deltas stay stable while the window grows under the cursor
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 8
            cursorShape: Qt.SizeHorCursor
            property real pressX
            onPressed: mouse => pressX = mouse.x
            onPositionChanged: mouse => {
                if (pressed) root.detailWidth = Math.max(320, Math.min(900, root.detailWidth + mouse.x - pressX));
            }
        }

        MouseArea {  // resize handle (bottom edge)
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 8
            cursorShape: Qt.SizeVerCursor
            property real pressY
            onPressed: mouse => pressY = mouse.y
            onPositionChanged: mouse => {
                if (pressed) root.popupHeight = Math.max(240, Math.min(1100, ml.contentHeight + mouse.y - pressY));
            }
        }
    }

    Rectangle {
        id: panel
        // same place as every left panel: hyprland outer gap from the screen's left edge and the bar
        x: Appearance.sizes.hyprlandGapsOut; y: Appearance.sizes.hyprlandGapsOut
        width: 440
        height: ml.contentHeight
        implicitHeight: header.implicitHeight + (listArea.implicitHeight) + 20
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        MouseArea {  // resize handle (bottom edge)
            z: 10
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 8
            cursorShape: Qt.SizeVerCursor
            property real pressY
            onPressed: mouse => pressY = mouse.y
            onPositionChanged: mouse => {
                if (pressed) root.popupHeight = Math.max(240, Math.min(1100, ml.contentHeight + mouse.y - pressY));
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header: title, tabs, actions
            RowLayout {
                id: header
                Layout.fillWidth: true
                Layout.margins: 12
                spacing: 8
                Repeater {
                    model: [{ "k": "inbox", "t": "All" }, { "k": "unread", "t": "Unread" }, { "k": "starred", "t": "Starred" }, { "k": "spam", "t": "Spam" }]
                    delegate: RippleButton {
                        required property var modelData
                        implicitHeight: 28
                        implicitWidth: tabText.implicitWidth + 24
                        buttonRadius: 14
                        toggled: root.view === modelData.k
                        onClicked: root.setView(modelData.k)
                        StyledText {
                            id: tabText
                            anchors.centerIn: parent
                            text: modelData.t
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                RippleButton {
                    implicitWidth: 28; implicitHeight: 28; buttonRadius: 14
                    onClicked: root.syncNow()
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "sync"; iconSize: 18; color: Appearance.colors.colOnLayer1
                        RotationAnimation on rotation { running: root.syncing; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                    }
                    StyledToolTip { text: "Sync now" }
                }
                RippleButton {
                    implicitWidth: 28; implicitHeight: 28; buttonRadius: 14
                    onClicked: { root.toggleApp(); root.close(); }
                    MaterialSymbol { anchors.centerIn: parent; text: "open_in_full"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                    StyledToolTip { text: "Open Dank Mail" }
                }
            }

            // Account switcher (only when more than one account is connected): one row of equal chips
            RowLayout {
                visible: root.accounts.length > 1
                Layout.fillWidth: true
                Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.bottomMargin: 10
                spacing: 6
                Repeater {
                    model: [{ "id": "", "label": "All", "icon": "inbox", "logo": "", "unread": 0, "fresh": false, "email": "All accounts" }].concat(root.accounts.map(a => ({ "id": a.id, "label": a.email.split("@")[0], "logo": a.type === "gmail" ? "gmail" : (a.type === "microsoft" || /(outlook|hotmail|live|msn)\./i.test(a.email)) ? "outlook" : "mail", "unread": root.counts[a.id] || 0, "fresh": !!root.fresh[a.id], "email": a.email })))
                    delegate: RippleButton {
                        id: chip
                        required property var modelData
                        // The selected account chip grows to show the full address
                        readonly property bool expanded: toggled && modelData.id !== ""
                        Layout.preferredWidth: chipRow.implicitWidth + 18
                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        implicitHeight: 32
                        buttonRadius: 16
                        toggled: root.accountFilter === modelData.id
                        onClicked: root.setAccount(modelData.id)
                        readonly property color fg: Appearance.colors.colOnLayer1   // plain black/white like the other shell icons
                        colBackgroundToggled: Appearance.colors.colLayer2Active
                        colBackgroundToggledHover: Appearance.colors.colLayer2Active
                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 5
                            MaterialSymbol { visible: chip.modelData.logo === ""; text: chip.modelData.icon ?? ""; iconSize: 20; color: chip.fg }
                            Image {
                                visible: chip.modelData.logo !== ""
                                source: visible ? Quickshell.shellPath("assets/icons/mail/" + chip.modelData.logo + ".svg") : ""
                                sourceSize: Qt.size(40, 40)
                                Layout.preferredWidth: 20; Layout.preferredHeight: 20
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: true     // monochrome: tint the white glyph with the chip's text colour
                                layer.effect: MultiEffect { colorization: 1; colorizationColor: chip.fg }
                            }
                            StyledText {
                                visible: chip.expanded
                                text: chip.modelData.email
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: chip.fg
                            }
                        }
                        Rectangle {  // count of mail that arrived since you last viewed this account; overlays the corner so chips keep their size
                            visible: chip.modelData.unread > 0 && !chip.toggled
                            anchors { top: parent.top; right: parent.right; topMargin: 0; rightMargin: 1 }
                            implicitWidth: Math.max(16, badgeText.implicitWidth + 8); implicitHeight: 16; radius: 8
                            color: Appearance.colors.colPrimary
                            border.width: 2; border.color: Appearance.colors.colLayer1
                            StyledText {
                                id: badgeText
                                anchors.centerIn: parent
                                text: chip.modelData.unread > 99 ? "99+" : chip.modelData.unread
                                font { pixelSize: 9; weight: Font.Bold }
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                        StyledToolTip { text: chip.modelData.email + (chip.modelData.unread > 0 ? qsTr(" (%1 new)").arg(chip.modelData.unread) : "") }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }

            Item {
                id: listArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: root.threads.length > 0 ? Math.min(670, root.threads.length * 78) : 120

                StyledText {
                    anchors.centerIn: parent
                    visible: root.threads.length === 0
                    text: root.requestError !== "" ? root.requestError
                        : root.view === "starred" ? "No starred mail."
                        : root.view === "spam" ? "No spam."
                        : root.view === "unread" ? "No unread mail." : "No mail in the inbox."
                    color: Appearance.colors.colSubtext
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    visible: root.threads.length > 0
                    model: root.threads
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    maximumFlickVelocity: 6000
                    property real wheelTarget: 0
                    Behavior on contentY { enabled: wheelArea.animating; NumberAnimation { duration: 140; easing.type: Easing.OutCubic; onRunningChanged: if (!running) wheelArea.animating = false } }
                    MouseArea {  // same bigger, smoothed wheel steps as the mail detail panel
                        id: wheelArea
                        property bool animating: false
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: w => {
                            const maxY = Math.max(0, list.contentHeight - list.height);
                            const base = animating ? list.wheelTarget : list.contentY;
                            const step = Math.abs(w.angleDelta.y) >= 120 ? 1.6 : 0.5;  // mouse notch vs touchpad
                            list.wheelTarget = Math.max(0, Math.min(base - w.angleDelta.y * step, maxY));
                            animating = true;
                            list.contentY = list.wheelTarget;
                            w.accepted = true;
                        }
                    }
                    delegate: MailRow { width: list.width; store: root }
                    function checkEnd() { if (contentHeight > 0 && contentHeight - contentY - height < 160) root.loadMore(); }
                    onContentYChanged: checkEnd()
                    onContentHeightChanged: loadMoreTimer.restart()
                    Timer { id: loadMoreTimer; interval: 150; onTriggered: list.checkEnd() }
                    footer: Item {
                        width: list.width
                        height: root.loadingMore ? 44 : 0
                        visible: root.loadingMore
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol {
                                text: "progress_activity"; iconSize: 20; color: Appearance.colors.colSubtext
                                RotationAnimation on rotation { running: root.loadingMore; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                            }
                            StyledText { text: "Loading older mail…"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                        }
                    }
                }
            }
        }
    }
    } }
}
