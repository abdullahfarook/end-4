#!/usr/bin/env bash
# Adds the PIN check to pkexec (polkit-1). Run after install.sh. Revert: sudo rm /etc/pam.d/polkit-1
[ "$EUID" -eq 0 ] || exec sudo bash "$(readlink -f "$0")"
[ -f /etc/pam.d/polkit-1 ] && { echo "already exists"; exit 0; }
PAM_LINES='auth       required     pam_faillock.so preauth
auth       sufficient   pam_pwdfile.so pwdfile=/etc/pin.pwd'
{ echo '#%PAM-1.0'; echo "$PAM_LINES"; tail -n +2 /usr/lib/pam.d/polkit-1; } > /etc/pam.d/polkit-1
chmod 644 /etc/pam.d/polkit-1; cat /etc/pam.d/polkit-1
