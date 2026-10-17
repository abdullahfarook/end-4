#!/usr/bin/env bash
# Adds a PIN as an alternative to the password for sudo and pkexec (polkit).
# The password keeps working; failed PINs count toward pam_faillock (system-auth).
set -euo pipefail
USER_NAME="${SUDO_USER:-$USER}"

if [ "$EUID" -ne 0 ]; then
  read -rsp "New PIN (6+ digits): " pin; echo
  read -rsp "Repeat PIN: " pin2; echo
  [[ "$pin" =~ ^[0-9]{6,}$ ]] || { echo "PIN must be 6+ digits"; exit 1; }
  [ "$pin" = "$pin2" ] || { echo "PINs differ"; exit 1; }
  hash=$(openssl passwd -6 "$pin"); unset pin pin2
  exec pkexec env HASH="$hash" TARGET_USER="$USER_NAME" bash "$(readlink -f "$0")"
fi

USER_NAME="$TARGET_USER"
ts=$(date +%Y%m%d-%H%M%S)
bk="/home/$USER_NAME/backups/pam/$ts-install"
mkdir -p "$bk"; cp -a /etc/pam.d "$bk/"; chown -R "$USER_NAME": "/home/$USER_NAME/backups/pam"

pacman -Q libpam_pwdfile >/dev/null 2>&1 || pacman -S --noconfirm libpam_pwdfile

umask 077
printf '%s:%s\n' "$USER_NAME" "$HASH" > /etc/pin.pwd
chmod 600 /etc/pin.pwd; chown root:root /etc/pin.pwd

PAM_LINES='auth       required     pam_faillock.so preauth
auth       sufficient   pam_pwdfile.so pwdfile=/etc/pin.pwd'

if ! grep -q pam_pwdfile /etc/pam.d/sudo; then
  { head -n1 /etc/pam.d/sudo; echo "$PAM_LINES"; tail -n +2 /etc/pam.d/sudo; } > /etc/pam.d/sudo.new
  chmod 644 /etc/pam.d/sudo.new; mv /etc/pam.d/sudo.new /etc/pam.d/sudo
fi
if [ "${WITH_POLKIT:-0}" = 1 ] && [ ! -f /etc/pam.d/polkit-1 ]; then
  { echo '#%PAM-1.0'; echo "$PAM_LINES"; tail -n +2 /usr/lib/pam.d/polkit-1; } > /etc/pam.d/polkit-1
fi
chmod 644 /etc/pam.d/polkit-1 2>/dev/null || true
echo "Done. Backup: $bk. Test in a NEW terminal while keeping a root shell open."
