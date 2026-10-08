#!/usr/bin/env bash
# Toggles the Git panel: a dedicated VS Code instance (own profile, Source Control + diff only) on the "vgit" special
# workspace, same geometry/animation as the AI sidebar. Window is matched by its dev-host title prefix.
D="$HOME/.local/share/vscode-git"
date +%s%3N > "${XDG_RUNTIME_DIR:-/tmp}/vscode-git-toggled"  # lets click-away ignore the click that caused this toggle
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/vscode-git.lock"; flock 9
nohup "$HOME/.config/hypr/custom/vscode-git-watch.sh" >/dev/null 2>&1 9>&- &
# One panel at a time: hide the AI panel if it is shown
hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:ai")' >/dev/null \
    && hyprctl dispatch 'hl.dsp.workspace.toggle_special("ai")' >/dev/null
if hyprctl clients -j | jq -e '.[] | select(.title|test("⎇"))' >/dev/null; then
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("vgit")' >/dev/null
else
    # Keep the Source Control Graph (commit log) view hidden: it is a saved view state, applied while VS Code is not running.
    python3 - "$D/User/globalStorage/state.vscdb" <<'PY' 2>/dev/null
import json, sqlite3, sys
db = sqlite3.connect(sys.argv[1]); k = "workbench.scm.views.state.hidden"
row = db.execute("select value from ItemTable where key=?", (k,)).fetchone()
views = json.loads(row[0]) if row else []
for v in views:
    if v["id"] == "workbench.scm.history": v["isHidden"] = True; break
else: views.append({"id": "workbench.scm.history", "isHidden": True})
db.execute("insert or replace into ItemTable(key, value) values(?, ?)", (k, json.dumps(views))); db.commit()
PY
    # Start from a known layout (editor area visible, bottom panel hidden): the extension hides the editor area itself.
    for db in "$D"/User/workspaceStorage/*/state.vscdb; do
        sqlite3 "$db" "update ItemTable set value='false' where key='workbench.editor.hidden'; update ItemTable set value='true' where key='workbench.panel.hidden'" 2>/dev/null
    done
    nohup code --user-data-dir "$D" --extensions-dir "$D/extensions" \
        --new-window "$D/ws/git-panel.code-workspace" >/dev/null 2>&1 9>&- &
    for _ in $(seq 60); do  # wait for the window, park it on the special workspace, then show it
        sleep 0.5
        a=$(hyprctl clients -j | jq -r '.[] | select(.title|test("⎇")) | .address' | head -1)
        [ -n "$a" ] && break
    done
    [ -n "$a" ] || exit 0
    read -r mw mh mx my < <(hyprctl monitors -j | jq -r '.[]|select(.focused)|"\(.width) \(.height) \(.x) \(.y)"')
    w="address:$a"
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:vgit\", window = \"$w\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.float({ action = \"enable\", window = \"$w\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.resize({ x = 392, y = $((mh - 83)), relative = false, window = \"$w\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.move({ x = $((mx + 6)), y = $((my + 46)), relative = false, window = \"$w\" })" >/dev/null
    sleep 0.5
    # The title rule may already have revealed the panel: only toggle if it is not shown yet (else it would hide again)
    hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:vgit")' >/dev/null \
        || hyprctl dispatch 'hl.dsp.workspace.toggle_special("vgit")' >/dev/null
    # Once the helper extension has closed restored editors, hide the (empty) editor area: the keybinding only acts when it is visible and no editor is open
    sleep 5
    hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"CTRL ALT SHIFT\", key = \"h\", window = \"$w\" })" >/dev/null
fi
