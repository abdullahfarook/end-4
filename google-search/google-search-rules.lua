-- >>> google-search >>>
-- Google widget: gsearch.py (QtWebEngine) docked under the popup's search field (left side, below the bar).
local gs = { class = "^(gsearch)$" }
hl.window_rule({ match = gs, float = true })
hl.window_rule({ match = gs, workspace = "special:gsearch silent" })
hl.window_rule({ match = gs, size = { 440, "(monitor_h-119)" } })
hl.window_rule({ match = gs, move = { 5, 114 } })
hl.window_rule({ match = gs, no_initial_focus = true })
hl.window_rule({ match = gs, animation = "slide left" })
hl.window_rule({ match = gs, rounding = 8 })
hl.window_rule({ match = gs, border_size = 0 })
-- <<< google-search <<<
