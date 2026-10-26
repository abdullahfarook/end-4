#!/usr/bin/env bash
# Shared behavior of the left panels that are real windows on special workspaces (AI, Console, Teams, Git), the window
# counterpart of WidgetBase.qml. Every panel follows the same rules:
#   - one left panel per monitor: a panel (window or shell panel) opening on a monitor closes the panel shown there
#   - a panel stays on the monitor it was opened on; activity on another monitor never closes or moves it
#   - a click outside the panel, focus moving to another window, a workspace switch or the overview on its own monitor close it
# Per-panel scripts keep only what is specific to them (how to start/dock the window) and call this one for the rest.
#
#   side-panel.sh stamp NAME          record that NAME was toggled now (its own click/focus must not close it again)
#   side-panel.sh launching NAME      NAME is starting (window may appear seconds later): treat as toggled for 60 s
#   side-panel.sh recent NAME MS      exit 0 if NAME was toggled within MS milliseconds
#   side-panel.sh hidden-recently NAME MS   exit 0 if click-away hid NAME within MS milliseconds
#   side-panel.sh mon NAME            print the monitor NAME is shown on (empty if hidden)
#   side-panel.sh hide NAME [force]   hide NAME on its own monitor (force: even right after a toggle)
#   side-panel.sh hide-on MONITOR     hide whichever panel is shown on MONITOR
#   side-panel.sh clickaway           left-click handler: hide the panel on the clicked monitor if the click is outside it
#   side-panel.sh watch               single-instance event watcher (focus, overview, shell panels, stray windows)
PANELS="ai console teams vgit"
R="${XDG_RUNTIME_DIR:-/tmp}"
SELF="$(readlink -f "$0")"

# Window of a panel, for docking stray windows back (the panel workspace is special:NAME)
match() {
    case "$1" in
        ai) echo '.class=="ai-sidebar"' ;;
        console) echo '.class=="console-sidebar"' ;;
        teams) echo '(.class=="teams-for-linux" and (.title|test("Microsoft Teams")))' ;;
        vgit) echo '(.title|test("⎇"))' ;;
    esac
}
now() { date +%s%3N; }
age() { local f="$R/side-panel-$1-$2"; [ -e "$f" ] && echo $(( $(now) - $(cat "$f") )) || echo 999999; }
mon_of() { hyprctl monitors -j | jq -r --arg n "special:$1" '.[] | select(.specialWorkspace.name==$n) | .name' | head -1; }
panel_on() { hyprctl monitors -j | jq -r --arg m "$1" '.[] | select(.name==$m) | .specialWorkspace.name // ""' | sed -n 's/^special://p'; }
is_panel() { case " $PANELS " in *" $1 "*) return 0 ;; esac; return 1; }
focused_mon() { hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'; }
# Hyprland toggles a special workspace on the FOCUSED monitor: with focus elsewhere a plain toggle would move the panel
# there instead of hiding it. Toggle on the panel's own monitor and give focus back (the cursor does not move).
toggle_on() {  # $1 name, $2 monitor
    local f; f=$(focused_mon)
    if [ "$f" = "$2" ]; then hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$1\")" >/dev/null
    else
        hyprctl dispatch "hl.dsp.focus({ monitor = \"$2\" })" >/dev/null
        hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$1\")" >/dev/null
        hyprctl dispatch "hl.dsp.focus({ monitor = \"$f\" })" >/dev/null
    fi
}
# Most recently focused normal window on the focused monitor (closing the overview/popups must not refocus a hidden panel)
refocus() {
    local m a; m=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .id')
    a=$(hyprctl clients -j | jq -r --argjson m "${m:-0}" '[.[] | select(.mapped and .workspace.id > 0 and .monitor == $m)] | sort_by(.focusHistoryID) | .[0].address // empty')
    [ -n "$a" ] && hyprctl dispatch "hl.dsp.focus({ window = \"address:$a\" })" >/dev/null
}
hide() {  # $1 name, $2 force?  (serialized per panel, so concurrent callers can't hide and re-show it)
    local name=$1
    (
        flock 7
        [ "${2:-}" != force ] && [ "$(age "$name" toggled)" -lt 800 ] && exit 0
        # the screen-snip overlay is up: its clicks select a region and must not close the panel
        hyprctl layers -j | jq -e '[.. | objects | select(.namespace? == "quickshell:regionSelector")] | length > 0' >/dev/null && exit 0
        m=$(mon_of "$name")
        if [ -n "$m" ]; then toggle_on "$name" "$m"
        else  # stranded on a visible normal workspace: dock it back onto its (hidden) special workspace
            addr=$(hyprctl clients -j | jq -r --argjson a "$(hyprctl monitors -j | jq -c '[.[].activeWorkspace.id]')" \
                "[.[] | select($(match "$name") and .workspace.name != \"special:$name\" and (.workspace.id as \$i | \$a | index(\$i)))][0].address // empty")
            [ -n "$addr" ] && hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:$name\", window = \"address:$addr\", follow = false })" >/dev/null
        fi
    ) 7>"$R/side-panel-$name.lock"
    return 0
}
hide_on() { local p; p=$(panel_on "$1"); [ -n "$p" ] && is_panel "$p" && hide "$p" force; return 0; }

case "${1:-}" in
stamp) now > "$R/side-panel-$2-toggled" ;;
launching) echo $(( $(now) + 60000 )) > "$R/side-panel-$2-toggled" ;;
recent) [ "$(age "$2" toggled)" -lt "$3" ] ;;
hidden-recently) [ "$(age "$2" hidden)" -lt "$3" ] ;;
mon) mon_of "$2" ;;
hide) hide "$2" "${3:-}" ;;
hide-on) hide_on "$2" ;;
clickaway)
    sleep 0.08  # let a click on a panel's own bar button stamp its toggle first
    read -r cx cy < <(hyprctl cursorpos | tr -d ',')
    cm=$(hyprctl monitors -j | jq -r --argjson x "$cx" --argjson y "$cy" '.[] | select($x >= .x and $x < .x + .width and $y >= .y and $y < .y + .height) | .name' | head -1)
    [ -n "$cm" ] || exit 0
    name=$(panel_on "$cm"); [ -n "$name" ] && is_panel "$name" || exit 0   # only the panel on the clicked monitor
    [ "$(age "$name" toggled)" -lt 1000 ] && exit 0                          # this click toggled it
    inside=$(hyprctl clients -j | jq -r --arg w "special:$name" --argjson x "$cx" --argjson y "$cy" \
        '[.[] | select(.workspace.name == $w and $x >= .at[0] and $x <= .at[0] + .size[0] and $y >= .at[1] and $y <= .at[1] + .size[1])] | length')
    if [ "${inside:-0}" = 0 ]; then now > "$R/side-panel-$name-hidden"; hide "$name" force; fi ;;
