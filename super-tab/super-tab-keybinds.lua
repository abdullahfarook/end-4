-- >>> super-tab-workspaces >>>
-- ALT+Tab: every press goes to the next workspace and shows the overview; release ALT to close it.
-- While the overview is open we sit in a submap so SUPER+click is not eaten by the window-move bind,
-- which lets you click workspace/window previews.
hl.bind("ALT + Tab", hl.dsp.exec_cmd("~/.config/hypr/custom/super-tab.sh"), { description = "Overview: open / next workspace" })
-- Also bind release globally: a quick release can land before the submap is entered. The script is a no-op without the flag.
for _, k in ipairs({ "ALT_L", "ALT_R" }) do
    hl.bind(k, hl.dsp.exec_cmd("~/.config/hypr/custom/super-tab-release.sh"), { ignore_mods = true, transparent = true, release = true })
end
hl.define_submap("super-tab", function()
    hl.bind("ALT + Tab", hl.dsp.exec_cmd("~/.config/hypr/custom/super-tab.sh"))
    hl.bind("ALT_L", hl.dsp.exec_cmd("~/.config/hypr/custom/super-tab-release.sh"), { ignore_mods = true, transparent = true, release = true })
    hl.bind("ALT_R", hl.dsp.exec_cmd("~/.config/hypr/custom/super-tab-release.sh"), { ignore_mods = true, transparent = true, release = true })
end)
-- <<< super-tab-workspaces <<<
