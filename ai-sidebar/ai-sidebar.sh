#!/usr/bin/env bash
# Toggles the left AI sidebar. Backend comes from ai.sidebarBackend in the illogical-impulse config:
#   native -> the shell's own Intelligence sidebar
#   claude / codex / antigravity -> a kitty window running that CLI on the "ai" special workspace
P="$HOME/.config/hypr/custom/side-panel.sh"   # shared window-panel behavior (closing, monitors, focus)
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/ai-sidebar.lock"; flock 9
backend=$(jq -r '.ai.sidebarBackend // "native"' "$HOME/.config/illogical-impulse/config.json" 2>/dev/null)
if [ "$backend" != claude ] && [ "$backend" != codex ] && [ "$backend" != antigravity ]; then
    exec hyprctl dispatch 'hl.dsp.global("quickshell:sidebarLeftToggle")'
fi
# Window title carries the backend so a changed setting replaces a stale window
title="ai-sidebar-$backend"
clients=$(hyprctl clients -j)
stale=$(jq -r '.[] | select(.class=="ai-sidebar" and .title!="'"$title"'") | .address' <<<"$clients")
for a in $stale; do hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null; done
[ -n "$stale" ] && sleep 0.3   # gone before the shared toggle looks for the window
"$P" toggle ai 9>&-; [ $? = 3 ] || exit 0   # shared: hide / show here / dock a stray window
# Resume the last conversation (survives restart/logout); start a new one if there is none
case $backend in
    claude) cmd='f="$HOME/repos/ii-dev/claude/shell.md"; set -- ; [ -r "$f" ] && set -- --append-system-prompt-file "$f"; claude --continue "$@" || exec claude "$@"' ;;
    codex)  cmd='codex resume --last || exec codex' ;;
    # agy has no system-prompt flag: a new conversation gets the same standing instructions as its first prompt
    antigravity) cmd='f="$HOME/repos/ii-dev/claude/shell.md"; agy --continue || { [ -r "$f" ] && exec agy -i "$(cat "$f")"; exec agy; }' ;;
esac
# Scrub Claude Code's own env: if this script was run from inside a claude session (tests, tools), kitty would
# carry CLAUDE_CODE_CHILD_SESSION/SESSION_ID forever and every sidebar claude would start with transcript saving off
for v in $(compgen -e | grep -E '^(CLAUDE_CODE_|CLAUDECODE$)'); do unset "$v"; done
nohup kitty -o window_padding_width=0 -o window_margin_width=10 -o font_size=10 --class ai-sidebar --title "$title" -d "$HOME" sh -c "$cmd" >/dev/null 2>&1 9>&- &
