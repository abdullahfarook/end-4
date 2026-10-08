#!/usr/bin/env bash
# Builds dankmail (AUR source tarball) with daemon-patch/lazy-month-sync.patch and installs /usr/bin/dmail (needs pkexec).
# Patch: initial sync only covers the last 7 days; threads.fetchOlder pulls one older month per call.
# A `yay -Syu` of dankmail restores the stock binary; just re-run this script.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
TAR="$(ls ~/.cache/yay/dankmail/dankmail-*.tar.gz | sort -V | tail -1)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
tar xzf "$TAR" -C "$W"; cd "$W"/dankmail-*
patch -p1 -s < "$REPO/daemon-patch/lazy-month-sync.patch"
make -C core build VERSION="$(basename "$PWD" | sed 's/dankmail-/v/')-lazy" COMMIT=local >/dev/null
B="$HOME/backups/dankmail/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$B"; cp /usr/bin/dmail "$B/dmail.orig"
pkexec install -Dm755 "$PWD/core/bin/dmail" /usr/bin/dmail
systemctl --user restart dmail
echo "Installed patched dmail (backup: $B/dmail.orig)"
