#!/usr/bin/env bash
# Teams panel (idempotent): scripts, SUPER+ALT+T keybind + click-away, bar button after the mail button. Teams for Linux itself: ./install.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"; KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"; BAR="$Q/modules/ii/bar/BarContent.qml"
BACKUP="$HOME/backups/teams-panel/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$KEYBINDS" "$BAR" "$Q/services/TrayService.qml" "$BACKUP/"
for f in teams-panel.sh teams-panel-hide.sh teams-panel-clickaway.sh; do install -Dm755 "$REPO/$f" "$HOME/.config/hypr/custom/$f"; done
install -Dm644 "$REPO/TeamsButton.qml" "$Q/modules/ii/bar/TeamsButton.qml"
# The Teams icon is on the left bar now: hide Teams from the right-hand tray (TeamsButton still reads SystemTray directly for its menu).
python3 - "$Q/services/TrayService.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
if "includes(\"teams\")" not in s:
    s = s.replace("SystemTray.items.values.filter(i => (", "SystemTray.items.values.filter(i => (!`${i.id} ${i.title}`.toLowerCase().includes(\"teams\") && ")
    open(p, "w").write(s)
PY
python3 - "$BAR" "$KEYBINDS" "$REPO/teams-panel-keybinds.lua" <<'PY'
import re, sys
bar, kb, snippet = sys.argv[1], sys.argv[2], open(sys.argv[3]).read().rstrip("\n")
s = open(bar).read()
if "TeamsButton {" not in s:
    m = re.search(r"( *)(?:MailButton|VscodeGitButton) \{.*?\n\1\}\n(?!(?:\n? *MailButton))", s, re.S)
    ms = list(re.finditer(r"( *)(?:MailButton|VscodeGitButton) \{.*?\n\1\}\n", s, re.S))
    m = ms[-1]; ind = m.group(1)
    block = (f"\n{ind}TeamsButton {{ // Teams panel button\n{ind}    Layout.alignment: Qt.AlignVCenter\n{ind}    Layout.leftMargin: 2\n"
             f"{ind}    colBackground: barLeftSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)\n{ind}}}\n")
    s = s[:m.end()] + block + s[m.end():]
    open(bar, "w").write(s)
t = open(kb).read()
pat = r"-- >>> teams-panel >>>.*?-- <<< teams-panel <<<"
t = re.sub(pat, lambda _: snippet, t, flags=re.S) if re.search(pat, t, re.S) else t.rstrip("\n") + "\n\n" + snippet + "\n"
open(kb, "w").write(t)
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
