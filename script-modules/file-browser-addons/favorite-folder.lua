--[[
    favorite-folder.lua
    Addon for mpv-file-browser.

    Press `f` while the file-browser is open to jump straight to your
    favorite folder. Change the FAVORITE constant below to point at
    whichever directory you want as your "home".

    Workflow:
      1. Launch mpv with nothing playing.
      2. Press `e` (your binding for file_browser/open-browser).
      3. Press `f` -> instantly inside O:/Anime/.

    Note: the keybind only fires while the browser is open. Outside
    the browser, `f` keeps its normal "cycle fullscreen" mpv behaviour.
]]

local mp = require 'mp'
local fb = require 'file-browser'

-- ====== EDIT THIS to point to your favorite folder ======
-- Trailing slash required. Forward slashes work on Windows too.
local FAVORITE = "O:/Anime/"
-- ========================================================

local function jump_to_favorite()
    fb.browse_directory(FAVORITE)
end

---@type ParserConfig
return {
    api_version = '1.8.0',
    priority = 100,
    keybinds = {
        { "f", "jump", jump_to_favorite, {} },
    },
}
