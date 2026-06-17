-- [[
--    history.lua
--    Tracks recently played files and exposes them in a uosc menu.
--    Storage: ~~/history.json (next to mpv.conf).
--    Persists across reboots. Click an entry to reopen it — mpv's
--    save-position-on-quit handles resume position automatically.
--
--    Folders can be EXCLUDED from history (e.g. a "Desktop" or scratch folder):
--    files inside an excluded folder are never recorded, never shown in the
--    menu, and never auto-resumed. Configure in script-opts/history.conf.
-- ]]

local mp      = require 'mp'
local msg     = require 'mp.msg'
local utils   = require 'mp.utils'
local options = require 'mp.options'

-- ====== CONFIG (override in script-opts/history.conf) ======
local opts = {
    max_entries  = 50,    -- maximum stored entries (oldest get dropped)
    min_duration = 5,     -- ignore files that played for fewer than this many seconds
    auto_resume  = true,  -- auto-open most recent (non-excluded) file when mpv launches with no file
    exclude      = "",    -- ";"-separated folders; files inside (recursively) are never recorded/shown/resumed
}
options.read_options(opts, "history")
-- ===========================================================

local HISTORY_PATH = mp.command_native({"expand-path", "~~/history.json"})

---@type { path: string, title: string, time: integer }[]
local history = {}

-- Track the file currently being played so we can record it on transition
local pending = nil  -- { path, title, started_at }

-- ----------------------------------------------------------------
-- Folder exclusion (configurable via `exclude` in history.conf)
-- ----------------------------------------------------------------
-- Normalize a path for comparison: expand ~, lowercase, forward slashes,
-- no trailing slash. So C:\Foo\ and c:/foo match the same folder.
local function normalize(p)
    if not p or p == "" then return nil end
    p = mp.command_native({"expand-path", p})
    p = p:gsub("\\", "/"):lower():gsub("/+$", "")
    return p
end

local excluded = {}
for entry in tostring(opts.exclude):gmatch("[^;]+") do
    local n = normalize((entry:gsub("^%s*(.-)%s*$", "%1")))  -- trim, then normalize
    if n then excluded[#excluded + 1] = n end
end

-- True if `path` sits inside one of the excluded folders (or a subfolder).
local function is_excluded(path)
    if not path or path == "" or path:find("://") then return false end
    local n = normalize(path)
    if not n then return false end
    for _, base in ipairs(excluded) do
        if n == base or n:sub(1, #base + 1) == base .. "/" then return true end
    end
    return false
end

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
    if is_excluded(path) then return end   -- excluded folder: never recorded

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

    while #history > opts.max_entries do
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
    if (now - pending.started_at) >= opts.min_duration then
        record(pending.path, pending.title)
    end
    pending = nil
end

-- ----------------------------------------------------------------
-- Menu builder
-- ----------------------------------------------------------------
local function show_menu()
    local items = {}
    for i, entry in ipairs(history) do
        if not is_excluded(entry.path) then   -- hide excluded (incl. pre-existing) entries
            items[#items + 1] = {
                title = entry.title,
                hint  = relative_time(entry.time),
                value = ("script-message hist-load %d"):format(i),  -- real index into history
            }
        end
    end

    if #items == 0 then
        mp.osd_message("No history yet", 2)
        return
    end

    local count = #items
    items[#items + 1] = { title = "──── Clear all ────", value = "script-message hist-clear", bold = true }

    local menu = {
        type  = "history",
        title = "Recently Played (" .. count .. ")",
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

-- Auto-resume the most recent NON-excluded file when mpv launches with no file
-- argument. We watch idle-active and fire ONCE the first time mpv goes idle.
-- The `resumed` flag prevents re-firing when later files end.
if opts.auto_resume and not mp.get_property_bool("options/input-test") then
    local resumed = false
    mp.observe_property("idle-active", "bool", function(_, active)
        if active and not resumed and #history > 0 then
            resumed = true
            local last
            for _, entry in ipairs(history) do
                if not is_excluded(entry.path) then last = entry; break end
            end
            if last then
                mp.osd_message("Resuming: " .. last.title, 3)
                mp.commandv("loadfile", last.path)
            end
        end
    end)
end
