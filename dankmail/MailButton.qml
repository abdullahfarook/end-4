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

    function toggleApp() {
        if (daemonConnected) Quickshell.execDetached(["bash", "-c", "$HOME/.config/hypr/custom/dankmail-toggle.sh"]);
        else Quickshell.execDetached(["systemctl", "--user", "start", "dmail"]);
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
        if (selectedId >= 0) _threadReqId = call("threads.get", { "id": selectedId });
        _threadsReqId = call("threads.list", { "inbox": view !== "starred", "starred": view === "starred", "unread": view === "unread", "limit": limit });
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
        _syncReqId = call("system.sync", {});
    }
    function selectThread(id) {
        if (id === selectedId) { closeThread(); return; }
        selectedId = id;
        currentThread = null;
        _threadReqId = call("threads.get", { "id": id });
        call("threads.previewOpened", { "id": id });
    }
    function closeThread() { selectedId = -1; currentThread = null; _threadReqId = -1; }
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
        if (msg.id === _threadReqId && msg.result) { if (msg.result.id === selectedId) currentThread = msg.result; return; }
        if (msg.id === _statusReqId && msg.result) {
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
        if (menuLoader.active && menuLoader.item && typeof menuLoader.item.close === "function") menuLoader.item.close();
        else menuLoader.active = true;
    }
    middleClickAction: () => toggleApp()       // middle click
    onClicked: {
        if (!daemonConnected) toggleApp();
        else { popupOpen = !popupOpen; if (popupOpen) { limit = pageSize; refresh(); } else closeThread(); }
    }

    Component.onCompleted: cmdSocket.connected = true

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
    Rectangle {  // unread dot (the cache only holds recent mail, so a count would be misleading)
        visible: root.unread > 0
        anchors { top: parent.top; right: parent.right; topMargin: 4; rightMargin: 4 }
        implicitWidth: 8; implicitHeight: 8; radius: 4
        color: root.dnd ? Appearance.colors.colOutline : Appearance.colors.colPrimary
    }

    Loader {
        id: menuLoader
        active: false
        sourceComponent: MailMenu {
            store: root
            Component.onCompleted: this.open()
            anchor {
                window: root.QsWindow.window
                item: root
                gravity: Config.options.bar.vertical ? (Config.options.bar.bottom ? Edges.Left : Edges.Right) : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
                edges: Config.options.bar.vertical ? (Config.options.bar.bottom ? Edges.Left : Edges.Right) : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
            }
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
