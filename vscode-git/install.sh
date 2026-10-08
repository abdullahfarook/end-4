#!/usr/bin/env bash
# Installs the Git panel: dedicated minimal VS Code (own profile in ~/.local/share/vscode-git), bar button, SUPER+Z, scripts, rules.
# Edit the repos shown in the panel in ~/.local/share/vscode-git/ws/git-panel.code-workspace (seeded once from ws.template.json).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"; KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"; D="$HOME/.local/share/vscode-git"
BACKUP="$HOME/backups/vscode-git/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$KEYBINDS" "$Q/modules/ii/bar/BarContent.qml" "$BACKUP/"
[ -e "$D/User/settings.json" ] && cp "$D/User/settings.json" "$BACKUP/vscode-settings.json"
mkdir -p "$D/User" "$D/extensions" "$D/ws" "$D/ext"
cp "$REPO/settings.json" "$D/User/settings.json"; cp "$REPO/keybindings.json" "$D/User/keybindings.json"; cp "$REPO"/ext/* "$D/ext/"
python3 "$REPO/build-vsix.py"
code --user-data-dir "$D" --extensions-dir "$D/extensions" --install-extension "$REPO/gitpanel.vsix" --force >/dev/null 2>&1 || echo "extension install failed"
[ -e "$D/ws/git-panel.code-workspace" ] || cp "$REPO/ws.template.json" "$D/ws/git-panel.code-workspace"
if grep -q "VscodeGitButton {" "$Q/modules/ii/bar/BarContent.qml"; then echo "QML patch already applied."
else patch -d "$Q" -p1 -s -f --no-backup-if-mismatch < "$REPO/vscode-git.patch" && echo "QML patch applied (restart the shell)."; fi
install -Dm644 "$REPO/VscodeGitButton.qml" "$Q/modules/ii/bar/VscodeGitButton.qml"
for f in vscode-git.sh vscode-git-watch.sh vscode-git-clickaway.sh vscode-git-hide.sh vscode-git-close.sh; do install -Dm755 "$REPO/$f" "$HOME/.config/hypr/custom/$f"; done
python3 - "$KEYBINDS" "$REPO/vscode-git-keybinds.lua" <<'PY'
import re, sys
target, snippet = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
s = open(target).read()
pat = r"-- >>> vscode-git >>>.*?-- <<< vscode-git <<<"
s = re.sub(pat, lambda _: snippet, s, flags=re.S) if re.search(pat, s, re.S) else s.rstrip("\n") + "\n\n" + snippet + "\n"
open(target, "w").write(s)
PY
echo "Done."
