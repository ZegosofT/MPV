-- Reload mpv: save position, relaunch the SAME mpv binary with the current
-- file, then quit. The new instance resumes via save-position-on-quit.
--
-- Finds mpv.exe through the "App Paths" registry key that mpv-install.bat
-- creates (HKLM\...\App Paths\mpv.exe). This works no matter where mpv is
-- installed and without mpv being on PATH. Falls back to ShellExecute/PATH
-- ("mpv.exe") if the key is missing.

local mp = require 'mp'

local mpv_exe = nil  -- cached after first probe

local function find_mpv_exe()
    if mpv_exe ~= nil then return mpv_exe end
    mpv_exe = false
    local res = mp.command_native({
        name = "subprocess",
        args = { "reg", "query",
            "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\mpv.exe", "/ve" },
        capture_stdout = true,
        playback_only = false,
    })
    if res and res.stdout then
        -- Line looks like:  (Default)    REG_SZ    C:\path\to\mpv.exe
        local p = res.stdout:match("REG_SZ%s+([^\r\n]+)")
        if p then
            p = p:gsub("%s+$", "")
            if p ~= "" then mpv_exe = p end
        end
    end
    return mpv_exe
end

mp.add_key_binding(nil, "reload", function()
    local path = mp.get_property("path")
    if not path or path == "" then
        mp.osd_message("Reload: no file loaded", 2)
        return
    end

    local exe = find_mpv_exe()

    -- Save current position so the new instance resumes here.
    mp.command("write-watch-later-config")

    -- Relaunch detached so it survives our quit.
    --  * If we found the exact path: launch it directly (no PATH, no cmd window).
    --  * Else: route through ShellExecute via `start "" "mpv.exe"`, which also
    --    consults App Paths / PATH.
    local args
    if exe then
        args = { exe, path }
    else
        args = { "cmd", "/c", "start", "", "mpv.exe", path }
    end

    local ok, err = pcall(function()
        mp.command_native({
            name = "subprocess",
            args = args,
            detach = true,
            playback_only = false,
        })
    end)

    if not ok then
        mp.osd_message("Reload failed: " .. tostring(err), 3)
        return
    end

    -- Quit current instance. The new one takes over.
    mp.command("quit")
end)

-- Launch a fresh mpv in --input-test mode (used by the "Binds Input Test" menu).
-- Uses the App Paths mpv.exe so it works without PATH; args passed as an array
-- so spaces in --title / --script are preserved.
mp.add_key_binding(nil, "input-test", function()
    local exe  = find_mpv_exe()
    local hint = mp.command_native({ "expand-path", "~~/input-test-hint.lua" })
    local args
    if exe then
        args = { exe, "--input-test", "--force-window=yes", "--idle=yes",
                 "--title=Binds Input Test", "--script=" .. hint }
    else
        args = { "cmd", "/c", "start", "", "mpv.exe", "--input-test",
                 "--force-window=yes", "--idle=yes",
                 "--title=Binds Input Test", "--script=" .. hint }
    end
    mp.command_native({ name = "subprocess", args = args, detach = true, playback_only = false })
end)
