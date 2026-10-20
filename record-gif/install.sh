#!/usr/bin/env bash
# After a recording stops (bar camera button / record.sh), convert it to a GIF next to the MP4 and copy the GIF to the clipboard
# (as a file, paste into Dolphin/chat apps; GIF_CLIP=image copies image data instead). Patches the upstream record.sh (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
R="$HOME/.config/quickshell/ii/scripts/videos/record.sh"
B="$HOME/backups/record-gif/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$B"; cp "$R" "$B/"
install -Dm755 "$REPO/record-gif.sh" "$HOME/.config/hypr/custom/record-gif.sh"
python3 - "$R" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
if "record-gif.sh" in s: sys.exit(0)
s = s.replace('notify-send "Starting recording"', 'RECORDED=1; notify-send "Starting recording"')
s = s.rstrip("\n") + '\n\n# once wf-recorder has exited (the stop press kills it): make a GIF and copy it\nif [[ -n "${RECORDED:-}" ]]; then\n    latest=$(ls -t recording_*.mp4 2>/dev/null | head -1)\n    [[ -n "$latest" ]] && "$HOME/.config/hypr/custom/record-gif.sh" "$PWD/$latest"\nfi\n'
open(p, "w").write(s)
PY
Q="$HOME/.config/quickshell/ii"; cp "$Q/modules/common/Config.qml" "$Q/modules/settings/ServicesConfig.qml" "$B/"
python3 "$REPO/patch-settings.py" "$Q/modules/common/Config.qml" "$Q/modules/settings/ServicesConfig.qml"
echo "Done."
