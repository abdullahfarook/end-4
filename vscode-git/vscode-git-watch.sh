#!/usr/bin/env bash
# Hides the git panel when the launcher/overview opens. Started by vscode-git.sh; single instance.
exec 9>"$XDG_RUNTIME_DIR/vscode-git-watch.lock"; flock -n 9 || exit 0
sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -u "UNIX-CONNECT:$sock" - | while IFS= read -r line; do
    case "$line" in openlayer\>\>quickshell:overview) "$HOME/.config/hypr/custom/vscode-git-hide.sh" ;; esac
done
