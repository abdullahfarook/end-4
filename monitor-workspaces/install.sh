#!/usr/bin/env bash
# Per-monitor workspace groups (idempotent): appends monitor-workspaces.lua to custom/rules.lua.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.config/hypr/custom/rules.lua"
BACKUP="$HOME/backups/monitor-workspaces/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"; cp "$TARGET" "$BACKUP/"
python3 - "$TARGET" "$REPO/monitor-workspaces.lua" <<'PY'
import re, sys
target, snippet = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
s = open(target).read()
pat = r"-- >>> monitor-workspaces >>>.*?-- <<< monitor-workspaces <<<"
s = re.sub(pat, lambda _: snippet, s, flags=re.S) if re.search(pat, s, re.S) else s.rstrip("\n") + "\n\n" + snippet + "\n"
open(target, "w").write(s)
PY
# Shell: undo the earlier "total split across monitors" patches; "shown" is the count per monitor (stock behaviour).
QS="$HOME/.config/quickshell/ii"
for f in modules/common/models/WorkspaceModel.qml modules/ii/background/Background.qml modules/settings/BarConfig.qml; do cp "$QS/$f" "$BACKUP/$(basename "$f")"; done
python3 - "$QS" <<'PY'
import re, sys
qs = sys.argv[1]
def sub(f, pattern, new):
    p = qs + "/" + f; s = open(p).read(); open(p, "w").write(re.sub(pattern, lambda _: new, s, flags=re.M))
sub("modules/common/models/WorkspaceModel.qml", r"^\s*readonly property int shownCount:.*$", "    readonly property int shownCount: C.Config.options.bar.workspaces.shown")
sub("modules/common/models/WorkspaceModel.qml", r"\Aimport Quickshell\n", "")
sub("modules/ii/background/Background.qml", r"^\s*property int workspaceChunkSize:.*$", "        property int workspaceChunkSize: Config?.options.bar.workspaces.shown ?? 10")
sub("modules/settings/BarConfig.qml", r'Translation\.tr\("Workspaces shown[^"]*"\)', 'Translation.tr("Workspaces shown (per monitor)")')
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
