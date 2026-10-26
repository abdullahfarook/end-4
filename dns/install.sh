#!/usr/bin/env bash
# Creates a "Dure-DNS" Wi-Fi profile cloned from "Dure" with fixed resolvers (router DNS is EDNS0-degraded).
set -e
b=~/backups/dns/$(date +%Y%m%d-%H%M%S); mkdir -p "$b"
pkexec cp -a /etc/NetworkManager/system-connections "$b/"; pkexec chown -R "$USER" "$b"
nmcli con show Dure-DNS >/dev/null 2>&1 || nmcli con clone Dure Dure-DNS
nmcli con mod Dure-DNS ipv4.ignore-auto-dns yes ipv4.dns "1.1.1.1 9.9.9.9 8.8.8.8" ipv6.ignore-auto-dns yes connection.autoconnect-priority 10
nmcli con up Dure-DNS
# Global: apply the same resolvers to every saved connection
for c in $(nmcli -t -f NAME,TYPE con show | grep -E '802-11-wireless|802-3-ethernet' | cut -d: -f1); do
  nmcli con mod "$c" ipv4.ignore-auto-dns yes ipv4.dns "1.1.1.1 9.9.9.9 8.8.8.8" ipv6.ignore-auto-dns yes
done
