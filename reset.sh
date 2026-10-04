#!/usr/bin/env bash
# Removes every customization from the live config (back to stock illogical-impulse). The repo is not touched.
# Backs up everything it modifies to ~/backups/reset/<timestamp>/. Re-apply anything with the folder's install.sh.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"
H="$HOME/.config/hypr/custom"
CFG="$HOME/.config/illogical-impulse/config.json"
KB="$H/keybinds.lua"
BACKUP="$HOME/backups/reset/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP/qml" "$BACKUP/hypr"

# Backups
[ -f "$KB" ] && cp "$KB" "$BACKUP/hypr/"
cp "$H"/super-tab*.sh "$H"/ai-sidebar.sh "$H"/ai-sidebar-watch.sh "$BACKUP/hypr/" 2>/dev/null || true
[ -f "$CFG" ] && cp "$CFG" "$BACKUP/"
cp -r "$Q" "$BACKUP/qml/" 2>/dev/null || true
echo "Backed up to $BACKUP"

# 1. Keybind blocks
if [ -f "$KB" ]; then
python3 - "$KB" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
for n in ("super-tab-workspaces", "alt-tab-workspaces", "ai-sidebar"):
    s = re.sub(r"\n*-- >>> %s >>>.*?-- <<< %s <<<\n*" % (n, n), "\n", s, flags=re.S)
open(p, "w").write(s.rstrip("\n") + "\n")
PY
fi
# 2. Installed scripts
pkill -f ai-sidebar-watch.sh 2>/dev/null || true
rm -f "$H"/super-tab.sh "$H"/super-tab-release.sh "$H"/ai-sidebar.sh "$H"/ai-sidebar-watch.sh
# 3. QML patches (reverse only if currently applied)
for p in "$REPO/ai-sidebar/ai-sidebar.patch" "$REPO/widgets/frequent-apps.patch"; do
    [ -f "$p" ] || continue
    if patch -d "$Q" -p1 -R --dry-run -s -f < "$p" >/dev/null 2>&1; then
        patch -d "$Q" -p1 -R -s -f --no-backup-if-mismatch < "$p"; echo "Reverted $(basename "$p")"
    fi
done
# 4. Dolphin entries
rm -f "$HOME/.local/share/kio/servicemenus/open-with-dev-tools.desktop"
# 5. Setting
if [ -f "$CFG" ] && jq -e '.ai.sidebarBackend' "$CFG" >/dev/null 2>&1; then
    jq 'del(.ai.sidebarBackend)' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
fi
echo "Reset done. Hyprland reloads itself; restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
