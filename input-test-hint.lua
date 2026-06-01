-- Persistent centered "how to close" hint for the Binds Input Test window.
-- Loaded ONLY by the input-test launch command (--script=...), never auto-loaded
-- (it lives outside the scripts/ folder).

local mp = require 'mp'

local ov = mp.create_osd_overlay("ass-events")
ov.res_x = 1920
ov.res_y = 1080

local function draw()
    ov.data =
        "{\\an8}{\\pos(960,775)}" ..
        "{\\fnSource Sans Pro}{\\b1}{\\bord3}{\\shad2}{\\blur1}{\\3c&H000000&}{\\4c&H000000&}" ..
        -- What this window is for (read-fast explanation)
        "{\\fs40}{\\1c&HFFFFFF&}Input Test  -  press any key, mouse button or shortcut to see what it's bound to in mpv\\N" ..
        -- How to leave
        "{\\fs40}{\\1c&HFFFFFF&}Press  ALT+F4  to close this window"
    ov:update()
end

draw()
-- Re-assert periodically so it stays on top of the idle indicator.
mp.add_periodic_timer(1, draw)
