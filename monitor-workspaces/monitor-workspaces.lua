-- >>> monitor-workspaces >>>
-- Per-monitor workspaces: the bar shows 8 dots (a "group"). Group 0 (1-8) lives on eDP-1, group 1 (9-16) on HDMI-A-2,
-- so each bar only shows its own monitor's workspaces/apps. If a monitor is unplugged Hyprland moves its workspaces to
-- the remaining one, where they appear after its own (scroll past the last dot); replugging sends them back.
workspaceGroupSize = 8  -- must match config bar.workspaces.shown
local ws_monitors = { { "eDP-1", 0 }, { "HDMI-A-2", 1 } }
for _, m in ipairs(ws_monitors) do
    for i = 1, workspaceGroupSize do
        hl.workspace_rule({ workspace = tostring(m[2] * workspaceGroupSize + i), monitor = m[1], default = (i == 1) })
    end
end
-- <<< monitor-workspaces <<<
