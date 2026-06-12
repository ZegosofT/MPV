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
local APPLY_DELAY = 0.7   -- apply remembered tracks this long after load (after track-selector)
local SETTLE      = 1.0   -- after applying, wait this long before changes count as "manual"

-- memory[folder] = { audio = {lang,title} | nil, sub = {lang,title} | {off=true} | nil }
local memory = {}
local current_folder = nil
local settling = true       -- true while loading/applying; ignore track changes
local settle_timer = nil

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

-- Find a track id matching a remembered {lang, title}. Prefer exact lang+title,
-- fall back to a lang-only match.
local function find_track(ttype, want)
    if not want then return nil end
    local lang_only = nil
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == ttype then
            local lang  = (t.lang or ""):lower()
            local title = (t.title or ""):lower()
            if lang == (want.lang or "") then
                if want.title and want.title ~= "" then
                    if title == want.title then return t.id end
                    if not lang_only then lang_only = t.id end
                else
                    return t.id
                end
            end
        end
    end
    return lang_only
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
            return { lang = (t.lang or ""):lower(), title = (t.title or ""):lower() }
        end
    end
    return nil
end

-- ----------------------------------------------------------------
-- Apply remembered tracks for the current folder
-- ----------------------------------------------------------------
local function apply_memory()
    local mem = current_folder and memory[current_folder]
    if not mem then return end

    if mem.audio then
        local id = find_track("audio", mem.audio)
        if id then mp.set_property("aid", id) end
    end

    if mem.sub then
        if mem.sub.off then
            mp.set_property("sid", "no")
        else
            local id = find_track("sub", mem.sub)
            if id then mp.set_property("sid", id) end
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
    if settle_timer then settle_timer:kill(); settle_timer = nil end

    -- After track-selector has had its turn:
    --   * known folder  -> re-apply the remembered choice
    --   * new folder    -> capture whatever is playing now (the auto/default pick)
    -- Then open the window where manual changes count.
    mp.add_timeout(APPLY_DELAY, function()
        if current_folder and memory[current_folder] then
            apply_memory()
        elseif current_folder then
            save_current(true)   -- silent auto-capture for this folder's 1st episode
        end
        settle_timer = mp.add_timeout(SETTLE, function() settling = false end)
    end)
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
