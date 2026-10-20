-- Right-click opens a small menu (Upscaler / Sources / Smoother motion / Clean up compression damage / Load subtitles / Fullscreen / Exit); "Upscaler" opens the full list (type to filter, Up/Down, Enter). `u` opens the list directly,
-- Ctrl+u / Ctrl+Shift+u cycle. Switches at runtime, no restart.
-- Shaders live in <config dir>/shaders (see fetch-shaders.sh). Hooks only run when they actually upscale (output larger than the video).
local mp = require 'mp'
local dir = mp.command_native({"expand-path", "~~/shaders/"})

local K = "KrigBilateral.glsl"
local presets = {
    {"Off (built-in Lanczos)", {}},
    {"Chroma only: KrigBilateral", {K}},
    {"FSR (fast, sharp)", {"FSR.glsl"}},
    {"NVIDIA Image Scaling (NVScaler)", {"NVScaler.glsl"}},
    {"NVScaler + NVSharpen", {"NVScaler.glsl", "NVSharpen.glsl"}},
    {"AMD CAS (sharpen)", {"CAS-scaled.glsl"}},
    {"RAVU Lite r4", {"ravu-lite-r4.hook"}},
    {"RAVU r4", {"ravu-r4.hook"}},
    {"RAVU Zoom r3 (heavy)", {"ravu-zoom-r3.hook"}},
    {"FSRCNNX 8-0-4-1 (live action)", {"FSRCNNX_x2_8-0-4-1.glsl"}},
    {"FSRCNNX 16-0-4-1 (live action, heavy)", {"FSRCNNX_x2_16-0-4-1.glsl"}},
    {"ArtCNN C4F16 (live action)", {"ArtCNN_C4F16.glsl"}},
    {"ArtCNN C4F32 (live action, heavy)", {"ArtCNN_C4F32.glsl"}},
    {"ArtCNN C4F16 denoise+sharpen", {"ArtCNN_C4F16_DS.glsl"}},
    {"ArtCNN C4F32 denoise+sharpen", {"ArtCNN_C4F32_DS.glsl"}},
    {"nnedi3 64", {"nnedi3-nns64-win8x6.hook"}},
    {"nnedi3 256 (heavy)", {"nnedi3-nns256-win8x6.hook"}},
    {"Anime4K S", {"Anime4K_Upscale_CNN_x2_S.glsl"}},
    {"Anime4K M", {"Anime4K_Upscale_CNN_x2_M.glsl"}},
    {"Anime4K L", {"Anime4K_Upscale_CNN_x2_L.glsl"}},
    {"Anime4K VL (heavy)", {"Anime4K_Upscale_CNN_x2_VL.glsl"}},
    {"Anime4K UL (heaviest)", {"Anime4K_Upscale_CNN_x2_UL.glsl"}},
    {"Anime4K M + denoise", {"Anime4K_Upscale_Denoise_CNN_x2_M.glsl"}},
    {"Anime4K DoG", {"Anime4K_Upscale_DoG_x2.glsl"}},
    {"Best live action: FSRCNNX 16 + SSimSuperRes + Krig", {"FSRCNNX_x2_16-0-4-1.glsl", "SSimSuperRes.glsl", K}},
    {"Best live action: ArtCNN C4F32 + Krig", {"ArtCNN_C4F32.glsl", K}},
    {"RAVU Lite + SSimSuperRes + Krig", {"ravu-lite-r4.hook", "SSimSuperRes.glsl", K}},
}
local cur = 1

