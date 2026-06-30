-- ASS subtitle style manager via sub-ass-style-overrides.
-- With sub-ass-override=yes, mpv's sub-font / sub-font-size / sub-color do NOT
-- apply to ASS subs (they keep the script's styling). This injects FontName /
-- FontSize / PrimaryColour / OutlineColour / BackColour so the configured font,
-- size & colors (set in the Options GUI) actually take effect, while preserving
-- other overrides (blur) and letting Alt+S resize live.

local mp = require 'mp'

-- Master switch (script-opts/sub_scale.conf: force_style=yes|no). When off, ASS
-- subtitles keep their own font/size/colors (only manual Alt+S still overrides).
local opts = { force_style = true }
require('mp.options').read_options(opts, 'sub_scale')

local STEP     = 2     -- pixels per press
local MIN_SIZE = 4     -- floor

-- Current overrides. nil = not seeded yet (seeded on load).
local size = nil
local font = nil
local pri, outc, shad = nil, nil, nil   -- ASS PrimaryColour / OutlineColour / BackColour

-- mpv "#AARRGGBB" (or "#RRGGBB") -> ASS "&HAABBGGRR" (alpha inverted, RGB reversed).
local function to_ass_color(c)
    if not c or c == "" then return nil end
    local hex = c:gsub("#", ""):upper()
    local aa, rr, gg, bb
    if #hex == 8 then
        aa, rr, gg, bb = hex:sub(1, 2), hex:sub(3, 4), hex:sub(5, 6), hex:sub(7, 8)
    elseif #hex == 6 then
        aa, rr, gg, bb = "FF", hex:sub(1, 2), hex:sub(3, 4), hex:sub(5, 6)
    else
        return nil
    end
    return "&H" .. string.format("%02X", 255 - tonumber(aa, 16)) .. bb .. gg .. rr
end

-- ASS style fields we manage via sub-ass-style-overrides.
local MANAGED = { "FontSize", "FontName", "PrimaryColour", "OutlineColour", "BackColour" }

-- Rebuild sub-ass-style-overrides, replacing any FontSize= entry with our value.
local function apply()
    local overrides = mp.get_property_native("sub-ass-style-overrides", {}) or {}
    local kept = {}
    for _, entry in ipairs(overrides) do
        -- Drop the entries WE manage; keep the rest (blur, etc.).
        local mine = false
        for _, m in ipairs(MANAGED) do
            if entry:match("^%s*" .. m .. "%s*=") then mine = true; break end
        end
        if not mine then kept[#kept + 1] = entry end
    end
    if size then kept[#kept + 1] = "FontSize=" .. tostring(size) end
    if font and font ~= "" then kept[#kept + 1] = "FontName=" .. font end
    if pri  then kept[#kept + 1] = "PrimaryColour=" .. pri end
    if outc then kept[#kept + 1] = "OutlineColour=" .. outc end
    if shad then kept[#kept + 1] = "BackColour=" .. shad end
    mp.set_property_native("sub-ass-style-overrides", kept)
end

local function bump(delta)
    if size == nil then
        -- Seed from current mpv sub-font-size so the first press starts from a sane value.
        size = mp.get_property_number("sub-font-size", 36)
    end
    size = math.max(MIN_SIZE, size + delta)
    apply()
    mp.osd_message("Sub size: " .. size, 1.5)
end

local function reset()
    size, font = nil, nil
    pri, outc, shad = nil, nil, nil
    apply()
    mp.osd_message("Sub style: default", 1.5)
end

mp.add_key_binding(nil, "scale-up",    function() bump( STEP) end)
mp.add_key_binding(nil, "scale-down",  function() bump(-STEP) end)
mp.add_key_binding(nil, "scale-reset", reset)

-- Apply the configured default size to ASS subtitles on every file. ASS subs
-- ignore mpv's `sub-font-size`, so without this the Options "Subtitle size"
-- (which writes sub-font-size) would have no visible effect. Manual Alt+S tweaks
-- still persist across files once set; a Ctrl+R reload re-seeds from the new
-- configured value.
mp.register_event("file-loaded", function()
    if not opts.force_style then return end   -- keep each subtitle's own styling
    if size == nil then
        size = mp.get_property_number("sub-font-size", 36)
    end
    if font == nil then
        font = mp.get_property("sub-font", "")
    end
    if pri  == nil then pri  = to_ass_color(mp.get_property("sub-color")) end
    if outc == nil then outc = to_ass_color(mp.get_property("sub-border-color")) end
    if shad == nil then shad = to_ass_color(mp.get_property("sub-shadow-color")) end
    apply()
end)
