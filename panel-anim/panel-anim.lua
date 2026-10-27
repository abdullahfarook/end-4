-- >>> panel-anim >>>
-- One animation for every left panel, open, close and switch alike: the shell panels (layers, WidgetBase.qml) and the
-- window panels (AI / Git / Console / Teams on special workspaces). Slide in from the left edge and back out to it,
-- the close the exact mirror of the open (same duration, mirrored curve), no lingering fade.
hl.curve("panelIn",  { type = "bezier", points = {{0.2, 0.8}, {0.3, 1}} })   -- decelerate
hl.curve("panelOut", { type = "bezier", points = {{0.7, 0}, {0.8, 0.2}} })   -- its mirror: accelerate
-- Window panels: their special workspace ("slide right" for out is mirrored by Hyprland: back to the left edge)
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 2.5, bezier = "panelIn",  style = "slide left" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2.5, bezier = "panelOut", style = "slide right" })
-- Shell panels: layers (Hyprland has no per-layer timing, so these apply to every layer; panels get "slide left" from rules.lua)
hl.animation({ leaf = "layersIn",  enabled = true, speed = 2.5, bezier = "panelIn",  style = "popin 93%" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2.5, bezier = "panelOut", style = "popin 94%" })
-- Fades: quick and symmetric (the slow "stall" fade-out left a translucent ghost while the panel slid away)
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.5, bezier = "panelIn" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.5, bezier = "panelOut" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.5, bezier = "panelIn" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 2.5, bezier = "panelOut" })
hl.window_rule({ match = { class = "^(teams-for-linux)$" }, animation = "slide left" })
-- <<< panel-anim <<<
