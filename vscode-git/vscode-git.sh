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
    nohup code --user-data-dir "$D" --extensions-dir "$D/extensions" \
        --new-window "$D/ws/git-panel.code-workspace" >/dev/null 2>&1 9>&- &
    for _ in $(seq 60); do  # wait for the window, park it on the special workspace, then show it
        sleep 0.5
        a=$(hyprctl clients -j | jq -r '.[] | select(.title|test("⎇")) | .address' | head -1)
        [ -n "$a" ] && break
    done
    [ -n "$a" ] || exit 0
    read -r mw mh < <(hyprctl monitors -j | jq -r '.[]|select(.focused)|"\(.width) \(.height)"')
    w="address:$a"
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:vgit\", window = \"$w\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.float({ action = \"enable\", window = \"$w\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.resize({ x = $((mw * 4 / 10)), y = $((mh - 80)), relative = false, window = \"$w\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.move({ x = 12, y = 60, relative = false, window = \"$w\" })" >/dev/null
    sleep 0.5
    # The title rule may already have revealed the panel: only toggle if it is not shown yet (else it would hide again)
    hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:vgit")' >/dev/null \
        || hyprctl dispatch 'hl.dsp.workspace.toggle_special("vgit")' >/dev/null
fi
