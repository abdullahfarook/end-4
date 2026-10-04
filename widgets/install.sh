#!/usr/bin/env bash
# Reapplies the "frequent apps" launcher changes to the illogical-impulse Quickshell config.
#
# Usage: ./install.sh           apply frequent-apps.patch (keeps upstream changes in those files)
#        ./install.sh --force   if the patch fails, overwrite with the saved copies in files/
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.config/quickshell/ii"
PATCH="$REPO/frequent-apps.patch"
FILES=(
    services/AppSearch.qml
    services/LauncherSearch.qml
    modules/ii/overview/SearchWidget.qml
    modules/common/Directories.qml
)

[ -d "$TARGET" ] || { echo "Config not found: $TARGET" >&2; exit 1; }

# Back up the current files before touching anything
BACKUP="$HOME/backups/widgets/$(date +%Y%m%d-%H%M%S)"
for f in "${FILES[@]}"; do
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$TARGET/$f" "$BACKUP/$f"
done
echo "Backed up current files to $BACKUP"

if patch -d "$TARGET" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
    echo "Changes are already applied, nothing to do."
elif patch -d "$TARGET" -p1 --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
    patch -d "$TARGET" -p1 -s -f --no-backup-if-mismatch < "$PATCH"
    echo "Patch applied."
elif [ "${1:-}" = "--force" ]; then
    for f in "${FILES[@]}"; do
        cp "$REPO/files/$f" "$TARGET/$f"
    done
    echo "Patch didn't apply cleanly; overwrote with saved copies (upstream changes in these files are lost)."
else
    echo "Patch doesn't apply cleanly (upstream changed these files)." >&2
    echo "Run with --force to overwrite with the saved copies instead." >&2
    exit 1
fi

echo "Quickshell reloads automatically; if not, restart it with: qs -c ii"
