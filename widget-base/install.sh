#!/usr/bin/env bash
# Shared bar widget base (WidgetBase.qml): side panel, click-away, Esc, per-monitor close rules. Installed by each widget that uses it (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
D="$HOME/.config/quickshell/ii/modules/ii/bar"
BACKUP="$HOME/backups/widget-base/$(date +%Y%m%d-%H%M%S)"
if [ -f "$D/WidgetBase.qml" ] && ! cmp -s "$REPO/WidgetBase.qml" "$D/WidgetBase.qml"; then mkdir -p "$BACKUP"; cp "$D/WidgetBase.qml" "$BACKUP/"; fi
install -Dm644 "$REPO/WidgetBase.qml" "$D/WidgetBase.qml"
