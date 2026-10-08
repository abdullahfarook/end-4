import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets

// Bar button for dankmail (https://github.com/arqueon/dankmail): unread badge + click-to-open inbox popup (MailPopup.qml).
// Talks to the dmail daemon over its line-JSON socket ($XDG_RUNTIME_DIR/dankmail.sock): one connection for requests,
// one subscribed to daemon events so the list/badge update live. Left click = popup, middle = full app, right = menu (open, compose, sync, DND, restart, stop).
RippleButton {
    id: root
    property real buttonPadding: 5
    property bool daemonConnected: false
    property int unread: 0
    property bool dnd: false
    property var threads: []
    property string view: "inbox"          // inbox | unread | starred
    property bool syncing: false
    property string requestError: ""
    property bool popupOpen: false
    property var accounts: []              // [{ id, type, email, unread, ... }] from accounts.list
    property string accountFilter: ""      // "" = all accounts, else an account id; kept while the shell runs, reset to All on restart
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
    property int _syncReqId: -1
    property int _threadReqId: -1
    property var currentThread: null       // full thread (with messages) shown in the popup's detail panel
    property int selectedId: -1
    property int pageSize: 25
    property int limit: pageSize            // how many threads the list currently asks the local cache for
    property bool localExhausted: false     // the cache returned fewer than `limit` threads
    property bool olderDone: false          // the server has no older mail left to pull
    property bool loadingMore: false        // spinner at the bottom of the list
    property var olderNext: null            // opaque per-account cursor for threads.fetchOlder
    property int _olderReqId: -1

    implicitWidth: icon.implicitWidth + buttonPadding * 2
    implicitHeight: icon.implicitHeight + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

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
        popupOpen = false; closeThread();
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
        _threadsReqId = call("threads.list", { "inbox": view !== "starred", "starred": view === "starred", "unread": view === "unread", "limit": limit, "account": accountFilter });
    }
    // Scrolled to the bottom: first reveal more of the local cache, then pull an older month from the server.
    function loadMore() {
        if (!cmdSocket.connected || loadingMore) return;
        if (!localExhausted) { loadingMore = true; limit += pageSize; refresh(); return; }
        if (olderDone || view === "starred") return;
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
        _syncReqId = call("system.sync", accountFilter !== "" ? { "accountId": accountFilter } : {});
    }
    function selectThread(id) {
        if (id === selectedId) { closeThread(); return; }
        selectedId = id;
        currentThread = null;
        _threadReqId = call("threads.get", { "id": id });
        call("threads.previewOpened", { "id": id });
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
        if (popupOpen && accountFilter !== "") { ls[accountFilter] = now; changed = true; }
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
        if (msg.id === _syncReqId) { syncing = false; syncGuard.stop(); }
        if (msg.error && msg.id === _threadReqId) { closeThread(); return; }
        if (msg.error) { requestError = qsTr("The request failed. Open Dank Mail to check the account."); return; }
        if (msg.id in _newestReqs && Array.isArray(msg.result)) {
            const n = Object.assign({}, newest); n[_newestReqs[msg.id]] = msg.result.length ? msg.result[0].lastMessageAt : "";
            const tm = Object.assign({}, times); tm[_newestReqs[msg.id]] = msg.result.map(t => t.lastMessageAt);
            newest = n; times = tm; updateFresh();
            if (popupOpen && accountFilter === _newestReqs[msg.id]) markSeen();
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
        _statusReqId = -1; _threadsReqId = -1; _syncReqId = -1; closeThread();
        loadingMore = false; _olderReqId = -1; olderNext = null; olderDone = false; localExhausted = false; limit = pageSize;
        syncGuard.stop();
    }

    altAction: () => {                         // right click: menu
        if (menuLoader.active) menuLoader.active = false;
        else menuLoader.active = true;
    }
    middleClickAction: () => toggleApp()       // middle click
    onClicked: {
        if (!daemonConnected) toggleApp();
        else { popupOpen = !popupOpen; if (popupOpen) { limit = pageSize; markSeen(); refresh(); } else closeThread(); }
    }

    Component.onCompleted: cmdSocket.connected = true

    // Per-account "last viewed" times, so a chip can show a dot for mail that arrived since
    FileView {
        id: seenStore
        property bool loaded: false
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/user/dankmail-seen.json"
        onLoaded: { try { root.lastSeen = JSON.parse(text()) || {}; } catch (e) { root.lastSeen = {}; } loaded = true; root.refresh(); }
        onLoadFailed: { loaded = true; root.refresh(); }   // first run: no file yet
    }

    Socket {
        id: cmdSocket
        path: root.socketPath
        connected: false
        onConnectionStateChanged: {
            root.daemonConnected = connected;
            if (connected) { subSocket.connected = true; root.refresh(); retryTimer.stop(); }
            else { subSocket.connected = false; root.clearState(); root.popupOpen = false; retryTimer.restart(); }
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
    Timer { id: syncGuard; interval: 20000; onTriggered: root.syncing = false }
    // Reconnect while the daemon is down, and a slow safety poll while it is up
    Timer { id: retryTimer; interval: 5000; repeat: true; onTriggered: { cmdSocket.connected = false; cmdSocket.connected = true; } }
    Timer { interval: 60000; repeat: true; running: root.daemonConnected; onTriggered: root.refresh() }

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        text: "mail"
        iconSize: 20
        color: Appearance.colors.colOnLayer0
        opacity: root.daemonConnected ? 1 : 0.4
    }
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

    Loader {
        id: menuLoader
        active: false
        sourceComponent: MailMenu {
            store: root
            hoverTarget: root
            onMenuClosed: menuLoader.active = false
        }
    }

    MailPopup {
        store: root
        open: root.popupOpen
        hoverTarget: root
        onCloseRequested: { root.popupOpen = false; root.closeThread(); }
    }
}
