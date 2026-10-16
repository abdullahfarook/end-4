-- >>> panel-anim >>>
-- Left panels that are real windows on special workspaces (AI / Git / Console / Teams): swipe in and out from the left edge
-- with the same curves and speeds as the shell's layer panels (layersIn/layersOut), like the right sidebar.
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 2.7, bezier = "emphasizedDecel", style = "slide left" })
-- Out is mirrored by Hyprland, so "slide right" makes the close go back to the left edge
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2.4, bezier = "menu_accel",      style = "slide right" })
-- Fades like the layers too (no fade while sliding in, opaque until the end of the slide out). Global: also applies to normal windows.
hl.animation({ leaf = "fadeIn",  enabled = true, speed = 0.5, bezier = "menu_decel" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 2.7, bezier = "stall" })
hl.window_rule({ match = { class = "^(teams-for-linux)$" }, animation = "slide left" })
-- <<< panel-anim <<<
