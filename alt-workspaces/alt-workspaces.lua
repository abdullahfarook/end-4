-- >>> alt-workspaces >>>
-- ALT + 1..9, 0 focus workspace 1..10 (within the current workspace group), except while Zen Browser is focused:
-- the binds are switched off then, so ALT + number reaches Zen's own tab shortcuts.
-- Exception: if Zen only got focus because ALT + number landed on its workspace, the binds stay on ("grace")
-- for 1.5 s after the last ALT + number press (so you can keep stepping through workspaces); after that, a focused Zen
-- gets its own ALT + number shortcuts again.
local alt_ws = {}
local alt_ws_update
local grace, gen = false, 0
for i = 1, 10 do
    local focus = function()
        grace, gen = true, gen + 1
        local mine = gen
        hl.timer(function() if gen == mine then grace = false alt_ws_update() end end, { timeout = 1500, type = "oneshot" })
        hl.dispatch(hl.dsp.focus({ workspace = workspace_in_group(i) }))
    end
    local desc = { description = "Workspace: Focus " .. i .. " (ALT)" }
    table.insert(alt_ws, hl.bind("ALT + " .. (i % 10), focus, desc))
    table.insert(alt_ws, hl.bind("ALT + code:" .. (9 + i), focus))  -- raw keycodes: layout-independent
end
alt_ws_update = function()
    local w = hl.get_active_window()
    local zen = w ~= nil and w.class ~= nil and w.class:lower():find("zen", 1, true) ~= nil
    for _, b in ipairs(alt_ws) do b:set_enabled(grace or not zen) end
end
hl.on("window.active", alt_ws_update)
alt_ws_update()
-- <<< alt-workspaces <<<
