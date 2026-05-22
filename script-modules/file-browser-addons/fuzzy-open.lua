--[[
    fuzzy-open.lua
    Addon for mpv-file-browser.

    Press Alt+o while the browser is open, type any part of a folder
    name, and the browser list is FILTERED to show only items whose
    name contains that substring (case-insensitive).
    Pick whichever match you want with the arrow keys and press
    Enter / Right to open it.

    The filter clears as soon as you navigate into a folder, navigate
    up, or trigger a rescan (Ctrl+R) — there's nothing persistent to
    clean up.
]]

local mp = require 'mp'
local msg = require 'mp.msg'
local fb  = require 'file-browser'
local g   = require 'modules.globals'
local input_loaded, input = pcall(require, 'mp.input')

---@type ParserConfig
local fuzzy = {
    api_version = '1.8.0',
    priority = 100,
}

---@async
local function fuzzy_open(_, state, co)
    if not input_loaded then
        mp.osd_message("Fuzzy open requires mpv 0.38+ (mp.input)", 2)
        return
    end
    if not state.list then return end

    input.get({
        prompt = "Filter folder list by:\n>",
        id = "file-browser/fuzzy-open",
        submit = fb.coroutine.callback(),
    })

    local query = coroutine.yield()
    input.terminate()
    if not query or query == "" then return end

    local q = query:lower()

    -- Filter the live list down to matching entries
    local filtered = {}
    for _, item in ipairs(g.state.list) do
        local name = (item.label or item.name or ""):lower()
        if name:find(q, 1, true) then
            table.insert(filtered, item)
        end
    end

    if #filtered == 0 then
        mp.osd_message("No match for '" .. query .. "'", 2)
        return
    end

    -- Apply the filter
    g.state.list = filtered
    fb.set_selected_index(1)
    fb.redraw()

    mp.osd_message(
        ("Filtered: %d match%s — navigate to clear")
            :format(#filtered, #filtered == 1 and "" or "es"),
        2
    )
end

fuzzy.keybinds = {
    { "Alt+o", "open", fuzzy_open, {} },
}

return fuzzy
