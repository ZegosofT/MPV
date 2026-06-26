-- [[
--    auto_anime_preset.lua
--    Per-folder auto-apply of a Zego preset.
--
--    On every file, it looks up the file's folder in the rule table
--    (~~/preset_folders.json, managed by the Options GUI) and:
--      * a folder matches  -> applies that preset (built-in or user-made),
--        with the most SPECIFIC (longest) folder winning for nested rules;
--      * no folder matches -> "raw": master shaders OFF, no enhancement
--        (mpv plays the video plain, like a normal player).
--
--    It only drives the existing controller (anime_profile_controller), so the
--    upscaling logic itself is never touched. Manual overrides via the "<" menu
--    still work for the current file; the rule is re-applied on the next file.
-- ]]

local mp    = require 'mp'
local utils = require 'mp.utils'

local RULES_PATH = mp.command_native({ "expand-path", "~~/preset_folders.json" })

local function load_rules()
    local f = io.open(RULES_PATH, "r")
    if not f then return {} end
    local data = utils.parse_json(f:read("*a"))
    f:close()
    return (type(data) == "table") and data or {}
end

-- Normalize for comparison: lowercase, forward slashes, no trailing slash.
local function norm(p)
    return (p or ""):lower():gsub("\\", "/"):gsub("/+$", "")
end

-- The preset whose folder is the longest prefix of `path`, or nil.
local function best_preset_for(path)
    if not path or path == "" or path:find("://") then return nil end
    local p = norm(path)
    local best, best_len = nil, -1
    for _, rule in ipairs(load_rules()) do
        local folder = norm(rule.folder)
        if folder ~= "" and #folder > best_len then
            if p == folder or p:sub(1, #folder + 1) == folder .. "/" then
                best, best_len = rule.preset, #folder
            end
        end
    end
    return best
end

local function auto_apply()
    local preset = best_preset_for(mp.get_property("path", ""))
    if preset and preset ~= "" then
        mp.commandv("script-message-to", "anime_profile_controller", "zego-folder-apply", preset)
    else
        mp.commandv("script-message-to", "anime_profile_controller", "zego-folder-raw")
    end
end

-- Delay slightly so the controller's own file-loaded handlers finish first,
-- then we set the per-folder state on top. 300 ms is invisible but wins the race.
mp.register_event("file-loaded", function()
    mp.add_timeout(0.3, auto_apply)
end)
