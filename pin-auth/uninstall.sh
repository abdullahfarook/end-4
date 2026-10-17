#!/usr/bin/env bash
[ "$EUID" -eq 0 ] || exec pkexec bash "$(readlink -f "$0")"
sed -i '/pam_pwdfile/d;/pam_faillock.so preauth/d' /etc/pam.d/sudo
rm -f /etc/pam.d/polkit-1 /etc/pin.pwd
echo removed
