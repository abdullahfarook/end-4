-- >>> super-tab-workspaces >>>
-- ALT+Tab like Windows (workspaces, most-recently-used order): tap = previous workspace, hold ALT + Tab = go further back,
-- ALT+SHIFT+Tab = forward; release ALT to close the overview. History is kept in Lua via the workspace.active event
-- (no external watcher). While the overview is open we sit in a submap so SUPER+click is not eaten by the window-move
-- bind, which lets you click workspace/window previews.
local mru, session = {}, nil

local function mru_push(id)
    if not id or id <= 0 then return end
    for i, v in ipairs(mru) do if v == id then table.remove(mru, i) break end end
    table.insert(mru, 1, id)
    mru[31] = nil
end

local seed = hl.get_active_workspace()
if seed then mru_push(seed.id) end
hl.on("workspace.active", function(ws)
    if not session and ws then mru_push(ws.id) end
end)

local function super_tab(step)
    if not session then
        local cur = hl.get_active_workspace()
        if cur then mru_push(cur.id) end
        local list = {}
        for _, id in ipairs(mru) do list[#list + 1] = id end  -- empty workspaces are included: focusing one recreates it
        session = { list = list, i = 1 }
        hl.dispatch(hl.dsp.submap("super-tab"))
    end
    local n = #session.list
    session.i = (session.i - 1 + step) % n + 1
    hl.dispatch(hl.dsp.focus({ workspace = tostring(session.list[session.i]) }))
    hl.exec_cmd("hyprctl layers | grep -q quickshell:overview || qs -c ii ipc call search open")
end

local function super_tab_release()
    if not session then return end
    session = nil
    local cur = hl.get_active_workspace()
    if cur then mru_push(cur.id) end
    hl.dispatch(hl.dsp.submap("reset"))
    hl.exec_cmd("sleep 0.15; qs -c ii ipc call search close")  -- let the shell's own release handler run first
end

hl.bind("ALT + Tab", function() super_tab(1) end, { description = "Overview: open / previous workspace (MRU)" })
hl.bind("ALT + SHIFT + Tab", function() super_tab(-1) end, { description = "Overview: workspace forward in MRU order" })
-- Also bind release globally: a quick release can land before the submap is entered. No-op without a session.
for _, k in ipairs({ "ALT_L", "ALT_R" }) do
    hl.bind(k, super_tab_release, { ignore_mods = true, transparent = true, release = true })
end
hl.define_submap("super-tab", function()
    hl.bind("ALT + Tab", function() super_tab(1) end)
    hl.bind("ALT + SHIFT + Tab", function() super_tab(-1) end)
    for _, k in ipairs({ "ALT_L", "ALT_R" }) do
        hl.bind(k, super_tab_release, { ignore_mods = true, transparent = true, release = true })
    end
end)
-- <<< super-tab-workspaces <<<
