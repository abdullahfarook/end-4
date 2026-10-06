-- >>> vscode-git >>>
-- Git panel: dedicated VS Code (Source Control + diff only) on special:vgit, opened from the bar button or SUPER + Z.
hl.bind("SUPER + Z", hl.dsp.exec_cmd("~/.config/hypr/custom/vscode-git.sh"), { description = "Toggle Git panel" })
local vg = { title = "⎇" }
hl.window_rule({ match = vg, float = true })
hl.window_rule({ match = vg, workspace = "special:vgit" })
hl.window_rule({ match = vg, size = { "(monitor_w*0.4)", "(monitor_h-80)" } })
hl.window_rule({ match = vg, move = { 12, 60 } })
hl.window_rule({ match = vg, animation = "slide left" })
hl.window_rule({ match = vg, rounding = 20 })
hl.workspace_rule({ workspace = "special:vgit", gaps_out = 12 })
hl.unbind("SUPER + Q")
hl.bind("SUPER + Q", hl.dsp.exec_cmd("~/.config/hypr/custom/vscode-git-close.sh"), { description = "Window: Close (hides the Git panel instead)" })
hl.bind("mouse:272", hl.dsp.exec_cmd("~/.config/hypr/custom/vscode-git-clickaway.sh"), { non_consuming = true, description = "Git panel: close on outside click" })
-- <<< vscode-git <<<
