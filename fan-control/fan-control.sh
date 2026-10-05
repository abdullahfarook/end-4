#!/usr/bin/env bash
# Acer fan control via the linuwu_sense sysfs file ("cpu,gpu" percent; 0,0 = auto, 100,100 = max).
#   fan-control.sh get            -> "<mode> <cpu> <gpu>" from the saved state (mode: auto|max|manual)
#   fan-control.sh auto|max       -> set and save
#   fan-control.sh manual CPU GPU -> set and save (percent, 5..100)
#   fan-control.sh restore        -> re-apply the saved state (login / after resume)
F=/sys/devices/platform/acer-wmi/nitro_sense/fan_speed
S="${XDG_STATE_HOME:-$HOME/.local/state}/fan-control"
mkdir -p "$(dirname "$S")"
[ -f "$S" ] || echo "auto 50 50" > "$S"
read -r mode cpu gpu < "$S"
clamp() { v=$(( $1 )); [ "$v" -lt 5 ] && v=5; [ "$v" -gt 100 ] && v=100; echo "$v"; }
apply() {
    case "$mode" in
        auto) v="0,0" ;;
        max) v="100,100" ;;
        *) v="$cpu,$gpu" ;;
    esac
    echo "$v" > "$F"
}
case "${1:-get}" in
    get) echo "$mode $cpu $gpu" ;;
    auto|max) mode=$1; echo "$mode $cpu $gpu" > "$S"; apply ;;
    manual) mode=manual; cpu=$(clamp "${2:-$cpu}"); gpu=$(clamp "${3:-$gpu}"); echo "$mode $cpu $gpu" > "$S"; apply ;;
    restore) [ "$mode" = auto ] || apply ;;
    *) echo "usage: $0 get|auto|max|manual CPU GPU|restore" >&2; exit 2 ;;
esac
