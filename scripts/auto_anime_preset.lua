-- Auto-apply the "Anime 1440P+" custom preset when the loaded file lives
-- inside a folder literally named "anime" (case-insensitive, slash or
-- backslash). Otherwise switch the preset back to "Off".
--
-- Hooks into the existing anime_profile_controller's custom-preset bindings,
-- so manual overrides from the UOSC menu still work mid-playback — they're
-- just re-evaluated whenever the next file loads.

local mp = require 'mp'

local PRESET_ON_BIND  = "anime_profile_controller/zego-custom-anime-1440p"
local PRESET_OFF_BIND = "anime_profile_controller/zego-custom-off"

local function is_in_anime_folder(path)
    if not path or path == "" then return false end
    -- Matches \anime\ or /anime/ anywhere in the path, case-insensitive.
    return path:lower():find("[\\/]anime[\\/]") ~= nil
end

local function auto_apply()
    local path = mp.get_property("path", "")
    if is_in_anime_folder(path) then
        mp.commandv("script-binding", PRESET_ON_BIND)
    else
        mp.commandv("script-binding", PRESET_OFF_BIND)
    end
end

-- Delay slightly so the main controller's own file-loaded handlers finish
-- before we layer the custom preset on top. 300 ms is invisible to the
-- user but enough to win the race.
mp.register_event("file-loaded", function()
    mp.add_timeout(0.3, auto_apply)
end)
