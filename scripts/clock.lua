-- Toggle a small on-screen clock (HH:MM, 24h) in the top-right corner.
-- Press the bound key once to show, again to hide.
-- Time auto-refreshes every 10 seconds, so the minute change is visible
-- within ~10s without spamming the OSD.

local mp = require 'mp'

local overlay = mp.create_osd_overlay("ass-events")
overlay.res_x = 1920
overlay.res_y = 1080
local timer = nil
local visible = false

local function render()
    if not visible then return end
    local now = os.date("%H:%M")
    overlay.data =
        "{\\an3}{\\pos(1900,1050)}" ..
        "{\\fnSource Sans Pro}{\\fs80}{\\b1}" ..
        "{\\bord3}{\\shad2}{\\blur0.8}" ..
        "{\\3c&H000000&}{\\4c&H000000&}{\\1c&HFFFFFF&}" ..
        now
    overlay:update()
end

local function show()
    visible = true
    render()
    if timer then timer:kill() end
    timer = mp.add_periodic_timer(10, render)
end

local function hide()
    visible = false
    overlay:remove()
    if timer then
        timer:kill()
        timer = nil
    end
end

local function toggle()
    if visible then hide() else show() end
end

mp.add_key_binding(nil, "toggle", toggle)
