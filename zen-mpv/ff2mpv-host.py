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
msg = json.loads(raw)
url = msg["url"]
stream = bool(msg.get("stream"))          # from the mpv Stream Sniffer extension: a detected HLS/DASH/file address, not a page
referer, origin = msg.get("referer") or "", msg.get("origin") or ""
sources_arg = []
if msg.get("sources"):                    # all detected streams: mpv's right-click menu > Sources lets you switch between them
    sdir = os.path.expanduser("~/.cache/zen-mpv"); os.makedirs(sdir, exist_ok=True)
    for old in sorted(os.listdir(sdir))[:-20]:   # keep only the newest files
        try: os.remove(os.path.join(sdir, old))
        except OSError: pass
    spath = os.path.join(sdir, "sources-%d.json" % os.getpid())
    json.dump({"current": url, "sources": msg["sources"]}, open(spath, "w"))
    sources_arg = ["--script-opts-append=zenmpv-sources=" + spath]
if not url.startswith(("http://", "https://", "file://")):
    sys.exit(1)
profile = os.path.expanduser("~/.zen/c0u92kn2.Default (release)")  # YouTube's bot check needs the browser's cookies
# No window is forced open (force-window=no): mpv only shows one once it has a video, so a page without video never flashes a blank window.
# Run mpv under a tiny shell watcher: when it cannot play the page (exit code 2), say so with a notification.
cmd = ["mpv", "--config-dir=" + os.path.expanduser("~/.config/mpv-upscale"), "--title=zen-mpv", "--force-window=no", "--network-timeout=15", "--keep-open=yes", "--osc=yes",
       "--ytdl-format=bv*[height<=1080]+ba/b[height<=1080]/b",
       "--ytdl-raw-options=cookies-from-browser=firefox:" + profile.replace(":", "\\:"), ] + (["--ytdl=no"] if stream else []) \
       + (["--referrer=" + referer] if referer.startswith("http") else []) \
       + (["--http-header-fields=Origin: " + origin] if origin.startswith("http") else []) + sources_arg + ["--", url]
script = '"$@"; [ $? -eq 2 ] && notify-send -a "Open in mpv" "No video found" "mpv could not find a playable video on this page (no stream was detected and yt-dlp does not know the site). Start playback in the page first, then try again."'
subprocess.Popen(["sh", "-c", script, "sh"] + cmd,
                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
# Answer the extension: it awaits a reply, and a host that exits silently makes it report "An unexpected error occurred" even though mpv started
reply = json.dumps({"ok": True}).encode()
sys.stdout.buffer.write(struct.pack("=I", len(reply)) + reply)
sys.stdout.buffer.flush()
