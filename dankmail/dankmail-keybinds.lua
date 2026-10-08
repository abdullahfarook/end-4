-- >>> dankmail >>>
-- dankmail triage window (mail). Toggle from the bar button or SUPER + CTRL + M. Needs `systemctl --user enable --now dmail`.
hl.bind("SUPER + CTRL + M", hl.dsp.exec_cmd("~/.config/hypr/custom/dankmail-toggle.sh"), { description = "Toggle mail triage (dankmail)" })
-- The user manager here has no graphical-session.target, so the unit never autostarts: start the daemon with the session.
hl.on("hyprland.start", function () hl.exec_cmd("systemctl --user start dmail") end)
-- <<< dankmail <<<
