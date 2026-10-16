#!/bin/sh
# Stop docker.service after it has had no running containers for ~60 s. docker.socket stays enabled, so the next `docker ...` starts it again.
M=/run/docker-idle-since
systemctl is-active --quiet docker.service || { rm -f "$M"; exit 0; }   # never wake it just to check
if [ -n "$(docker ps -q 2>/dev/null)" ]; then rm -f "$M"; exit 0; fi
[ -f "$M" ] || { : > "$M"; exit 0; }
[ $(( $(date +%s) - $(stat -c %Y "$M") )) -ge 60 ] && { systemctl stop docker.service; rm -f "$M"; }
exit 0
