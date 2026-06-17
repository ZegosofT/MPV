-- [[
--    folder_track_memory.lua
--    Remembers the audio + subtitle of a series, PER FOLDER, and re-applies it
--    on every other episode in that same folder.
--
--    On the FIRST episode you open in a folder, it captures whatever is playing
--    (the default / auto-selected audio + subtitle) and locks it for that folder.
--    On the next episodes it re-applies that choice, matched by LANGUAGE + TITLE
--    (not by track number) — so if "French" is track 1 on ep1 but track 2 on ep2,
--    it still picks French. If you change a track by hand, the memory updates.
--    New folder (e.g. Season 2) = it captures again from its first episode.
-- ]]

local mp    = require 'mp'
local utils = require 'mp.utils'
local msg   = require 'mp.msg'

local STORE_PATH  = mp.command_native({ "expand-path", "~~/track_memory.json" })

-- The remembered tracks are RE-ASSERTED several times after load (offsets in
-- seconds from file-loaded). A single apply can lose a race: mpv or
-- track-selector sometimes re-selects the default sub a beat later, which is
-- why the language occasionally "snapped back" to English. Re-checking for a
-- few seconds defeats any late override. Each pass only changes a track if it
-- isn't already the remembered one, so it never fights itself.
local REASSERT_AT = { 0.7, 1.5, 2.5, 3.5 }
local SETTLE      = 1.0   -- after the last re-assert, wait this long before changes count as "manual"

-- memory[folder] = { audio = {lang,title} | nil, sub = {lang,title} | {off=true} | nil }
local memory = {}
local current_folder = nil
local settling = true       -- true while loading/applying; ignore track changes
local pending_timers = {}   -- timers from the current file-loaded (killed on the next load)

-- ----------------------------------------------------------------
-- Persistence
-- ----------------------------------------------------------------
local function load_store()
    local f = io.open(STORE_PATH, "r")
    if not f then return end
    local data = utils.parse_json(f:read("*a"))
    f:close()
    if type(data) == "table" then memory = data end
end

local function save_store()
    local f = io.open(STORE_PATH, "w")
    if not f then msg.error("cannot write " .. STORE_PATH); return end
    f:write(utils.format_json(memory) or "{}")
    f:close()
end

-- ----------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------
local function get_folder()
    local path = mp.get_property("path")
    if not path or path == "" or path:find("://") then return nil end
    local dir = utils.split_path(path)   -- returns dir, filename
    return dir
end

local function count_tracks(ttype)
    local n = 0
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == ttype then n = n + 1 end
    end
    return n
end

-- Find the track id that best matches a remembered track. Among tracks of the
-- right language, score by flags + title and pick the best — so a "Forced"
-- (signs-only) track is never confused with the "Full" dialogue track of the
-- same language, even when neither has a distinctive title.
local function find_track(ttype, want)
    if not want then return nil end
    local best_id, best_score = nil, -1
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == ttype and (t.lang or ""):lower() == (want.lang or "") then
            local score = 0
            -- "forced" is the key differentiator (Forced/signs vs Full dialogue)
            if (t.forced or false)              == (want.forced or false) then score = score + 4 end
            if (t["hearing-impaired"] or false) == (want.hi or false)     then score = score + 2 end
            if (t.title or ""):lower()          == (want.title or "")     then score = score + 1 end
            if score > best_score then best_score = score; best_id = t.id end
        end
    end
    return best_id
end

-- Describe the currently selected track of a type, for saving.
--   returns {lang,title}          -> a track is selected
--   returns {off=true}            -> tracks exist but user disabled them
--   returns nil                   -> no tracks of this type (leave memory alone)
local function describe(ttype)
    local prop = (ttype == "audio") and "aid" or "sid"
    if count_tracks(ttype) == 0 then return nil end
    local cur = mp.get_property(prop)
    if cur == "no" then return { off = true } end
    local id = mp.get_property_number(prop)
    if not id then return nil end
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == ttype and t.id == id then
            return {
                lang   = (t.lang or ""):lower(),
                title  = (t.title or ""):lower(),
                forced = t.forced or false,
                hi     = t["hearing-impaired"] or false,
            }
        end
    end
    return nil
