#!/usr/bin/env bash
# Builds the custom dankmail daemon (upstream tag + the ordered patches in daemon-patch/) with Go and runs it as the
# user's dmail.service instead of /usr/bin/dmail. No root; the packaged binary is left untouched, so package updates
# don't overwrite it (re-run this script to update the custom build).
#   01-lazy-month-sync.patch     Microsoft: initial sync covers 7 days; threads.fetchOlder pulls one older month per call
#   02-gmail-7d-history-html.patch  Gmail: initial sync limited to newer_than:7d, HistoryPage loads one older month per call (like Microsoft); messages.getHtml returns a message's original HTML on demand
# Needs: git, go, patch; dankmail already installed (dmail.service + the Quickshell UI) and its accounts added.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
VER="${DANKMAIL_VERSION:-v0.3.11}"
SRC="${XDG_CACHE_HOME:-$HOME/.cache}/dankmail-src"
BIN="$HOME/.local/bin/dmail-custom"
DROPIN="$HOME/.config/systemd/user/dmail.service.d"
for t in git go patch; do command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; done
rm -rf "$SRC"; git clone -q --depth 1 --branch "$VER" https://github.com/arqueon/dankmail "$SRC"
cd "$SRC"
for p in "$REPO"/daemon-patch/*.patch; do echo "patch: $(basename "$p")"; patch -p1 -s < "$p"; done
mkdir -p "$(dirname "$BIN")"
(cd core && CGO_ENABLED=0 go build -ldflags "-s -w -X main.Version=$VER-custom -X main.Commit=local" -o "$BIN.new" ./cmd/dmail)
mv "$BIN.new" "$BIN"
mkdir -p "$DROPIN"; rm -f "$DROPIN/30d.conf"
printf '[Service]\nExecStart=\nExecStart=%%h/.local/bin/dmail-custom run --hidden\n' > "$DROPIN/custom.conf"
systemctl --user daemon-reload
systemctl --user restart dmail.service
echo "Installed $BIN ($VER-custom); dmail.service now runs it."
