#!/usr/bin/env bash
# Gist widget: bar button + popup for your GitHub gists (list/filter, view, create, edit, delete, secret gist from clipboard),
# synced in the background into a local cache by gist-widget.sh through `gh api` (idempotent). Needs: github-cli (logged in, `gist` scope), jq, wl-clipboard.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"; BAR="$Q/modules/ii/bar/BarContent.qml"; SCRIPT="$HOME/.config/hypr/custom/gist-widget.sh"
for c in gh jq wl-paste; do command -v "$c" >/dev/null || { echo "needs $c (pkexec pacman -S github-cli jq wl-clipboard)" >&2; exit 1; }; done
gh auth status 2>&1 | grep -q "'gist'" || echo "warning: the gh token has no 'gist' scope; run: gh auth refresh -s gist" >&2
BACKUP="$HOME/backups/gist-widget/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$BAR" "$BACKUP/"
[ -f "$SCRIPT" ] && cp "$SCRIPT" "$BACKUP/"
for f in GistButton.qml GistPopup.qml; do
  [ -f "$Q/modules/ii/bar/$f" ] && cp "$Q/modules/ii/bar/$f" "$BACKUP/"
  install -Dm644 "$REPO/$f" "$Q/modules/ii/bar/$f"
done
install -Dm755 "$REPO/gist-widget.sh" "$SCRIPT"
install -Dm644 "$REPO/icons/github-symbolic.svg" "$Q/assets/icons/github-symbolic.svg"
python3 - "$BAR" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
if "GistButton {" in s: sys.exit(0)
col = "colBackground: barLeftSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)"
if "RevealSlot" in s:
    # zbar-reveal already applied: add a slot after the Google one, in the next grid column
    m = None
    for m2 in re.finditer(r"^( *)RevealSlot \{\n.*?^\1\}\n", s, re.S | re.M):
        if "GoogleSearchButton {" in m2.group(0): m = m2
    if not m: sys.exit("GoogleSearchButton slot not found")
    i = m.group(1)
    block = (f"\n{i}RevealSlot {{\n{i}    Layout.row: 0\n{i}    Layout.column: 9\n{i}    open: iconRow.hot\n"
             f"{i}    pinned: gistBtn.pinned\n"
             f"{i}    GistButton {{ // GitHub gists button\n{i}        id: gistBtn\n{i}        Layout.alignment: Qt.AlignVCenter\n"
             f"{i}        Layout.leftMargin: 2\n{i}        {col}\n{i}    }}\n{i}}}\n")
else:
    m = re.search(r"( *)GoogleSearchButton \{.*?\n\1\}\n", s, re.S)
    if not m: sys.exit("GoogleSearchButton not found")
    i = m.group(1)
    block = (f"\n{i}GistButton {{ // GitHub gists button\n{i}    Layout.alignment: Qt.AlignVCenter\n"
             f"{i}    Layout.leftMargin: 2\n{i}    {col}\n{i}}}\n")
s = s[:m.end()] + block + s[m.end():]
open(p, "w").write(s)
PY
# upgrade an older slot (pinned only while open) so an unsaved draft also keeps the icon shown
sed -i 's/pinned: gistBtn\.open || gistBtn\.menuOpen$/pinned: gistBtn.pinned/' "$BAR"
install -d -m700 "$HOME/.local/state/gist-widget"   # local draft autosave
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
