-- >>> dankmail >>>
-- dankmail triage window (mail). Toggle from the bar button or SUPER + CTRL + M. Needs `systemctl --user enable --now dmail`.
hl.bind("SUPER + CTRL + M", hl.dsp.exec_cmd("dmail toggle"), { description = "Toggle mail triage (dankmail)" })
-- <<< dankmail <<<
