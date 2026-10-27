# Panel widgets: shared code

Every left panel (a bar button that opens something on the left) uses the shared code in this folder. **A new panel
widget must not implement any of the behavior below itself.** Use these files, and add a generic option here if
something is missing, so all panels keep behaving the same.

There are two kinds of panels:

| Kind | Examples | Shared code |
|---|---|---|
| **Shell panel**: drawn by Quickshell (a layer) | Task manager, File search, Docker, Gist, Google search, Mail | `WidgetBase.qml` |
| **Window panel**: a real app window on a Hyprland special workspace | AI (Claude/Codex), Console, Teams, Git | `side-panel.sh` |

## The rules (same for every panel)

1. **One panel per monitor.** Opening a panel closes the one already shown on that monitor, of either kind.
2. **A panel stays on the monitor it was opened on** (the monitor of the bar that was clicked, or the focused monitor for a keybind). It never follows the mouse or the focus.
3. **On its own monitor**, these close it: a click outside it, focus moving to another window, a workspace switch, a special workspace (e.g. the AI panel), the launcher/overview, another panel opening.
4. **On another monitor**, nothing closes or moves it.
5. **Esc closes** a shell panel (first closing whatever is open inside it: a menu, a thread, a sub-view). Window panels keep Esc for the app.
6. **Nothing runs while closed**: shell panel content is created on open and destroyed on close; data that must survive lives on the button.
7. **Right-click menu**: the widget gives only the entries; placement and closing are shared.
8. The window **close-button overlay** (`shell-extras/CloseButton.qml`) opening never closes a panel.

## Shell panels: `WidgetBase.qml`

A widget is one file, `<Name>Button.qml`, whose root is `WidgetBase` (installed to `modules/ii/bar/`). Extra files only
when really needed (e.g. `MailRow.qml`, `MailDetail.qml`, `MailMenu.qml`, `MailBody.js`).

```qml
WidgetBase {
    id: root
    iconName: "memory"                  // Material Symbol on the 30×30 bar button
    // data that must survive closing lives here, on the button
    panelContent: Component { FocusScope {
        id: tm
        // panel state, processes, timers: created on open, destroyed on close
        StyledTextInput { focus: true }  // gets the keyboard when the panel opens
    } }
    menuContent: Component { RippleButton { /* entries only */ onClicked: root.closeMenu() } }
}
```

### Properties

| Property | Default | Use |
|---|---|---|
| `iconName` | `""` | Material Symbol name. Leave empty to draw your own icon as a child of the button (Gist draws the GitHub mark). |
| `iconSize` | `21` | Icon size. |
| `iconOpacity` | `1` | Dim the icon, e.g. `available ? 1 : 0.4` when the backend is down. |
| `open` | `false` | The panel is shown. Set it to open/close from code; react with `onOpenChanged` (e.g. refresh on open). |
| `clickOpens` | `true` | `false`: left click does not toggle the panel; handle `onClicked` yourself (Mail opens its app when the daemon is down). |
| `panelContent` | `null` | Component with the panel content. Its root should be a `FocusScope`; give the field that should get the keys `focus: true`. |
| `panelWidth` | `440` | Card width. Resizable panels bind it: `Binding { target: root; property: "panelWidth"; value: fs.cardW }`. |
| `panelKeyboardFocus` | `OnDemand` | Layer keyboard focus. Bind it if it must change (Google: `Exclusive` while the first search loads). |
| `panelCard` | `true` | `true`: the base draws the standard card (full height, gaps, shadow) and the content fills it. `false`: custom layout, see below. |
| `ignoredLayers` | `[]` | Extra layer namespaces whose opening must not close this panel. Rarely needed. |
| `menuContent` | `null` | Component with the right-click menu entries. Unset: right click does nothing. |
| `menuOpen` | (read-only) | The menu is shown (e.g. to keep a bar slot revealed). |
| `panelScreen` | (read-only) | The bar's screen: where the panel opens. |

### Functions

| Function | Use |
|---|---|
| `close()` | Close the panel (e.g. after an action that opens another app). |
| `closeMenu()` | Close the right-click menu (call it from each menu entry). |

### Custom layout (`panelCard: false`)

For panels that are not one full-height card. The content fills the panel window (below the bar) and draws its own
card(s); place them at `Appearance.sizes.hyprlandGapsOut` from the left and top like every panel. The content may define:

| Content property | Use |
|---|---|
| `panelMaskItems: list<Item>` | The items that take clicks (everything else is click-through). Mail: `detailOpen ? [panel, detail] : [panel]`. Google: `[card, dropdown, grip]`. |
| `panelClickThrough: rect` | Screen-coordinate rect where clicks reach the windows below instead of closing the panel (Google: the browser window next to the card). |
| `panelHidden: bool` | Hide the panel window for a while without closing (Google: a video is fullscreen). |

