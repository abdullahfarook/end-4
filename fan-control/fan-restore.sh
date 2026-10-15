#!/usr/bin/env bash
# Re-applies the saved fan setting at login and after every resume from sleep (firmware resets it).
H="$(dirname "$0")/fan-control.sh"
"$H" restore
"$(dirname "$0")/cpu-freq.sh" restore
dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" 2>/dev/null |
while read -r line; do
    case "$line" in *"boolean false"*) sleep 3; "$H" restore; "$(dirname "$0")/cpu-freq.sh" restore ;; esac
done
