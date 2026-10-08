#!/usr/bin/env bash
# dankmail widget (idempotent): bar mail button with unread badge after the Git button, SUPER+ALT+M toggle.
# The app itself: `yay -S dankmail && systemctl --user enable --now dmail`; add accounts with `dmail account add-microsoft --client-id <azure-app-id>`.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"; KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"; BAR="$Q/modules/ii/bar/BarContent.qml"
BACKUP="$HOME/backups/dankmail/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$KEYBINDS" "$BAR" "$BACKUP/"
for f in MailButton MailPopup MailRow MailMenu; do install -Dm644 "$REPO/$f.qml" "$Q/modules/ii/bar/$f.qml"; done
python3 - "$BAR" "$KEYBINDS" "$REPO/dankmail-keybinds.lua" <<'PY'
import re, sys
bar, kb, snippet = sys.argv[1], sys.argv[2], open(sys.argv[3]).read().rstrip("\n")
s = open(bar).read()
if "MailButton {" not in s:
    m = re.search(r"( *)VscodeGitButton \{.*?\n\1\}\n", s, re.S)
    ind = m.group(1)
    block = (f"\n{ind}MailButton {{ // dankmail button\n{ind}    Layout.alignment: Qt.AlignVCenter\n{ind}    Layout.leftMargin: 2\n"
             f"{ind}    colBackground: barLeftSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)\n{ind}}}\n")
    s = s[:m.end()] + block + s[m.end():]
    open(bar, "w").write(s)
t = open(kb).read()
pat = r"-- >>> dankmail >>>.*?-- <<< dankmail <<<"
t = re.sub(pat, lambda _: snippet, t, flags=re.S) if re.search(pat, t, re.S) else t.rstrip("\n") + "\n\n" + snippet + "\n"
open(kb, "w").write(t)
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
