#!/usr/bin/python3 -I
# Native-messaging host for the ff2mpv extension (native Zen runs it directly).
# Reads one message {"url": ...}, starts a small floating mpv (rules in zen-mpv-rules.lua match the title "zen-mpv") and answers nothing.
import json, os, struct, subprocess, sys

n = sys.stdin.buffer.read(4)
if len(n) < 4:
    sys.exit(0)
raw = sys.stdin.buffer.read(struct.unpack("=I", n)[0])
LOG = os.path.expanduser("~/.cache/zen-mpv.log")
open(LOG, "a").write(raw.decode(errors="replace") + "\n")  # last messages from the extension, for debugging
url = json.loads(raw)["url"]
if not url.startswith(("http://", "https://", "file://")):
    sys.exit(1)
profile = os.path.expanduser("~/.zen/c0u92kn2.Default (release)")  # YouTube's bot check needs the browser's cookies
subprocess.Popen(
    ["mpv", "--title=zen-mpv", "--force-window=immediate", "--keep-open=yes", "--osc=yes",
     "--script-opts=osc-vidscale=no,osc-scalewindowed=1.8",
     "--ytdl-format=bv*[height<=720]+ba/b[height<=720]/b",
     "--ytdl-raw-options=cookies-from-browser=firefox:" + profile.replace(":", "\\:"), "--", url],
    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
