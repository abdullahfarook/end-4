#!/usr/bin/env bash
# Builds the custom dankmail daemon from the AUR source tarball + the ordered patches in daemon-patch/ and runs it as the
# user's dmail.service instead of /usr/bin/dmail. No root; the packaged binary is left untouched, so package updates
# don't overwrite it (re-run this script after updating dankmail to rebuild).
#   01-sync-last-7-days.patch  Outlook + Gmail: the initial sync only covers the last 7 days
#   02-lazy-load.patch         Outlook + Gmail: threads.fetchOlder pulls one older month per call (HistoryPage);
#                              messages.getHtml returns a message's original HTML on demand (never stored)
# Needs: go, patch, tar; dankmail installed via yay so its source tarball is in ~/.cache/yay/dankmail (`yay -S dankmail`).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
TAR="$(ls ~/.cache/yay/dankmail/dankmail-*.tar.gz 2>/dev/null | sort -V | tail -1 || true)"
[ -n "$TAR" ] || { echo "no dankmail source tarball in ~/.cache/yay/dankmail (run: yay -S dankmail)" >&2; exit 1; }
for t in go patch tar; do command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; done
BIN="$HOME/.local/bin/dmail-custom"
DROPIN="$HOME/.config/systemd/user/dmail.service.d"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
tar xzf "$TAR" -C "$W"; cd "$W"/dankmail-*
VER="v$(basename "$PWD" | sed 's/dankmail-//')"
for p in "$REPO"/daemon-patch/*.patch; do echo "patch: $(basename "$p")"; patch -p1 -s < "$p"; done
mkdir -p "$(dirname "$BIN")"
(cd core && CGO_ENABLED=0 go build -ldflags "-s -w -X main.Version=$VER-custom -X main.Commit=local" -o "$BIN.new" ./cmd/dmail)
mv "$BIN.new" "$BIN"
mkdir -p "$DROPIN"; rm -f "$DROPIN/30d.conf"
printf '[Service]\nExecStart=\nExecStart=%%h/.local/bin/dmail-custom run --hidden\n' > "$DROPIN/custom.conf"
systemctl --user daemon-reload
systemctl --user restart dmail.service
echo "Installed $BIN ($VER-custom); dmail.service now runs it."
