-- >>> console-sidebar >>>
-- Left console panel: a plain kitty shell docked like the AI sidebar (SUPER + `).
hl.bind("SUPER + grave", hl.dsp.exec_cmd("~/.config/hypr/custom/console-sidebar.sh"), { description = "Shell: Toggle left console panel" })
hl.window_rule({ match = { class = "^(console-sidebar)$" }, float = true })
hl.window_rule({ match = { class = "^(console-sidebar)$" }, workspace = "special:console" })
hl.window_rule({ match = { class = "^(console-sidebar)$" }, size = { "(monitor_w*0.3)", "(monitor_h-80)" } })
hl.window_rule({ match = { class = "^(console-sidebar)$" }, move = { 12, 60 } })
hl.window_rule({ match = { class = "^(console-sidebar)$" }, animation = "slide left" })
hl.window_rule({ match = { class = "^(console-sidebar)$" }, rounding = 20 })
hl.workspace_rule({ workspace = "special:console", gaps_out = 12 })
hl.bind("mouse:272", hl.dsp.exec_cmd("~/.config/hypr/custom/console-sidebar.sh clickaway"), { non_consuming = true, description = "Console panel: close on outside click" })
-- <<< console-sidebar <<<
