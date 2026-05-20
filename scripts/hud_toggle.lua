-- Toggle uosc HUD visibility lock per-element + a "reset everything" action.
-- Default uosc behaviour: every element auto-hides when the mouse leaves.
-- This script flips a "force always on" mode by setting *_persistency
-- options to cover every playback state, then restores autohide on second
-- press.

local mp = require 'mp'

local FORCED = 'audio,video,image,idle,paused'

-- The "all-at-once" lock (kept for the original H binding)
local ALL_KEYS = {
    "uosc-top_bar_persistency",
    "uosc-timeline_persistency",
    "uosc-controls_persistency",
    "uosc-volume_persistency",
    "uosc-speed_persistency",
    "uosc-progress_persistency",
}

-- Per-element entries that we expose as individual toggles
local INDIVIDUAL = {
    timeline = "uosc-timeline_persistency",
    controls = "uosc-controls_persistency",
    top_bar  = "uosc-top_bar_persistency",
    volume   = "uosc-volume_persistency",
}

local state = {}  -- state[key] = true if currently forced-on

local function set_opt(key, value)
    local opts = mp.get_property_native("script-opts") or {}
    opts[key] = value
    mp.set_property_native("script-opts", opts)
end

-- Toggle a single element between FORCED and autohide ("")
local function make_toggle(name)
    local key = INDIVIDUAL[name]
    return function()
        if state[key] then
            set_opt(key, "")
            state[key] = false
            mp.osd_message(name .. ": auto-hide", 1)
        else
            set_opt(key, FORCED)
            state[key] = true
            mp.osd_message(name .. ": always on", 1)
        end
    end
end

-- Reset every per-element override back to autohide
local function reset_all()
    local opts = mp.get_property_native("script-opts") or {}
    for _, key in pairs(INDIVIDUAL) do
        opts[key] = ""
        state[key] = false
    end
    mp.set_property_native("script-opts", opts)
    mp.osd_message("HUD: defaults", 1)
end

-- The original "lock everything on / off" master toggle (used by your H key)
local forced_all = false
local saved = {}
local function toggle_all()
    local opts = mp.get_property_native("script-opts") or {}
    if not forced_all then
        saved = {}
        for _, key in ipairs(ALL_KEYS) do
            saved[key] = opts[key] or ""
            opts[key] = FORCED
        end
        forced_all = true
        mp.osd_message("HUD: locked on", 1)
    else
        for _, key in ipairs(ALL_KEYS) do
            opts[key] = saved[key] or ""
        end
        forced_all = false
        mp.osd_message("HUD: auto-hide", 1)
    end
    mp.set_property_native("script-opts", opts)
end

mp.add_key_binding(nil, "toggle",          toggle_all)
mp.add_key_binding(nil, "toggle-timeline", make_toggle("timeline"))
mp.add_key_binding(nil, "toggle-controls", make_toggle("controls"))
mp.add_key_binding(nil, "toggle-top_bar",  make_toggle("top_bar"))
mp.add_key_binding(nil, "toggle-volume",   make_toggle("volume"))
mp.add_key_binding(nil, "reset",           reset_all)
