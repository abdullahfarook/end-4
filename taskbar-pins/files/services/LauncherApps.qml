pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell

Singleton {
    id: root

    function isPinned(appId) {
        return Config.options.launcher.pinnedApps.indexOf(appId) !== -1;
    }

    function togglePin(appId) {
        if (root.isPinned(appId)) {
            Config.options.launcher.pinnedApps = Config.options.launcher.pinnedApps.filter(id => id !== appId)
        } else {
            Config.options.launcher.pinnedApps = Config.options.launcher.pinnedApps.concat([appId])
        }
    }

    function pinIndex(appId) {
        return Config.options.launcher.pinnedApps.findIndex(id => id.toLowerCase() === appId.toLowerCase());
    }

    function pin(appId) {
        if (root.pinIndex(appId) === -1)
            Config.options.launcher.pinnedApps = Config.options.launcher.pinnedApps.concat([appId]);
    }

    function unpin(appId) {
        Config.options.launcher.pinnedApps = Config.options.launcher.pinnedApps.filter(id => id.toLowerCase() !== appId.toLowerCase());
    }

    function movePin(fromIdx, toIdx) {
        const list = Config.options.launcher.pinnedApps.slice();
        toIdx = Math.max(0, Math.min(list.length - 1, toIdx));
        if (fromIdx < 0 || fromIdx >= list.length || toIdx === fromIdx) return;
        list.splice(toIdx, 0, list.splice(fromIdx, 1)[0]);
        Config.options.launcher.pinnedApps = list;
    }

    function moveToFront(appId) {
        if (!root.isPinned(appId)) return;
        const pinnedApps = Config.options.launcher.pinnedApps;
        Config.options.launcher.pinnedApps = [appId].concat(pinnedApps.filter(id => id !== appId));
    }

    function moveLeft(appId) {
        const pinnedApps = Config.options.launcher.pinnedApps;
        const index = pinnedApps.indexOf(appId);
        if (index === -1 || index === 0) return;
        Config.options.launcher.pinnedApps = pinnedApps.slice(0, index - 1).concat([appId]).concat(pinnedApps[index - 1]).concat(pinnedApps.slice(index + 1));
    }

    function moveRight(appId) {
        const pinnedApps = Config.options.launcher.pinnedApps;
        const index = pinnedApps.indexOf(appId);
        if (index === -1 || index === pinnedApps.length - 1) return;
        Config.options.launcher.pinnedApps = pinnedApps.slice(0, index).concat(pinnedApps[index + 1]).concat([appId]).concat(pinnedApps.slice(index + 2));
    }
}
