-- >>> teams-panel >>>
-- Teams panel: Teams for Linux floated on special:teams (left, like the Git panel). Toggle from the bar button or SUPER + ALT + T; click outside to hide.
hl.bind("SUPER + ALT + T", hl.dsp.exec_cmd("~/.config/hypr/custom/teams-panel.sh"), { description = "Toggle Teams panel" })
hl.bind("mouse:272", hl.dsp.exec_cmd("~/.config/hypr/custom/teams-panel-clickaway.sh"), { non_consuming = true, description = "Teams panel: hide on outside click" })
hl.workspace_rule({ workspace = "special:teams", gaps_out = 12 })
hl.window_rule({ match = { workspace = "special:teams" }, rounding = 20 })
-- <<< teams-panel <<<
