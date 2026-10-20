#!/usr/bin/env bash
# Zen (native, pacman zen-browser-bin) "Open in mpv" via the ff2mpv extension: host script + native-messaging manifest + window rules (idempotent).
# Needs: mpv, yt-dlp, the ff2mpv extension (ff2mpv@yossarian.net) installed in Zen.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
ZEN="$HOME/.zen"; KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
BACKUP="$HOME/backups/zen-mpv/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP"; cp "$KEYBINDS" "$BACKUP/"
[ -d "$HOME/.mozilla/native-messaging-hosts" ] && cp -r "$HOME/.mozilla/native-messaging-hosts" "$BACKUP/" || true
# mpv config for the Zen window (upscaler picker); shaders are downloaded, not stored in git
mkdir -p "$HOME/.config/mpv-upscale/scripts"
install -Dm644 "$REPO/mpv-upscale/mpv.conf" "$HOME/.config/mpv-upscale/mpv.conf"
install -Dm644 "$REPO/mpv-upscale/input.conf" "$HOME/.config/mpv-upscale/input.conf"
install -Dm644 "$REPO/mpv-upscale/scripts/upscale-menu.lua" "$HOME/.config/mpv-upscale/scripts/upscale-menu.lua"
"$REPO/mpv-upscale/fetch-shaders.sh"
install -Dm755 "$REPO/ff2mpv-host.py" "$HOME/.local/bin/ff2mpv-host"
# Zen (native) reads the standard Firefox folder ~/.mozilla/native-messaging-hosts (not ~/.zen), so the manifest goes there
NMH="$HOME/.mozilla/native-messaging-hosts"; mkdir -p "$NMH"
cat > "$NMH/ff2mpv.json" <<JSON
{"name": "ff2mpv", "description": "ff2mpv native host", "path": "$HOME/.local/bin/ff2mpv-host", "type": "stdio", "allowed_extensions": ["ff2mpv@yossarian.net", "mpv-sniffer@local"]}
JSON
# mpv Stream Sniffer extension: packaged only, NOT installed into the profile (it is unsigned; loading it is up to you: about:debugging ->
# This Firefox -> Load Temporary Add-on -> extension/manifest.json, or sign it with Mozilla and install the signed file)
( cd "$REPO/extension" && rm -f "$HOME/.config/mpv-upscale/mpv-sniffer.xpi" && bsdtar --format zip -cf "$HOME/.config/mpv-upscale/mpv-sniffer.xpi" . )
python3 - "$KEYBINDS" "$REPO/zen-mpv-rules.lua" <<'PY'
import re, sys
kb, rules = sys.argv[1:3]
snippet = open(rules).read().rstrip("\n"); t = open(kb).read()
pat = r"-- >>> zen-mpv >>>.*?-- <<< zen-mpv <<<"
t = re.sub(pat, lambda _: snippet, t, flags=re.S) if re.search(pat, t, re.S) else t.rstrip("\n") + "\n\n" + snippet + "\n"
open(kb, "w").write(t)
PY
echo "Done. Zen picks up the manifest on the next ff2mpv click."
