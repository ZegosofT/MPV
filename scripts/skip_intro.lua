-- [[
--    FILENAME: skip_intro.lua
--    VERSION:  v3.0 (Config-driven, exact-match)
--    DESC:     OP/ED/PV/Intro detection is now driven entirely by
--              script-opts/skip_intro.conf. Only chapters whose titles are
--              listed in the conf (or whose 1-based chapter number is
--              listed) get categorised and skipped.
--
--              Matching is case-insensitive and whitespace-tolerant.
--              No hardcoded keyword list — the conf is the single source.
-- ]]

local mp = require("mp")
local utils = require("mp.utils")

local opts = {
    enabled = true,
    auto_skip = true,
    instant_skip_key = "ENTER",   -- press during countdown to skip immediately
    cancel_key       = "BS",      -- press during countdown to cancel the skip
    toggle_key       = "Ctrl+ENTER",
    timeout = 6,
    countdown = 5,

    skip_intro = true,
    skip_opening = true,
    skip_ending = true, -- also controls Preview/PV
}

-- Conf key -> label mapping.
local CATEGORY_TO_LABEL = {
    opening = "OP",
    intro   = "Intro",
    ending  = "ED",
    preview = "PV",
}

local label_colors = {
    Intro = "0099FF",
    OP    = "00FF00",
    PV    = "FF8000",
    ED    = "FF8000"
}

local state = {
    current_chapter_idx = -1,
    cached_chapters = nil,
    countdown_timer = nil,
    clear_timer = nil,
    countdown_active = false,
    cancelled_chapters = {},
    active_label = nil,
    active_chapter_idx = nil
}

-- Conf-loaded map (rebuilt every load_manual_overrides()).
local manual_title_labels = {} -- normalized_title -> label

local function normalize_title(t)
    if not t then return "" end
    return (t:match("^%s*(.-)%s*$") or ""):lower()
end

local function load_manual_overrides()
    manual_title_labels = {}

    local conf_path = mp.command_native({"expand-path", "~~/script-opts/skip_intro.conf"})
    local f = io.open(conf_path, "r")
    if not f then return end

    for line in f:lines() do
        if not line:match("^%s*#") and not line:match("^%s*$") then
            local key, value = line:match("^%s*([%w_]+)%s*=%s*(.*)$")
            if key and value then
                local label = CATEGORY_TO_LABEL[key:lower()]
                if label then
                    -- Pure exact-title match. Each quoted string in the
                    -- value list becomes one matchable chapter title.
                    for title in value:gmatch('"([^"]*)"') do
                        local norm = normalize_title(title)
                        if norm ~= "" then
                            manual_title_labels[norm] = label
                        end
                    end
                end
            end
        end
    end
    f:close()
end

local function broadcast_skip_state()
    mp.commandv("script-message", "anime-state-broadcast", utils.format_json({
        skip_target_intro   = opts.skip_intro,
        skip_target_opening = opts.skip_opening,
        skip_target_ending  = opts.skip_ending,
    }))
end

local function label_enabled(label)
    if     label == "Intro"               then return opts.skip_intro
    elseif label == "OP"                  then return opts.skip_opening
    elseif label == "ED" or label == "PV" then return opts.skip_ending
    end
    return false
end

-- Returns the label for this chapter, or nil. Driven only by exact
-- title match against entries in skip_intro.conf.
local function get_chapter_label(_, title)
    if not title then return nil end
    local lab = manual_title_labels[normalize_title(title)]
    if lab and label_enabled(lab) then return lab end
    return nil
end

local function paint_canvas(ass_text)
    mp.set_osd_ass(1920, 1080, ass_text or "")
end

local function clear_osd() paint_canvas("") end

local function stop_clear_timer()
    if state.clear_timer then
        state.clear_timer:kill()
        state.clear_timer = nil
    end
end

local function clear_osd_later(delay)
    stop_clear_timer()
    state.clear_timer = mp.add_timeout(delay or 0.2, function()
        clear_osd()
        state.clear_timer = nil
    end)
end

-- `keep_instant_skip` lets us preserve the ENTER binding after a
-- cancellation, so the user can still manually skip the rest of the
-- chapter. When the chapter changes or playback ends, on_tick /
-- skip_action call stop_countdown without the flag, which removes
-- ENTER again. Safe even when ENTER was already removed.
local function stop_countdown(keep_instant_skip)
    if state.countdown_timer then
        state.countdown_timer:kill()
        state.countdown_timer = nil
    end
    state.countdown_active = false
    mp.remove_key_binding("skip-intro-cancel-countdown")
    if not keep_instant_skip then
        mp.remove_key_binding("skip-intro-instant-skip")
    end
end

local function reset_runtime_state()
    stop_countdown()
    stop_clear_timer()
    clear_osd()
    state.current_chapter_idx = -1
    state.active_label = nil
    state.active_chapter_idx = nil
    state.cancelled_chapters = {}
end

local function draw_countdown(label, remaining)
    local color = label_colors[label] or "FFFFFF"
    local display_label = label == "PV" and "ENDING" or label
    local cx, cy = 1650, 980
    local ass = "{\\an5}{\\pos(" .. cx .. "," .. cy .. ")}"
    ass = ass .. "{\\fnSource Sans Pro}{\\fs40}{\\b1}"
    ass = ass .. "{\\bord4}{\\shad2}{\\blur4}{\\3c&H000000&}{\\4c&H000000&}"
    ass = ass .. "{\\1c&H" .. color .. "&}▶ "
    ass = ass .. "{\\1c&HFFFFFF&}" .. display_label .. " IN "
    ass = ass .. "{\\1c&H" .. color .. "&}" .. tostring(remaining)
    ass = ass .. "   {\\1c&H00FF00&}ENTER{\\1c&HFFFFFF&} skip"
    ass = ass .. "   {\\1c&H0000FF&}BS{\\1c&HFFFFFF&} cancel"
    paint_canvas(ass)
