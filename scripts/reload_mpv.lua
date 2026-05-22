-- Reload mpv: saves current position, relaunches mpv with the same file,
-- then quits the current instance. The new instance resumes from where
-- you were thanks to save-position-on-quit / watch-later.
--
-- Caveats:
--   * Requires mpv.exe to be in your Windows PATH (shinchiro builds do this).
--   * Only the current file is passed to the new instance — playlist context
--     is lost. Watch-later position is preserved.
--   * If no file is loaded, the script bails out so you don't accidentally
--     kill an idle mpv with no recovery.

local mp = require 'mp'

mp.add_key_binding(nil, "reload", function()
    local path = mp.get_property("path")
    if not path or path == "" then
        mp.osd_message("Reload: no file loaded", 2)
        return
    end

    -- 1. Save current position so the new instance resumes here.
    mp.command("write-watch-later-config")

    -- 2. Detached relaunch of mpv with the current file.
    --    `cmd /c start "" mpv "<path>"` is the safest Windows incantation:
    --    `start` immediately returns, and `""` is the (required, empty) title.
    --    Detach + playback_only=false make sure the child process is
    --    independent of our soon-to-quit process.
    local ok, err = pcall(function()
        mp.command_native({
            name = "subprocess",
            args = { "cmd", "/c", "start", "", "mpv", path },
            detach = true,
            playback_only = false,
        })
    end)

    if not ok then
        mp.osd_message("Reload failed: " .. tostring(err), 3)
        return
    end

    -- 3. Quit current instance. The new one takes over.
    mp.command("quit")
end)
