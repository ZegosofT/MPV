-- [[
--    zego_update.lua
--    Checks YOUR config repo (github.com/ZegosofT/MPV) for a newer version
--    and lets you pull the update via git. Broadcasts an "update available"
--    flag that the uosc menu reads to show an indicator.
--
--    Versioning: script-opts/zego_version.conf holds your local version.
--    Bump it before each `git push` so other installs detect the update.
-- ]]

local mp    = require 'mp'
local utils = require 'mp.utils'
local msg   = require 'mp.msg'
local opts  = require 'mp.options'

-- ====== CONFIG (edit if you fork/rename the repo) ======
local REPO_RAW = "https://raw.githubusercontent.com/ZegosofT/MPV/main/script-opts/zego_version.conf"
-- =======================================================

local cfg = { version = "0.0" }
opts.read_options(cfg, "zego_version")
local LOCAL_VERSION = cfg.version

local remote_version  = nil
local update_available = false

-- Compare dotted numeric versions (1.0 < 1.1 < 2.0 ; 2026.05.30 < 2026.05.31)
local function ver_list(v)
    local t = {}
    for n in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end
local function is_newer(remote, loc)
    local r, l = ver_list(remote), ver_list(loc)
    for i = 1, math.max(#r, #l) do
        local a, b = r[i] or 0, l[i] or 0
        if a > b then return true elseif a < b then return false end
    end
    return false
end

local function broadcast()
    mp.commandv("script-message", "anime-state-broadcast", utils.format_json({
        zego_update_available = update_available,
        zego_remote_version   = remote_version or "",
        zego_local_version    = LOCAL_VERSION,
    }))
end

-- ----------------------------------------------------------------
-- Check GitHub for a newer version
-- ----------------------------------------------------------------
local function check(user_initiated)
    if user_initiated then mp.osd_message("Checking config updates…", 2) end

    local args
    if mp.get_property("platform") == "windows" then
        args = { "powershell", "-NoProfile", "-Command",
                 "(Invoke-WebRequest -Uri '" .. REPO_RAW .. "' -UseBasicParsing).Content" }
    else
        args = { "curl", "-s", REPO_RAW }
    end

    local res = utils.subprocess({ args = args, cancellable = false, capture_stdout = true })
    if res.status ~= 0 or not res.stdout or res.stdout == "" then
        if user_initiated then mp.osd_message("Update check failed (no internet?)", 3) end
        return
    end

    remote_version = res.stdout:match("version%s*=%s*([%w%.%-]+)")
    if not remote_version then
        if user_initiated then mp.osd_message("Could not read remote version", 3) end
        return
    end

    update_available = is_newer(remote_version, LOCAL_VERSION)
    broadcast()

    if update_available then
        mp.osd_message("Zego Config update available: " .. remote_version ..
                       "  (you have " .. LOCAL_VERSION .. ")", 5)
    elseif user_initiated then
        mp.osd_message("Zego Config up to date (" .. LOCAL_VERSION .. ")", 3)
    end
end

-- ----------------------------------------------------------------
-- Pull the update (git fast-forward only — never clobbers local work)
-- ----------------------------------------------------------------
local function pull()
    local dir = mp.command_native({ "expand-path", "~~/" })
    mp.osd_message("Updating config from GitHub…", 3)

    local res = utils.subprocess({
        args = { "git", "-C", dir, "pull", "--ff-only" },
        cancellable = false, capture_stdout = true, capture_stderr = true,
        playback_only = false,
    })

    if res.status == 0 then
        local out = (res.stdout or ""):gsub("%s+$", "")
        if out:find("Already up to date") or out:find("up%-to%-date") then
            mp.osd_message("Config already up to date.", 4)
        else
            update_available = false
            broadcast()
            mp.osd_message("Config updated! Press Ctrl+R (or restart) to apply.", 6)
        end
    else
        mp.osd_message("Update failed — see console (²). Local changes may block it.", 6)
        if res.stderr then msg.error(res.stderr) end
        if res.stdout then msg.info(res.stdout) end
    end
end

-- ----------------------------------------------------------------
-- Bindings + startup check
-- ----------------------------------------------------------------
mp.add_key_binding(nil, "check", function() check(true) end)
mp.add_key_binding(nil, "pull",  pull)
mp.register_script_message("zego-check", function() check(true) end)
mp.register_script_message("zego-pull",  pull)

-- Check once shortly after launch.
mp.add_timeout(3, function() check(false) end)
