#!/usr/bin/env bash
# Max CPU frequency cap via cpufreq scaling_max_freq (kHz). "auto" = no cap (hardware max).
#   cpu-freq.sh get          -> "auto|<kHz> <min kHz> <max kHz>"-style: "<mode> <khz> <min> <max>"
#   cpu-freq.sh auto         -> remove the cap and save
#   cpu-freq.sh set <MHz>    -> cap and save
#   cpu-freq.sh restore      -> re-apply the saved state (login / after resume)
D=/sys/devices/system/cpu/cpu0/cpufreq
S="${XDG_STATE_HOME:-$HOME/.local/state}/cpu-freq"
mkdir -p "$(dirname "$S")"
[ -f "$S" ] || echo "auto" > "$S"
min=$(cat $D/cpuinfo_min_freq); max=$(cat $D/cpuinfo_max_freq)
read -r mode khz < "$S"
apply() {
    v=$max; [ "$mode" = cap ] && v=$khz
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo "$v" > "$f"; done
}
case "${1:-get}" in
    get) echo "$mode ${khz:-$max} $min $max" ;;
    auto) mode=auto; echo auto > "$S"; apply ;;
    set) mode=cap; khz=$(( ${2:?MHz} * 1000 )); [ "$khz" -lt "$min" ] && khz=$min
         if [ "$khz" -ge "$max" ]; then mode=auto; echo auto > "$S"; else echo "cap $khz" > "$S"; fi; apply ;;
    restore) [ "$mode" = auto ] || apply ;;
    *) echo "usage: $0 get|auto|set MHz|restore" >&2; exit 2 ;;
esac
