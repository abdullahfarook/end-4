#!/usr/bin/env bash
# Stops the git panel's dedicated VS Code instance (and its watcher); the next toggle starts a fresh one.
D="$HOME/.local/share/vscode-git"
pkill -f vscode-git-watch.sh
for pid in $(hyprctl clients -j | jq -r '.[]|select(.title|test("⎇"))|.pid'); do kill "$pid"; done
pkill -f -- "$D"   # leftover helper processes (extension hosts, codex, ...)
exit 0
