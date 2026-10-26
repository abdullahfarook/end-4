# dns
Clones the `Dure` Wi-Fi profile to `Dure-DNS` with DNS 1.1.1.1/9.9.9.9/8.8.8.8 (ignores router DNS). Original `Dure` is untouched.
Rollback: `nmcli con up Dure; nmcli con delete Dure-DNS`.

Global: the installer also sets the same DNS (ignoring router DNS) on every saved Wi-Fi/Ethernet profile (Connation B, Connation 786 5G, Dure, Wired connection 1). Reconnect to apply. Backups: `~/backups/dns/<timestamp>-global`. Undo per profile: `nmcli con mod "<name>" ipv4.ignore-auto-dns no ipv4.dns "" ipv6.ignore-auto-dns no`.