watch)
    exec 8>"$R/side-panel-watch.lock"; flock -n 8 || exit 0
    socat -u "UNIX-CONNECT:$R/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" - | while IFS= read -r line; do
        case "$line" in
        openlayer\>\>quickshell:overview)  # launcher/overview opened: close the panel on that monitor
            m=$(focused_mon); hide_on "$m"
            p=$(hyprctl activewindow -j | jq -r '.workspace.name // ""' | sed -n 's/^special://p')
            [ -n "$p" ] && is_panel "$p" && refocus ;;
        openlayer\>\>quickshell:sidebarLeft)  # a shell panel (mail, file search, native sidebar, ...) opened: one panel per monitor
            hide_on "$(focused_mon)" ;;
        closelayer\>\>quickshell:overview)  # Hyprland may refocus a hidden panel window: hide it and give focus back
            sleep 0.15
            p=$(hyprctl activewindow -j | jq -r '.workspace.name // ""' | sed -n 's/^special://p')
            [ -n "$p" ] && is_panel "$p" && [ -z "$(mon_of "$p")" ] && refocus ;;
        activespecial\>\>*)  # a panel shown without a toggle (focus fell back onto it after a popup/overview closed): undo
            IFS=, read -r ws m <<<"${line#activespecial>>}"; p=${ws#special:}
            [ -n "$ws" ] && is_panel "$p" || continue
            [ "$(age "$p" toggled)" -lt 1500 ] && continue
            sleep 0.03; hide "$p" force; refocus ;;
        openwindow\>\>*)  # another app's window mapped onto a shown panel's workspace: move it out to the normal workspace
            IFS=, read -r addr ws class title <<<"${line#openwindow>>}"; p=${ws#special:}
            [ "$ws" != "$p" ] && is_panel "$p" || continue
            hyprctl clients -j | jq -e --arg a "0x$addr" ".[] | select(.address == \$a) | select($(match "$p"))" >/dev/null && continue
            dest=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .activeWorkspace.id')
            hyprctl dispatch "hl.dsp.window.move({ workspace = \"$dest\", window = \"address:0x$addr\" })" >/dev/null ;;
        activewindow\>\>*)  # focus moved to another window: close the panel on THAT window's monitor only
            [ "${line#activewindow>>}" = "," ] && continue
            sleep 0.05
            read -r ws wm < <(hyprctl activewindow -j | jq -r '"\(.workspace.name // "") \(.monitor // -1)"')
            [ -n "$ws" ] || continue
            p=${ws#special:}; is_panel "$p" && [ "$ws" != "$p" ] && continue    # focus is on a panel itself
            m=$(hyprctl monitors -j | jq -r --argjson i "$wm" '.[] | select(.id == $i) | .name')
            [ -n "$m" ] || continue
            p=$(panel_on "$m"); [ -n "$p" ] && is_panel "$p" && hide "$p" ;;
        esac
    done ;;
*) sed -n '2,20p' "$SELF"; exit 2 ;;
esac
