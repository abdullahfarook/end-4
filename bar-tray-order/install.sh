#!/usr/bin/env bash
# Reorders the left bar buttons after Teams: file search, Docker, task manager, Google.
set -e
Q="$HOME/.config/quickshell/ii"; BAR="$Q/modules/ii/bar/BarContent.qml"
B="$HOME/backups/bar-tray-order/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$B"; cp "$BAR" "$B/"
python3 - "$BAR" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
order = ["FileSearchButton", "DockerButton", "TaskManagerButton", "GoogleSearchButton"]
blocks = []
for n in order:
    m = re.search(r"\n *" + n + r" \{.*?\n( *)\}\n", s, re.S)
    if not m: sys.exit(f"{n} not found")
    blocks.append(m.group(0))
    s = s[:m.start()] + s[m.end() - 1:]
t = re.search(r"\n *TeamsButton \{.*?\n( *)\}\n", s, re.S)
s = s[:t.end()] + "".join(blocks) + s[t.end():]
open(p, "w").write(s)
PY
echo "Done. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
