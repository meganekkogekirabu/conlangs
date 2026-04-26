---@diagnostic disable: cast-local-type, unbalanced-assignments
local cd = {}

-- Most of the code in this file is adapted from 'Module:string utilities'
-- on the English Wiktionary, licensed under CC BY-SA 4.0. The original
-- code can be found here:
-- https://en.wiktionary.org/wiki/Module:string_utilities

-- dependencies
local ansicolors = "ansicolors"
local utf8 = "lua-utf8"

local byte = string.byte
local char = string.char
local concat = table.concat
local gsub = string.gsub
local match = string.match
local pairs = pairs
local print = print
local require = require
local sort = table.sort
local sub = string.sub
local tonumber = tonumber
local tostring = tostring
local type = type

local function ugsub(...)
    ugsub = require(utf8).gsub
    return ugsub(...)
end

local function colors(...)
    colors = require(ansicolors)
    return colors(...)
end

function cd.dump_object(t, depth)
    if not depth then
        depth = 0
    end

    local str = ""

    local function get_tabulation(d)
        local s = ""
        for i = 1, d do
            s = s .. "\t"
        end

        return s
    end

    if type(t) == "table" then
        local n = 0

        str = str .. "{\n"

        for k, v in pairs(t) do
            n = n + 1
            str = str ..
                get_tabulation(depth + 1) ..
                "[" .. (tonumber(k) and k or string.format('"%s"', k)) .. "] = " .. cd.dump_object(v, depth + 1) .. "\n"
        end

        str = str .. get_tabulation(depth) .. "},\n"

        if n > 0 then
            return str
        end

        return "{},"
    elseif type(t) == "string" then
        return '"' .. tostring(t) .. '",'
    else
        return tostring(t) .. ","
    end
end

function cd.log_object(t)
    print(cd.dump_object(t))
end

function cd.display_cli(input, phonemic, phonetic)
    local pn = phonemic(input)
    local ph = phonetic(pn)

    ph = concat(ph, " ")
    pn = concat(pn, " ")

    pn = colors("%{blue}phonemic:%{reset}") .. " /" .. pn .. "/"
    ph = colors("%{red}phonetic:%{reset}") .. " [" .. ph .. "]"

    print("input:    " .. input)
    print(pn)
    print(ph)
end

function cd.benchmark(func, ...)
    local start = os.clock()

    for _ = 1, 10000 do
        func(...)
    end

    return os.clock() - start
end

cd.string = {}

local character_classes
local function get_character_classes()
    character_classes, get_character_classes = {
        [0x41] = true,
        [0x61] = true, -- Aa
        [0x43] = true,
        [0x63] = true, -- Cc
        [0x44] = true,
        [0x64] = true, -- Dd
        [0x4C] = true,
        [0x6C] = true, -- Ll
        [0x50] = true,
        [0x70] = true, -- Pp
        [0x53] = true,
        [0x73] = true, -- Ss
        [0x55] = true,
        [0x75] = true, -- Uu
        [0x57] = true,
        [0x77] = true, -- Ww
        [0x58] = true,
        [0x78] = true, -- Xx
        [0x5A] = true, -- z dealt with separately.
    }, nil
    return character_classes
end

local function parse_1_byte_charset(pattern, pos)
    local ch
    while true do
        pos, ch = match(pattern, "()([%%%]\192-\255])", pos)
        if ch == "%" then
            local nxt = byte(pattern, pos + 1)
            if not nxt or nxt >= 128 or (character_classes or get_character_classes())[nxt] then -- acdlpsuwxACDLPSUWXZ, but not z
                return false
            end
            pos = pos + 2
        elseif ch == "]" then
            pos = pos + 1
            return pos
        else
            return false
        end
    end
end

local function check_sets_equal(set1, set2)
    local k2
    for k1, v1 in next, set1 do
        local v2 = set2[k1]
        if v1 ~= v2 and (v2 == nil or not check_sets_equal(v1, v2)) then
            return false
        end
        k2 = next(set2, k2)
    end
    return next(set2, k2) == nil
end

local function check_sets(bytes)
    local key, set1, set = next(bytes)
    if set1 == true then
        return true
    elseif not check_sets(set1) then
        return false
    end
    while true do
        key, set = next(bytes, key)
        if not key then
            return true
        elseif not check_sets_equal(set, set1) then
            return false
        end
    end
end

