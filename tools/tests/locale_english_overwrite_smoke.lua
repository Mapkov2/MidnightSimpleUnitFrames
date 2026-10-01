-- A translated language pack must never turn a key it already translated back
-- into English (review F15: a late block of English Swing Timer lines reset
-- None, Always, Width, Center, Font size, Outline, Border thickness, Display
-- mode and the textures in nine packs). Each pack runs with a logging L, so
-- assignments copied in from its MSUF2_* tables count in their real order.
-- Usage: lua tools/tests/locale_english_overwrite_smoke.lua <repoRoot>
local repo = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local PACKS = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
-- A later English line is right here: the word is the same in the language,
-- the text is a credit, or the key is an internal identifier.
local ALLOWED = {
    deDE = { Performance = "German uses the English word" },
    esES = { General = "same word in Spanish" },
    esMX = { General = "same word in Spanish" },
    frFR = { Pixel = "same word in French", Position = "same word in French" },
    zhCN = { ["by Mapko"] = "author credit stays English", gf_raid = "internal identifier",
        gf_mythicraid = "internal identifier", MSUF_UpdateAllFonts = "internal identifier" },
    zhTW = { ["by Mapko"] = "author credit stays English", gf_raid = "internal identifier",
        gf_mythicraid = "internal identifier", MSUF_UpdateAllFonts = "internal identifier" },
}
local failures, unused = {}, {}
for _, pack in ipairs(PACKS) do
    for key in pairs(ALLOWED[pack] or {}) do unused[pack .. ":" .. key] = true end
    local store, history = {}, {}
    local L = setmetatable({}, {
        __index = store,
        __newindex = function(_, key, value)
            local line = debug.getinfo(2, "l").currentline
            local list = history[key]
            if not list then list = {}; history[key] = list end
            list[#list + 1] = { line = line, value = value }
            store[key] = value
        end,
    })
    local namespace = { L = L, LOCALE = pack }
    namespace.RegisterLocale = function() return L end
    namespace.RegisterLocaleLoader = function(_, loader) loader() end
    local previousNS, previousMSUF = _G.MSUF_NS, _G.MSUF
    _G.MSUF_NS, _G.MSUF = namespace, namespace
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Locales/" .. pack .. ".lua"))("MidnightSimpleUnitFrames", namespace)
    _G.MSUF_NS, _G.MSUF = previousNS, previousMSUF
    for key, list in pairs(history) do
        local final = list[#list]
        if type(key) == "string" and final.value == key then
            for i = 1, #list - 1 do
                if list[i].value ~= key then
                    if ALLOWED[pack] and ALLOWED[pack][key] then
                        unused[pack .. ":" .. key] = nil
                    else
                        failures[#failures + 1] = string.format("%s.lua:%d turns %q back into English (translated at line %d)",
                            pack, final.line, key, list[i].line)
                    end
                    break
                end
            end
        end
    end
end
for entry in pairs(unused) do failures[#failures + 1] = "allow-list entry no longer needed: " .. entry end
table.sort(failures)
if #failures > 0 then error("locale_english_overwrite_smoke:\n  " .. table.concat(failures, "\n  "), 0) end
print("locale_english_overwrite_smoke: OK (" .. #PACKS .. " translated packs)")
