local export = {}

package.path = package.path .. ";../?.lua"

-- dependencies
local utf8 = "lua-utf8"
local conlib = "conlib"

local concat = table.concat
local find = string.find
local gmatch = string.gmatch
local ipairs = ipairs
local lower = string.lower
local require = require

local function ugmatch(...)
    ugmatch = require(utf8).gmatch
    return ugmatch(...)
end

local function display(...)
    display = require(conlib).display_cli
    return display(...)
end

local function gsub(...)
    gsub = require(conlib).string.gsub
    return gsub(...)
end

local C = "mnŋptkqhʁTDsɬɮwlɾ"
local V = "aiueAIE=13ɨ"
local T = "mnŋptkqʁ"
local syllable = "_?[" .. C .. "]?[" .. V .. "][" .. T .. "]?"

local NSYL = "\204\175" -- nonsyllabic

local function encode(text)
    local ret = gsub(text, "tʃ", "T")
    ret = gsub(ret, "dʒ", "D")

    ret = gsub(ret, "ai" .. NSYL .. "?", "A")
    ret = gsub(ret, "iu" .. NSYL .. "?", "I")

    return ret
end

local function decode(text)
    local ret = gsub(text, "T", "tʃ")
    ret = gsub(ret, "D", "dʒ")
    ret = gsub(ret, "A", "ai" .. NSYL)
    ret = gsub(ret, "I", "iu" .. NSYL)

    return ret
end

-- This supports treating enclitic =ng as a separate syllable,
-- but you need to mark it as such with the =.
function export.stress(text)
    text = encode(text)
    text = text .. " " -- tack on an extra space so the final word doesn't get ignored
    -- stupid but works

    local syllables = {}
    local i = 1

    for v in gmatch(text, "([^ ]+) ") do
        syllables[i] = { v }
        i = i + 1
    end

    for k, word in ipairs(syllables) do
        local n = 1
        for v in ugmatch(word[1], syllable) do
            syllables[k][n] = v
            n = n + 1
        end
    end

    for _, v in ipairs(syllables) do
        local len = #v

        for n, syl in ipairs(v) do
            syl = decode(syl)

            if find(syl, "_") then
                v[n] = gsub(syl, "_", "ˈ")
                if n == len then
                    v[n - 1] = gsub(v[n - 1], "ˈ", "")
                end
                break
            elseif n == len - 1 then
                v[n] = "ˈ" .. syl
            end
        end
    end

    return syllables
end

function export.phonemic(text)
    text = lower(text)
    text = gsub(text, "ng", "ŋ")
    text = gsub(text, "ch", "tʃ")
    text = gsub(text, "ll", "ɬ")
    text = gsub(text, "lz", "ɮ")
    text = gsub(text, "h%f[%A]", "ʁ")
    text = gsub(text, "r", "ʁ")
    text = gsub(text, "j", "dʒ")
    text = gsub(text, "[.?]$", "")
    text = gsub(text, "[¿¡]", "")
    text = gsub(text, "[,%-]", " |")
    text = gsub(text, "[;:.?]", " ||")
    text = gsub(text, "o", "u")
    text = gsub(text, "4", "ɾ")

    local syllables = export.stress(text)

    for k, word in ipairs(syllables) do
        local len = #word
        for n, v in ipairs(word) do
            if find(v, "^ˈ[^e]*e") or (v ~= "e" and n == len and len == 1) then
                word[n] = gsub(v, "e", "æ")
            end
        end

        word = concat(word)

        -- Override default pronunciation for e with 1/3:
        -- 1 outputs ɨ, 3 outputs æ.
        word = gsub(word, "e", "ɨ")
        word = gsub(word, "1", "ɨ")
        word = gsub(word, "3", "æ")
        word = gsub(word, "=", "")

        word = decode(word)
        syllables[k] = word
    end

    return syllables
end

function export.phonetic(syllables)
    local ret = {}

    for k, v in ipairs(syllables) do
        v = gsub(v, "^ŋ", "")
        v = gsub(v, "iu" .. NSYL, "jo")
        v = gsub(v, "ʁ", "(h)")
        v = gsub(v, "[ptkq]$", "ˀ")

        -- escape stressed /ɨ/
        v = gsub(v, "(ˈ[" .. C .. "]?)ɨ([" .. T .. "]?)", "%11%2")

        v = gsub(v, "^([" .. C .. "]?)[aæ]([" .. T .. "]?)$", "%1ə%2")

        v = gsub(v, "ɨ", "ə")
        v = gsub(v, "(ˈ" .. syllable .. ".-)a", "%1ə")
        v = gsub(v, "1", "ɨ")

        v = gsub(v, "sə(ˈ?)([ptk])", "%1s%2")
        v = gsub(v, "([ptk])ə(ˈ?)ɾ", "%2%1ɾ")

        ret[k] = v
    end

    return ret
end

local input = "Jaksun kai siah - o4ma - tari_puni - qai saru churiukeng ngahum rawem ngu. Ne, ngu ngahum ara? In ngahumeng? - miukeng waqi? - miukeng wiuchi? Sun ngu meteng ngahum ara? Ku kuti saru pemeng!"
display(input, export.phonemic, export.phonetic)

return export