local function make_charset(range)
    if #range == 1 then
        return char(range[1])
    end
    sort(range)
    local compressed, n, start = {}, 0, range[1]
    for i = 1, #range do
        local this, nxt = range[i], range[i + 1]
        if nxt ~= this + 1 then
            n = n + 1
            compressed[n] = this == start and char(this) or
                char(start) .. "-" .. char(this)
            start = nxt
        end
    end
    return "[" .. concat(compressed) .. "]"
end


local function pattern_simplifier(pattern)
    if type(pattern) == "number" then
        return tostring(pattern)
    end
    ---@diagnostic disable-next-line: unbalanced-assignments
    local pos, capture_groups, start, n, output, ch, nxt_pos = 1, 0, 1, 0
    while true do
        -- FIXME: use "()([%%(.[\128-\255])[\128-\191]?[\128-\191]?[\128-\191]?()" and ensure non-UTF8 always fails.
        pos, ch, nxt_pos = match(pattern, "()([%%(.[\192-\255])[\128-\191]*()", pos)
        if not ch then
            break
        end
        local nxt = byte(pattern, nxt_pos)
        if ch == "%" then
            if nxt == 0x62 then -- b
                local nxt2, nxt3 = byte(pattern, pos + 2, pos + 3)
                if not (nxt2 and nxt2 < 128 and nxt3 and nxt3 < 128) then
                    return false
                end
                pos = pos + 4
            elseif nxt == 0x66 then -- f
                nxt_pos = nxt_pos + 2
                local nxt2, nxt3 = byte(pattern, nxt_pos - 1, nxt_pos)
                -- Only possible to convert a positive %f charset which is
                -- all ASCII, so use parse_1_byte_charset.
                if not (nxt2 == 0x5B and nxt3 and nxt3 ~= 0x5E and nxt3 < 128) then -- [^
                    return false
                elseif nxt3 == 0x5D then                                            -- Initial ] is non-magic.
                    nxt_pos = nxt_pos + 1
                end
                pos = parse_1_byte_charset(pattern, nxt_pos)
                if not pos then
                    return false
                end
            elseif nxt == 0x5A then                -- Z
                nxt = byte(pattern, nxt_pos + 1)
                if nxt == 0x2A or nxt == 0x2D then -- *-
                    pos = pos + 3
                else
                    if output == nil then
                        output = {}
                    end
                    local ins = sub(pattern, start, pos - 1) .. "[\1-\127\192-\255]"
                    n = n + 1
                    if nxt == 0x2B then -- +
                        output[n] = ins .. "%Z*"
                        pos = pos + 3
                    elseif nxt == 0x3F then -- ?
                        output[n] = ins .. "?[\128-\191]*"
                        pos = pos + 3
                    else
                        output[n] = ins .. "[\128-\191]*"
                        pos = pos + 2
                    end
                    start = pos
                end
            elseif not nxt or (character_classes or get_character_classes())[nxt] then -- acdlpsuwxACDLPSUWX, but not Zz
                return false
                -- Skip the next character if it's ASCII. Otherwise, we will
                -- still need to do length checks.
            else
                pos = pos + (nxt < 128 and 2 or 1)
            end
        elseif ch == "(" then
            if nxt == 0x29 or capture_groups == 32 then -- )
                return false
            end
            capture_groups = capture_groups + 1
            pos = pos + 1
        elseif ch == "." then
            if nxt == 0x2A or nxt == 0x2D then -- *-
                pos = pos + 2
            else
                if output == nil then
                    output = {}
                end
                local ins = sub(pattern, start, pos - 1) .. "[^\128-\191]"
                n = n + 1
                if nxt == 0x2B then -- +
                    output[n] = ins .. ".*"
                    pos = pos + 2
                elseif nxt == 0x3F then -- ?
                    output[n] = ins .. "?[\128-\191]*"
                    pos = pos + 2
                else
                    output[n] = ins .. "[\128-\191]*"
                    pos = pos + 1
                end
                start = pos
            end
        elseif ch == "[" then
            -- Fail negative charsets. TODO: 1-byte charsets should be safe.
            if nxt == 0x5E then -- ^
                return false
                -- If the first character is "%", ch_len is determined by the
                -- next one instead.
            elseif nxt == 0x25 then -- %
                nxt = byte(pattern, nxt_pos + 1)
            elseif nxt == 0x5D then -- Initial ] is non-magic.
                nxt_pos = nxt_pos + 1
            end
            if not nxt then
                return false
            end
            local ch_len = nxt < 128 and 1 or nxt < 224 and 2 or nxt < 240 and 3 or 4
            if ch_len == 1 then -- Single-byte charset.
                pos = parse_1_byte_charset(pattern, nxt_pos)
                if not pos then
                    return false
                end
            else -- Multibyte charset.
                -- TODO: 1-byte chars should be safe to mix with multibyte chars. CONFIRM THIS FIRST.
                local charset_pos, bytes = pos
                pos = pos + 1
                while true do -- TODO: non-ASCII charset ranges.
                    pos, ch, nxt_pos = match(pattern, "^()([^\128-\191])[\128-\191]*()", pos)
                    -- If escaped, get the next character. No need to
                    -- distinguish magic characters or character classes,
                    -- as they'll all fail for having the wrong length
                    -- anyway.
                    if ch == "%" then
                        pos, ch, nxt_pos = match(pattern, "^()([^\128-\191])[\128-\191]*()", nxt_pos)
                    elseif ch == "]" then
                        pos = nxt_pos
                        break
                    end
                    if not (ch and nxt_pos - pos == ch_len) then
                        return false
                    elseif bytes == nil then
                        bytes = {}
                    end
                    local bytes, last = bytes, nxt_pos - 1
                    for i = pos, last - 1 do
                        local b = byte(pattern, i)
                        local bytes_b = bytes[b]
                        if bytes_b == nil then
                            bytes_b = {}
                            bytes[b] = bytes_b
                        end
                        bytes[b], bytes = bytes_b, bytes_b
                    end
                    bytes[byte(pattern, last)] = true
                    pos = nxt_pos
                end
                if not pos then
                    return false
                end
                nxt = byte(pattern, pos)
                if (
                        (nxt == 0x2A or nxt == 0x2D or nxt == 0x3F) or -- *-?
                        (nxt == 0x2B and ch_len > 2) or                -- +
                        not check_sets(bytes)
                    ) then
                    return false
                end
                local ranges, b, key, next_byte = {}, 0
                repeat
                    key, next_byte = next(bytes)
                    local range, n = { key }, 1
                    -- Loop starts on the second iteration.
                    for key in next, bytes, key do
                        n = n + 1
                        range[n] = key
                    end
                    b = b + 1
                    ranges[b] = range
                    bytes = next_byte
                until next_byte == true
                if nxt == 0x2B then -- +
                    local range1, range2 = ranges[1], ranges[2]
                    ranges[1], ranges[3] = make_charset(range1), make_charset(range2)
                    local n = #range2
                    for i = 1, #range1 do
                        n = n + 1
                        range2[n] = range1[i]
                    end
                    ranges[2] = make_charset(range2) .. "*"
                    pos = pos + 1
                else
                    for i = 1, #ranges do
                        ranges[i] = make_charset(ranges[i])
                    end
                end
                if output == nil then
                    output = {}
                end
                nxt = byte(pattern, pos)
                n = n + 1
                output[n] = sub(pattern, start, charset_pos - 1) .. concat(ranges) ..
                    ((nxt == 0x2A or nxt == 0x2B or nxt == 0x2D or nxt == 0x3F) and "%" or "") -- following *+-? now have to be escaped
                start = pos
            end
        elseif not nxt then
            break
        elseif nxt == 0x2B then -- +
            if nxt_pos - pos ~= 2 then
                return false
            elseif output == nil then
                output = {}
            end
            pos, nxt_pos = pos + 1, nxt_pos + 1
            nxt = byte(pattern, nxt_pos)
            local ch2 = sub(pattern, pos, pos)
            n = n + 1
            output[n] = sub(pattern, start, pos - 1) .. "[" .. ch .. ch2 .. "]*" .. ch2 ..
                ((nxt == 0x2A or nxt == 0x2B or nxt == 0x2D or nxt == 0x3F) and "%" or "") -- following *+-? now have to be escaped
            pos, start = nxt_pos, nxt_pos
        elseif nxt == 0x2A or nxt == 0x2D or nxt == 0x3F then                              -- *-?
            return false
        else
            pos = nxt_pos
        end
    end
    if start == 1 then
        return pattern
    end
    return concat(output) .. sub(pattern, start)
end

function cd.string.gsub(str, pattern, repl, n)
    local simple = pattern_simplifier(pattern)
    if simple then
        return gsub(str, simple, repl, n)
    end
    return ugsub(str, pattern, repl, n)
end

return cd
