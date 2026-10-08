#!/bin/sh
# Run as root (pkexec): installs the patch script + pacman hook that re-applies it after VS Code updates.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
install -Dm755 "$here/patch-min-width.sh" /usr/local/share/vscode-git/patch-min-width.sh
install -Dm644 "$here/vscode-min-width.hook" /etc/pacman.d/hooks/vscode-min-width.hook
