#!/usr/bin/env bash
# After a screen recording stops: make a GIF next to the MP4 (per Settings) and copy files to the clipboard (per Settings).
# Config (Settings > Services): screenRecord.format = mp4 | gif | both (files kept), screenRecord.copy = none | mp4 | gif | both (files copied).
# usage: record-gif.sh recording.mp4        env: GIF_FPS (15), GIF_WIDTH (800), GIF_CLIP=file|image (file; image copies the GIF as image data)
mp4="$1"; [ -f "$mp4" ] || exit 1
cfg="$HOME/.config/illogical-impulse/config.json"
fmt=$(jq -r '.screenRecord.format // "mp4"' "$cfg" 2>/dev/null || echo mp4)
copy=$(jq -r '.screenRecord.copy // "gif"' "$cfg" 2>/dev/null || echo gif)
gif="${mp4%.mp4}.gif"; fps="${GIF_FPS:-15}"; w="${GIF_WIDTH:-800}"
if [ "$fmt" != mp4 ]; then
    notify-send "Making GIF" "$(basename "$gif")" -a 'Recorder'
    if ffmpeg -y -loglevel error -i "$mp4" -vf "fps=$fps,scale='min($w,iw)':-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5" "$gif"; then
        [ "$fmt" = gif ] && rm -f "$mp4"
    else
        notify-send "GIF conversion failed" "$mp4" -a 'Recorder'; exit 1
    fi
fi
files=()
case "$copy" in mp4|both) [ -f "$mp4" ] && files+=("$mp4") ;; esac
case "$copy" in gif|both) [ -f "$gif" ] && files+=("$gif") ;; esac
if [ ${#files[@]} -eq 0 ]; then exit 0; fi
if [ "${GIF_CLIP:-file}" = image ] && [ -f "$gif" ] && [ "$copy" = gif ]; then wl-copy -t image/gif < "$gif"
else printf 'file://%s\n' "${files[@]}" | wl-copy -t text/uri-list; fi
names=$(printf '%s, ' "${files[@]##*/}"); names="${names%, }"
notify-send "Recording ready to paste" "Ctrl+V to paste (${names})" -a 'Recorder'
