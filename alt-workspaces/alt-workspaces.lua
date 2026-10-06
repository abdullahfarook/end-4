-- >>> alt-workspaces >>>
-- ALT + 1..9, 0 focus workspace 1..10 (within the current workspace group), except while Zen Browser is focused:
-- the binds are switched off then, so ALT + number reaches Zen's own tab shortcuts.
local alt_ws = {}
for i = 1, 10 do
    local focus = function() hl.dispatch(hl.dsp.focus({ workspace = workspace_in_group(i) })) end
    local desc = { description = "Workspace: Focus " .. i .. " (ALT)" }
    table.insert(alt_ws, hl.bind("ALT + " .. (i % 10), focus, desc))
    table.insert(alt_ws, hl.bind("ALT + code:" .. (9 + i), focus))  -- raw keycodes: layout-independent
end
local function alt_ws_update()
    local w = hl.get_active_window()
    local zen = w ~= nil and w.class ~= nil and w.class:lower():find("zen", 1, true) ~= nil
    for _, b in ipairs(alt_ws) do b:set_enabled(not zen) end
end
hl.on("window.active", alt_ws_update)
alt_ws_update()
-- <<< alt-workspaces <<<
