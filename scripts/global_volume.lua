-- [[
--    global_volume.lua
--    Makes the master volume (and mute) GLOBAL and PERSISTENT.
--
--    * Nothing ties the volume to a file or folder: it is removed from
--      watch-later-options in mpv.conf, so mpv never restores a per-file level.
--    * The level you set is remembered across files AND across mpv restarts,
--      stored in ~~/volume_state.json.
--
--    The remembered level is re-applied on every file-loaded, so it also wins
--    over per-file resets (e.g. reset-on-next-file in the Audio-Only profile).
-- ]]

local mp    = require 'mp'
local utils = require 'mp.utils'
local msg   = require 'mp.msg'

local STORE = mp.command_native({ "expand-path", "~~/volume_state.json" })

local saved = { volume = nil, mute = nil }  -- the global level we enforce
local ready = false                         -- true once we've applied at least once
local save_timer = nil

-- ----------------------------------------------------------------
-- Persistence
-- ----------------------------------------------------------------
local function load()
    local f = io.open(STORE, "r")
    if not f then return end
    local data = utils.parse_json(f:read("*a"))
    f:close()
    if type(data) == "table" then
        if type(data.volume) == "number"  then saved.volume = data.volume end
        if type(data.mute)   == "boolean" then saved.mute   = data.mute   end
    end
end

local function write()
    local f = io.open(STORE, "w")
    if not f then msg.error("cannot write " .. STORE); return end
    f:write(utils.format_json(saved) or "{}")
    f:close()
end

-- Capture the live values (called at fire time, so it always records the
-- latest even if it was scheduled mid-reset) and persist them.
local function commit()
    saved.volume = mp.get_property_number("volume") or saved.volume
    local m = mp.get_property_bool("mute")
    if m ~= nil then saved.mute = m end
    write()
end

-- ----------------------------------------------------------------
-- Apply / observe
-- ----------------------------------------------------------------
-- Enforce the remembered level. Runs on every file-loaded so it survives any
-- per-file reset and keeps the volume identical everywhere.
local function apply()
    if saved.volume then mp.set_property_number("volume", saved.volume) end
    if saved.mute ~= nil then mp.set_property_bool("mute", saved.mute) end
    ready = true
end

-- Debounced save so dragging the slider doesn't hammer the disk.
local function schedule_save()
    if not ready then return end   -- ignore the initial property fire at load
    if save_timer then save_timer:kill() end
    save_timer = mp.add_timeout(0.4, commit)
end

load()
mp.register_event("file-loaded", apply)
mp.register_event("shutdown", function() if ready then commit() end end)
mp.observe_property("volume", "number", schedule_save)
mp.observe_property("mute",   "bool",   schedule_save)
