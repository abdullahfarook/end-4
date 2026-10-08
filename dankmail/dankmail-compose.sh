#!/usr/bin/env bash
# Opens a compose window and brings it to the workspace you are on (it otherwise appears on the workspace the UI was created on).
S="${XDG_RUNTIME_DIR:-/tmp}/dankmail.sock"
[ -S "$S" ] || { systemctl --user start dmail; sleep 3; }
(echo '{"id":1,"method":"ui.compose","params":{}}'; sleep 0.5) | socat - "UNIX-CONNECT:$S" >/dev/null
for _ in $(seq 40); do
    a=$(hyprctl clients -j | jq -r '.[]|select(.class=="org.arqueon.dankmail" and (.title|startswith("New message")))|.address' | head -1)
    [ -n "$a" ] && break
    sleep 0.1
done
[ -n "${a:-}" ] || exit 0
ws=$(hyprctl activeworkspace -j | jq -r .id)
hyprctl dispatch "hl.dsp.window.move({ workspace = \"$ws\", window = \"address:$a\" })" >/dev/null
hyprctl dispatch "hl.dsp.focus({ window = \"address:$a\" })" >/dev/null
