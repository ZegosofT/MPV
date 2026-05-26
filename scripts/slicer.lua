-- [[
--    slicer.lua
--    Cut a segment of the current video and save it via ffmpeg.
--    Uses STREAM COPY (no re-encode) -> fast and lossless, but cuts
--    happen at the nearest keyframe so they may be a few frames off.
--    Output goes to a `_output` folder next to the source video.
--
--    UX: bind a key to `script-binding slicer/menu` to open the uosc
--    menu (recommended ALT+c). The menu has Begin / End / Reset.
--    Underlying actions are also exposed as separate script-bindings
--    in case you want direct keybinds.
-- ]]

local mp     = require 'mp'
local msg    = require 'mp.msg'
local utils  = require 'mp.utils'

-- ====== CONFIG ======
-- Path to ffmpeg.exe. Default "ffmpeg" tries the system PATH first.
-- If that fails, point this at the absolute path of the ffmpeg.exe
-- you want to use, e.g.:
--   local FFMPEG = "C:/mpv/ffmpeg.exe"
--   local FFMPEG = "C:/ffmpeg/bin/ffmpeg.exe"
local FFMPEG = "C:/ffmpeg/bin/ffmpeg.exe"
-- ====================

local begin_time = nil  ---@type number|nil
local end_time   = nil  ---@type number|nil

-- ----------------------------------------------------------------
-- Time formatters
-- ----------------------------------------------------------------
local function fmt_display(t)
    if not t then return "—" end
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = t - h * 3600 - m * 60
    return string.format("%02d:%02d:%05.2f", h, m, s)
end

local function fmt_filename_part(t)
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = math.floor(t - h * 3600 - m * 60)
    return string.format("%02dh%02dm%02ds", h, m, s)
end

-- ----------------------------------------------------------------
-- Build output path, ensuring the `_output` directory exists
-- ----------------------------------------------------------------
local function build_output_path()
    local input_path = mp.get_property("path")
    if not input_path or input_path:find("://") then
        return nil, "URL / stream — cannot slice"
    end

    local dir, name = utils.split_path(input_path)
    local base, ext = name:match("^(.*)%.([^.]+)$")
    if not base then base = name; ext = "mkv" end

    local output_dir = utils.join_path(dir, "_output")
    -- Best-effort mkdir; ignore "already exists"
    os.execute(('mkdir "%s" 2>nul'):format(output_dir:gsub("/", "\\")))

    local out_name = ("%s_%s-%s.%s"):format(
        base, fmt_filename_part(begin_time), fmt_filename_part(end_time), ext)
    return utils.join_path(output_dir, out_name)
end

-- ----------------------------------------------------------------
-- Run ffmpeg in the background
-- ----------------------------------------------------------------
local function do_cut()
    if not begin_time or not end_time then
        mp.osd_message("Set both BEGIN and END first", 2)
        return
    end

    if begin_time > end_time then
        begin_time, end_time = end_time, begin_time
    end

    local input_path = mp.get_property("path")
    if not input_path then return end

    local out_path, err = build_output_path()
    if not out_path then
        mp.osd_message("Slicer: " .. err, 3)
        return
    end

    local duration = end_time - begin_time
    mp.osd_message(("Cutting %.2fs ..."):format(duration), 3)

    mp.command_native_async({
        name = "subprocess",
        args = {
            FFMPEG,
            "-y",
            "-ss", tostring(begin_time),
            "-i", input_path,
            "-t", tostring(duration),
            "-c", "copy",
            "-avoid_negative_ts", "make_zero",
            out_path,
        },
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
    }, function(_, result, _)
        if result and result.status == 0 then
            mp.osd_message("Saved: " .. out_path, 4)
            msg.info("Slice saved -> " .. out_path)
        elseif not result or result.error_string == "init" then
            mp.osd_message(
                ("Slicer: ffmpeg not found at '%s'. Set FFMPEG path at top of slicer.lua."):format(FFMPEG),
                6)
            msg.error("ffmpeg binary not found / could not be started. "
                .. "Configure FFMPEG at the top of scripts/slicer.lua.")
        else
            mp.osd_message("Slice FAILED — check console (²)", 4)
            if result and result.stderr then msg.error(result.stderr) end
        end
        begin_time = nil
        end_time   = nil
    end)
end

-- ----------------------------------------------------------------
-- Actions
-- ----------------------------------------------------------------
local function mark_begin()
    begin_time = mp.get_property_number("time-pos")
    if not begin_time then return end
    mp.osd_message("BEGIN @ " .. fmt_display(begin_time), 2)
end

local function mark_end()
    end_time = mp.get_property_number("time-pos")
    if not end_time then return end
    mp.osd_message("END @ " .. fmt_display(end_time), 2)
end

local function save_clip()
    if not begin_time then
        mp.osd_message("BEGIN not set", 2)
        return
    end
    if not end_time then
        mp.osd_message("END not set", 2)
        return
    end
    do_cut()
end

local function reset_marks()
    begin_time = nil
    end_time   = nil
    mp.osd_message("Slicer marks reset", 2)
end

-- ----------------------------------------------------------------
-- uosc menu
-- ----------------------------------------------------------------
local function show_menu()
    local menu = {
        type  = "slicer",
        title = "Slicer",
        items = {
            { title = "Mark BEGIN",  icon = "play_arrow",
              value = "script-binding slicer/mark-begin" },
            { title = "Mark END",    icon = "stop",
              value = "script-binding slicer/mark-end" },
            { title = "SAVE clip",   icon = "save",
              value = "script-binding slicer/save" },
            { title = "Begin: " .. fmt_display(begin_time), value = "ignore", bold = true },
            { title = "End:   " .. fmt_display(end_time),   value = "ignore", bold = true },
            { title = "Reset markers", icon = "refresh",
              value = "script-binding slicer/reset" },
        },
    }
    mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json(menu))
end

-- ----------------------------------------------------------------
-- Bindings
-- ----------------------------------------------------------------
mp.add_key_binding(nil, "menu",       show_menu)
mp.add_key_binding(nil, "mark-begin", mark_begin)
mp.add_key_binding(nil, "mark-end",   mark_end)
mp.add_key_binding(nil, "save",       save_clip)
mp.add_key_binding(nil, "reset",      reset_marks)
