-- [[ 
--    FILENAME: skip_intro.lua
--    VERSION:  v2.5
--    AUTHOR:   mpv-anime-build + custom edit
--    DESC:     OP/ED/PV/Intro detection with countdown auto-skip, cancel and per-type toggles.
-- ]]

local mp = require("mp")
local utils = require("mp.utils")

local opts = {
    enabled = true,
    auto_skip = true,
    skip_key = "ENTER",
    toggle_key = "Ctrl+ENTER",
    timeout = 6,
    countdown = 5,

    skip_intro = true,
    skip_opening = true,
    skip_ending = true, -- also controls Preview/PV
}

local categories = {
    {
        label = "OP",
        keywords = {
            "opening", " op ", "^op$", "op%d", "theme song", "main theme", "Chapter 02",
            "オープニング", "オープニングテーマ", "OPテーマ", "主題歌", 
            "ncop", "creditless op", "creditless opening"
        }
    },
    {
        label = "ED",
        keywords = {
            "ending", " ed ", "^ed$", "ed%d", "credits", "outro", "end roll", "Chapter 06", "Chapter 7",
            "エンディング", "エンディングテーマ", "EDテーマ", "結び",
            "nced", "creditless ed", "creditless ending"
        }
    },
    {
        label = "PV",
        keywords = {
            "preview", " pv ", "^pv$", "pv%d", "trailer", "next episode",
            "予告", "次回予告", "特報", "プロモーション",
            "jikai", "yokoku"
        }
    },
    {
        label = "Intro",
        keywords = {
            "intro", "introduction", "cold open",
            "アバン", "アバンタイトル", "序章", "前説"
        }
    }
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

local function broadcast_skip_state()
    mp.commandv("script-message", "anime-state-broadcast", utils.format_json({
        skip_target_intro = opts.skip_intro,
        skip_target_opening = opts.skip_opening,
        skip_target_ending = opts.skip_ending,
    }))
end

local function label_enabled(label)
    if label == "Intro" then
        return opts.skip_intro
    elseif label == "OP" then
        return opts.skip_opening
    elseif label == "ED" or label == "PV" then
        return opts.skip_ending
    end
    return false
end

local function get_chapter_label(title)
    if not title then return nil end
    local title_lower = title:lower()
    for _, category in ipairs(categories) do
        for _, keyword in ipairs(category.keywords) do
            if title_lower:find(keyword) or title:find(keyword) then
                if label_enabled(category.label) then
                    return category.label
                end
                return nil
            end
        end
    end
    return nil
end

local function paint_canvas(ass_text)
    mp.set_osd_ass(1920, 1080, ass_text or "")
end

local function clear_osd()
    paint_canvas("")
end

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

local function stop_countdown()
    if state.countdown_timer then
        state.countdown_timer:kill()
        state.countdown_timer = nil
    end
    state.countdown_active = false
    mp.remove_key_binding("skip-intro-cancel-countdown")
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
    ass = ass .. "{\\1c&HFFFFFF&}  [ENTER = CANCEL]"
    paint_canvas(ass)
end

local function draw_cancelled(label)
    local color = label_colors[label] or "FFFFFF"
    local display_label = label == "PV" and "ENDING" or label
    local cx, cy = 1650, 980
    local ass = "{\\an5}{\\pos(" .. cx .. "," .. cy .. ")}"
    ass = ass .. "{\\fnSource Sans Pro}{\\fs40}{\\b1}"
    ass = ass .. "{\\bord4}{\\shad2}{\\blur4}{\\3c&H000000&}{\\4c&H000000&}"
    ass = ass .. "{\\1c&H" .. color .. "&}" .. display_label .. " SKIP CANCELLED"
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
    stop_countdown()
    draw_cancelled(label)
    clear_osd_later(1.0)
end

local function start_countdown(label, chapter_idx)
    stop_countdown()
    stop_clear_timer()

    state.countdown_active = true
    state.active_label = label
    state.active_chapter_idx = chapter_idx
    state.cancelled_chapters[chapter_idx] = nil

    local remaining = opts.countdown

    mp.add_forced_key_binding(opts.skip_key, "skip-intro-cancel-countdown", cancel_current_countdown)

    local function tick()
        if not state.countdown_active then return end

        if state.active_chapter_idx ~= chapter_idx then
            stop_countdown()
            clear_osd()
            return
        end

        if remaining <= 0 then
            skip_action()
            return
        end

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
            local label = get_chapter_label(ch.title)
            if label then
                return i, label
            end
            return i, nil
        end
    end

    return nil, nil
end

local function update_chapter_cache()
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
        if state.countdown_active then
            stop_countdown()
            clear_osd()
        end
        return
    end

    local current_idx, label = find_current_target()

    if not current_idx or not label then
        if state.current_chapter_idx ~= -1 or state.countdown_active then
            state.current_chapter_idx = -1
            state.active_label = nil
            state.active_chapter_idx = nil
            stop_countdown()
            clear_osd()
        end
        return
    end

    if current_idx ~= state.current_chapter_idx then
        state.current_chapter_idx = current_idx
        state.active_label = label
        state.active_chapter_idx = current_idx

        stop_countdown()
        clear_osd()

        if opts.auto_skip and not state.cancelled_chapters[current_idx] then
            start_countdown(label, current_idx)
        end
    end
end

mp.register_script_message("toggle-state", function(val)
    opts.enabled = (val == "true")
    if not opts.enabled then
        reset_runtime_state()
    end
    broadcast_skip_state()
end)

mp.register_script_message("skip-toggle-intro", function()
    opts.skip_intro = not opts.skip_intro
    reset_runtime_state()
    broadcast_skip_state()
    mp.osd_message("Skip Intro: " .. (opts.skip_intro and "ON" or "OFF"), 2)
end)

mp.register_script_message("skip-toggle-opening", function()
    opts.skip_opening = not opts.skip_opening
    reset_runtime_state()
    broadcast_skip_state()
    mp.osd_message("Skip Opening: " .. (opts.skip_opening and "ON" or "OFF"), 2)
end)

mp.register_script_message("skip-toggle-ending", function()
    opts.skip_ending = not opts.skip_ending
    reset_runtime_state()
    broadcast_skip_state()
    mp.osd_message("Skip Ending/Preview: " .. (opts.skip_ending and "ON" or "OFF"), 2)
end)

mp.add_forced_key_binding(opts.toggle_key, "toggle-auto-skip-op-ed", toggle_auto_skip)

mp.register_event("file-loaded", update_chapter_cache)
mp.register_event("end-file", reset_runtime_state)
mp.observe_property("chapter", "native", function()
    if state.countdown_active then
        stop_countdown()
        clear_osd()
    end
end)

mp.add_periodic_timer(0.2, on_tick)
