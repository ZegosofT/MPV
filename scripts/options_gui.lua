-- [[
--    options_gui.lua
--    Opens the desktop Options / Keybinds editor (tools/options/app.py) in its
--    own native window, launched WITHOUT a console window (via pyw.exe, the
--    windowless Python launcher) and detached so it neither blocks mpv nor
--    closes with it.
--
--    Trigger:
--      * uosc menu -> Binds -> Keybinds Editor
--      * or bind a key to  script-binding options_gui/open  in input.conf
--
--    First-time setup: run tools/options/launch.bat ONCE so it installs the
--    pywebview dependency (that step wants a visible console). After that this
--    windowless launch works.
-- ]]

local mp = require 'mp'

local APP = mp.command_native({ "expand-path", "~~/tools/options/app.py" })

local function open_options()
    -- `run` launches detached; `pyw` (C:\Windows\pyw.exe) is the windowless
    -- Python launcher, so no command prompt appears.
    mp.commandv("run", "pyw", APP)
    mp.osd_message("Opening Options…", 1)
end

mp.add_key_binding(nil, "open", open_options)
mp.register_script_message("open-options", open_options)
