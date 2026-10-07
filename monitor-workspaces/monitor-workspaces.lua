-- >>> monitor-workspaces >>>
-- Per-monitor workspaces: the bar's workspace count (Settings -> Bar -> Workspaces -> Shown, bar.workspaces.shown in
-- config.json) is PER MONITOR. Monitor 1 (eDP-1) owns the first group, monitor 2 (HDMI-A-2) the next, so each bar only
-- shows its own monitor's workspaces/apps (shown = 5: eDP-1 1-5, HDMI-A-2 6-10). Alone, a monitor just has its group;
-- if one is unplugged Hyprland moves its workspaces to the remaining one, after its own (scroll past the last dot).
-- The count is read when the Lua config loads (run `hyprctl reload` after changing it).
local size = 5
local f = io.open(os.getenv("HOME") .. "/.config/illogical-impulse/config.json", "r")
if f then
    local n = f:read("*a"):match('"workspaces"%s*:%s*{.-"shown"%s*:%s*(%d+)')
    f:close()
    if n then size = tonumber(n) end
end
workspaceGroupSize = math.max(1, size)
for k, name in ipairs({ "eDP-1", "HDMI-A-2" }) do
    for i = 1, workspaceGroupSize do
        hl.workspace_rule({ workspace = tostring((k - 1) * workspaceGroupSize + i), monitor = name, default = (i == 1) })
    end
end
-- <<< monitor-workspaces <<<
