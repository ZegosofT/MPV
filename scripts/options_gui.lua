-- [[
--    options_gui.lua
--    Opens the desktop Options / Keybinds editor (tools/options/app.py) in its
--    own native window, launched WITHOUT a console window and detached so it
--    neither blocks mpv nor closes with it.
--
--    A self-contained Python runtime is bundled in tools/options/runtime, so the
--    window works out of the box with NO Python install and NO dependencies.
--    If that folder is missing (e.g. someone cloned only the source), it falls
--    back to the system windowless launcher `pyw`.
--
--    Trigger:
--      * uosc right-click menu -> Options
--      * or bind a key to  script-binding options_gui/open  in input.conf
-- ]]

local mp = require 'mp'
local utils = require 'mp.utils'

local APP = mp.command_native({ "expand-path", "~~/tools/options/app.py" })
local PYW = mp.command_native({ "expand-path", "~~/tools/options/runtime/pythonw.exe" })

local function exists(path)
    return path ~= nil and utils.file_info(path) ~= nil
end

local function open_options()
    if exists(PYW) then
        -- Bundled, self-contained Python (windowless): no install needed.
        mp.commandv("run", PYW, APP)
    else
        -- Source-only fallback: system windowless Python launcher.
        mp.commandv("run", "pyw", APP)
    end
    mp.osd_message("Opening Options…", 1)
end

mp.add_key_binding(nil, "open", open_options)
mp.register_script_message("open-options", open_options)
