-- >>> google-search >>>
-- Google widget: gsearch.qml (QtWebEngine via qml6) docked under the popup's search field (left side, below the bar).
local gs = { title = "^(gsearch)$" }
hl.window_rule({ match = gs, float = true })
hl.window_rule({ match = gs, workspace = "special:gsearch silent" })
hl.window_rule({ match = gs, size = { 440, "(monitor_h-119)" } })
hl.window_rule({ match = gs, move = { 5, 86 } })
hl.window_rule({ match = gs, no_initial_focus = true })
hl.window_rule({ match = gs, animation = "slide left" })
hl.window_rule({ match = gs, rounding = 8 })
hl.window_rule({ match = gs, border_size = 0 })
-- Pulled-out video (mpv): small floating always-on-top window, bottom-right
local pip = { title = "^(gsearch-pip)$" }
hl.window_rule({ match = pip, float = true })
hl.window_rule({ match = pip, pin = true })
hl.window_rule({ match = pip, size = { 480, 270 } })
hl.window_rule({ match = pip, move = { "(monitor_w-500)", "(monitor_h-290)" } })
hl.window_rule({ match = pip, keep_aspect_ratio = true })
-- <<< google-search <<<
