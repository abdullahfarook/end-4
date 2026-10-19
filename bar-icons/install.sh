#!/usr/bin/env bash
# Consistent bar icon buttons: the upstream sidebar button gets the same fixed 30x30 box / 20px icon as the custom buttons (idempotent).
set -euo pipefail
Q="$HOME/.config/quickshell/ii/modules/ii/bar"; F="$Q/LeftSidebarButton.qml"
BACKUP="$HOME/backups/bar-icons/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP"; cp "$F" "$Q/BarContent.qml" "$BACKUP/"
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("implicitWidth: distroIcon.width + buttonPadding * 2", "implicitWidth: 30")
s = s.replace("implicitHeight: distroIcon.height + buttonPadding * 2", "implicitHeight: 30")
s = s.replace("        width: 19.5\n        height: 19.5\n", "        width: 20\n        height: 20\n")
s = s.replace("source: Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`",
    "source: ({ claude: 'claude-symbolic', codex: 'openai-symbolic', antigravity: 'google-gemini-symbolic' })[Config.options.ai.sidebarBackend] ?? (Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`)")
open(p, "w").write(s)
PY
python3 - "$Q/BarContent.qml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = "                Layout.leftMargin: Appearance.rounding.screenRounding\n"
if "screenRounding\n                Layout.rightMargin" not in s:
    s = s.replace(a, a + "                Layout.rightMargin: -4\n", 1)
    open(p, "w").write(s)
PY
install -Dm644 "$(dirname "$0")/icons/claude-symbolic.svg" "$HOME/.config/quickshell/ii/assets/icons/claude-symbolic.svg"
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
