#!/bin/sh
# Installs earlyoom + config, disables systemd-oomd (avoid two killers). Swapfile: setup-swapfile.sh (run via pkexec).
set -e
here=$(cd "$(dirname "$0")" && pwd)
b=~/backups/swap-oom/$(date +%Y%m%d-%H%M%S); mkdir -p "$b"
[ -f /etc/default/earlyoom ] && cp /etc/default/earlyoom "$b/"
pkexec sh -c "pacman -S --needed --noconfirm earlyoom && install -m644 '$here/earlyoom' /etc/default/earlyoom && systemctl disable --now systemd-oomd && systemctl enable --now earlyoom && systemctl restart earlyoom"
