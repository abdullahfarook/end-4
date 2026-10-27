# Shell extras: one process for every add-on

Every Quickshell add-on that is **not part of the ii shell** and **not a panel widget** lives here, as one component of
the shared `qs -c extras` config. **A new extra must not start its own `qs` process:** each one loads a full Qt/QML
runtime (~175 MB), so every extra shares this one.

| Extra | File | What it does |
|---|---|---|
| Close button | `CloseButton.qml` | Drag / maximize / close drawer at the top of windows whose app has no buttons |
| Type-search | `TypeSearch.qml` | Typing right after switching to an empty workspace opens the launcher search |

## Which home fits

| What you are building | Where it goes |
|---|---|
| Bar button + left panel, or app window on a special workspace | `widget-base/` (see its README) |
| Change to an existing ii module (bar, overview, launcher, …) | that module, patched by an installer |
| Anything else drawn or run by Quickshell: window overlays, keyboard grabs, background watchers, popups not tied to the bar | **here** |

## How it runs

- `shell.qml` is the config root: it holds the pragmas and lists every extra (`CloseButton {}`, `TypeSearch {}`).
- `run.sh` (installed as `~/.config/hypr/custom/extras-run.sh`, started from `execs.lua`) keeps it alive. It is a
  single instance (flock) and restarts the process **2 s after a crash**.
- It is a separate process from ii, so an extra that fails never touches the bar, and installing an extra never
  restarts ii. (Restarting ii kills `kded6`, which crashes Teams.)
- Trade-off: the extras share a process, so a hard crash (segfault) in one restarts all of them. A JavaScript
  exception does not crash anything: QML logs it and the handler stops.

## Adding an extra

1. **Create `<Name>.qml`** with `Scope` as its root (never `ShellRoot`; there is only one, in `shell.qml`):

   ```qml
   import QtQuick
   import Quickshell
   import Quickshell.Wayland
   import Quickshell.Hyprland

   // One-paragraph comment: what it does and when it is active.
   Scope {
       id: root
       // state, Process, Timer, Connections, PanelWindow / Variants ...
       PanelWindow {
           WlrLayershell.namespace: "quickshell:<name>"   // unique, lowercase
           // ...
       }
   }
   ```

2. **List it in `shell.qml`**: add `<Name> {}` inside `ShellRoot`. The installer copies every `*.qml` here, so there
   is no install list to edit.
3. **Keybinds** go in `keybinds.lua`. The installer writes it into the `-- >>> shell-extras >>>` block of
   `~/.config/hypr/custom/keybinds.lua`. A `GlobalShortcut` uses its own `appid` (e.g. `typesearch`), bound as
   `hl.dsp.global("<appid>:<name>")`.
4. **Pragmas** (`//@ pragma ...`) only work in `shell.qml`; add them there, never in a component.
5. **Patches to ii** (e.g. a new IPC function): a small idempotent Python script here (like `patch.py`), called from
   `install.sh`. Never edit upstream ii files by hand. Talk to ii through its IPC
   (`qs -c ii ipc call <target> <function>`), never by reaching into its files at runtime.
6. **Install and check**: `./install.sh` (it backs up to `~/backups/shell-extras/<timestamp>/` and restarts only
   the extras process), then `qs log -c extras` must end with `Configuration Loaded` and no errors.
7. Add a row to the table above and update the `shell-extras/` row in the repo `README.md`.

## Rules for every extra

- **Never break the others.** Guard JSON parsing and other code that can throw (`try`/`catch`), and keep every
  grab or modal state on a timer: a keyboard grab (`WlrKeyboardFocus.Exclusive`) must always end by itself (see
  `TypeSearch.qml`: timeout, Esc, click, another layer opening).
- **Click-through by default**: a `PanelWindow` that covers more than its visible part sets a `mask` so clicks
  outside it reach the windows below. An empty `Region {}` still takes input; use a 1 px region instead.
- **Idle means idle**: no polling while nothing is shown; react to `Hyprland.onRawEvent` and debounce.
- **Unique names**: the layer namespace `quickshell:<name>`, the log prefix `<name>:`, and the shortcut `appid`.
  Other code may filter on them (e.g. `widget-base` ignores `quickshell:closebutton` layers opening).
- **Hyprland dispatch uses the Lua syntax**: `Hyprland.dispatch("hl.dsp.window.close({ window = 'address:…' })")`.
- **Removing an extra**: delete its file and its line in `shell.qml` (and its binds), then run `./install.sh`. The
  live folder mirrors this one.
