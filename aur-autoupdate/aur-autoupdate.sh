#!/bin/sh
# Updates the AUR packages listed in aur-packages.list (only those with a newer version), at startup.
# Root step goes through pkexec (graphical prompt). Log: ~/.local/state/aur-autoupdate.log
list=${AUR_LIST:-$HOME/.config/aur-autoupdate/aur-packages.list}
log=$HOME/.local/state/aur-autoupdate.log
mkdir -p "$(dirname "$log")"
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/aur-autoupdate.lock"; flock -n 9 || exit 0
[ -f "$list" ] || exit 0
exec >>"$log" 2>&1; echo "== $(date -Is)"
nm-online -q -t 120 || { echo "offline, skipped"; exit 0; }
wanted=$(sed 's/#.*//' "$list" | tr -s ' \t\n' '\n' | sed '/^$/d')
[ -n "$wanted" ] || exit 0
outdated=$(yay -Qua 2>/dev/null | awk '{print $1}')
todo=$(for p in $outdated; do printf "%s\n" "$wanted" | grep -Fxq "$p" && echo "$p"; done)
[ -n "$todo" ] || { echo "nothing to update"; exit 0; }
echo "updating: $todo"
if yay -S --noconfirm --needed --sudo pkexec --answerclean None --answerdiff None --answeredit None --answerupgrade None $todo; then
  notify-send -a "AUR update" "AUR packages updated" "$(echo $todo)"
else
  notify-send -u critical -a "AUR update" "AUR update failed" "See $log"
fi
