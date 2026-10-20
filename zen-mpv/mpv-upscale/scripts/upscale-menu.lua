-- Right-click opens a small menu (Upscaler / Exit); "Upscaler" opens the full list (type to filter, Up/Down, Enter). `u` opens the list directly,
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
    mp.osd_message("Upscaler: " .. presets[i][1], 2.5)
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

-- Right-click menu: Upscaler (opens the list above) / Exit
local function context()
    local ok, input = pcall(require, 'mp.input')
    if not (ok and input.select) then return open() end
    input.select({
        prompt = "Menu:",
        items = {"Upscaler", "Exit"},
        submit = function(n)
            if n == 1 then mp.add_timeout(0.15, open) else mp.commandv("quit") end  -- delay: the menu closes itself after submit
        end,
    })
end
mp.add_key_binding(nil, "context", context)
