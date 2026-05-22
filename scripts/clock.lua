-- On-screen clock (HH:MM, 24h) in the bottom-right corner.
--
-- Two independent bindings, pick whichever you want in input.conf:
--   script-binding clock/flash   -> show for FLASH_DURATION seconds, auto-hide.
--                                   Pressing again while visible restarts timer.
--   script-binding clock/toggle  -> press to show indefinitely, press again to hide.
--                                   Auto-refreshes the time every TICK_INTERVAL sec.
--
-- You can even bind both to different keys if you want both behaviours.

local mp = require 'mp'

-- =====================================================
--  CONFIG
-- =====================================================
local FLASH_DURATION = 2    -- seconds (flash mode)
local TICK_INTERVAL  = 10   -- seconds between refreshes (toggle mode)
-- =====================================================

local overlay = mp.create_osd_overlay("ass-events")
overlay.res_x = 1920
overlay.res_y = 1080

local hide_timer = nil
local tick_timer = nil
local visible    = false

local function render()
    local now = os.date("%H:%M")
    overlay.data =
        "{\\an3}{\\pos(1900,1050)}" ..
        "{\\fnSource Sans Pro}{\\fs80}{\\b1}" ..
        "{\\bord3}{\\shad2}{\\blur0.8}" ..
        "{\\3c&H000000&}{\\4c&H000000&}{\\1c&HFFFFFF&}" ..
        now
    overlay:update()
end

local function kill(t)
    if t then t:kill() end
    return nil
end

local function hide()
    visible    = false
    hide_timer = kill(hide_timer)
    tick_timer = kill(tick_timer)
    overlay:remove()
end

-- Flash: show, schedule auto-hide. Cancels any active toggle session.
local function flash()
    visible    = true
    tick_timer = kill(tick_timer)
    render()
    hide_timer = kill(hide_timer)
    hide_timer = mp.add_timeout(FLASH_DURATION, hide)
end

-- Toggle: persistent show with periodic refresh, second press hides.
local function toggle()
    if visible then
        hide()
    else
        visible    = true
        hide_timer = kill(hide_timer)
        render()
        tick_timer = mp.add_periodic_timer(TICK_INTERVAL, render)
    end
end

mp.add_key_binding(nil, "flash",  flash)
mp.add_key_binding(nil, "toggle", toggle)
