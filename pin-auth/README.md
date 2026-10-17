# pin-auth
PIN as an alternative to the password for sudo + pkexec via pam_pwdfile (hash in /etc/pin.pwd).
Password still works. Wrong PINs count toward pam_faillock. Run ./install.sh; undo with ./uninstall.sh.
