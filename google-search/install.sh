#!/usr/bin/env bash
# Google widget: bar button + popup with a search field and an embedded QtWebEngine browser (gsearch.qml via gsearch.sh) below it (idempotent).
# Needs: qt6-webengine, qt6-declarative (qml6). No Python.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
Q="$HOME/.config/quickshell/ii"; BAR="$Q/modules/ii/bar/BarContent.qml"; KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
BACKUP="$HOME/backups/google-search/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$BAR" "$KEYBINDS" "$BACKUP/"
command -v qml6 >/dev/null && pacman -Q qt6-webengine >/dev/null 2>&1 || { echo "needs qt6-declarative + qt6-webengine: pkexec pacman -S qt6-declarative qt6-webengine" >&2; exit 1; }
"$REPO/../widget-base/install.sh"   # shared panel behavior (WidgetBase.qml)
for f in GoogleSearchButton.qml GoogleSearchPopup.qml; do
  [ -f "$Q/modules/ii/bar/$f" ] && cp "$Q/modules/ii/bar/$f" "$BACKUP/"
done
install -Dm644 "$REPO/GoogleSearchButton.qml" "$Q/modules/ii/bar/GoogleSearchButton.qml"
rm -f "$Q/modules/ii/bar/GoogleSearchPopup.qml"   # merged into GoogleSearchButton.qml
install -Dm755 "$REPO/gsearch.sh" "$HOME/.config/hypr/custom/gsearch.sh"
install -Dm644 "$REPO/gsearch.qml" "$HOME/.config/hypr/custom/gsearch.qml"
rm -f "$HOME/.config/hypr/custom/gsearch.py"
# keep the old PySide6 profile (cookies, solved captcha) once
OLD="$HOME/.local/share/gsearch.py/QtWebEngine/gsearch"; NEW="$HOME/.local/share/gsearch"
[ -d "$OLD" ] && [ ! -e "$NEW/.migrated-from-pyside" ] && { [ -d "$NEW" ] && mv "$NEW" "$HOME/backups/gsearch-profile-$(date +%Y%m%d-%H%M%S)"; cp -r "$OLD" "$NEW"; touch "$NEW/.migrated-from-pyside"; } || true
install -Dm755 "$REPO/gsearch-resize.sh" "$HOME/.config/hypr/custom/gsearch-resize.sh"
install -Dm644 "$REPO/gsearch-pip.qml" "$HOME/.config/hypr/custom/gsearch-pip.qml"
install -Dm755 "$REPO/gsearch-popout.sh" "$HOME/.config/hypr/custom/gsearch-popout.sh"
install -Dm755 "$REPO/gsearch-open.sh" "$HOME/.config/hypr/custom/gsearch-open.sh"
install -Dm755 "$REPO/gsearch-close.sh" "$HOME/.config/hypr/custom/gsearch-close.sh"
rm -f "$HOME/.config/hypr/custom/gsearch-close-delay"   # old close-timing knob: the panel now slides a still of the browser out itself
python3 - "$BAR" "$KEYBINDS" "$REPO/google-search-rules.lua" <<'PY'
import re, sys
bar, kb, rules = sys.argv[1:4]
s = open(bar).read()
if "GoogleSearchButton {" not in s:
    m = re.search(r"( *)FileSearchButton \{.*?\n\1\}\n", s, re.S)
    ind = m.group(1)
    block = (f"\n{ind}GoogleSearchButton {{ // Google (embedded browser) button\n{ind}    Layout.alignment: Qt.AlignVCenter\n"
             f"{ind}    Layout.leftMargin: 2\n"
             f"{ind}    colBackground: barLeftSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)\n{ind}}}\n")
    s = s[:m.end()] + block + s[m.end():]
    open(bar, "w").write(s)
snippet = open(rules).read().rstrip("\n")
t = open(kb).read()
pat = r"-- >>> google-search >>>.*?-- <<< google-search <<<"
t = re.sub(pat, lambda _: snippet, t, flags=re.S) if re.search(pat, t, re.S) else t.rstrip("\n") + "\n\n" + snippet + "\n"
open(kb, "w").write(t)
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
