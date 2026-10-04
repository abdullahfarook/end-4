-- >>> ai-sidebar >>>
-- Left AI sidebar: native shell panel, or a kitty window with Claude Code / Codex (Settings -> Services -> AI).
for _, key in ipairs({ "A", "B", "O" }) do
    hl.unbind("SUPER + " .. key)
    hl.bind("SUPER + " .. key, hl.dsp.exec_cmd("~/.config/hypr/custom/ai-sidebar.sh"), { description = "Shell: Toggle left sidebar / AI terminal" })
end
hl.window_rule({ match = { class = "^(ai-sidebar)$" }, float = true })
hl.window_rule({ match = { class = "^(ai-sidebar)$" }, workspace = "special:ai" })
hl.window_rule({ match = { class = "^(ai-sidebar)$" }, size = { "(monitor_w*0.3)", "(monitor_h-80)" } })
hl.window_rule({ match = { class = "^(ai-sidebar)$" }, move = { 12, 60 } })
-- <<< ai-sidebar <<<
