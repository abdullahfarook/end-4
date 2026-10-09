#!/usr/bin/env bash
# Toggles the left AI sidebar. Backend comes from ai.sidebarBackend in the illogical-impulse config:
#   native -> the shell's own Intelligence sidebar
#   claude / codex / antigravity -> a kitty window running that CLI on the "ai" special workspace
date +%s%3N > "${XDG_RUNTIME_DIR:-/tmp}/ai-sidebar-toggled"  # lets the click-away handler ignore the click that caused this toggle
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/ai-sidebar.lock"; flock 9
backend=$(jq -r '.ai.sidebarBackend // "native"' "$HOME/.config/illogical-impulse/config.json" 2>/dev/null)
if [ "$backend" != claude ] && [ "$backend" != codex ] && [ "$backend" != antigravity ]; then
    exec hyprctl dispatch 'hl.dsp.global("quickshell:sidebarLeftToggle")'
fi
# Window title carries the backend so a changed setting replaces a stale window
nohup "$HOME/.config/hypr/custom/ai-sidebar-watch.sh" >/dev/null 2>&1 9>&- &
title="ai-sidebar-$backend"
clients=$(hyprctl clients -j)
stale=$(jq -r '.[] | select(.class=="ai-sidebar" and .title!="'"$title"'") | .address' <<<"$clients")
for a in $stale; do hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null; done
win=$(jq -c '[.[] | select(.class=="ai-sidebar" and .title=="'"$title"'")][0] // empty' <<<"$clients")
if [ -n "$win" ]; then
    addr=$(jq -r .address <<<"$win")
    if hyprctl monitors -j | jq -e 'any(.[]; .specialWorkspace.name=="special:ai")' >/dev/null; then
        hyprctl dispatch 'hl.dsp.workspace.toggle_special("ai")' >/dev/null  # shown -> hide
    else
        # The window can be stranded on a normal workspace (moved/dragged/restored there): dock it back first
        if [ "$(jq -r .workspace.name <<<"$win")" != special:ai ]; then
            visible=$(hyprctl monitors -j | jq --argjson w "$(jq .workspace.id <<<"$win")" 'any(.[]; .activeWorkspace.id == $w)')
            hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:ai\", window = \"address:$addr\", follow = false })" >/dev/null
            [ "$visible" = true ] && exit 0  # it was on screen: moving it away is the hide
        fi
        hyprctl dispatch 'hl.dsp.workspace.toggle_special("ai")' >/dev/null  # show
        sleep 0.1; hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null  # make sure typing goes to it
    fi
else
    # Resume the last conversation (survives restart/logout); start a new one if there is none
    case $backend in
        claude) cmd='f="$HOME/repos/end-4/claude/shell.md"; set -- ; [ -r "$f" ] && set -- --append-system-prompt-file "$f"; claude --continue "$@" || exec claude "$@"' ;;
        codex)  cmd='codex resume --last || exec codex' ;;
        # agy has no system-prompt flag: a new conversation gets the same standing instructions as its first prompt
        antigravity) cmd='f="$HOME/repos/end-4/claude/shell.md"; agy --continue || { [ -r "$f" ] && exec agy -i "$(cat "$f")"; exec agy; }' ;;
    esac
    # Scrub Claude Code's own env: if this script was run from inside a claude session (tests, tools), kitty would
    # carry CLAUDE_CODE_CHILD_SESSION/SESSION_ID forever and every sidebar claude would start with transcript saving off
    for v in $(compgen -e | grep -E '^(CLAUDE_CODE_|CLAUDECODE$)'); do unset "$v"; done
    nohup kitty --class ai-sidebar --title "$title" -d "$HOME" sh -c "$cmd" >/dev/null 2>&1 9>&- &
fi
