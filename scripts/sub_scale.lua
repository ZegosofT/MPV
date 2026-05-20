-- Dynamic ASS subtitle scaling via sub-ass-style-overrides.
-- Keeps your custom sub-font / sub-color (sub-ass-override=yes) AND lets
-- you resize subtitles on the fly. Other sub-ass-style-overrides entries
-- (like blur=1) are preserved.

local mp = require 'mp'

local STEP     = 2     -- pixels per press
local MIN_SIZE = 4     -- floor

-- Current target FontSize. nil = no override (use defaults).
local size = nil

-- Rebuild sub-ass-style-overrides, replacing any FontSize= entry with our value.
local function apply()
    local overrides = mp.get_property_native("sub-ass-style-overrides", {}) or {}
    local kept = {}
    for _, entry in ipairs(overrides) do
        if not entry:match("^%s*FontSize%s*=") then
            kept[#kept + 1] = entry
        end
    end
    if size then
        kept[#kept + 1] = "FontSize=" .. tostring(size)
    end
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
    size = nil
    apply()
    mp.osd_message("Sub size: default", 1.5)
end

mp.add_key_binding(nil, "scale-up",    function() bump( STEP) end)
mp.add_key_binding(nil, "scale-down",  function() bump(-STEP) end)
mp.add_key_binding(nil, "scale-reset", reset)
