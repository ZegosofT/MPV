-- [[
--    history.lua
--    Tracks recently played files and exposes them in a uosc menu.
--    Storage: ~~/history.json (next to mpv.conf).
--    Persists across reboots. Click an entry to reopen it — mpv's
--    save-position-on-quit handles resume position automatically.
-- ]]

local mp     = require 'mp'
local msg    = require 'mp.msg'
local utils  = require 'mp.utils'

-- ====== CONFIG ======
local MAX_ENTRIES   = 50    -- maximum stored entries (oldest get dropped)
local MIN_DURATION  = 5     -- ignore files that played for less than this many seconds
-- ====================

local HISTORY_PATH = mp.command_native({"expand-path", "~~/history.json"})

---@type { path: string, title: string, time: integer }[]
local history = {}

-- Track the file currently being played so we can record it on transition
local pending = nil  -- { path, title, started_at }

-- ----------------------------------------------------------------
-- Persistence
-- ----------------------------------------------------------------
local function load_history()
    local f = io.open(HISTORY_PATH, "r")
    if not f then return end
    local content = f:read("*a")
    f:close()
    local data = utils.parse_json(content)
    if type(data) == "table" then
        history = data
    end
end

local function save_history()
    local f, err = io.open(HISTORY_PATH, "w")
    if not f then
        msg.error("Could not write history file: " .. tostring(err))
        return
    end
    f:write(utils.format_json(history) or "[]")
    f:close()
end

-- ----------------------------------------------------------------
-- Time helper for "5 min ago" / "yesterday" hint text
-- ----------------------------------------------------------------
local function relative_time(ts)
    local diff = os.time() - ts
    if diff < 60        then return "just now"
    elseif diff < 3600  then return string.format("%d min ago",  math.floor(diff / 60))
    elseif diff < 86400 then return string.format("%d hr ago",   math.floor(diff / 3600))
    elseif diff < 86400 * 7  then return string.format("%d days ago", math.floor(diff / 86400))
    else                     return os.date("%Y-%m-%d", ts)
    end
end

-- ----------------------------------------------------------------
-- Add (or move-to-top) an entry
-- ----------------------------------------------------------------
local function record(path, title)
    if not path or path == "" then return end

    -- Remove any previous occurrence so it moves to top
    for i = #history, 1, -1 do
        if history[i].path == path then
            table.remove(history, i)
        end
    end

    table.insert(history, 1, {
        path  = path,
        title = title or path,
        time  = os.time(),
    })

    while #history > MAX_ENTRIES do
        table.remove(history)
    end

    save_history()
end

-- ----------------------------------------------------------------
-- Commit the currently-playing file if it played long enough
-- ----------------------------------------------------------------
local function commit_pending()
    if not pending then return end
    local now = os.time()
    if (now - pending.started_at) >= MIN_DURATION then
        record(pending.path, pending.title)
    end
    pending = nil
end

-- ----------------------------------------------------------------
-- Menu builder
-- ----------------------------------------------------------------
local function show_menu()
    if #history == 0 then
        mp.osd_message("No history yet", 2)
        return
    end

    local items = {}
    for i, entry in ipairs(history) do
        table.insert(items, {
            title = entry.title,
            hint  = relative_time(entry.time),
            value = ("script-message hist-load %d"):format(i),
        })
    end
    table.insert(items, { title = "──── Clear all ────", value = "script-message hist-clear", bold = true })

    local menu = {
        type  = "history",
        title = "Recently Played (" .. #history .. ")",
        items = items,
    }
    mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json(menu))
end

-- ----------------------------------------------------------------
-- Script-messages
-- ----------------------------------------------------------------
mp.register_script_message("hist-load", function(idx_str)
    local idx = tonumber(idx_str)
    if not idx or not history[idx] then return end
    mp.commandv("loadfile", history[idx].path)
end)

mp.register_script_message("hist-clear", function()
    history = {}
    save_history()
    mp.osd_message("History cleared", 2)
end)

-- ----------------------------------------------------------------
-- Lifecycle hooks
-- ----------------------------------------------------------------
mp.register_event("file-loaded", function()
    -- Commit the previous file (if any) when a new one loads
    commit_pending()

    local path = mp.get_property("path")
    if not path or path == "" then return end
    pending = {
        path  = path,
        title = mp.get_property("media-title") or mp.get_property("filename") or path,
        started_at = os.time(),
    }
end)

mp.register_event("shutdown", commit_pending)

mp.add_key_binding(nil, "menu",  show_menu)
mp.add_key_binding(nil, "clear", function()
    history = {}
    save_history()
    mp.osd_message("History cleared", 2)
end)

load_history()