end

local function draw_cancelled(label)
    local color = label_colors[label] or "FFFFFF"
    local display_label = label == "PV" and "ENDING" or label
    local cx, cy = 1650, 980
    local ass = "{\\an5}{\\pos(" .. cx .. "," .. cy .. ")}"
    ass = ass .. "{\\fnSource Sans Pro}{\\fs40}{\\b1}"
    ass = ass .. "{\\bord4}{\\shad2}{\\blur4}{\\3c&H000000&}{\\4c&H000000&}"
    ass = ass .. "{\\1c&H" .. color .. "&}" .. display_label .. " CANCELLED"
    ass = ass .. "   {\\1c&H00FF00&}ENTER{\\1c&HFFFFFF&} still skips"
    paint_canvas(ass)
end

local function skip_action()
    stop_countdown()
    clear_osd()
    mp.commandv("no-osd", "add", "chapter", 1)
    clear_osd_later(0.05)
end

local function cancel_current_countdown()
    if not state.countdown_active or not state.active_chapter_idx then return end
    local idx = state.active_chapter_idx
    state.cancelled_chapters[idx] = true
    local label = state.active_label or "SKIP"
    -- Keep ENTER bound: user can still skip this chapter manually
    -- until it ends (or until they enter a different chapter).
    stop_countdown(true)
    draw_cancelled(label)
    clear_osd_later(1.5)
end

local function start_countdown(label, chapter_idx)
    stop_countdown()
    stop_clear_timer()

    state.countdown_active     = true
    state.active_label         = label
    state.active_chapter_idx   = chapter_idx
    state.cancelled_chapters[chapter_idx] = nil

    local remaining = opts.countdown

    mp.add_forced_key_binding(opts.cancel_key,       "skip-intro-cancel-countdown", cancel_current_countdown)
    mp.add_forced_key_binding(opts.instant_skip_key, "skip-intro-instant-skip",     skip_action)

    local function tick()
        if not state.countdown_active then return end
        if state.active_chapter_idx ~= chapter_idx then
            stop_countdown(); clear_osd(); return
        end
        if remaining <= 0 then skip_action(); return end
        draw_countdown(label, remaining)
        remaining = remaining - 1
        state.countdown_timer = mp.add_timeout(1.0, tick)
    end

    tick()
end

local function find_current_target()
    local chapters = state.cached_chapters
    if not chapters then return nil, nil end

    local pos = mp.get_property_number("time-pos")
    if not pos then return nil, nil end

    for i, ch in ipairs(chapters) do
        local next_ch = chapters[i + 1]
        if pos >= ch.time and (not next_ch or pos < next_ch.time) then
            local label = get_chapter_label(i, ch.title)
            if label then return i, label end
            return i, nil
        end
    end
    return nil, nil
end

local function update_chapter_cache()
    load_manual_overrides()
    state.cached_chapters = mp.get_property_native("chapter-list")
    reset_runtime_state()
    broadcast_skip_state()
end

local function toggle_auto_skip()
    opts.auto_skip = not opts.auto_skip
    mp.osd_message("Auto-skip OP/ED: " .. (opts.auto_skip and "ON" or "OFF"), 2)
end

local function on_tick()
    if not opts.enabled then
        if state.countdown_active then stop_countdown(); clear_osd() end
        return
    end

    local current_idx, label = find_current_target()

    if not current_idx or not label then
        if state.current_chapter_idx ~= -1 or state.countdown_active then
            state.current_chapter_idx = -1
            state.active_label = nil
            state.active_chapter_idx = nil
            stop_countdown(); clear_osd()
        end
        return
    end

    if current_idx ~= state.current_chapter_idx then
        state.current_chapter_idx = current_idx
        state.active_label = label
        state.active_chapter_idx = current_idx

        stop_countdown(); clear_osd()

        if opts.auto_skip and not state.cancelled_chapters[current_idx] then
            start_countdown(label, current_idx)
        end
    end
end

mp.register_script_message("toggle-state", function(val)
    opts.enabled = (val == "true")
    if not opts.enabled then reset_runtime_state() end
    broadcast_skip_state()
end)

mp.register_script_message("skip-toggle-intro", function()
    opts.skip_intro = not opts.skip_intro
    reset_runtime_state(); broadcast_skip_state()
    mp.osd_message("Skip Intro: " .. (opts.skip_intro and "ON" or "OFF"), 2)
end)

mp.register_script_message("skip-toggle-opening", function()
    opts.skip_opening = not opts.skip_opening
    reset_runtime_state(); broadcast_skip_state()
    mp.osd_message("Skip Opening: " .. (opts.skip_opening and "ON" or "OFF"), 2)
end)

mp.register_script_message("skip-toggle-ending", function()
    opts.skip_ending = not opts.skip_ending
    reset_runtime_state(); broadcast_skip_state()
    mp.osd_message("Skip Ending/Preview: " .. (opts.skip_ending and "ON" or "OFF"), 2)
end)

mp.register_script_message("reload-skip-intro", function()
    load_manual_overrides()
    reset_runtime_state()
    mp.osd_message("Skip Intro: chapter overrides reloaded", 2)
end)

mp.add_forced_key_binding(opts.toggle_key, "toggle-auto-skip-op-ed", toggle_auto_skip)

mp.register_event("file-loaded", update_chapter_cache)
mp.register_event("end-file",    reset_runtime_state)
mp.observe_property("chapter", "native", function()
    if state.countdown_active then stop_countdown(); clear_osd() end
end)

mp.add_periodic_timer(0.2, on_tick)
