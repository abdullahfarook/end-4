#!/usr/bin/env bash
# Clicking the media title in the media controls focuses the app/workspace/tab playing it.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
F="$HOME/.config/quickshell/ii/modules/ii/mediaControls/PlayerControl.qml"
B="$HOME/backups/media-goto/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$B"; cp "$F" "$B/"
install -Dm755 "$REPO/goto-player.sh" "$HOME/.config/hypr/custom/goto-player.sh"
python3 - "$F" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
if "goto-player.sh" in s: print("already patched"); sys.exit()
old='''                    animationDistanceY: 0
                }
                StyledText {
                    id: trackArtist'''
new='''                    animationDistanceY: 0
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/custom/goto-player.sh", root.player?.trackTitle ?? "", root.player?.desktopEntry || root.player?.identity || ""])
                    }
                }
                StyledText {
                    id: trackArtist'''
assert old in s; open(p,"w").write(s.replace(old,new,1))
PY
echo "Installed. Restart shell: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
