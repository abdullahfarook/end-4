#!/usr/bin/env bash
# Usage: gsearch.sh show <query> | goto <url> | hide | back | forward | reload | stop | open
# Single-instance launcher/controller for gsearch.qml (QtWebEngine via qml6, no Python). Only show/goto start the window;
# commands go through $XDG_RUNTIME_DIR/gsearch-cmd. `hide` quits it. Colors come from env GSEARCH_BG / GSEARCH_THUMB / GSEARCH_THUMB_HOVER.
RUN="${XDG_RUNTIME_DIR:-/tmp}"; DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cmd="${1:-show}"; shift; arg="$*"
CMDF="$RUN/gsearch-cmd"; STATUS="$RUN/gsearch-status"
running() { pgrep -f "^(/usr/bin/)?qml6 .*gsearch\\.qml" >/dev/null; }
send() { printf '%s\t%s\t%s' "$(date +%s%N)" "$cmd" "$arg" > "$CMDF.tmp" && mv -f "$CMDF.tmp" "$CMDF"; }
exec 9>"$RUN/gsearch.lock"; flock -w 5 9 || exit 1
if running; then send; exit 0; fi
case "$cmd" in show|goto) ;; *) exit 0 ;; esac
: > "$STATUS"; send
export QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1 QML_XHR_ALLOW_FILE_READ=1
( setsid qml6 "$DIR/gsearch.qml" -- "${GSEARCH_BG:-#1f1f1f}" "${GSEARCH_THUMB:-#6a6a6a}" "${GSEARCH_THUMB_HOVER:-#9a9a9a}" \
      "cmdfile=$CMDF" "data=$HOME/.local/share/gsearch" 2>&1 >/dev/null \
  | sed -u -n 's/^qml: GS //p' >> "$STATUS" ) 9>&- &
disown