local function apply(i)
    cur = i
    local list = {}
    for _, f in ipairs(presets[i][2]) do list[#list + 1] = dir .. f end
    mp.set_property_native("glsl-shaders", list)
    -- say whether the shaders can act: they only run when the picture is enlarged (>= ~1.2x), never at 1:1 or when shrinking
    local vp, od = mp.get_property_native("video-params"), mp.get_property_native("osd-dimensions")
    local note = ""
    if vp and vp.w and od and od.w and #list > 0 then
        local scale = (od.w - od.ml - od.mr) / vp.w
        note = string.format("\nvideo %dx%d shown at x%.2f: %s", vp.w, vp.h, scale,
            scale >= 1.2 and "shader active" or "shader idle (picture is not enlarged: make the window bigger or go fullscreen)")
    end
    mp.osd_message("Upscaler: " .. presets[i][1] .. note, 4)
end

local function open()
    local items = {}
    for i, p in ipairs(presets) do items[i] = (i == cur and "● " or "   ") .. p[1] end
    local ok, input = pcall(require, 'mp.input')
    if ok and input.select then
        input.select({prompt = "Upscaler:", items = items, default_item = cur, submit = function(n) apply(n) end})
    else
        apply(cur % #presets + 1)  -- no picker in this mpv: just cycle
    end
end

mp.add_key_binding(nil, "open", open)
mp.add_key_binding(nil, "next", function() apply(cur % #presets + 1) end)
mp.add_key_binding(nil, "prev", function() apply((cur - 2) % #presets + 1) end)
mp.register_script_message("set", function(n) apply(tonumber(n)) end)  -- for tests: script-message-to upscale_menu set <n>

-- Subtitles from a file: KDE file dialog, then sub-add (also works by dropping a .srt/.ass/.vtt onto the window)
local function load_subs()
    mp.command_native_async({name = "subprocess", capture_stdout = true, playback_only = false,
        args = {"kdialog", "--title", "Load subtitles", "--getopenfilename", os.getenv("HOME"),
                "*.srt *.ass *.ssa *.vtt *.sub *.sup|Subtitles"}},
        function(ok, res)
            local path = ok and res and res.status == 0 and (res.stdout or ""):gsub("%s+$", "") or ""
            if path ~= "" then
                mp.commandv("sub-add", path, "select")
                mp.osd_message("Subtitles: " .. path:match("[^/]+$"), 3)
            end
        end)
end

-- Sources: the streams the browser extension detected (best one already playing); pick another to switch, keeping the position
local sources, current_src = {}, nil
do
    local path = mp.get_opt("zenmpv-sources")
    if path and path ~= "" then
        local f = io.open(path, "r")
        if f then
            local d = require('mp.utils').parse_json(f:read("*a")); f:close()
            if d and d.sources then sources, current_src = d.sources, d.current end
        end
    end
end

local function source_label(i, src)
    local host = src.url:match("^https?://([^/]+)") or "?"
    local tail = (src.url:match("([^/?#]+)[^/]*$") or ""):sub(1, 30)
    local q = src.url:match("(%d%d%d%d?)[pP]") or src.url:match("[_/%-](%d%d%d%d?)[_/%.]")
    return string.format("%s %d. [%s%s] %s / %s", src.url == current_src and "●" or "  ", i, src.kind or "?", q and (" " .. q .. "p") or "", host:sub(1, 28), tail)
end

local switching, prev_src = false, nil

local function load_source(src, pos)
    mp.set_property("referrer", src.referer or "")
    mp.set_property("http-header-fields", (src.origin and src.origin ~= "") and ("Origin: " .. src.origin) or "")
    current_src = src.url
    mp.commandv("loadfile", src.url, "replace", "-1", string.format("start=%.1f,ytdl=no", pos))
end

-- A source that cannot be opened must not close the window: stay idle during the switch and fall back to the previous source
mp.register_event("file-loaded", function()
    if switching then switching = false; mp.set_property("idle", "no") end
end)
mp.register_event("end-file", function(ev)
    if switching and ev.reason == "error" and prev_src then
        local back = prev_src
        switching, prev_src = false, nil
        mp.osd_message("That source could not be opened: back to the previous one", 4)
        mp.add_timeout(0.2, function() load_source(back.src, back.pos); mp.set_property("idle", "no") end)
    end
end)

local function pick_source()
    local ok, input = pcall(require, 'mp.input')
    if not (ok and input.select) or #sources == 0 then return end
    local items, def = {}, 1
    for i, src in ipairs(sources) do items[i] = source_label(i, src); if src.url == current_src then def = i end end
    input.select({prompt = "Sources:", items = items, default_item = def, submit = function(n)
        local src = sources[n]
        if not src or src.url == current_src then return end
        local pos = mp.get_property_number("time-pos") or 0
        local before
        for _, c in ipairs(sources) do if c.url == current_src then before = c end end
        prev_src = before and {src = before, pos = pos} or nil
        switching = true
        mp.set_property("idle", "yes")
        load_source(src, pos)
        mp.osd_message("Source " .. n .. "/" .. #sources, 2.5)
    end})
end

-- Toggles (per window): smoother motion = frame interpolation, compression cleanup = debanding
local function smooth_on() return mp.get_property_native("interpolation") == true end
local function deband_on() return mp.get_property_native("deband") == true end

local function toggle_smooth()
    if smooth_on() then
        mp.set_property("interpolation", "no"); mp.set_property("video-sync", "audio")
    else  -- needs display-resample sync; oversample blends frames without ghosting
        mp.set_property("video-sync", "display-resample"); mp.set_property("tscale", "oversample"); mp.set_property("interpolation", "yes")
    end
    mp.osd_message("Smoother motion: " .. (smooth_on() and "on" or "off"), 2.5)
end

local function toggle_deband()
    mp.set_property("deband", deband_on() and "no" or "yes")
    mp.osd_message("Clean up compression damage: " .. (deband_on() and "on" or "off"), 2.5)
end

-- Right-click menu: Upscaler (opens the list above) / Exit
local function context()
    local ok, input = pcall(require, 'mp.input')
    if not (ok and input.select) then return open() end
    local menu_items, menu_actions = {"Upscaler"}, {"upscaler"}
    if #sources > 0 then menu_items[#menu_items + 1] = "Sources (" .. #sources .. ")..."; menu_actions[#menu_actions + 1] = "sources" end
    menu_items[#menu_items + 1] = "Smoother motion: " .. (smooth_on() and "ON" or "off"); menu_actions[#menu_actions + 1] = "smooth"
    menu_items[#menu_items + 1] = "Clean up compression damage: " .. (deband_on() and "ON" or "off"); menu_actions[#menu_actions + 1] = "deband"
    for _, e in ipairs({{"Load subtitles...", "subs"}, {"Fullscreen", "fullscreen"}, {"Exit", "exit"}}) do
        menu_items[#menu_items + 1] = e[1]; menu_actions[#menu_actions + 1] = e[2]
    end
    input.select({
        prompt = "Menu:",
        items = menu_items,
        submit = function(n)  -- delay: the menu closes itself after submit
            local what = menu_actions[n]
            if what == "upscaler" then mp.add_timeout(0.15, open)
            elseif what == "sources" then mp.add_timeout(0.15, pick_source)
            elseif what == "smooth" then mp.add_timeout(0.15, toggle_smooth)
            elseif what == "deband" then mp.add_timeout(0.15, toggle_deband)
            elseif what == "subs" then mp.add_timeout(0.15, load_subs)
            elseif what == "fullscreen" then mp.add_timeout(0.15, function() mp.commandv("cycle", "fullscreen") end)
            else mp.commandv("quit") end
        end,
    })
end
mp.add_key_binding(nil, "context", context)
