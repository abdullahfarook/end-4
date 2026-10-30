pragma Singleton

import QtQuick
import Quickshell

// All WidgetBase panels. Opening one closes the others on its screen at once (not only when its layer shows up, which
// left both panels on screen and made the old one fade in place instead of sliding out before the new one slides in).
Singleton {
    readonly property int defaultWidth: 440   // the one panel width, same as the AI window panel (ai-sidebar window rule: keep in sync)
    property var panels: []
    function register(p) { panels = panels.concat([p]) }
    function unregister(p) { panels = panels.filter(x => x !== p) }
    function closeOthers(p) {
        for (const o of panels) if (o !== p && o.open && o.panelScreen === p.panelScreen) o.open = false
    }
}
