-- >>> side-panel >>>
-- Shared behavior of the window panels (AI, Console, Teams, Git): one click-away handler and one event watcher for all.
hl.bind("mouse:272", hl.dsp.exec_cmd("~/.config/hypr/custom/side-panel.sh clickaway"), { non_consuming = true, description = "Side panels: close on outside click (same monitor only)" })
hl.on("hyprland.start", function () hl.exec_cmd("~/.config/hypr/custom/side-panel.sh watch") end)
-- <<< side-panel <<<
