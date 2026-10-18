# dns
Clones the `Dure` Wi-Fi profile to `Dure-DNS` with DNS 1.1.1.1/9.9.9.9/8.8.8.8 (ignores router DNS). Original `Dure` is untouched.
Rollback: `nmcli con up Dure; nmcli con delete Dure-DNS`.
