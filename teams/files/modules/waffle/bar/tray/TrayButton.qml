pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.bar

BarIconButton {
    id: root

    required property SystemTrayItem item
    property alias menuOpen: menu.visible
    readonly property bool barAtBottom: Config.options.waffles.bar.bottom
    iconSource: item.icon
    iconScale: 0
    Component.onCompleted: {
        root.iconScale = 1
    }
    Behavior on iconScale {
        animation: Looks.transition.enter.createObject(this)
    }

    onClicked: {
        if (`${item.id} ${item.title}`.toLowerCase().includes("teams"))
            // teams-for-linux tray click fails to re-show a hidden window; a 2nd instance shows/focuses it
            Quickshell.execDetached(["/opt/teams-for-linux/teams-for-linux", "--ozone-platform=x11"]);
        else
            item.activate();
    }

    altAction: () => {
        if (item.hasMenu) menu.open()
    }

    // This is lazy, but it's not like tray menus on Windoes are consistent...
    // TODO: Figure out how to do cascading menus then use a custom menu
    QsMenuAnchor {
        id: menu
        menu: root.item.menu
        anchor {
            adjustment: PopupAdjustment.ResizeY | PopupAdjustment.SlideX
            item: root
            gravity: root.barAtBottom ? Edges.Top : Edges.Bottom
            edges: root.barAtBottom ? Edges.Top : Edges.Bottom
        }
    }

    BarToolTip {
        extraVisibleCondition: root.shouldShowTooltip && !root.Drag.active
        text: TrayService.getTooltipForItem(root.item)
    }
}
