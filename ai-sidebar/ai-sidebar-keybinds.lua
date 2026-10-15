-- >>> ai-sidebar >>>
-- Left AI sidebar: native shell panel, or a kitty window with Claude Code / Codex (Settings -> Services -> AI).
for _, key in ipairs({ "A", "B", "O" }) do
    hl.unbind("SUPER + " .. key)
    hl.bind("SUPER + " .. key, hl.dsp.exec_cmd("~/.config/hypr/custom/ai-sidebar.sh"), { description = "Shell: Toggle left sidebar / AI terminal" })
end
hl.window_rule({ match = { class = "^(ai-sidebar)$" }, float = true })
hl.window_rule({ match = { class = "^(ai-sidebar)$" }, workspace = "special:ai" })
hl.window_rule({ match = { class = "^(ai-sidebar)$" }, size = { 440, "(monitor_h-50)" } })
hl.window_rule({ match = { class = "^(ai-sidebar)$" }, move = { 5, 45 } })
hl.window_rule({ match = { class = "^(ai-sidebar)$" }, animation = "slide left" })
hl.window_rule({ match = { class = "^(ai-sidebar)$" }, rounding = 17, rounding_power = 2 })
-- Slide in from the left edge like the shell sidebar (special workspaces otherwise use the global slidevert)
hl.workspace_rule({ workspace = "special:ai", gaps_out = 12 })
hl.bind("mouse:272", hl.dsp.exec_cmd("~/.config/hypr/custom/ai-sidebar-clickaway.sh"), { non_consuming = true, description = "AI panel: close on outside click" })
-- <<< ai-sidebar <<<
