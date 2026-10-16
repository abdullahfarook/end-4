#!/usr/bin/env bash
# Docker on demand: docker.socket enabled (starts the daemon on first `docker` command), docker.service disabled at boot,
# idle timer stops the daemon after ~60 s with no running containers. Needs root once (pkexec). Idempotent.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$HOME/backups/docker-on-demand/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
systemctl is-enabled docker.service docker.socket docker-idle-stop.timer > "$BACKUP/unit-state.txt" 2>&1 || true
echo "Backed up to $BACKUP"
pkexec sh -c "
install -m755 '$REPO/docker-idle-stop.sh' /usr/local/bin/docker-idle-stop.sh &&
install -m644 '$REPO/docker-idle-stop.service' '$REPO/docker-idle-stop.timer' /etc/systemd/system/ &&
install -m644 '$REPO/50-docker-service.rules' /etc/polkit-1/rules.d/ &&
systemctl daemon-reload &&
systemctl disable docker.service &&
systemctl enable --now docker.socket docker-idle-stop.timer"
# Quickshell widget: count poll must not wake the daemon
"$REPO/../docker-widget/install.sh"
