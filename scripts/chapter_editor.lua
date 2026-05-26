-- [[
--    chapter_editor.lua
--    Create / rename / delete chapters at runtime.
--    Changes persist to a sidecar file `<videoname>.chapters` next to
--    the video, in OGM format (CHAPTERxx= / CHAPTERxxNAME=).
--    The sidecar is auto-loaded on file open if present — it OVERRIDES
--    any chapters embedded in the file. Delete the sidecar to revert.
-- ]]

local mp     = require 'mp'
local msg    = require 'mp.msg'
local utils  = require 'mp.utils'
local input_loaded, input = pcall(require, 'mp.input')

-- ----------------------------------------------------------------
-- Sidecar path
-- ----------------------------------------------------------------
local function sidecar_path()
    local path = mp.get_property("path")
    if not path or path:find("://") then return nil end  -- skip URLs / streams
    return (path:gsub("%.[^.]+$", "")) .. ".chapters"
end

-- ----------------------------------------------------------------
-- Time formatting helpers
-- ----------------------------------------------------------------
local function fmt_time(t)
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = t - h * 3600 - m * 60
    return string.format("%02d:%02d:%06.3f", h, m, s)
end

local function parse_time(str)
    local h, m, s = str:match("^(%d+):(%d+):([%d.]+)$")
    if not h then return nil end
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
end

-- ----------------------------------------------------------------
-- Sort + assign chapter list to mpv
-- ----------------------------------------------------------------
local function apply_chapter_list(chapters)
    table.sort(chapters, function(a, b) return a.time < b.time end)
    mp.set_property_native("chapter-list", chapters)
end

-- ----------------------------------------------------------------
-- Save current chapter-list to sidecar
-- ----------------------------------------------------------------
local function save_sidecar()
    local sp = sidecar_path()
    if not sp then return end

    local chapters = mp.get_property_native("chapter-list", {})
    if #chapters == 0 then
        -- Empty list: delete sidecar if present
        os.remove(sp)
        return
    end

    local f, err = io.open(sp, "w")
    if not f then
        msg.error("Could not write " .. sp .. ": " .. tostring(err))
        mp.osd_message("Chapter save failed", 2)
        return
    end
    for i, ch in ipairs(chapters) do
        f:write(string.format("CHAPTER%02d=%s\n", i, fmt_time(ch.time or 0)))
        f:write(string.format("CHAPTER%02dNAME=%s\n", i, ch.title or ("Chapter " .. i)))
    end
    f:close()
end

