local mp = require 'mp'
local input_loaded, input = pcall(require, 'mp.input')

local skip_seconds = 10  -- default, until user sets one

-- ----------------------------------------------------------------
-- Convert a single "time spec" like 1h07m02 / 2m02 / 47s / 47
-- into seconds. Walks digit+unit segments left-to-right.
-- Units: h=hours, m=minutes, s=seconds, none=seconds.
-- ----------------------------------------------------------------
local function spec_to_seconds(spec)
    local total = 0
    local cursor = 1
    while cursor <= #spec do
        local num_str = spec:match("^(%d+)", cursor)
        if not num_str then break end
        cursor = cursor + #num_str
        local unit = spec:sub(cursor, cursor)
        local n = tonumber(num_str)
        if unit == "h" then
            total = total + n * 3600
            cursor = cursor + 1
        elseif unit == "m" then
            total = total + n * 60
            cursor = cursor + 1
        elseif unit == "s" then
            total = total + n
            cursor = cursor + 1
        else
            -- no unit = plain seconds
            total = total + n
        end
    end
    return total
end

-- ----------------------------------------------------------------
-- Convert every time-spec inside an arithmetic expression into
-- raw seconds, leaving operators / parens / spaces alone.
-- Example:  "01h07m02-1h06m02"  ->  "4022-3962"
-- ----------------------------------------------------------------
local function convert_time_specs(expr)
    local out = {}
    local i, len = 1, #expr
    while i <= len do
        local c = expr:sub(i, i)
        if c:match("%d") then
            -- read a full time-spec (digits + hms letters)
            local start = i
            while i <= len and expr:sub(i, i):match("[%dhms]") do
                i = i + 1
            end
            out[#out + 1] = tostring(spec_to_seconds(expr:sub(start, i - 1)))
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- ----------------------------------------------------------------
-- Parse user input:
--   "34"            -> 34         (plain number, sign allowed)
--   "-14"           -> -14
--   "=2m02-47"      -> 75         (smart mode: leading '=')
--   "=1h07m-1h06m"  -> 60
-- Returns (number|nil, error_message|nil)
-- ----------------------------------------------------------------
local function parse_input(text)
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, "empty" end

    -- Plain number?
    local plain = tonumber(text)
    if plain then return plain end

    -- Otherwise must start with '='
    if text:sub(1, 1) ~= "=" then
        return nil, "use a number, or '=' followed by an expression"
    end

    local converted = convert_time_specs(text:sub(2))

    -- Safety: only allow math chars in the final expression
    if not converted:match("^[%d%+%-%*%/%(%)%s%.]*$") then
        return nil, "invalid expression"
    end

    local fn, err = load("return " .. converted)
    if not fn then return nil, "parse error" end
    local ok, val = pcall(fn)
    if not ok or type(val) ~= "number" then return nil, "eval error" end
    return val
end

-- ----------------------------------------------------------------
-- Format seconds back into a human-readable label for the OSD
-- (used only for the confirmation message).
-- ----------------------------------------------------------------
local function format_seconds(n)
    local sign = n < 0 and "-" or ""
    local abs = math.abs(n)
    local h = math.floor(abs / 3600)
    local m = math.floor((abs % 3600) / 60)
    local s = abs - h * 3600 - m * 60
    if h > 0 then
        return string.format("%s%dh%02dm%02.0fs", sign, h, m, s)
    elseif m > 0 then
        return string.format("%s%dm%02.0fs", sign, m, s)
    else
        return string.format("%s%gs", sign, s)
    end
end

local function prompt_for_seconds()
    if not input_loaded then
        mp.osd_message("mp.input not available — needs mpv 0.38+", 3)
        return
    end
    input.get({
        prompt = "Skip step (current: " .. skip_seconds .. "s) — number or =expression:",
        default_text = tostring(skip_seconds),
        submit = function(text)
            local n, err = parse_input(text)
            if n then
                skip_seconds = n
                mp.osd_message("Skip step set to " .. format_seconds(n), 2)
            else
                mp.osd_message("Skip step: " .. (err or "invalid"), 3)
            end
            input.terminate()
        end,
    })
end

local function do_skip()
    mp.commandv("seek", tostring(skip_seconds), "relative+exact")
end

mp.add_key_binding(nil, "set-skip-step", prompt_for_seconds)
mp.add_key_binding(nil, "do-skip", do_skip)
