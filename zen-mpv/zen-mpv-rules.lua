-- >>> zen-mpv >>>
-- mpv started from Zen by ff2mpv ("Open in mpv"): small floating window, bottom-right (not pinned, so fullscreen works)
local zm = { title = "^(zen-mpv)$" }
hl.window_rule({ match = zm, float = true })
hl.window_rule({ match = zm, size = { 640, 360 } })
hl.window_rule({ match = zm, move = { "(monitor_w-660)", "(monitor_h-380)" } })
hl.window_rule({ match = zm, keep_aspect_ratio = true })
-- <<< zen-mpv <<<