-- ----------------------------------------------------------------
-- Load chapters from sidecar (if present)
-- ----------------------------------------------------------------
local function load_sidecar()
    local sp = sidecar_path()
    if not sp then return end

    local f = io.open(sp, "r")
    if not f then return end  -- no sidecar, nothing to load

    local buckets = {}  -- index -> {time=, title=}
    for line in f:lines() do
        local idx, time_str = line:match("^CHAPTER(%d+)=(.+)$")
        if idx and time_str then
            local i = tonumber(idx)
            buckets[i] = buckets[i] or {}
            buckets[i].time = parse_time(time_str)
        else
            local idx2, name = line:match("^CHAPTER(%d+)NAME=(.*)$")
            if idx2 then
                local i = tonumber(idx2)
                buckets[i] = buckets[i] or {}
                buckets[i].title = name
            end
        end
    end
    f:close()

    -- Collapse sparse bucket table into an array
    local chapters = {}
    for i = 1, 999 do
        if buckets[i] and buckets[i].time then
            table.insert(chapters, {
                time = buckets[i].time,
                title = buckets[i].title or ("Chapter " .. i),
            })
        end
    end

    if #chapters > 0 then
        apply_chapter_list(chapters)
        msg.info("Loaded " .. #chapters .. " chapters from sidecar")
    end
end

-- ----------------------------------------------------------------
-- Add chapter at current time
-- ----------------------------------------------------------------
local function add_chapter()
    if not input_loaded then
        mp.osd_message("Needs mpv 0.38+ (mp.input)", 2)
        return
    end

    local t = mp.get_property_number("time-pos")
    if not t then
        mp.osd_message("No file loaded", 2)
        return
    end

    input.get({
        prompt = ("New chapter at %s — name:"):format(mp.get_property_osd("time-pos")),
        submit = function(name)
            input.terminate()
            if not name or name == "" then return end

            local chapters = mp.get_property_native("chapter-list", {}) or {}
            table.insert(chapters, { time = t, title = name })
            apply_chapter_list(chapters)
            save_sidecar()
            mp.osd_message(("+ %s @ %s"):format(name, mp.get_property_osd("time-pos")), 2)
        end,
    })
end

-- ----------------------------------------------------------------
-- Rename the chapter currently playing
-- ----------------------------------------------------------------
local function rename_current_chapter()
    if not input_loaded then
        mp.osd_message("Needs mpv 0.38+ (mp.input)", 2)
        return
    end

    local idx = mp.get_property_number("chapter")  -- 0-based, nil if no chapters
    if not idx or idx < 0 then
        mp.osd_message("No active chapter", 2)
        return
    end
    idx = idx + 1  -- to 1-based for Lua

    local chapters = mp.get_property_native("chapter-list", {}) or {}
    local ch = chapters[idx]
    if not ch then
        mp.osd_message("No active chapter", 2)
        return
    end

    input.get({
        prompt = ("Rename '%s' to:"):format(ch.title or "Chapter " .. idx),
        default_text = ch.title or "",
        submit = function(name)
            input.terminate()
            if not name or name == "" then return end
            chapters[idx].title = name
            apply_chapter_list(chapters)
            save_sidecar()
            mp.osd_message("Renamed: " .. name, 2)
        end,
    })
end

-- ----------------------------------------------------------------
-- Delete the chapter currently playing
-- ----------------------------------------------------------------
local function delete_current_chapter()
    local idx = mp.get_property_number("chapter")
    if not idx or idx < 0 then
        mp.osd_message("No active chapter", 2)
        return
    end
    idx = idx + 1

    local chapters = mp.get_property_native("chapter-list", {}) or {}
    if not chapters[idx] then
        mp.osd_message("No active chapter", 2)
        return
    end

    local removed_title = chapters[idx].title or ("Chapter " .. idx)
    table.remove(chapters, idx)
    apply_chapter_list(chapters)
    save_sidecar()
    mp.osd_message("Deleted: " .. removed_title, 2)
end

-- ----------------------------------------------------------------
-- Wipe ALL chapters for this file (deletes sidecar too)
-- ----------------------------------------------------------------
local function clear_all_chapters()
    apply_chapter_list({})
    save_sidecar()  -- with empty list, this removes the sidecar
    mp.osd_message("All chapters cleared (sidecar removed)", 2)
end

-- ----------------------------------------------------------------
-- uosc menu wrapper
-- ----------------------------------------------------------------
local function show_menu()
    local chapters    = mp.get_property_native("chapter-list", {}) or {}
    local current_idx = mp.get_property_number("chapter")
    local current_str
    if current_idx and current_idx >= 0 and chapters[current_idx + 1] then
        local ch = chapters[current_idx + 1]
        current_str = ("Current: \"%s\" @ %s"):format(
            ch.title or ("Chapter " .. (current_idx + 1)),
            fmt_time(ch.time or 0))
    else
        current_str = ("No active chapter (%d total)"):format(#chapters)
    end

    local menu = {
        type  = "chapter-editor",
        title = "Chapter Editor",
        items = {
            { title = current_str, value = "ignore", bold = true },
            { title = "Add chapter at current time", icon = "add",
              value = "script-binding chapter_editor/add" },
            { title = "Rename current chapter", icon = "edit",
              value = "script-binding chapter_editor/rename-current" },
            { title = "Delete current chapter", icon = "delete",
              value = "script-binding chapter_editor/delete-current" },
            { title = "Wipe ALL chapters (removes sidecar)", icon = "delete_forever",
              value = "script-binding chapter_editor/clear-all", bold = true },
        },
    }
    mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json(menu))
end

-- ----------------------------------------------------------------
-- Bindings + auto-load
-- ----------------------------------------------------------------
mp.add_key_binding(nil, "add",            add_chapter)
mp.add_key_binding(nil, "rename-current", rename_current_chapter)
mp.add_key_binding(nil, "delete-current", delete_current_chapter)
mp.add_key_binding(nil, "clear-all",      clear_all_chapters)
mp.add_key_binding(nil, "menu",           show_menu)

mp.register_event("file-loaded", function()
    -- Tiny delay so embedded chapters land first; our load then overrides.
    mp.add_timeout(0.3, load_sidecar)
end)