end

-- ----------------------------------------------------------------
-- Apply remembered tracks for the current folder
-- ----------------------------------------------------------------
-- Idempotent: only touches a track when it isn't already the remembered one,
-- so it can be called repeatedly (re-assert) without fighting itself or the user.
local function apply_memory()
    local mem = current_folder and memory[current_folder]
    if not mem then return end

    if mem.audio then
        local id = find_track("audio", mem.audio)
        if id and mp.get_property_number("aid") ~= id then
            mp.set_property_number("aid", id)
        end
    end

    if mem.sub then
        if mem.sub.off then
            if mp.get_property("sid") ~= "no" then mp.set_property("sid", "no") end
        else
            local id = find_track("sub", mem.sub)
            if id and mp.get_property_number("sid") ~= id then
                mp.set_property_number("sid", id)
            end
        end
    end
end

-- ----------------------------------------------------------------
-- Save current selection into the folder's memory
-- ----------------------------------------------------------------
local function save_current(silent)
    if not current_folder then return end
    local mem = memory[current_folder] or {}
    mem.audio = describe("audio") or mem.audio
    mem.sub   = describe("sub")   or mem.sub
    memory[current_folder] = mem
    save_store()
    if not silent then
        mp.osd_message("🎬 Audio + subtitle remembered for this series", 2)
    end
end

-- ----------------------------------------------------------------
-- Lifecycle
-- ----------------------------------------------------------------
mp.register_event("file-loaded", function()
    current_folder = get_folder()
    settling = true
    for _, t in ipairs(pending_timers) do t:kill() end
    pending_timers = {}

    local mem = current_folder and memory[current_folder]
    local has_mem = mem and next(mem) ~= nil   -- treats {} / [] empty entries as "no memory"

    -- Tell track-selector.lua to stand aside when WE own this folder's choice,
    -- so it doesn't race us by re-selecting the default (English) subtitle.
    -- (It reads this flag in its own 0.2s callback, after this handler has run.)
    mp.set_property_native("user-data/folder_track_memory_active", has_mem and true or false)

    if has_mem then
        -- Known folder: re-assert the remembered choice several times so any late
        -- auto-selection can't win the race (belt-and-suspenders alongside the flag).
        for _, at in ipairs(REASSERT_AT) do
            pending_timers[#pending_timers + 1] = mp.add_timeout(at, apply_memory)
        end
        pending_timers[#pending_timers + 1] =
            mp.add_timeout(REASSERT_AT[#REASSERT_AT] + SETTLE, function() settling = false end)
    elseif current_folder then
        -- New folder: capture whatever is playing (the auto/default pick) once,
        -- after track-selector has settled — silent for this folder's 1st episode.
        pending_timers[#pending_timers + 1] =
            mp.add_timeout(REASSERT_AT[1], function() save_current(true) end)
        pending_timers[#pending_timers + 1] =
            mp.add_timeout(REASSERT_AT[1] + SETTLE, function() settling = false end)
    else
        settling = false
    end
end)

-- Detect manual track changes (ignored during the settle window).
mp.observe_property("aid", "string", function()
    if settling then return end
    save_current()
end)
mp.observe_property("sid", "string", function()
    if settling then return end
    save_current()
end)

-- Forget the remembered choice for the current folder.
mp.register_script_message("forget-folder-tracks", function()
    if current_folder and memory[current_folder] then
        memory[current_folder] = nil
        save_store()
        mp.osd_message("Track memory cleared for this series", 2)
    else
        mp.osd_message("No track memory for this series", 2)
    end
end)
mp.add_key_binding(nil, "forget", function()
    mp.commandv("script-message", "forget-folder-tracks")
end)

load_store()