### Keys

The content's `focus: true` item gets the keyboard on open. Esc that is not accepted by the content closes the panel.
To close something inside first, accept Esc only then:

```qml
Keys.onEscapePressed: event => { if (dk.selected !== "") dk.selected = ""; else event.accepted = false }
```

### Right-click menu

`menuContent` holds only the entries (a single `RippleButton`, or a `ColumnLayout` of them, or a separate file like
`dankmail/MailMenu.qml`). WidgetBase places the menu under the button (above it for a bottom bar), closes it on an
outside click, and closes the panel when the menu opens with the panel open (the menu then appears once the panel is gone).

### Converting an old popup

`migrate.py POPUP.qml ID` turns an old `<X>Popup.qml` (Scope + click-away layer + window + card) into the content of a
`panelContent` block (prints it). Then: make the button root `WidgetBase`, drop its own size/icon/`onClicked`/`Loader`,
point `<X>Popup` references at the content id, and update the folder's `install.sh` (below).

## Window panels: `side-panel.sh`

A window panel is an app window on the special workspace `special:<name>`, docked by window rules (float, size, `move`
to the left, `slide left` animation, `workspace = "special:<name>"`). Its own script only starts and docks the app;
everything else is shared. Register a new panel in `side-panel.sh`: add the name to `PANELS` and a window match to
`match()`.

```bash
P="$HOME/.config/hypr/custom/side-panel.sh"
"$P" stamp myname                              # first thing in a toggle: its own click must not close it again
nohup "$P" watch >/dev/null 2>&1 &             # make sure the shared watcher runs (single instance)
if [ "$("$P" mon myname)" = "$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')" ]; then
    "$P" hide myname force                     # shown on this monitor: hide
else
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("myname")'   # hidden or on another monitor: show here
fi
```

| Command | Use |
|---|---|
| `stamp NAME` | Record a toggle now (click-away and the watcher ignore its own click/focus for a moment). |
| `launching NAME` | The app is starting and its window may take seconds: treat as toggled for 60 s (then `stamp` again before showing). |
| `recent NAME MS` | Exit 0 if NAME was toggled within MS ms. |
| `hidden-recently NAME MS` | Exit 0 if click-away hid NAME within MS ms (a toggle right after must not reopen it). |
| `mon NAME` | Print the monitor NAME is shown on (empty if hidden). |
| `hide NAME [force]` | Hide NAME **on its own monitor**. Never hide with a plain `toggle_special`: Hyprland toggles on the focused monitor, which moves the panel there instead. |
| `hide-on MONITOR` | Hide whichever panel is shown on MONITOR. |
| `clickaway` | The one shared left-click handler (bound in `side-panel-keybinds.lua`; do not add another). |
| `watch` | The one shared event watcher: focus change, overview, shell panel opening, a panel shown without a toggle, stray windows landing on a panel workspace. |

Keep a `<name>-hide.sh` wrapper only if other code calls it (e.g. SUPER+Q in `vscode-git/vscode-git-close.sh`):
`exec "$HOME/.config/hypr/custom/side-panel.sh" hide <name> "$@"`.

## Installing

Every panel widget's `install.sh` runs the shared installer first, installs its own file(s) and removes files it replaced:

```bash
"$REPO/../widget-base/install.sh"   # shared panel behavior (WidgetBase.qml, side-panel.sh + keybinds)
install -Dm644 "$REPO/MyButton.qml" "$Q/modules/ii/bar/MyButton.qml"
```

`widget-base/install.sh` installs `WidgetBase.qml`, `side-panel.sh` and the `side-panel` keybind block (one click-away bind,
watcher started at login), backs up what it replaces, and removes the old per-panel click-away/watch scripts.

## Checklist for a new panel widget

- [ ] Root is `WidgetBase` (shell panel) or the script uses `side-panel.sh` (window panel). No own click-away layer, `PanelWindow`, `HyprlandFocusGrab`, `onRawEvent` close logic, monitor tracking, Esc-to-close, button size/icon/toggle code, or menu window.
- [ ] One main file; extra files only when really needed.
- [ ] Panel content holds its state and processes (nothing runs while closed); data that must survive is on the button.
- [ ] Right-click menu: entries only, via `menuContent`, each entry calls `root.closeMenu()`.
- [ ] `install.sh` runs `widget-base/install.sh` first.
- [ ] Something generic is missing? Add an option to `WidgetBase.qml` / `side-panel.sh`, document it here, and use it.
- [ ] Tested on two monitors: opens on the clicked bar's monitor; a click/workspace change there closes it; activity on the other monitor does not; opening another panel closes it; Esc closes it.
