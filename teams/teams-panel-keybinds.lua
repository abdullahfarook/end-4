-- >>> teams-panel >>>
-- Teams panel: Teams for Linux floated on special:teams (left, like the Git panel). Toggle from the bar button or SUPER + ALT + T; click outside to hide.
hl.bind("SUPER + ALT + T", hl.dsp.exec_cmd("~/.config/hypr/custom/teams-panel.sh"), { description = "Toggle Teams panel" })
hl.bind("mouse:272", hl.dsp.exec_cmd("~/.config/hypr/custom/teams-panel-clickaway.sh"), { non_consuming = true, description = "Teams panel: hide on outside click" })
hl.workspace_rule({ workspace = "special:teams", gaps_out = 12 })
hl.window_rule({ match = { workspace = "special:teams" }, rounding = 20 })
-- Open Teams windows straight onto the hidden special workspace (no full-screen splash flash at login)
hl.window_rule({ match = { class = "^(teams-for-linux)$" }, workspace = "special:teams silent" })
hl.window_rule({ match = { class = "^(teams-for-linux)$" }, float = true })
hl.window_rule({ match = { class = "^(teams-for-linux)$" }, size = { 480, "(monitor_h-83)" } })
hl.window_rule({ match = { class = "^(teams-for-linux)$" }, move = { 6, 46 } })
-- Teams asks for focus while loading (focus_on_activate would pop its workspace open): ignore that, the bar button shows it
hl.window_rule({ match = { class = "^(teams-for-linux)$" }, suppress_event = "activate activatefocus" })
hl.window_rule({ match = { class = "^(teams-for-linux)$" }, no_initial_focus = true })
-- <<< teams-panel <<<
