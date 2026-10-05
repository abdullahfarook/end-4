# Shared helpers for ALT+Tab workspace MRU (most recently used first).
rt=${XDG_RUNTIME_DIR:-/tmp}
mru_file="$rt/ws-mru"
mru_push() {  # move workspace id $1 to the front
    [ "${1:-0}" -gt 0 ] 2>/dev/null || return 0
    { echo "$1"; grep -vx "$1" "$mru_file" 2>/dev/null; } | head -n 30 >"$mru_file.tmp" && mv "$mru_file.tmp" "$mru_file"
}
