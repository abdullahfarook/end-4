#!/usr/bin/env bash
# Bar resources: animate show/hide of an indicator (swap on hover, GPU, CPU) as one smooth transition instead of separate width/slide animations
# that popped in at full width and overlapped neighbours. A single `progress` (0..1) drives width, slide, fade and the left margin. Idempotent.
set -euo pipefail
D="$HOME/.config/quickshell/ii/modules/ii/bar"
BACKUP="$HOME/backups/swap-bar-threshold/anim-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP"; cp "$D/Resource.qml" "$D/Resources.qml" "$BACKUP/"
python3 - "$D" <<'PY'
import sys
d = sys.argv[1]
def sub(path, pairs):
    t = open(path).read()
    for a, b in pairs:
        if a in t: t = t.replace(a, b)
        elif b not in t: sys.exit(f"pattern missing in {path}: {a[:40]!r}")
    open(path, "w").write(t)
sub(d + "/Resource.qml", [
 ("    implicitWidth: resourceRowLayout.x < 0 ? 0 : resourceRowLayout.implicitWidth\n",
  "    property real progress: shown ? 1 : 0\n    implicitWidth: resourceRowLayout.implicitWidth * progress\n    opacity: progress\n"),
 ("        x: shown ? 0 : -resourceRowLayout.width\n", "        x: -(1 - root.progress) * resourceRowLayout.width\n"),
 ("        Behavior on x {\n            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)\n        }\n", ""),
 ("        enabled: resourceRowLayout.x >= 0 && root.width > 0 && root.visible", "        enabled: root.progress > 0.99 && root.visible"),
 ("    Behavior on implicitWidth {", "    Behavior on progress {"),
])
sub(d + "/Resources.qml", [("Layout.leftMargin: shown ? 6 : 0", "Layout.leftMargin: 6 * progress")])
PY
echo "Applied. Restart the shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
