-- Smart "previous": near start of file -> go to previous playlist entry,
-- otherwise -> seek to start of current file.
local THRESHOLD = 5  -- seconds

mp.add_key_binding(nil, "smart-prev", function()
    local pos = mp.get_property_number("time-pos", 0)
    if pos > THRESHOLD then
        mp.commandv("seek", 0, "absolute")
    else
        mp.commandv("playlist-prev")
    end
end)